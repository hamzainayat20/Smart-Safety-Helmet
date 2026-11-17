#include "smart_safety/FallFeatures.h"

#include <algorithm>
#include <cmath>

namespace smart_safety {
namespace {

struct Stats {
  double mean{0};
  double std{0};
  double min{0};
  double max{0};
};

// Two-pass mean/variance: stable for 100 samples and cheap on the ESP32.
template <std::size_t N>
bool statistics(const std::array<double, N>& values, std::size_t count,
                Stats& output) {
  if (count == 0 || count > N) return false;
  double sum = 0;
  double minimum = values[0];
  double maximum = values[0];
  for (std::size_t index = 0; index < count; ++index) {
    const double value = values[index];
    if (!std::isfinite(value) || value < 0) return false;
    sum += value;
    minimum = std::min(minimum, value);
    maximum = std::max(maximum, value);
  }
  const double mean = sum / static_cast<double>(count);
  double squared = 0;
  for (std::size_t index = 0; index < count; ++index) {
    const double delta = values[index] - mean;
    squared += delta * delta;
  }
  output = Stats{mean, std::sqrt(squared / static_cast<double>(count)),
                 minimum, maximum};
  return std::isfinite(output.std);
}

}  // namespace

double jerkGPerSecond(double previousMagnitudeG, double magnitudeG) {
  return std::fabs(magnitudeG - previousMagnitudeG) *
         static_cast<double>(kFallSamplingRateHz);
}

std::optional<FallFeatures> computeFallFeatures(
    const std::array<double, kFallWindowSamples>& acc,
    const std::array<double, kFallWindowSamples>& gyro) {
  Stats accStats;
  Stats gyroStats;
  if (!statistics(acc, kFallWindowSamples, accStats) ||
      !statistics(gyro, kFallWindowSamples, gyroStats)) {
    return std::nullopt;
  }
  std::array<double, kFallWindowSamples> jerk{};
  for (std::size_t index = 1; index < kFallWindowSamples; ++index) {
    jerk[index - 1] = jerkGPerSecond(acc[index - 1], acc[index]);
  }
  Stats jerkStats;
  if (!statistics(jerk, kFallWindowSamples - 1, jerkStats)) return std::nullopt;
  return FallFeatures{accStats.mean,  accStats.std,  accStats.min,
                      accStats.max,   gyroStats.mean, gyroStats.std,
                      gyroStats.max,  jerkStats.mean, jerkStats.max};
}

void FallFeatureWindow::reset() {
  head_ = 0;
  count_ = 0;
  lastMs_ = 0;
  runMaxLatenessMs_ = 0;
}

void FallFeatureWindow::push(double acc, double gyro, std::uint32_t sampleMs,
                             bool saturated) {
  lastLatenessMs_ = 0;
  if (count_ > 0) {
    // Wrap-safe signed distance from the expected grid slot.
    const std::int64_t deviation =
        static_cast<std::int32_t>(sampleMs - nextSlotMs_);
    const auto limit = static_cast<std::int64_t>(kFallMaxSampleLatenessMs);
    bool contiguous = true;
    if (deviation > limit) {
      contiguous = false;  // missed slot(s) or excessive lateness
    } else if (deviation < 0) {
      // Earlier than expected: the grid anchor (the run's first sample) was
      // itself late. Move the grid earlier, but only while every sample
      // already in the run stays within the lateness limit; otherwise the
      // samples are not on one 50 Hz grid (for example a 19 ms rate).
      const auto shift = static_cast<std::uint32_t>(-deviation);
      if (runMaxLatenessMs_ + shift > kFallMaxSampleLatenessMs) {
        contiguous = false;
      } else {
        runMaxLatenessMs_ += shift;
        nextSlotMs_ = sampleMs;
      }
    } else {
      lastLatenessMs_ = static_cast<std::uint32_t>(deviation);
      runMaxLatenessMs_ = std::max(runMaxLatenessMs_, lastLatenessMs_);
    }
    if (!contiguous) {
      lastRestartDeviationMs_ = static_cast<std::int32_t>(deviation);
      reset();
      ++restarts_;
    }
  }
  if (count_ == 0) {
    nextSlotMs_ = sampleMs;  // a new run anchors the grid on its first sample
    runMaxLatenessMs_ = 0;
  }
  acc_[head_] = acc;
  gyro_[head_] = gyro;
  saturated_[head_] = saturated;
  head_ = (head_ + 1) % kFallWindowSamples;
  if (count_ < kFallWindowSamples) ++count_;
  lastMs_ = sampleMs;
  nextSlotMs_ += kFallSamplePeriodMs;
}

bool FallFeatureWindow::containsSaturation() const {
  for (std::size_t index = 0; index < count_; ++index) {
    if (saturated_[index]) return true;
  }
  return false;
}

std::optional<FallFeatures> FallFeatureWindow::compute() const {
  if (!full() || containsSaturation()) return std::nullopt;
  // Unroll the ring oldest-first; jerk depends on sample order.
  std::array<double, kFallWindowSamples> acc{};
  std::array<double, kFallWindowSamples> gyro{};
  for (std::size_t index = 0; index < kFallWindowSamples; ++index) {
    const auto source = (head_ + index) % kFallWindowSamples;
    acc[index] = acc_[source];
    gyro[index] = gyro_[source];
  }
  return computeFallFeatures(acc, gyro);
}

const char* calibrationStateName(CalibrationState state) {
  switch (state) {
    case CalibrationState::kCollecting:
      return "collecting";
    case CalibrationState::kComplete:
      return "complete";
    case CalibrationState::kFailed:
      return "failed";
  }
  return "failed";
}

const char* calibrationFailureName(CalibrationFailure failure) {
  switch (failure) {
    case CalibrationFailure::kNone:
      return "none";
    case CalibrationFailure::kMotionDetected:
      return "motionDetected";
    case CalibrationFailure::kGravityImplausible:
      return "gravityImplausible";
    case CalibrationFailure::kOffsetImplausible:
      return "offsetImplausible";
    case CalibrationFailure::kReadInterrupted:
      return "readInterrupted";
  }
  return "none";
}

GyroCalibrator::GyroCalibrator(CalibrationLimits limits) : limits_(limits) {
  if (limits_.samplesPerAttempt < 2) limits_.samplesPerAttempt = 2;
  if (limits_.maxAttempts < 1) limits_.maxAttempts = 1;
}

void GyroCalibrator::reset() {
  state_ = CalibrationState::kCollecting;
  lastFailure_ = CalibrationFailure::kNone;
  attempts_ = 1;
  offsets_ = {};
  startAttempt();
}

void GyroCalibrator::startAttempt() {
  count_ = 0;
  mean_.fill(0);
  m2_.fill(0);
}

bool GyroCalibrator::add(double gx, double gy, double gz, double accMag) {
  if (state_ != CalibrationState::kCollecting) return false;
  if (!std::isfinite(gx) || !std::isfinite(gy) || !std::isfinite(gz) ||
      !std::isfinite(accMag)) {
    return finishAttempt(CalibrationFailure::kReadInterrupted);
  }
  const std::array<double, 4> values{gx, gy, gz, accMag};
  ++count_;
  for (std::size_t axis = 0; axis < values.size(); ++axis) {
    const double delta = values[axis] - mean_[axis];
    mean_[axis] += delta / static_cast<double>(count_);
    m2_[axis] += delta * (values[axis] - mean_[axis]);
  }
  if (count_ < limits_.samplesPerAttempt) return false;

  const auto stdOf = [&](std::size_t axis) {
    return std::sqrt(m2_[axis] / static_cast<double>(count_));
  };
  for (std::size_t axis = 0; axis < 3; ++axis) {
    if (stdOf(axis) > limits_.maxGyroAxisStdDps) {
      return finishAttempt(CalibrationFailure::kMotionDetected);
    }
  }
  if (stdOf(3) > limits_.maxAccelerationStdG) {
    return finishAttempt(CalibrationFailure::kMotionDetected);
  }
  if (mean_[3] < limits_.minGravityG || mean_[3] > limits_.maxGravityG) {
    return finishAttempt(CalibrationFailure::kGravityImplausible);
  }
  for (std::size_t axis = 0; axis < 3; ++axis) {
    if (std::fabs(mean_[axis]) > limits_.maxGyroAxisOffsetDps) {
      return finishAttempt(CalibrationFailure::kOffsetImplausible);
    }
  }
  offsets_ = GyroOffsets{mean_[0], mean_[1], mean_[2]};
  return finishAttempt(CalibrationFailure::kNone);
}

bool GyroCalibrator::interrupt() {
  if (state_ != CalibrationState::kCollecting || count_ == 0) return false;
  return finishAttempt(CalibrationFailure::kReadInterrupted);
}

bool GyroCalibrator::finishAttempt(CalibrationFailure failure) {
  lastFailure_ = failure;
  if (failure == CalibrationFailure::kNone) {
    state_ = CalibrationState::kComplete;
    return true;
  }
  if (attempts_ >= limits_.maxAttempts) {
    state_ = CalibrationState::kFailed;
    return true;
  }
  ++attempts_;
  startAttempt();
  return true;
}

}  // namespace smart_safety
