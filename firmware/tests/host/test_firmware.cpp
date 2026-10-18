#include <array>
#include <cmath>
#include <cstdint>
#include <functional>
#include <iostream>
#include <map>
#include <stdexcept>
#include <string>
#include <utility>
#include <vector>

#include "smart_safety/DHT22Sensor.h"
#include "smart_safety/DisabledHardware.h"
#include "smart_safety/EventIdGenerator.h"
#include "smart_safety/FallDetectionEngine.h"
#include "smart_safety/MPU6500Sensor.h"
#include "smart_safety/NonBlockingScheduler.h"
#include "smart_safety/OfflineBuffer.h"
#include "smart_safety/SensorManager.h"
#include "smart_safety/SecureIngestionProtocol.h"
#include "smart_safety/TelemetryBuilder.h"

namespace {

using namespace smart_safety;

void require(bool condition, const std::string& message) {
  if (!condition) throw std::runtime_error(message);
}

bool hasFault(const SensorSnapshot& snapshot, SensorFault fault) {
  for (const auto current : snapshot.sensorFaults) {
    if (current == fault) return true;
  }
  return false;
}

class FakeDhtReader final : public Dht22Reader {
 public:
  bool success{true};
  Dht22RawReading reading{25.0, 50.0, 25.5};

  bool read(Dht22RawReading& output) override {
    if (!success) return false;
    output = reading;
    return true;
  }
};

class FakeI2cBus final : public I2cBus {
 public:
  std::uint8_t whoAmI{0x70};
  bool readsSucceed{true};
  std::optional<std::uint8_t> failedWriteRegister;
  std::uint32_t timeoutMs{0};
  std::vector<std::pair<std::uint8_t, std::uint8_t>> writes;
  std::array<std::uint8_t, 14> motionBytes{};

  FakeI2cBus() { setSignedWord(4, 16384); }

  void setTimeoutMs(std::uint32_t value) override { timeoutMs = value; }

  bool readRegister(std::uint8_t, std::uint8_t registerAddress,
                    std::uint8_t& value) override {
    if (!readsSucceed || registerAddress != 0x75) return false;
    value = whoAmI;
    return true;
  }

  bool writeRegister(std::uint8_t, std::uint8_t registerAddress,
                     std::uint8_t value) override {
    writes.emplace_back(registerAddress, value);
    return failedWriteRegister != registerAddress;
  }

  bool readRegisters(std::uint8_t, std::uint8_t startRegister,
                     std::uint8_t* output, std::size_t length) override {
    if (!readsSucceed || startRegister != 0x3B || length != motionBytes.size()) {
      return false;
    }
    std::copy(motionBytes.begin(), motionBytes.end(), output);
    return true;
  }

