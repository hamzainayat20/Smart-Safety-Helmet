#include "smart_safety/MQ135AnalogSensor.h"

namespace smart_safety {

MQ135AnalogSensor::MQ135AnalogSensor(AnalogInput& input,
                                     std::uint32_t intervalMs,
                                     std::uint8_t oversample)
    : input_(input),
      schedule_(intervalMs),
      oversample_(oversample == 0 ? 1 : oversample) {}

void MQ135AnalogSensor::begin(std::uint32_t nowMs) { schedule_.reset(nowMs); }

bool MQ135AnalogSensor::poll(std::uint32_t nowMs, SensorSnapshot& snapshot) {
  if (!schedule_.due(nowMs)) return false;
  lastAtRail_ = false;
  long sum = 0;
  for (std::uint8_t index = 0; index < oversample_; ++index) {
    int raw = -1;
    if (!input_.read(raw) || raw < 0 || raw > kAdcMaxRaw) {
      snapshot.mq135Raw.reset();
      return true;
    }
    sum += raw;
  }
  // Rounded integer mean of the oversampled conversions.
  const int average =
      static_cast<int>((sum + oversample_ / 2) / static_cast<long>(oversample_));
  if (average <= 0 || average >= kAdcMaxRaw) {
    lastAtRail_ = true;
    snapshot.mq135Raw.reset();
    return true;
  }
  snapshot.mq135Raw = average;
  return true;
}

}  // namespace smart_safety
