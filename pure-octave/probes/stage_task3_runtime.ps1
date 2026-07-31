[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string] $StageRoot,
    [Parameter(Mandatory = $true)][string] $DisposableParent,
    [Parameter(Mandatory = $true)][string] $PermanentOctaveRoot,
    [Parameter(Mandatory = $true)][string] $PureRuntimeRoot,
    [Parameter(Mandatory = $true)][string] $NormalizedOctaveRoot,
    [Parameter(Mandatory = $true)][string] $BridgeRoot,
    [Parameter(Mandatory = $true)][string] $BridgeModuleSource,
    [Parameter(Mandatory = $true)][string] $ProbeRoot,
    [Parameter(Mandatory = $true)][string] $PatchedLiboctave,
    [Parameter(Mandatory = $true)][ValidatePattern('^[0-9A-Fa-f]{64}$')][string] $ExpectedPatchedSha256,
    [Parameter(Mandatory = $true)][ValidatePattern('^[0-9A-Fa-f]{64}$')][string] $ExpectedLibgccSha256,
    [string] $Objdump = 'C:\tmp\todo51-task3\toolchain-normalize-pristine\mingw64\bin\objdump.exe',
    [string] $NormalizedSnapshot = 'C:\tmp\todo51-task3\toolchain-normalized-before-msys.tsv',
    [string] $PermanentSnapshot = 'C:\tmp\todo51-task3\permanent-before.tsv',
    [string] $NormalizedIdempotenceEvidence = 'C:\tmp\todo51-task3\normalizer-idempotence-apply.stdout.json',
    [ValidatePattern('^[0-9A-Fa-f]{64}$')][string] $ExpectedNormalizedSnapshotSha256 = 'B19A1BAB6293EBAAD7D0076B43D5E8F466BA896EAADFD81EED7E0C7C8F96FB31',
    [ValidatePattern('^[0-9A-Fa-f]{64}$')][string] $ExpectedNormalizedIdempotenceEvidenceSha256 = 'FA3FD0315B4B32B68A0C3FD860D83DCAE8A268E978B5C576A64006912428AF59',
    [ValidatePattern('^[0-9A-Fa-f]{64}$')][string] $ExpectedNormalizedManifestSha256 = '9417DC1DC935E33ACADACA3A0AD86389F500B937F7670E3D177A8D58B3C68CED',
    [ValidatePattern('^[0-9A-Fa-f]{64}$')][string] $ExpectedPermanentManifestSha256 = '95D51222C8000706D235A309EF1CAEA6D986B08F1B04A08671475AD041A18CCD',
    [switch] $SeparateLoaderRoots,
    [switch] $TestMode
)

# This assembler deliberately never starts a staged binary.  It validates every
# input first, creates an absent disposable root once, and thereafter writes only
# below that root.  The strict runner is a later Task 3 checkpoint.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)

function Get-Sha256File([string] $Path) {
    # Streaming avoids loading large DLLs and avoids the per-file cmdlet
    # overhead that can turn a full 59k-file evidence pass into a timeout.
    $stream = New-Object IO.FileStream($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash($stream))).Replace('-','') }
    finally { $sha.Dispose(); $stream.Dispose() }
}

function Assert-LocalDosPath([string] $Path, [string] $Description) {
    if ($Path -notmatch '^[A-Za-z]:\\' -or $Path -match '^(\\\\|\\\?\\|\\\.\\)' -or $Path -match '[\\/]\.\.([\\/]|$)') {
        throw "$Description is not a local drive-letter DOS path: $Path"
    }
}

function Get-CanonicalExistingPath([string] $Path, [string] $Description) {
    Assert-LocalDosPath $Path $Description
    if (-not (Test-Path -LiteralPath $Path)) { throw "$Description does not exist: $Path" }
    return [IO.Path]::GetFullPath((Get-Item -LiteralPath $Path -Force).FullName).TrimEnd('\\')
}

