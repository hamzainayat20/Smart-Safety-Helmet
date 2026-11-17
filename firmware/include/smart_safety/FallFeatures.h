#pragma once

#include <array>
#include <cstddef>
#include <cstdint>
#include <optional>

namespace smart_safety {

// Model contract: inference_service/models/fall/fall_model_config.json
// (SisFall_KFall_XGBoost_Fall_Detector v2.0): 50 Hz, 100-sample (2 s) windows,
// 25-sample (0.5 s) step, nine features in this exact order.
inline constexpr int kFallSamplingRateHz = 50;
inline constexpr std::uint32_t kFallSamplePeriodMs = 20;
inline constexpr std::size_t kFallWindowSamples = 100;
inline constexpr std::size_t kFallWindowStrideSamples = 25;
// Window continuity is judged against one fixed 20 ms grid, not sample-to-
// sample gaps. A sample may be up to 9 ms LATE for its grid slot (task wake-up
// jitter: the sampler can be delayed but never runs early). 9 ms is below half
// a period, so every accepted sample still belongs unambiguously to its own
// slot; nothing is stretched, merged or interpolated. A missed slot, a sample
// more than 9 ms late, or a rate that drifts off 50 Hz restarts the window.
inline constexpr std::uint32_t kFallMaxSampleLatenessMs = 9;

// Feature definitions (inferred from model metadata and the trained split
// thresholds; see firmware/README.md "Fall feature definitions"):
//   acc_*  : statistics of |a| = sqrt(ax^2 + ay^2 + az^2) in g, gravity kept
//   gyro_* : statistics of |w| = sqrt(gx^2 + gy^2 + gz^2) in deg/s
//   jerk_* : statistics of jerkGPerSecond() over the 99 consecutive pairs
//   *_std  : population standard deviation (ddof = 0)
struct FallFeatures {
  double accMean{0};
  double accStd{0};
  double accMin{0};
  double accMax{0};
  double gyroMean{0};
  double gyroStd{0};
  double gyroMax{0};
  double jerkMean{0};
  double jerkMax{0};
};

// The only place jerk is defined: absolute first difference of acceleration
// magnitude multiplied by the sampling rate, in g/s. The first sample of a
// window has no predecessor and contributes no jerk value.
double jerkGPerSecond(double previousMagnitudeG, double magnitudeG);

// Computes features over exactly kFallWindowSamples magnitudes (oldest first).
// Returns nullopt for any non-finite or negative input; never substitutes 0.
std::optional<FallFeatures> computeFallFeatures(
    const std::array<double, kFallWindowSamples>& accelerationMagnitudeG,
    const std::array<double, kFallWindowSamples>& gyroMagnitudeDps);

// Fixed-size ring of contiguous 50 Hz samples.
class FallFeatureWindow {
 public:
  void reset();
  // Appends a sample. If it does not fit the window's 50 Hz grid within
  // kFallMaxSampleLatenessMs, the window restarts with this sample first.
  void push(double accelerationMagnitudeG, double gyroMagnitudeDps,
            std::uint32_t sampleMs, bool saturated);
  bool full() const { return count_ == kFallWindowSamples; }
  std::size_t size() const { return count_; }
  std::uint32_t endMs() const { return lastMs_; }
  std::uint32_t restarts() const { return restarts_; }
  // Lateness of the last accepted sample relative to its grid slot.
  std::uint32_t lastLatenessMs() const { return lastLatenessMs_; }
  // Largest lateness in the current contiguous run.
  std::uint32_t runMaxLatenessMs() const { return runMaxLatenessMs_; }
  // Signed deviation from the expected slot that caused the latest restart
  // (positive = late / missed slots, negative = early / rate too high).
  std::int32_t lastRestartDeviationMs() const { return lastRestartDeviationMs_; }
  bool containsSaturation() const;
  // Features only for a full window with no saturated (clipped) sample.
  std::optional<FallFeatures> compute() const;

 private:
  std::array<double, kFallWindowSamples> acc_{};
  std::array<double, kFallWindowSamples> gyro_{};
  std::array<bool, kFallWindowSamples> saturated_{};
  std::size_t head_{0};  // next write position
  std::size_t count_{0};
  std::uint32_t lastMs_{0};
  std::uint32_t nextSlotMs_{0};  // grid time expected for the next sample
  std::uint32_t runMaxLatenessMs_{0};
  std::uint32_t lastLatenessMs_{0};
  std::int32_t lastRestartDeviationMs_{0};
  std::uint32_t restarts_{0};
};

struct GyroOffsets {
  double x{0};
  double y{0};
  double z{0};
};

enum class CalibrationState { kCollecting, kComplete, kFailed };

enum class CalibrationFailure {
  kNone,
  kMotionDetected,
  kGravityImplausible,
  kOffsetImplausible,
  kReadInterrupted,
};

const char* calibrationStateName(CalibrationState state);
const char* calibrationFailureName(CalibrationFailure failure);

struct CalibrationLimits {
  std::size_t samplesPerAttempt{100};      // 2 s at 50 Hz
  unsigned maxAttempts{10};                // bounded: about 20 s in total
  double maxGyroAxisStdDps{1.0};           // still on a table
  double maxGyroAxisOffsetDps{30.0};       // beyond datasheet zero-rate spec
  double minGravityG{0.80};                // |a| must look like gravity alone
  double maxGravityG{1.20};
  double maxAccelerationStdG{0.03};
};

// Estimates gyro zero-rate offsets from stationary samples. Acceleration is
// only checked for stillness; it is never offset-corrected or gravity-removed
// because the model was trained on raw |a| including gravity.
class GyroCalibrator {
 public:
  explicit GyroCalibrator(CalibrationLimits limits = {});

  void reset();
  // Feeds one uncalibrated sample. Returns true when the state changed.
  bool add(double gx, double gy, double gz, double accelerationMagnitudeG);
  // A read failure during collection ends the current attempt.
  bool interrupt();

  CalibrationState state() const { return state_; }
  CalibrationFailure lastFailure() const { return lastFailure_; }
  unsigned attempts() const { return attempts_; }
  const GyroOffsets& offsets() const { return offsets_; }
  std::size_t collected() const { return count_; }

 private:
  bool finishAttempt(CalibrationFailure failure);
  void startAttempt();

  CalibrationLimits limits_;
  CalibrationState state_{CalibrationState::kCollecting};
  CalibrationFailure lastFailure_{CalibrationFailure::kNone};
  unsigned attempts_{1};
  GyroOffsets offsets_{};
  // Welford running statistics, numerically stable on single-pass data.
  std::size_t count_{0};
  std::array<double, 4> mean_{};
  std::array<double, 4> m2_{};
};

}  // namespace smart_safety
