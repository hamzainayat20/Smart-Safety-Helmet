#include "smart_safety/FallDetectionEngine.h"

#include <algorithm>
#include <cmath>

namespace smart_safety {

FallDetectionEngine::FallDetectionEngine(FallDetectionConfig config)
    : config_(config) {}

FallDetectionResult FallDetectionEngine::update(const MotionSample& sample,
                                                 std::uint32_t nowMs) {
  if (!sample.finite()) {
    returnToNormal();
    return result();
  }

  const double magnitudeG = sample.accelerationMagnitudeG();
  switch (phase_) {
    case Phase::kCooldown:
      if (static_cast<std::uint32_t>(nowMs - phaseStartedAtMs_) <
          config_.duplicateCooldownMs) {
        status_ = FallStatus::kCooldown;
        return result();
      }
      returnToNormal();
      break;

    case Phase::kConfirmed:
      phase_ = Phase::kCooldown;
      phaseStartedAtMs_ = nowMs;
      status_ = FallStatus::kCooldown;
      return result();

    case Phase::kNormal:
      if (magnitudeG < config_.freeFallThresholdG) {
        phase_ = Phase::kFreeFall;
        phaseStartedAtMs_ = nowMs;
        freeFallQualified_ = false;
        evidence_ = FallEvidence{};
        evidence_.minimumFreeFallMagnitudeG = magnitudeG;
        status_ = FallStatus::kFreeFallCandidate;
      }
      return result();

    case Phase::kFreeFall: {
      evidence_.minimumFreeFallMagnitudeG =
          std::min(evidence_.minimumFreeFallMagnitudeG, magnitudeG);
      const auto elapsed =
          static_cast<std::uint32_t>(nowMs - phaseStartedAtMs_);
      if (magnitudeG < config_.freeFallThresholdG) {
        if (elapsed >= config_.freeFallMinimumMs) freeFallQualified_ = true;
        status_ = FallStatus::kFreeFallCandidate;
        return result();
      }
      if (freeFallQualified_ && magnitudeG >= config_.impactThresholdG &&
          elapsed <= config_.impactWindowMs) {
        phase_ = Phase::kImpact;
        phaseStartedAtMs_ = nowMs;
        evidence_.peakImpactMagnitudeG = magnitudeG;
        stillnessActive_ = false;
        status_ = FallStatus::kImpactDetected;
        return result();
      }
      returnToNormal();
      return result();
    }

    case Phase::kImpact: {
      evidence_.peakImpactMagnitudeG =
          std::max(evidence_.peakImpactMagnitudeG, magnitudeG);
      if (static_cast<std::uint32_t>(nowMs - phaseStartedAtMs_) >
          config_.postImpactWindowMs) {
        returnToNormal();
        return result();
      }
      if (!isStill(sample, magnitudeG)) {
        stillnessActive_ = false;
        evidence_.stillnessDurationMs = 0;
        status_ = FallStatus::kImpactDetected;
        return result();
      }
      if (!stillnessActive_) {
        stillnessActive_ = true;
        stillnessStartedAtMs_ = nowMs;
      }
      evidence_.stillnessDurationMs =
          static_cast<std::uint32_t>(nowMs - stillnessStartedAtMs_);
      status_ = FallStatus::kStillnessCandidate;
      if (evidence_.stillnessDurationMs >= config_.stillnessRequiredMs) {
        phase_ = Phase::kConfirmed;
        phaseStartedAtMs_ = nowMs;
        status_ = FallStatus::kConfirmed;
        return result(true);
      }
      return result();
    }
  }
  return result();
}

bool FallDetectionEngine::isStill(const MotionSample& sample,
                                  double magnitudeG) const {
  return std::abs(magnitudeG - 1.0) <=
             config_.stillnessAccelerationToleranceG &&
         sample.gyroMagnitudeDegreesPerSecond() <=
             config_.stillnessGyroThresholdDegreesPerSecond;
}

void FallDetectionEngine::returnToNormal() {
  phase_ = Phase::kNormal;
  status_ = FallStatus::kNormal;
  freeFallQualified_ = false;
  stillnessActive_ = false;
  evidence_ = FallEvidence{};
}

void FallDetectionEngine::reset() { returnToNormal(); }

FallStatus FallDetectionEngine::status() const { return status_; }

FallDetectionResult FallDetectionEngine::result(bool confirmedNow) const {
  return FallDetectionResult{status_, confirmedNow, evidence_};
}

}  // namespace smart_safety

