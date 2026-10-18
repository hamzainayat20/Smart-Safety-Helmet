#pragma once

#include <cstdint>

namespace smart_safety {

class PeriodicTask {
 public:
  explicit PeriodicTask(std::uint32_t intervalMs)
      : intervalMs_(intervalMs) {}

  void reset(std::uint32_t nowMs) {
    lastRunMs_ = nowMs;
    initialized_ = true;
  }

  bool due(std::uint32_t nowMs) {
    if (!initialized_) {
      reset(nowMs);
      return false;
    }
    if (static_cast<std::uint32_t>(nowMs - lastRunMs_) < intervalMs_) {
      return false;
    }
    lastRunMs_ = nowMs;
    return true;
  }

  std::uint32_t intervalMs() const { return intervalMs_; }

 private:
  std::uint32_t intervalMs_;
  std::uint32_t lastRunMs_{0};
  bool initialized_{false};
};

}  // namespace smart_safety

