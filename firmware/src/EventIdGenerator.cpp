#include "smart_safety/EventIdGenerator.h"

#include <cctype>
#include <utility>

namespace smart_safety {

EventIdGenerator::EventIdGenerator(std::string helmetId,
                                   std::string bootSessionId)
    : helmetId_(safeComponent(helmetId)),
      bootSessionId_(safeComponent(bootSessionId)) {}

std::string EventIdGenerator::next() {
  ++sequence_;
  return helmetId_ + "_" + bootSessionId_ + "_" +
         std::to_string(sequence_);
}

std::string EventIdGenerator::safeComponent(const std::string& value) {
  std::string result;
  result.reserve(value.size());
  for (const unsigned char character : value) {
    if (result.size() >= 48) break;
    result.push_back(std::isalnum(character) || character == '_' ||
                             character == '-'
                         ? static_cast<char>(character)
                         : '_');
  }
  return result.empty() ? "unknown" : result;
}

}  // namespace smart_safety
