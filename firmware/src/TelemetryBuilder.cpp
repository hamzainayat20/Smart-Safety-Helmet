#include "smart_safety/TelemetryBuilder.h"

#include <cmath>
#include <iomanip>
#include <locale>
#include <sstream>

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
  if (value == 0.0) return "0";  // also normalizes -0
  std::ostringstream output;
  output.imbue(std::locale::classic());
  output << std::setprecision(8) << value;
  return output.str();
}

bool finiteNonNegative(double value) {
  return std::isfinite(value) && value >= 0.0;
}

bool featuresValid(const FallFeatures& f) {
  for (const double value :
       {f.accMean, f.accStd, f.accMin, f.accMax, f.gyroMean, f.gyroStd,
        f.gyroMax, f.jerkMean, f.jerkMax}) {
    if (!finiteNonNegative(value) || value > 100000.0) return false;
  }
  return f.accMin <= f.accMax;
}

void appendFeatures(std::ostringstream& output, const FallFeatures& f) {
  // Exact model featureOrder from fall_model_config.json.
  output << "{\"acc_mean\":" << numberJson(f.accMean)
         << ",\"acc_std\":" << numberJson(f.accStd)
         << ",\"acc_min\":" << numberJson(f.accMin)
         << ",\"acc_max\":" << numberJson(f.accMax)
         << ",\"gyro_mean\":" << numberJson(f.gyroMean)
         << ",\"gyro_std\":" << numberJson(f.gyroStd)
         << ",\"gyro_max\":" << numberJson(f.gyroMax)
         << ",\"jerk_mean\":" << numberJson(f.jerkMean)
         << ",\"jerk_max\":" << numberJson(f.jerkMax) << '}';
}

void appendFaults(std::ostringstream& output, const SensorSnapshot& snapshot) {
  output << ",\"sensorFaults\":[";
  const auto names = deriveSensorFaults(snapshot);
  for (std::size_t index = 0; index < names.size(); ++index) {
    if (index > 0) output << ',';
    output << '"' << names[index] << '"';
  }
  output << ']';
}

void appendMotionFields(std::ostringstream& output, const MotionSample& m) {
  output << ",\"accelXG\":" << numberJson(m.accelXG)
         << ",\"accelYG\":" << numberJson(m.accelYG)
         << ",\"accelZG\":" << numberJson(m.accelZG)
         << ",\"gyroXDegreesPerSecond\":" << numberJson(m.gyroXDegreesPerSecond)
         << ",\"gyroYDegreesPerSecond\":" << numberJson(m.gyroYDegreesPerSecond)
         << ",\"gyroZDegreesPerSecond\":"
         << numberJson(m.gyroZDegreesPerSecond);
}

template <typename T>
std::string optionalJson(const std::optional<T>& value) {
  return value.has_value() ? numberJson(static_cast<double>(*value)) : "null";
}

}  // namespace

const char* ingestionBlockName(IngestionBlock block) {
  switch (block) {
    case IngestionBlock::kNone:
      return "none";
    case IngestionBlock::kTimeUnsynchronized:
      return "timeUnsynchronized";
    case IngestionBlock::kMotionOutsideContractRange:
      return "motionOutsideContractRange";
  }
  return "none";
}

bool TelemetryBuilder::motionWithinIngestionContract(const MotionSample& m) {
  if (!m.finite()) return false;
  for (const double axis : {m.accelXG, m.accelYG, m.accelZG}) {
    if (std::fabs(axis) > kIngestionAccelLimitG) return false;
  }
  for (const double axis : {m.gyroXDegreesPerSecond, m.gyroYDegreesPerSecond,
                            m.gyroZDegreesPerSecond}) {
    if (std::fabs(axis) > kIngestionGyroLimitDps) return false;
  }
  return true;
}

SensorSnapshot TelemetryBuilder::sanitizeForIngestion(
    const SensorSnapshot& snapshot, std::uint64_t deviceTimestampMs) {
  SensorSnapshot clean = snapshot;
  const bool dhtValid =
      clean.temperatureC.has_value() && clean.humidityPct.has_value() &&
      std::isfinite(*clean.temperatureC) && *clean.temperatureC >= -40.0 &&
      *clean.temperatureC <= 80.0 && std::isfinite(*clean.humidityPct) &&
      *clean.humidityPct >= 0.0 && *clean.humidityPct <= 100.0;
  if (!dhtValid) {
    clean.temperatureC.reset();
    clean.humidityPct.reset();
    clean.heatIndexC.reset();
  } else if (clean.heatIndexC.has_value() &&
             (!std::isfinite(*clean.heatIndexC) || *clean.heatIndexC < -100.0 ||
              *clean.heatIndexC > 250.0)) {
    clean.heatIndexC.reset();
  }
  if (clean.mq7Raw.has_value() &&
      (*clean.mq7Raw < 0 || *clean.mq7Raw > 4095)) {
    clean.mq7Raw.reset();
  }
  if (clean.fallWindow.has_value()) {
    const auto& window = *clean.fallWindow;
    if (!window.windowEndTimestampMs.has_value() ||
        *window.windowEndTimestampMs > deviceTimestampMs ||
        !featuresValid(window.features)) {
      clean.fallWindow.reset();
    }
  }
  return clean;
}

