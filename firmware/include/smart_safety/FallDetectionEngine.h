#pragma once

#include <cstdint>

#include "smart_safety/SensorTypes.h"

namespace smart_safety {

struct FallDetectionConfig {
  double freeFallThresholdG{0.5};
  std::uint32_t freeFallMinimumMs{200};
  double impactThresholdG{2.0};
  std::uint32_t impactWindowMs{1500};
  double stillnessAccelerationToleranceG{0.15};
  double stillnessGyroThresholdDegreesPerSecond{15.0};
  std::uint32_t stillnessRequiredMs{2000};
  std::uint32_t postImpactWindowMs{5000};
  std::uint32_t duplicateCooldownMs{30000};
};

struct FallEvidence {
  double minimumFreeFallMagnitudeG{0};
  double peakImpactMagnitudeG{0};
  std::uint32_t stillnessDurationMs{0};
};

struct FallDetectionResult {
  FallStatus status{FallStatus::kNormal};
  bool confirmedNow{false};
  FallEvidence evidence{};
};

class FallDetectionEngine {
 public:
  explicit FallDetectionEngine(FallDetectionConfig config = {});

  FallDetectionResult update(const MotionSample& sample,
                             std::uint32_t nowMs);
  void reset();
  FallStatus status() const;

 private:
  enum class Phase {
    kNormal,
    kFreeFall,
    kImpact,
    kConfirmed,
    kCooldown,
  };

  bool isStill(const MotionSample& sample, double magnitudeG) const;
  void returnToNormal();
  FallDetectionResult result(bool confirmedNow = false) const;

  FallDetectionConfig config_;
  Phase phase_{Phase::kNormal};
  FallStatus status_{FallStatus::kNormal};
  bool freeFallQualified_{false};
  bool stillnessActive_{false};
  std::uint32_t phaseStartedAtMs_{0};
  std::uint32_t stillnessStartedAtMs_{0};
  FallEvidence evidence_{};
};

}  // namespace smart_safety

