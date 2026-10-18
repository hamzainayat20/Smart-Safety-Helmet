#include "smart_safety/SecureIngestionProtocol.h"

namespace smart_safety {

std::string SecureIngestionProtocol::signingPath(const std::string& helmetId) {
  return "/ingest/v1/helmets/" + helmetId + "/telemetry";
}

std::string SecureIngestionProtocol::canonicalRequest(
    const std::string& helmetId, std::uint64_t requestTimestampMs,
    const std::string& nonce, const std::string& bodySha256Hex) {
  return "POST\n" + signingPath(helmetId) + "\n" +
         std::to_string(requestTimestampMs) + "\n" + nonce + "\n" +
         bodySha256Hex;
}

}  // namespace smart_safety
