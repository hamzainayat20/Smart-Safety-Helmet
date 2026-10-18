#pragma once

#include <cstdint>
#include <memory>
#include <string>

namespace smart_safety {

// Staging transport. It reads a unique helmet identity, Wi-Fi credentials,
// endpoint, HMAC key, and TLS root CA from NVS. It never contains credentials
// in source or build flags and never writes Realtime Database directly.
class SecureIngestionClient {
 public:
  SecureIngestionClient();
  ~SecureIngestionClient();

  SecureIngestionClient(const SecureIngestionClient&) = delete;
  SecureIngestionClient& operator=(const SecureIngestionClient&) = delete;

  bool begin();
  bool enqueue(std::string eventId, std::string canonicalJson);
  bool configured() const;
  bool timeSynchronized() const;
  std::uint64_t utcNowMs() const;
  const std::string& helmetId() const;

 private:
  struct Impl;
  std::unique_ptr<Impl> impl_;
};

}  // namespace smart_safety
