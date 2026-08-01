[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string] $StageRoot,
    [Parameter(Mandatory = $true)][string] $DisposableParent,
    [Parameter(Mandatory = $true)][string] $PermanentOctaveRoot,
    [Parameter(Mandatory = $true)][string] $PureRuntimeRoot,
    [Parameter(Mandatory = $true)][string] $NormalizedOctaveRoot,
    [Parameter(Mandatory = $true)][string] $BridgeRoot,
    [string] $BridgeBinaryRoot = '',
    [Parameter(Mandatory = $true)][string] $BridgeModuleSource,
    [Parameter(Mandatory = $true)][string] $ProbeRoot,
    [Parameter(Mandatory = $true)][string] $PatchedLiboctave,
    [Parameter(Mandatory = $true)][ValidatePattern('^[0-9A-Fa-f]{64}$')][string] $ExpectedPatchedSha256,
    [Parameter(Mandatory = $true)][ValidatePattern('^[0-9A-Fa-f]{64}$')][string] $ExpectedLibgccSha256,
    [long] $ExpectedPureFileCount = 4769,
    [long] $ExpectedPureTotalBytes = 260533868,
    [ValidatePattern('^[0-9A-Fa-f]{64}$')][string] $ExpectedPureManifestSha256 = '52DA19745D9F33DEC4CEAF09E24E3836C04E82E1651BB695990D18B14D667FE3',
    [long] $ExpectedBridgeFileCount = 2,
    [long] $ExpectedBridgeTotalBytes = 4771866,
    [ValidatePattern('^[0-9A-Fa-f]{64}$')][string] $ExpectedBridgeManifestSha256 = '974C07999D4EBC62C218F0EDA7D271B6CCC7AFDEBD1EBFA063C7A25109C4CE11',
    [ValidatePattern('^[0-9A-Fa-f]{64}$')][string] $ExpectedBridgeModuleSha256 = '51A4FADE279C91CB63103EFD7A0A97FB1DF9E674F807A7E0BF65991D6E6066F0',
    [ValidatePattern('^[0-9A-Fa-f]{64}$')][string] $ExpectedProbeSha256 = '8924A6A2FC79FB1C0F0B97248014079D685D1724C1708523FE08240CA87424A5',
    [string] $Objdump = 'C:\tmp\todo51-task3\toolchain-normalize-pristine\mingw64\bin\objdump.exe',
    [string] $NormalizedSnapshot = 'C:\tmp\todo51-task3\toolchain-normalized-before-msys.tsv',
    [string] $PermanentSnapshot = 'C:\tmp\todo51-task3\permanent-before.tsv',
    [string] $NormalizedIdempotenceEvidence = 'C:\tmp\todo51-task3\normalizer-idempotence-apply.stdout.json',
    [ValidatePattern('^[0-9A-Fa-f]{64}$')][string] $ExpectedNormalizedSnapshotSha256 = 'B19A1BAB6293EBAAD7D0076B43D5E8F466BA896EAADFD81EED7E0C7C8F96FB31',
    [ValidatePattern('^[0-9A-Fa-f]{64}$')][string] $ExpectedNormalizedIdempotenceEvidenceSha256 = 'FA3FD0315B4B32B68A0C3FD860D83DCAE8A268E978B5C576A64006912428AF59',
    [ValidatePattern('^[0-9A-Fa-f]{64}$')][string] $ExpectedNormalizedManifestSha256 = '9417DC1DC935E33ACADACA3A0AD86389F500B937F7670E3D177A8D58B3C68CED',
    [ValidatePattern('^[0-9A-Fa-f]{64}$')][string] $ExpectedPermanentManifestSha256 = '95D51222C8000706D235A309EF1CAEA6D986B08F1B04A08671475AD041A18CCD',
    [string] $SyntheticImportManifest = '',
    [string] $SyntheticSystemMappingManifest = '',
    [string] $SyntheticArtifactEvidence = '',
    [string] $SyntheticObjectEvidence = '',
    [string] $SyntheticBuildEvidence = '',
    [switch] $InjectSupplementDestinationCollision,
    [switch] $InjectSupplementMappingMismatch,
    [switch] $InjectFourthSupplementDependency,
    [switch] $InjectSupplementContractSchemaFault,
    [switch] $InjectSupplementPostconditionFault,
    [ValidateSet('','PeCount','OctCount','PlaceholderCount','FileCount','ByteCount','ManifestSha256')][string] $InjectSupplementPostAuditFault = '',
    [switch] $InjectGnuplotCaseCollision,
    [ValidateSet('','Sibling','Nested','NonPe','ReparseRoot','ReparseFile')][string] $InjectGnuplotAuditFault = '',
    [ValidateSet('FileCount','PeCount','ImportEdgeCount','ApplicationDirectoryEdgeCount','ApiSetEdgeCount','System32EdgeCount','UnresolvedEdgeCount')][string] $InjectGnuplotPostAuditFault = '',
    [switch] $InjectGnuplotApiSetReleaseFailure,
    [switch] $TestMode
)

# This assembler deliberately never starts a staged binary.  It validates every
# input first, creates an absent disposable root once, and thereafter writes only
# below that root.  The strict runner is a later Task 3 checkpoint.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ($InjectGnuplotCaseCollision -and -not $TestMode) { throw 'Gnuplot case-collision injection is TestMode-only and has no production access.' }
if ($InjectGnuplotAuditFault -and -not $TestMode) { throw 'Gnuplot audit fault injection is TestMode-only and has no production access.' }
if ($InjectGnuplotPostAuditFault -and -not $TestMode) { throw 'Gnuplot post-audit fault injection is TestMode-only and has no production access.' }
if ($InjectGnuplotApiSetReleaseFailure -and -not $TestMode) { throw 'Gnuplot API-set release injection is TestMode-only and has no production access.' }
if ($InjectSupplementPostAuditFault -and -not $TestMode) { throw 'Post-audit supplement failure injection is TestMode-only and has no production access.' }
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$acceptedPatchedSha256 = 'A10BBD461B628379F02CF87E059F89C2F4485F69D88AD2C51466E8789DAF2663'
$acceptedLibgccSha256 = '592E6966F66D7993726D3CE329E81B658188E5CB286ACE9DE56C2FAB939EA491'
$acceptedPermanentRoot = 'C:\Tools\GNU Octave\11.3.0'
$acceptedPureRoot = 'C:\tmp\Relocated Pure Gplot Final Bundle 20260729'
$acceptedBridgeRoot = 'C:\pure-lang\pure-octave'
$acceptedBridgeBinaryRoot = 'C:\tmp\Pure Octave Permanent Build 20260730\lib\pure'
$acceptedOctaveRoot = 'C:\tmp\todo51-task3\toolchain-normalize-pristine'
$acceptedPatchedPath = 'C:\tmp\todo51-task3\build-normalized-confined\liboctave\.libs\liboctave-13.dll'
$acceptedProbeRoot = 'C:\pure-lang\pure-octave\probes'
$acceptedBridgeModulePath = 'C:\pure-lang\pure-octave\octave.pure'
$acceptedPackageRoot = 'C:\pure-lang\pure-octave'
$acceptedObjdump = 'C:\tmp\todo51-task3\toolchain-normalize-pristine\mingw64\bin\objdump.exe'
$acceptedPatchPath = 'C:\pure-lang\pure-octave\patches\octave-11.3.0-appcontainer-canonicalization.patch'
$acceptedPatchSha256 = '521C6C501B1146A253E306314A454D4C545D0385450BAC6068D3FC6A7C968E71'
$acceptedHelperHeaderPath = 'C:\pure-lang\pure-octave\probes\windows_system_volume_canonicalization.h'
$acceptedHelperHeaderSha256 = '7C7A46B7202F9A7E6F89CD7D53C28F0F48AFFB495E18FCE34E525AC5DA0D0D44'
$acceptedArtifactEvidence = 'C:\tmp\todo51-task3\liboctave-normalized-confined-artifact-audit.log'
$acceptedObjectEvidence = 'C:\tmp\todo51-task3\liboctave-normalized-confined-patch-object-audit.log'
$acceptedBuildEvidence = 'C:\tmp\todo51-task3\liboctave-normalized-confined.log'
$acceptedArtifactEvidenceSha256 = 'C56E0746AA0673447F6BD64117772BEC9D450321C53F508A96352818F7EB964C'
$acceptedObjectEvidenceSha256 = 'DFB6BA01DCDDCBDDEDA4FAA278556284F68C89B2AA79E417FDDFDA463893B9F0'
$acceptedBuildEvidenceSha256 = '842678BFBBC560B4258EE15920C1E36B030D334B2B8BC948C6768CA6613E3608'
$acceptedApiSchemaSha256 = '8FFADF5FF3D8D3843FC393E9D03C2091AC5DDFC6227B8097DC182E2A8F8463FC'
$acceptedOsVersion = 'Microsoft Windows NT 10.0.26200.0'
$acceptedGnuplotRelativeRoot = 'pure/tools/gnuplot/bin'
$acceptedGnuplotFileCount = 65
$acceptedGnuplotPeFileCount = 63
$acceptedGnuplotImportEdgeCount = 1002
$acceptedGnuplotApplicationDirectoryEdgeCount = 249
$acceptedGnuplotApiSetEdgeCount = 563
$acceptedGnuplotSystem32EdgeCount = 190
$acceptedGnuplotUnresolvedEdgeCount = 0
$acceptedStageFiles = 64309
$acceptedStageBytes = 3327729829
$acceptedStageManifestSha256 = 'E142C07EDA4D71184D1892189834818B9DCE7AD44B8F0A6708A51C54FA56476F'
$acceptedSupplementContractSha256 = '692341FA19E6D7AC3CF4C02894DBDB92AFAE7A5DD154B659A5CFD099AD63F2CC'
$acceptedSupplementSnapshotRoot = 'C:\tmp\todo51-task3\pure-rsvg-supplement-v1'
$acceptedSupplementSourceRoot = 'C:\msys64\clang64\bin'
$acceptedSupplementFiles = @(
    [pscustomobject]@{ Name='librsvg-2-2.dll'; Length=[long]5882880; Sha256='9F90DE3779E80F590B542AFDF79C105A403B0C566265D69EACBBF9B524338F89'; PeMachine='pei-x86-64' },
    [pscustomobject]@{ Name='libunwind.dll'; Length=[long]63488; Sha256='60FA3C200899BC6E4A5876B82E2C656FF72FC53EC55979D99CB7C4EF640A6D96'; PeMachine='pei-x86-64' },
    [pscustomobject]@{ Name='libxml2-16.dll'; Length=[long]1294848; Sha256='C6C34A810D86C19C034A1BC96C4C500BDE8FB789DED69B434E67EEE773605852'; PeMachine='pei-x86-64' }
)
$syntheticArtifactEvidenceSha256 = '86083033EE13E6B733D2F59393B28009D0A3C635F288AFF492F6D964788CE479'
$syntheticObjectEvidenceSha256 = '0C7F800EE9C9696F5BEF78524D8021DDE617255734C5940BF5B922FB47ABB302'
$syntheticBuildEvidenceSha256 = '58CFBD17EEBEB306E5251A63B0EE5EF0425B6C7C51767303156EEF1A6F93F01B'
$syntheticPatchedSha256 = 'DD8C8FC072699F2AE0767DEDAF66276E536E85737B9EF3FDF95C9D9C052577DC'
$syntheticLibgccSha256 = '66679E04C91C3FEA75FF8CC85C0DD2F09BB2007EB1439DE8F236A56980BDEA52'
$syntheticPureFileCount = 4
$syntheticPureTotalBytes = 41
$syntheticPureManifestSha256 = 'A20CD63507F946EE07E9B9419662F3BD754FF7151B99468C49AAB6985EDAD3AE'
$syntheticBridgeFileCount = 3
$syntheticBridgeTotalBytes = 30
$syntheticBridgeManifestSha256 = '025D6C9E917AA89AE1B068CD87598E96C00896F1D2BEE6AD139C7BF1BCD78648'
$syntheticBridgeModuleSha256 = '120970D812836F19888625587A4606A5AD23CEF31C8684E601771552548FC6B9'
$syntheticGnuplotPureFileCount = 6
$syntheticGnuplotPureTotalBytes = 63
$syntheticGnuplotPureManifestSha256 = 'D5C9A7FB7C74CC7E937FF2FF3B0586EC519492EE1823821BE4DD40B5F1DA3C3A'
$syntheticProbeSha256 = 'BA9C736F19E7F60B7F6764ADB0B7908C0A2B394E09B6C09863528C7F2BC86095'
$approvedInertPlaceholders = @(
    [pscustomobject]@{ Relative = 'mingw64/qt6/bin/qhelpgenerator.exe'; Length = [long]0; Sha256 = 'E3B0C44298FC1C149AFBF4C8996FB92427AE41E4649B934CA495991B7852B855' }
)
$acceptedAuditedPeFileCount = 1536
$acceptedAuditedOctFileCount = 219
$acceptedInput = [ordered]@{
    PureFileCount = 4769; PureTotalBytes = 260533868; PureManifestSha256 = '52DA19745D9F33DEC4CEAF09E24E3836C04E82E1651BB695990D18B14D667FE3'
    BridgeFileCount = 2; BridgeTotalBytes = 4771866; BridgeManifestSha256 = '974C07999D4EBC62C218F0EDA7D271B6CCC7AFDEBD1EBFA063C7A25109C4CE11'
    BridgeModuleSha256 = '51A4FADE279C91CB63103EFD7A0A97FB1DF9E674F807A7E0BF65991D6E6066F0'
    ProbeSha256 = '8924A6A2FC79FB1C0F0B97248014079D685D1724C1708523FE08240CA87424A5'
}
$acceptedRepositoryFiles = [ordered]@{
    'tests\basic.pure' = '23C378107498CF605C4777132C817CDAE6D090306007F0E67A83CCD4D726346D'
    'cmake\RunEmbedProbe.cmake' = '73BEE376A8D2A23897D9FBA85277F5B59439C45BE442300B43AC63388F003DCB'
    'cmake\RunPureTest.cmake' = 'A45618D605CB6B70F6D5008351731F786F7C3D97CF0537A4BEFC47DEF2BA08CB'
}

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