function Assert-NoReparsePath([string] $Path, [string] $Description) {
    $full = [IO.Path]::GetFullPath($Path).TrimEnd('\\')
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

function Assert-StrictChild([string] $Child, [string] $Parent, [string] $Description) {
    $childFull = [IO.Path]::GetFullPath($Child).TrimEnd('\\')
    $parentFull = [IO.Path]::GetFullPath($Parent).TrimEnd('\\')
    if (-not $childFull.StartsWith($parentFull + '\', [StringComparison]::OrdinalIgnoreCase)) {
        throw "$Description is not a strict child of disposable parent: $childFull"
    }
}

function Assert-NoReparseTree([string] $Root, [string] $Description) {
    Assert-NoReparsePath $Root $Description
    foreach ($item in Get-ChildItem -LiteralPath $Root -Recurse -Force) {
        if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "$Description contains a reparse point: $($item.FullName)"
        }
    }
}

function Get-TreeManifest([string] $Root, [string[]] $ExcludedRelative = @(), [string[]] $Order = @()) {
    $excluded = @{}
    foreach ($entry in $ExcludedRelative) { $excluded[$entry.Replace('\','/').ToLowerInvariant()] = $true }
    $files = @(
        Get-ChildItem -LiteralPath $Root -Recurse -Force -File |
        Where-Object {
            $relative = $_.FullName.Substring($Root.Length + 1).Replace('\','/')
            -not $excluded.ContainsKey($relative.ToLowerInvariant())
        }
    )
    $paths = [string[]] @($files | ForEach-Object { $_.FullName.Substring($Root.Length + 1).Replace('\','/') })
    if ($Order.Count -gt 0) { $paths = [string[]]$Order } else { [Array]::Sort($paths, [StringComparer]::Ordinal) }
    $lines = New-Object 'Collections.Generic.List[string]'
    [long] $bytes = 0
    foreach ($relative in $paths) {
        $file = Join-Path $Root $relative.Replace('/','\')
        $item = Get-Item -LiteralPath $file -Force
        $bytes += $item.Length
        $lines.Add(('{0}`t{1}`t{2}' -f $relative, $item.Length, (Get-Sha256File $file)))
    }
    $text = if ($lines.Count -eq 0) { '' } elseif ($Order.Count -gt 0) { ($lines -join "`r`n") + "`r`n" } else { ($lines -join "`n") + "`n" }
    [pscustomobject]@{ FileCount=[long]$paths.Count; TotalBytes=$bytes; Text=$text; Sha256=(Get-Sha256Bytes $utf8NoBom.GetBytes($text)) }
}

function Get-ManifestOrder([string] $Reference) {
    Assert-RegularFile $Reference 'Manifest order reference'
    $paths = New-Object 'Collections.Generic.List[string]'
    $seen = @{}
    foreach ($line in Get-Content -LiteralPath $Reference) {
        $fields = $line.Split("`t")
        if ($fields.Count -ne 3 -or [string]::IsNullOrWhiteSpace($fields[0]) -or $fields[0] -match '(^|/)(\.|\.\.)(/|$)') { throw "Invalid manifest order record: $line" }
        if ($seen.ContainsKey($fields[0])) { throw "Duplicate manifest order path: $($fields[0])" }
        $seen[$fields[0]] = $true
        $paths.Add($fields[0])
    }
    return [string[]]$paths.ToArray()
}

function Assert-ExpectedTree([string] $Root, [string[]] $Order, [long] $ExpectedFiles, [long] $ExpectedBytes, [string] $ExpectedHash, [string] $Description) {
    $actual = @(Get-ChildItem -LiteralPath $Root -Recurse -Force -File | ForEach-Object { $_.FullName.Substring($Root.Length + 1).Replace('\','/') })
    if ($actual.Count -ne $Order.Count) { throw "$Description file count does not match its audited order reference." }
    $set = @{}; foreach ($path in $actual) { $set[$path] = $true }
    foreach ($path in $Order) { if (-not $set.ContainsKey($path)) { throw "$Description is missing audited path $path" } }
    $manifest = Get-TreeManifest $Root @() $Order
    if ($manifest.FileCount -ne $ExpectedFiles -or $manifest.TotalBytes -ne $ExpectedBytes -or -not $manifest.Sha256.Equals($ExpectedHash, [StringComparison]::OrdinalIgnoreCase)) { throw "$Description does not match its audited inventory or manifest SHA-256: actual $($manifest.FileCount) / $($manifest.TotalBytes) / $($manifest.Sha256), expected $ExpectedFiles / $ExpectedBytes / $ExpectedHash." }
}

function Assert-SnapshotTree([string] $Root, [string] $Snapshot, [string] $ExpectedSnapshotHash, [long] $ExpectedFiles, [long] $ExpectedBytes, [string] $Description) {
    Assert-RegularFile $Snapshot "$Description snapshot"
    if ((Get-Sha256File $Snapshot) -ne $ExpectedSnapshotHash.ToUpperInvariant()) { throw "$Description snapshot hash is not the approved record." }
    $records = @(Get-Content -LiteralPath $Snapshot)
    if ($records.Count -ne $ExpectedFiles) { throw "$Description snapshot record count is unexpected." }
    $actual = @(Get-ChildItem -LiteralPath $Root -Recurse -Force -File)
    if ($actual.Count -ne $records.Count) { throw "$Description file count differs from its approved snapshot." }
    $seen = @{}; [long]$bytes = 0
    foreach ($record in $records) {
        $fields = $record.Split("`t")
        if ($fields.Count -ne 3 -or $fields[0] -match '(^|/)(\.|\.\.)(/|$)' -or $fields[0].Contains('\')) { throw "$Description snapshot has an unsafe record." }
        if ($seen.ContainsKey($fields[0])) { throw "$Description snapshot has a duplicate record." }; $seen[$fields[0]] = $true
        $path = Join-Path $Root $fields[0].Replace('/','\')
        Assert-RegularFile $path "$Description snapshot path"
        $item = Get-Item -LiteralPath $path -Force; $bytes += $item.Length
        if ($item.Length -ne [long]$fields[1] -or (Get-Sha256File $path) -ne $fields[2].ToUpperInvariant()) { throw "$Description differs from approved snapshot at $($fields[0])." }
    }
    if ($bytes -ne $ExpectedBytes) { throw "$Description byte count differs from approved snapshot." }
}

function Get-Sha256Bytes([byte[]] $Bytes) {
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash($Bytes))).Replace('-','') }
    finally { $sha.Dispose() }
}

function Copy-TreeTracked([string] $Source, [string] $Destination, [string] $Role, [Collections.Generic.List[string]] $Mappings) {
    [IO.Directory]::CreateDirectory($Destination) | Out-Null
    foreach ($file in Get-ChildItem -LiteralPath $Source -Recurse -Force -File) {
        $relative = $file.FullName.Substring($Source.Length + 1)
        $target = Join-Path $Destination $relative
        [IO.Directory]::CreateDirectory((Split-Path -Parent $target)) | Out-Null
        if (Test-Path -LiteralPath $target) { throw "Stage collision for $target while copying $Role" }
        [IO.File]::Copy($file.FullName, $target, $false)
        $Mappings.Add(('"{0}"`t"{1}"`t{2}`t{3}' -f $file.FullName, $target, $Role, (Get-Sha256File $file.FullName)))
    }
}

function Copy-FileTracked([string] $Source, [string] $Destination, [string] $Role, [Collections.Generic.List[string]] $Mappings) {
    [IO.Directory]::CreateDirectory((Split-Path -Parent $Destination)) | Out-Null
    if (Test-Path -LiteralPath $Destination) { throw "Stage collision for $Destination while copying $Role" }
    [IO.File]::Copy($Source, $Destination, $false)
    $Mappings.Add(('"{0}"`t"{1}"`t{2}`t{3}' -f $Source, $Destination, $Role, (Get-Sha256File $Source)))
}

function Assert-RegularFile([string] $Path, [string] $Description) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "$Description is missing: $Path" }
    if (((Get-Item -LiteralPath $Path -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw "$Description is a reparse point: $Path" }
}

function Get-PeImports([string] $Tool, [string] $File) {
    $output = & $Tool -p $File 2>&1
    if ($LASTEXITCODE -ne 0) { throw "objdump failed for staged PE file: $File`n$output" }
    return @($output | ForEach-Object { if ($_ -match '^\s*DLL Name:\s*(.+?)\s*$') { $Matches[1].Trim() } })
}

Assert-LocalDosPath $DisposableParent 'Disposable parent'
Assert-LocalDosPath $StageRoot 'Stage root'
Assert-StrictChild $StageRoot $DisposableParent 'Stage root'
$parent = Get-CanonicalExistingPath $DisposableParent 'Disposable parent'
Assert-NoReparsePath $parent 'Disposable parent'
if (Test-Path -LiteralPath $StageRoot) { throw "Stage root must be absent: $StageRoot" }
Assert-NoReparsePath ([IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($StageRoot))) 'Stage root parent'

$permanent = Get-CanonicalExistingPath $PermanentOctaveRoot 'Permanent Octave root'
$pure = Get-CanonicalExistingPath $PureRuntimeRoot 'Pure runtime root'
$octave = Get-CanonicalExistingPath $NormalizedOctaveRoot 'Normalized Octave root'
$bridge = Get-CanonicalExistingPath $BridgeRoot 'Bridge root'
$bridgeModule = Get-CanonicalExistingPath $BridgeModuleSource 'Bridge module source'
$probe = Get-CanonicalExistingPath $ProbeRoot 'Probe root'
$patched = Get-CanonicalExistingPath $PatchedLiboctave 'Patched liboctave'
foreach ($pair in @(@($pure,'Pure runtime root'), @($octave,'Normalized Octave root'), @($bridge,'Bridge root'), @($probe,'Probe root'))) { Assert-NoReparseTree $pair[0] $pair[1] }
Assert-RegularFile $patched 'Patched liboctave'
Assert-RegularFile $bridgeModule 'Bridge module source'
if ($octave.Equals($permanent, [StringComparison]::OrdinalIgnoreCase)) { throw 'Normalized Octave root resolves to the permanent Octave root.' }
if ((Get-Sha256File $patched) -ne $ExpectedPatchedSha256.ToUpperInvariant()) { throw 'Patched liboctave SHA-256 does not match the required artifact.' }
$octaveDll = Join-Path $octave 'mingw64\bin\liboctave-13.dll'
$gcc = Join-Path $octave 'mingw64\bin\libgcc_s_seh-1.dll'
Assert-RegularFile $octaveDll 'Normalized source liboctave'
Assert-RegularFile $gcc 'Normalized runtime libgcc'
if ((Get-Sha256File $gcc) -ne $ExpectedLibgccSha256.ToUpperInvariant()) { throw 'Normalized runtime libgcc SHA-256 is not the approved loader copy.' }

if (-not $TestMode) {
    $expectedRoot = 'C:\tmp\todo51-task3\toolchain-normalize-pristine'
    if (-not $octave.Equals($expectedRoot, [StringComparison]::OrdinalIgnoreCase)) { throw "Non-test staging requires the verified normalized root: $expectedRoot" }
    Assert-SnapshotTree $octave $NormalizedSnapshot $ExpectedNormalizedSnapshotSha256 59533 2797722565 'Normalized source runtime'
    Assert-SnapshotTree $permanent $PermanentSnapshot $ExpectedPermanentManifestSha256 59533 2797722287 'Permanent Octave runtime before staging'
    Assert-RegularFile $NormalizedIdempotenceEvidence 'Normalized idempotence evidence'
    if ((Get-Sha256File $NormalizedIdempotenceEvidence) -ne $ExpectedNormalizedIdempotenceEvidenceSha256.ToUpperInvariant()) { throw 'Normalized idempotence evidence hash is not approved.' }
    $evidence = Get-Content -LiteralPath $NormalizedIdempotenceEvidence -Raw | ConvertFrom-Json
    if ($evidence.ResultFileCount -ne 59533 -or $evidence.ResultTotalBytes -ne 2797722565 -or $evidence.ResultManifestSha256 -ne $ExpectedNormalizedManifestSha256) { throw 'Normalized idempotence evidence does not attest the required canonical manifest.' }
}
$pureBefore = Get-TreeManifest $pure
$bridgeBefore = Get-TreeManifest $bridge
$bridgeModuleBefore = Get-Sha256File $bridgeModule
$patchedBefore = Get-Sha256File $patched

# All validation is complete; this is the first write under the absent stage.
[IO.Directory]::CreateDirectory($StageRoot) | Out-Null
$mappings = New-Object 'Collections.Generic.List[string]'
try {
    Copy-TreeTracked $octave $StageRoot 'normalized-octave' $mappings
    Copy-TreeTracked $pure (Join-Path $StageRoot 'pure') 'verified-pure-runtime' $mappings
    foreach ($name in @('octave_embed.dll','octave_bridge_impl.dll')) {
        Copy-FileTracked (Join-Path $bridge $name) (Join-Path $StageRoot ('bridge\\' + $name)) 'verified-bridge' $mappings
    }
    Copy-FileTracked $bridgeModule (Join-Path $StageRoot 'bridge\\octave.pure') 'repository-bridge-module' $mappings
    foreach ($name in @('embed_probe.cc')) { Copy-FileTracked (Join-Path $probe $name) (Join-Path $StageRoot ('probes\\' + $name)) 'public-embed-probe' $mappings }
    $packageRoot = Split-Path -Parent $PSScriptRoot
    foreach ($entry in @(@('tests\\basic.pure','tests\\basic.pure'), @('cmake\\RunEmbedProbe.cmake','cmake\\RunEmbedProbe.cmake'), @('cmake\\RunPureTest.cmake','cmake\\RunPureTest.cmake'))) {
        $source = Join-Path $packageRoot $entry[0]
        Assert-RegularFile $source "Required public test script $($entry[0])"
        Copy-FileTracked $source (Join-Path $StageRoot ('scripts\\' + $entry[1].Replace('tests\\','').Replace('cmake\\',''))) 'public-test-script' $mappings
    }
    # Only the stage copy is replaced; source and permanent roots were never opened for write.
    [IO.File]::Copy($patched, (Join-Path $StageRoot 'mingw64\bin\liboctave-13.dll'), $true)
    $mappings.Add(('"{0}"`t"{1}"`tpatched-liboctave`t{2}' -f $patched, (Join-Path $StageRoot 'mingw64\bin\liboctave-13.dll'), (Get-Sha256File $patched)))
    if ((Get-Sha256File (Join-Path $StageRoot 'mingw64\bin\liboctave-13.dll')) -ne $ExpectedPatchedSha256.ToUpperInvariant()) { throw 'Staged liboctave does not match the patched artifact.' }
    if ((Get-Sha256File $octaveDll) -eq $ExpectedPatchedSha256.ToUpperInvariant()) { throw 'Source normalized Octave unexpectedly already contains the patched DLL.' }

    # Production uses separate Pure and Octave loader roots: their same-named
    # vendor DLLs must never be silently merged.
    $stageBin = Join-Path $StageRoot 'mingw64\bin'
    if (-not $SeparateLoaderRoots) { foreach ($file in Get-ChildItem -LiteralPath (Join-Path $pure 'bin') -File -Force) {
        $target = Join-Path $stageBin $file.Name
        if (Test-Path -LiteralPath $target) {
            if ((Get-Sha256File $target) -ne (Get-Sha256File $file.FullName)) { throw "Pure/Octave runtime DLL collision: $($file.Name)" }
            $mappings.Add(('"{0}"`t"{1}"`tpure-runtime-loader-closure-identical-name-approved`t{2}' -f $file.FullName, $target, (Get-Sha256File $file.FullName)))
        } else { Copy-FileTracked $file.FullName $target 'pure-runtime-loader-closure' $mappings }
    } }
    if (-not $SeparateLoaderRoots) { foreach ($file in Get-ChildItem -LiteralPath $bridge -File -Force | Where-Object { $_.Extension -ieq '.dll' }) {
        $target = Join-Path $stageBin $file.Name
        if (-not (Test-Path -LiteralPath $target)) { Copy-FileTracked $file.FullName $target 'bridge-loader-closure' $mappings }
        elseif ((Get-Sha256File $target) -ne (Get-Sha256File $file.FullName)) { throw "Bridge/Octave runtime DLL collision: $($file.Name)" }
        else { $mappings.Add(('"{0}"`t"{1}"`tbridge-loader-closure-identical-name-approved`t{2}' -f $file.FullName, $target, (Get-Sha256File $file.FullName))) }
    } }
    Assert-NoReparseTree $StageRoot 'Staged runtime'

    $runtimeFiles = @('mingw64\\bin\\liboctave-13.dll','mingw64\\bin\\libgcc_s_seh-1.dll')
    foreach ($relative in $runtimeFiles) { Assert-RegularFile (Join-Path $StageRoot $relative) "Staged $relative" }
    if ((Get-Sha256File (Join-Path $StageRoot 'mingw64\bin\libgcc_s_seh-1.dll')) -ne $ExpectedLibgccSha256.ToUpperInvariant()) { throw 'Staged loader directory does not contain the approved libgcc.' }
    $compilerCopies = @(Get-ChildItem -LiteralPath $StageRoot -Recurse -Force -File -Filter 'libgcc_s_seh-1.dll')
    foreach ($copy in $compilerCopies) {
        if ($copy.FullName -ne (Join-Path $StageRoot 'mingw64\bin\libgcc_s_seh-1.dll') -and $copy.FullName.StartsWith($stageBin + '\', [StringComparison]::OrdinalIgnoreCase)) { throw "Unapproved libgcc duplicate is in the effective loader directory: $($copy.FullName)" }
    }

    if (-not $TestMode) {
        Assert-RegularFile $Objdump 'External objdump'
        $apiSetSchema = Join-Path $env:WINDIR 'System32\apisetschema.dll'
        Assert-RegularFile $apiSetSchema 'Windows API-set schema'
        $apiContracts = New-Object 'Collections.Generic.List[string]'
        $pureBin = Join-Path $StageRoot 'pure\bin'
        $octaveSet = @{}; foreach ($item in Get-ChildItem -LiteralPath $stageBin -File -Force) { $octaveSet[$item.Name.ToLowerInvariant()] = @($item.FullName) }
        $pureSet = @{}; foreach ($item in Get-ChildItem -LiteralPath $pureBin -File -Force) { $pureSet[$item.Name.ToLowerInvariant()] = @($item.FullName) }
        $peFiles = @()
        foreach ($f in Get-ChildItem -LiteralPath $stageBin -File -Force | Where-Object { $_.Extension -in @('.dll','.exe') }) { $peFiles += [pscustomobject]@{File=$f;Group='octave'} }
        foreach ($f in Get-ChildItem -LiteralPath $pureBin -File -Force | Where-Object { $_.Extension -in @('.dll','.exe') }) { $peFiles += [pscustomobject]@{File=$f;Group='pure'} }
        foreach ($f in Get-ChildItem -LiteralPath (Join-Path $StageRoot 'bridge') -File -Force | Where-Object { $_.Extension -ieq '.dll' }) { $peFiles += [pscustomobject]@{File=$f;Group='bridge'} }
        $imports = New-Object 'Collections.Generic.List[string]'
        foreach ($pe in $peFiles) {
            $effective = if ($pe.Group -eq 'octave') { $octaveSet } elseif ($pe.Group -eq 'pure') { $pureSet } else { $both=@{}; foreach($set in @($pureSet,$octaveSet)){foreach($key in $set.Keys){if(-not $both.ContainsKey($key)){$both[$key]=@()};$both[$key]+=$set[$key]}}; $both }
            foreach ($dll in Get-PeImports $Objdump $pe.File.FullName) {
                $key = $dll.ToLowerInvariant(); $resolved = ''
                if ($effective.ContainsKey($key)) { if ($effective[$key].Count -ne 1) { throw "Ambiguous effective staged import $dll" }; $resolved = $effective[$key][0] }
                else {
                    if ($dll -match '^(api-ms-win-|ext-ms-win-).+\.dll$') {
                        $resolved = 'virtual-api-set-contract; runtime-loader-gate-required'
                        $apiContracts.Add($dll.ToLowerInvariant())
                    } else { $system = Join-Path $env:WINDIR ('System32\\' + $dll); if (-not (Test-Path -LiteralPath $system -PathType Leaf)) { throw "Missing effective import $dll needed by $($pe.File.FullName)" }; $resolved = $system }
                }
                $imports.Add(('"{0}"`t{1}`t{2}`t"{3}"' -f $pe.File.FullName,$pe.Group,$dll,$resolved))
            }
        }
        [IO.File]::WriteAllText((Join-Path $StageRoot 'stage-import-closure.tsv'), (($imports | Sort-Object) -join "`n") + "`n", $utf8NoBom)
        $apiSetText = "OSBuild`t$([Environment]::OSVersion.VersionString)`nApiSetSchema`t$apiSetSchema`t$(Get-Sha256File $apiSetSchema)`n" + (($apiContracts | Sort-Object -Unique) -join "`n") + "`n"
        [IO.File]::WriteAllText((Join-Path $StageRoot 'stage-api-set-contracts.tsv'), $apiSetText, $utf8NoBom)
    }
    $excluded = @('stage-manifest.tsv','stage-mapping.tsv','stage-import-closure.tsv','stage-api-set-contracts.tsv')
    $manifest = Get-TreeManifest $StageRoot $excluded
    [IO.File]::WriteAllText((Join-Path $StageRoot 'stage-manifest.tsv'), $manifest.Text, $utf8NoBom)
    [IO.File]::WriteAllText((Join-Path $StageRoot 'stage-mapping.tsv'), (($mappings | Sort-Object) -join "`n") + "`n", $utf8NoBom)
    $pureAfter = Get-TreeManifest $pure
    $bridgeAfter = Get-TreeManifest $bridge
    if ($pureAfter.FileCount -ne $pureBefore.FileCount -or $pureAfter.TotalBytes -ne $pureBefore.TotalBytes -or $pureAfter.Sha256 -ne $pureBefore.Sha256) { throw 'Pure runtime source changed during staging.' }
    if ($bridgeAfter.FileCount -ne $bridgeBefore.FileCount -or $bridgeAfter.TotalBytes -ne $bridgeBefore.TotalBytes -or $bridgeAfter.Sha256 -ne $bridgeBefore.Sha256) { throw 'Bridge source changed during staging.' }
    if ((Get-Sha256File $bridgeModule) -ne $bridgeModuleBefore) { throw 'Bridge module source changed during staging.' }
    if ((Get-Sha256File $patched) -ne $patchedBefore) { throw 'Patched DLL artifact changed during staging.' }
    if (-not $TestMode) { Assert-SnapshotTree $octave $NormalizedSnapshot $ExpectedNormalizedSnapshotSha256 59533 2797722565 'Normalized source runtime after staging'; Assert-SnapshotTree $permanent $PermanentSnapshot $ExpectedPermanentManifestSha256 59533 2797722287 'Permanent Octave runtime after staging' }
    [pscustomobject]@{ StageRoot=$StageRoot; FileCount=$manifest.FileCount; TotalBytes=$manifest.TotalBytes; ManifestSha256=$manifest.Sha256; PatchedLiboctaveSha256=(Get-Sha256File (Join-Path $StageRoot 'mingw64\bin\liboctave-13.dll')); LibgccSha256=(Get-Sha256File (Join-Path $StageRoot 'mingw64\bin\libgcc_s_seh-1.dll')); ImportAuditSkipped=[bool]$TestMode } | ConvertTo-Json -Depth 3
}
catch {
    throw
}
