#include "smart_safety/SecureIngestionClient.h"

#include <Arduino.h>
#include <HTTPClient.h>
#include <Preferences.h>
#include <WiFi.h>
#include <WiFiClientSecure.h>
#include <esp_system.h>
#include <mbedtls/base64.h>
#include <mbedtls/md.h>
#include <sys/time.h>

#include <algorithm>
#include <array>
#include <cctype>
#include <ctime>
#include <deque>
#include <iomanip>
#include <sstream>
#include <utility>
#include <vector>

#include "smart_safety/FirmwareConfig.h"
#include "smart_safety/OfflineBuffer.h"
#include "smart_safety/SecureIngestionProtocol.h"

namespace smart_safety {
namespace {

std::string hex(const unsigned char* bytes, std::size_t length) {
  std::ostringstream output;
  output << std::hex << std::setfill('0');
  for (std::size_t index = 0; index < length; ++index) {
    output << std::setw(2) << static_cast<unsigned int>(bytes[index]);
  }
  return output.str();
}

bool sha256(const std::string& value, std::array<unsigned char, 32>& output) {
  const auto* info = mbedtls_md_info_from_type(MBEDTLS_MD_SHA256);
  return info != nullptr &&
         mbedtls_md(info,
                    reinterpret_cast<const unsigned char*>(value.data()),
                    value.size(), output.data()) == 0;
}

bool hmacSha256(const std::vector<unsigned char>& secret,
                const std::string& value,
                std::array<unsigned char, 32>& output) {
  const auto* info = mbedtls_md_info_from_type(MBEDTLS_MD_SHA256);
  return info != nullptr &&
         mbedtls_md_hmac(info, secret.data(), secret.size(),
                         reinterpret_cast<const unsigned char*>(value.data()),
                         value.size(), output.data()) == 0;
}

bool decodeBase64(const std::string& encoded,
                  std::vector<unsigned char>& decoded) {
  std::size_t required = 0;
  const auto first = mbedtls_base64_decode(
      nullptr, 0, &required,
      reinterpret_cast<const unsigned char*>(encoded.data()), encoded.size());
  if (first != MBEDTLS_ERR_BASE64_BUFFER_TOO_SMALL || required == 0) return false;
  decoded.resize(required);
  std::size_t actual = 0;
  return mbedtls_base64_decode(
             decoded.data(), decoded.size(), &actual,
             reinterpret_cast<const unsigned char*>(encoded.data()),
             encoded.size()) == 0 &&
         (decoded.resize(actual), true);
}

std::string nonce() {
  std::array<unsigned char, 16> bytes{};
  for (std::size_t index = 0; index < bytes.size(); index += 4) {
    const auto value = esp_random();
    std::copy_n(reinterpret_cast<const unsigned char*>(&value), 4,
                bytes.begin() + index);
  }
  return hex(bytes.data(), bytes.size());
}

bool validSafeId(const std::string& value) {
  if (value.empty() || value.size() > 128) return false;
  return std::all_of(value.begin(), value.end(), [](unsigned char character) {
    return std::isalnum(character) || character == '_' || character == '-';
  });
}

bool validKeyVersion(const std::string& value) {
  if (value.empty() || value.size() > 32) return false;
  return std::all_of(value.begin(), value.end(), [](unsigned char character) {
    return std::isalnum(character) || character == '_' || character == '-' ||
           character == '.';
  });
}

}  // namespace

struct SecureIngestionClient::Impl {
  std::string helmetId;
  std::string keyVersion;
  std::string endpointUrl;
  std::string wifiSsid;
  std::string wifiPassword;
  std::string rootCaPem;
  std::vector<unsigned char> secret;
  OfflineBuffer buffer{config::kOfflineBufferCapacity};
  SemaphoreHandle_t mutex{xSemaphoreCreateMutex()};
  bool ready{false};
  std::uint32_t retryDelayMs{1000};
  std::string assessmentStatus;

  ~Impl() {
    if (mutex != nullptr) vSemaphoreDelete(mutex);
  }

