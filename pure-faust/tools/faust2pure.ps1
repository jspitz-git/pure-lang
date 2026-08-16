[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [string]$InputPath,

  [string]$OutputPath
)

$temporaryOutputPath = $null
$workDirectory = $null

Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;

public static class PureFaustFile {
  [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
  private static extern bool MoveFileEx(
    string existingName, string newName, int flags);

  public static void Replace(string source, string destination) {
    const int MOVEFILE_REPLACE_EXISTING = 0x1;
    const int MOVEFILE_WRITE_THROUGH = 0x8;
    if (!MoveFileEx(source, destination,
        MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH)) {
      throw new Win32Exception(Marshal.GetLastWin32Error());
    }
  }
}
'@

function Invoke-FaustStage {
  param(
    [Parameter(Mandatory = $true)] [string]$Stage,
    [Parameter(Mandatory = $true)] [string]$Executable,
    [Parameter(Mandatory = $true)] [string[]]$Arguments,
    [string]$WorkingDirectory
  )

  try {
    if (-not [string]::IsNullOrWhiteSpace($WorkingDirectory)) {
      Push-Location -LiteralPath $WorkingDirectory
    }
    & $Executable @Arguments
    if ($LASTEXITCODE -ne 0) {
      throw "$Stage stage failed ($LASTEXITCODE)"
    }
  } finally {
    if (-not [string]::IsNullOrWhiteSpace($WorkingDirectory)) {
      Pop-Location
    }
  }
}

try {
  $scriptDirectory = $PSScriptRoot
  $distributionPrefix = [System.IO.Path]::GetFullPath(
    (Join-Path $scriptDirectory '..'))

  $inputItem = Get-Item -LiteralPath $InputPath -ErrorAction Stop
  if ($inputItem.PSIsContainer) {
    throw "InputPath must name a file: $InputPath"
  }
  $inputAbsolutePath = $inputItem.FullName

  if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $outputAbsolutePath = [System.IO.Path]::ChangeExtension(
      $inputAbsolutePath, '.bc')
  } else {
    $outputAbsolutePath = [System.IO.Path]::GetFullPath($OutputPath)
  }

  if (Test-Path -LiteralPath $outputAbsolutePath -PathType Container) {
    throw "OutputPath must name a file, not a directory: $outputAbsolutePath"
  }
  if ([string]::Equals(
      $inputAbsolutePath, $outputAbsolutePath,
      [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "InputPath and OutputPath must not name the same file"
  }

  $faustExecutable = Join-Path $distributionPrefix 'bin/faust.exe'
  $pureArchitecture = Join-Path $distributionPrefix 'share/pure-faust/pure.c'
  $clangExecutable = Join-Path $distributionPrefix 'bin/clang.exe'
  $optExecutable = Join-Path $distributionPrefix 'bin/opt.exe'

  foreach ($requiredFile in @(
      $faustExecutable, $pureArchitecture, $clangExecutable, $optExecutable)) {
    if (-not (Test-Path -LiteralPath $requiredFile -PathType Leaf)) {
      throw "Faust developer component is not installed: missing $requiredFile"
    }
  }

  $outputDirectory = Split-Path -Parent $outputAbsolutePath
  if (-not (Test-Path -LiteralPath $outputDirectory -PathType Container)) {
    throw "Output directory does not exist: $outputDirectory"
  }
  $temporaryOutputPath = "$outputAbsolutePath.new"

  do {
    $workDirectory = Join-Path $outputDirectory (
      '.faust2pure-' + [System.IO.Path]::GetRandomFileName())
  } while (Test-Path -LiteralPath $workDirectory)
  New-Item -ItemType Directory -Path $workDirectory -ErrorAction Stop |
    Out-Null

  $referenceC = Join-Path $workDirectory 'reference.c'
  $referenceBc = Join-Path $workDirectory 'reference.bc'
  $architectureDirectory = Split-Path -Parent $pureArchitecture
  $architectureName = Split-Path -Leaf $pureArchitecture

  Invoke-FaustStage -Stage faust -Executable $faustExecutable `
    -WorkingDirectory $architectureDirectory -Arguments @(
      '-lang', 'c', '-a', $architectureName, $inputAbsolutePath,
      '-o', $referenceC)
  Invoke-FaustStage -Stage clang -Executable $clangExecutable `
    -WorkingDirectory $workDirectory -Arguments @(
      '-emit-llvm', '-O3', '-g0', '-fdebug-compilation-dir=.',
      '-c', 'reference.c', '-o', 'reference.bc')
  Invoke-FaustStage -Stage verify -Executable $optExecutable -Arguments @(
    '-passes=verify', '-disable-output', $referenceBc)

  try {
    Copy-Item -LiteralPath $referenceBc -Destination $temporaryOutputPath `
      -ErrorAction Stop
    [PureFaustFile]::Replace($temporaryOutputPath, $outputAbsolutePath)
  } catch {
    throw "publish stage failed: $($_.Exception.Message)"
  }

  Write-Output $outputAbsolutePath
} catch {
  [Console]::Error.WriteLine($_.Exception.Message)
  exit 1
} finally {
  if ($null -ne $temporaryOutputPath) {
    Remove-Item -LiteralPath $temporaryOutputPath -Force -ErrorAction SilentlyContinue
  }
  if ($null -ne $workDirectory) {
    Remove-Item -LiteralPath $workDirectory -Recurse -Force `
      -ErrorAction SilentlyContinue
  }
}
