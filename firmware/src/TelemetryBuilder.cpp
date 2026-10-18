#include "smart_safety/TelemetryBuilder.h"

#include <algorithm>
#include <cmath>
#include <iomanip>
#include <locale>
#include <sstream>
#include <vector>

#include "smart_safety/FirmwareConfig.h"

namespace smart_safety {
namespace {

std::string escapeJson(const std::string& input) {
  std::ostringstream output;
  for (const unsigned char character : input) {
    switch (character) {
      case '"':
        output << "\\\"";
        break;
      case '\\':
        output << "\\\\";
        break;
      case '\b':
        output << "\\b";
        break;
      case '\f':
        output << "\\f";
        break;
      case '\n':
        output << "\\n";
        break;
      case '\r':
        output << "\\r";
        break;
      case '\t':
        output << "\\t";
        break;
      default:
        if (character < 0x20) {
          output << "\\u" << std::hex << std::setw(4) << std::setfill('0')
                 << static_cast<int>(character) << std::dec;
        } else {
          output << static_cast<char>(character);
        }
    }
  }
  return output.str();
}

std::string numberJson(double value) {
  if (!std::isfinite(value)) return "null";
  if (value == 0.0) return "0";
  std::ostringstream output;
  output.imbue(std::locale::classic());
  output << std::setprecision(8) << value;
  return output.str();
}

template <typename T>
void appendOptionalNumber(std::ostringstream& output,
                          const std::optional<T>& value) {
  if (!value.has_value()) {
    output << "null";
    return;
  }
  output << numberJson(static_cast<double>(*value));
}

void appendOptionalBool(std::ostringstream& output,
                        const std::optional<bool>& value) {
  if (!value.has_value()) {
    output << "null";
  } else {
    output << (*value ? "true" : "false");
  }
}

}  // namespace

TelemetryRecord TelemetryBuilder::build(const TelemetryMetadata& metadata,
                                        const SensorSnapshot& snapshot) const {
  return TelemetryRecord{metadata, snapshot, serialize(metadata, snapshot)};
}

std::optional<std::string> TelemetryBuilder::buildIngestionJson(
    const TelemetryMetadata& metadata,
    const SensorSnapshot& snapshot) const {
  if (!metadata.timeSynchronized || !metadata.deviceTimestampMs.has_value()) {
    return std::nullopt;
  }
  return serializeIngestion(metadata, snapshot);
}

std::string TelemetryBuilder::serialize(const TelemetryMetadata& metadata,
                                        const SensorSnapshot& snapshot) {
  std::ostringstream output;
  output.imbue(std::locale::classic());
  output << "{\"schemaVersion\":\"" << config::kSchemaVersion
         << "\",\"eventId\":\"" << escapeJson(metadata.eventId)
         << "\",\"helmetId\":\"" << escapeJson(metadata.helmetId)
         << "\",\"deviceTimestamp\":";
  if (metadata.timeSynchronized && metadata.deviceTimestampMs.has_value()) {
    output << *metadata.deviceTimestampMs;
  } else {
    output << "null";
  }
  output << ",\"deviceTimeStatus\":\""
         << (metadata.timeSynchronized ? "synchronized" : "unsynchronized")
         << "\",\"firmwareVersion\":\""
         << escapeJson(metadata.firmwareVersion) << "\",\"temperatureC\":";
  appendOptionalNumber(output, snapshot.temperatureC);
  output << ",\"humidityPct\":";
  appendOptionalNumber(output, snapshot.humidityPct);
  output << ",\"heatIndexC\":";
  appendOptionalNumber(output, snapshot.heatIndexC);

  output << ",\"gasPpm\":null,\"gasWarmUp\":true,\"gasRaw\":";
  appendOptionalNumber(output, snapshot.gasRaw);
  output << ",\"gasAdcVoltage\":";
  appendOptionalNumber(output, snapshot.gasAdcVoltage);
  output << ",\"gasSensorVoltage\":";
  appendOptionalNumber(output, snapshot.gasSensorVoltage);
  output << ",\"gasDigitalThreshold\":";
  appendOptionalBool(output, snapshot.gasDigitalThreshold);

  const auto appendMotion = [&](double MotionSample::*member) {
    if (!snapshot.motion.has_value()) {
      output << "null";
    } else {
      output << numberJson(snapshot.motion.value().*member);
    }
  };
  output << ",\"accelXG\":";
  appendMotion(&MotionSample::accelXG);
  output << ",\"accelYG\":";
  appendMotion(&MotionSample::accelYG);
  output << ",\"accelZG\":";
  appendMotion(&MotionSample::accelZG);
  output << ",\"gyroXDegreesPerSecond\":";
  appendMotion(&MotionSample::gyroXDegreesPerSecond);
  output << ",\"gyroYDegreesPerSecond\":";
  appendMotion(&MotionSample::gyroYDegreesPerSecond);
  output << ",\"gyroZDegreesPerSecond\":";
  appendMotion(&MotionSample::gyroZDegreesPerSecond);

  output << ",\"fallStatus\":\"" << fallStatusName(snapshot.fallStatus)
         << "\",\"location\":null,\"gpsStatus\":\"invalid\""
         << ",\"batteryPct\":null,\"severity\":\"unassessed\""
         << ",\"sensorFaults\":[";

  std::vector<std::string> faultNames;
  faultNames.reserve(snapshot.sensorFaults.size());
  for (const auto fault : snapshot.sensorFaults) {
    faultNames.emplace_back(sensorFaultName(fault));
  }
  std::sort(faultNames.begin(), faultNames.end());
  faultNames.erase(std::unique(faultNames.begin(), faultNames.end()),
                   faultNames.end());
  for (std::size_t index = 0; index < faultNames.size(); ++index) {
    if (index > 0) output << ',';
    output << '\"' << faultNames[index] << '\"';
  }
  output << "]}";
  return output.str();
}

std::string TelemetryBuilder::serializeIngestion(
    const TelemetryMetadata& metadata, const SensorSnapshot& snapshot) {
  std::ostringstream output;
  output.imbue(std::locale::classic());
  output << "{\"schemaVersion\":\"" << config::kSchemaVersion
         << "\",\"eventId\":\"" << escapeJson(metadata.eventId)
         << "\",\"helmetId\":\"" << escapeJson(metadata.helmetId)
         << "\",\"deviceTimestamp\":" << *metadata.deviceTimestampMs
         << ",\"firmwareVersion\":\""
         << escapeJson(metadata.firmwareVersion) << "\"";

  const auto appendOptionalField = [&](const char* name, const auto& value) {
    if (value.has_value()) {
      output << ",\"" << name << "\":";
      appendOptionalNumber(output, value);
    }
  };
  appendOptionalField("temperatureC", snapshot.temperatureC);
  appendOptionalField("humidityPct", snapshot.humidityPct);
  appendOptionalField("heatIndexC", snapshot.heatIndexC);
  if (snapshot.gasRaw.has_value()) {
    output << ",\"gasRaw\":" << *snapshot.gasRaw;
  }
  appendOptionalField("gasAdcVoltage", snapshot.gasAdcVoltage);
  appendOptionalField("gasSensorVoltage", snapshot.gasSensorVoltage);
  if (snapshot.gasDigitalThreshold.has_value()) {
    output << ",\"gasDigitalThreshold\":"
           << (*snapshot.gasDigitalThreshold ? "true" : "false");
  }
  if (snapshot.motion.has_value()) {
    const auto& motion = *snapshot.motion;
    output << ",\"accelXG\":" << numberJson(motion.accelXG)
           << ",\"accelYG\":" << numberJson(motion.accelYG)
           << ",\"accelZG\":" << numberJson(motion.accelZG)
           << ",\"gyroXDegreesPerSecond\":"
           << numberJson(motion.gyroXDegreesPerSecond)
           << ",\"gyroYDegreesPerSecond\":"
           << numberJson(motion.gyroYDegreesPerSecond)
           << ",\"gyroZDegreesPerSecond\":"
           << numberJson(motion.gyroZDegreesPerSecond);
  }

  // The current ingestion contract deliberately excludes fall assessment,
  // calibrated gas, GPS, battery, client severity, and client connectivity.
  output << ",\"gasWarmUp\":true,\"fallStatus\":\"notEvaluated\""
         << ",\"sensorFaults\":[";
  std::vector<std::string> faultNames;
  faultNames.reserve(snapshot.sensorFaults.size());
  for (const auto fault : snapshot.sensorFaults) {
    faultNames.emplace_back(sensorFaultName(fault));
  }
  std::sort(faultNames.begin(), faultNames.end());
  faultNames.erase(std::unique(faultNames.begin(), faultNames.end()),
                   faultNames.end());
  for (std::size_t index = 0; index < faultNames.size(); ++index) {
    if (index > 0) output << ',';
    output << '\"' << faultNames[index] << '\"';
  }
  output << "]}";
  return output.str();
}

}  // namespace smart_safety
