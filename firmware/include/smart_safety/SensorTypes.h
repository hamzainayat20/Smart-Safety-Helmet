#pragma once

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <optional>
#include <string>
#include <vector>

#include "smart_safety/FallFeatures.h"

namespace smart_safety {

// Telemetry schema 2.0 fault vocabulary. Names must match
// functions/src/telemetry_contract.js and inference_service/app/schemas.py.
enum class SensorFault {
  kMpuReadFailed,
  kDhtReadFailed,
  kMq7ReadFailed,
  kMq7Uncalibrated,
  kMq7HeaterStateUnknown,
  kMq135ReadFailed,
  kMq135Uncalibrated,
  kMq135HeaterStateUnknown,
  kFallWindowUnavailable,
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
    case SensorFault::kMq135ReadFailed:
      return "mq135ReadFailed";
    case SensorFault::kMq135Uncalibrated:
      return "mq135Uncalibrated";
    case SensorFault::kMq135HeaterStateUnknown:
      return "mq135HeaterStateUnknown";
    case SensorFault::kFallWindowUnavailable:
      return "fallWindowUnavailable";
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

// A complete, validated 100-sample fall window. windowEndTimestampMs is UTC
// epoch milliseconds and is present only when device time is synchronized.
struct FallWindowEvidence {
  FallFeatures features{};
  std::optional<std::uint64_t> windowEndTimestampMs;
};

// Everything here is either a real measurement or absent. There are no
// placeholder values: a missing measurement is represented only by absence,
// and its fault is derived from that absence by deriveSensorFaults().
struct SensorSnapshot {
  std::optional<double> temperatureC;
  std::optional<double> humidityPct;
  std::optional<double> heatIndexC;
  std::optional<MotionSample> motion;  // gyro is offset-corrected when present
  std::optional<int> mq7Raw;           // raw 12-bit ADC count, never ppm
  std::optional<FallWindowEvidence> fallWindow;
  FallStatus fallStatus{FallStatus::kNotEvaluated};  // local diagnostic only
};

// Deterministic, sorted, duplicate-free fault names for a snapshot.
inline std::vector<std::string> deriveSensorFaults(
    const SensorSnapshot& snapshot) {
  std::vector<SensorFault> faults{
      // MQ-7 raw ADC is never calibrated and heater cycling is not monitored.
      SensorFault::kMq7Uncalibrated,
      SensorFault::kMq7HeaterStateUnknown,
      // MQ-135 hardware is absent from this helmet build.
      SensorFault::kMq135ReadFailed,
      SensorFault::kMq135Uncalibrated,
      SensorFault::kMq135HeaterStateUnknown,
      // GPS and battery monitoring hardware are absent.
      SensorFault::kGpsUnavailable,
      SensorFault::kBatteryUnavailable,
  };
  if (!snapshot.motion.has_value()) faults.push_back(SensorFault::kMpuReadFailed);
  if (!snapshot.temperatureC.has_value() || !snapshot.humidityPct.has_value()) {
    faults.push_back(SensorFault::kDhtReadFailed);
  }
  if (!snapshot.mq7Raw.has_value()) faults.push_back(SensorFault::kMq7ReadFailed);
  if (!snapshot.fallWindow.has_value() ||
      !snapshot.fallWindow->windowEndTimestampMs.has_value()) {
    faults.push_back(SensorFault::kFallWindowUnavailable);
  }
  std::vector<std::string> names;
  names.reserve(faults.size());
  for (const auto fault : faults) names.emplace_back(sensorFaultName(fault));
  std::sort(names.begin(), names.end());
  names.erase(std::unique(names.begin(), names.end()), names.end());
  return names;
}

}  // namespace smart_safety
