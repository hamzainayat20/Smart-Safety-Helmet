#include <algorithm>
#include <array>
#include <cmath>
#include <cstdint>
#include <cstring>
#include <fstream>
#include <functional>
#include <iostream>
#include <map>
#include <optional>
#include <stdexcept>
#include <string>
#include <utility>
#include <vector>

#include "smart_safety/DHT22Sensor.h"
#include "smart_safety/DisabledHardware.h"
#include "smart_safety/EventIdGenerator.h"
#include "smart_safety/FallDetectionEngine.h"
#include "smart_safety/FallFeatures.h"
#include "smart_safety/FirmwareConfig.h"
#include "smart_safety/MQ7AnalogSensor.h"
#include "smart_safety/MotionPipeline.h"
#include "smart_safety/MpuSensor.h"
#include "smart_safety/NonBlockingScheduler.h"
#include "smart_safety/OfflineBuffer.h"
#include "smart_safety/SecureIngestionProtocol.h"
#include "smart_safety/SensorManager.h"
#include "smart_safety/TelemetryBuilder.h"

namespace {

using namespace smart_safety;

std::string gFixtureDirectory;  // optional: write JSON fixtures for Node/Python

void require(bool condition, const std::string& message) {
  if (!condition) throw std::runtime_error(message);
}

bool near(double actual, double expected, double tolerance = 1e-9) {
  return std::fabs(actual - expected) <= tolerance;
}

bool contains(const std::string& text, const std::string& needle) {
  return text.find(needle) != std::string::npos;
}

bool hasFault(const SensorSnapshot& snapshot, const std::string& fault) {
  const auto names = deriveSensorFaults(snapshot);
  return std::find(names.begin(), names.end(), fault) != names.end();
}

void writeFixture(const std::string& name, const std::string& json) {
  if (gFixtureDirectory.empty()) return;
  std::ofstream(gFixtureDirectory + "/" + name) << json;
}

// ---------------------------------------------------------------- fakes

class FakeDhtReader final : public Dht22Reader {
 public:
  bool success{true};
  int reads{0};
  Dht22RawReading reading{25.0, 50.0, 25.5};

  bool read(Dht22RawReading& output) override {
    ++reads;
    if (!success) return false;
    output = reading;
    return true;
  }
};

class FakeI2cBus final : public I2cBus {
 public:
  std::uint8_t whoAmI{0x68};
  bool whoAmIReadSucceeds{true};
  bool dataReadsSucceed{true};
  std::optional<std::uint8_t> failedWriteRegister;
  std::optional<std::uint8_t> corruptReadbackRegister;
  std::uint32_t timeoutMs{0};
  std::map<std::uint8_t, std::uint8_t> registers;
  std::vector<std::pair<std::uint8_t, std::uint8_t>> writes;
  std::array<std::uint8_t, 14> motionBytes{};

  FakeI2cBus() { setWord(4, 2048); }  // +1 g on Z at +/-16 g

  void setTimeoutMs(std::uint32_t value) override { timeoutMs = value; }

  bool readRegister(std::uint8_t, std::uint8_t reg,
                    std::uint8_t& value) override {
    if (reg == 0x75) {
      if (!whoAmIReadSucceeds) return false;
      value = whoAmI;
      return true;
    }
    const auto found = registers.find(reg);
    if (found == registers.end()) return false;
    value = found->second;
    if (corruptReadbackRegister == reg) value ^= 0xFF;
    return true;
  }

  bool writeRegister(std::uint8_t, std::uint8_t reg,
                     std::uint8_t value) override {
    writes.emplace_back(reg, value);
    if (failedWriteRegister == reg) return false;
    registers[reg] = value;
    return true;
  }

  bool readRegisters(std::uint8_t, std::uint8_t start, std::uint8_t* output,
                     std::size_t length) override {
    if (!dataReadsSucceed || start != 0x3B || length != motionBytes.size()) {
      return false;
    }
    std::copy(motionBytes.begin(), motionBytes.end(), output);
    return true;
  }

  void setWord(std::size_t offset, std::int16_t value) {
    const auto raw = static_cast<std::uint16_t>(value);
    motionBytes[offset] = static_cast<std::uint8_t>(raw >> 8U);
    motionBytes[offset + 1] = static_cast<std::uint8_t>(raw & 0xFFU);
  }

  bool wrote(std::uint8_t reg, std::uint8_t value) const {
    return std::find(writes.begin(), writes.end(), std::make_pair(reg, value)) !=
           writes.end();
  }
};

class FakeAnalogInput final : public AnalogInput {
 public:
  std::vector<int> values{208};
  bool succeed{true};
  std::size_t reads{0};

