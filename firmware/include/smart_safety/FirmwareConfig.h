#pragma once

#include <cstddef>
#include <cstdint>

namespace smart_safety::config {

inline constexpr int kDht22Pin = 4;
inline constexpr int kI2cSdaPin = 21;
inline constexpr int kI2cSclPin = 22;
inline constexpr std::uint8_t kMpuAddress = 0x68;

// No MQ-7, GPS, battery, buzzer, or LED pin is defined until its wiring is
// physically verified. In particular, production firmware does not use GPIO 27.
inline constexpr bool kMq7AnalogEnabled = false;
inline constexpr bool kMq7DigitalEnabled = false;

inline constexpr std::uint32_t kDhtIntervalMs = 2000;
inline constexpr std::uint32_t kMpuIntervalMs = 20;
inline constexpr std::uint32_t kTelemetryIntervalMs = 5000;
inline constexpr std::uint32_t kI2cTimeoutMs = 20;
inline constexpr std::uint32_t kMpuWakeDelayMs = 100;

inline constexpr char kSchemaVersion[] = "1.0";
inline constexpr char kFirmwareVersion[] = "0.2.0-staging";
inline constexpr char kHelmetIdPlaceholder[] = "UNPROVISIONED_HELMET";

#ifndef SMART_SAFETY_ENABLE_STAGING_NETWORK
#define SMART_SAFETY_ENABLE_STAGING_NETWORK 0
#endif

inline constexpr std::size_t kOfflineBufferCapacity = 10;
inline constexpr std::uint32_t kNetworkRequestTimeoutMs = 5000;

}  // namespace smart_safety::config
