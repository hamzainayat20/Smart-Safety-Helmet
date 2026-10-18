#pragma once

#include <cstdint>
#include <string>

namespace smart_safety {

class SecureIngestionProtocol {
 public:
  static std::string signingPath(const std::string& helmetId);
  static std::string canonicalRequest(const std::string& helmetId,
                                      std::uint64_t requestTimestampMs,
                                      const std::string& nonce,
                                      const std::string& bodySha256Hex);
};

}  // namespace smart_safety