  bool read(int& raw) override {
    if (!succeed) return false;
    raw = values[reads++ % values.size()];
    return true;
  }
};

// Brings a sensor to the ready state: begin at 0, configure at 100 ms.
void bringUp(MpuSensor& sensor) {
  RawImuReading ignored;
  require(sensor.begin(0), "MPU begin failed");
  require(sensor.read(99, ignored) == ImuReadResult::kInitializing,
          "MPU wake delay was skipped");
  require(sensor.read(100, ignored) == ImuReadResult::kInitializing,
          "MPU configuration emitted a sample");
  require(sensor.ready(), "MPU was not ready after configuration");
}

RawImuReading still(double gx = 0.4, double gy = -0.3, double gz = 0.2,
                    double az = 1.0) {
  RawImuReading reading;
  reading.sample.accelZG = az;
  reading.sample.gyroXDegreesPerSecond = gx;
  reading.sample.gyroYDegreesPerSecond = gy;
  reading.sample.gyroZDegreesPerSecond = gz;
  return reading;
}

// Feeds n samples at exact 20 ms spacing; returns the next timestamp.
std::uint32_t feed(MotionPipeline& pipeline, std::uint32_t startMs, int n,
                   const std::function<RawImuReading(int)>& make) {
  std::uint32_t now = startMs;
  for (int index = 0; index < n; ++index, now += 20) {
    pipeline.onSample(make(index), now);
  }
  return now;
}

// ---------------------------------------------------------------- MPU

void testMpu6050IdentityAccepted() {
  FakeI2cBus bus;
  MpuSensor sensor(bus, 0x68, 100, 20);
  bringUp(sensor);
  require(sensor.model() == ImuModel::kMpu6050 && sensor.detectedWhoAmI() == 0x68,
          "MPU6050 WHO_AM_I 0x68 was not identified");
  require(bus.timeoutMs == 20, "I2C timeout was not configured");
  require(bus.wrote(0x6B, 0x01) && bus.wrote(0x19, 19) && bus.wrote(0x1A, 0x04) &&
              bus.wrote(0x1B, 0x18) && bus.wrote(0x1C, 0x18),
          "MPU6050 was not configured for 50 Hz, DLPF 4, +/-2000 dps, +/-16 g");
  require(!bus.wrote(0x1D, 0x04), "MPU6500-only register written on MPU6050");

  bus.setWord(0, -1024);  // -0.5 g
  bus.setWord(8, 164);    // 10 deg/s
  RawImuReading reading;
  require(sensor.read(120, reading) == ImuReadResult::kSample, "no MPU sample");
  require(near(reading.sample.accelXG, -0.5) && near(reading.sample.accelZG, 1.0) &&
              near(reading.sample.gyroXDegreesPerSecond, 10.0),
          "MPU +/-16 g or +/-2000 dps scaling is wrong");
  require(!reading.saturated, "unsaturated sample flagged as clipped");
}

void testMpu6500IdentityRetained() {
  FakeI2cBus bus;
  bus.whoAmI = 0x70;
  MpuSensor sensor(bus, 0x68, 100, 20);
  bringUp(sensor);
  require(sensor.model() == ImuModel::kMpu6500, "MPU6500 0x70 not identified");
  require(bus.wrote(0x1D, 0x04), "MPU6500 accel DLPF was not configured");
}

void testInvalidIdentitiesRejected() {
  for (const std::uint8_t identity : {0x00, 0x69, 0x71, 0x72, 0x98, 0xFF}) {
    FakeI2cBus bus;
    bus.whoAmI = identity;
    MpuSensor sensor(bus, 0x68, 100, 20);
    require(!sensor.begin(0), "unverified WHO_AM_I accepted: " +
                                  std::to_string(identity));
    require(!sensor.ready() && sensor.model() == ImuModel::kUnknown,
            "rejected identity was marked ready");
    require(bus.writes.empty(), "rejected device was written to");
  }
  FakeI2cBus silent;
  silent.whoAmIReadSucceeds = false;
  MpuSensor absent(silent, 0x68, 100, 20);
  require(!absent.begin(0), "absent IMU was accepted");
}

void testMpuConfigurationReadbackAndRecovery() {
  FakeI2cBus bus;
  bus.corruptReadbackRegister = 0x1C;
  MpuSensor sensor(bus, 0x68, 100, 20, 1000, 5);
  RawImuReading reading;
  require(sensor.begin(0), "wake stage failed");
  require(sensor.read(100, reading) == ImuReadResult::kUnavailable &&
              !sensor.ready(),
          "unverified accelerometer range was accepted");

  // Bounded recovery: retried only after the re-init interval.
  bus.corruptReadbackRegister.reset();
  require(sensor.read(500, reading) == ImuReadResult::kUnavailable &&
              sensor.reinitializations() == 0,
          "re-initialization was not rate limited");
  require(sensor.read(1100, reading) == ImuReadResult::kUnavailable &&
              sensor.reinitializations() == 1,
          "re-initialization did not start after the interval");
  sensor.read(1200, reading);
  require(sensor.ready(), "MPU did not recover after re-initialization");
}

void testMpuReadFailureRecoveryAndSaturation() {
  FakeI2cBus bus;
  MpuSensor sensor(bus, 0x68, 100, 20, 1000, 5);
  bringUp(sensor);
  RawImuReading reading;
  bus.dataReadsSucceed = false;
  std::uint32_t now = 120;
  for (int failure = 0; failure < 4; ++failure, now += 20) {
    require(sensor.read(now, reading) == ImuReadResult::kReadFailed,
            "read failure not reported");
    require(sensor.ready(), "single failures left the ready state too early");
  }
  require(sensor.read(now, reading) == ImuReadResult::kReadFailed && !sensor.ready(),
          "five consecutive failures did not enter back-off");
  bus.dataReadsSucceed = true;
  sensor.read(now + 1000, reading);  // re-begin
  sensor.read(now + 1100, reading);  // configure
  require(sensor.ready(), "MPU did not recover from read failures");

  bus.setWord(2, 32767);
  require(sensor.read(now + 1120, reading) == ImuReadResult::kSample &&
              reading.saturated,
          "clipped axis was not flagged as saturated");
}

// ---------------------------------------------------------------- calibration

void testCalibrationSuccess() {
  GyroCalibrator calibrator;
  for (int index = 0; index < 99; ++index) {
    const double noise = (index % 2 == 0 ? 0.05 : -0.05);
    calibrator.add(-3.19 + noise, 2.02 - noise, -0.79 + noise, 1.094);
  }
  require(calibrator.state() == CalibrationState::kCollecting,
          "calibration finished before 100 samples");
  calibrator.add(-3.19, 2.02, -0.79, 1.094);
  require(calibrator.state() == CalibrationState::kComplete,
          "stationary calibration did not complete");
  const auto& offsets = calibrator.offsets();
  require(near(offsets.x, -3.19, 1e-3) && near(offsets.y, 2.02, 1e-3) &&
              near(offsets.z, -0.79, 1e-3),
          "gyro offsets are wrong");
}

void testCalibrationFailuresAreBounded() {
  CalibrationLimits limits;
  limits.maxAttempts = 3;
  GyroCalibrator moving(limits);
  for (int index = 0; index < 300; ++index) {
    moving.add(index % 2 == 0 ? 20.0 : -20.0, 0, 0, 1.0);
  }
  require(moving.state() == CalibrationState::kFailed &&
              moving.attempts() == 3 &&
              moving.lastFailure() == CalibrationFailure::kMotionDetected,
          "moving calibration was not rejected after bounded attempts");
  require(!moving.add(0, 0, 0, 1.0), "failed calibrator kept collecting");

  GyroCalibrator freeFall(limits);
  for (int index = 0; index < 100; ++index) freeFall.add(0, 0, 0, 0.2);
  require(freeFall.lastFailure() == CalibrationFailure::kGravityImplausible &&
              freeFall.state() == CalibrationState::kCollecting &&
              freeFall.attempts() == 2,
          "implausible gravity was not rejected and retried");

  GyroCalibrator broken(limits);
  for (int index = 0; index < 100; ++index) broken.add(45, 0, 0, 1.0);
  require(broken.lastFailure() == CalibrationFailure::kOffsetImplausible,
          "implausible gyro offset was accepted");

  GyroCalibrator interrupted(limits);
  interrupted.add(0, 0, 0, 1.0);
  require(interrupted.interrupt() &&
              interrupted.lastFailure() == CalibrationFailure::kReadInterrupted &&
              interrupted.collected() == 0,
          "read failure did not restart the calibration attempt");
}

// ---------------------------------------------------------------- features

void testFeatureValuesDeterministicFixture() {
  std::array<double, kFallWindowSamples> acc{};
  std::array<double, kFallWindowSamples> gyro{};
  for (std::size_t i = 0; i < kFallWindowSamples; ++i) {
    acc[i] = 1.0 + 0.01 * static_cast<double>(i);
    gyro[i] = (i % 2 == 0) ? 0.0 : 10.0;
  }
  const auto f = computeFallFeatures(acc, gyro);
  require(f.has_value(), "valid fixture produced no features");
  // Population std of 0..99 is sqrt((100^2 - 1) / 12).
  require(near(f->accMean, 1.495) && near(f->accStd, 0.01 * std::sqrt(9999.0 / 12.0)) &&
              near(f->accMin, 1.0) && near(f->accMax, 1.99),
          "acceleration features are wrong");
  require(near(f->gyroMean, 5.0) && near(f->gyroStd, 5.0) && near(f->gyroMax, 10.0),
          "gyro features are wrong");
  require(near(f->jerkMean, 0.5) && near(f->jerkMax, 0.5),
          "jerk features are wrong (expected 0.01 g x 50 Hz = 0.5 g/s)");
}

void testJerkFirstSampleHandling() {
  std::array<double, kFallWindowSamples> acc{};
  std::array<double, kFallWindowSamples> gyro{};
  acc.fill(1.0);
  gyro.fill(0.0);
  acc[0] = 5.0;  // only pair (0, 1) carries jerk
  const auto f = computeFallFeatures(acc, gyro);
  require(f.has_value(), "fixture produced no features");
  require(near(jerkGPerSecond(5.0, 1.0), 200.0), "jerk definition changed");
  require(near(f->jerkMax, 200.0) && near(f->jerkMean, 200.0 / 99.0),
          "jerk must average 99 pairs; the first sample has no jerk value");
  require(near(f->gyroMean, 0.0) && f->gyroStd == 0.0,
          "a real all-zero gyro window must stay zero, not be rejected");

  auto bad = acc;
  bad[50] = std::nan("");
  require(!computeFallFeatures(bad, gyro).has_value(),
          "non-finite magnitude produced features");
  bad[50] = -1.0;
  require(!computeFallFeatures(bad, gyro).has_value(),
          "negative magnitude produced features");
}

void testExactFiftyHertzHundredSampleWindow() {
  FallFeatureWindow window;
  std::uint32_t now = 1000;
  for (int i = 0; i < 99; ++i, now += 20) window.push(1.0, 0.0, now, false);
  require(window.size() == 99 && !window.full() && !window.compute().has_value(),
          "99 samples produced a window");
  window.push(1.0, 0.0, now, false);
  require(window.full() && window.compute().has_value(),
          "exactly 100 contiguous samples did not complete the window");
  window.push(1.0, 0.0, now + 20, false);
  require(window.size() == 100, "window grew beyond 100 samples");

  window.push(1.0, 0.0, now + 60, false);  // 40 ms gap: missed sample
  require(window.size() == 1 && window.restarts() == 1,
          "a missed 50 Hz slot did not restart the window");
  window.push(1.0, 0.0, now + 70, false);  // 10 ms: too early
  require(window.size() == 1 && window.restarts() == 2,
          "an early sample did not restart the window");

  FallFeatureWindow wrapped;
  std::uint32_t t = 0xFFFFFFFFU - 990U;
  for (int i = 0; i < 100; ++i, t += 20) wrapped.push(1.0, 0.0, t, false);
  require(wrapped.full() && wrapped.restarts() == 0,
          "millis() wraparound broke window continuity");
}


// Grid sample time for slot i, plus a non-negative wake-up lateness.
std::uint32_t slot(std::uint32_t start, int i, std::uint32_t lateMs = 0) {
  return start + 20U * static_cast<std::uint32_t>(i) + lateMs;
}

void testRealDeviceJitterTolerated() {
  // Lateness pattern seen with vTaskDelayUntil: a late wake followed by an
  // on-time one gives sample-to-sample gaps of 29 ms then 11 ms, which the
  // old 15-25 ms pair rule rejected.
  const std::uint32_t pattern[] = {0, 3, 7, 9, 0, 1, 8, 2, 0, 6, 9, 0};
  FallFeatureWindow jittered;
  FallFeatureWindow exact;
  for (int i = 0; i < 300; ++i) {
    const double acc = 1.0 + 0.01 * (i % 100);
    const double gyro = (i % 2) ? 10.0 : 0.0;
    jittered.push(acc, gyro, slot(5000, i, pattern[i % 12]), false);
    exact.push(acc, gyro, slot(5000, i), false);
  }
  require(jittered.restarts() == 0 && jittered.full(),
          "normal ESP32 wake-up jitter restarted the window");
  require(jittered.runMaxLatenessMs() == 9, "lateness was not tracked");
  const auto a = jittered.compute();
  const auto b = exact.compute();
  require(a.has_value() && b.has_value() && near(a->accMean, b->accMean) &&
              near(a->accStd, b->accStd) && near(a->gyroMax, b->gyroMax) &&
              near(a->jerkMean, b->jerkMean) && near(a->jerkMax, b->jerkMax),
          "jitter tolerance changed the feature values");
}

void testLatenessBoundary() {
  for (const std::uint32_t late : {9U, 10U}) {
    FallFeatureWindow window;
    for (int i = 0; i < 50; ++i) window.push(1.0, 0.0, slot(0, i), false);
    window.push(1.0, 0.0, slot(0, 50, late), false);
    if (late == 9) {
      require(window.size() == 51 && window.restarts() == 0,
              "a sample 9 ms late was rejected");
    } else {
      require(window.size() == 1 && window.restarts() == 1 &&
                  window.lastRestartDeviationMs() == 10,
              "a sample 10 ms late (closer to the next slot) was accepted");
    }
  }
}

void testLateAnchorReanchorsGrid() {
  FallFeatureWindow window;
  window.push(1.0, 0.0, slot(0, 0, 9), false);  // first sample woke 9 ms late
  for (int i = 1; i < 100; ++i) {
    // later samples are on time; one is 9 ms late against the true grid
    window.push(1.0, 0.0, slot(0, i, i == 60 ? 9 : 0), false);
  }
  require(window.full() && window.restarts() == 0,
          "a late first sample prevented an on-time window");
  require(window.runMaxLatenessMs() == 9, "re-anchored lateness is wrong");
  // After the grid is anchored, a sample 1 ms early is not physically
  // possible for a delayed task and would exceed the lateness budget.
  window.push(1.0, 0.0, slot(0, 100) - 1, false);
  require(window.restarts() == 1 && window.lastRestartDeviationMs() == -1,
          "lateness budget was exceeded without a restart");
}

void testRateDriftRejected() {
  for (const std::uint32_t period : {19U, 21U}) {
    FallFeatureWindow window;
    std::uint32_t now = 0;
    for (int i = 0; i < 300; ++i, now += period) {
      window.push(1.0, 0.0, now, false);
      require(!window.full(),
              "a " + std::to_string(period) + " ms rate filled a 50 Hz window");
    }
    require(window.restarts() > 0, "rate drift was never detected");
  }
}

void testStallRestartsHonestly() {
  // A ~80 ms core stall (as caused by polling an absent DHT22) loses real
  // samples. The window must restart, never bridge the gap.
  FallFeatureWindow window;
  for (int i = 0; i < 60; ++i) window.push(1.0, 0.0, slot(0, i), false);
  window.push(1.0, 0.0, slot(0, 60, 80), false);  // first sample after stall
  require(window.size() == 1 && window.restarts() == 1 &&
              window.lastRestartDeviationMs() == 80,
          "missing samples were bridged across a stall");
  // vTaskDelayUntil catch-up: the following slots run immediately, then the
  // schedule is back on the grid; the window recovers by itself.
  window.push(1.0, 0.0, slot(0, 61, 80) + 1, false);
  window.push(1.0, 0.0, slot(0, 62, 79), false);
  std::uint32_t restarts = window.restarts();
  for (int i = 66; i < 166; ++i) window.push(1.0, 0.0, slot(0, i), false);
  require(window.full() && window.restarts() <= restarts + 1,
          "window did not recover after a stall");
}

void testPipelineToleratesJitter() {
  const std::uint32_t pattern[] = {0, 4, 9, 0, 2, 7};
  MotionPipeline pipeline;
  for (int i = 0; i < 260; ++i) {
    pipeline.onSample(still(), slot(1000, i, pattern[i % 6]));
  }
  require(pipeline.status().windowRestarts == 0 &&
              pipeline.peekCandidate().has_value() &&
              pipeline.status().maxSampleLatenessMs == 9,
          "pipeline lost windows to normal jitter or hid the lateness");
}

void testDhtNotInstalledIsNeverPolled() {
  FakeDhtReader reader;
  DHT22Sensor sensor(reader, 2000, false);
  SensorSnapshot snapshot;
  snapshot.temperatureC = 25.0;
  sensor.begin(0);
  for (std::uint32_t now = 0; now <= 20000; now += 20) sensor.poll(now, snapshot);
  require(reader.reads == 0, "an uninstalled DHT22 was polled");
  require(!snapshot.temperatureC.has_value() && hasFault(snapshot, "dhtReadFailed"),
          "an uninstalled DHT22 was not reported as dhtReadFailed");
}

void testDhtFailureBackoff() {
  FakeDhtReader reader;
  reader.success = false;
  DHT22Sensor sensor(reader, 2000, true, 60000, 3);
  SensorSnapshot snapshot;
  sensor.begin(0);
  for (std::uint32_t now = 0; now <= 10000; now += 20) sensor.poll(now, snapshot);
  require(reader.reads == 3 && sensor.backingOff(),
          "repeated DHT failures did not back off after three attempts");
  for (std::uint32_t now = 10020; now < 66000; now += 20) sensor.poll(now, snapshot);
  require(reader.reads == 3, "DHT was polled during the back-off period");
  reader.success = true;
  for (std::uint32_t now = 66000; now <= 70000; now += 20) sensor.poll(now, snapshot);
  require(reader.reads >= 2 && !sensor.backingOff() &&
              snapshot.temperatureC.has_value(),
          "DHT did not recover from back-off");
}

void testRingOrderIsOldestFirst() {
  FallFeatureWindow window;
  std::uint32_t now = 0;
  // 30 old samples at 3 g that must be pushed out, then 100 ramp samples.
  for (int i = 0; i < 30; ++i, now += 20) window.push(3.0, 0.0, now, false);
  for (int i = 0; i < 100; ++i, now += 20) {
    window.push(1.0 + 0.01 * i, 0.0, now, false);
  }
  const auto f = window.compute();
  require(f.has_value() && near(f->accMax, 1.99) && near(f->jerkMax, 0.5),
          "ring buffer did not keep the latest 100 samples in order");
}

void testSaturatedWindowUnavailable() {
  FallFeatureWindow window;
  std::uint32_t now = 0;
  for (int i = 0; i < 100; ++i, now += 20) window.push(1.0, 0.0, now, i == 40);
  require(window.full() && !window.compute().has_value(),
          "a clipped window produced features");
}

// ---------------------------------------------------------------- pipeline

void testPipelineCalibrationGatesWindow() {
  CalibrationLimits limits;
  limits.maxAttempts = 2;
  MotionPipeline pipeline(limits);
  // Moving during both calibration attempts: never any window.
  feed(pipeline, 0, 400, [](int i) { return still(i % 2 ? 30 : -30); });
  require(pipeline.status().calibration == CalibrationState::kFailed,
          "pipeline calibration did not fail when moving");
  require(!pipeline.peekCandidate().has_value(),
          "uncalibrated pipeline produced a fall window");
  require(pipeline.latest().has_value() &&
              near(std::fabs(pipeline.latest()->gyroXDegreesPerSecond), 30.0),
          "a working IMU must still report its real (uncalibrated) reading");
}

void testPipelineWindowsStrideAndCandidate() {
  MotionPipeline pipeline;
  std::uint32_t now = feed(pipeline, 0, 100, [](int) { return still(); });
  require(pipeline.status().calibration == CalibrationState::kComplete,
          "calibration did not complete");
  require(pipeline.latest().has_value() &&
              near(pipeline.latest()->gyroXDegreesPerSecond, 0.0, 1e-9),
          "gyro offsets were not removed from the latest sample");
  require(near(pipeline.latest()->accelZG, 1.0),
          "acceleration was altered; gravity must be kept");
  require(!pipeline.peekCandidate().has_value(),
          "candidate before the first full post-calibration window");

  // The calibration-completing sample is window sample 1; 99 more fill it.
  now = feed(pipeline, now, 99, [](int) { return still(); });
  require(pipeline.peekCandidate().has_value(), "full window not evaluated");
  const auto first = *pipeline.peekCandidate();
  require(first.windowEndMs == now - 20, "window end time is wrong");
  require(near(first.features.accMean, 1.0) && near(first.features.gyroMean, 0.0),
          "stationary features are not plausible");

  // A stronger window replaces the candidate at the next 25-sample step.
  now = feed(pipeline, now, 24, [](int) { return still(); });
  require(pipeline.peekCandidate()->windowEndMs == first.windowEndMs,
          "window evaluated before the 25-sample stride");
  now = feed(pipeline, now, 1, [](int) { return still(0.4, -0.3, 0.2, 1.8); });
  require(near(pipeline.peekCandidate()->features.accMax, 1.8),
          "stronger window did not replace the candidate at the stride");
  const auto strong = pipeline.peekCandidate()->windowEndMs;
  require(!pipeline.consumeCandidate(first.windowEndMs) &&
              pipeline.peekCandidate().has_value(),
          "a newer candidate was discarded by a stale consume");
  require(pipeline.consumeCandidate(strong) && !pipeline.peekCandidate().has_value(),
          "candidate was not consumed");

  pipeline.onReadFailure();
  require(!pipeline.latest().has_value() && pipeline.status().windowFill == 0,
          "read failure kept stale motion or a partial window");
}

void testPipelineSaturationCounted() {
  MotionPipeline pipeline;
  std::uint32_t now = feed(pipeline, 0, 100, [](int) { return still(); });
  feed(pipeline, now, 99, [](int i) {
    auto reading = still();
    reading.saturated = (i == 10);
    return reading;
  });
  require(!pipeline.peekCandidate().has_value() &&
              pipeline.status().saturatedWindows == 1,
          "saturated window was evaluated or not reported");
}

// ---------------------------------------------------------------- DHT / MQ-7

void testDhtValidAndMissing() {
  FakeDhtReader reader;
  DHT22Sensor sensor(reader, 2000);
  SensorSnapshot snapshot;
  sensor.begin(0);
  require(!sensor.poll(1999, snapshot), "DHT sampled before two seconds");
  require(sensor.poll(2000, snapshot) && snapshot.temperatureC == 25.0 &&
              !hasFault(snapshot, "dhtReadFailed"),
          "valid DHT values were not retained");
  reader.success = false;
  require(sensor.poll(4000, snapshot) && !snapshot.temperatureC.has_value() &&
              !snapshot.humidityPct.has_value() && !snapshot.heatIndexC.has_value() &&
              hasFault(snapshot, "dhtReadFailed"),
          "missing DHT22 was not reported as dhtReadFailed");
}

void testDhtMissingDoesNotStopMotion() {
  FakeDhtReader dhtReader;
  dhtReader.success = false;
  FakeAnalogInput adc;
  DHT22Sensor dht(dhtReader, 2000);
  MQ7AnalogSensor mq7(adc, 1000);
  SensorManager manager(dht, mq7);
  MotionPipeline pipeline;
  manager.begin(0);
  // Interleave slow-sensor polling with 50 Hz motion, as loop() and the
  // motion task do on the ESP32.
  std::uint32_t now = 0;
  for (int i = 0; i < 260; ++i, now += 20) {
    pipeline.onSample(still(), now);
    manager.poll(now);
  }
  require(hasFault(manager.snapshot(), "dhtReadFailed"), "DHT fault missing");
  require(manager.snapshot().mq7Raw == 208, "MQ-7 stopped with DHT absent");
  require(pipeline.latest().has_value() && pipeline.peekCandidate().has_value() &&
              pipeline.status().windowRestarts == 0,
          "DHT absence interrupted 50 Hz motion sampling");
}

void testMq7ValidAndInvalidAdc() {
  FakeAnalogInput adc;
  adc.values = {206, 210};
  MQ7AnalogSensor sensor(adc, 1000, 8);
  SensorSnapshot snapshot;
  sensor.begin(0);
  require(!sensor.poll(999, snapshot), "MQ-7 sampled early");
  require(sensor.poll(1000, snapshot) && snapshot.mq7Raw == 208 && adc.reads == 8,
          "MQ-7 oversampled mean is wrong");
  require(!hasFault(snapshot, "mq7ReadFailed") &&
              hasFault(snapshot, "mq7Uncalibrated") &&
              hasFault(snapshot, "mq7HeaterStateUnknown"),
          "valid MQ-7 raw must still be uncalibrated with unknown heater state");

  for (const auto& values : std::vector<std::vector<int>>{{4095}, {0}, {5000}, {-1}}) {
    adc.values = values;
    adc.reads = 0;
    SensorSnapshot rail;
    rail.mq7Raw = 208;
    MQ7AnalogSensor railSensor(adc, 1000, 8);
    railSensor.begin(0);
    railSensor.poll(1000, rail);
    require(!rail.mq7Raw.has_value() && hasFault(rail, "mq7ReadFailed"),
            "invalid MQ-7 ADC value was reported: " + std::to_string(values[0]));
  }
  adc.values = {208};
  adc.succeed = false;
  SensorSnapshot failed;
  MQ7AnalogSensor failing(adc, 1000);
  failing.begin(0);
  failing.poll(1000, failed);
  require(!failed.mq7Raw.has_value(), "failed ADC read produced a value");
}

// ---------------------------------------------------------------- schema 2.0

TelemetryMetadata synchronized(std::uint64_t timestamp = 1775900000000ULL) {
  return TelemetryMetadata{"helmet001_boot_1", "helmet001", timestamp, true,
                           "0.3.0-staging"};
}

SensorSnapshot physicalSnapshot(bool withWindow = true) {
  SensorSnapshot snapshot;  // DHT22 absent
  MotionSample m;
  m.accelXG = 0.04;
  m.accelYG = -0.002;
  m.accelZG = 1.094;
  m.gyroXDegreesPerSecond = 0.012;
  m.gyroYDegreesPerSecond = -0.02;
  m.gyroZDegreesPerSecond = 0.005;
  snapshot.motion = m;
  snapshot.mq7Raw = 208;
  if (withWindow) {
    snapshot.fallWindow = FallWindowEvidence{
        FallFeatures{1.0948, 0.0021, 1.0901, 1.0995, 0.21, 0.08, 0.45, 0.11, 0.35},
        1775899999800ULL};
  }
  snapshot.fallStatus = FallStatus::kNormal;
  return snapshot;
}

void testSchemaTwoExactPayload() {
  TelemetryBuilder builder;
  const auto built = builder.buildIngestion(synchronized(), physicalSnapshot());
  require(built.json.has_value() && built.block == IngestionBlock::kNone,
          "valid physical telemetry was not built");
  const std::string expected =
      "{\"schemaVersion\":\"2.0\",\"eventId\":\"helmet001_boot_1\","
      "\"helmetId\":\"helmet001\",\"deviceTimestamp\":1775900000000,"
      "\"firmwareVersion\":\"0.3.0-staging\","
      "\"accelXG\":0.04,\"accelYG\":-0.002,\"accelZG\":1.094,"
      "\"gyroXDegreesPerSecond\":0.012,\"gyroYDegreesPerSecond\":-0.02,"
      "\"gyroZDegreesPerSecond\":0.005,\"mq7Raw\":208,"
      "\"mq7WarmUp\":true,\"mq135WarmUp\":false,"
      "\"fallFeatures\":{\"acc_mean\":1.0948,\"acc_std\":0.0021,"
      "\"acc_min\":1.0901,\"acc_max\":1.0995,\"gyro_mean\":0.21,"
      "\"gyro_std\":0.08,\"gyro_max\":0.45,\"jerk_mean\":0.11,"
      "\"jerk_max\":0.35},\"samplingRateHz\":50,\"windowSamples\":100,"
      "\"windowEndTimestamp\":1775899999800,"
      "\"sensorFaults\":[\"batteryUnavailable\",\"dhtReadFailed\","
      "\"gpsUnavailable\",\"mq135HeaterStateUnknown\",\"mq135ReadFailed\","
      "\"mq135Uncalibrated\",\"mq7HeaterStateUnknown\",\"mq7Uncalibrated\"]}";
  require(*built.json == expected, "schema 2.0 payload changed:\n" + *built.json);
  require(built.json->size() < 8192, "payload exceeds the 8 KiB limit");
  require(builder.buildIngestion(synchronized(), physicalSnapshot()).json ==
              built.json,
          "payload serialization is not deterministic");
  writeFixture("physical_with_window.json", *built.json);
}

void testNoFabricatedOrForbiddenFields() {
  TelemetryBuilder builder;
  SensorSnapshot empty;  // every sensor absent
  const auto built = builder.buildIngestion(synchronized(), empty);
  require(built.json.has_value(), "fault-only telemetry was not built");
  const auto& json = *built.json;
  for (const auto* forbidden :
       {"temperatureC", "humidityPct", "heatIndexC", "accelXG", "mq7Raw",
        "mq135Raw", "fallFeatures", "samplingRateHz", "windowSamples",
        "windowEndTimestamp", "gasPpm", "gasRaw", "gasWarmUp", "gasAdcVoltage",
        "gasDigitalThreshold", "fallStatus", "location", "batteryPct",
        "severity", "connectivity", "serverReceivedAt", "deviceTimeStatus",
        "gpsStatus", "signature", "secret"}) {
    require(!contains(json, std::string("\"") + forbidden + "\""),
            std::string("fabricated, v1-only or backend-owned field: ") + forbidden);
  }
  for (const auto* fault :
       {"mpuReadFailed", "dhtReadFailed", "mq7ReadFailed", "mq7Uncalibrated",
        "mq7HeaterStateUnknown", "mq135ReadFailed", "fallWindowUnavailable",
        "gpsUnavailable", "batteryUnavailable"}) {
    require(contains(json, std::string("\"") + fault + "\""),
            std::string("absent measurement lacks its fault: ") + fault);
  }
  writeFixture("all_sensors_absent.json", json);

  const auto noWindow =
      builder.buildIngestion(synchronized(), physicalSnapshot(false));
  require(contains(*noWindow.json, "fallWindowUnavailable") &&
              !contains(*noWindow.json, "fallFeatures") &&
              !contains(*noWindow.json, "mpuReadFailed"),
          "missing window must be fallWindowUnavailable, not zeros");
  writeFixture("physical_without_window.json", *noWindow.json);
}

void testPartialOrInvalidWindowDropped() {
  TelemetryBuilder builder;
  auto unsynced = physicalSnapshot();
  unsynced.fallWindow->windowEndTimestampMs.reset();
  auto future = physicalSnapshot();
  future.fallWindow->windowEndTimestampMs = 1775900000001ULL;
  auto inverted = physicalSnapshot();
  inverted.fallWindow->features.accMin = 2.0;
  auto nonFinite = physicalSnapshot();
  nonFinite.fallWindow->features.jerkMax = std::nan("");
  for (const auto& snapshot : {unsynced, future, inverted, nonFinite}) {
    const auto built = builder.buildIngestion(synchronized(), snapshot);
    require(built.json.has_value() && !contains(*built.json, "fallFeatures") &&
                !contains(*built.json, "windowEndTimestamp") &&
                contains(*built.json, "fallWindowUnavailable"),
            "invalid or partial fall window was uploaded");
  }
}

void testIngestionBlocks() {
  TelemetryBuilder builder;
  TelemetryMetadata unsynced = synchronized();
  unsynced.timeSynchronized = false;
  unsynced.deviceTimestampMs.reset();
  require(builder.buildIngestion(unsynced, physicalSnapshot()).block ==
              IngestionBlock::kTimeUnsynchronized,
          "unsynchronized telemetry became uploadable");

  auto fast = physicalSnapshot();
  fast.motion->accelXG = 2.5;
  require(builder.buildIngestion(synchronized(), fast).block ==
              IngestionBlock::kMotionOutsideContractRange,
          "accel outside deployed +/-2 g contract was not blocked");
  fast = physicalSnapshot();
  fast.motion->gyroZDegreesPerSecond = -251;
  require(!builder.buildIngestion(synchronized(), fast).json.has_value(),
          "gyro outside deployed +/-250 deg/s contract was not blocked");
  fast.motion->gyroZDegreesPerSecond = -250;
  require(builder.buildIngestion(synchronized(), fast).json.has_value(),
          "boundary value rejected");
}

void testLocalDiagnosticHonesty() {
  TelemetryBuilder builder;
  const auto record = builder.build(
      TelemetryMetadata{"e_1", "UNPROVISIONED_HELMET", std::nullopt, false,
                        "0.3.0-staging"},
      SensorSnapshot{});
  require(contains(record.json, "\"deviceTimestamp\":null") &&
              contains(record.json, "\"deviceTimeStatus\":\"unsynchronized\"") &&
              contains(record.json, "\"accelXG\":null") &&
              contains(record.json, "\"mq7Raw\":null") &&
              contains(record.json, "\"fallFeatures\":null") &&
              contains(record.json, "not ppm") &&
              !contains(record.json, "ppm\":"),
          "local diagnostics fabricated readings or ppm");
}

// ---------------------------------------------------------------- legacy

void testFallStateTransitionsAndCooldown() {
  FallDetectionEngine engine;
  const auto motion = [](double g, double gyro = 0) {
    MotionSample sample;
    sample.accelZG = g;
    sample.gyroXDegreesPerSecond = gyro;
    return sample;
  };
  require(engine.update(motion(0.3), 0).status == FallStatus::kFreeFallCandidate,
          "free-fall candidate was not entered");
  engine.update(motion(0.3), 200);
  require(engine.update(motion(2.2), 220).status == FallStatus::kImpactDetected,
          "impact phase was not entered");
  require(engine.update(motion(1.0, 1), 240).status ==
              FallStatus::kStillnessCandidate,
          "stillness phase was not entered");
  const auto confirmed = engine.update(motion(1.0, 1), 2240);
  require(confirmed.status == FallStatus::kConfirmed && confirmed.confirmedNow,
          "three-phase fall was not confirmed");
  require(engine.update(motion(0.3), 32259).status == FallStatus::kCooldown,
          "30-second duplicate cooldown ended early");
}

void testStableEventIds() {
  EventIdGenerator generator("HELMET 1", "boot:abc");
  require(generator.next() == "HELMET_1_boot_abc_1" &&
              generator.next() == "HELMET_1_boot_abc_2",
          "event IDs are not normalized and sequential");
}

void testSigningCanonicalPath() {
  const auto canonical = SecureIngestionProtocol::canonicalRequest(
      "helmet001", 1775900000000ULL, "0123456789abcdef0123456789abcdef",
      std::string(64, 'a'));
  require(canonical ==
              "POST\n/ingest/v1/helmets/helmet001/telemetry\n1775900000000\n"
              "0123456789abcdef0123456789abcdef\n" + std::string(64, 'a'),
          "signing must use the canonical ingest path, not the API URL path");
  require(!contains(canonical, "/staging/") && !contains(canonical, "execute-api"),
          "public API Gateway path leaked into the canonical request");
}

void testOfflineQueueBounded() {
  OfflineBuffer buffer(config::kOfflineBufferCapacity);
  for (int i = 0; i < 25; ++i) {
    require(buffer.push({"event-" + std::to_string(i), "{}"}), "push failed");
  }
  require(buffer.size() == config::kOfflineBufferCapacity &&
              buffer.oldest()->eventId == "event-15",
          "offline queue was not bounded oldest-first");
  require(buffer.push({"event-20", "changed"}) &&
              buffer.size() == config::kOfflineBufferCapacity,
          "duplicate event was queued twice");
  require(!buffer.removeOldest("event-16") && buffer.removeOldest("event-15"),
          "only the matching oldest record may be removed");
  require(!buffer.push({"", "{}"}) && !buffer.push({"x", ""}),
          "empty records were queued");
}

void testUnavailableHardwareStaysUnavailable() {
  DisabledTelemetryTransport transport;
  UnavailableGPSManager gps;
  UnavailableBatteryMonitor battery;
  UnconfiguredBuzzerController buzzer;
  UnconfiguredLedController led;
  require(!transport.networkActivityAllowed() && !gps.available() &&
              !battery.available() && !buzzer.activate() && !led.activate(),
          "absent hardware reported availability");
  require(config::kMq7AnalogPin == 34 && !config::kMq7DigitalEnabled &&
              config::kI2cSdaPin == 21 && config::kI2cSclPin == 22 &&
              config::kMpuAddress == 0x68 && config::kMpuIntervalMs == 20 &&
              kFallSamplePeriodMs == 20 &&
              kFallWindowSamples == 100 && kFallMaxSampleLatenessMs < 10,
          "pin or sampling configuration changed");
  require(std::strcmp(config::kSchemaVersion, "2.0") == 0, "schema is not 2.0");
}

}  // namespace

