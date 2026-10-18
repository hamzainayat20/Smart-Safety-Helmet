#pragma once

#include <cstdint>

#include "smart_safety/HardwareInterfaces.h"
#include "smart_safety/NonBlockingScheduler.h"
#include "smart_safety/SensorTypes.h"

namespace smart_safety {

class MPU6500Sensor {
 public:
  MPU6500Sensor(I2cBus& bus, std::uint8_t address,
                std::uint32_t sampleIntervalMs,
                std::uint32_t wakeDelayMs,
                std::uint32_t timeoutMs);

  bool begin(std::uint32_t nowMs, SensorSnapshot& snapshot);
  bool poll(std::uint32_t nowMs, SensorSnapshot& snapshot);
  bool initialized() const;
  std::uint8_t detectedWhoAmI() const;

 private:
  enum class InitializationState { kNotStarted, kWaking, kReady, kFailed };

  bool completeConfiguration(std::uint32_t nowMs,
                             SensorSnapshot& snapshot);
  bool readMotion(MotionSample& sample);
  void markUnavailable(SensorSnapshot& snapshot);
  static std::int16_t signedWord(const std::uint8_t* bytes);

  I2cBus& bus_;
  std::uint8_t address_;
  std::uint32_t wakeDelayMs_;
  std::uint32_t timeoutMs_;
  std::uint32_t wakeStartedAtMs_{0};
  PeriodicTask schedule_;
  InitializationState state_{InitializationState::kNotStarted};
  std::uint8_t detectedWhoAmI_{0};
};

}  // namespace smart_safety
