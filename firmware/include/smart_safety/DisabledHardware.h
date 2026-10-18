#pragma once

#include <string>

#include "smart_safety/TelemetryBuilder.h"

namespace smart_safety {

enum class TransportResult {
  kAccepted,
  kRetryableFailure,
  kRejected,
  kDisabled,
};

class TelemetryTransport {
 public:
  virtual ~TelemetryTransport() = default;
  virtual TransportResult send(const TelemetryRecord& record) = 0;
  virtual bool networkActivityAllowed() const = 0;
};

class DisabledTelemetryTransport final : public TelemetryTransport {
 public:
  TransportResult send(const TelemetryRecord&) override {
    return TransportResult::kDisabled;
  }
  bool networkActivityAllowed() const override { return false; }
};

class NetworkManager {
 public:
  virtual ~NetworkManager() = default;
  virtual bool available() const = 0;
};

class DisabledNetworkManager final : public NetworkManager {
 public:
  bool available() const override { return false; }
};

class MQ7Sensor {
 public:
  virtual ~MQ7Sensor() = default;
  virtual bool available() const = 0;
  virtual bool analogEnabled() const = 0;
  virtual bool digitalEnabled() const = 0;
  virtual bool heaterStateKnown() const = 0;
};

class DisabledMQ7Sensor final : public MQ7Sensor {
 public:
  bool available() const override { return false; }
  bool analogEnabled() const override { return false; }
  bool digitalEnabled() const override { return false; }
  bool heaterStateKnown() const override { return false; }
};

class GPSManager {
 public:
  virtual ~GPSManager() = default;
  virtual bool available() const = 0;
};

class UnavailableGPSManager final : public GPSManager {
 public:
  bool available() const override { return false; }
};

class BatteryMonitor {
 public:
  virtual ~BatteryMonitor() = default;
  virtual bool available() const = 0;
};

class UnavailableBatteryMonitor final : public BatteryMonitor {
 public:
  bool available() const override { return false; }
};

class BuzzerController {
 public:
  virtual ~BuzzerController() = default;
  virtual bool configured() const = 0;
  virtual bool activate() = 0;
};

class UnconfiguredBuzzerController final : public BuzzerController {
 public:
  bool configured() const override { return false; }
  bool activate() override { return false; }
};

class LedController {
 public:
  virtual ~LedController() = default;
  virtual bool configured() const = 0;
  virtual bool activate() = 0;
};

class UnconfiguredLedController final : public LedController {
 public:
  bool configured() const override { return false; }
  bool activate() override { return false; }
};

}  // namespace smart_safety
