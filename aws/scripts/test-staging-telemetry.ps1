[CmdletBinding()]
param(
  [string]$Endpoint = 'https://3sqh6oq2i5.execute-api.us-east-1.amazonaws.com/staging/v1/telemetry',
  [string]$Profile = 'smart-safety',
  [string]$Region = 'us-east-1',
  [string]$ParameterName = '/smart-safety/staging/configuration',
  [ValidateSet('Safe', 'Gas', 'Fall')]
  [string]$Scenario = 'Safe'
)

$ErrorActionPreference = 'Stop'

$configurationJson = aws ssm get-parameter `
  --name $ParameterName `
  --with-decryption `
  --query 'Parameter.Value' `
  --output text `
  --region $Region `
  --profile $Profile

if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($configurationJson)) {
  throw 'Unable to read the encrypted staging configuration.'
}

$configuration = $configurationJson | ConvertFrom-Json
$credential = $configuration.helmetDeviceSecrets.helmet001
if ($null -eq $credential -or
    [string]::IsNullOrWhiteSpace([string]$credential.keyVersion) -or
    [string]::IsNullOrWhiteSpace([string]$credential.secretBase64)) {
  throw 'The encrypted configuration has no usable helmet001 credential.'
}
$keyVersion = [string]$credential.keyVersion

$timestamp = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
$nonceBytes = New-Object byte[] 18
$random = [Security.Cryptography.RandomNumberGenerator]::Create()
try {
  $random.GetBytes($nonceBytes)
} finally {
  $random.Dispose()
}
$nonce = [Convert]::ToBase64String($nonceBytes).TrimEnd('=').Replace('+', '-').Replace('/', '_')
$scenarioId = $Scenario.ToLowerInvariant()
$eventId = "aws_${scenarioId}_${timestamp}"

$payload = [ordered]@{
  schemaVersion = '2.0'
  eventId = $eventId
  helmetId = 'helmet001'
  deviceTimestamp = $timestamp
  firmwareVersion = 'aws-simulator.1'
  sensorFaults = @('gpsUnavailable', 'batteryUnavailable')
  mq7Raw = 575
  mq135Raw = 443
  mq7WarmUp = $false
  mq135WarmUp = $false
  temperatureC = 27.0
  humidityPct = 55.0
  heatIndexC = 28.0
  accelXG = 0.02
  accelYG = 0.03
  accelZG = 1.01
  gyroXDegreesPerSecond = 1.0
  gyroYDegreesPerSecond = 1.2
  gyroZDegreesPerSecond = 0.8
  fallFeatures = [ordered]@{
    acc_mean = 1.0
    acc_std = 0.05
    acc_min = 0.9
    acc_max = 1.1
    gyro_mean = 1.0
    gyro_std = 0.2
    gyro_max = 2.0
    jerk_mean = 0.1
    jerk_max = 0.3
  }
  samplingRateHz = 50
  windowSamples = 100
  windowEndTimestamp = $timestamp
}

$expectedAssessment = 'SAFE with no modeled hazard'
switch ($Scenario) {
  'Gas' {
    # Verified locally against the packaged gas model as Smoke (> 0.90 confidence).
    $payload['mq7Raw'] = 536
    $payload['mq135Raw'] = 275
    $expectedAssessment = 'CRITICAL Smoke hazard'
  }
  'Fall' {
    # Verified locally against the packaged fall model above its 0.46 threshold.
    $payload['accelXG'] = 0.2
    $payload['accelYG'] = 0.3
    $payload['accelZG'] = 2.0
    $payload['gyroXDegreesPerSecond'] = 180.0
    $payload['gyroYDegreesPerSecond'] = 220.0
    $payload['gyroZDegreesPerSecond'] = 200.0
    $payload['fallFeatures'] = [ordered]@{
      acc_mean = 0.8
      acc_std = 0.8
      acc_min = 0.0
      acc_max = 3.0
      gyro_mean = 25.0
      gyro_std = 50.0
      gyro_max = 200.0
      jerk_mean = 5.0
      jerk_max = 50.0
    }
    $expectedAssessment = 'CRITICAL Fall detected'
  }
}

$body = $payload | ConvertTo-Json -Depth 10 -Compress
$bodyBytes = [Text.Encoding]::UTF8.GetBytes($body)
$sha = [Security.Cryptography.SHA256]::Create()
try {
  $bodyHash = ([BitConverter]::ToString($sha.ComputeHash($bodyBytes))).Replace('-', '').ToLowerInvariant()
} finally {
  $sha.Dispose()
}

$canonical = "POST`n/ingest/v1/helmets/helmet001/telemetry`n$timestamp`n$nonce`n$bodyHash"
$secretBytes = [Convert]::FromBase64String([string]$credential.secretBase64)
$hmac = [Security.Cryptography.HMACSHA256]::new($secretBytes)
try {
  $signature = ([BitConverter]::ToString(
    $hmac.ComputeHash([Text.Encoding]::UTF8.GetBytes($canonical))
  )).Replace('-', '').ToLowerInvariant()
} finally {
  $hmac.Dispose()
  [Array]::Clear($secretBytes, 0, $secretBytes.Length)
  [Array]::Clear($nonceBytes, 0, $nonceBytes.Length)
  $configurationJson = $null
  $configuration = $null
  $credential = $null
}

$headers = @{
  'x-smart-safety-helmet-id' = 'helmet001'
  'x-smart-safety-timestamp' = [string]$timestamp
  'x-smart-safety-nonce' = $nonce
  'x-smart-safety-key-version' = $keyVersion
  'x-smart-safety-signature' = $signature
}

$response = Invoke-RestMethod `
  -Method Post `
  -Uri $Endpoint `
  -Headers $headers `
  -ContentType 'application/json; charset=utf-8' `
  -Body $body

[ordered]@{
  result = 'PASS'
  endpoint = $Endpoint
  scenario = $Scenario
  expectedAssessment = $expectedAssessment
  eventId = $eventId
  helmetId = 'helmet001'
  apiResponse = $response
} | ConvertTo-Json -Depth 10
