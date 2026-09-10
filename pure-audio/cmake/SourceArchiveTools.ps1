param([Parameter(Mandatory=$true)][ValidateSet('Validate','Reserve','Publish','Remove')][string]$Mode,
      [string]$Root,[Parameter(Mandatory=$true)][string]$Directory,
      [string]$Destination,[string]$Names,[string]$Tools,[string]$Temporary)
$ErrorActionPreference='Stop'

function Get-ArchiveAttributes([string]$Path) {
  return [IO.File]::GetAttributes($Path)
}
function Assert-ArchivePath([string]$Path,[string]$Kind) {
  if($Path -notmatch '^[A-Za-z]:[/\\]' -or $Path -match '[|<>"?*\r\n]' -or
     $Path -match '(^|[/\\])[^/\\]*[. ]([/\\]|$)') { throw 'Malformed archive path' }
  $full=[IO.Path]::GetFullPath($Path)
  $item=Get-Item -LiteralPath $full -Force
  if($Kind -eq 'file' -and $item.PSIsContainer) { throw "Expected regular archive input: $full" }
  if($Kind -eq 'directory' -and -not $item.PSIsContainer) { throw "Expected archive directory: $full" }
  $current=$full
  while($current) {
    $attributes=Get-ArchiveAttributes $current
    if(($attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw "Archive reparse component: $current" }
    $current=[IO.Path]::GetDirectoryName($current)
  }
  return $full
}
function Assert-NewArchive([string]$Path) {
  $full=[IO.Path]::GetFullPath($Path)
  $null=Assert-ArchivePath ([IO.Path]::GetDirectoryName($full)) 'directory'
  try { $null=Get-ArchiveAttributes $full }
  catch [IO.FileNotFoundException] { return $full }
  catch [IO.DirectoryNotFoundException] { return $full }
  throw "Archive destination already exists (no overwrite): $full"
}
function Assert-OwnedTemporary([string]$Path,[string]$Parent) {
  $full=[IO.Path]::GetFullPath($Path)
  if([IO.Path]::GetDirectoryName($full) -ine $Parent -or
     [IO.Path]::GetFileName($full) -notmatch '^\.pure-audio-dist-[a-f0-9]{32}\.tmp$') {
    throw 'Temporary archive is outside its declared directory'
  }
  return (Assert-ArchivePath $full 'file')
}

$directoryPath=Assert-ArchivePath $Directory 'directory'
if($Mode -eq 'Validate') {
  $rootPath=Assert-ArchivePath $Root 'directory'
  $null=Assert-NewArchive $Destination
  foreach($name in $Names.Split('|')) {
    if($name -notmatch '^[A-Za-z0-9_+./-]+$' -or $name.StartsWith('/') -or
       $name -match '(^|/)\.\.(/|$)') { throw 'Malformed relative archive input' }
    $null=Assert-ArchivePath ([IO.Path]::Combine($rootPath,$name)) 'file'
  }
  foreach($tool in $Tools.Split('|')) { $null=Assert-ArchivePath $tool 'file' }
  'SOURCE_ARCHIVE_INPUTS_OK'
} elseif($Mode -eq 'Reserve') {
  $null=Assert-NewArchive $Destination
  $temporaryPath=[IO.Path]::Combine($directoryPath,'.pure-audio-dist-'+[Guid]::NewGuid().ToString('N')+'.tmp')
  $stream=[IO.File]::Open($temporaryPath,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
  $stream.Dispose()
  $temporaryPath.Replace('\','/')
} elseif($Mode -eq 'Publish') {
  $temporaryPath=Assert-OwnedTemporary $Temporary $directoryPath
  $destinationPath=Assert-NewArchive $Destination
  if([IO.Path]::GetDirectoryName($destinationPath) -ine $directoryPath) { throw 'Archive publication crossed directories' }
  # Same-volume entry publication. The two-argument API fails if the destination
  # already exists; it never truncates an existing file or follows its link.
  [IO.File]::Move($temporaryPath,$destinationPath)
  'SOURCE_ARCHIVE_PUBLISHED'
} else {
  $temporaryPath=Assert-OwnedTemporary $Temporary $directoryPath
  [IO.File]::Delete($temporaryPath)
}