int main(int argc, char** argv) {
  if (argc > 1) gFixtureDirectory = argv[1];
  const std::vector<std::pair<std::string, std::function<void()>>> tests{
      {"MPU6050 WHO_AM_I 0x68 accepted", testMpu6050IdentityAccepted},
      {"MPU6500 WHO_AM_I 0x70 retained", testMpu6500IdentityRetained},
      {"invalid IMU identities rejected", testInvalidIdentitiesRejected},
      {"MPU configuration readback and recovery",
       testMpuConfigurationReadbackAndRecovery},
      {"MPU read-failure recovery and saturation",
       testMpuReadFailureRecoveryAndSaturation},
      {"calibration success", testCalibrationSuccess},
      {"calibration failures bounded", testCalibrationFailuresAreBounded},
      {"nine feature values (deterministic fixture)",
       testFeatureValuesDeterministicFixture},
      {"jerk and first-sample handling", testJerkFirstSampleHandling},
      {"exact 50 Hz / 100-sample window", testExactFiftyHertzHundredSampleWindow},
      {"real-device jitter tolerated", testRealDeviceJitterTolerated},
      {"lateness boundary 9 ms / 10 ms", testLatenessBoundary},
      {"late anchor re-anchors grid", testLateAnchorReanchorsGrid},
      {"19/21 ms rate drift rejected", testRateDriftRejected},
      {"stall restarts honestly", testStallRestartsHonestly},
      {"pipeline tolerates jitter", testPipelineToleratesJitter},
      {"DHT22 not installed is never polled", testDhtNotInstalledIsNeverPolled},
      {"DHT22 failure back-off", testDhtFailureBackoff},
      {"ring order oldest-first", testRingOrderIsOldestFirst},
      {"saturated window unavailable", testSaturatedWindowUnavailable},
      {"calibration gates fall windows", testPipelineCalibrationGatesWindow},
      {"window stride and candidate selection",
       testPipelineWindowsStrideAndCandidate},
      {"saturated windows counted", testPipelineSaturationCounted},
      {"DHT valid and missing", testDhtValidAndMissing},
      {"DHT missing does not stop motion", testDhtMissingDoesNotStopMotion},
      {"MQ-7 valid and invalid ADC", testMq7ValidAndInvalidAdc},
      {"schema 2.0 exact payload", testSchemaTwoExactPayload},
      {"no fabricated or forbidden fields", testNoFabricatedOrForbiddenFields},
      {"partial or invalid window dropped", testPartialOrInvalidWindowDropped},
      {"ingestion blocks", testIngestionBlocks},
      {"local diagnostics honesty", testLocalDiagnosticHonesty},
      {"local fall state machine", testFallStateTransitionsAndCooldown},
      {"stable event IDs", testStableEventIds},
      {"signing canonical path", testSigningCanonicalPath},
      {"offline queue bounded", testOfflineQueueBounded},
      {"unavailable hardware stays unavailable",
       testUnavailableHardwareStaysUnavailable},
  };
  std::size_t passed = 0;
  for (const auto& [name, test] : tests) {
    try {
      test();
      ++passed;
      std::cout << "PASS: " << name << '\n';
    } catch (const std::exception& error) {
      std::cerr << "FAIL: " << name << ": " << error.what() << '\n';
      return 1;
    }
  }
  std::cout << passed << " host tests passed\n";
  return 0;
}