  bool load() {
    Preferences preferences;
    if (!preferences.begin("ss_device", true)) return false;
    helmetId = preferences.getString("helmet", "").c_str();
    keyVersion = preferences.getString("keyver", "").c_str();
    endpointUrl = preferences.getString("endpoint", "").c_str();
    wifiSsid = preferences.getString("ssid", "").c_str();
    wifiPassword = preferences.getString("wifi_pass", "").c_str();
    rootCaPem = preferences.getString("root_ca", "").c_str();
    const std::string secretBase64 = preferences.getString("secret", "").c_str();
    preferences.end();
    ready = validSafeId(helmetId) && validKeyVersion(keyVersion) &&
            endpointUrl.rfind("https://", 0) == 0 && !wifiSsid.empty() &&
            !rootCaPem.empty() && decodeBase64(secretBase64, secret) &&
            secret.size() >= 32;
    return ready;
  }

  static void taskEntry(void* context) {
    static_cast<Impl*>(context)->run();
  }

  void connectWifi() {
    if (WiFi.status() == WL_CONNECTED) return;
    WiFi.mode(WIFI_STA);
    WiFi.begin(wifiSsid.c_str(), wifiPassword.c_str());
    const auto started = millis();
    while (WiFi.status() != WL_CONNECTED && millis() - started < 10000) {
      vTaskDelay(pdMS_TO_TICKS(100));
    }
    if (WiFi.status() == WL_CONNECTED) {
      configTime(0, 0, "time.google.com", "pool.ntp.org");
    }
  }

  bool peek(PendingTelemetry& output) {
    if (xSemaphoreTake(mutex, pdMS_TO_TICKS(50)) != pdTRUE) return false;
    const auto* pending = buffer.oldest();
    if (pending != nullptr) output = *pending;
    xSemaphoreGive(mutex);
    return pending != nullptr;
  }

  void remove(const std::string& eventId) {
    if (xSemaphoreTake(mutex, pdMS_TO_TICKS(50)) != pdTRUE) return;
    buffer.removeOldest(eventId);
    xSemaphoreGive(mutex);
  }

  int send(const PendingTelemetry& pending) {
    const auto nowMs = utcNowMs();
    if (nowMs == 0 || WiFi.status() != WL_CONNECTED) return -1;
    std::array<unsigned char, 32> bodyHash{};
    if (!sha256(pending.json, bodyHash)) return -1;
    const std::string requestNonce = nonce();
    const auto canonical = SecureIngestionProtocol::canonicalRequest(
        helmetId, nowMs, requestNonce, hex(bodyHash.data(), bodyHash.size()));
    std::array<unsigned char, 32> signature{};
    if (!hmacSha256(secret, canonical, signature)) return -1;

    WiFiClientSecure tls;
    tls.setCACert(rootCaPem.c_str());
    HTTPClient http;
    http.setTimeout(config::kNetworkRequestTimeoutMs);
    if (!http.begin(tls, endpointUrl.c_str())) return -1;
    http.addHeader("Content-Type", "application/json");
    http.addHeader("X-Smart-Safety-Helmet-Id", helmetId.c_str());
    const auto nowText = std::to_string(nowMs);
    http.addHeader("X-Smart-Safety-Timestamp", nowText.c_str());
    http.addHeader("X-Smart-Safety-Nonce", requestNonce.c_str());
    http.addHeader("X-Smart-Safety-Key-Version", keyVersion.c_str());
    const auto signatureHex = hex(signature.data(), signature.size());
    http.addHeader("X-Smart-Safety-Signature", signatureHex.c_str());
    const int status = http.POST(reinterpret_cast<std::uint8_t*>(
                                     const_cast<char*>(pending.json.data())),
                                 pending.json.size());
    assessmentStatus.clear();
    if (status == 200 || status == 202) {
      // Only the backend-reported assessmentStatus is extracted for logging;
      // the response body itself is never printed.
      const std::string body = http.getString().c_str();
      const std::string key = "\"assessmentStatus\":\"";
      const auto start = body.find(key);
      if (start != std::string::npos) {
        const auto valueStart = start + key.size();
        const auto end = body.find('"', valueStart);
        if (end != std::string::npos && end - valueStart <= 32) {
          assessmentStatus = body.substr(valueStart, end - valueStart);
        }
      }
    }
    http.end();
    return status;
  }

