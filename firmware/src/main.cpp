#include <Arduino.h>
#include <DHT.h>
#include <Wire.h>
#include <esp_system.h>

#include <atomic>
#include <cstdio>
#include <optional>
#include <string>

#include "smart_safety/ArduinoAdapters.h"
#include "smart_safety/DHT22Sensor.h"
#include "smart_safety/DisabledHardware.h"
#include "smart_safety/EventIdGenerator.h"
#include "smart_safety/FallFeatures.h"
#include "smart_safety/FirmwareConfig.h"
#include "smart_safety/MQ7AnalogSensor.h"
#include "smart_safety/MotionPipeline.h"
#include "smart_safety/MpuSensor.h"
#include "smart_safety/NonBlockingScheduler.h"
#include "smart_safety/SecureIngestionClient.h"
#include "smart_safety/SensorManager.h"
#include "smart_safety/TelemetryBuilder.h"

#ifndef SMART_SAFETY_PROVISIONER_BUILD
#define SMART_SAFETY_PROVISIONER_BUILD 0
#endif

#if !SMART_SAFETY_PROVISIONER_BUILD

namespace {

using namespace smart_safety;

static_assert(config::kMpuIntervalMs == kFallSamplePeriodMs,
              "MPU sampling must match the 50 Hz fall model contract");

DHT dht(config::kDht22Pin, DHT22);
ArduinoDht22Reader dhtReader(dht);
ArduinoAnalogInput mq7Input(config::kMq7AnalogPin);
ArduinoTwoWireBus i2cBus(Wire);
DHT22Sensor dhtSensor(dhtReader, config::kDhtIntervalMs,
                      config::kDht22Installed, config::kDhtFailureBackoffMs,
                      config::kDhtFailuresBeforeBackoff);
MQ7AnalogSensor mq7Sensor(mq7Input, config::kMq7IntervalMs,
                          config::kMq7Oversample);
SensorManager sensors(dhtSensor, mq7Sensor);
MpuSensor mpu(i2cBus, config::kMpuAddress, config::kMpuWakeDelayMs,
              config::kI2cTimeoutMs, config::kMpuReinitIntervalMs,
              config::kMpuMaxConsecutiveFailures);
MotionPipeline motion;
SemaphoreHandle_t motionMutex = nullptr;
// 50 Hz slots the motion task could not hand to the pipeline (mutex busy).
std::atomic<std::uint32_t> droppedMotionSlots{0};
TelemetryBuilder telemetryBuilder;
UnavailableGPSManager gpsManager;
UnavailableBatteryMonitor batteryMonitor;
UnconfiguredBuzzerController buzzer;
UnconfiguredLedController led;
PeriodicTask telemetrySchedule(config::kTelemetryIntervalMs);
EventIdGenerator* eventIds = nullptr;
#if SMART_SAFETY_ENABLE_STAGING_NETWORK
SecureIngestionClient secureIngestion;
#endif

// Everything loop() needs from the motion task, copied under the mutex.
struct MotionView {
  std::optional<MotionSample> latest;
  std::uint32_t latestMs{0};
  std::optional<WindowCandidate> candidate;
  MotionStatus status{};
  bool imuReady{false};
  bool imuBackingOff{false};
  ImuModel model{ImuModel::kUnknown};
  std::uint8_t whoAmI{0};
  std::uint32_t reinitializations{0};
};

bool pendingTelemetry = false;
std::uint32_t pendingSinceMs = 0;
bool reportedImuReady = false;
bool reportedImuMissing = false;
CalibrationState reportedCalibration = CalibrationState::kCollecting;
unsigned reportedCalibrationAttempts = 1;
bool reportedMq7Rail = false;

std::string bootSessionId() {
  char value[9]{};
  std::snprintf(value, sizeof(value), "%08lx",
                static_cast<unsigned long>(esp_random()));
  return value;
}

// 50 Hz sampling task. Runs above loop() priority on the application core so
// DHT reads, Serial output and telemetry building never stretch the cadence.
// The HTTPS upload runs in its own task on the other core.
void motionTask(void*) {
  TickType_t lastWake = xTaskGetTickCount();
  const TickType_t period = pdMS_TO_TICKS(kFallSamplePeriodMs);
  for (;;) {
    vTaskDelayUntil(&lastWake, period);
    const std::uint32_t nowMs = millis();
    RawImuReading reading;
    const auto result = mpu.read(nowMs, reading);
    // The timestamp is already captured, so waiting for the mutex does not
    // shift the sample in time. Only a sample that still cannot be handed
    // over is dropped; the window then restarts (it is never bridged).
    if (xSemaphoreTake(motionMutex, pdMS_TO_TICKS(15)) != pdTRUE) {
      droppedMotionSlots.fetch_add(1, std::memory_order_relaxed);
      continue;
    }
    if (result == ImuReadResult::kSample) {
      motion.onSample(reading, nowMs);
    } else if (result == ImuReadResult::kReadFailed) {
      motion.onReadFailure();
    }
    xSemaphoreGive(motionMutex);
  }
}

bool copyMotion(MotionView& view) {
  if (xSemaphoreTake(motionMutex, pdMS_TO_TICKS(50)) != pdTRUE) return false;
  view.latest = motion.latest();
  view.latestMs = motion.latestMs();
  view.candidate = motion.peekCandidate();
  view.status = motion.status();
  view.imuReady = mpu.ready();
  view.imuBackingOff = mpu.backingOff();
  view.model = mpu.model();
  view.whoAmI = mpu.detectedWhoAmI();
  view.reinitializations = mpu.reinitializations();
  xSemaphoreGive(motionMutex);
  return true;
}

void consumeCandidate(std::uint32_t windowEndMs) {
  if (xSemaphoreTake(motionMutex, pdMS_TO_TICKS(50)) == pdTRUE) {
    motion.consumeCandidate(windowEndMs);
    xSemaphoreGive(motionMutex);
  }
}

void reportTransitions(const MotionView& view) {
  if (view.imuReady && !reportedImuReady) {
    Serial.printf("IMU ready: %s (WHO_AM_I 0x%02X) at I2C 0x%02X, +/-16 g, "
                  "+/-2000 deg/s, 50 Hz.\n",
                  MpuSensor::modelName(view.model), view.whoAmI,
                  config::kMpuAddress);
    reportedImuMissing = false;
  }
  if (view.imuBackingOff && !reportedImuMissing) {
    Serial.printf("IMU unavailable (WHO_AM_I read 0x%02X; accepted 0x68 "
                  "MPU6050 or 0x70 MPU6500). Retrying every %lu ms.\n",
                  view.whoAmI,
                  static_cast<unsigned long>(config::kMpuReinitIntervalMs));
    reportedImuMissing = true;
  }
  if (view.imuReady) reportedImuMissing = false;
  reportedImuReady = view.imuReady;

  const auto& status = view.status;
  if (status.calibration == CalibrationState::kCollecting &&
      status.calibrationAttempts != reportedCalibrationAttempts) {
    Serial.printf("Gyro calibration attempt %u failed (%s); keep the board "
                  "still. Retrying.\n",
                  reportedCalibrationAttempts,
                  calibrationFailureName(status.lastCalibrationFailure));
    reportedCalibrationAttempts = status.calibrationAttempts;
  }
  if (status.calibration != reportedCalibration) {
    if (status.calibration == CalibrationState::kComplete) {
      Serial.printf("Gyro calibration complete after %u attempt(s): offsets "
                    "x=%.3f y=%.3f z=%.3f deg/s. Fall windows start now.\n",
                    status.calibrationAttempts, status.gyroOffsets.x,
                    status.gyroOffsets.y, status.gyroOffsets.z);
    } else if (status.calibration == CalibrationState::kFailed) {
      Serial.printf("Gyro calibration FAILED after %u attempts (%s). Fall "
                    "windows stay unavailable (fallWindowUnavailable). Place "
                    "the board still and press EN/RESET.\n",
                    status.calibrationAttempts,
                    calibrationFailureName(status.lastCalibrationFailure));
    }
    reportedCalibration = status.calibration;
  }

  if (mq7Sensor.lastReadAtRail() && !reportedMq7Rail) {
    Serial.println("WARNING: MQ-7 ADC reading is at a rail (0 or 4095). "
                   "Reported as mq7ReadFailed. If 4095, disconnect the MQ-7 "
                   "AO wire and verify the 10k/20k divider with a multimeter: "
                   "GPIO34 must never exceed 3.3 V.");
  }
  reportedMq7Rail = mq7Sensor.lastReadAtRail();
}

}  // namespace

