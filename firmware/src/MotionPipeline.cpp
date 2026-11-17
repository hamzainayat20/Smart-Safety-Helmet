#include "smart_safety/MotionPipeline.h"

#include <algorithm>

namespace smart_safety {

MotionPipeline::MotionPipeline(CalibrationLimits limits)
    : calibrator_(limits) {}

void MotionPipeline::onSample(const RawImuReading& reading,
                              std::uint32_t sampleMs) {
  const auto& raw = reading.sample;
  if (!raw.finite()) {
    onReadFailure();
    return;
  }

  if (calibrator_.state() != CalibrationState::kComplete) {
    // Never compute fall windows from uncorrected gyro data.
    if (calibrator_.state() == CalibrationState::kCollecting) {
      if (reading.saturated) {
        calibrator_.interrupt();
      } else {
        calibrator_.add(raw.gyroXDegreesPerSecond, raw.gyroYDegreesPerSecond,
                        raw.gyroZDegreesPerSecond,
                        raw.accelerationMagnitudeG());
      }
    }
    status_.calibration = calibrator_.state();
    status_.lastCalibrationFailure = calibrator_.lastFailure();
    status_.calibrationAttempts = calibrator_.attempts();
    status_.gyroOffsets = calibrator_.offsets();
    window_.reset();
    status_.windowFill = 0;
    if (calibrator_.state() != CalibrationState::kComplete) {
      // The IMU is working, so the real (not offset-corrected) reading is
      // reported; only the fall window is withheld until calibration is done.
      latest_ = raw;
      latestMs_ = sampleMs;
      return;
    }
    // Calibration just completed; this sample starts the first window below.
  }

  const auto& offsets = calibrator_.offsets();
  MotionSample corrected = raw;
  corrected.gyroXDegreesPerSecond -= offsets.x;
  corrected.gyroYDegreesPerSecond -= offsets.y;
  corrected.gyroZDegreesPerSecond -= offsets.z;
  latest_ = corrected;
  latestMs_ = sampleMs;

  const auto restartsBefore = window_.restarts();
  window_.push(corrected.accelerationMagnitudeG(),
               corrected.gyroMagnitudeDegreesPerSecond(), sampleMs,
               reading.saturated);
  if (window_.restarts() != restartsBefore) samplesSinceEvaluation_ = 0;
  status_.windowRestarts = window_.restarts();
  status_.lastRestartDeviationMs = window_.lastRestartDeviationMs();
  status_.maxSampleLatenessMs =
      std::max(status_.maxSampleLatenessMs, window_.runMaxLatenessMs());
  status_.windowFill = window_.size();
  status_.localFallStatus = localFall_.update(corrected, sampleMs).status;

  if (!window_.full()) {
    samplesSinceEvaluation_ = 0;
    return;
  }
  // Evaluate at full, then every 25 samples (the model's 0.5 s step).
  if (samplesSinceEvaluation_ != 0 &&
      samplesSinceEvaluation_ < kFallWindowStrideSamples) {
    ++samplesSinceEvaluation_;
    return;
  }
  samplesSinceEvaluation_ = 1;
  const auto features = window_.compute();
  if (!features.has_value()) {
    if (window_.containsSaturation()) ++status_.saturatedWindows;
    return;
  }
  if (!candidate_.has_value() || features->accMax > candidate_->features.accMax) {
    candidate_ = WindowCandidate{*features, window_.endMs()};
  }
}

void MotionPipeline::onReadFailure() {
  ++status_.readFailures;
  latest_.reset();
  window_.reset();
  samplesSinceEvaluation_ = 0;
  status_.windowFill = 0;
  if (calibrator_.interrupt()) {
    status_.calibration = calibrator_.state();
    status_.lastCalibrationFailure = calibrator_.lastFailure();
    status_.calibrationAttempts = calibrator_.attempts();
  }
}

bool MotionPipeline::consumeCandidate(std::uint32_t windowEndMs) {
  if (!candidate_.has_value() || candidate_->windowEndMs != windowEndMs) {
    return false;
  }
  candidate_.reset();
  return true;
}

std::optional<WindowCandidate> MotionPipeline::takeCandidate() {
  auto taken = candidate_;
  candidate_.reset();
  return taken;
}

}  // namespace smart_safety
