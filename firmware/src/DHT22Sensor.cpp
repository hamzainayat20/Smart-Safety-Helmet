#include "smart_safety/DHT22Sensor.h"

#include <cmath>

namespace smart_safety {

DHT22Sensor::DHT22Sensor(Dht22Reader& reader, std::uint32_t intervalMs)
    : reader_(reader), schedule_(intervalMs) {}

void DHT22Sensor::begin(std::uint32_t nowMs) { schedule_.reset(nowMs); }

bool DHT22Sensor::poll(std::uint32_t nowMs, SensorSnapshot& snapshot) {
  if (!schedule_.due(nowMs)) return false;

  Dht22RawReading reading{};
  if (!reader_.read(reading) || !std::isfinite(reading.temperatureC) ||
      !std::isfinite(reading.humidityPct) ||
      !std::isfinite(reading.heatIndexC) || reading.temperatureC < -40.0 ||
      reading.temperatureC > 80.0 || reading.humidityPct < 0.0 ||
      reading.humidityPct > 100.0) {
    markUnavailable(snapshot);
    return true;
  }

  snapshot.temperatureC = reading.temperatureC;
  snapshot.humidityPct = reading.humidityPct;
  snapshot.heatIndexC = reading.heatIndexC;
  snapshot.removeFault(SensorFault::kDhtReadFailed);
  return true;
}

void DHT22Sensor::markUnavailable(SensorSnapshot& snapshot) const {
  snapshot.temperatureC.reset();
  snapshot.humidityPct.reset();
  snapshot.heatIndexC.reset();
  snapshot.addFault(SensorFault::kDhtReadFailed);
}

}  // namespace smart_safety

