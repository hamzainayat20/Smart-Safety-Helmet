# Phase C: AWS staging deployment

This directory adds AWS deployment adapters without replacing the existing
Flutter, Firebase, firmware, Cloud Functions, Cloud Run, or local inference
paths. Nothing in this directory deploys automatically.

## Architecture

`ESP32 -> API Gateway -> ingestion Lambda -> private inference Lambda -> Firebase RTDB -> Flutter`

`Flutter -> authenticated assistant route -> assistant Lambda -> Groq`

The public endpoint still requires the existing per-helmet HMAC headers. The
inference Lambda has no API Gateway event and is invokable only through IAM.
Both model artifacts are loaded by one private Python function. The ingestion
function reuses the existing telemetry contract, replay protection, rate limit,
dedupe logic, assessment contract, and Firebase storage code.

## Prerequisites

- AWS Free or paid account with sufficient credits.
- AWS CLI, AWS SAM CLI, Docker, and Node.js 22 for deployment builds.
- One AWS region selected for every resource.
- Existing active/provisioned `helmet001` metadata in Firebase staging.
- A dedicated Firebase service account limited to this staging project.
- The exact Firebase RTDB URL.

Do not deploy from a repository containing a downloaded service-account file.
Do not put the configuration secret JSON in firmware, Flutter, source control,
CloudFormation parameters, shell history, or command output.

## Secret shape

`configuration-secret.example.json` documents the required shape. Create one
**standard SecureString** in AWS Systems Manager Parameter Store using the
console, then securely delete any temporary local copy. The same encrypted
parameter contains the Firebase service account and device-secret registry so
only one decrypted read is needed per cold start. Its JSON must remain below
the standard parameter size limit.

The helmet secret must be unique, random, at least 32 bytes, revocable, and
restricted to its matching Helmet ID. The existing signing contract and header
names remain defined in `functions/src/device_auth.js`.

## Build and test (no deployment)

From the repository root:

```powershell
npm install --prefix aws/ingestion
npm test --prefix aws/ingestion
npm install --prefix aws/assistant
npm test --prefix aws/assistant
inference_service\.venv\Scripts\python.exe -m pytest inference_service\tests -q
sam validate --lint --template-file aws/template.yaml
sam build --template-file aws/template.yaml
```

The Lambda image builds use Docker only during deployment preparation. It does not
need to remain running after the image has been uploaded.

## Deployment review gate

Before running `sam deploy --guided`, review:

1. Region and current AWS credit expiry.
2. The CloudFormation change set.
3. API Gateway throttling: 1 request/second with a burst of 5.
4. API Gateway throttling protects this low-quota staging account. Assistant
   concurrency is capped at two; telemetry and inference behavior is unchanged.
5. Seven-day CloudWatch retention.
6. The exact SecureString parameter name and Firebase staging database URL.
7. No production data, credentials, or physical-hardware claims.

After deployment, test simulated telemetry first. Confirm writes at:

- `/helmets/helmet001/current`
- `/readings/helmet001/{eventId}`
- `/helmets/helmet001/currentAssessment`
- `/assessments/helmet001/{eventId}`

Only after duplicate, replay, malformed-payload, and assessment tests pass
should firmware be pointed at the API endpoint. Normal telemetry must remain at
or below the existing 30 requests/minute per-helmet limit; critical events may
be sent immediately.

## Groq assistant key

The conversational assistant uses a separate standard SSM `SecureString`:

`/smart-safety/staging/groq-api-key`

Never place the Groq API key in Flutter, Lambda environment variables,
CloudFormation parameters, source control, command history, or logs. The helper
script prompts for the value with hidden input and sends it to SSM through a
temporary file that is deleted in a `finally` block:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File `
  ".\aws\scripts\put-groq-api-key.ps1"
```

The IAM policy in
`aws/iam/smart-safety-staging-groq-secret-writer.json` grants only the two
operations required to create this exact parameter. Attach it temporarily to
the deployment user, run the helper, verify the parameter metadata without
decrypting it, and then remove the temporary writer policy. The assistant
Lambda receives read-only permissions for this exact parameter and the existing
Firebase configuration parameter. It decrypts both only during cold-start
initialization; neither secret is returned to Flutter or logged.

## Authenticated assistant endpoint

`POST /v1/assistant` accepts only this JSON body:

```json
{
  "helmetId": "helmet001",
  "question": "What does the current assessment mean?"
}
```

The caller must send its current Firebase ID token in
`Authorization: Bearer <token>`. The Lambda verifies token revocation and then
rechecks the trusted RTDB profile and helmet assignment. Administrators may
access any helmet; supervisors need both the site and helmet assignment; workers
must be assigned to that helmet.

Only selected current readings, the current deterministic assessment, and
approved recommendation text are sent to Groq. Raw MQ-7/MQ-135 values remain
diagnostic and are never presented as calibrated ppm. The assistant explains
the prediction; it does not replace the fall/gas models or safety rules.

The SAM stack output named `AssistantEndpoint` provides the deployed URL. Do
not connect Flutter until the deployment change set has been reviewed and the
endpoint has passed authentication, cross-helmet, missing-data, and prompt-
injection smoke tests.
