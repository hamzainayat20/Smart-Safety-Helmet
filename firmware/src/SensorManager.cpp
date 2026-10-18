#include "smart_safety/SensorManager.h"

namespace smart_safety {

SensorManager::SensorManager(DHT22Sensor& dht22, MPU6500Sensor& mpu6500)
    : dht22_(dht22), mpu6500_(mpu6500) {}

void SensorManager::begin(std::uint32_t nowMs) {
  dht22_.begin(nowMs);
  mpu6500_.begin(nowMs, snapshot_);
}

SensorPollResult SensorManager::poll(std::uint32_t nowMs) {
  return SensorPollResult{dht22_.poll(nowMs, snapshot_),
                          mpu6500_.poll(nowMs, snapshot_)};
}

SensorSnapshot& SensorManager::snapshot() { return snapshot_; }

const SensorSnapshot& SensorManager::snapshot() const { return snapshot_; }

}  // namespace smart_safety