  void setSignedWord(std::size_t offset, std::int16_t value) {
    const auto raw = static_cast<std::uint16_t>(value);
    motionBytes[offset] = static_cast<std::uint8_t>(raw >> 8U);
    motionBytes[offset + 1] = static_cast<std::uint8_t>(raw & 0xFFU);
  }
};

MotionSample motion(double magnitudeG, double gyro = 0) {
  MotionSample sample{};
  sample.accelZG = magnitudeG;
  sample.gyroXDegreesPerSecond = gyro;
  return sample;
}

SensorSnapshot completeSnapshot() {
  SensorSnapshot snapshot;
  snapshot.temperatureC = 25.0;
  snapshot.humidityPct = 50.0;
  snapshot.heatIndexC = 25.5;
  snapshot.motion = motion(1.0);
  snapshot.fallStatus = FallStatus::kNormal;
  return snapshot;
}

TelemetryMetadata metadata(const std::string& eventId = "helmet_boot_1") {
  return TelemetryMetadata{eventId, "UNPROVISIONED_HELMET", std::nullopt,
                           false, "0.1.0-local"};
}

void testDhtValidAndFailedReadings() {
  FakeDhtReader reader;
  DHT22Sensor sensor(reader, 2000);
  SensorSnapshot snapshot;
  sensor.begin(0);
  require(!sensor.poll(1999, snapshot), "DHT sampled before two seconds");
  require(sensor.poll(2000, snapshot), "DHT did not sample at two seconds");
  require(snapshot.temperatureC == 25.0 && snapshot.humidityPct == 50.0,
          "valid DHT values were not retained");
  require(!hasFault(snapshot, SensorFault::kDhtReadFailed),
          "valid DHT retained a fault");

  reader.success = false;
  require(sensor.poll(4000, snapshot), "failed DHT read was not attempted");
  require(!snapshot.temperatureC.has_value() &&
              !snapshot.humidityPct.has_value() &&
              !snapshot.heatIndexC.has_value(),
          "failed DHT values were not cleared");
  require(hasFault(snapshot, SensorFault::kDhtReadFailed),
          "failed DHT did not produce a fault");

  reader.success = true;
  reader.reading.heatIndexC = std::nan("");
  require(sensor.poll(6000, snapshot), "non-finite DHT read was not attempted");
  require(!snapshot.heatIndexC.has_value(),
          "non-finite heat index was retained");
}

void testMpuInitializationAndSampling() {
  FakeI2cBus bus;
  SensorSnapshot snapshot;
  MPU6500Sensor sensor(bus, 0x68, 20, 100, 20);
  require(sensor.begin(0, snapshot), "verified MPU6500 did not start waking");
  require(!sensor.initialized(), "MPU marked valid before configuration");
  require(bus.timeoutMs == 20, "I2C timeout was not configured");
  require(!sensor.poll(99, snapshot), "MPU wake delay was skipped");
  require(!sensor.poll(100, snapshot), "configuration emitted a sample");
  require(sensor.initialized(), "MPU was not initialized after configuration");
  require(bus.writes.size() == 4, "not every MPU register write was checked");
  require(sensor.poll(120, snapshot), "MPU did not sample at 50 Hz");
  require(snapshot.motion.has_value(), "valid MPU sample was unavailable");
  require(std::abs(snapshot.motion->accelZG - 1.0) < 0.0001,
          "MPU ±2 g scaling changed");
  bus.readsSucceed = false;
  require(sensor.poll(140, snapshot), "failed MPU sample was not attempted");
  require(!snapshot.motion.has_value() &&
              hasFault(snapshot, SensorFault::kMpuReadFailed),
          "failed MPU sample retained fabricated motion");

  FakeI2cBus wrongIdentity;
  wrongIdentity.whoAmI = 0x68;
  SensorSnapshot wrongSnapshot;
  MPU6500Sensor rejected(wrongIdentity, 0x68, 20, 100, 20);
  require(!rejected.begin(0, wrongSnapshot),
          "unverified WHO_AM_I 0x68 was accepted");
  require(!rejected.initialized(), "failed MPU initialization was marked valid");
  require(hasFault(wrongSnapshot, SensorFault::kMpuReadFailed),
          "failed MPU initialization did not produce a fault");

  FakeI2cBus failedConfiguration;
  failedConfiguration.failedWriteRegister = 0x1B;
  SensorSnapshot failedSnapshot;
  MPU6500Sensor failed(failedConfiguration, 0x68, 20, 100, 20);
  require(failed.begin(0, failedSnapshot), "MPU wake stage unexpectedly failed");
  failed.poll(100, failedSnapshot);
  require(!failed.initialized(), "failed configuration was marked valid");
  require(hasFault(failedSnapshot, SensorFault::kMpuReadFailed),
          "configuration failure did not retain MPU fault");
}

void testDhtFailureDoesNotStopMpu() {
  FakeDhtReader dhtReader;
  dhtReader.success = false;
  FakeI2cBus bus;
  DHT22Sensor dht(dhtReader, 2000);
  MPU6500Sensor mpu(bus, 0x68, 20, 100, 20);
  SensorManager manager(dht, mpu);
  manager.begin(0);
  manager.poll(100);
  require(manager.poll(120).mpuUpdated,
          "MPU did not sample before the DHT failure");
  const auto result = manager.poll(2000);
  require(result.dhtUpdated && result.mpuUpdated,
          "DHT failure prevented independent MPU scheduling");
  require(hasFault(manager.snapshot(), SensorFault::kDhtReadFailed) &&
              manager.snapshot().motion.has_value(),
          "DHT failure removed a valid MPU sample");
}

void testFiftyHertzScheduler() {
  PeriodicTask schedule(20);
  schedule.reset(1000);
  require(!schedule.due(1019), "20 ms schedule fired early");
  require(schedule.due(1020), "20 ms schedule did not fire");
  require(!schedule.due(1039), "20 ms schedule fired twice");
  require(schedule.due(1040), "20 ms schedule lost cadence");
  schedule.reset(0xFFFFFFF0U);
  require(schedule.due(4), "millis wraparound was not handled");
}

void testFallStateTransitionsAndCooldown() {
  FallDetectionEngine engine;
  require(engine.update(motion(0.3), 0).status ==
              FallStatus::kFreeFallCandidate,
          "free-fall candidate was not entered");
  engine.update(motion(0.3), 200);
  require(engine.update(motion(2.2), 220).status ==
              FallStatus::kImpactDetected,
          "impact phase was not entered");
  require(engine.update(motion(1.0, 1), 240).status ==
              FallStatus::kStillnessCandidate,
          "stillness phase was not entered");
  const auto confirmed = engine.update(motion(1.0, 1), 2240);
  require(confirmed.status == FallStatus::kConfirmed && confirmed.confirmedNow,
          "three-phase fall was not confirmed");
  require(engine.update(motion(0.3), 2260).status == FallStatus::kCooldown,
          "fall cooldown was not entered");
  require(engine.update(motion(0.3), 32259).status == FallStatus::kCooldown,
          "30-second duplicate cooldown ended early");
}

void testNormalMotionDoesNotCreateFall() {
  FallDetectionEngine engine;
  for (std::uint32_t now = 0; now < 10000; now += 20) {
    const double magnitude = 0.9 + 0.2 * std::sin(now / 250.0);
    const auto result = engine.update(motion(magnitude, 8), now);
    require(!result.confirmedNow && result.status != FallStatus::kConfirmed,
            "normal motion fixture created a false fall");
  }
}

void testStableEventIds() {
  EventIdGenerator generator("HELMET 1", "boot:abc");
  const auto first = generator.next();
  const auto retainedForRetry = first;
  const auto second = generator.next();
  require(first == retainedForRetry, "retained retry event ID changed");
  require(first == "HELMET_1_boot_abc_1", "event ID was not normalized");
  require(second == "HELMET_1_boot_abc_2", "event sequence was not stable");
}

void testCanonicalNullableJson() {
  TelemetryBuilder builder;
  SensorSnapshot snapshot;
  const auto record = builder.build(metadata(), snapshot);
  require(record.json.find("\"schemaVersion\":\"1.0\"") !=
              std::string::npos,
          "schema version missing");
  require(record.json.find("\"deviceTimestamp\":null") !=
              std::string::npos,
          "unsynchronized timestamp was fabricated");
  require(record.json.find("\"deviceTimeStatus\":\"unsynchronized\"") !=
              std::string::npos,
          "unsynchronized time status missing");
  require(record.json.find("\"temperatureC\":null") != std::string::npos &&
              record.json.find("\"accelXG\":null") != std::string::npos,
          "unavailable readings were fabricated");
  require(record.json.find("\"latitude\"") == std::string::npos &&
              record.json.find("\"longitude\"") == std::string::npos,
          "unavailable GPS coordinates were serialized");
}

void testGasGpsBatteryAndSeverityRemainExcluded() {
  TelemetryBuilder builder;
  const auto record = builder.build(metadata(), completeSnapshot());
  require(record.json.find("\"gasPpm\":null") != std::string::npos,
          "gas ppm was not null");
  require(record.json.find("\"gasWarmUp\":true") != std::string::npos,
          "gas warm-up exclusion missing");
  require(record.json.find("\"gasRaw\":null") != std::string::npos &&
              record.json.find("\"gasDigitalThreshold\":null") !=
                  std::string::npos,
          "disabled MQ-7 generated diagnostic values");
  require(record.json.find("\"location\":null") != std::string::npos &&
              record.json.find("\"batteryPct\":null") != std::string::npos,
          "GPS or battery unavailability missing");
  require(record.json.find("\"severity\":\"unassessed\"") !=
              std::string::npos,
          "local telemetry was assessed as safe");
  require(record.json.find("mq7Uncalibrated") != std::string::npos &&
              record.json.find("mq7HeaterStateUnknown") != std::string::npos,
          "MQ-7 exclusion faults missing");
  require(record.json.find("serverReceivedAt") == std::string::npos,
          "backend timestamp leaked into local telemetry");
}

void testStrictIngestionJson() {
  TelemetryBuilder builder;
  auto snapshot = completeSnapshot();
  const TelemetryMetadata synchronized{
      "helmet001_boot_1", "helmet001", 1775900000000ULL, true,
      "0.2.0-staging"};
  const auto json = builder.buildIngestionJson(synchronized, snapshot);
  require(json.has_value(), "synchronized telemetry was not ingestible");
  require(json->find("\"helmetId\":\"helmet001\"") != std::string::npos &&
              json->find("\"deviceTimestamp\":1775900000000") !=
                  std::string::npos,
          "canonical identity or timestamp missing");
  require(json->find("\"accelXG\":0") != std::string::npos &&
              json->find("\"accelZG\":1") != std::string::npos,
          "valid zero or acceleration unit was lost");
  require(json->find("\"fallStatus\":\"notEvaluated\"") !=
              std::string::npos,
          "diagnostic fall state escaped into ingestion");
  for (const auto* forbidden : {"severity", "connectivity", "gpsStatus",
                                "location", "batteryPct", "gasPpm",
                                "serverReceivedAt", "deviceTimeStatus"}) {
    require(json->find(forbidden) == std::string::npos,
            std::string("backend-owned or unavailable field emitted: ") +
                forbidden);
  }
  require(!builder.buildIngestionJson(metadata(), snapshot).has_value(),
          "unsynchronized telemetry became uploadable");
}

void testOfflineBufferAndSigningProtocol() {
  OfflineBuffer buffer(2);
  require(buffer.push({"event-1", "{1}"}) &&
              buffer.push({"event-2", "{2}"}),
          "offline records were not queued");
  require(buffer.push({"event-2", "changed"}) && buffer.size() == 2,
          "duplicate event was queued twice");
  require(buffer.oldest() != nullptr &&
              buffer.oldest()->eventId == "event-1",
          "offline buffer was not oldest-first");
  require(buffer.push({"event-3", "{3}"}) &&
              buffer.oldest()->eventId == "event-2",
          "bounded buffer did not evict the oldest record");
  require(buffer.removeOldest("event-2") &&
              buffer.oldest()->eventId == "event-3",
          "successful upload did not remove the matching oldest record");

  const auto canonical = SecureIngestionProtocol::canonicalRequest(
      "helmet001", 1775900000000ULL, "nonce_1234567890abcdef",
      std::string(64, 'a'));
  require(canonical ==
              "POST\n/ingest/v1/helmets/helmet001/telemetry\n"
              "1775900000000\nnonce_1234567890abcdef\n" +
                  std::string(64, 'a'),
          "firmware signing protocol differs from backend protocol");
}

void testNetworkingAndUnconfirmedHardwareAreDisabled() {
  DisabledTelemetryTransport transport;
  DisabledNetworkManager network;
  DisabledMQ7Sensor mq7;
  UnavailableGPSManager gps;
  UnavailableBatteryMonitor battery;
  UnconfiguredBuzzerController buzzer;
  UnconfiguredLedController led;
  TelemetryBuilder builder;
  const auto record = builder.build(metadata(), SensorSnapshot{});
  require(!transport.networkActivityAllowed() &&
              transport.send(record) == TransportResult::kDisabled,
          "disabled transport allowed network activity");
  require(!network.available() && !mq7.available() && !mq7.analogEnabled() &&
              !mq7.digitalEnabled() && !mq7.heaterStateKnown(),
          "disabled networking or MQ-7 reported available");
  require(!gps.available() && !battery.available(),
          "GPS or battery stub fabricated availability");
  require(!buzzer.configured() && !buzzer.activate() && !led.configured() &&
              !led.activate(),
          "unconfigured physical alert output activated");
}

}  // namespace

