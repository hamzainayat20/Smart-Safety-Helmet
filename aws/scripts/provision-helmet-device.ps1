<#
.SYNOPSIS
  Provisions the physical helmet001 ESP32 for the AWS staging endpoint without
  exposing secrets.

.DESCRIPTION
  Run with Windows PowerShell (powershell.exe), which includes System.IO.Ports.
  The ESP32 must be running the esp32dev_provisioner firmware, and no other
  program (for example "pio device monitor") may hold the serial port.

  -Stage Credential
      Reads the EXISTING helmet001 credential (keyVersion + secretBase64) from
      the encrypted SSM parameter and streams it to the device over the serial
      port. The secret is never printed, logged, written to disk or placed in
      a command line. No rotation happens: AWS, the Safe/Fall simulators and
      the Lambda's cached configuration all keep using the same credential.
  -Stage Network
      Prompts for Wi-Fi SSID and password (password input hidden), downloads
      the Amazon Trust Services root CAs, verifies that the live endpoint's
      certificate chain anchors to one of them, then stores endpoint, Wi-Fi
      and root CA bundle on the device. TLS verification stays enabled.
  -Stage Status
      Prints what the device has stored (presence only, no secrets).
  -Stage Erase -ConfirmErase
      Erases the device identity and network configuration (for example when
      the device holds an old credential that does not match AWS).
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [ValidateSet('Credential', 'Network', 'Status', 'Erase')]
  [string]$Stage,
  [string]$Port = 'COM4',
  [string]$Endpoint = 'https://3sqh6oq2i5.execute-api.us-east-1.amazonaws.com/staging/v1/telemetry',
  [string]$Profile = 'smart-safety',
  [string]$Region = 'us-east-1',
  [string]$ParameterName = '/smart-safety/staging/configuration',
  [switch]$ConfirmErase
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System

function Wait-ForText([System.IO.Ports.SerialPort]$serial, [string]$pattern, [int]$timeoutSeconds = 30) {
  $deadline = (Get-Date).AddSeconds($timeoutSeconds)
  while ((Get-Date) -lt $deadline) {
    try {
      $line = $serial.ReadLine().TrimEnd("`r")
    } catch [System.TimeoutException] {
      continue
    }
    # Device output never contains secrets; echo it for the operator.
    Write-Host "  device> $line"
    if ($line -match $pattern) { return $line }
    if ($line -match 'rejected|refus|FAILED') { throw "Device reported: $line" }
  }
  throw "Timed out waiting for the device to print '$pattern'."
}

function Send-Line([System.IO.Ports.SerialPort]$serial, [string]$value) {
  # Small chunks so long base64 lines never overrun the ESP32 receive buffer.
  for ($offset = 0; $offset -lt $value.Length; $offset += 64) {
    $serial.Write($value.Substring($offset, [Math]::Min(64, $value.Length - $offset)))
    Start-Sleep -Milliseconds 10
  }
  $serial.Write("`n")
}

function Open-Provisioner([string]$portName) {
  $serial = [System.IO.Ports.SerialPort]::new($portName, 115200, 'None', 8, 'One')
  $serial.NewLine = "`n"
  $serial.ReadTimeout = 500
  $serial.DtrEnable = $false
  $serial.RtsEnable = $false
  $serial.Open()
  Write-Host "Opened $portName. Press the EN/RESET button on the ESP32 now..."
  [void](Wait-ForText $serial 'Select stage' 45)
  return $serial
}

