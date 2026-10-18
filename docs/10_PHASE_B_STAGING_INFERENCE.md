# Phase B staging inference integration

## Implemented flow

Phase B connects the Phase A components without changing the device trust boundary:

```text
signed schema-2 telemetry
        |
        v
ingestTelemetry -> /readings/{helmetId}/{eventId}
                         |
                         v
                 assessTelemetry trigger
                         |
                  Google identity token
                         |
                         v
              private Cloud Run inference
                         |
                         v
 /assessments/{helmetId}/{eventId}
 /helmets/{helmetId}/currentAssessment -> existing Flutter listener
```

`assessTelemetry` is creation-triggered, so duplicate ingestion repairs do not
create duplicate inference events. The processor also checks immutable history
before calling the models, making explicit retries idempotent. Assessment jobs
are recorded under `/assessmentJobs/{helmetId}/{eventId}` with only status,
attempt timestamps, count, and an allowlisted error code. Firebase clients
cannot read or write this operational branch.

The inference client:

- permits HTTPS only, except explicit localhost test mode;
- obtains a Google identity token for the Cloud Run audience;
- sends only canonical model-input fields;
- applies a timeout and response-size bound;
- validates the complete assessment contract before trusted persistence;
- never stores or logs a bearer token, telemetry body, or free-form model text.

Failure never creates a fabricated assessment. Flutter continues to show the
existing pending/unavailable state and never treats inference failure as safe.

## Local simulated verification

No physical hardware is required. Install Python dependencies and run:

```powershell
$env:PHASE_B_PYTHON = "$PWD\inference_service\.venv\Scripts\python.exe"
npm run test:phase-b
```

The smoke test launches the real FastAPI service, verifies both model checksums,
sends one schema-2 simulated reading through the trusted Node pipeline, writes
assessment history and current projection to the Realtime Database emulator,
and repeats the event to prove idempotency.

## Controlled staging deployment

Deployment requires a billing-enabled Google Cloud/Firebase staging project,
the Google Cloud CLI, and an approved operator. It is intentionally not
performed by repository tests.

1. Build and deploy `inference_service` to Cloud Run in `us-central1` with
   unauthenticated access disabled.
2. Grant `roles/run.invoker` on that service only to the Firebase Functions
   runtime service account.
3. Set the Firebase Functions string parameter `INFERENCE_SERVICE_URL` to the
   HTTPS Cloud Run origin. Do not place credentials in this value.
4. Deploy `assessTelemetry`, `ingestTelemetry`, and Realtime Database rules only
   after reviewing the planned resource changes.
5. Submit a signed simulated schema-2 event and verify all four paths:

```text
/readings/helmet001/{eventId}
/helmets/helmet001/current
/assessments/helmet001/{eventId}
/helmets/helmet001/currentAssessment
```

Do not make Cloud Run public, embed a service-account key, weaken client rules,
or treat prototype environmental thresholds as approved field limits.

## Remaining physical validation

MQ-7/MQ-135 calibration, helmet-mounted fall-window extraction, TLS from the
ESP32, offline replay, and live sensor behavior remain Phase C hardware work.
The checked-in gas model consumes raw dataset-scale MQ-7/MQ-135 inputs, not ppm,
and the system is not a certified safety device.