  // Milliseconds since the UTC epoch once SNTP has set the clock, else 0.
  std::uint64_t utcNowMs() const {
    timeval now{};
    if (gettimeofday(&now, nullptr) != 0 || now.tv_sec < 1700000000) return 0;
    return static_cast<std::uint64_t>(now.tv_sec) * 1000ULL +
           static_cast<std::uint64_t>(now.tv_usec / 1000);
  }

  void run() {
    for (;;) {
      connectWifi();
      PendingTelemetry pending;
      if (!peek(pending)) {
        vTaskDelay(pdMS_TO_TICKS(100));
        continue;
      }
      const int status = send(pending);
      if (status == 200 || status == 202) {
        Serial.printf("UPLOAD accepted event=%s status=%d assessmentStatus=%s\n",
                      pending.eventId.c_str(), status,
                      assessmentStatus.empty() ? "unknown"
                                               : assessmentStatus.c_str());
        remove(pending.eventId);
        retryDelayMs = 1000;
      } else if (status == 400 || status == 409 || status == 413 ||
                 status == 415) {
        // A contract/auth/conflict rejection cannot be repaired by retrying the
        // identical event. Log only the status and event ID, never body/secret.
        Serial.printf("UPLOAD rejected event=%s status=%d (contract or conflict; not retried)\n",
                      pending.eventId.c_str(), status);
        remove(pending.eventId);
        retryDelayMs = 1000;
      } else {
        if (status == 401 || status == 403) {
          Serial.printf("UPLOAD unauthorized event=%s status=%d (helmet "
                        "credential or key version does not match AWS SSM; "
                        "re-run provisioning). Retrying with back-off.\n",
                        pending.eventId.c_str(), status);
        } else {
          Serial.printf("UPLOAD retry event=%s status=%d wifi=%s timeSync=%s\n",
                        pending.eventId.c_str(), status,
                        WiFi.status() == WL_CONNECTED ? "connected" : "down",
                        utcNowMs() != 0 ? "yes" : "no");
        }
        const auto jitter = esp_random() % 251U;
        vTaskDelay(pdMS_TO_TICKS(retryDelayMs + jitter));
        retryDelayMs = std::min<std::uint32_t>(retryDelayMs * 2U, 30000U);
      }
    }
  }
};

SecureIngestionClient::SecureIngestionClient() : impl_(new Impl()) {}
SecureIngestionClient::~SecureIngestionClient() = default;

bool SecureIngestionClient::begin() {
  if (impl_->mutex == nullptr || !impl_->load()) return false;
  const bool started =
      xTaskCreatePinnedToCore(Impl::taskEntry, "telemetry-upload", 12288,
                              impl_.get(), 1, nullptr, 0) == pdPASS;
  if (!started) impl_->ready = false;
  return started;
}

bool SecureIngestionClient::enqueue(std::string eventId,
                                    std::string canonicalJson) {
  if (!impl_->ready ||
      xSemaphoreTake(impl_->mutex, pdMS_TO_TICKS(20)) != pdTRUE) {
    return false;
  }
  const bool added = impl_->buffer.push(
      PendingTelemetry{std::move(eventId), std::move(canonicalJson)});
  xSemaphoreGive(impl_->mutex);
  return added;
}

bool SecureIngestionClient::configured() const { return impl_->ready; }
bool SecureIngestionClient::timeSynchronized() const {
  return impl_->utcNowMs() != 0;
}
std::uint64_t SecureIngestionClient::utcNowMs() const {
  return impl_->utcNowMs();
}
const std::string& SecureIngestionClient::helmetId() const {
  return impl_->helmetId;
}

}  // namespace smart_safety
