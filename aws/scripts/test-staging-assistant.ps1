[CmdletBinding()]
param(
  [string]$Endpoint = 'https://3sqh6oq2i5.execute-api.us-east-1.amazonaws.com/staging/v1/assistant',
  [string]$HelmetId = 'helmet001',
  [string]$Question = 'Summarize the current validated safety status, clearly separate known and unknown data, and list only approved immediate actions.',
  [string]$FirebaseOptionsPath
)

$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($FirebaseOptionsPath)) {
  $FirebaseOptionsPath = Join-Path $PSScriptRoot '..\..\lib\firebase_options.dart'
}

if (-not (Test-Path -LiteralPath $FirebaseOptionsPath)) {
  throw 'Firebase options file was not found.'
}

$firebaseOptions = Get-Content -Raw -LiteralPath $FirebaseOptionsPath
$webSection = [regex]::Match(
  $firebaseOptions,
  'static const FirebaseOptions web = FirebaseOptions\((?<body>[\s\S]*?)\);'
)
if (-not $webSection.Success) {
  throw 'Firebase web configuration was not found.'
}

$apiKeyMatch = [regex]::Match($webSection.Groups['body'].Value, "apiKey:\s*'(?<key>[^']+)'" )
if (-not $apiKeyMatch.Success) {
  throw 'Firebase web API key was not found.'
}
$firebaseApiKey = $apiKeyMatch.Groups['key'].Value

$email = Read-Host 'Firebase email'
if ([string]::IsNullOrWhiteSpace($email)) {
  throw 'Firebase email is required.'
}
$securePassword = Read-Host 'Firebase password (input is hidden)' -AsSecureString
$passwordPointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePassword)

$password = $null
$idToken = $null
try {
  $password = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($passwordPointer)
  $signInBody = @{
    email = $email.Trim()
    password = $password
    returnSecureToken = $true
  } | ConvertTo-Json -Compress

  $signInResponse = Invoke-RestMethod `
    -Method Post `
    -Uri "https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=$firebaseApiKey" `
    -ContentType 'application/json; charset=utf-8' `
    -Body $signInBody

  $idToken = [string]$signInResponse.idToken
  if ([string]::IsNullOrWhiteSpace($idToken)) {
    throw 'Firebase sign-in returned no ID token.'
  }

  $assistantBody = @{
    helmetId = $HelmetId
    question = $Question
  } | ConvertTo-Json -Compress

  $response = Invoke-RestMethod `
    -Method Post `
    -Uri $Endpoint `
    -Headers @{ Authorization = "Bearer $idToken" } `
    -ContentType 'application/json; charset=utf-8' `
    -Body $assistantBody

  [ordered]@{
    result = 'PASS'
    endpoint = $Endpoint
    helmetId = $response.helmetId
    sourceEventId = $response.sourceEventId
    answer = $response.answer
    disclaimer = $response.disclaimer
    generatedAt = $response.generatedAt
  } | ConvertTo-Json -Depth 8
} finally {
  if ($passwordPointer -ne [IntPtr]::Zero) {
    [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($passwordPointer)
  }
  $password = $null
  $idToken = $null
  $securePassword = $null
  $firebaseApiKey = $null
  $firebaseOptions = $null
}
