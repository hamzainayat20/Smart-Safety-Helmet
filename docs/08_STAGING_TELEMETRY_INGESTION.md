# Staging telemetry ingestion

This document contains no credentials. The implementation is configuration-
ready but is not deployed or provisioned by the repository changes alone.

## Data flow

The ESP32 never writes Firebase Realtime Database directly:

```text
helmet001 -> HTTPS ingestTelemetry -> authentication/validation
          -> /helmets/helmet001/current
          -> /readings/helmet001/{eventId}
          -> existing Flutter RTDB listener
```

The Cloud Function accepts the backward-compatible schema `1.0` contract and
the strict Phase A schema `2.0` model-input contract. It
adds `serverReceivedAt`, `connectivity: online`, and `severity: unassessed` after
validation. Ingestion itself creates no alerts and performs no model inference;
the private inference boundary described in the Phase A assessment contract
owns that work.

## Request protocol

The device sends `application/json` with these headers:

- `X-Smart-Safety-Helmet-Id`
- `X-Smart-Safety-Timestamp` (UTC epoch milliseconds)
- `X-Smart-Safety-Nonce` (16 random bytes encoded as 32 hexadecimal characters)
- `X-Smart-Safety-Key-Version`
- `X-Smart-Safety-Signature` (lowercase hexadecimal HMAC-SHA256)

The HMAC input is exactly:

```text
POST
/ingest/v1/helmets/{helmetId}/telemetry
{requestTimestampMs}
{nonce}
{lowercaseHexSha256OfExactBodyBytes}
```

The backend enforces an 8 KiB limit, a five-minute authentication timestamp
window, one-time nonces, a default rate of 30 accepted attempts per helmet per
minute, helmet ownership, active/provisioned metadata, strict field/range
validation, and event-ID semantic deduplication. The signature, credential, and
request body are never logged.

Every accepted unique event is reconciled into history. Current-reading order is
determined first by `deviceTimestamp`; for equal timestamps the lexicographically
greater ASCII `eventId` wins. `serverReceivedAt` is deliberately not an ordering
input. The dedupe reservation owns an immutable `firstReceivedAt`, which becomes
the event's stable `serverReceivedAt` on the first attempt and every repair.
Stored duplicates still verify/repair missing history and current projections,
and the dedupe status changes to `stored` only after both reconciliations finish.

## Secret Manager format

`HELMET_DEVICE_SECRETS` is a Firebase Functions secret containing JSON. Use a
different random 32-byte-or-longer secret for every physical helmet:

```json
{
  "helmet001": {
    "keyVersion": "v1",
    "secretBase64": "<ONE_TIME_BASE64_DEVICE_SECRET>",
    "revoked": false
  }
}
```

HMAC verification requires both sides to possess the plaintext HMAC key. It is
not stored merely as a one-way hash. After the controlled one-time transfer, the
plaintext key exists only in ESP32 protected storage and Google Secret Manager.
Secret Manager protects the backend copy at rest and controls runtime access.
The key is never committed or logged. ESP32 flash/NVS encryption and secure boot
remain mandatory before the device copy is production-protected.

Never add the real value to a command argument, `.env` file, firmware build
flag, repository file, issue, or log. Use the Firebase CLI's interactive secret
input:

```text
firebase functions:secrets:set HELMET_DEVICE_SECRETS
```

Deployment is a separate approved operation performed only after the secret is
present:

```text
firebase deploy --only functions:ingestTelemetry
```

## ESP32 targets

The default target remains network-disabled:

```text
pio run -e esp32dev
```

The staging provisioner has two deliberately separate stages. Stage 1 generates
and stores identity/secret only. If a secret already exists, stage 1 refuses to
replace it. Stage 2 requires that identity, then stores or updates endpoint,
Wi-Fi, and TLS CA without reading, printing, rotating, or replacing the secret.

```text
pio run -e esp32dev_provisioner --target upload --upload-port COMx
pio device monitor --baud 115200 --port COMx
```

The exact controlled order is:

1. Compile and upload `esp32dev_provisioner` after approval.
2. Select stage 1 to store `helmet001`, key version, and a newly generated
   device secret. Transfer the one-time displayed test secret securely.
3. Enter that value interactively into `HELMET_DEVICE_SECRETS` in Google Secret
   Manager. Preserve other helmet entries.
4. Deploy `ingestTelemetry` after separate approval.
5. Obtain the deployed HTTPS endpoint URL and verified TLS root CA.
6. Run the same provisioner again and select stage 2. Configure endpoint, CA,
   and Wi-Fi; the existing device secret is unchanged.
7. Upload the `esp32dev_staging` firmware after separate approval.
8. Make the trusted metadata transition to `provisioningStatus: provisioned`
   only as an approved administrative operation, then perform staging tests.

After those steps, upload the opt-in staging firmware with:

```text
pio run -e esp32dev_staging --target upload --upload-port COMx
pio device monitor --baud 115200 --port COMx
```

The TLS root CA entered during provisioning must be obtained from the deployed
endpoint's verified certificate chain. Do not disable certificate validation.

## Bounded ingestion-state cleanup

Every authenticated request opportunistically removes at most 25 expired child
records from each of that helmet's `/ingestionNonces` and
`/ingestionRateLimits` branches. Selection is deterministic by `expiresAt` then
key, and cleanup failure never changes telemetry acceptance. This bounds work
per request and prevents active helmets from accumulating these records.

Before production, a trusted scheduled administrative sweep must call the same
bounded helper for inactive and revoked helmets, advancing through helmet IDs in
bounded batches. That scheduled export/deployment is intentionally not included
in this local-only batch. Client rules remain default-deny for both branches.

## Production limitations

- Provisioning, Secret Manager changes, metadata activation, and deployment
  have not been executed by this change.
- NVS/flash encryption and ESP32 secure boot must be enabled and physically
  validated before treating stored credentials as production-protected.
- Credential rotation requires provisioning the new version on the device and
  updating Secret Manager during a controlled overlap window.
- Revocation is available through the backend secret registry and inactive or
  unprovisioned helmet metadata, but no administrative provisioning UI is added.
- The buffer is RAM-backed and survives network loss but not power loss.
- MQ-7 acquisition/ppm, GPS, battery, alert generation, and fall-alert upload
  remain disabled.
- Physical ESP32, Wi-Fi, TLS, Firebase deployment, and end-to-end behavior must
  not be considered validated until run on the actual staging hardware.
