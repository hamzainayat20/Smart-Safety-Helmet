#include "smart_safety/MpuSensor.h"

#include <limits>

namespace smart_safety {
namespace {

constexpr std::uint8_t kSampleRateDividerRegister = 0x19;
constexpr std::uint8_t kConfigRegister = 0x1A;
constexpr std::uint8_t kGyroConfigRegister = 0x1B;
constexpr std::uint8_t kAccelConfigRegister = 0x1C;
constexpr std::uint8_t kAccelConfig2Register = 0x1D;  // MPU6500 only
constexpr std::uint8_t kDataStartRegister = 0x3B;
constexpr std::uint8_t kPowerManagementRegister = 0x6B;
constexpr std::uint8_t kWhoAmIRegister = 0x75;
// CLKSEL = 1: PLL with X-axis gyro reference, recommended over the internal
// oscillator by the datasheets of both parts. SLEEP bit cleared.
constexpr std::uint8_t kPowerOnPllClock = 0x01;

}  // namespace

MpuSensor::MpuSensor(I2cBus& bus, std::uint8_t address,
                     std::uint32_t wakeDelayMs, std::uint32_t timeoutMs,
                     std::uint32_t reinitIntervalMs,
                     std::uint8_t maxConsecutiveFailures)
    : bus_(bus),
      address_(address),
      wakeDelayMs_(wakeDelayMs),
      timeoutMs_(timeoutMs),
      reinitIntervalMs_(reinitIntervalMs),
      maxConsecutiveFailures_(maxConsecutiveFailures == 0
                                  ? 1
                                  : maxConsecutiveFailures) {}

ImuModel MpuSensor::identify(std::uint8_t whoAmI) {
  switch (whoAmI) {
    case kMpu6050WhoAmI:
      return ImuModel::kMpu6050;
    case kMpu6500WhoAmI:
      return ImuModel::kMpu6500;
    default:
      return ImuModel::kUnknown;
  }
}

const char* MpuSensor::modelName(ImuModel model) {
  switch (model) {
    case ImuModel::kMpu6050:
      return "MPU6050";
    case ImuModel::kMpu6500:
      return "MPU6500";
    case ImuModel::kUnknown:
      return "unknown";
  }
  return "unknown";
}

bool MpuSensor::begin(std::uint32_t nowMs) {
  model_ = ImuModel::kUnknown;
  whoAmI_ = 0;
  consecutiveFailures_ = 0;
  bus_.setTimeoutMs(timeoutMs_);
  if (!bus_.readRegister(address_, kWhoAmIRegister, whoAmI_)) {
    enterBackoff(nowMs);
    return false;
  }
  model_ = identify(whoAmI_);
  if (model_ == ImuModel::kUnknown ||
      !bus_.writeRegister(address_, kPowerManagementRegister,
                          kPowerOnPllClock)) {
    enterBackoff(nowMs);
    return false;
  }
  state_ = State::kWaking;
  stateSinceMs_ = nowMs;
  return true;
}

ImuReadResult MpuSensor::read(std::uint32_t nowMs, RawImuReading& output) {
  const auto elapsed = static_cast<std::uint32_t>(nowMs - stateSinceMs_);
  switch (state_) {
    case State::kNotStarted:
      begin(nowMs);
      return ImuReadResult::kInitializing;
    case State::kBackoff:
      if (elapsed >= reinitIntervalMs_) {
        ++reinitializations_;
        begin(nowMs);
      }
      return ImuReadResult::kUnavailable;
    case State::kWaking:
      if (elapsed < wakeDelayMs_) return ImuReadResult::kInitializing;
      if (!configure()) {
        enterBackoff(nowMs);
        return ImuReadResult::kUnavailable;
      }
      state_ = State::kReady;
      stateSinceMs_ = nowMs;
      return ImuReadResult::kInitializing;
    case State::kReady:
      break;
  }

  std::uint8_t data[14]{};
  if (!bus_.readRegisters(address_, kDataStartRegister, data, sizeof(data))) {
    if (++consecutiveFailures_ >= maxConsecutiveFailures_) enterBackoff(nowMs);
    return ImuReadResult::kReadFailed;
  }
  consecutiveFailures_ = 0;

  const std::int16_t raw[6]{signedWord(&data[0]),  signedWord(&data[2]),
                            signedWord(&data[4]),  signedWord(&data[8]),
                            signedWord(&data[10]), signedWord(&data[12])};
  output.saturated = false;
  for (const auto value : raw) {
    if (value == std::numeric_limits<std::int16_t>::max() ||
        value == std::numeric_limits<std::int16_t>::min()) {
      output.saturated = true;
    }
  }
  output.sample.accelXG = raw[0] / kAccelLsbPerG;
  output.sample.accelYG = raw[1] / kAccelLsbPerG;
  output.sample.accelZG = raw[2] / kAccelLsbPerG;
  output.sample.gyroXDegreesPerSecond = raw[3] / kGyroLsbPerDps;
  output.sample.gyroYDegreesPerSecond = raw[4] / kGyroLsbPerDps;
  output.sample.gyroZDegreesPerSecond = raw[5] / kGyroLsbPerDps;
  return ImuReadResult::kSample;
}

bool MpuSensor::configure() {
  bool configured =
      writeVerified(kSampleRateDividerRegister, kSampleRateDivider, 0xFF) &&
      writeVerified(kConfigRegister, kDlpfConfig, 0x07) &&
      writeVerified(kGyroConfigRegister, kGyroConfigFs2000, 0x18) &&
      writeVerified(kAccelConfigRegister, kAccelConfigFs16g, 0x18);
  if (configured && model_ == ImuModel::kMpu6500) {
    // A_DLPF_CFG 4 (~20 Hz) so accel bandwidth matches the gyro on MPU6500.
    configured = writeVerified(kAccelConfig2Register, kDlpfConfig, 0x0F);
  }
  return configured;
}

bool MpuSensor::writeVerified(std::uint8_t reg, std::uint8_t value,
                              std::uint8_t mask) {
  std::uint8_t readBack = 0;
  return bus_.writeRegister(address_, reg, value) &&
         bus_.readRegister(address_, reg, readBack) &&
         (readBack & mask) == (value & mask);
}

void MpuSensor::enterBackoff(std::uint32_t nowMs) {
  state_ = State::kBackoff;
  stateSinceMs_ = nowMs;
  consecutiveFailures_ = 0;
}

std::int16_t MpuSensor::signedWord(const std::uint8_t* bytes) {
  const auto value = static_cast<std::uint16_t>(
      static_cast<std::uint16_t>(bytes[0]) << 8U |
      static_cast<std::uint16_t>(bytes[1]));
  return static_cast<std::int16_t>(value);
}

}  // namespace smart_safety
