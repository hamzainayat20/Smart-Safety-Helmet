#pragma once

#include <cstddef>
#include <cstdint>

namespace smart_safety::config {

inline constexpr int kDht22Pin = 4;
inline constexpr int kI2cSdaPin = 21;
inline constexpr int kI2cSclPin = 22;
inline constexpr std::uint8_t kMpuAddress = 0x68;

// MQ-7 analog output (AO) via a 10 k (top) / 20 k (bottom) divider into
// GPIO34 (ADC1, input-only, usable while Wi-Fi is active). Raw ADC only.
// MQ-7 digital output (DO) stays disconnected; GPIO 27 is not used.
// GPS, battery, buzzer and LED pins are not defined: that hardware is absent.
inline constexpr int kMq7AnalogPin = 34;
inline constexpr bool kMq7AnalogEnabled = true;
inline constexpr bool kMq7DigitalEnabled = false;
inline constexpr std::uint32_t kMq7IntervalMs = 1000;
inline constexpr std::uint8_t kMq7Oversample = 8;

inline constexpr std::uint32_t kDhtIntervalMs = 2000;
// DHT22 is wired to GPIO4 (with pull-up) on the current prototype. Polling an
// ABSENT DHT22 stalls core 1 with interrupts disabled (see DHT22Sensor.h) and
// breaks 50 Hz sampling; if the sensor is removed, set this to false so it is
// not polled and dhtReadFailed is reported instead.
inline constexpr bool kDht22Installed = true;
// Even when installed, repeated failures back off to one attempt per minute.
inline constexpr std::uint32_t kDhtFailureBackoffMs = 60000;
inline constexpr std::uint8_t kDhtFailuresBeforeBackoff = 3;
inline constexpr std::uint32_t kMpuIntervalMs = 20;
inline constexpr std::uint32_t kTelemetryIntervalMs = 5000;
inline constexpr std::uint32_t kI2cTimeoutMs = 20;
inline constexpr std::uint32_t kMpuWakeDelayMs = 100;
inline constexpr std::uint32_t kMpuReinitIntervalMs = 1000;
inline constexpr std::uint8_t kMpuMaxConsecutiveFailures = 5;
// A motion sample older than this is not reported as current.
inline constexpr std::uint32_t kMotionStaleMs = 100;
// If the current instantaneous axes exceed the deployed ingestion limits,
// the upload waits (up to this long) for an in-range sample instead of
// sending clipped, fabricated or fault-flagged motion.
inline constexpr std::uint32_t kTelemetryDeferralMaxMs = 1000;

inline constexpr char kSchemaVersion[] = "2.0";
inline constexpr char kFirmwareVersion[] = "0.3.0-staging";
inline constexpr char kHelmetIdPlaceholder[] = "UNPROVISIONED_HELMET";

#ifndef SMART_SAFETY_ENABLE_STAGING_NETWORK
#define SMART_SAFETY_ENABLE_STAGING_NETWORK 0
#endif

inline constexpr std::size_t kOfflineBufferCapacity = 10;
inline constexpr std::uint32_t kNetworkRequestTimeoutMs = 5000;

}  // namespace smart_safety::config