int main() {
  const std::vector<std::pair<std::string, std::function<void()>>> tests{
      {"DHT valid and failed readings", testDhtValidAndFailedReadings},
      {"MPU initialization and sampling", testMpuInitializationAndSampling},
      {"DHT failure does not stop MPU", testDhtFailureDoesNotStopMpu},
      {"50 Hz scheduling", testFiftyHertzScheduler},
      {"fall state transitions and cooldown", testFallStateTransitionsAndCooldown},
      {"normal motion has no false fall", testNormalMotionDoesNotCreateFall},
      {"stable event IDs", testStableEventIds},
      {"canonical nullable JSON", testCanonicalNullableJson},
      {"gas, GPS, battery, and severity exclusions",
       testGasGpsBatteryAndSeverityRemainExcluded},
      {"strict canonical ingestion JSON", testStrictIngestionJson},
      {"offline buffer and signing protocol",
       testOfflineBufferAndSigningProtocol},
      {"networking and unconfirmed hardware disabled",
       testNetworkingAndUnconfirmedHardwareAreDisabled},
  };

  std::size_t passed = 0;
  for (const auto& [name, test] : tests) {
    try {
      test();
      ++passed;
      std::cout << "PASS: " << name << '\n';
    } catch (const std::exception& error) {
      std::cerr << "FAIL: " << name << ": " << error.what() << '\n';
      return 1;
    }
  }
  std::cout << passed << " host tests passed\n";
  return 0;
}
