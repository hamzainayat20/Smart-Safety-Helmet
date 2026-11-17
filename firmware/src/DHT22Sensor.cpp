#include "smart_safety/DHT22Sensor.h"

#include <cmath>

namespace smart_safety {

DHT22Sensor::DHT22Sensor(Dht22Reader& reader, std::uint32_t intervalMs,
                         bool installed, std::uint32_t failureBackoffMs,
                         std::uint8_t failuresBeforeBackoff)
    : reader_(reader),
      schedule_(intervalMs),
      installed_(installed),
      failureBackoffMs_(failureBackoffMs),
      failuresBeforeBackoff_(failuresBeforeBackoff == 0 ? 1
                                                        : failuresBeforeBackoff) {}

void DHT22Sensor::begin(std::uint32_t nowMs) { schedule_.reset(nowMs); }

bool DHT22Sensor::poll(std::uint32_t nowMs, SensorSnapshot& snapshot) {
  if (!installed_) {
    markUnavailable(snapshot);
    return false;
  }
  if (!schedule_.due(nowMs)) return false;
  if (backingOff_ &&
      static_cast<std::uint32_t>(nowMs - backoffStartedMs_) < failureBackoffMs_) {
    return false;
  }

  Dht22RawReading reading{};
  if (!reader_.read(reading) || !std::isfinite(reading.temperatureC) ||
      !std::isfinite(reading.humidityPct) ||
      !std::isfinite(reading.heatIndexC) || reading.temperatureC < -40.0 ||
      reading.temperatureC > 80.0 || reading.humidityPct < 0.0 ||
      reading.humidityPct > 100.0) {
    markUnavailable(snapshot);
    if (consecutiveFailures_ < 255) ++consecutiveFailures_;
    if (consecutiveFailures_ >= failuresBeforeBackoff_) {
      backingOff_ = true;
      backoffStartedMs_ = nowMs;
    }
    return true;
  }
  consecutiveFailures_ = 0;
  backingOff_ = false;

  snapshot.temperatureC = reading.temperatureC;
  snapshot.humidityPct = reading.humidityPct;
  snapshot.heatIndexC = reading.heatIndexC;
  return true;
}

void DHT22Sensor::markUnavailable(SensorSnapshot& snapshot) const {
  snapshot.temperatureC.reset();
  snapshot.humidityPct.reset();
  snapshot.heatIndexC.reset();
  // dhtReadFailed is derived from the absent values by deriveSensorFaults().
}

}  // namespace smart_safety

