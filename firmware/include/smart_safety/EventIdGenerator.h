#pragma once

#include <cstdint>
#include <string>

namespace smart_safety {

class EventIdGenerator {
 public:
  EventIdGenerator(std::string helmetId, std::string bootSessionId);

  std::string next();

 private:
  static std::string safeComponent(const std::string& value);

  std::string helmetId_;
  std::string bootSessionId_;
  std::uint64_t sequence_{0};
};

}  // namespace smart_safety