void setup() {
  Serial.begin(115200);
  Wire.begin(config::kI2cSdaPin, config::kI2cSclPin);
  Wire.setClock(100000);
  if (config::kDht22Installed) dht.begin();
  mq7Input.begin();

  Serial.printf("\nSmart Safety Helmet firmware %s (telemetry schema %s).\n",
                config::kFirmwareVersion, config::kSchemaVersion);
  Serial.println("Prototype only: not certified PPE. Fall/gas detection is "
                 "not guaranteed.");
  Serial.println("Keep the board completely still for gyro calibration "
                 "(about 2 s after the IMU is ready).");

  if (!config::kDht22Installed) {
    Serial.println("DHT22 marked not installed (kDht22Installed=false): not "
                   "polled, reported as dhtReadFailed.");
  }

  const auto nowMs = millis();
  sensors.begin(nowMs);
  telemetrySchedule.reset(nowMs);
  mpu.begin(nowMs);
  motionMutex = xSemaphoreCreateMutex();
  if (motionMutex == nullptr ||
      xTaskCreatePinnedToCore(motionTask, "motion-50hz", 6144, nullptr, 3,
                              nullptr, 1) != pdPASS) {
    Serial.println("FATAL: motion task could not start; motion unavailable.");
  }

#if SMART_SAFETY_ENABLE_STAGING_NETWORK
  const bool transportConfigured = secureIngestion.begin();
  const std::string helmetId = transportConfigured
                                   ? secureIngestion.helmetId()
                                   : config::kHelmetIdPlaceholder;
#else
  const bool transportConfigured = false;
  const std::string helmetId = config::kHelmetIdPlaceholder;
#endif
  static EventIdGenerator generator(helmetId, bootSessionId());
  eventIds = &generator;

  Serial.println(
      transportConfigured
          ? "Staging telemetry transport enabled (HMAC-signed HTTPS to AWS)."
          : "Telemetry transport disabled; local diagnostics only.");
#if SMART_SAFETY_ENABLE_STAGING_NETWORK
  if (!transportConfigured) {
    Serial.println("Device is not provisioned (NVS ss_device incomplete). Run "
                   "the esp32dev_provisioner build first.");
  }
#endif
}

