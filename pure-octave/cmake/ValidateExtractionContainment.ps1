param(
  [Parameter(Mandatory = $true)][string]$ExtractionRoot,
  [Parameter(Mandatory = $true)][string]$WorkRoot
)

$ErrorActionPreference = 'Stop'

function Get-NormalizedPath([string]$Path) {
  return [System.IO.Path]::GetFullPath((Resolve-Path -LiteralPath $Path).ProviderPath)
}

function Test-ContainedPath([string]$Path, [string]$Root, [string]$Description) {
  if ($Path -eq $Root) {
    return
  }
  $prefix = $Root.TrimEnd([System.IO.Path]::DirectorySeparatorChar,
                          [System.IO.Path]::AltDirectorySeparatorChar) +
            [System.IO.Path]::DirectorySeparatorChar
  if (-not $Path.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "$Description escaped its controlled root: $Path"
  }
}

$normalizedExtractionRoot = Get-NormalizedPath $ExtractionRoot
$normalizedWorkRoot = Get-NormalizedPath $WorkRoot
Test-ContainedPath $normalizedExtractionRoot $normalizedWorkRoot 'extraction root'
$script:entryCount = 0

function Test-MaterializedEntry([System.IO.FileSystemInfo]$entry) {
  $script:entryCount += 1
  if (($entry.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
    throw "PURE_OCTAVE_CONTAINMENT_ENTRIES:$script:entryCount; link-like materialized entry rejected: $($entry.FullName)"
  }
  $normalizedEntry = Get-NormalizedPath $entry.FullName
  Test-ContainedPath $normalizedEntry $normalizedExtractionRoot 'materialized entry'
  Test-ContainedPath $normalizedEntry $normalizedWorkRoot 'materialized entry'
  if ($entry -is [System.IO.DirectoryInfo]) {
    foreach ($child in $entry.EnumerateFileSystemInfos()) {
      Test-MaterializedEntry $child
    }
  }
}

Test-MaterializedEntry (Get-Item -LiteralPath $ExtractionRoot -Force)
[System.Console]::Out.WriteLine("PURE_OCTAVE_CONTAINMENT_ENTRIES:$script:entryCount")
