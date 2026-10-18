#pragma once

#include <cstdint>

#include "smart_safety/DHT22Sensor.h"
#include "smart_safety/MPU6500Sensor.h"
#include "smart_safety/SensorTypes.h"

namespace smart_safety {

struct SensorPollResult {
  bool dhtUpdated{false};
  bool mpuUpdated{false};
};

class SensorManager {
 public:
  SensorManager(DHT22Sensor& dht22, MPU6500Sensor& mpu6500);

  void begin(std::uint32_t nowMs);
  SensorPollResult poll(std::uint32_t nowMs);
  SensorSnapshot& snapshot();
  const SensorSnapshot& snapshot() const;

 private:
  DHT22Sensor& dht22_;
  MPU6500Sensor& mpu6500_;
  SensorSnapshot snapshot_{};
};

}  // namespace smart_safety

