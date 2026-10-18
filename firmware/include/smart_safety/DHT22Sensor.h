#pragma once

#include <cstdint>

#include "smart_safety/HardwareInterfaces.h"
#include "smart_safety/NonBlockingScheduler.h"
#include "smart_safety/SensorTypes.h"

namespace smart_safety {

class DHT22Sensor {
 public:
  DHT22Sensor(Dht22Reader& reader, std::uint32_t intervalMs);

  void begin(std::uint32_t nowMs);
  bool poll(std::uint32_t nowMs, SensorSnapshot& snapshot);

 private:
  void markUnavailable(SensorSnapshot& snapshot) const;

  Dht22Reader& reader_;
  PeriodicTask schedule_;
};

}  // namespace smart_safety

