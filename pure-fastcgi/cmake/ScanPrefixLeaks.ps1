param(
  [Parameter(Mandatory = $true)][string]$FilePath,
  [Parameter(Mandatory = $true)][string]$Prefix
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Test-NormalizedPrefix {
  param(
    [Parameter(Mandatory = $true)][string]$Decoded,
    [Parameter(Mandatory = $true)][string]$Needle
  )
  return $Decoded.Replace('\', '/').ToLowerInvariant().Contains($Needle)
}

try {
  $bytes = [System.IO.File]::ReadAllBytes($FilePath)
  $needle = $Prefix.Replace('\', '/').ToLowerInvariant()

  $ascii = [System.Text.Encoding]::ASCII.GetString($bytes)
  if (Test-NormalizedPrefix -Decoded $ascii -Needle $needle) {
    exit 42
  }

  if ($bytes.Length -ge 2) {
    $utf16Even = [System.Text.Encoding]::Unicode.GetString($bytes)
    if (Test-NormalizedPrefix -Decoded $utf16Even -Needle $needle) {
      exit 42
    }

    $oddBytes = New-Object byte[] ($bytes.Length - 1)
    [System.Array]::Copy($bytes, 1, $oddBytes, 0, $oddBytes.Length)
    $utf16Odd = [System.Text.Encoding]::Unicode.GetString($oddBytes)
    if (Test-NormalizedPrefix -Decoded $utf16Odd -Needle $needle) {
      exit 42
    }
  }
  exit 0
} catch {
  [Console]::Error.WriteLine($_.Exception.Message)
  exit 2
}
