[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string] $SourceBin,
    [Parameter(Mandatory = $true)][string] $PureRoot,
    [Parameter(Mandatory = $true)][string] $AcceptedStageManifest,
    [Parameter(Mandatory = $true)][string] $SnapshotRoot,
    [Parameter(Mandatory = $true)][string] $ContractOutput,
    [Parameter(Mandatory = $true)][ValidateSet('Plan','Apply')][string] $Mode,
    [string] $ObjdumpPath = 'C:\tmp\todo51-task3\toolchain-normalize-pristine\mingw64\bin\objdump.exe',
    [string] $SyntheticExpectedFiles = '',
    [string] $SyntheticImportManifest = '',
    [switch] $InjectFailureAfterFirstCopy,
    [switch] $InjectApiSetReleaseFailure,
    [switch] $InjectApiSetTruncatedPath,
    [switch] $TestMode
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$utf8NoBom = [Text.UTF8Encoding]::new($false)
$acceptedSourceBin = 'C:\msys64\clang64\bin'
$acceptedPureRoot = 'C:\tmp\Relocated Pure Gplot Final Bundle 20260729'
$acceptedManifest = 'C:\tmp\todo51-task3\stage-runtime-v5\stage-manifest.tsv'
$acceptedManifestSha256 = 'E142C07EDA4D71184D1892189834818B9DCE7AD44B8F0A6708A51C54FA56476F'
$acceptedManifestFiles = [long]64309
$acceptedManifestBytes = [long]3327729829
$acceptedSnapshot = 'C:\tmp\todo51-task3\pure-rsvg-supplement-v1'
$acceptedContract = 'C:\pure-lang\pure-octave\probes\task3-pure-rsvg-supplement-contract.psd1'
$acceptedObjdump = 'C:\tmp\todo51-task3\toolchain-normalize-pristine\mingw64\bin\objdump.exe'
$testRoot = 'C:\tmp\todo51-task3\supplement-preparer-tests'
$pinned = @(
    [pscustomobject]@{ Name='librsvg-2-2.dll'; Length=[long]5882880; Sha256='9F90DE3779E80F590B542AFDF79C105A403B0C566265D69EACBBF9B524338F89'; PeMachine='pei-x86-64' },
    [pscustomobject]@{ Name='libunwind.dll'; Length=[long]63488; Sha256='60FA3C200899BC6E4A5876B82E2C656FF72FC53EC55979D99CB7C4EF640A6D96'; PeMachine='pei-x86-64' },
    [pscustomobject]@{ Name='libxml2-16.dll'; Length=[long]1294848; Sha256='C6C34A810D86C19C034A1BC96C4C500BDE8FB789DED69B434E67EEE773605852'; PeMachine='pei-x86-64' }
)

if (-not ('PureRsvgNative' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Text;
public static class PureRsvgNative {
  [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
  public static extern IntPtr LoadLibraryExW(string name, IntPtr file, uint flags);
  [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
  public static extern uint GetModuleFileNameW(IntPtr module, StringBuilder path, int size);
  [DllImport("kernel32.dll", SetLastError=true)]
  [return: MarshalAs(UnmanagedType.Bool)]
  public static extern bool FreeLibrary(IntPtr module);
}
'@
}

function Get-Sha256File([string] $Path) {
    $stream = [IO.File]::Open($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash($stream))).Replace('-','') }
    finally { $sha.Dispose(); $stream.Dispose() }
}

function Get-Sha256Bytes([byte[]] $Bytes) {
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash($Bytes))).Replace('-','') }
    finally { $sha.Dispose() }
}

function Assert-LocalDosPath([string] $Path, [string] $Description) {
    if ($Path -notmatch '^[A-Za-z]:\\' -or $Path -match '^(\\\\|\\\?\\|\\\.\\)' -or $Path -match '[\\/]\.\.([\\/]|$)') {
        throw "$Description is not a local drive-letter DOS path: $Path"
    }
}

