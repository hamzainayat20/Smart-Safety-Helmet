#pragma once

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <optional>
#include <vector>

namespace smart_safety {

enum class SensorFault {
  kMpuReadFailed,
  kDhtReadFailed,
  kMq7ReadFailed,
  kMq7Uncalibrated,
  kMq7HeaterStateUnknown,
  kGpsUnavailable,
  kBatteryUnavailable,
};

enum class FallStatus {
  kNotEvaluated,
  kNormal,
  kFreeFallCandidate,
  kImpactDetected,
  kStillnessCandidate,
  kConfirmed,
  kCooldown,
};

inline const char* sensorFaultName(SensorFault fault) {
  switch (fault) {
    case SensorFault::kMpuReadFailed:
      return "mpuReadFailed";
    case SensorFault::kDhtReadFailed:
      return "dhtReadFailed";
    case SensorFault::kMq7ReadFailed:
      return "mq7ReadFailed";
    case SensorFault::kMq7Uncalibrated:
      return "mq7Uncalibrated";
    case SensorFault::kMq7HeaterStateUnknown:
      return "mq7HeaterStateUnknown";
    case SensorFault::kGpsUnavailable:
      return "gpsUnavailable";
    case SensorFault::kBatteryUnavailable:
      return "batteryUnavailable";
  }
  return "unknownSensorFault";
}

inline const char* fallStatusName(FallStatus status) {
  switch (status) {
    case FallStatus::kNotEvaluated:
      return "notEvaluated";
    case FallStatus::kNormal:
      return "normal";
    case FallStatus::kFreeFallCandidate:
      return "freeFallCandidate";
    case FallStatus::kImpactDetected:
      return "impactDetected";
    case FallStatus::kStillnessCandidate:
      return "stillnessCandidate";
    case FallStatus::kConfirmed:
      return "confirmed";
    case FallStatus::kCooldown:
      return "cooldown";
  }
  return "notEvaluated";
}

struct MotionSample {
  double accelXG{0};
  double accelYG{0};
  double accelZG{0};
  double gyroXDegreesPerSecond{0};
  double gyroYDegreesPerSecond{0};
  double gyroZDegreesPerSecond{0};

  bool finite() const {
    return std::isfinite(accelXG) && std::isfinite(accelYG) &&
           std::isfinite(accelZG) &&
           std::isfinite(gyroXDegreesPerSecond) &&
           std::isfinite(gyroYDegreesPerSecond) &&
           std::isfinite(gyroZDegreesPerSecond);
  }

  double accelerationMagnitudeG() const {
    return std::sqrt(accelXG * accelXG + accelYG * accelYG +
                     accelZG * accelZG);
  }

  double gyroMagnitudeDegreesPerSecond() const {
    return std::sqrt(gyroXDegreesPerSecond * gyroXDegreesPerSecond +
                     gyroYDegreesPerSecond * gyroYDegreesPerSecond +
                     gyroZDegreesPerSecond * gyroZDegreesPerSecond);
  }
};

struct SensorSnapshot {
  std::optional<double> temperatureC;
  std::optional<double> humidityPct;
  std::optional<double> heatIndexC;
  std::optional<MotionSample> motion;

  // MQ-7 remains unavailable and diagnostic-only until its electrical design is
  // verified. These values are deliberately nullable rather than fabricated.
  std::optional<int> gasRaw;
  std::optional<double> gasAdcVoltage;
  std::optional<double> gasSensorVoltage;
  std::optional<bool> gasDigitalThreshold;
  bool gasWarmUp{true};

  FallStatus fallStatus{FallStatus::kNotEvaluated};
  std::vector<SensorFault> sensorFaults{
      SensorFault::kMq7ReadFailed,
      SensorFault::kMq7Uncalibrated,
      SensorFault::kMq7HeaterStateUnknown,
      SensorFault::kGpsUnavailable,
      SensorFault::kBatteryUnavailable,
  };

  void addFault(SensorFault fault) {
    if (std::find(sensorFaults.begin(), sensorFaults.end(), fault) ==
        sensorFaults.end()) {
      sensorFaults.push_back(fault);
    }
  }

  void removeFault(SensorFault fault) {
    sensorFaults.erase(
        std::remove(sensorFaults.begin(), sensorFaults.end(), fault),
        sensorFaults.end());
  }
};

}  // namespace smart_safety

