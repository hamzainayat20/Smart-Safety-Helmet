#include "smart_safety/SensorManager.h"

namespace smart_safety {

SensorManager::SensorManager(DHT22Sensor& dht22, MQ7AnalogSensor& mq7)
    : dht22_(dht22), mq7_(mq7) {}

void SensorManager::begin(std::uint32_t nowMs) {
  dht22_.begin(nowMs);
  mq7_.begin(nowMs);
}

SensorPollResult SensorManager::poll(std::uint32_t nowMs) {
  SensorPollResult result;
  result.dhtUpdated = dht22_.poll(nowMs, snapshot_);
  result.mq7Updated = mq7_.poll(nowMs, snapshot_);
  return result;
}

SensorSnapshot& SensorManager::snapshot() { return snapshot_; }

const SensorSnapshot& SensorManager::snapshot() const { return snapshot_; }

}  // namespace smart_safety
