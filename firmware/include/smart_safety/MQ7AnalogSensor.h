#pragma once

#include <cstdint>

#include "smart_safety/HardwareInterfaces.h"
#include "smart_safety/NonBlockingScheduler.h"
#include "smart_safety/SensorTypes.h"

namespace smart_safety {

inline constexpr int kAdcMaxRaw = 4095;

// MQ-7 analog output (AO) through a 10 k / 20 k divider into GPIO34.
// Reports the raw ADC count only. It does not, and must not, convert to CO
// ppm: the sensor is uncalibrated and its heater cycle is not controlled.
// Readings at either ADC rail (0 or 4095) are rejected as mq7ReadFailed:
// 0 usually means a disconnected/shorted signal and 4095 means the input is
// at or above the ADC limit, which must be investigated before trusting it.
class MQ7AnalogSensor {
 public:
  MQ7AnalogSensor(AnalogInput& input, std::uint32_t intervalMs,
                  std::uint8_t oversample = 8);

  void begin(std::uint32_t nowMs);
  // Returns true when a read was attempted.
  bool poll(std::uint32_t nowMs, SensorSnapshot& snapshot);
  bool lastReadAtRail() const { return lastAtRail_; }

 private:
  AnalogInput& input_;
  PeriodicTask schedule_;
  std::uint8_t oversample_;
  bool lastAtRail_{false};
};

}  // namespace smart_safety
