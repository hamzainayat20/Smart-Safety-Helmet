#pragma once

#include <cstdint>

#include "smart_safety/DHT22Sensor.h"
#include "smart_safety/MQ135AnalogSensor.h"
#include "smart_safety/MQ7AnalogSensor.h"
#include "smart_safety/SensorTypes.h"

namespace smart_safety {

struct SensorPollResult {
  bool dhtUpdated{false};
  bool mq7Updated{false};
  bool mq135Updated{false};
};

// Slow environmental sensors polled from loop(). Motion is sampled
// independently (MotionPipeline in its own task), so a slow or failing DHT22,
// MQ-7 or MQ-135 read can never delay or stop 50 Hz motion sampling.
// The MQ-135 is optional: with no sensor (nullptr) it is never polled and its
// absence is reported as mq135ReadFailed.
class SensorManager {
 public:
  SensorManager(DHT22Sensor& dht22, MQ7AnalogSensor& mq7,
                MQ135AnalogSensor* mq135 = nullptr);

  void begin(std::uint32_t nowMs);
  SensorPollResult poll(std::uint32_t nowMs);
  SensorSnapshot& snapshot();
  const SensorSnapshot& snapshot() const;

 private:
  DHT22Sensor& dht22_;
  MQ7AnalogSensor& mq7_;
  MQ135AnalogSensor* mq135_;
  SensorSnapshot snapshot_{};
};

}  // namespace smart_safety
