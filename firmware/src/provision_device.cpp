#include <Arduino.h>
#include <Preferences.h>
#include <esp_system.h>
#include <mbedtls/base64.h>

#include <array>
#include <string>
#include <vector>

#ifndef SMART_SAFETY_PROVISIONER_BUILD
#define SMART_SAFETY_PROVISIONER_BUILD 0
#endif

#if SMART_SAFETY_PROVISIONER_BUILD
namespace {

String readLine(const char* prompt) {
  Serial.println(prompt);
  while (!Serial.available()) delay(20);
  String value = Serial.readStringUntil('\n');
  value.trim();
  return value;
}

bool decodeBase64(const String& encoded, std::string& decoded) {
  std::size_t required = 0;
  const auto first = mbedtls_base64_decode(
      nullptr, 0, &required,
      reinterpret_cast<const unsigned char*>(encoded.c_str()), encoded.length());
  if (first != MBEDTLS_ERR_BASE64_BUFFER_TOO_SMALL || required == 0) return false;
  std::vector<unsigned char> buffer(required);
  std::size_t actual = 0;
  if (mbedtls_base64_decode(
          buffer.data(), buffer.size(), &actual,
          reinterpret_cast<const unsigned char*>(encoded.c_str()),
          encoded.length()) != 0) {
    return false;
  }
  decoded.assign(reinterpret_cast<const char*>(buffer.data()), actual);
  return true;
}

String encodeBase64(const unsigned char* data, std::size_t length) {
  std::size_t required = 0;
  mbedtls_base64_encode(nullptr, 0, &required, data, length);
  std::vector<unsigned char> output(required + 1, 0);
  std::size_t actual = 0;
  if (mbedtls_base64_encode(output.data(), output.size(), &actual, data,
                            length) != 0) {
    return {};
  }
  return String(reinterpret_cast<const char*>(output.data())).substring(0, actual);
}

}  // namespace

void setup() {
  Serial.begin(115200);
  Serial.setTimeout(300000);
  delay(1000);
  Serial.println("Smart Safety staged local provisioner.");
  Serial.println("1 = initialize device identity and generate secret once");
  Serial.println("2 = configure endpoint/TLS/Wi-Fi without changing identity");
  const String stage = readLine("Select stage 1 or 2:");
  Preferences preferences;
  if (!preferences.begin("ss_device", false)) {
    Serial.println("Provisioning failed: NVS unavailable.");
    return;
  }

  if (stage == "1") {
    if (preferences.isKey("secret")) {
      preferences.end();
      Serial.println(
          "Identity already exists. Refusing to replace or rotate its secret.");
      return;
    }
    const String helmet = readLine("Helmet ID (expected: helmet001):");
    const String keyVersion = readLine("Credential version (for example v1):");
    if (helmet != "helmet001" || keyVersion.length() == 0) {
      preferences.end();
      Serial.println("Identity initialization rejected: invalid identity.");
      return;
    }
    std::array<unsigned char, 32> secret{};
    esp_fill_random(secret.data(), secret.size());
    const String secretBase64 = encodeBase64(secret.data(), secret.size());
    const bool stored = preferences.putString("helmet", helmet) > 0 &&
                        preferences.putString("keyver", keyVersion) > 0 &&
                        preferences.putString("secret", secretBase64) > 0;
    preferences.end();
    if (!stored) {
      Serial.println("Identity initialization failed: NVS write incomplete.");
      return;
    }
    Serial.println(
        "Identity stored. Enter this one-time test secret into Firebase Secret Manager:");
    Serial.println(secretBase64);
    Serial.println(
        "It will not be printed again. Deploy the function before running stage 2.");
    return;
  }

  if (stage == "2") {
    const String existingHelmet = preferences.getString("helmet", "");
    const String existingKeyVersion = preferences.getString("keyver", "");
    if (!preferences.isKey("secret") || existingHelmet != "helmet001" ||
        existingKeyVersion.length() == 0) {
      preferences.end();
      Serial.println("Network configuration refused: initialize identity first.");
      return;
    }
    const String endpoint =
        readLine("Deployed HTTPS ingestTelemetry function URL:");
    const String ssid = readLine("Wi-Fi SSID:");
    const String password =
        readLine("Wi-Fi password (input is not printed by firmware):");
    const String rootCaBase64 =
        readLine("Base64-encoded PEM root CA for the endpoint:");
    std::string rootCa;
    if (!endpoint.startsWith("https://") || ssid.length() == 0 ||
        !decodeBase64(rootCaBase64, rootCa)) {
      preferences.end();
      Serial.println("Network configuration rejected: invalid configuration.");
      return;
    }
    const bool stored = preferences.putString("endpoint", endpoint) > 0 &&
                        preferences.putString("ssid", ssid) > 0 &&
                        preferences.putString("wifi_pass", password) > 0 &&
                        preferences.putString("root_ca", rootCa.c_str()) > 0;
    preferences.end();
    Serial.println(stored
                       ? "Network configuration stored; device secret unchanged."
                       : "Network configuration failed: NVS write incomplete.");
    return;
  }

  preferences.end();
  Serial.println("Provisioning rejected: select stage 1 or 2.");
}

void loop() { delay(1000); }
#endif
