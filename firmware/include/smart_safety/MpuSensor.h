#pragma once

#include <cstdint>

#include "smart_safety/HardwareInterfaces.h"
#include "smart_safety/SensorTypes.h"

namespace smart_safety {

// Only identities verified on project hardware are accepted. Clones that
// report other WHO_AM_I values (0x71, 0x72, 0x98, ...) are rejected rather
// than guessed at, because their register maps and scaling are unverified.
enum class ImuModel { kUnknown, kMpu6050, kMpu6500 };

inline constexpr std::uint8_t kMpu6050WhoAmI = 0x68;
inline constexpr std::uint8_t kMpu6500WhoAmI = 0x70;

// Configured full-scale ranges. Wide ranges are required because the fall
// model was trained on peaks up to about 7 g and 740 deg/s; the previous
// +/-2 g / +/-250 deg/s setting would clip exactly the samples that matter.
inline constexpr double kAccelLsbPerG = 2048.0;     // +/-16 g
inline constexpr double kGyroLsbPerDps = 16.4;      // +/-2000 deg/s
inline constexpr std::uint8_t kAccelConfigFs16g = 0x18;
inline constexpr std::uint8_t kGyroConfigFs2000 = 0x18;
// DLPF_CFG 4: about 21 Hz accel / 20 Hz gyro bandwidth, the closest
// anti-alias setting below the 25 Hz Nyquist limit of 50 Hz sampling.
inline constexpr std::uint8_t kDlpfConfig = 0x04;
// SMPLRT_DIV 19: 1 kHz internal rate / (1 + 19) = 50 Hz output data rate.
inline constexpr std::uint8_t kSampleRateDivider = 19;

struct RawImuReading {
  MotionSample sample{};  // physical units, uncalibrated
  bool saturated{false};  // any axis at the int16 rail: value is clipped
};

enum class ImuReadResult {
  kSample,        // reading is valid
  kInitializing,  // wake delay or configuration still in progress
  kReadFailed,    // this read failed; driver keeps trying
  kUnavailable,   // driver is in back-off after repeated failures
};

class MpuSensor {
 public:
  MpuSensor(I2cBus& bus, std::uint8_t address, std::uint32_t wakeDelayMs,
            std::uint32_t timeoutMs, std::uint32_t reinitIntervalMs = 1000,
            std::uint8_t maxConsecutiveFailures = 5);

  static ImuModel identify(std::uint8_t whoAmI);
  static const char* modelName(ImuModel model);

  // Starts identification and wake-up. Never blocks on the wake delay.
  bool begin(std::uint32_t nowMs);
  // Call once per 50 Hz tick. All waits are expressed as state, not delays.
  ImuReadResult read(std::uint32_t nowMs, RawImuReading& output);

  bool ready() const { return state_ == State::kReady; }
  // True only after a failure (bad identity, configuration or reads), not
  // during the normal wake-up delay.
  bool backingOff() const { return state_ == State::kBackoff; }
  ImuModel model() const { return model_; }
  std::uint8_t detectedWhoAmI() const { return whoAmI_; }
  std::uint32_t reinitializations() const { return reinitializations_; }

 private:
  enum class State { kNotStarted, kWaking, kReady, kBackoff };

  bool configure();
  bool writeVerified(std::uint8_t reg, std::uint8_t value, std::uint8_t mask);
  void enterBackoff(std::uint32_t nowMs);
  static std::int16_t signedWord(const std::uint8_t* bytes);

  I2cBus& bus_;
  std::uint8_t address_;
  std::uint32_t wakeDelayMs_;
  std::uint32_t timeoutMs_;
  std::uint32_t reinitIntervalMs_;
  std::uint8_t maxConsecutiveFailures_;
  State state_{State::kNotStarted};
  ImuModel model_{ImuModel::kUnknown};
  std::uint8_t whoAmI_{0};
  std::uint32_t stateSinceMs_{0};
  std::uint8_t consecutiveFailures_{0};
  std::uint32_t reinitializations_{0};
};

}  // namespace smart_safety
