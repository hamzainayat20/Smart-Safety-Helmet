#include "smart_safety/MPU6500Sensor.h"

namespace smart_safety {
namespace {

constexpr std::uint8_t kWhoAmIRegister = 0x75;
constexpr std::uint8_t kPowerManagementRegister = 0x6B;
constexpr std::uint8_t kFilterConfigRegister = 0x1A;
constexpr std::uint8_t kGyroConfigRegister = 0x1B;
constexpr std::uint8_t kAccelConfigRegister = 0x1C;
constexpr std::uint8_t kDataStartRegister = 0x3B;
constexpr std::uint8_t kVerifiedMpu6500WhoAmI = 0x70;

}  // namespace

MPU6500Sensor::MPU6500Sensor(I2cBus& bus, std::uint8_t address,
                             std::uint32_t sampleIntervalMs,
                             std::uint32_t wakeDelayMs,
                             std::uint32_t timeoutMs)
    : bus_(bus),
      address_(address),
      wakeDelayMs_(wakeDelayMs),
      timeoutMs_(timeoutMs),
      schedule_(sampleIntervalMs) {}

bool MPU6500Sensor::begin(std::uint32_t nowMs, SensorSnapshot& snapshot) {
  state_ = InitializationState::kNotStarted;
  detectedWhoAmI_ = 0;
  markUnavailable(snapshot);
  bus_.setTimeoutMs(timeoutMs_);

  if (!bus_.readRegister(address_, kWhoAmIRegister, detectedWhoAmI_) ||
      detectedWhoAmI_ != kVerifiedMpu6500WhoAmI ||
      !bus_.writeRegister(address_, kPowerManagementRegister, 0x00)) {
    state_ = InitializationState::kFailed;
    return false;
  }

  wakeStartedAtMs_ = nowMs;
  state_ = InitializationState::kWaking;
  schedule_.reset(nowMs);
  return true;
}

bool MPU6500Sensor::poll(std::uint32_t nowMs, SensorSnapshot& snapshot) {
  if (state_ == InitializationState::kWaking) {
    return completeConfiguration(nowMs, snapshot);
  }
  if (state_ != InitializationState::kReady || !schedule_.due(nowMs)) {
    return false;
  }

  MotionSample sample{};
  if (!readMotion(sample) || !sample.finite()) {
    markUnavailable(snapshot);
    return true;
  }
  snapshot.motion = sample;
  snapshot.removeFault(SensorFault::kMpuReadFailed);
  return true;
}

bool MPU6500Sensor::completeConfiguration(std::uint32_t nowMs,
                                          SensorSnapshot& snapshot) {
  if (static_cast<std::uint32_t>(nowMs - wakeStartedAtMs_) < wakeDelayMs_) {
    return false;
  }

  // 0x00 preserves verified ±250 degrees/second and ±2 g ranges.
  const bool configured =
      bus_.writeRegister(address_, kFilterConfigRegister, 0x03) &&
      bus_.writeRegister(address_, kGyroConfigRegister, 0x00) &&
      bus_.writeRegister(address_, kAccelConfigRegister, 0x00);
  if (!configured) {
    state_ = InitializationState::kFailed;
    markUnavailable(snapshot);
    return false;
  }

  state_ = InitializationState::kReady;
  schedule_.reset(nowMs);
  snapshot.removeFault(SensorFault::kMpuReadFailed);
  return false;
}

bool MPU6500Sensor::readMotion(MotionSample& sample) {
  std::uint8_t data[14]{};
  if (!bus_.readRegisters(address_, kDataStartRegister, data, sizeof(data))) {
    return false;
  }
  sample.accelXG = signedWord(&data[0]) / 16384.0;
  sample.accelYG = signedWord(&data[2]) / 16384.0;
  sample.accelZG = signedWord(&data[4]) / 16384.0;
  sample.gyroXDegreesPerSecond = signedWord(&data[8]) / 131.0;
  sample.gyroYDegreesPerSecond = signedWord(&data[10]) / 131.0;
  sample.gyroZDegreesPerSecond = signedWord(&data[12]) / 131.0;
  return true;
}

void MPU6500Sensor::markUnavailable(SensorSnapshot& snapshot) {
  snapshot.motion.reset();
  snapshot.addFault(SensorFault::kMpuReadFailed);
}

std::int16_t MPU6500Sensor::signedWord(const std::uint8_t* bytes) {
  const auto value = static_cast<std::uint16_t>(bytes[0]) << 8U |
                     static_cast<std::uint16_t>(bytes[1]);
  return static_cast<std::int16_t>(value);
}

bool MPU6500Sensor::initialized() const {
  return state_ == InitializationState::kReady;
}

std::uint8_t MPU6500Sensor::detectedWhoAmI() const {
  return detectedWhoAmI_;
}

}  // namespace smart_safety
