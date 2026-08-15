[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [string]$InputPath,

  [string]$OutputPath
)

$temporaryOutputPath = $null

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
  $driver = Join-Path $distributionPrefix 'cmake/RunFaust2Pure.cmake'

  foreach ($requiredFile in @(
      $faustExecutable, $pureArchitecture, $clangExecutable, $optExecutable,
      $driver)) {
    if (-not (Test-Path -LiteralPath $requiredFile -PathType Leaf)) {
      throw "Faust developer component is not installed: missing $requiredFile"
    }
  }

  $outputDirectory = Split-Path -Parent $outputAbsolutePath
  if (-not (Test-Path -LiteralPath $outputDirectory -PathType Container)) {
    throw "Output directory does not exist: $outputDirectory"
  }
  $temporaryOutputPath = "$outputAbsolutePath.new"

  if ([string]::IsNullOrWhiteSpace($env:PURE_FAUST_CMAKE)) {
    $cmake = Get-Command cmake.exe, cmake -ErrorAction Stop |
      Select-Object -First 1 -ExpandProperty Source
  } else {
    $cmake = (Get-Item -LiteralPath $env:PURE_FAUST_CMAKE -ErrorAction Stop).FullName
  }
  $cmakeArguments = @(
    "-DINPUT_PATH=$inputAbsolutePath"
    "-DOUTPUT_PATH=$outputAbsolutePath"
    "-DFAUST_EXECUTABLE=$faustExecutable"
    "-DPURE_ARCHITECTURE=$pureArchitecture"
    "-DCLANG_EXECUTABLE=$clangExecutable"
    "-DOPT_EXECUTABLE=$optExecutable"
    '-P'
    $driver
  )
  & $cmake @cmakeArguments
  if ($LASTEXITCODE -ne 0) {
    throw "Faust bitcode generation failed"
  }

  Write-Output $outputAbsolutePath
} catch {
  [Console]::Error.WriteLine($_.Exception.Message)
  exit 1
} finally {
  if ($null -ne $temporaryOutputPath) {
    Remove-Item -LiteralPath $temporaryOutputPath -Force -ErrorAction SilentlyContinue
  }
}
