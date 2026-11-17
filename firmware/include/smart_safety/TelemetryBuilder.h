#pragma once

#include <cstdint>
#include <optional>
#include <string>

#include "smart_safety/SensorTypes.h"

namespace smart_safety {

struct TelemetryMetadata {
  std::string eventId;
  std::string helmetId;
  std::optional<std::uint64_t> deviceTimestampMs;
  bool timeSynchronized{false};
  std::string firmwareVersion;
};

struct TelemetryRecord {
  TelemetryMetadata metadata;
  SensorSnapshot snapshot;
  std::string json;  // local diagnostic JSON, never uploaded
};

// Instantaneous-axis limits enforced by the *deployed* ingestion contract
// (functions/src/telemetry_contract.js). The IMU measures wider ranges for
// the fall window; instantaneous axes outside these limits cannot be sent.
inline constexpr double kIngestionAccelLimitG = 2.0;
inline constexpr double kIngestionGyroLimitDps = 250.0;

enum class IngestionBlock {
  kNone,
  kTimeUnsynchronized,
  kMotionOutsideContractRange,
};

const char* ingestionBlockName(IngestionBlock block);

struct IngestionBuild {
  std::optional<std::string> json;
  IngestionBlock block{IngestionBlock::kNone};
};

class TelemetryBuilder {
 public:
  // Local Serial diagnostics: explicit nulls, local-only status fields.
  TelemetryRecord build(const TelemetryMetadata& metadata,
                        const SensorSnapshot& snapshot) const;

  // Strict schema 2.0 ingestion body. Deterministic field order, only real
  // measurements, every absence paired with its fault, no backend-owned or
  // schema 1.0 fields.
  IngestionBuild buildIngestion(const TelemetryMetadata& metadata,
                                const SensorSnapshot& snapshot) const;

  static bool motionWithinIngestionContract(const MotionSample& motion);
  // Drops values the contract would reject and windows that are incomplete.
  static SensorSnapshot sanitizeForIngestion(const SensorSnapshot& snapshot,
                                             std::uint64_t deviceTimestampMs);
};

}  // namespace smart_safety