function Assert-ExactPath([string] $Actual, [string] $Expected, [string] $Description) {
    if (-not ([IO.Path]::GetFullPath($Actual).TrimEnd('\')).Equals(([IO.Path]::GetFullPath($Expected).TrimEnd('\')), [StringComparison]::OrdinalIgnoreCase)) {
        throw "$Description is not the fixed approved path: $Expected"
    }
}

function Assert-SourceBoundary([string] $Source, [string] $Root, [string] $Description) {
    $sourceFull = [IO.Path]::GetFullPath($Source).TrimEnd('\')
    $rootFull = [IO.Path]::GetFullPath($Root).TrimEnd('\')
    if (-not $sourceFull.Equals($rootFull, [StringComparison]::OrdinalIgnoreCase) -and
        -not $sourceFull.StartsWith($rootFull + '\', [StringComparison]::OrdinalIgnoreCase)) {
        throw "$Description escapes its explicit provenance root: $sourceFull"
    }
    Assert-NoReparsePath $sourceFull $Description
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

function Copy-TreeTracked([string] $Source, [string] $Destination, [string] $Role, [string] $ProvenanceRoot, [Collections.Generic.List[string]] $Mappings) {
    Assert-SourceBoundary $Source $ProvenanceRoot "$Role source root"
    [IO.Directory]::CreateDirectory($Destination) | Out-Null
    foreach ($file in Get-ChildItem -LiteralPath $Source -Recurse -Force -File) {
        Assert-SourceBoundary $file.FullName $ProvenanceRoot "$Role source file"
        $relative = $file.FullName.Substring($Source.Length + 1)
        $target = Join-Path $Destination $relative
        [IO.Directory]::CreateDirectory((Split-Path -Parent $target)) | Out-Null
        if (Test-Path -LiteralPath $target) { throw "Stage collision for $target while copying $Role" }
        [IO.File]::Copy($file.FullName, $target, $false)
        $Mappings.Add(('"{0}"' -f $file.FullName) + "`t" + ('"{0}"' -f $target) + "`t$Role`t" + (Get-Sha256File $file.FullName))
    }
}

function Copy-FileTracked([string] $Source, [string] $Destination, [string] $Role, [string] $ProvenanceRoot, [Collections.Generic.List[string]] $Mappings) {
    Assert-SourceBoundary $Source $ProvenanceRoot "$Role source file"
    [IO.Directory]::CreateDirectory((Split-Path -Parent $Destination)) | Out-Null
    if (Test-Path -LiteralPath $Destination) { throw "Stage collision for $Destination while copying $Role" }
    [IO.File]::Copy($Source, $Destination, $false)
    $Mappings.Add(('"{0}"' -f $Source) + "`t" + ('"{0}"' -f $Destination) + "`t$Role`t" + (Get-Sha256File $Source))
}

function Assert-RegularFile([string] $Path, [string] $Description) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "$Description is missing: $Path" }
    if (((Get-Item -LiteralPath $Path -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw "$Description is a reparse point: $Path" }
}

function Assert-ExactDataKeys([Collections.IDictionary] $Value, [string[]] $Expected, [string] $Description) {
    $actual = [string[]]@($Value.Keys)
    [Array]::Sort($actual, [StringComparer]::Ordinal)
    $wanted = [string[]]@($Expected)
    [Array]::Sort($wanted, [StringComparer]::Ordinal)
    if ($actual.Count -ne $wanted.Count -or [string]::Join("`n", $actual) -cne [string]::Join("`n", $wanted)) {
        throw "$Description does not contain exactly the declared schema keys."
    }
}

function Get-PeMachine([string] $Path, [string] $Description) {
    Assert-RegularFile $Path $Description
    $stream = New-Object IO.FileStream($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
    $reader = New-Object IO.BinaryReader($stream)
    try {
        if ($stream.Length -lt 64 -or $reader.ReadUInt16() -ne 0x5a4d) { throw "$Description is not a PE image." }
        [void]$stream.Seek(0x3c, [IO.SeekOrigin]::Begin)
        $peOffset = $reader.ReadUInt32()
        if ($peOffset -gt $stream.Length - 6) { throw "$Description has an invalid PE header offset." }
        [void]$stream.Seek($peOffset, [IO.SeekOrigin]::Begin)
        if ($reader.ReadUInt32() -ne 0x00004550) { throw "$Description has an invalid PE signature." }
        $machine = $reader.ReadUInt16()
        if ($machine -eq 0x8664) { return 'pei-x86-64' }
        return ('0x{0:X4}' -f $machine)
    }
    finally { $reader.Dispose(); $stream.Dispose() }
}

function Assert-PinnedSupplementFile([string] $Path, $Record, [string] $Description) {
    Assert-RegularFile $Path $Description
    $item = Get-Item -LiteralPath $Path -Force
    $machine = Get-PeMachine $Path $Description
    if ($machine -cne $Record.PeMachine) { throw "$Description PE machine is $machine, expected $($Record.PeMachine)." }
    $sha256 = Get-Sha256File $Path
    if ($item.Length -ne [long]$Record.Length -or $sha256 -cne $Record.Sha256) {
        throw "$Description length or SHA-256 does not match the pinned contract."
    }
}

function Assert-ExactSupplementTree([string] $Root, $Records, [string] $Description) {
    Assert-NoReparseTree $Root $Description
    $items = @(Get-ChildItem -LiteralPath $Root -Force)
    if ($items.Count -ne $Records.Count -or @($items | Where-Object { -not $_.PSIsContainer -and ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0 }).Count -ne $Records.Count) {
        throw "$Description must contain exactly three regular non-reparse files."
    }
    $actualNames = [string[]]@($items.Name); [Array]::Sort($actualNames, [StringComparer]::Ordinal)
    $expectedNames = [string[]]@($Records.Name); [Array]::Sort($expectedNames, [StringComparer]::Ordinal)
    if ([string]::Join("`n", $actualNames) -cne [string]::Join("`n", $expectedNames)) { throw "$Description contains a missing or unlisted snapshot file." }
    foreach ($record in $Records) { Assert-PinnedSupplementFile (Join-Path $Root $record.Name) $record "$Description $($record.Name)" }
}

function Assert-StageAuditPostconditions(
    [long] $ActualPeCount,
    [long] $ActualOctCount,
    [long] $ActualPlaceholderCount,
    [long] $ExpectedPeCount,
    [long] $ExpectedOctCount,
    [long] $ExpectedPlaceholderCount
) {
    if ($ActualPeCount -ne $ExpectedPeCount) { throw 'Staged PE audit count does not match the expected postcondition.' }
    if ($ActualOctCount -ne $ExpectedOctCount) { throw 'Staged .oct audit count does not match the expected postcondition.' }
    if ($ActualPlaceholderCount -ne $ExpectedPlaceholderCount) { throw 'Pinned inert placeholder audit count does not match the expected postcondition.' }
}

function Assert-GnuplotLoaderPostconditions(
    [long] $ActualFileCount,
    [long] $ActualPeCount,
    [long] $ActualImportEdgeCount,
    [long] $ActualApplicationDirectoryEdgeCount,
    [long] $ActualApiSetEdgeCount,
    [long] $ActualSystem32EdgeCount,
    [long] $ActualUnresolvedEdgeCount,
    [long] $ExpectedFileCount,
    [long] $ExpectedPeCount,
    [long] $ExpectedImportEdgeCount,
    [long] $ExpectedApplicationDirectoryEdgeCount,
    [long] $ExpectedApiSetEdgeCount,
    [long] $ExpectedSystem32EdgeCount,
    [long] $ExpectedUnresolvedEdgeCount
) {
    if ($ActualFileCount -ne $ExpectedFileCount) { throw 'Gnuplot loader file count does not match the expected postcondition.' }
    if ($ActualPeCount -ne $ExpectedPeCount) { throw 'Gnuplot loader PE file count does not match the expected postcondition.' }
    if ($ActualImportEdgeCount -ne $ExpectedImportEdgeCount) { throw 'Gnuplot loader import edge count does not match the expected postcondition.' }
    if ($ActualApplicationDirectoryEdgeCount -ne $ExpectedApplicationDirectoryEdgeCount) { throw 'Gnuplot loader application-directory edge count does not match the expected postcondition.' }
    if ($ActualApiSetEdgeCount -ne $ExpectedApiSetEdgeCount) { throw 'Gnuplot loader API-set edge count does not match the expected postcondition.' }
    if ($ActualSystem32EdgeCount -ne $ExpectedSystem32EdgeCount) { throw 'Gnuplot loader System32 edge count does not match the expected postcondition.' }
    if ($ActualUnresolvedEdgeCount -ne $ExpectedUnresolvedEdgeCount) { throw 'Gnuplot loader unresolved edge count does not match the expected postcondition.' }
    if ($ActualApplicationDirectoryEdgeCount + $ActualApiSetEdgeCount + $ActualSystem32EdgeCount + $ActualUnresolvedEdgeCount -ne $ActualImportEdgeCount) { throw 'Gnuplot loader edge origin counts do not sum to the total import edge count.' }
}

function Assert-FinalStagePostconditions(
    [long] $ActualFileCount,
    [long] $ActualByteCount,
    [string] $ActualManifestSha256,
    [long] $ExpectedFileCount,
    [long] $ExpectedByteCount,
    [string] $ExpectedManifestSha256
) {
    if ($ActualFileCount -ne $ExpectedFileCount) { throw 'Final stage file count does not match the expected postcondition.' }
    if ($ActualByteCount -ne $ExpectedByteCount) { throw 'Final stage byte count does not match the expected postcondition.' }
    if ($ActualManifestSha256 -cne $ExpectedManifestSha256) { throw 'Final stage manifest SHA-256 does not match the expected postcondition.' }
}

function Get-PeImports([string] $Tool, [string] $File) {
    $output = & $Tool -p $File 2>&1
    if ($LASTEXITCODE -ne 0) { throw "objdump failed for staged PE file: $File`n$output" }
    return @($output | ForEach-Object { if ($_ -match '^\s*DLL Name:\s*(.+?)\s*$') { $Matches[1].Trim() } })
}

function Test-PortableExecutable([string] $Path) {
    $stream = New-Object IO.FileStream($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
    try {
        if ($stream.Length -lt 2) { return $false }
        return ($stream.ReadByte() -eq 0x4d -and $stream.ReadByte() -eq 0x5a)
    }
    finally { $stream.Dispose() }
}
function Get-LoaderDomain([string] $Relative) {
    $gnuplotPrefix = $acceptedGnuplotRelativeRoot + '/'
    if ($Relative.StartsWith($gnuplotPrefix, [StringComparison]::OrdinalIgnoreCase)) {
        $leaf = $Relative.Substring($gnuplotPrefix.Length)
        if ($leaf.Length -gt 0 -and $leaf.IndexOf('/') -lt 0) { return 'pure-gnuplot-app' }
    }
    if ($Relative.StartsWith('pure/', [StringComparison]::OrdinalIgnoreCase)) { return 'pure' }
    if ($Relative.StartsWith('bridge/', [StringComparison]::OrdinalIgnoreCase)) { return 'bridge' }
    return 'octave'
}

function New-DirectLoaderSet([string] $Root, [string] $Description) {
    if (-not (Test-Path -LiteralPath $Root -PathType Container)) { throw "$Description is absent or is not a directory: $Root" }
    Assert-NoReparsePath $Root $Description
    $set = @{}
    foreach ($item in Get-ChildItem -LiteralPath $Root -File -Force) {
        Assert-NoReparsePath $item.FullName "$Description file"
        $key = $item.Name.ToLowerInvariant()
        if ($set.ContainsKey($key)) { throw "$Description has an ambiguous case-insensitive filename: $($item.Name)" }
        $set[$key] = @($item.FullName)
    }
    return $set
}

function Get-EffectiveLoaderSet([string] $Domain, [hashtable] $PureSet, [hashtable] $OctaveSet, [hashtable] $GnuplotSet) {
    switch ($Domain) {
        'pure' { return $PureSet }
        'octave' { return $OctaveSet }
        'pure-gnuplot-app' { return $GnuplotSet }
        'bridge' {
            $union = @{}
            foreach ($set in @($PureSet,$OctaveSet)) {
                foreach ($key in $set.Keys) {
                    if (-not $union.ContainsKey($key)) { $union[$key] = @() }
                    $union[$key] += $set[$key]
                }
            }
            return $union
        }
        default { throw "Unknown staged loader domain: $Domain" }
    }
}


function Get-PinnedInertPlaceholders([string] $Root, [string] $Description) {
    if ($approvedInertPlaceholders.Count -ne 1) { throw 'The production inert-placeholder approval cardinality must be exactly one.' }
    $records = New-Object 'Collections.Generic.List[object]'
    foreach ($approved in $approvedInertPlaceholders) {
        if ($approved.Relative -ne 'mingw64/qt6/bin/qhelpgenerator.exe' -or $approved.Length -ne 0 -or $approved.Sha256 -ne 'E3B0C44298FC1C149AFBF4C8996FB92427AE41E4649B934CA495991B7852B855') {
            throw 'The production inert-placeholder approval is not the exact pinned artifact.'
        }
        $path = Join-Path $Root $approved.Relative.Replace('/','\')
        Assert-RegularFile $path "$Description pinned inert placeholder"
        $item = Get-Item -LiteralPath $path -Force
        $sha256 = Get-Sha256File $path
        if ($item.Length -ne $approved.Length -or $sha256 -ne $approved.Sha256) {
            throw "$Description pinned inert placeholder does not have the approved length and SHA-256: $($approved.Relative)"
        }
        $records.Add([pscustomobject]@{ Relative = $approved.Relative; Length = [long]$item.Length; Sha256 = $sha256 })
    }
    return [object[]]$records.ToArray()
}

function Read-SyntheticImports([string] $Manifest, [string] $FixtureRoot) {
    Assert-SourceBoundary $Manifest $FixtureRoot 'Synthetic import manifest'
    Assert-RegularFile $Manifest 'Synthetic import manifest'
    $result = @{}
    foreach ($line in Get-Content -LiteralPath $Manifest) {
        $fields = $line.Split("`t")
        if ($fields.Count -ne 2 -or $fields[0] -notmatch '^[^:\\]+(?:/[^:\\]+)*$' -or $fields[0] -match '(^|/)\.\.?(?:/|$)') { throw "Invalid synthetic import record: $line" }
        $key = $fields[0].ToLowerInvariant()
        if ($result.ContainsKey($key)) { throw "Duplicate synthetic import record: $($fields[0])" }
        $result[$key] = if ($fields[1] -eq '-') { @() } else { [string[]]@($fields[1].Split(';') | ForEach-Object { $_.Trim() }) }
    }
    return $result
}

function Read-SyntheticSystemMappings([string] $Manifest, [string] $FixtureRoot) {
    Assert-SourceBoundary $Manifest $FixtureRoot 'Synthetic system mapping manifest'
    Assert-RegularFile $Manifest 'Synthetic system mapping manifest'
    $result = @{}
    foreach ($line in Get-Content -LiteralPath $Manifest) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        $fields = $line.Split("`t")
        if ($fields.Count -ne 2) { throw "Invalid synthetic system mapping record: $line" }
        $isApiSetContract = $fields[0] -match '^(api|ext)-ms-win-[a-z0-9][a-z0-9-]*-l[0-9]+-[0-9]+-[0-9]+\.dll$'
        $isApiSetLookalike = $fields[0] -match '^(api|ext)-ms-win-'
        if ($fields[0] -notmatch '^[A-Za-z0-9][A-Za-z0-9_.-]*\.dll$' -or ($isApiSetLookalike -and -not $isApiSetContract) -or $fields[1] -notmatch '^[A-Za-z0-9][A-Za-z0-9_.-]*\.dll$') { throw "Invalid synthetic system mapping record: $line" }
        $key = $fields[0].ToLowerInvariant()
        if ($result.ContainsKey($key)) { throw "Duplicate synthetic system mapping: $($fields[0])" }
        $result[$key] = $fields[1]
    }
    return $result
}

function Initialize-ApiSetResolver([string] $WriteRoot) {
    $helperTemp = Join-Path $WriteRoot ('.task3-api-resolver-' + [guid]::NewGuid().ToString('N'))
    Assert-StrictChild $helperTemp $WriteRoot 'API-set resolver temporary directory'
    [IO.Directory]::CreateDirectory($helperTemp) | Out-Null
    $saved = @{}
    foreach ($name in @('TEMP','TMP','TMPDIR')) {
        $saved[$name] = [pscustomobject]@{ Present = [Environment]::GetEnvironmentVariables('Process').Contains($name); Value = [Environment]::GetEnvironmentVariable($name, 'Process') }
        [Environment]::SetEnvironmentVariable($name, $helperTemp, 'Process')
    }
    try {
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Text;
public static class Task3ApiSetResolver {
  [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)] public static extern IntPtr LoadLibraryExW(string name, IntPtr file, uint flags);
  [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)] public static extern uint GetModuleFileNameW(IntPtr module, StringBuilder path, int size);
  [DllImport("kernel32.dll", SetLastError=true)] [return: MarshalAs(UnmanagedType.Bool)] public static extern bool FreeLibrary(IntPtr module);
}
'@
    }
    finally {
        foreach ($name in @('TEMP','TMP','TMPDIR')) {
            if ($saved[$name].Present) { [Environment]::SetEnvironmentVariable($name, $saved[$name].Value, 'Process') }
            else { [Environment]::SetEnvironmentVariable($name, $null, 'Process') }
        }
        if (Test-Path -LiteralPath $helperTemp) { [IO.Directory]::Delete($helperTemp, $true) }
    }
}

function Resolve-ApiSetContract([string] $Contract, [string] $System32) {
    $handle = [Task3ApiSetResolver]::LoadLibraryExW($Contract, [IntPtr]::Zero, 0x00000800)
    if ($handle -eq [IntPtr]::Zero) { throw "API-set contract has no authoritative local OS mapping: $Contract (Win32 $([Runtime.InteropServices.Marshal]::GetLastWin32Error()))" }
    $freeError = 0
    try {
        $buffer = New-Object Text.StringBuilder 32768
        $length = [Task3ApiSetResolver]::GetModuleFileNameW($handle, $buffer, $buffer.Capacity)
        if ($length -eq 0 -or $length -ge $buffer.Capacity) { throw "API-set contract mapping path could not be read: $Contract" }
        $resolved = [IO.Path]::GetFullPath($buffer.ToString()).TrimEnd('\')
    }
    finally {
        if (-not [Task3ApiSetResolver]::FreeLibrary($handle)) { $freeError = [Runtime.InteropServices.Marshal]::GetLastWin32Error() }
    }
    if ($freeError -ne 0) { throw "API-set contract mapping could not be freed: $Contract (Win32 $freeError)" }
    Assert-SourceBoundary $resolved $System32 "API-set host for $Contract"
    Assert-RegularFile $resolved "API-set host for $Contract"
    return $resolved
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
$bridgeBinary = Get-CanonicalExistingPath $(if ($BridgeBinaryRoot) { $BridgeBinaryRoot } else { $BridgeRoot }) 'Bridge binary root'
$bridgeModule = Get-CanonicalExistingPath $BridgeModuleSource 'Bridge module source'
$probe = Get-CanonicalExistingPath $ProbeRoot 'Probe root'
$patched = Get-CanonicalExistingPath $PatchedLiboctave 'Patched liboctave'
Assert-NoReparseTree $permanent 'Permanent Octave root'
Assert-StrictChild $bridgeModule $bridge 'Bridge module source'
foreach ($pair in @(@($pure,'Pure runtime root'), @($octave,'Normalized Octave root'), @($bridge,'Bridge root'), @($bridgeBinary,'Bridge binary root'), @($probe,'Probe root'))) { Assert-NoReparseTree $pair[0] $pair[1] }
Assert-RegularFile $patched 'Patched liboctave'
Assert-NoReparsePath $patched 'Patched liboctave'
Assert-RegularFile $bridgeModule 'Bridge module source'
if ($octave.Equals($permanent, [StringComparison]::OrdinalIgnoreCase)) { throw 'Normalized Octave root resolves to the permanent Octave root.' }
$packageRoot = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot)).TrimEnd('\')
Assert-NoReparsePath $packageRoot 'Repository package root'
$hasSupplementInjection = $InjectSupplementDestinationCollision -or $InjectSupplementMappingMismatch -or $InjectFourthSupplementDependency -or $InjectSupplementContractSchemaFault -or $InjectSupplementPostconditionFault -or [bool]$InjectSupplementPostAuditFault
if ($hasSupplementInjection -and -not $TestMode) { throw 'Supplement failure injection is TestMode-only and restricted to the exact synthetic fixture root.' }

if ($TestMode) {
    $fixtureRoot = [IO.Path]::GetDirectoryName($parent)
    if (-not (Split-Path -Leaf $parent).Equals('parent', [StringComparison]::OrdinalIgnoreCase) -or
        $fixtureRoot -notmatch '^C:\\tmp\\todo51-stage-tests-[0-9a-f]{32}$') {
        throw 'TestMode is allowed only within the exact synthetic fixture C:\tmp\todo51-stage-tests-<32 hex>\parent.'
    }
    Assert-ExactPath $parent (Join-Path $fixtureRoot 'parent') 'Synthetic disposable parent'
    foreach ($pair in @(
        @($permanent,'Synthetic permanent root'), @($pure,'Synthetic Pure root'), @($octave,'Synthetic Octave root'),
        @($bridge,'Synthetic bridge root'), @($bridgeBinary,'Synthetic bridge binary root'), @($probe,'Synthetic probe root'), @($patched,'Synthetic patched DLL'),
        @($SyntheticImportManifest,'Synthetic import manifest'), @($SyntheticSystemMappingManifest,'Synthetic system mapping manifest'),
        @($SyntheticArtifactEvidence,'Synthetic artifact evidence'), @($SyntheticObjectEvidence,'Synthetic object evidence'),
        @($SyntheticBuildEvidence,'Synthetic build evidence'))) {
        Assert-StrictChild $pair[0] $fixtureRoot $pair[1]
        Assert-NoReparsePath $pair[0] $pair[1]
    }
    $syntheticGnuplotRoot = Join-Path $pure 'tools\gnuplot\bin'
    if (Test-Path -LiteralPath $syntheticGnuplotRoot -PathType Container) {
        $syntheticPureFileCount = $syntheticGnuplotPureFileCount
        $syntheticPureTotalBytes = $syntheticGnuplotPureTotalBytes
        $syntheticPureManifestSha256 = $syntheticGnuplotPureManifestSha256
    }
    if ($ExpectedPatchedSha256 -ne $syntheticPatchedSha256 -or $ExpectedLibgccSha256 -ne $syntheticLibgccSha256 -or
        $ExpectedPureFileCount -ne $syntheticPureFileCount -or $ExpectedPureTotalBytes -ne $syntheticPureTotalBytes -or $ExpectedPureManifestSha256 -ne $syntheticPureManifestSha256 -or
        $ExpectedBridgeFileCount -ne $syntheticBridgeFileCount -or $ExpectedBridgeTotalBytes -ne $syntheticBridgeTotalBytes -or $ExpectedBridgeManifestSha256 -ne $syntheticBridgeManifestSha256 -or
        $ExpectedBridgeModuleSha256 -ne $syntheticBridgeModuleSha256 -or $ExpectedProbeSha256 -ne $syntheticProbeSha256) {
        throw 'TestMode input expectations must equal the exact versioned synthetic fixture.'
    }
    $requiredPatchedSha256 = $syntheticPatchedSha256
    $requiredLibgccSha256 = $syntheticLibgccSha256
    $requiredPureFileCount = $syntheticPureFileCount
    $requiredPureTotalBytes = $syntheticPureTotalBytes
    $requiredPureManifestSha256 = $syntheticPureManifestSha256
    $requiredBridgeFileCount = $syntheticBridgeFileCount
    $requiredBridgeTotalBytes = $syntheticBridgeTotalBytes
    $requiredBridgeManifestSha256 = $syntheticBridgeManifestSha256
    $requiredBridgeModuleSha256 = $syntheticBridgeModuleSha256
    $requiredProbeSha256 = $syntheticProbeSha256
    $artifactEvidencePath = $SyntheticArtifactEvidence
    $objectEvidencePath = $SyntheticObjectEvidence
    $buildEvidencePath = $SyntheticBuildEvidence
    $requiredArtifactEvidenceSha256 = $syntheticArtifactEvidenceSha256
    $requiredObjectEvidenceSha256 = $syntheticObjectEvidenceSha256
    $requiredBuildEvidenceSha256 = $syntheticBuildEvidenceSha256
}
else {
    if ($SyntheticImportManifest -or $SyntheticSystemMappingManifest -or $SyntheticArtifactEvidence -or $SyntheticObjectEvidence -or $SyntheticBuildEvidence) {
        throw 'Synthetic tool or evidence inputs are TestMode-only.'
    }
    if ($ExpectedPatchedSha256 -ne $acceptedPatchedSha256 -or $ExpectedLibgccSha256 -ne $acceptedLibgccSha256 -or
        $ExpectedPureFileCount -ne $acceptedInput.PureFileCount -or $ExpectedPureTotalBytes -ne $acceptedInput.PureTotalBytes -or $ExpectedPureManifestSha256 -ne $acceptedInput.PureManifestSha256 -or
        $ExpectedBridgeFileCount -ne $acceptedInput.BridgeFileCount -or $ExpectedBridgeTotalBytes -ne $acceptedInput.BridgeTotalBytes -or $ExpectedBridgeManifestSha256 -ne $acceptedInput.BridgeManifestSha256 -or
        $ExpectedBridgeModuleSha256 -ne $acceptedInput.BridgeModuleSha256 -or $ExpectedProbeSha256 -ne $acceptedInput.ProbeSha256 -or
        $ExpectedNormalizedSnapshotSha256 -ne 'B19A1BAB6293EBAAD7D0076B43D5E8F466BA896EAADFD81EED7E0C7C8F96FB31' -or
        $ExpectedNormalizedIdempotenceEvidenceSha256 -ne 'FA3FD0315B4B32B68A0C3FD860D83DCAE8A268E978B5C576A64006912428AF59' -or
        $ExpectedNormalizedManifestSha256 -ne '9417DC1DC935E33ACADACA3A0AD86389F500B937F7670E3D177A8D58B3C68CED' -or
        $ExpectedPermanentManifestSha256 -ne '95D51222C8000706D235A309EF1CAEA6D986B08F1B04A08671475AD041A18CCD') {
        throw 'Non-test staging rejects caller-controlled evidence or inventory overrides.'
    }
    Assert-ExactPath $octave $acceptedOctaveRoot 'Normalized Octave root'
    Assert-ExactPath $permanent $acceptedPermanentRoot 'Permanent Octave root'
    Assert-ExactPath $pure $acceptedPureRoot 'Pure runtime root'
    Assert-ExactPath $bridge $acceptedBridgeRoot 'Bridge root'
    Assert-ExactPath $bridgeBinary $acceptedBridgeBinaryRoot 'Bridge binary root'
    Assert-ExactPath $probe $acceptedProbeRoot 'Probe root'
    Assert-ExactPath $bridgeModule $acceptedBridgeModulePath 'Bridge module source'
    Assert-ExactPath $patched $acceptedPatchedPath 'Patched liboctave'
    Assert-ExactPath $packageRoot $acceptedPackageRoot 'Repository package root'
    Assert-ExactPath $Objdump $acceptedObjdump 'Static import auditor'
    Assert-ExactPath $NormalizedSnapshot 'C:\tmp\todo51-task3\toolchain-normalized-before-msys.tsv' 'Normalized snapshot evidence'
    Assert-ExactPath $PermanentSnapshot 'C:\tmp\todo51-task3\permanent-before.tsv' 'Permanent snapshot evidence'
    Assert-ExactPath $NormalizedIdempotenceEvidence 'C:\tmp\todo51-task3\normalizer-idempotence-apply.stdout.json' 'Normalizer idempotence evidence'
    $requiredPatchedSha256 = $acceptedPatchedSha256
    $requiredLibgccSha256 = $acceptedLibgccSha256
    $requiredPureFileCount = $acceptedInput.PureFileCount
    $requiredPureTotalBytes = $acceptedInput.PureTotalBytes
    $requiredPureManifestSha256 = $acceptedInput.PureManifestSha256
    $requiredBridgeFileCount = $acceptedInput.BridgeFileCount
    $requiredBridgeTotalBytes = $acceptedInput.BridgeTotalBytes
    $requiredBridgeManifestSha256 = $acceptedInput.BridgeManifestSha256
    $requiredBridgeModuleSha256 = $acceptedInput.BridgeModuleSha256
    $requiredProbeSha256 = $acceptedInput.ProbeSha256
    $artifactEvidencePath = $acceptedArtifactEvidence
    $objectEvidencePath = $acceptedObjectEvidence
    $buildEvidencePath = $acceptedBuildEvidence
    $requiredArtifactEvidenceSha256 = $acceptedArtifactEvidenceSha256
    $requiredObjectEvidenceSha256 = $acceptedObjectEvidenceSha256
    $requiredBuildEvidenceSha256 = $acceptedBuildEvidenceSha256
}

$supplementContractPath = Join-Path $PSScriptRoot 'task3-pure-rsvg-supplement-contract.psd1'
Assert-RegularFile $supplementContractPath 'Pinned Pure SVG supplement contract'
Assert-SourceBoundary $supplementContractPath $PSScriptRoot 'Pinned Pure SVG supplement contract'
if ((Get-Sha256File $supplementContractPath) -cne $acceptedSupplementContractSha256) { throw 'Pinned Pure SVG supplement contract SHA-256 is not approved.' }
$supplementContract = Import-PowerShellDataFile -LiteralPath $supplementContractPath
if ($TestMode -and $InjectSupplementContractSchemaFault) { $supplementContract['UnapprovedSchemaKey'] = 'synthetic fault' }
if ($TestMode -and $InjectSupplementPostconditionFault) { $supplementContract.ExpectedStageFileCount = [long]$supplementContract.ExpectedStageFileCount + 1 }
Assert-ExactDataKeys $supplementContract @('SnapshotRoot','Files','ReusedPureDependencies','AddedFileCount','AddedBytes','ExpectedStageFileCount','ExpectedStageBytes','ExpectedStageManifestSha256','ExpectedAuditedPeCount','ExpectedAuditedOctCount','ExpectedPinnedPlaceholderCount') 'Pinned Pure SVG supplement contract'
if ($supplementContract.SnapshotRoot -cne $acceptedSupplementSnapshotRoot) { throw 'Pinned Pure SVG supplement contract snapshot root is not exact.' }
$contractFiles = @($supplementContract.Files)
if ($contractFiles.Count -ne 3) { throw 'Pinned Pure SVG supplement contract must declare exactly three files.' }
for ($index = 0; $index -lt $acceptedSupplementFiles.Count; $index++) {
    $actual = $contractFiles[$index]; $expected = $acceptedSupplementFiles[$index]
    Assert-ExactDataKeys $actual @('Name','Length','Sha256','PeMachine') "Pinned supplement file record $index"
    if ($actual.Name -cne $expected.Name -or [long]$actual.Length -ne $expected.Length -or $actual.Sha256 -cne $expected.Sha256 -or $actual.PeMachine -cne $expected.PeMachine) {
        throw "Pinned supplement file record $index does not match the production pin."
    }
}
$reusedPureDependencies = @($supplementContract.ReusedPureDependencies)
if ($reusedPureDependencies.Count -ne 38) { throw 'Pinned Pure SVG supplement contract must declare exactly 38 reused Pure dependencies.' }
$reusedNames = @{}
foreach ($record in $reusedPureDependencies) {
    Assert-ExactDataKeys $record @('Name','Length','PureSha256','SourceSha256') "Reused Pure dependency $($record.Name)"
    if ($record.Name -notmatch '^[A-Za-z0-9_.+-]+\.dll$' -or $record.Name -match '[\\/:]' -or
        $record.PureSha256 -notmatch '^[0-9A-F]{64}$' -or $record.SourceSha256 -notmatch '^[0-9A-F]{64}$' -or $reusedNames.ContainsKey($record.Name)) {
        throw 'Pinned Pure SVG supplement contract has an invalid or duplicate reused dependency record.'
    }
    $reusedNames[$record.Name] = $true
}
if ([long]$supplementContract.AddedFileCount -ne 3 -or [long]$supplementContract.AddedBytes -ne 7241216 -or
    [long]$supplementContract.ExpectedStageFileCount -ne 64312 -or [long]$supplementContract.ExpectedStageFileCount -ne ($acceptedStageFiles + [long]$supplementContract.AddedFileCount) -or
    [long]$supplementContract.ExpectedStageBytes -ne 3334971045 -or [long]$supplementContract.ExpectedStageBytes -ne ($acceptedStageBytes + [long]$supplementContract.AddedBytes) -or
    $supplementContract.ExpectedStageManifestSha256 -cne '115AC1F8843FFC60A4FFD103DCB7CD9C3099CAE14F2B3B674EF5D6230DF22DE0' -or
    [long]$supplementContract.ExpectedAuditedPeCount -ne 1539 -or [long]$supplementContract.ExpectedAuditedPeCount -ne ($acceptedAuditedPeFileCount + 3) -or
    [long]$supplementContract.ExpectedAuditedOctCount -ne 219 -or [long]$supplementContract.ExpectedAuditedOctCount -ne $acceptedAuditedOctFileCount -or
    [long]$supplementContract.ExpectedPinnedPlaceholderCount -ne 1) {
    throw 'Pinned Pure SVG supplement contract does not have the exact fixed arithmetic and stage postconditions.'
}
if ($TestMode) {
    $supplementSnapshotRoot = Get-CanonicalExistingPath (Join-Path $fixtureRoot 'supplement-snapshot') 'Synthetic supplement snapshot'
    $supplementSourceRoot = Get-CanonicalExistingPath (Join-Path $fixtureRoot 'supplement-source') 'Synthetic supplement source'
    Assert-StrictChild $supplementSnapshotRoot $fixtureRoot 'Synthetic supplement snapshot'
    Assert-StrictChild $supplementSourceRoot $fixtureRoot 'Synthetic supplement source'
}
else {
    $supplementSnapshotRoot = Get-CanonicalExistingPath $supplementContract.SnapshotRoot 'Pinned supplement snapshot'
    $supplementSourceRoot = Get-CanonicalExistingPath $acceptedSupplementSourceRoot 'Pinned supplement source'
    Assert-ExactPath $supplementSnapshotRoot $acceptedSupplementSnapshotRoot 'Pinned supplement snapshot'
    Assert-ExactPath $supplementSourceRoot $acceptedSupplementSourceRoot 'Pinned supplement source'
}
Assert-ExactSupplementTree $supplementSnapshotRoot $contractFiles 'Supplement snapshot'
foreach ($record in $contractFiles) {
    $source = Join-Path $supplementSourceRoot $record.Name
    Assert-SourceBoundary $source $supplementSourceRoot "Supplement source $($record.Name)"
    Assert-PinnedSupplementFile $source $record "Supplement source $($record.Name)"
}
if (-not $TestMode) {
    foreach ($record in $reusedPureDependencies) {
        $pureDependency = Join-Path $pure ('bin\' + $record.Name)
        $sourceDependency = Join-Path $supplementSourceRoot $record.Name
        Assert-SourceBoundary $pureDependency $pure "Reused Pure dependency $($record.Name)"
        Assert-SourceBoundary $sourceDependency $supplementSourceRoot "Reused source dependency $($record.Name)"
        Assert-RegularFile $pureDependency "Reused Pure dependency $($record.Name)"
        Assert-RegularFile $sourceDependency "Reused source dependency $($record.Name)"
        if ((Get-Item -LiteralPath $pureDependency).Length -ne [long]$record.Length -or (Get-Sha256File $pureDependency) -cne $record.PureSha256 -or
            (Get-Item -LiteralPath $sourceDependency).Length -ne [long]$record.Length -or (Get-Sha256File $sourceDependency) -cne $record.SourceSha256) {
            throw "Reused Pure dependency does not match the exact contract: $($record.Name)"
        }
    }
}

if (-not $TestMode) {
    foreach ($sourceEvidence in @(
        @($acceptedPatchPath,$acceptedPatchSha256,'Accepted canonicalization patch'),
        @($acceptedHelperHeaderPath,$acceptedHelperHeaderSha256,'Accepted canonicalization helper header'))) {
        Assert-RegularFile $sourceEvidence[0] $sourceEvidence[2]
        Assert-SourceBoundary $sourceEvidence[0] $packageRoot $sourceEvidence[2]
        if ((Get-Sha256File $sourceEvidence[0]) -ne $sourceEvidence[1]) { throw "$($sourceEvidence[2]) is not the exact approved provenance input." }
    }
}

if ((Get-Sha256File $patched) -ne $requiredPatchedSha256) { throw 'Patched liboctave SHA-256 does not match the required artifact.' }
$octaveDll = Join-Path $octave 'mingw64\bin\liboctave-13.dll'
$gcc = Join-Path $octave 'mingw64\bin\libgcc_s_seh-1.dll'
Assert-RegularFile $octaveDll 'Normalized source liboctave'
Assert-RegularFile $gcc 'Normalized runtime libgcc'
if ((Get-Sha256File $gcc) -ne $requiredLibgccSha256) { throw 'Normalized runtime libgcc SHA-256 is not the approved loader copy.' }

$pureBefore = Get-TreeManifest $pure
if ($pureBefore.FileCount -ne $requiredPureFileCount -or $pureBefore.TotalBytes -ne $requiredPureTotalBytes -or $pureBefore.Sha256 -ne $requiredPureManifestSha256) {
    throw "Pure runtime input does not match its exact approved inventory: actual $($pureBefore.FileCount) / $($pureBefore.TotalBytes) / $($pureBefore.Sha256)."
}
$bridgeBefore = Get-TreeManifest $bridgeBinary
if ($bridgeBefore.FileCount -ne $requiredBridgeFileCount -or $bridgeBefore.TotalBytes -ne $requiredBridgeTotalBytes -or $bridgeBefore.Sha256 -ne $requiredBridgeManifestSha256) {
    throw "Bridge binary input does not match its exact approved inventory: actual $($bridgeBefore.FileCount) / $($bridgeBefore.TotalBytes) / $($bridgeBefore.Sha256)."
}
if ((Get-Sha256File $bridgeModule) -ne $requiredBridgeModuleSha256) { throw 'Bridge module source does not match its exact approved SHA-256.' }
$probeSource = Join-Path $probe 'embed_probe.cc'
Assert-RegularFile $probeSource 'Public embed probe source'
Assert-SourceBoundary $probeSource $probe 'Public embed probe source'
if ((Get-Sha256File $probeSource) -ne $requiredProbeSha256) { throw 'Public embed probe does not match its exact approved SHA-256.' }

foreach ($evidencePair in @(
    @($artifactEvidencePath,$requiredArtifactEvidenceSha256,'Patched artifact evidence'),
    @($objectEvidencePath,$requiredObjectEvidenceSha256,'Patched object evidence'),
    @($buildEvidencePath,$requiredBuildEvidenceSha256,'Confined build evidence'))) {
    Assert-RegularFile $evidencePair[0] $evidencePair[2]
    Assert-NoReparsePath $evidencePair[0] $evidencePair[2]
    if ((Get-Sha256File $evidencePair[0]) -ne $evidencePair[1]) { throw "$($evidencePair[2]) is not the exact approved evidence." }
}

foreach ($relative in $acceptedRepositoryFiles.Keys) {
    $source = Join-Path $packageRoot $relative
    Assert-RegularFile $source "Required public test script $relative"
    Assert-SourceBoundary $source $packageRoot "Required public test script $relative"
    if ((Get-Sha256File $source) -ne $acceptedRepositoryFiles[$relative]) { throw "Required public test script $relative does not match its exact approved SHA-256." }
}

if (-not $TestMode) {
    Assert-SnapshotTree $octave $NormalizedSnapshot 'B19A1BAB6293EBAAD7D0076B43D5E8F466BA896EAADFD81EED7E0C7C8F96FB31' 59533 2797722565 'Normalized source runtime'
    Assert-SnapshotTree $permanent $PermanentSnapshot '95D51222C8000706D235A309EF1CAEA6D986B08F1B04A08671475AD041A18CCD' 59533 2797722287 'Permanent Octave runtime before staging'
    Assert-RegularFile $NormalizedIdempotenceEvidence 'Normalized idempotence evidence'
    if ((Get-Sha256File $NormalizedIdempotenceEvidence) -ne 'FA3FD0315B4B32B68A0C3FD860D83DCAE8A268E978B5C576A64006912428AF59') { throw 'Normalized idempotence evidence hash is not approved.' }
    $evidence = Get-Content -LiteralPath $NormalizedIdempotenceEvidence -Raw | ConvertFrom-Json
    if ($evidence.ResultFileCount -ne 59533 -or $evidence.ResultTotalBytes -ne 2797722565 -or $evidence.ResultManifestSha256 -ne '9417DC1DC935E33ACADACA3A0AD86389F500B937F7670E3D177A8D58B3C68CED') { throw 'Normalized idempotence evidence does not attest the required canonical manifest.' }
}
$sourcePinnedInertPlaceholders = @(Get-PinnedInertPlaceholders $octave 'Normalized source runtime')
$bridgeModuleBefore = Get-Sha256File $bridgeModule
$patchedBefore = Get-Sha256File $patched

# All validation is complete; this is the first write under the absent stage.
[IO.Directory]::CreateDirectory($StageRoot) | Out-Null
$mappings = New-Object 'Collections.Generic.List[string]'
try {
    Copy-TreeTracked $octave $StageRoot 'normalized-octave' $octave $mappings
    Copy-TreeTracked $pure (Join-Path $StageRoot 'pure') 'verified-pure-runtime' $pure $mappings
    $supplementMappingStart = $mappings.Count
    if ($TestMode -and $InjectSupplementDestinationCollision) {
        [IO.File]::WriteAllText((Join-Path $StageRoot 'pure\bin\librsvg-2-2.dll'), 'synthetic collision', $utf8NoBom)
    }
    foreach ($record in $contractFiles) {
        $source = Join-Path $supplementSnapshotRoot $record.Name
        $destination = Join-Path $StageRoot ('pure\bin\' + $record.Name)
        Copy-FileTracked $source $destination 'pinned-pure-rsvg-supplement' $supplementSnapshotRoot $mappings
        Assert-PinnedSupplementFile $destination $record "Staged supplement $($record.Name)"
    }
    if ($TestMode -and $InjectSupplementMappingMismatch) { $mappings[$supplementMappingStart] = $mappings[$supplementMappingStart] + '-synthetic-mismatch' }
    if ($mappings.Count - $supplementMappingStart -ne 3) { throw 'Pinned supplement tracked-copy mapping count is not exactly three.' }
    for ($index = 0; $index -lt $contractFiles.Count; $index++) {
        $record = $contractFiles[$index]
        $source = Join-Path $supplementSnapshotRoot $record.Name
        $destination = Join-Path $StageRoot ('pure\bin\' + $record.Name)
        $expectedMapping = ('"{0}"' -f $source) + "`t" + ('"{0}"' -f $destination) + "`tpinned-pure-rsvg-supplement`t$($record.Sha256)"
        if ($mappings[$supplementMappingStart + $index] -cne $expectedMapping) { throw "Pinned supplement tracked-copy mapping mismatch for $($record.Name)." }
    }
    Assert-ExactSupplementTree $supplementSnapshotRoot $contractFiles 'Supplement snapshot after copying'
    foreach ($record in $contractFiles) { Assert-PinnedSupplementFile (Join-Path $supplementSourceRoot $record.Name) $record "Supplement source after copying $($record.Name)" }
    foreach ($name in @('octave_embed.dll','octave_bridge_impl.dll')) {
        Copy-FileTracked (Join-Path $bridgeBinary $name) (Join-Path $StageRoot ('bridge\\' + $name)) 'verified-bridge' $bridgeBinary $mappings
    }
    Copy-FileTracked $bridgeModule (Join-Path $StageRoot 'bridge\\octave.pure') 'repository-bridge-module' $bridge $mappings
    foreach ($name in @('embed_probe.cc')) { Copy-FileTracked (Join-Path $probe $name) (Join-Path $StageRoot ('probes\\' + $name)) 'public-embed-probe' $probe $mappings }
    foreach ($entry in @(@('tests\\basic.pure','tests\\basic.pure'), @('cmake\\RunEmbedProbe.cmake','cmake\\RunEmbedProbe.cmake'), @('cmake\\RunPureTest.cmake','cmake\\RunPureTest.cmake'))) {
        $source = Join-Path $packageRoot $entry[0]
        Copy-FileTracked $source (Join-Path $StageRoot ('scripts\\' + $entry[1].Replace('tests\\','').Replace('cmake\\',''))) 'public-test-script' $packageRoot $mappings
    }
    # Only the stage copy is replaced; source and permanent roots were never opened for write.
    [IO.File]::Copy($patched, (Join-Path $StageRoot 'mingw64\bin\liboctave-13.dll'), $true)
    $mappings.Add(('"{0}"' -f $patched) + "`t" + ('"{0}"' -f (Join-Path $StageRoot 'mingw64\bin\liboctave-13.dll')) + "`tpatched-liboctave`t" + (Get-Sha256File $patched))
    if ((Get-Sha256File (Join-Path $StageRoot 'mingw64\bin\liboctave-13.dll')) -ne $requiredPatchedSha256) { throw 'Staged liboctave does not match the patched artifact.' }
    if ((Get-Sha256File $octaveDll) -eq $requiredPatchedSha256) { throw 'Source normalized Octave unexpectedly already contains the patched DLL.' }

    # Production uses separate Pure and Octave loader roots: their same-named
    # vendor DLLs must never be silently merged.
    $stageBin = Join-Path $StageRoot 'mingw64\bin'
    Assert-NoReparseTree $StageRoot 'Staged runtime'

    $runtimeFiles = @('mingw64\\bin\\liboctave-13.dll','mingw64\\bin\\libgcc_s_seh-1.dll')
    foreach ($relative in $runtimeFiles) { Assert-RegularFile (Join-Path $StageRoot $relative) "Staged $relative" }
    if ((Get-Sha256File (Join-Path $StageRoot 'mingw64\bin\libgcc_s_seh-1.dll')) -ne $requiredLibgccSha256) { throw 'Staged loader directory does not contain the approved libgcc.' }
    $compilerCopies = @(Get-ChildItem -LiteralPath $StageRoot -Recurse -Force -File -Filter 'libgcc_s_seh-1.dll')
    foreach ($copy in $compilerCopies) {
        if ($copy.FullName -ne (Join-Path $StageRoot 'mingw64\bin\libgcc_s_seh-1.dll') -and $copy.FullName.StartsWith($stageBin + '\', [StringComparison]::OrdinalIgnoreCase)) { throw "Unapproved libgcc duplicate is in the effective loader directory: $($copy.FullName)" }
    }

    $pureBin = Join-Path $StageRoot 'pure\bin'
    $octaveSet = @{}; foreach ($item in Get-ChildItem -LiteralPath $stageBin -File -Force) { $octaveSet[$item.Name.ToLowerInvariant()] = @($item.FullName) }
    $pureSet = @{}; foreach ($item in Get-ChildItem -LiteralPath $pureBin -File -Force) { $pureSet[$item.Name.ToLowerInvariant()] = @($item.FullName) }
    $supplementRelativeSet = @{}
    $gnuplotRoot = Join-Path $StageRoot $acceptedGnuplotRelativeRoot.Replace('/','\')
    $gnuplotSet = if ($TestMode -and -not (Test-Path -LiteralPath $gnuplotRoot -PathType Container)) { @{} } else { New-DirectLoaderSet $gnuplotRoot 'Staged Gnuplot application loader root' }
    if ($TestMode -and $InjectGnuplotCaseCollision) {
        if (-not $gnuplotSet.ContainsKey('qt6core.dll')) { throw 'Gnuplot case-collision injection requires the exact Qt6Core fixture candidate.' }
        $gnuplotSet['qt6core.dll'] += (Join-Path $gnuplotRoot 'Qt6Core.dll')
    }

    foreach ($record in $contractFiles) { $supplementRelativeSet[('pure/bin/' + $record.Name).ToLowerInvariant()] = $record.Name }
    $stagedPinnedInertPlaceholders = @(Get-PinnedInertPlaceholders $StageRoot 'Staged runtime')
    $pinnedInertByRelative = @{}
    foreach ($placeholder in $stagedPinnedInertPlaceholders) { $pinnedInertByRelative[$placeholder.Relative.ToLowerInvariant()] = $true }
    if ($TestMode -and $InjectGnuplotAuditFault) {
        switch ($InjectGnuplotAuditFault) {
            'Sibling' { [IO.Directory]::CreateDirectory((Join-Path $StageRoot 'pure\tools\other\bin')) | Out-Null; [IO.File]::WriteAllBytes((Join-Path $StageRoot 'pure\tools\other\bin\sibling-only.dll'), [Text.Encoding]::ASCII.GetBytes('MZsibling-only')) }
            'Nested' { [IO.Directory]::CreateDirectory((Join-Path $StageRoot 'pure\tools\gnuplot\bin\plugins')) | Out-Null; [IO.File]::WriteAllBytes((Join-Path $StageRoot 'pure\tools\gnuplot\bin\plugins\nested-only.dll'), [Text.Encoding]::ASCII.GetBytes('MZnested-only')) }
            'NonPe' { [IO.File]::WriteAllText((Join-Path $StageRoot 'pure\tools\gnuplot\bin\bad.dll'), 'not a PE', [Text.Encoding]::ASCII) }
            'ReparseRoot' { $realRoot = $gnuplotRoot + '-real'; [IO.Directory]::Move($gnuplotRoot, $realRoot); cmd.exe /c ('mklink /J "{0}" "{1}"' -f $gnuplotRoot, $realRoot) | Out-Null }
            'ReparseFile' { $source = Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)) 'Microsoft\WindowsApps\pwsh.exe'; New-Item -ItemType HardLink -Path (Join-Path $gnuplotRoot 'reparse-file.dll') -Target $source | Out-Null }
        }
    }
    if ($TestMode -and $InjectGnuplotAuditFault) { $gnuplotSet = New-DirectLoaderSet $gnuplotRoot 'Staged Gnuplot application loader root' }
    $peFiles = @(
        foreach ($file in Get-ChildItem -LiteralPath $StageRoot -Recurse -Force -File) {
            $relative = $file.FullName.Substring($StageRoot.Length + 1).Replace('\','/')
            if ($pinnedInertByRelative.ContainsKey($relative.ToLowerInvariant())) { continue }
            $isPe = Test-PortableExecutable $file.FullName
            if ($file.Extension -in @('.dll','.exe','.oct','.mex','.mexw64') -and -not $isPe) { throw "Staged loadable file does not contain a PE image: $($file.FullName)" }
            if ($isPe) {
                $group = Get-LoaderDomain $relative

                [pscustomobject]@{ File=$file; Relative=$relative; Group=$group }
            }
        }
    )
    [long]$gnuplotFileCount = $gnuplotSet.Count
    [long]$gnuplotPeFileCount = @($peFiles | Where-Object { $_.Group -ceq 'pure-gnuplot-app' }).Count
    $octPeFiles = @($peFiles | Where-Object { $_.Relative.EndsWith('.oct', [StringComparison]::OrdinalIgnoreCase) })
    foreach ($relative in $supplementRelativeSet.Keys) {
        $matches = @($peFiles | Where-Object { $_.Relative.Equals($relative, [StringComparison]::OrdinalIgnoreCase) })
        if ($matches.Count -ne 1 -or $matches[0].Group -cne 'pure') { throw "Pinned supplement PE is not unique in the Pure loader group: $relative" }
    }
    [long]$expectedPeCount = if ($TestMode) { $peFiles.Count } else { $supplementContract.ExpectedAuditedPeCount }
    [long]$expectedOctCount = if ($TestMode) { $octPeFiles.Count } else { $supplementContract.ExpectedAuditedOctCount }
    [long]$expectedPlaceholderCount = if ($TestMode) { $stagedPinnedInertPlaceholders.Count } else { $supplementContract.ExpectedPinnedPlaceholderCount }
    [long]$observedPeCount = $peFiles.Count
    [long]$observedOctCount = $octPeFiles.Count
    [long]$observedPlaceholderCount = $stagedPinnedInertPlaceholders.Count
    if ($TestMode) {
        switch ($InjectSupplementPostAuditFault) {
            'PeCount' { $observedPeCount++ }
            'OctCount' { $observedOctCount++ }
            'PlaceholderCount' { $observedPlaceholderCount++ }
        }
    }
    Assert-StageAuditPostconditions $observedPeCount $observedOctCount $observedPlaceholderCount $expectedPeCount $expectedOctCount $expectedPlaceholderCount

    if ($TestMode) {
        $syntheticImports = Read-SyntheticImports $SyntheticImportManifest $fixtureRoot
        if ($InjectGnuplotAuditFault -eq 'Sibling') { $syntheticImports['pure/tools/other/bin/sibling-only.dll'] = @() }
        if ($InjectGnuplotAuditFault -eq 'Nested') { $syntheticImports['pure/tools/gnuplot/bin/plugins/nested-only.dll'] = @() }

        $syntheticSystemMappings = Read-SyntheticSystemMappings $SyntheticSystemMappingManifest $fixtureRoot
        $peSet = @{}
        foreach ($pe in $peFiles) {
            $key = $pe.Relative.ToLowerInvariant(); $peSet[$key] = $true
            if (-not $syntheticImports.ContainsKey($key) -and -not $supplementRelativeSet.ContainsKey($key)) { throw "Synthetic import manifest omits staged PE file: $($pe.Relative)" }
        }
        foreach ($key in $syntheticImports.Keys) { if (-not $peSet.ContainsKey($key)) { throw "Synthetic import manifest names a non-PE or absent file: $key" } }
        $apiSetSchema = 'synthetic-system32\apisetschema.dll'
        $apiSetSchemaHash = 'synthetic-fixture'
        $osVersion = 'synthetic-fixture'
    }
    else {
        Assert-RegularFile $Objdump 'External objdump'
        Assert-NoReparsePath $Objdump 'External objdump'
        $system32 = Get-CanonicalExistingPath (Join-Path $env:WINDIR 'System32') 'Windows System32'
        $apiSetSchema = Join-Path $system32 'apisetschema.dll'
        Assert-RegularFile $apiSetSchema 'Windows API-set schema'
        Assert-NoReparsePath $apiSetSchema 'Windows API-set schema'
        $apiSetSchemaHash = Get-Sha256File $apiSetSchema
        $osVersion = [Environment]::OSVersion.VersionString
        if ($osVersion -ne $acceptedOsVersion -or $apiSetSchemaHash -ne $acceptedApiSchemaSha256) { throw 'Local OS API-set schema is not the exact approved authoritative mapping source.' }
    }

    $imports = New-Object 'Collections.Generic.List[string]'
    $apiMappings = @{}
    $resolverReady = $false
    [long]$svgLoaderRsvgEdgeCount = 0
    [long]$gnuplotImportEdgeCount = 0
    [long]$gnuplotApplicationDirectoryEdgeCount = 0
    [long]$gnuplotApiSetEdgeCount = 0
    [long]$gnuplotSystem32EdgeCount = 0
    [long]$gnuplotUnresolvedEdgeCount = 0
    foreach ($pe in $peFiles) {
        $effective = Get-EffectiveLoaderSet $pe.Group $pureSet $octaveSet $gnuplotSet
        if ($TestMode -and $supplementRelativeSet.ContainsKey($pe.Relative.ToLowerInvariant())) {
            $peImports = switch ($pe.File.Name.ToLowerInvariant()) {
                'librsvg-2-2.dll' { @('libunwind.dll','libxml2-16.dll','libpure.dll') }
                'libunwind.dll' { @('libpure.dll') }
                'libxml2-16.dll' { @('libpure.dll') }
                default { throw "Unexpected synthetic supplement PE: $($pe.Relative)" }
            }
            if ($InjectFourthSupplementDependency -and $pe.File.Name.Equals('librsvg-2-2.dll', [StringComparison]::OrdinalIgnoreCase)) { $peImports += 'libunexpected-fourth.dll' }
        }
        else { $peImports = if ($TestMode) { [string[]]$syntheticImports[$pe.Relative.ToLowerInvariant()] } else { Get-PeImports $Objdump $pe.File.FullName } }
        foreach ($dll in $peImports) {
            if ([string]::IsNullOrWhiteSpace($dll) -or $dll -match '[\\/:]') { throw "Unsafe import name in $($pe.File.FullName): $dll" }
            $key = $dll.ToLowerInvariant(); $resolved = ''
            if ($pe.Group -ceq 'pure-gnuplot-app') {
                $gnuplotImportEdgeCount++
                if ($effective.ContainsKey($key)) { $gnuplotApplicationDirectoryEdgeCount++ }
                elseif ($key.StartsWith('api-ms-win-') -or $key.StartsWith('ext-ms-win-')) { $gnuplotApiSetEdgeCount++ }
                else { $gnuplotSystem32EdgeCount++ }
            }
            if ($effective.ContainsKey($key)) {
                if ($effective[$key].Count -ne 1) { throw "Ambiguous effective staged import $dll needed by $($pe.File.FullName)" }
                $resolved = $effective[$key][0]
            }
            elseif ($key.StartsWith('api-ms-win-') -or $key.StartsWith('ext-ms-win-')) {
                if ($key -notmatch '^(api|ext)-ms-win-[a-z0-9][a-z0-9-]*-l[0-9]+-[0-9]+-[0-9]+\.dll$') { throw "API-set lookalike has invalid contract syntax: $dll" }
                if ($TestMode) {
                    if (-not $syntheticSystemMappings.ContainsKey($key)) {
                        if ($pe.Group -ceq 'pure-gnuplot-app') { $gnuplotUnresolvedEdgeCount++ }
                        throw "API-set contract has no authoritative synthetic mapping: $dll"
                    }
                    $resolved = 'synthetic-system32\' + $syntheticSystemMappings[$key]
                    $hostHash = 'synthetic-fixture'
                    if ($InjectGnuplotApiSetReleaseFailure -and $pe.Group -ceq 'pure-gnuplot-app') { throw "API-set contract mapping could not be freed: $dll (synthetic injected failure)" }
                }
                else {
                    if (-not $resolverReady) { Initialize-ApiSetResolver $StageRoot; $resolverReady = $true }
                    try {
                        $resolved = Resolve-ApiSetContract $dll $system32
                    }
                    catch {
                        $isUnresolvedApiSetEdge =
                            $_.Exception.Message.StartsWith('API-set contract has no authoritative local OS mapping:', [StringComparison]::Ordinal) -or
                            ($_.Exception.Message.StartsWith("API-set host for $dll ", [StringComparison]::Ordinal) -and (
                                $_.Exception.Message.Contains(' escapes its explicit provenance root:') -or
                                $_.Exception.Message.Contains(' is missing:')))
                        if ($pe.Group -ceq 'pure-gnuplot-app' -and $isUnresolvedApiSetEdge) { $gnuplotUnresolvedEdgeCount++ }
                        throw
                    }
                    $hostHash = Get-Sha256File $resolved
                }
                if ($apiMappings.ContainsKey($key) -and $apiMappings[$key].Path -ne $resolved) { throw "API-set contract mapped inconsistently: $dll" }
                $apiMappings[$key] = [pscustomobject]@{ Path=$resolved; Sha256=$hostHash }
            }
            else {
                if ($TestMode) {
                    if (-not $syntheticSystemMappings.ContainsKey($key)) {
                        if ($pe.Group -ceq 'pure-gnuplot-app') { $gnuplotUnresolvedEdgeCount++ }
                        throw "Missing effective import $dll needed by $($pe.File.FullName)"
                    }
                    $resolved = 'synthetic-system32\' + $syntheticSystemMappings[$key]
                }
                else {
                    $system = Join-Path $system32 $dll
                    if (-not (Test-Path -LiteralPath $system -PathType Leaf)) {
                        if ($pe.Group -ceq 'pure-gnuplot-app') { $gnuplotUnresolvedEdgeCount++ }
                        throw "Missing effective import $dll needed by $($pe.File.FullName)"
                    }
                    Assert-NoReparsePath $system "System import $dll"
                    $resolved = [IO.Path]::GetFullPath($system)
                }
            }
            if ($pe.Relative.Equals('pure/lib/gdk-pixbuf-2.0/2.10.0/loaders/pixbufloader_svg.dll', [StringComparison]::OrdinalIgnoreCase) -and $key -eq 'librsvg-2-2.dll') {
                $expectedRsvg = Join-Path $StageRoot 'pure\bin\librsvg-2-2.dll'
                if ($pe.Group -cne 'pure' -or -not $resolved.Equals($expectedRsvg, [StringComparison]::OrdinalIgnoreCase)) { throw 'The SVG loader does not resolve librsvg-2-2.dll uniquely inside the Pure loader group.' }
                $svgLoaderRsvgEdgeCount++
            }
            $imports.Add(('"{0}"' -f $pe.File.FullName) + "`t$($pe.Group)`t$dll`t" + ('"{0}"' -f $resolved))
        }
    }
    [long]$expectedGnuplotFileCount = if ($TestMode) { $gnuplotFileCount } else { $acceptedGnuplotFileCount }
    [long]$expectedGnuplotPeFileCount = if ($TestMode) { $gnuplotPeFileCount } else { $acceptedGnuplotPeFileCount }
    [long]$expectedGnuplotImportEdgeCount = if ($TestMode) { $gnuplotImportEdgeCount } else { $acceptedGnuplotImportEdgeCount }
    [long]$expectedGnuplotApplicationDirectoryEdgeCount = if ($TestMode) { $gnuplotApplicationDirectoryEdgeCount } else { $acceptedGnuplotApplicationDirectoryEdgeCount }
    [long]$expectedGnuplotApiSetEdgeCount = if ($TestMode) { $gnuplotApiSetEdgeCount } else { $acceptedGnuplotApiSetEdgeCount }
    [long]$expectedGnuplotSystem32EdgeCount = if ($TestMode) { $gnuplotSystem32EdgeCount } else { $acceptedGnuplotSystem32EdgeCount }
    [long]$expectedGnuplotUnresolvedEdgeCount = if ($TestMode) { $gnuplotUnresolvedEdgeCount } else { $acceptedGnuplotUnresolvedEdgeCount }
    [long]$observedGnuplotFileCount = $gnuplotFileCount
    [long]$observedGnuplotPeFileCount = $gnuplotPeFileCount
    [long]$observedGnuplotImportEdgeCount = $gnuplotImportEdgeCount
    [long]$observedGnuplotApplicationDirectoryEdgeCount = $gnuplotApplicationDirectoryEdgeCount
    [long]$observedGnuplotApiSetEdgeCount = $gnuplotApiSetEdgeCount
    [long]$observedGnuplotSystem32EdgeCount = $gnuplotSystem32EdgeCount
    [long]$observedGnuplotUnresolvedEdgeCount = $gnuplotUnresolvedEdgeCount
    if ($TestMode) {
        switch ($InjectGnuplotPostAuditFault) {
            'FileCount' { $observedGnuplotFileCount++ }
            'PeCount' { $observedGnuplotPeFileCount++ }
            'ImportEdgeCount' { $observedGnuplotImportEdgeCount++ }
            'ApplicationDirectoryEdgeCount' { $observedGnuplotApplicationDirectoryEdgeCount++ }
            'ApiSetEdgeCount' { $observedGnuplotApiSetEdgeCount++ }
            'System32EdgeCount' { $observedGnuplotSystem32EdgeCount++ }
            'UnresolvedEdgeCount' { $observedGnuplotUnresolvedEdgeCount++ }
        }
    }
    Assert-GnuplotLoaderPostconditions $observedGnuplotFileCount $observedGnuplotPeFileCount $observedGnuplotImportEdgeCount $observedGnuplotApplicationDirectoryEdgeCount $observedGnuplotApiSetEdgeCount $observedGnuplotSystem32EdgeCount $observedGnuplotUnresolvedEdgeCount $expectedGnuplotFileCount $expectedGnuplotPeFileCount $expectedGnuplotImportEdgeCount $expectedGnuplotApplicationDirectoryEdgeCount $expectedGnuplotApiSetEdgeCount $expectedGnuplotSystem32EdgeCount $expectedGnuplotUnresolvedEdgeCount

    $svgLoaderPeCount = @($peFiles | Where-Object { $_.Relative.Equals('pure/lib/gdk-pixbuf-2.0/2.10.0/loaders/pixbufloader_svg.dll', [StringComparison]::OrdinalIgnoreCase) }).Count
    if ((-not $TestMode -and $svgLoaderPeCount -ne 1) -or ($svgLoaderPeCount -gt 0 -and $svgLoaderRsvgEdgeCount -ne 1)) { throw 'The exact pixbufloader_svg.dll to librsvg-2-2.dll stage edge was not observed once.' }
    [IO.File]::WriteAllText((Join-Path $StageRoot 'stage-import-closure.tsv'), (($imports | Sort-Object) -join "`n") + "`n", $utf8NoBom)
    $apiLines = @($apiMappings.Keys | Sort-Object | ForEach-Object { "$_`t$($apiMappings[$_].Path)`t$($apiMappings[$_].Sha256)" })
    $apiSetText = "OSBuild`t$osVersion`nApiSetSchema`t$apiSetSchema`t$apiSetSchemaHash`n" + $(if ($apiLines.Count -eq 0) { '' } else { ($apiLines -join "`n") + "`n" })
    [IO.File]::WriteAllText((Join-Path $StageRoot 'stage-api-set-contracts.tsv'), $apiSetText, $utf8NoBom)
    $pinnedPlaceholderLines = @($stagedPinnedInertPlaceholders | Sort-Object Relative | ForEach-Object { "$($_.Relative)`t$($_.Length)`t$($_.Sha256)" })
    [IO.File]::WriteAllText((Join-Path $StageRoot 'stage-pinned-inert-placeholders.tsv'), (($pinnedPlaceholderLines -join "`n") + "`n"), $utf8NoBom)
    $excluded = @('stage-manifest.tsv','stage-mapping.tsv','stage-import-closure.tsv','stage-api-set-contracts.tsv','stage-pinned-inert-placeholders.tsv')
    $manifest = Get-TreeManifest $StageRoot $excluded
    [long]$expectedStageFileCount = if ($TestMode) { $manifest.FileCount } else { $supplementContract.ExpectedStageFileCount }
    [long]$expectedStageByteCount = if ($TestMode) { $manifest.TotalBytes } else { $supplementContract.ExpectedStageBytes }
    [string]$expectedStageManifestSha256 = if ($TestMode) { $manifest.Sha256 } else { $supplementContract.ExpectedStageManifestSha256 }
    [long]$observedStageFileCount = $manifest.FileCount
    [long]$observedStageByteCount = $manifest.TotalBytes
    [string]$observedStageManifestSha256 = $manifest.Sha256
    if ($TestMode) {
        switch ($InjectSupplementPostAuditFault) {
            'FileCount' { $observedStageFileCount++ }
            'ByteCount' { $observedStageByteCount++ }
            'ManifestSha256' { $observedStageManifestSha256 = '0000000000000000000000000000000000000000000000000000000000000000' }
        }
    }
    Assert-FinalStagePostconditions $observedStageFileCount $observedStageByteCount $observedStageManifestSha256 $expectedStageFileCount $expectedStageByteCount $expectedStageManifestSha256
    [IO.File]::WriteAllText((Join-Path $StageRoot 'stage-manifest.tsv'), $manifest.Text, $utf8NoBom)
    [IO.File]::WriteAllText((Join-Path $StageRoot 'stage-mapping.tsv'), (($mappings | Sort-Object) -join "`n") + "`n", $utf8NoBom)
    $pureAfter = Get-TreeManifest $pure
    $bridgeAfter = Get-TreeManifest $bridgeBinary
    if ($pureAfter.FileCount -ne $pureBefore.FileCount -or $pureAfter.TotalBytes -ne $pureBefore.TotalBytes -or $pureAfter.Sha256 -ne $pureBefore.Sha256) { throw 'Pure runtime source changed during staging.' }
    if ($bridgeAfter.FileCount -ne $bridgeBefore.FileCount -or $bridgeAfter.TotalBytes -ne $bridgeBefore.TotalBytes -or $bridgeAfter.Sha256 -ne $bridgeBefore.Sha256) { throw 'Bridge source changed during staging.' }
    if ((Get-Sha256File $bridgeModule) -ne $bridgeModuleBefore) { throw 'Bridge module source changed during staging.' }
    if ((Get-Sha256File $patched) -ne $patchedBefore) { throw 'Patched DLL artifact changed during staging.' }
    if ((Get-Sha256File $probeSource) -ne $requiredProbeSha256) { throw 'Public embed probe source changed during staging.' }
    Assert-ExactSupplementTree $supplementSnapshotRoot $contractFiles 'Supplement snapshot after staging'
    foreach ($record in $contractFiles) { Assert-PinnedSupplementFile (Join-Path $supplementSourceRoot $record.Name) $record "Supplement source after staging $($record.Name)" }
    foreach ($relative in $acceptedRepositoryFiles.Keys) {
        if ((Get-Sha256File (Join-Path $packageRoot $relative)) -ne $acceptedRepositoryFiles[$relative]) { throw "Required public test script $relative changed during staging." }
    }
    if (-not $TestMode) { Assert-SnapshotTree $octave $NormalizedSnapshot 'B19A1BAB6293EBAAD7D0076B43D5E8F466BA896EAADFD81EED7E0C7C8F96FB31' 59533 2797722565 'Normalized source runtime after staging'; Assert-SnapshotTree $permanent $PermanentSnapshot '95D51222C8000706D235A309EF1CAEA6D986B08F1B04A08671475AD041A18CCD' 59533 2797722287 'Permanent Octave runtime after staging' }
    [pscustomobject]@{
        StageRoot=$StageRoot
        FileCount=$manifest.FileCount
        TotalBytes=$manifest.TotalBytes
        ManifestSha256=$manifest.Sha256
        PatchedLiboctaveSha256=(Get-Sha256File (Join-Path $StageRoot 'mingw64\bin\liboctave-13.dll'))
        LibgccSha256=(Get-Sha256File (Join-Path $StageRoot 'mingw64\bin\libgcc_s_seh-1.dll'))
        ImportAuditSkipped=$false
        AuditedPeFileCount=$peFiles.Count
        AuditedOctFileCount=$octPeFiles.Count
        PinnedInertPlaceholderCount=$stagedPinnedInertPlaceholders.Count
        PinnedPureRsvgSupplementCount=$contractFiles.Count
        ApiSetContractCount=$apiMappings.Count
        GnuplotLoaderFileCount=$gnuplotFileCount
        GnuplotLoaderPeFileCount=$gnuplotPeFileCount
        GnuplotLoaderImportEdgeCount=$gnuplotImportEdgeCount
        GnuplotLoaderApplicationDirectoryEdgeCount=$gnuplotApplicationDirectoryEdgeCount
        GnuplotLoaderApiSetEdgeCount=$gnuplotApiSetEdgeCount
        GnuplotLoaderSystem32EdgeCount=$gnuplotSystem32EdgeCount
        GnuplotLoaderUnresolvedEdgeCount=$gnuplotUnresolvedEdgeCount
    } | ConvertTo-Json -Depth 3
}
catch {
    throw
}