function Assert-NoReparsePath([string] $Path, [string] $Description) {
    Assert-LocalDosPath $Path $Description
    $full = [IO.Path]::GetFullPath($Path).TrimEnd('\')
    $cursor = $full.Substring(0, 3)
    foreach ($part in $full.Substring(3).Split('\', [StringSplitOptions]::RemoveEmptyEntries)) {
        $cursor = Join-Path $cursor $part
        if (Test-Path -LiteralPath $cursor) {
            if (((Get-Item -LiteralPath $cursor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw "$Description contains a reparse point: $cursor"
            }
        }
    }
}

function Assert-RegularFile([string] $Path, [string] $Description) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "$Description is missing: $Path" }
    Assert-NoReparsePath $Path $Description
}

function Assert-ExactPath([string] $Actual, [string] $Expected, [string] $Description) {
    if (-not ([IO.Path]::GetFullPath($Actual).TrimEnd('\')).Equals([IO.Path]::GetFullPath($Expected).TrimEnd('\'), [StringComparison]::OrdinalIgnoreCase)) {
        throw "$Description is not the fixed approved path: $Expected"
    }
}

function Get-RegularPinnedFile([string] $Path, [long] $Length, [string] $Sha256) {
    Assert-RegularFile $Path 'Pinned supplement file'
    $item = Get-Item -LiteralPath $Path -Force
    if ($item.Length -ne $Length) { throw "Supplement length mismatch for $Path" }
    $actualHash = Get-Sha256File $Path
    if ($actualHash -ne $Sha256.ToUpperInvariant()) { throw "Supplement SHA-256 mismatch for $Path" }
    return [pscustomobject]@{ Path=$item.FullName; Length=[long]$item.Length; Sha256=$actualHash }
}

function Get-PeImports([string] $ObjdumpPath, [string] $PePath) {
    $output = & $ObjdumpPath -p $PePath 2>&1
    if ($LASTEXITCODE -ne 0) { throw "objdump import audit failed for $PePath`n$output" }
    return @($output | ForEach-Object { if ($_ -match '^\s*DLL Name:\s*(.+?)\s*$') { $Matches[1].Trim() } })
}

function Get-PeMachine([string] $ObjdumpPath, [string] $PePath) {
    $output = & $ObjdumpPath -f $PePath 2>&1
    if ($LASTEXITCODE -ne 0) { throw "objdump machine audit failed for $PePath`n$output" }
    $format = @($output | ForEach-Object { if ($_ -match '^\s*.+:\s+file format\s+(\S+)\s*$') { $Matches[1] } })
    if ($format.Count -ne 1) { throw "Unable to determine one PE machine format for $PePath" }
    return $format[0]
}

function Get-SyntheticImports([string] $Name) {
    if (-not $SyntheticImportManifest) { return @() }
    foreach ($line in Get-Content -LiteralPath $SyntheticImportManifest) {
        $fields = $line.Split("`t")
        if ($fields.Count -ne 2) { throw "Invalid synthetic import record: $line" }
        if ($fields[0].Equals($Name, [StringComparison]::OrdinalIgnoreCase)) {
            return @($fields[1].Split(';', [StringSplitOptions]::RemoveEmptyEntries))
        }
    }
    return @()
}

function Resolve-SystemImport([string] $Name) {
    $lower = $Name.ToLowerInvariant()
    $system32 = [IO.Path]::GetFullPath((Join-Path $env:WINDIR 'System32')).TrimEnd('\')
    Assert-NoReparsePath $system32 'Windows System32'
    if ($lower.StartsWith('api-ms-win-') -or $lower.StartsWith('ext-ms-win-')) {
        if ($lower -notmatch '^(api|ext)-ms-win-[a-z0-9][a-z0-9-]*-l[0-9]+-[0-9]+-[0-9]+\.dll$') { return '' }
        $handle = [PureRsvgNative]::LoadLibraryExW($Name, [IntPtr]::Zero, 0x00000800)
        if ($handle -eq [IntPtr]::Zero) { return '' }
        $hostPath = ''
        $releaseSucceeded = $false
        $releaseError = 0
        try {
            $builder = [Text.StringBuilder]::new(32768)
            $pathLength = [PureRsvgNative]::GetModuleFileNameW($handle, $builder, $builder.Capacity)
            if ($InjectApiSetTruncatedPath) { $pathLength = $builder.Capacity }
            if ($pathLength -ge $builder.Capacity) { throw "Truncated API-set module path for $Name." }
            if ($pathLength -gt 0 -and $pathLength -lt $builder.Capacity) {
                $candidate = [IO.Path]::GetFullPath($builder.ToString())
                if ($candidate.StartsWith($system32 + '\', [StringComparison]::OrdinalIgnoreCase)) {
                    Assert-RegularFile $candidate "API-set host for $Name"
                    $hostPath = $candidate
                }
            }
        }
        finally {
            $releaseSucceeded = [PureRsvgNative]::FreeLibrary($handle)
            $releaseError = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
            if ($InjectApiSetReleaseFailure) { $releaseSucceeded = $false; $releaseError = 5 }
        }
        if (-not $releaseSucceeded) { throw "Failed to release API-set module $Name (Win32 error $releaseError)." }
        return $hostPath
    }
    $physical = Join-Path $system32 $Name
    if (-not (Test-Path -LiteralPath $physical -PathType Leaf)) { return '' }
    Assert-RegularFile $physical "System import $Name"
    return [IO.Path]::GetFullPath($physical)
}

function Resolve-SupplementClosure([string[]] $RootNames, [string] $SourceBin, [string] $PureBin) {
    $supplementSet = @{}; foreach ($name in $RootNames) { $supplementSet[$name.ToLowerInvariant()] = $true }
    $queue = [Collections.Generic.Queue[object]]::new()
    foreach ($name in $RootNames) { $queue.Enqueue([pscustomobject]@{ Name=$name; Origin='Supplement'; Path=(Join-Path $SourceBin $name) }) }
    $resolved = @{}
    $reused = [Collections.Generic.List[object]]::new()
    $reusedSet = @{}
    $edges = [Collections.Generic.List[object]]::new()
    while ($queue.Count -gt 0) {
        $current = $queue.Dequeue()
        $currentKey = $current.Name.ToLowerInvariant()
        if ($resolved.ContainsKey($currentKey)) { continue }
        $resolved[$currentKey] = $current.Origin
        $imports = @(Get-PeImports $ObjdumpPath $current.Path)
        if ($TestMode) { $imports += @(Get-SyntheticImports $current.Name) }
        foreach ($import in $imports) {
            if ([string]::IsNullOrWhiteSpace($import) -or $import -match '[\\/:]') { throw "Unsafe supplement import $import from $($current.Name)" }
            $key = $import.ToLowerInvariant()
            $origin = ''; $resolvedPath = ''
            if ($supplementSet.ContainsKey($key)) {
                $origin = 'Supplement'; $resolvedPath = Join-Path $SourceBin $import
            }
            else {
                $purePath = Join-Path $PureBin $import
                $sourcePath = Join-Path $SourceBin $import
                if (Test-Path -LiteralPath $purePath -PathType Leaf) {
                    Assert-RegularFile $purePath "Reused Pure dependency $import"
                    Assert-RegularFile $sourcePath "Matching clang64 dependency $import"
                    $pureHash = Get-Sha256File $purePath; $sourceHash = Get-Sha256File $sourcePath
                    if ($pureHash -ne $sourceHash -or (Get-Item -LiteralPath $purePath).Length -ne (Get-Item -LiteralPath $sourcePath).Length) {
                        throw "Reused Pure dependency differs from clang64: $import"
                    }
                    $origin = 'Pure'; $resolvedPath = $purePath
                    if (-not $resolved.ContainsKey($key) -and -not $reusedSet.ContainsKey($key)) {
                        $reused.Add([pscustomobject]@{ Name=$import; Length=[long](Get-Item -LiteralPath $purePath).Length; PureSha256=$pureHash; SourceSha256=$sourceHash })
                        $reusedSet[$key] = $true
                    }
                }
                elseif (Test-Path -LiteralPath $sourcePath -PathType Leaf) {
                    throw "Unresolved supplement import $import from $($current.Name)"
                }
                else {
                    $systemPath = Resolve-SystemImport $import
                    if ($systemPath) { $origin = 'System'; $resolvedPath = $systemPath }
                    else { throw "Unresolved supplement import $import from $($current.Name)" }
                }
            }
            $edges.Add([pscustomobject]@{ From=$current.Name; Import=$import; Origin=$origin; Resolved=$resolvedPath })
            if (($origin -eq 'Supplement' -or $origin -eq 'Pure') -and -not $resolved.ContainsKey($key)) {
                $queue.Enqueue([pscustomobject]@{ Name=$import; Origin=$origin; Path=$resolvedPath })
            }
        }
    }
    return [pscustomobject]@{
        ReusedPureDependencies=@($reused | Sort-Object Name)
        ImportEdges=@($edges | Sort-Object From,Import)
    }
}

function Get-PredictedStageManifest([string] $AcceptedManifest, [object[]] $SupplementFiles) {
    Assert-RegularFile $AcceptedManifest 'Accepted stage manifest'
    $lines = [Collections.Generic.List[string]]::new()
    foreach ($line in [IO.File]::ReadAllLines($AcceptedManifest)) {
        if ($line -notmatch '^(.+?)`t([0-9]+)`t([0-9A-F]{64})$') { throw "Invalid accepted stage manifest record: $line" }
        $lines.Add($line)
    }
    foreach ($file in $SupplementFiles) { $lines.Add("pure/bin/$($file.Name)``t$($file.Length)``t$($file.Sha256)") }
    $ordered = [string[]]$lines.ToArray(); [Array]::Sort($ordered, [StringComparer]::Ordinal)
    $text = ($ordered -join "`n") + "`n"
    return [pscustomobject]@{
        Text=$text
        FileCount=[long]$ordered.Count
        TotalBytes=[long]($acceptedManifestBytes + ($SupplementFiles | Measure-Object -Property Length -Sum).Sum)
        Sha256=Get-Sha256Bytes $utf8NoBom.GetBytes($text)
    }
}

function Read-ExpectedFiles {
    if (-not $TestMode) { return $pinned }
    Assert-RegularFile $SyntheticExpectedFiles 'Synthetic expected supplement manifest'
    $records = @(
        foreach ($line in Get-Content -LiteralPath $SyntheticExpectedFiles) {
            $fields = $line.Split("`t")
            if ($fields.Count -ne 4) { throw "Invalid synthetic expected supplement record: $line" }
            [pscustomobject]@{ Name=$fields[0]; Length=[long]$fields[1]; Sha256=$fields[2].ToUpperInvariant(); PeMachine=$fields[3] }
        }
    )
    return $records
}

function ConvertTo-Psd1Literal([object] $Contract) {
    $quote = { param([string]$s) "'" + $s.Replace("'","''") + "'" }
    $fileLines = @($Contract.Files | ForEach-Object { "        @{ Name = $(& $quote $_.Name); Length = [long]$($_.Length); Sha256 = $(& $quote $_.Sha256); PeMachine = $(& $quote $_.PeMachine) }" })
    $reuseLines = @($Contract.ReusedPureDependencies | ForEach-Object { "        @{ Name = $(& $quote $_.Name); Length = [long]$($_.Length); PureSha256 = $(& $quote $_.PureSha256); SourceSha256 = $(& $quote $_.SourceSha256) }" })
    return @"
@{
    SnapshotRoot = $(& $quote $Contract.SnapshotRoot)
    Files = @(
$($fileLines -join "`r`n")
    )
    ReusedPureDependencies = @(
$($reuseLines -join "`r`n")
    )
    AddedFileCount = [long]$($Contract.AddedFileCount)
    AddedBytes = [long]$($Contract.AddedBytes)
    ExpectedStageFileCount = [long]$($Contract.ExpectedStageFileCount)
    ExpectedStageBytes = [long]$($Contract.ExpectedStageBytes)
    ExpectedStageManifestSha256 = $(& $quote $Contract.ExpectedStageManifestSha256)
    ExpectedAuditedPeCount = [long]$($Contract.ExpectedAuditedPeCount)
    ExpectedAuditedOctCount = [long]$($Contract.ExpectedAuditedOctCount)
    ExpectedPinnedPlaceholderCount = [long]$($Contract.ExpectedPinnedPlaceholderCount)
}
"@
}

$SourceBin = [IO.Path]::GetFullPath($SourceBin).TrimEnd('\')
$PureRoot = [IO.Path]::GetFullPath($PureRoot).TrimEnd('\')
$AcceptedStageManifest = [IO.Path]::GetFullPath($AcceptedStageManifest)
$SnapshotRoot = [IO.Path]::GetFullPath($SnapshotRoot).TrimEnd('\')
$ContractOutput = [IO.Path]::GetFullPath($ContractOutput)
$ObjdumpPath = [IO.Path]::GetFullPath($ObjdumpPath)
$pureBin = Join-Path $PureRoot 'bin'

foreach ($pair in @(@($SourceBin,'Source bin'),@($PureRoot,'Pure root'),@($pureBin,'Pure bin'),@($AcceptedStageManifest,'Accepted stage manifest'),@($SnapshotRoot,'Snapshot root'),@($ContractOutput,'Contract output'),@($ObjdumpPath,'objdump'))) {
    Assert-NoReparsePath $pair[0] $pair[1]
}
if (-not $TestMode) {
    Assert-ExactPath $SourceBin $acceptedSourceBin 'Source bin'
    Assert-ExactPath $PureRoot $acceptedPureRoot 'Pure root'
    Assert-ExactPath $AcceptedStageManifest $acceptedManifest 'Accepted stage manifest'
    Assert-ExactPath $SnapshotRoot $acceptedSnapshot 'Snapshot root'
    Assert-ExactPath $ContractOutput $acceptedContract 'Contract output'
    Assert-ExactPath $ObjdumpPath $acceptedObjdump 'objdump'
}
else {
    if (-not $SnapshotRoot.StartsWith($testRoot + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'Synthetic snapshot escapes the exact test root.' }
    if (-not $ContractOutput.StartsWith($testRoot + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'Synthetic contract escapes the exact test root.' }
}
if ($InjectApiSetReleaseFailure -and (-not $TestMode -or -not $SnapshotRoot.StartsWith($testRoot + '\', [StringComparison]::OrdinalIgnoreCase))) {
    throw 'API-set release failure injection is restricted to the exact synthetic root.'
}
if ($InjectApiSetTruncatedPath -and (-not $TestMode -or -not $SnapshotRoot.StartsWith($testRoot + '\', [StringComparison]::OrdinalIgnoreCase))) {
    throw 'API-set truncation injection is restricted to the exact synthetic root.'
}
Assert-RegularFile $ObjdumpPath 'objdump'
Assert-RegularFile $AcceptedStageManifest 'Accepted stage manifest'
if ((Get-Sha256File $AcceptedStageManifest) -ne $acceptedManifestSha256) { throw 'Accepted stage manifest SHA-256 is not the pinned v5 contract.' }
if ([IO.File]::ReadAllLines($AcceptedStageManifest).Count -ne $acceptedManifestFiles) { throw 'Accepted stage manifest file count is not pinned.' }

$expectedFiles = @(Read-ExpectedFiles)
if ($expectedFiles.Count -ne 3 -or [string]::Join(',', [string[]]$expectedFiles.Name) -ne [string]::Join(',', [string[]]$pinned.Name)) {
    throw 'Supplement file set is not exact'
}
if ($TestMode) {
    for ($index = 0; $index -lt $pinned.Count; $index++) {
        $expected = $expectedFiles[$index]; $production = $pinned[$index]
        if (-not $expected.Name.Equals($production.Name, [StringComparison]::Ordinal) -or
            $expected.Length -ne $production.Length -or
            -not $expected.Sha256.Equals($production.Sha256, [StringComparison]::Ordinal) -or
            -not $expected.PeMachine.Equals($production.PeMachine, [StringComparison]::Ordinal)) {
            throw "Synthetic expected supplement contract differs from production pins at index $index."
        }
    }
}
$audited = [Collections.Generic.List[object]]::new()
foreach ($expected in $expectedFiles) {
    $regular = Get-RegularPinnedFile (Join-Path $SourceBin $expected.Name) $expected.Length $expected.Sha256
    $machine = Get-PeMachine $ObjdumpPath $regular.Path
    if ($machine -ne $expected.PeMachine -or $machine -ne 'pei-x86-64') { throw "Supplement PE machine mismatch for $($expected.Name)" }
    $audited.Add([pscustomobject]@{ Name=$expected.Name; Path=$regular.Path; Length=$regular.Length; Sha256=$regular.Sha256; PeMachine=$machine })
}
$closure = Resolve-SupplementClosure ([string[]]$expectedFiles.Name) $SourceBin $pureBin
$predicted = Get-PredictedStageManifest $AcceptedStageManifest @($audited)
$addedBytes = [long]($audited | Measure-Object -Property Length -Sum).Sum
if (-not $TestMode) {
    if ($addedBytes -ne 7241216 -or $predicted.FileCount -ne 64312 -or $predicted.TotalBytes -ne 3334971045 -or $predicted.Sha256 -ne '115AC1F8843FFC60A4FFD103DCB7CD9C3099CAE14F2B3B674EF5D6230DF22DE0') {
        throw 'Predicted stage contract differs from the audited immutable postcondition.'
    }
}
$contract = [ordered]@{
    SnapshotRoot=$SnapshotRoot
    Files=@($audited | Select-Object Name,Length,Sha256,PeMachine)
    ReusedPureDependencies=@($closure.ReusedPureDependencies)
    AddedFileCount=[long]3
    AddedBytes=$addedBytes
    ExpectedStageFileCount=$predicted.FileCount
    ExpectedStageBytes=$predicted.TotalBytes
    ExpectedStageManifestSha256=$predicted.Sha256
    ExpectedAuditedPeCount=[long]1539
    ExpectedAuditedOctCount=[long]219
    ExpectedPinnedPlaceholderCount=[long]1
}

$changes = 3
if (Test-Path -LiteralPath $SnapshotRoot) {
    if ($Mode -eq 'Apply') { throw 'Snapshot root must be absent' }
    if (-not (Test-Path -LiteralPath $SnapshotRoot -PathType Container)) { throw 'Existing snapshot root is not a directory.' }
    Assert-NoReparsePath $SnapshotRoot 'Existing snapshot root'
    $actualItems = @(Get-ChildItem -LiteralPath $SnapshotRoot -Force)
    if ($actualItems.Count -ne 3 -or @($actualItems | Where-Object {
        -not ($_ -is [IO.FileInfo]) -or (($_.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0)
    }).Count -ne 0) { throw 'Existing snapshot file set is not exact.' }
    foreach ($file in $audited) { Get-RegularPinnedFile (Join-Path $SnapshotRoot $file.Name) $file.Length $file.Sha256 | Out-Null }
    $actualNames = @(($actualItems | Sort-Object Name).Name)
    if ([string]::Join(',', [string[]]$actualNames) -ne [string]::Join(',', ([string[]]$pinned.Name | Sort-Object))) { throw 'Existing snapshot file set is not exact.' }
    $changes = 0
}

if ($Mode -eq 'Apply') {
    $temporary = $SnapshotRoot + '.tmp'
    if (Test-Path -LiteralPath $temporary) { throw "Temporary snapshot sibling must be absent: $temporary" }
    $createdTemporary = $false
    try {
        [IO.Directory]::CreateDirectory($temporary) | Out-Null; $createdTemporary = $true
        for ($index = 0; $index -lt $audited.Count; $index++) {
            [IO.File]::Copy($audited[$index].Path, (Join-Path $temporary $audited[$index].Name), $false)
            if ($InjectFailureAfterFirstCopy -and $index -eq 0) {
                if (-not $TestMode -or -not $SnapshotRoot.StartsWith($testRoot + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'Failure injection is restricted to the exact synthetic root.' }
                throw 'Injected failure after first copied file'
            }
        }
        foreach ($file in $audited) {
            $copy = Get-RegularPinnedFile (Join-Path $temporary $file.Name) $file.Length $file.Sha256
            if ((Get-PeMachine $ObjdumpPath $copy.Path) -ne 'pei-x86-64') { throw "Copied supplement PE machine mismatch for $($file.Name)" }
            Get-PeImports $ObjdumpPath $copy.Path | Out-Null
        }
        foreach ($file in $audited) { Get-RegularPinnedFile $file.Path $file.Length $file.Sha256 | Out-Null }
        [IO.Directory]::Move($temporary, $SnapshotRoot); $createdTemporary = $false
        foreach ($file in $audited) { Get-RegularPinnedFile $file.Path $file.Length $file.Sha256 | Out-Null }
        $contractText = ConvertTo-Psd1Literal $contract
        $contractParent = Split-Path -Parent $ContractOutput
        [IO.Directory]::CreateDirectory($contractParent) | Out-Null
        $contractTemporary = $ContractOutput + '.tmp'
        if (Test-Path -LiteralPath $contractTemporary) { throw "Contract temporary sibling must be absent: $contractTemporary" }
        [IO.File]::WriteAllText($contractTemporary, $contractText, $utf8NoBom)
        Move-Item -LiteralPath $contractTemporary -Destination $ContractOutput -Force
    }
    catch {
        if ($createdTemporary -and (Test-Path -LiteralPath $temporary)) { Remove-Item -LiteralPath $temporary -Recurse -Force }
        throw
    }
}

[pscustomobject]@{
    Mode=$Mode
    Changes=[long]$changes
    SnapshotRoot=$SnapshotRoot
    Files=$contract.Files
    ReusedPureDependencies=$contract.ReusedPureDependencies
    ImportEdges=$closure.ImportEdges
    AddedFileCount=$contract.AddedFileCount
    AddedBytes=$contract.AddedBytes
    ExpectedStageFileCount=$contract.ExpectedStageFileCount
    ExpectedStageBytes=$contract.ExpectedStageBytes
    ExpectedStageManifestSha256=$contract.ExpectedStageManifestSha256
    ExpectedAuditedPeCount=$contract.ExpectedAuditedPeCount
    ExpectedAuditedOctCount=$contract.ExpectedAuditedOctCount
    ExpectedPinnedPlaceholderCount=$contract.ExpectedPinnedPlaceholderCount
} | ConvertTo-Json -Depth 8