void loop() {
  const auto nowMs = millis();
  sensors.poll(nowMs);

  MotionView view;
  if (motionMutex == nullptr || !copyMotion(view)) {
    delay(1);
    return;
  }
  reportTransitions(view);

  if (!pendingTelemetry && telemetrySchedule.due(nowMs) && eventIds != nullptr) {
    pendingTelemetry = true;
    pendingSinceMs = nowMs;
  }
  if (!pendingTelemetry) {
    delay(1);
    return;
  }

  SensorSnapshot snapshot = sensors.snapshot();
  if (view.latest.has_value() &&
      static_cast<std::uint32_t>(nowMs - view.latestMs) <=
          config::kMotionStaleMs) {
    snapshot.motion = view.latest;
  }
  snapshot.fallStatus = view.status.localFallStatus;

  // The deployed contract only accepts instantaneous axes within +/-2 g and
  // +/-250 deg/s. Wait briefly for an in-range sample rather than sending
  // clipped values or a false mpuReadFailed.
  if (snapshot.motion.has_value() &&
      !TelemetryBuilder::motionWithinIngestionContract(*snapshot.motion) &&
      static_cast<std::uint32_t>(nowMs - pendingSinceMs) <
          config::kTelemetryDeferralMaxMs) {
    delay(1);
    return;
  }

#if SMART_SAFETY_ENABLE_STAGING_NETWORK
  const bool timeSynchronized = secureIngestion.timeSynchronized();
  const std::uint64_t utcNowMs = secureIngestion.utcNowMs();
  const std::string helmetId = secureIngestion.configured()
                                   ? secureIngestion.helmetId()
                                   : config::kHelmetIdPlaceholder;
#else
  const bool timeSynchronized = false;
  const std::uint64_t utcNowMs = 0;
  const std::string helmetId = config::kHelmetIdPlaceholder;
#endif

  if (view.candidate.has_value()) {
    FallWindowEvidence evidence{view.candidate->features, std::nullopt};
    const auto ageMs =
        static_cast<std::uint32_t>(nowMs - view.candidate->windowEndMs);
    if (timeSynchronized && utcNowMs >= ageMs) {
      evidence.windowEndTimestampMs = utcNowMs - ageMs;
    }
    snapshot.fallWindow = evidence;
  }

  const auto eventId = eventIds->next();
  const TelemetryMetadata metadata{
      eventId, helmetId,
      timeSynchronized ? std::optional<std::uint64_t>(utcNowMs) : std::nullopt,
      timeSynchronized, config::kFirmwareVersion};
  const auto record = telemetryBuilder.build(metadata, snapshot);
  Serial.print("LOCAL ");
  Serial.println(record.json.c_str());
  Serial.printf("STATUS imu=%s whoami=0x%02X calibration=%s window=%u/%u "
                "windowRestarts=%lu saturatedWindows=%lu imuReadFailures=%lu "
                "imuReinit=%lu maxLateMs=%lu lastRestartDevMs=%ld "
                "droppedSlots=%lu\n",
                MpuSensor::modelName(view.model), view.whoAmI,
                calibrationStateName(view.status.calibration),
                static_cast<unsigned>(view.status.windowFill),
                static_cast<unsigned>(kFallWindowSamples),
                static_cast<unsigned long>(view.status.windowRestarts),
                static_cast<unsigned long>(view.status.saturatedWindows),
                static_cast<unsigned long>(view.status.readFailures),
                static_cast<unsigned long>(view.reinitializations),
                static_cast<unsigned long>(view.status.maxSampleLatenessMs),
                static_cast<long>(view.status.lastRestartDeviationMs),
                static_cast<unsigned long>(
                    droppedMotionSlots.load(std::memory_order_relaxed)));

  bool keepCandidate = false;
#if SMART_SAFETY_ENABLE_STAGING_NETWORK
  if (secureIngestion.configured()) {
    const auto ingestion = telemetryBuilder.buildIngestion(metadata, snapshot);
    if (ingestion.json.has_value()) {
      const bool queued = secureIngestion.enqueue(eventId, *ingestion.json);
      Serial.printf("UPLOAD %s event=%s bytes=%u fallWindow=%s\n",
                    queued ? "queued" : "queue-failed", eventId.c_str(),
                    static_cast<unsigned>(ingestion.json->size()),
                    ingestion.json->find("\"fallFeatures\"") != std::string::npos
                        ? "included"
                        : "unavailable");
    } else {
      Serial.printf("UPLOAD skipped event=%s reason=%s\n", eventId.c_str(),
                    ingestionBlockName(ingestion.block));
      // A window blocked only by momentary motion range is kept for retry.
      keepCandidate =
          ingestion.block == IngestionBlock::kMotionOutsideContractRange;
    }
  }
#endif
  if (view.candidate.has_value() && !keepCandidate) {
    consumeCandidate(view.candidate->windowEndMs);
  }
  pendingTelemetry = false;
}

#endif  // !SMART_SAFETY_PROVISIONER_BUILD
