#pragma once

#include <cstdint>
#include <optional>

#include "smart_safety/FallDetectionEngine.h"
#include "smart_safety/FallFeatures.h"
#include "smart_safety/MpuSensor.h"
#include "smart_safety/SensorTypes.h"

namespace smart_safety {

// A real, complete window evaluated on the device. windowEndMs is the
// millis() timestamp of its last sample; it is converted to UTC only at
// upload time and only if device time is synchronized.
struct WindowCandidate {
  FallFeatures features{};
  std::uint32_t windowEndMs{0};
};

struct MotionStatus {
  CalibrationState calibration{CalibrationState::kCollecting};
  CalibrationFailure lastCalibrationFailure{CalibrationFailure::kNone};
  unsigned calibrationAttempts{1};
  GyroOffsets gyroOffsets{};
  std::uint32_t windowRestarts{0};
  std::uint32_t maxSampleLatenessMs{0};      // largest accepted lateness seen
  std::int32_t lastRestartDeviationMs{0};    // what caused the last restart
  std::uint32_t saturatedWindows{0};
  std::uint32_t readFailures{0};
  std::size_t windowFill{0};
  FallStatus localFallStatus{FallStatus::kNotEvaluated};
};

// Hardware-independent 50 Hz motion processing. The ESP32 build runs it in a
// dedicated FreeRTOS task; host tests drive it with synthetic timestamps.
class MotionPipeline {
 public:
  explicit MotionPipeline(CalibrationLimits limits = {});

  void onSample(const RawImuReading& reading, std::uint32_t sampleMs);
  void onReadFailure();

  // Latest real sample: gyro offset-corrected once calibration is complete,
  // raw before that (or if calibration failed). Absent after a read failure.
  const std::optional<MotionSample>& latest() const { return latest_; }
  std::uint32_t latestMs() const { return latestMs_; }

  // The strongest (largest acc_max) window evaluated since the last take.
  // Taking it clears it, so each window is uploaded at most once.
  std::optional<WindowCandidate> takeCandidate();
  const std::optional<WindowCandidate>& peekCandidate() const {
    return candidate_;
  }
  // Clears the candidate only if it is still the one that was peeked (a
  // stronger window may have replaced it meanwhile and must not be lost).
  bool consumeCandidate(std::uint32_t windowEndMs);

  const MotionStatus& status() const { return status_; }

 private:
  GyroCalibrator calibrator_;
  FallFeatureWindow window_;
  FallDetectionEngine localFall_;
  std::optional<MotionSample> latest_;
  std::uint32_t latestMs_{0};
  std::optional<WindowCandidate> candidate_;
  std::size_t samplesSinceEvaluation_{0};
  MotionStatus status_{};
};

}  // namespace smart_safety
