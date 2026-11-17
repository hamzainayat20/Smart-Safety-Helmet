#pragma once

#include <cstdint>

#include "smart_safety/HardwareInterfaces.h"
#include "smart_safety/NonBlockingScheduler.h"
#include "smart_safety/SensorTypes.h"

namespace smart_safety {

// The Adafruit DHT driver disables interrupts on the calling core while it
// waits for the sensor. With no sensor attached that wait runs to the
// library's timeout, which on the ESP32 is far longer than its nominal 1 ms
// and starves the 50 Hz motion task. Therefore:
//  - installed == false: the bus is never touched; values stay absent and
//    dhtReadFailed is reported.
//  - after `failuresBeforeBackoff` consecutive failures, reads are attempted
//    only every `failureBackoffMs` until one succeeds.
class DHT22Sensor {
 public:
  DHT22Sensor(Dht22Reader& reader, std::uint32_t intervalMs,
              bool installed = true, std::uint32_t failureBackoffMs = 60000,
              std::uint8_t failuresBeforeBackoff = 3);

  void begin(std::uint32_t nowMs);
  // Returns true when a read was attempted.
  bool poll(std::uint32_t nowMs, SensorSnapshot& snapshot);
  bool installed() const { return installed_; }
  bool backingOff() const { return backingOff_; }

 private:
  void markUnavailable(SensorSnapshot& snapshot) const;

  Dht22Reader& reader_;
  PeriodicTask schedule_;
  bool installed_;
  std::uint32_t failureBackoffMs_;
  std::uint8_t failuresBeforeBackoff_;
  std::uint8_t consecutiveFailures_{0};
  bool backingOff_{false};
  std::uint32_t backoffStartedMs_{0};
};

}  // namespace smart_safety
