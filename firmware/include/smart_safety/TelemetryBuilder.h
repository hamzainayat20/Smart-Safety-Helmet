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
  std::string json;
};

class TelemetryBuilder {
 public:
  TelemetryRecord build(const TelemetryMetadata& metadata,
                        const SensorSnapshot& snapshot) const;

  // Returns the strict ingestion payload. Unsynchronized records are not
  // eligible for upload and therefore return nullopt.
  std::optional<std::string> buildIngestionJson(
      const TelemetryMetadata& metadata,
      const SensorSnapshot& snapshot) const;

 private:
  static std::string serialize(const TelemetryMetadata& metadata,
                               const SensorSnapshot& snapshot);
  static std::string serializeIngestion(const TelemetryMetadata& metadata,
                                        const SensorSnapshot& snapshot);
};

}  // namespace smart_safety
