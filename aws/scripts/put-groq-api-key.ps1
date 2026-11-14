[CmdletBinding()]
param(
  [string]$Profile = 'smart-safety',
  [string]$Region = 'us-east-1',
  [string]$ParameterName = '/smart-safety/staging/groq-api-key',
  [switch]$Overwrite
)

$ErrorActionPreference = 'Stop'

$secureKey = Read-Host 'Paste the Groq API key (input is hidden)' -AsSecureString
$keyPointer = [IntPtr]::Zero
$plainKey = $null
$requestFile = $null

try {
  $keyPointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureKey)
  $plainKey = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($keyPointer)

  if ([string]::IsNullOrWhiteSpace($plainKey) -or
      -not $plainKey.StartsWith('gsk_') -or
      $plainKey.Length -lt 20) {
    throw 'The value does not look like a valid Groq API key.'
  }

  $request = [ordered]@{
    Name = $ParameterName
    Description = 'Smart Safety staging Groq assistant API key'
    Type = 'SecureString'
    Value = $plainKey
    Tier = 'Standard'
  }

  if ($Overwrite) {
    $request.Overwrite = $true
  } else {
    $request.Tags = @(
      @{ Key = 'Project'; Value = 'smart-safety' },
      @{ Key = 'Environment'; Value = 'staging' },
      @{ Key = 'Purpose'; Value = 'assistant-api-key' }
    )
  }

  $requestFile = [IO.Path]::GetTempFileName()
  $requestJson = $request | ConvertTo-Json -Depth 10 -Compress
  [IO.File]::WriteAllText(
    $requestFile,
    $requestJson,
    [Text.UTF8Encoding]::new($false)
  )

  # Windows PowerShell 5 can promote a native process's stderr stream to a
  # terminating NativeCommandError when ErrorActionPreference is Stop. Allow
  # AWS CLI to finish so its exit code and sanitized error can be handled here.
  $previousErrorActionPreference = $ErrorActionPreference
  try {
    $ErrorActionPreference = 'Continue'
    $result = aws ssm put-parameter `
      --cli-input-json "file://$requestFile" `
      --region $Region `
      --profile $Profile `
      --output json 2>&1
    $awsExitCode = $LASTEXITCODE
  } finally {
    $ErrorActionPreference = $previousErrorActionPreference
  }

  if ($awsExitCode -ne 0) {
    $safeError = ($result | Out-String).Trim().Replace(
      $plainKey,
      '[REDACTED]'
    )
    throw "AWS rejected the Groq SecureString parameter. $safeError"
  }

  $version = ($result | ConvertFrom-Json).Version
  Write-Host "Groq API key stored as encrypted SecureString. Version: $version"
  Write-Host "Parameter: $ParameterName"
} finally {
  if ($null -ne $requestFile -and
      (Test-Path -LiteralPath $requestFile)) {
    Remove-Item -LiteralPath $requestFile -Force
  }
  if ($keyPointer -ne [IntPtr]::Zero) {
    [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($keyPointer)
  }
  $plainKey = $null
  $secureKey.Dispose()
}