TelemetryRecord TelemetryBuilder::build(const TelemetryMetadata& metadata,
                                        const SensorSnapshot& snapshot) const {
  std::ostringstream output;
  output.imbue(std::locale::classic());
  output << "{\"record\":\"local-diagnostic\",\"schemaVersion\":\""
         << config::kSchemaVersion << "\",\"eventId\":\""
         << escapeJson(metadata.eventId) << "\",\"helmetId\":\""
         << escapeJson(metadata.helmetId) << "\",\"deviceTimestamp\":";
  if (metadata.timeSynchronized && metadata.deviceTimestampMs.has_value()) {
    output << *metadata.deviceTimestampMs;
  } else {
    output << "null";
  }
  output << ",\"deviceTimeStatus\":\""
         << (metadata.timeSynchronized ? "synchronized" : "unsynchronized")
         << "\",\"firmwareVersion\":\"" << escapeJson(metadata.firmwareVersion)
         << "\",\"temperatureC\":" << optionalJson(snapshot.temperatureC)
         << ",\"humidityPct\":" << optionalJson(snapshot.humidityPct)
         << ",\"heatIndexC\":" << optionalJson(snapshot.heatIndexC);
  if (snapshot.motion.has_value()) {
    appendMotionFields(output, *snapshot.motion);
  } else {
    output << ",\"accelXG\":null,\"accelYG\":null,\"accelZG\":null"
           << ",\"gyroXDegreesPerSecond\":null,\"gyroYDegreesPerSecond\":null"
           << ",\"gyroZDegreesPerSecond\":null";
  }
  output << ",\"mq7Raw\":" << optionalJson(snapshot.mq7Raw)
         << ",\"mq7Units\":\"raw ADC count, not ppm\",\"fallFeatures\":";
  if (snapshot.fallWindow.has_value()) {
    appendFeatures(output, snapshot.fallWindow->features);
    output << ",\"windowEndTimestamp\":"
           << optionalJson(snapshot.fallWindow->windowEndTimestampMs);
  } else {
    output << "null,\"windowEndTimestamp\":null";
  }
  output << ",\"localFallStatus\":\"" << fallStatusName(snapshot.fallStatus)
         << '"';
  appendFaults(output, snapshot);
  output << '}';
  return TelemetryRecord{metadata, snapshot, output.str()};
}

IngestionBuild TelemetryBuilder::buildIngestion(
    const TelemetryMetadata& metadata, const SensorSnapshot& snapshot) const {
  if (!metadata.timeSynchronized || !metadata.deviceTimestampMs.has_value()) {
    return {std::nullopt, IngestionBlock::kTimeUnsynchronized};
  }
  if (snapshot.motion.has_value() &&
      !motionWithinIngestionContract(*snapshot.motion)) {
    return {std::nullopt, IngestionBlock::kMotionOutsideContractRange};
  }
  const auto deviceTimestamp = *metadata.deviceTimestampMs;
  const auto clean = sanitizeForIngestion(snapshot, deviceTimestamp);

  std::ostringstream output;
  output.imbue(std::locale::classic());
  output << "{\"schemaVersion\":\"" << config::kSchemaVersion
         << "\",\"eventId\":\"" << escapeJson(metadata.eventId)
         << "\",\"helmetId\":\"" << escapeJson(metadata.helmetId)
         << "\",\"deviceTimestamp\":" << deviceTimestamp
         << ",\"firmwareVersion\":\"" << escapeJson(metadata.firmwareVersion)
         << '"';
  if (clean.temperatureC.has_value()) {
    output << ",\"temperatureC\":" << numberJson(*clean.temperatureC)
           << ",\"humidityPct\":" << numberJson(*clean.humidityPct);
    if (clean.heatIndexC.has_value()) {
      output << ",\"heatIndexC\":" << numberJson(*clean.heatIndexC);
    }
  }
  if (clean.motion.has_value()) appendMotionFields(output, *clean.motion);
  if (clean.mq7Raw.has_value()) output << ",\"mq7Raw\":" << *clean.mq7Raw;
  // Warm-up flags are required booleans in schema 2.0.
  //  mq7WarmUp = true: the MQ-7 is powered but its heater cycle is not
  //    controlled or verified, so it is never claimed to be ready.
  //  mq135WarmUp = false: MQ-135 hardware is absent, so it is not warming
  //    up; its absence is stated by the mq135ReadFailed fault instead. (true
  //    would make the backend tell the worker to wait for a sensor that does
  //    not exist.)
  output << ",\"mq7WarmUp\":true,\"mq135WarmUp\":false";
  if (clean.fallWindow.has_value()) {
    output << ",\"fallFeatures\":";
    appendFeatures(output, clean.fallWindow->features);
    output << ",\"samplingRateHz\":" << kFallSamplingRateHz
           << ",\"windowSamples\":" << kFallWindowSamples
           << ",\"windowEndTimestamp\":"
           << *clean.fallWindow->windowEndTimestampMs;
  }
  appendFaults(output, clean);
  output << '}';
  return {output.str(), IngestionBlock::kNone};
}

}  // namespace smart_safety
