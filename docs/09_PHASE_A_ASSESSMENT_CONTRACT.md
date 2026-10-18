# Phase A safety assessment contract

## Local integration boundary

Telemetry ingestion remains the public device trust boundary. The ESP32 sends a
signed schema-2.0 payload to `ingestTelemetry`; it never writes Realtime Database
directly and it never invokes a model directly.

Schema 2.0 carries separate `mq7Raw` and `mq135Raw` values plus the exact
nine-field, 50 Hz, 100-sample fall feature window. If that window cannot be
created, the device must omit the whole window and send `mpuReadFailed` or
`fallWindowUnavailable`; fabricated zero features are rejected.

The Python inference service is a private, trusted component. It loads the two
verified XGBoost artifacts, evaluates a stored telemetry event, applies the
deterministic risk engine and approved recommendation library, then hands one
canonical assessment to trusted backend persistence. Phase A does not add a
public assessment-write endpoint and does not deploy this service.

```text
ESP32 -> HTTPS ingestion -> telemetry history/current
                              |
                              v
                    private inference service
                              |
                              v
                 assessment history/current -> Flutter
```

## Canonical assessment

`functions/src/assessment_contract.js` is the Node-side validation boundary.
An assessment uses schema `1.0` and contains:

- stable `assessmentId`, equal to the source `eventId`;
- `helmetId`, source schema and source/device timestamps;
- `modelBundleVersion`;
- fall status, probability, threshold and model version, or explicit
  `unavailable`;
- gas class (`Mixture`, `NoGas`, `Perfume`, or `Smoke`), confidence, all four
  probabilities, model version and out-of-distribution flag, or explicit
  `unavailable`;
- deterministic temperature, humidity and heat-index risk states;
- `overallRisk`: `unknown`, `safe`, `warning`, or `critical`;
- allowlisted reason and recommendation codes.

Free-form model advice is not stored. The Flutter application maps approved
recommendation codes to reviewed display text. `safe` is rejected when a model
or environmental result is unavailable, or when gas input is out of
distribution.

Environmental rules are read from
`inference_service/config/environment_thresholds.json`. The checked-in values
are clearly marked as unapproved prototype defaults so they can support
simulation without pretending that final site thresholds have been selected.
Supervisor-approved values and physical validation are required before field
deployment.

## Firebase storage

Trusted backend code writes immutable history and one order-aware current
projection:

```text
/assessments/{helmetId}/{eventId}
/helmets/{helmetId}/currentAssessment
```

`persistSafetyAssessment` validates before writing. Repeating the identical
event is idempotent; reusing an event ID for different assessment content is a
conflict. The helper also requires the source history event to exist and match
the assessment's helmet, event, schema and source timestamps. Current ordering
uses `deviceTimestamp` and then ASCII `eventId`, so
offline replay of an older event cannot replace a newer result.

Realtime Database clients cannot write either path. A verified active worker,
supervisor, or administrator can read only assessments permitted by the same
helmet/site/worker assignment checks already used for telemetry. The Rules
Emulator tests cover same-helmet reads, cross-helmet denial and client-write
denial for all roles.

## Current limitations

- No Firebase deployment was performed.
- No public inference endpoint was added.
- Model output has been validated with simulated payloads only.
- Physical ESP32 sampling, field calibration and end-to-end hardware behavior
  remain unverified.
- MQ-7 and MQ-135 values are raw ADC model inputs, not ppm or a regulatory air
  quality measurement.
