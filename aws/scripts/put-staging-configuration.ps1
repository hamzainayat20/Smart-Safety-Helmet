[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [string]$FirebaseServiceAccountPath,

  [string]$Profile = 'smart-safety',
  [string]$Region = 'us-east-1',
  [string]$ParameterName = '/smart-safety/staging/configuration'
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $FirebaseServiceAccountPath -PathType Leaf)) {
  throw "Firebase service-account file was not found."
}

$serviceAccount = Get-Content -Raw -LiteralPath $FirebaseServiceAccountPath |
  ConvertFrom-Json

$requiredFields = @(
  'type',
  'project_id',
  'private_key_id',
  'private_key',
  'client_email',
  'client_id',
  'token_uri'
)

foreach ($field in $requiredFields) {
  if ([string]::IsNullOrWhiteSpace([string]$serviceAccount.$field)) {
    throw "Firebase service-account file is missing a required field."
  }
}

if ($serviceAccount.type -ne 'service_account' -or
    $serviceAccount.project_id -ne 'smart-safety-331d6') {
  throw "Firebase service-account file belongs to the wrong project or account type."
}

$secretBytes = New-Object byte[] 32
$random = [System.Security.Cryptography.RandomNumberGenerator]::Create()
try {
  $random.GetBytes($secretBytes)
} finally {
  $random.Dispose()
}

$configuration = [ordered]@{
  firebaseServiceAccount = $serviceAccount
  helmetDeviceSecrets = [ordered]@{
    helmet001 = [ordered]@{
      keyVersion = 'v1'
      secretBase64 = [Convert]::ToBase64String($secretBytes)
    }
  }
} | ConvertTo-Json -Depth 20 -Compress

$configurationBytes = [Text.Encoding]::UTF8.GetByteCount($configuration)
if ($configurationBytes -gt 4096) {
  throw "Configuration is too large for a standard SSM parameter."
}

$request = [ordered]@{
  Name = $ParameterName
  Description = 'Smart Safety staging Firebase and helmet device configuration'
  Type = 'SecureString'
  Value = $configuration
  Tier = 'Standard'
  Tags = @(
    @{ Key = 'Project'; Value = 'smart-safety' },
    @{ Key = 'Environment'; Value = 'staging' }
  )
} | ConvertTo-Json -Depth 20

$requestFile = [IO.Path]::GetTempFileName()
try {
  [IO.File]::WriteAllText($requestFile, $request, [Text.UTF8Encoding]::new($false))
  aws ssm put-parameter `
    --cli-input-json "file://$requestFile" `
    --region $Region `
    --profile $Profile `
    --output json

  if ($LASTEXITCODE -ne 0) {
    throw "AWS rejected the encrypted configuration parameter."
  }
} finally {
  if (Test-Path -LiteralPath $requestFile) {
    Remove-Item -LiteralPath $requestFile -Force
  }
  [Array]::Clear($secretBytes, 0, $secretBytes.Length)
}

Write-Host "Encrypted staging configuration created at $ParameterName."
