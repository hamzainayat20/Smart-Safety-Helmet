#pragma once

#include <cstdint>

#include "smart_safety/DHT22Sensor.h"
#include "smart_safety/MQ7AnalogSensor.h"
#include "smart_safety/SensorTypes.h"

namespace smart_safety {

struct SensorPollResult {
  bool dhtUpdated{false};
  bool mq7Updated{false};
};

// Slow environmental sensors polled from loop(). Motion is sampled
// independently (MotionPipeline in its own task), so a slow or failing DHT22
// or MQ-7 read can never delay or stop 50 Hz motion sampling.
class SensorManager {
 public:
  SensorManager(DHT22Sensor& dht22, MQ7AnalogSensor& mq7);

  void begin(std::uint32_t nowMs);
  SensorPollResult poll(std::uint32_t nowMs);
  SensorSnapshot& snapshot();
  const SensorSnapshot& snapshot() const;

 private:
  DHT22Sensor& dht22_;
  MQ7AnalogSensor& mq7_;
  SensorSnapshot snapshot_{};
};

}  // namespace smart_safety
