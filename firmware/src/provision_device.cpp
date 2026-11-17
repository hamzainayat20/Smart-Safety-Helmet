#include <Arduino.h>
#include <Preferences.h>
#include <mbedtls/base64.h>

#include <algorithm>
#include <cctype>
#include <string>
#include <vector>

#ifndef SMART_SAFETY_PROVISIONER_BUILD
#define SMART_SAFETY_PROVISIONER_BUILD 0
#endif

#if SMART_SAFETY_PROVISIONER_BUILD
namespace {

// The expected helmet identity for this prototype. The credential itself is
// owned by AWS SSM (/smart-safety/staging/configuration, key
// helmetDeviceSecrets.helmet001) and is imported here, never generated, so the
// deployed ingestion Lambda and the device always share the same secret.
constexpr char kExpectedHelmetId[] = "helmet001";

String readLine(const char* prompt) {
  Serial.println(prompt);
  String value = Serial.readStringUntil('\n');
  value.trim();
  return value;
}

bool decodeBase64(const String& encoded, std::vector<unsigned char>& decoded) {
  std::size_t required = 0;
  const auto first = mbedtls_base64_decode(
      nullptr, 0, &required,
      reinterpret_cast<const unsigned char*>(encoded.c_str()), encoded.length());
  if (first != MBEDTLS_ERR_BASE64_BUFFER_TOO_SMALL || required == 0) return false;
  decoded.assign(required, 0);
  std::size_t actual = 0;
  if (mbedtls_base64_decode(
          decoded.data(), decoded.size(), &actual,
          reinterpret_cast<const unsigned char*>(encoded.c_str()),
          encoded.length()) != 0) {
    return false;
  }
  decoded.resize(actual);
  return true;
}

bool validKeyVersion(const String& value) {
  if (value.length() == 0 || value.length() > 32) return false;
  for (std::size_t index = 0; index < value.length(); ++index) {
    const auto character = static_cast<unsigned char>(value[index]);
    if (!std::isalnum(character) && character != '_' && character != '-' &&
        character != '.') {
      return false;
    }
  }
  return true;
}

void wipe(String& value) {
  for (std::size_t index = 0; index < value.length(); ++index) value[index] = 0;
  value = "";
}

void wipe(std::vector<unsigned char>& value) {
  std::fill(value.begin(), value.end(), 0);
  value.clear();
}

void importCredential(Preferences& preferences) {
  if (preferences.isKey("secret")) {
    Serial.println("A credential already exists. Refusing to overwrite it. Use "
                   "stage 9 to erase it first if it does not match AWS.");
    return;
  }
  const String helmet = readLine("Helmet ID (expected: helmet001):");
  const String keyVersion = readLine("Credential key version from AWS SSM:");
  // The secret is consumed silently: never echoed, logged or printed.
  String secretBase64 = readLine("Credential secretBase64 (not echoed):");
  std::vector<unsigned char> secret;
  const bool decoded = decodeBase64(secretBase64, secret);
  const bool valid = helmet == kExpectedHelmetId && validKeyVersion(keyVersion) &&
                     decoded && secret.size() >= 32;
  const std::size_t secretBytes = secret.size();
  wipe(secret);
  if (!valid) {
    wipe(secretBase64);
    Serial.println("Credential import rejected: invalid helmet ID, key "
                   "version or secret (must decode to at least 32 bytes).");
    return;
  }
  const bool stored = preferences.putString("helmet", helmet) > 0 &&
                      preferences.putString("keyver", keyVersion) > 0 &&
                      preferences.putString("secret", secretBase64) > 0;
  wipe(secretBase64);
  Serial.printf("%s helmet=%s keyVersion=%s secretBytes=%u (secret not "
                "printed).\n",
                stored ? "Credential imported:" : "Credential import FAILED:",
                helmet.c_str(), keyVersion.c_str(),
                static_cast<unsigned>(secretBytes));
}

void configureNetwork(Preferences& preferences) {
  if (!preferences.isKey("secret") ||
      preferences.getString("helmet", "") != kExpectedHelmetId) {
    Serial.println("Network configuration refused: import the credential "
                   "first (stage 1).");
    return;
  }
  const String endpoint = readLine("HTTPS telemetry endpoint URL:");
  const String ssid = readLine("Wi-Fi SSID:");
  String password = readLine("Wi-Fi password (not echoed):");
  const String rootCaBase64 =
      readLine("Base64-encoded PEM root CA bundle for the endpoint:");
  std::vector<unsigned char> rootCa;
  if (!endpoint.startsWith("https://") || ssid.length() == 0 ||
      !decodeBase64(rootCaBase64, rootCa) || rootCa.size() > 3900) {
    wipe(password);
    Serial.println("Network configuration rejected: invalid endpoint, SSID or "
                   "root CA bundle.");
    return;
  }
  const std::string rootCaPem(rootCa.begin(), rootCa.end());
  const bool stored = preferences.putString("endpoint", endpoint) > 0 &&
                      preferences.putString("ssid", ssid) > 0 &&
                      preferences.putString("wifi_pass", password) > 0 &&
                      preferences.putString("root_ca", rootCaPem.c_str()) > 0;
  wipe(password);
  Serial.println(stored
                     ? "Network configuration stored; credential unchanged."
                     : "Network configuration FAILED: NVS write incomplete.");
}

void printStatus(Preferences& preferences) {
  // Presence only. Never prints the secret, Wi-Fi password or SSID.
  Serial.printf("helmet=%s keyVersion=%s credential=%s endpoint=%s wifi=%s "
                "rootCa=%s\n",
                preferences.getString("helmet", "(none)").c_str(),
                preferences.getString("keyver", "(none)").c_str(),
                preferences.isKey("secret") ? "present" : "absent",
                preferences.getString("endpoint", "(none)").c_str(),
                preferences.isKey("ssid") ? "configured" : "absent",
                preferences.isKey("root_ca") ? "present" : "absent");
}

void eraseIdentity(Preferences& preferences) {
  const String confirmation =
      readLine("Type ERASE helmet001 to delete the stored identity and "
               "network configuration:");
  if (confirmation != "ERASE helmet001") {
    Serial.println("Erase cancelled.");
    return;
  }
  Serial.println(preferences.clear() ? "Identity and network configuration "
                                       "erased."
                                     : "Erase FAILED.");
}

}  // namespace

void setup() {
  // Root CA bundles arrive as one long line; keep them from overrunning RX.
  Serial.setRxBufferSize(4096);
  Serial.begin(115200);
  Serial.setTimeout(300000);
  delay(1000);
  Serial.println("Smart Safety local provisioner (AWS SSM credential import).");
  Serial.println("1 = import existing helmet001 credential from AWS SSM");
  Serial.println("2 = configure endpoint / TLS root CA / Wi-Fi");
  Serial.println("3 = show provisioning status (no secrets)");
  Serial.println("9 = erase stored identity and network configuration");
  const String stage = readLine("Select stage 1, 2, 3 or 9:");
  Preferences preferences;
  if (!preferences.begin("ss_device", false)) {
    Serial.println("Provisioning failed: NVS unavailable.");
    return;
  }
  if (stage == "1") {
    importCredential(preferences);
  } else if (stage == "2") {
    configureNetwork(preferences);
  } else if (stage == "3") {
    printStatus(preferences);
  } else if (stage == "9") {
    eraseIdentity(preferences);
  } else {
    Serial.println("Provisioning rejected: select stage 1, 2, 3 or 9.");
  }
  preferences.end();
  Serial.println("Provisioner finished. Press EN/RESET to run another stage.");
}

void loop() { delay(1000); }
#endif
