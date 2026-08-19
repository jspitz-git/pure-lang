param(
  [Parameter(Mandatory=$true)]
  [ValidateSet('inspect-file','inspect-dir','inspect-tree','remove-file',
    'remove-empty-dir','remove-tree','unlink-reparse')]
  [string]$Mode,
  [Parameter(Mandatory=$true)][string]$Path,
  [string]$Root = ''
)

$ErrorActionPreference = 'Stop'

function Stop-Safety([string]$Kind, [string]$Detail) {
  [Console]::Error.WriteLine(('{0}|{1}' -f $Kind, $Detail))
  exit 73
}

function Get-Full([string]$Value) {
  return [IO.Path]::GetFullPath($Value).TrimEnd('\', '/')
}

function Assert-Contained([string]$Candidate, [string]$Container) {
  if ([String]::IsNullOrEmpty($Container)) { return }
  $candidateFull = Get-Full $Candidate
  $containerFull = Get-Full $Container
  if ($candidateFull.Equals($containerFull,
      [StringComparison]::OrdinalIgnoreCase)) { return }
  $prefix = $containerFull + [IO.Path]::DirectorySeparatorChar
  if (-not $candidateFull.StartsWith($prefix,
      [StringComparison]::OrdinalIgnoreCase)) {
    Stop-Safety 'OUTSIDE' ($candidateFull + ' !< ' + $containerFull)
  }
}

function Get-NoFollowItem([string]$Candidate, [bool]$WantDirectory,
    [bool]$WantFile) {
  $full = Get-Full $Candidate
  $volume = [IO.Path]::GetPathRoot($full)
  if ([String]::IsNullOrEmpty($volume)) { Stop-Safety 'ABSOLUTE' $full }
  $remainder = $full.Substring($volume.Length)
  $segments = $remainder.Split(@('\','/'),
    [StringSplitOptions]::RemoveEmptyEntries)
  $current = $volume.TrimEnd('\', '/')
  if ($current.Length -eq 2 -and $current[1] -eq ':') { $current += '\' }
  for ($index = 0; $index -lt $segments.Length; ++$index) {
    $current = [IO.Path]::Combine($current, $segments[$index])
    if (-not (Test-Path -LiteralPath $current)) {
      Stop-Safety 'MISSING' $current
    }
    $item = Get-Item -LiteralPath $current -Force
    if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
      Stop-Safety 'REPARSE' $current
    }
    if ($index -lt ($segments.Length - 1) -and -not $item.PSIsContainer) {
      Stop-Safety 'NOT_DIRECTORY' $current
    }
  }
  $final = Get-Item -LiteralPath $full -Force
  if ($WantDirectory -and -not $final.PSIsContainer) {
    Stop-Safety 'NOT_DIRECTORY' $full
  }
  if ($WantFile -and $final.PSIsContainer) { Stop-Safety 'NOT_FILE' $full }
  return $final
}

if ($Mode -eq 'unlink-reparse') {
  $full = Get-Full $Path
  $parent = [IO.Path]::GetDirectoryName($full)
  [void](Get-NoFollowItem $parent $true $false)
  try {
    $entry = Get-Item -LiteralPath $full -Force
  } catch {
    Stop-Safety 'MISSING' $full
  }
  if (($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0) {
    Stop-Safety 'NOT_REPARSE' $full
  }
  if ($entry.PSIsContainer) {
    [IO.Directory]::Delete($full, $false)
  } else {
    [IO.File]::Delete($full)
  }
  if (Test-Path -LiteralPath $full) { Stop-Safety 'LEFTOVER' $full }
  exit 0
}

Assert-Contained $Path $Root
if ($Mode -eq 'inspect-file') {
  [void](Get-NoFollowItem $Path $false $true)
  exit 0
}
if ($Mode -eq 'inspect-dir') {
  [void](Get-NoFollowItem $Path $true $false)
  exit 0
}
if ($Mode -eq 'remove-file') {
  [void](Get-NoFollowItem $Path $false $true)
  [IO.File]::Delete((Get-Full $Path))
  if (Test-Path -LiteralPath $Path) { Stop-Safety 'LEFTOVER' $Path }
  exit 0
}
if ($Mode -eq 'remove-empty-dir') {
  [void](Get-NoFollowItem $Path $true $false)
  $enumerator = [IO.Directory]::EnumerateFileSystemEntries(
    (Get-Full $Path)).GetEnumerator()
  try {
    if ($enumerator.MoveNext()) { Stop-Safety 'NOT_EMPTY' $Path }
  } finally {
    $enumerator.Dispose()
  }
  [IO.Directory]::Delete((Get-Full $Path), $false)
  if (Test-Path -LiteralPath $Path) { Stop-Safety 'LEFTOVER' $Path }
  exit 0
}

$rootItem = Get-NoFollowItem $Path $true $false
$pending = [Collections.Generic.Stack[IO.DirectoryInfo]]::new()
$pending.Push([IO.DirectoryInfo]$rootItem)
$files = [Collections.Generic.List[string]]::new()
$directories = [Collections.Generic.List[string]]::new()
while ($pending.Count -gt 0) {
  $directory = $pending.Pop()
  $directories.Add($directory.FullName)
  foreach ($entry in $directory.EnumerateFileSystemInfos()) {
    if (($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
      Stop-Safety 'REPARSE' $entry.FullName
    }
    Assert-Contained $entry.FullName $Root
    if (($entry.Attributes -band [IO.FileAttributes]::Directory) -ne 0) {
      $pending.Push([IO.DirectoryInfo]$entry)
    } else {
      $files.Add($entry.FullName)
    }
  }
}
if ($Mode -eq 'inspect-tree') { exit 0 }

if ($Mode -eq 'remove-tree') {
  foreach ($file in $files) {
    Assert-Contained $file $Root
    [void](Get-NoFollowItem $file $false $true)
    [IO.File]::Delete((Get-Full $file))
  }
  $ordered = $directories | Sort-Object { $_.Length } -Descending
  foreach ($directory in $ordered) {
    Assert-Contained $directory $Root
    [void](Get-NoFollowItem $directory $true $false)
    [IO.Directory]::Delete((Get-Full $directory), $false)
  }
  if (Test-Path -LiteralPath $Path) { Stop-Safety 'LEFTOVER' $Path }
  exit 0
}

Stop-Safety 'MODE' $Mode
