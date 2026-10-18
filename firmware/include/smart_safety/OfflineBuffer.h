#pragma once

#include <cstddef>
#include <deque>
#include <string>
#include <utility>

namespace smart_safety {

struct PendingTelemetry {
  std::string eventId;
  std::string json;
};

class OfflineBuffer {
 public:
  explicit OfflineBuffer(std::size_t capacity = 10) : capacity_(capacity) {}

  bool push(PendingTelemetry record) {
    if (capacity_ == 0 || record.eventId.empty() || record.json.empty()) {
      return false;
    }
    for (const auto& existing : records_) {
      if (existing.eventId == record.eventId) return true;
    }
    if (records_.size() == capacity_) records_.pop_front();
    records_.push_back(std::move(record));
    return true;
  }

  const PendingTelemetry* oldest() const {
    return records_.empty() ? nullptr : &records_.front();
  }

  bool removeOldest(const std::string& eventId) {
    if (records_.empty() || records_.front().eventId != eventId) return false;
    records_.pop_front();
    return true;
  }

  std::size_t size() const { return records_.size(); }

 private:
  std::size_t capacity_;
  std::deque<PendingTelemetry> records_;
};

}  // namespace smart_safety