function Get-RootCaBundle([string]$endpointUrl) {
  $uri = [Uri]$endpointUrl
  if ($uri.Scheme -ne 'https') { throw 'Endpoint must use HTTPS.' }
  $sources = @(
    'https://www.amazontrust.com/repository/AmazonRootCA1.pem',
    'https://www.amazontrust.com/repository/SFSRootCAG2.pem'
  )
  $pems = @()
  $thumbprints = @()
  foreach ($source in $sources) {
    $pem = (Invoke-WebRequest -UseBasicParsing -Uri $source).Content
    if ($pem -is [byte[]]) { $pem = [Text.Encoding]::ASCII.GetString($pem) }
    $pem = $pem.Trim()
    $body = ($pem -replace '-----(BEGIN|END) CERTIFICATE-----', '' -replace '\s', '')
    $certificate = [Security.Cryptography.X509Certificates.X509Certificate2]::new([Convert]::FromBase64String($body))
    $pems += $pem
    $thumbprints += $certificate.Thumbprint
  }

  # Verify the live endpoint chain anchors to one of these roots.
  $client = [Net.Sockets.TcpClient]::new($uri.Host, 443)
  try {
    $stream = [Net.Security.SslStream]::new($client.GetStream(), $false)
    $stream.AuthenticateAsClient($uri.Host)
    $leaf = [Security.Cryptography.X509Certificates.X509Certificate2]::new($stream.RemoteCertificate)
    $chain = [Security.Cryptography.X509Certificates.X509Chain]::new()
    if (-not $chain.Build($leaf)) { throw 'Endpoint certificate chain did not validate on this PC.' }
    $chainThumbprints = $chain.ChainElements | ForEach-Object { $_.Certificate.Thumbprint }
    $anchored = $chainThumbprints | Where-Object { $thumbprints -contains $_ }
    if (-not $anchored) { throw 'Endpoint chain does not anchor to the downloaded Amazon root CAs.' }
    Write-Host "Endpoint certificate chain verified (anchor $($anchored | Select-Object -First 1))."
  } finally {
    $client.Dispose()
  }

  $bundle = ($pems -join "`n") + "`n"
  $encoded = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes($bundle))
  if ($bundle.Length -gt 3900) { throw 'Root CA bundle is too large for NVS.' }
  return $encoded
}

$serial = $null
try {
  switch ($Stage) {
    'Credential' {
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
      $credential = ($configurationJson | ConvertFrom-Json).helmetDeviceSecrets.helmet001
      $configurationJson = $null
      if ($null -eq $credential -or
          [string]::IsNullOrWhiteSpace([string]$credential.keyVersion) -or
          [string]::IsNullOrWhiteSpace([string]$credential.secretBase64) -or
          $credential.revoked -eq $true) {
        throw 'SSM has no usable (unrevoked) helmet001 credential.'
      }
      $secretLength = [Convert]::FromBase64String([string]$credential.secretBase64).Length
      if ($secretLength -lt 32) { throw 'The SSM helmet001 secret is shorter than 32 bytes.' }

      $serial = Open-Provisioner $Port
      Send-Line $serial '1'
      [void](Wait-ForText $serial 'Helmet ID')
      Send-Line $serial 'helmet001'
      [void](Wait-ForText $serial 'key version')
      Send-Line $serial ([string]$credential.keyVersion)
      [void](Wait-ForText $serial 'secretBase64')
      Send-Line $serial ([string]$credential.secretBase64)
      $credential = $null
      [void](Wait-ForText $serial 'Credential imported' 20)
      [void](Wait-ForText $serial 'Provisioner finished' 10)
      Write-Host 'PASS: helmet001 credential imported from SSM. Next: -Stage Network.'
    }
    'Network' {
      $rootCa = Get-RootCaBundle $Endpoint
      $ssid = Read-Host 'Wi-Fi SSID (2.4 GHz network)'
      $securePassword = Read-Host 'Wi-Fi password' -AsSecureString
      $pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePassword)
      try {
        $serial = Open-Provisioner $Port
        Send-Line $serial '2'
        [void](Wait-ForText $serial 'endpoint URL')
        Send-Line $serial $Endpoint
        [void](Wait-ForText $serial 'Wi-Fi SSID')
        Send-Line $serial $ssid
        [void](Wait-ForText $serial 'Wi-Fi password')
        Send-Line $serial ([Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer))
      } finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer)
        $securePassword.Dispose()
      }
      [void](Wait-ForText $serial 'root CA')
      Send-Line $serial $rootCa
      [void](Wait-ForText $serial 'Network configuration stored' 30)
      [void](Wait-ForText $serial 'Provisioner finished' 10)
      Write-Host 'PASS: endpoint, Wi-Fi and root CA stored. Next: upload esp32dev_staging.'
    }
    'Status' {
      $serial = Open-Provisioner $Port
      Send-Line $serial '3'
      [void](Wait-ForText $serial 'Provisioner finished' 10)
    }
    'Erase' {
      if (-not $ConfirmErase) { throw 'Add -ConfirmErase to erase the device identity.' }
      $serial = Open-Provisioner $Port
      Send-Line $serial '9'
      [void](Wait-ForText $serial 'Type ERASE')
      Send-Line $serial 'ERASE helmet001'
      [void](Wait-ForText $serial 'erased' 10)
    }
  }
} finally {
  if ($null -ne $serial) { $serial.Close(); $serial.Dispose() }
  $credential = $null
}
