#include <Arduino.h>
#include <DHT.h>
#include <Wire.h>
#include <esp_system.h>

#include <cstdio>
#include <string>

#include "smart_safety/ArduinoAdapters.h"
#include "smart_safety/DHT22Sensor.h"
#include "smart_safety/DisabledHardware.h"
#include "smart_safety/EventIdGenerator.h"
#include "smart_safety/FallDetectionEngine.h"
#include "smart_safety/FirmwareConfig.h"
#include "smart_safety/MPU6500Sensor.h"
#include "smart_safety/NonBlockingScheduler.h"
#include "smart_safety/SensorManager.h"
#include "smart_safety/SecureIngestionClient.h"
#include "smart_safety/TelemetryBuilder.h"

#ifndef SMART_SAFETY_PROVISIONER_BUILD
#define SMART_SAFETY_PROVISIONER_BUILD 0
#endif

#if !SMART_SAFETY_PROVISIONER_BUILD

namespace {

using namespace smart_safety;

DHT dht(config::kDht22Pin, DHT22);
ArduinoDht22Reader dhtReader(dht);
ArduinoTwoWireBus i2cBus(Wire);
DHT22Sensor dhtSensor(dhtReader, config::kDhtIntervalMs);
MPU6500Sensor mpuSensor(i2cBus, config::kMpuAddress,
                        config::kMpuIntervalMs, config::kMpuWakeDelayMs,
                        config::kI2cTimeoutMs);
SensorManager sensors(dhtSensor, mpuSensor);
FallDetectionEngine fallDetection;
TelemetryBuilder telemetryBuilder;
DisabledTelemetryTransport telemetryTransport;
DisabledNetworkManager networkManager;
DisabledMQ7Sensor mq7Sensor;
UnavailableGPSManager gpsManager;
UnavailableBatteryMonitor batteryMonitor;
UnconfiguredBuzzerController buzzer;
UnconfiguredLedController led;
PeriodicTask telemetrySchedule(config::kTelemetryIntervalMs);
EventIdGenerator* eventIds = nullptr;
#if SMART_SAFETY_ENABLE_STAGING_NETWORK
SecureIngestionClient secureIngestion;
#endif

std::string bootSessionId() {
  char value[9]{};
  std::snprintf(value, sizeof(value), "%08lx",
                static_cast<unsigned long>(esp_random()));
  return value;
}

}  // namespace

void setup() {
  Serial.begin(115200);
  Wire.begin(config::kI2cSdaPin, config::kI2cSclPin);
  Wire.setClock(100000);
  dht.begin();

  const auto nowMs = millis();
  sensors.begin(nowMs);
  telemetrySchedule.reset(nowMs);
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

  Serial.println(transportConfigured
                     ? "Staging telemetry transport enabled."
                     : "Telemetry transport disabled; local diagnostics only.");
}

void loop() {
  const auto nowMs = millis();
  const auto updated = sensors.poll(nowMs);
  auto& snapshot = sensors.snapshot();

  if (updated.mpuUpdated && snapshot.motion.has_value()) {
    const auto fall = fallDetection.update(*snapshot.motion, nowMs);
    snapshot.fallStatus = fall.status;
    // Confirmed fall remains diagnostic state only. No buzzer, LED, transport,
    // or alert action is activated in this restricted batch.
  }

  if (!telemetrySchedule.due(nowMs) || eventIds == nullptr) return;

  const auto eventId = eventIds->next();
#if SMART_SAFETY_ENABLE_STAGING_NETWORK
  const bool timeSynchronized = secureIngestion.timeSynchronized();
  const auto timestamp = timeSynchronized
                             ? std::optional<std::uint64_t>(secureIngestion.utcNowMs())
                             : std::nullopt;
  const std::string helmetId = secureIngestion.configured()
                                   ? secureIngestion.helmetId()
                                   : config::kHelmetIdPlaceholder;
#else
  const bool timeSynchronized = false;
  const std::optional<std::uint64_t> timestamp = std::nullopt;
  const std::string helmetId = config::kHelmetIdPlaceholder;
#endif
  const TelemetryMetadata metadata{eventId, helmetId, timestamp,
                                   timeSynchronized,
                                   config::kFirmwareVersion};
  const auto record = telemetryBuilder.build(metadata, snapshot);
  Serial.println(record.json.c_str());
#if SMART_SAFETY_ENABLE_STAGING_NETWORK
  const auto ingestionJson = telemetryBuilder.buildIngestionJson(metadata, snapshot);
  if (secureIngestion.configured() && ingestionJson.has_value()) {
    secureIngestion.enqueue(eventId, *ingestionJson);
  }
#else
  telemetryTransport.send(record);  // Deterministically returns kDisabled.
#endif
}

#endif  // !SMART_SAFETY_PROVISIONER_BUILD
