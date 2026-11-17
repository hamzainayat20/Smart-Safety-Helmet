# Staging telemetry ingestion

> **Superseded deployment notes.** The deployed staging backend is now AWS
> (API Gateway + ingestion Lambda + private inference Lambda, stack
> `smart-safety-staging`). Device credentials live in the encrypted SSM
> parameter `/smart-safety/staging/configuration`, not in Firebase or Google
> Secret Manager, and the Firebase `ingestTelemetry` function is not the
> device endpoint. The signing contract, validation rules and RTDB projection
> described below are unchanged and still implemented by the shared code in
> `functions/src/`. For current device provisioning, build and validation use
> `firmware/README.md` and `aws/README.md`.

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

## Device credential format

The deployed AWS ingestion Lambda reads the helmet credential registry from
the `helmetDeviceSecrets` object inside the encrypted SSM SecureString
`/smart-safety/staging/configuration` (see `aws/configuration-secret.example.json`).
Use a different random 32-byte-or-longer secret for every physical helmet:

```json
{
  "helmet001": {
    "keyVersion": "v1",
    "secretBase64": "<NEVER_COMMITTED>",
    "revoked": false
  }
}
```

HMAC verification requires both sides to hold the plaintext key; it is not a
one-way hash. The key exists only in that SSM parameter and in the ESP32's NVS.
It is never committed, logged, printed, or placed in a command argument,
`.env` file or build flag. The Lambda decrypts the parameter once per cold
start and caches it per warm execution environment, so a rotated key is only
honoured after those environments reload.

The ESP32 receives the **existing** SSM credential through
`aws/scripts/provision-helmet-device.ps1 -Stage Credential`, which streams it
over USB into the provisioner firmware without displaying it. No rotation or
redeployment is involved.

## ESP32 targets

The default target remains network-disabled:

```text
pio run -e esp32dev
```

The provisioner firmware no longer generates secrets. Its stages are:
1 = import the existing `helmet001` credential from AWS SSM, 2 = store
endpoint / TLS root CA / Wi-Fi, 3 = show status (no secrets), 9 = erase. Stage
1 refuses to overwrite an existing credential. The controlled order is:

1. `pio run -e esp32dev_provisioner --target upload --upload-port COM4`
2. `aws/scripts/provision-helmet-device.ps1 -Stage Credential -Port COM4`
3. `aws/scripts/provision-helmet-device.ps1 -Stage Network -Port COM4`
   (verifies the live endpoint chain against Amazon Trust Services roots)
4. `pio run -e esp32dev_staging --target upload --upload-port COM4`
5. `pio device monitor --baud 115200 --port COM4` and wait for
   `UPLOAD accepted ... assessmentStatus=completed`.

The endpoint is the deployed API Gateway URL
(`.../staging/v1/telemetry`), but the device signs the canonical path
`/ingest/v1/helmets/{helmetId}/telemetry`. Do not disable certificate
validation. Full details: `firmware/README.md`.

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

- Physical device provisioning and the first signed physical upload must be
  performed and observed on the real hardware.
- NVS/flash encryption and ESP32 secure boot must be enabled and physically
  validated before treating stored credentials as production-protected.
- Credential rotation requires writing a new key version to the SSM
  parameter, importing it into the device, and allowing every warm ingestion
  Lambda environment to reload during a controlled overlap window.
- Revocation is available through the backend secret registry and inactive or
  unprovisioned helmet metadata, but no administrative provisioning UI is added.
- The buffer is RAM-backed and survives network loss but not power loss.
- MQ-7 is raw ADC only (no ppm, no gas classification); DHT22 and MQ-135 are
  absent; GPS, battery and alert outputs remain unavailable.
- Physical ESP32, Wi-Fi, TLS, Firebase deployment, and end-to-end behavior must
  not be considered validated until run on the actual staging hardware.
