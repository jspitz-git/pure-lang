[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$scriptPath = Join-Path $PSScriptRoot 'stage_task3_runtime.ps1'
$testRoot = 'C:\tmp\todo51-stage-tests-' + [guid]::NewGuid().ToString('N')
$permanentRoot = Join-Path $testRoot 'permanent-octave'
$parent = Join-Path $testRoot 'parent'
$pure = Join-Path $testRoot 'pure'
$octave = Join-Path $testRoot 'normalized-octave'
$bridge = Join-Path $testRoot 'bridge'
$probe = Join-Path $testRoot 'probe'
$patched = Join-Path $testRoot 'patched\liboctave-13.dll'
$artifactEvidence = Join-Path $testRoot 'evidence\artifact.txt'
$objectEvidence = Join-Path $testRoot 'evidence\object.txt'
$buildEvidence = Join-Path $testRoot 'evidence\build.txt'
$supplementContractPath = Join-Path $PSScriptRoot 'task3-pure-rsvg-supplement-contract.psd1'
$supplementContract = Import-PowerShellDataFile -LiteralPath $supplementContractPath
$supplementSnapshot = Join-Path $testRoot 'supplement-snapshot'
$supplementSource = Join-Path $testRoot 'supplement-source'
$supplementNames = [string[]]@('librsvg-2-2.dll','libunwind.dll','libxml2-16.dll')
$syntheticSystem32 = Join-Path $testRoot 'synthetic-system32'
$syntheticApiSetSchema = Join-Path $syntheticSystem32 'apisetschema.dll'
$syntheticPlatformOsVersion = 'Microsoft Windows NT 10.0.99999.0'
$syntheticPlatformCurrentBuild = '99999'
$syntheticPlatformUbr = [int]42
$syntheticPlatformFileVersion = '10.0.99999.42 (Synthetic.000000.0000)'
$syntheticPlatformProductVersion = '10.0.99999.42'
$syntheticPlatformLength = [long]24
$syntheticPlatformSha256 = '6251FC42BCBC8353101386F8A2A1C01B96CEAE9898A0C757C0842862737E3316'

function Write-TestFile {
    param([string]$Path, [string]$Text)
    [IO.Directory]::CreateDirectory((Split-Path -Parent $Path)) | Out-Null
    [IO.File]::WriteAllText($Path, $Text, [Text.Encoding]::ASCII)
}

function Write-TestPe {
    param([string]$Path, [string]$Tag)
    Write-TestFile $Path ("MZ" + $Tag)
}

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

function Get-Sha256File([string]$Path) {
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
}

function Get-TreeManifest([string]$Root) {
    $files = @(Get-ChildItem -LiteralPath $Root -Recurse -Force -File)
    $paths = [string[]]@($files | ForEach-Object { $_.FullName.Substring($Root.Length + 1).Replace('\','/') })
    [Array]::Sort($paths, [StringComparer]::Ordinal)
    $lines = New-Object 'Collections.Generic.List[string]'
    [long]$bytes = 0
    foreach ($relative in $paths) {
        $file = Join-Path $Root $relative.Replace('/','\')
        $item = Get-Item -LiteralPath $file -Force
        $bytes += $item.Length
        $lines.Add(('{0}`t{1}`t{2}' -f $relative, $item.Length, (Get-Sha256File $file)))
    }
    $text = if ($lines.Count -eq 0) { '' } else { ($lines -join "`n") + "`n" }
    $sha = [Security.Cryptography.SHA256]::Create()
    try { $hash = ([BitConverter]::ToString($sha.ComputeHash(([Text.UTF8Encoding]::new($false)).GetBytes($text)))).Replace('-','') }
    finally { $sha.Dispose() }
    return [pscustomobject]@{ FileCount=$paths.Count; TotalBytes=$bytes; Sha256=$hash }
}

function Write-ImportFixture {
    param([string]$Path, [hashtable]$Imports)
    $lines = @($Imports.Keys | Sort-Object | ForEach-Object {
        $value = if ($Imports[$_].Count -eq 0) { '-' } else { [string]::Join(';', [string[]]$Imports[$_]) }
        "$_`t$value"
    })
    Write-TestFile $Path (($lines -join "`r`n") + "`r`n")
}

function Write-SystemFixture {
    param([string]$Path, [hashtable]$Mappings)
    $lines = @($Mappings.Keys | Sort-Object | ForEach-Object { "$_`t$($Mappings[$_])" })
    Write-TestFile $Path $(if ($lines.Count -eq 0) { '' } else { ($lines -join "`r`n") + "`r`n" })
}

function New-BaseImports {
    return @{
        'bridge/octave_bridge_impl.dll' = @()
        'bridge/octave_embed.dll' = @()
        'mingw64/bin/libgcc_s_seh-1.dll' = @()
        'mingw64/bin/liboctave-13.dll' = @()
        'mingw64/lib/octave/packages/hidden_module.oct' = @()
        'pure/bin/libgcc_s_seh-1.dll' = @()
        'pure/bin/libpure.dll' = @()
        'pure/bin/pure.exe' = @()
    }
}

function New-SupplementImports {
    $imports = New-BaseImports
    $imports['pure/lib/gdk-pixbuf-2.0/2.10.0/loaders/pixbufloader_svg.dll'] = @('librsvg-2-2.dll')
    return $imports
}

function Add-GnuplotFixture([hashtable] $Imports) {
    Write-TestPe (Join-Path $pure 'tools\gnuplot\bin\gnuplot_qt.exe') 'gnuplot-qt'
    Write-TestPe (Join-Path $pure 'tools\gnuplot\bin\Qt6Core.dll') 'qt6-core'
    Write-TestPe (Join-Path $pure 'tools\gnuplot\bin\Qt6Gui.dll') 'qt6-gui'
    $Imports['pure/tools/gnuplot/bin/gnuplot_qt.exe'] = @('Qt6Core.dll','api-ms-win-core-synch-l1-2-0.dll','kernel32.dll')
    $Imports['pure/tools/gnuplot/bin/Qt6Core.dll'] = @()
    $Imports['pure/tools/gnuplot/bin/Qt6Gui.dll'] = @()
    return Add-GnuplotPlatformPluginFixture $Imports
}
function Add-GnuplotPlatformPluginFixture([hashtable] $Imports) {
    Write-TestPe (Join-Path $pure 'tools\gnuplot\bin\platforms\qminimal.dll') 'qminimal'
    Write-TestPe (Join-Path $pure 'tools\gnuplot\bin\platforms\qwindows.dll') 'qwindows'
    $Imports['pure/tools/gnuplot/bin/platforms/qminimal.dll'] = @('Qt6Gui.dll','Qt6Core.dll','kernel32.dll')
    $Imports['pure/tools/gnuplot/bin/platforms/qwindows.dll'] = @('Qt6Gui.dll','Qt6Core.dll','user32.dll')
    return $Imports
}


function Remove-GnuplotFixture {
    $root = Join-Path $pure 'tools\gnuplot'
    if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
}

function Reset-SupplementFixture {
    foreach ($root in @($supplementSnapshot,$supplementSource)) {
        $full = [IO.Path]::GetFullPath($root)
        Assert-True ($full.StartsWith($testRoot + '\', [StringComparison]::OrdinalIgnoreCase)) "Synthetic supplement root escaped the exact test root: $full"
        if (Test-Path -LiteralPath $full) { Remove-Item -LiteralPath $full -Recurse -Force }
        [IO.Directory]::CreateDirectory($full) | Out-Null
    }
    foreach ($name in $supplementNames) {
        [IO.File]::Copy((Join-Path $supplementContract.SnapshotRoot $name), (Join-Path $supplementSnapshot $name), $false)
        [IO.File]::Copy((Join-Path 'C:\msys64\clang64\bin' $name), (Join-Path $supplementSource $name), $false)
    }
}

function Reset-PlatformIdentityFixture {
    $root = Join-Path $testRoot 'synthetic-system32'
    if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
    [IO.Directory]::CreateDirectory($root) | Out-Null
    Write-TestFile (Join-Path $root 'apisetschema.dll') 'synthetic-api-set-schema'
}

function Set-TestPeMachine {
    param([string]$Path, [uint16]$Machine)
    $bytes = [IO.File]::ReadAllBytes($Path)
    $peOffset = [BitConverter]::ToInt32($bytes, 0x3c)
    $bytes[$peOffset + 4] = [byte]($Machine -band 0xff)
    $bytes[$peOffset + 5] = [byte](($Machine -shr 8) -band 0xff)
    [IO.File]::WriteAllBytes($Path, $bytes)
}

function Invoke-Stage {
    param(
        [string]$Name,
        [hashtable]$Imports,
        [hashtable]$SystemMappings = @{},
        [string]$InjectGnuplotAuditFault = '',
        [string]$InjectGnuplotPostAuditFault = '',
        [switch]$NoTestMode,
        [switch]$InjectGnuplotCaseCollision,
        [switch]$InjectGnuplotApiSetReleaseFailure,
        [string]$InjectPlatformIdentityFault = '',
        [switch]$OmitSyntheticTools,
        [string]$DisposableParentOverride = '',
        [string]$BridgeModuleOverride = '',
        [string]$PermanentRootOverride = '',
        [string]$ExpectedPatchedOverride = '',
        [switch]$InjectSupplementDestinationCollision,
        [switch]$InjectSupplementMappingMismatch,
        [switch]$InjectFourthSupplementDependency,
        [switch]$InjectSupplementContractSchemaFault,
        [switch]$InjectSupplementPostconditionFault,
        [string]$InjectSupplementPostAuditFault = '',
        [string[]]$ExtraArguments = @()
    )
    $stage = Join-Path $parent $Name
    $importFile = Join-Path $testRoot ("fixtures\$Name-imports.tsv")
    $systemFile = Join-Path $testRoot ("fixtures\$Name-system.tsv")
    Write-ImportFixture $importFile $Imports
    Write-SystemFixture $systemFile $SystemMappings
    Reset-PlatformIdentityFixture
    if ($InjectPlatformIdentityFault -eq 'ReparseSchema') {
        Remove-Item -LiteralPath $syntheticApiSetSchema -Force
        $reparseSource = Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)) 'Microsoft\WindowsApps\pwsh.exe'
        New-Item -ItemType HardLink -Path $syntheticApiSetSchema -Target $reparseSource | Out-Null
    }
    elseif ($InjectPlatformIdentityFault -eq 'NonRegularSchema') {
        Remove-Item -LiteralPath $syntheticApiSetSchema -Force
        [IO.Directory]::CreateDirectory($syntheticApiSetSchema) | Out-Null
    }
    $pureManifest = Get-TreeManifest $pure
    $bridgeManifest = Get-TreeManifest $bridge
    $args = @(
        '-NoProfile','-ExecutionPolicy','Bypass','-File',$scriptPath,
        '-StageRoot',$stage,
        '-DisposableParent',$(if ($DisposableParentOverride) { $DisposableParentOverride } else { $parent }),
        '-PermanentOctaveRoot',$(if ($PermanentRootOverride) { $PermanentRootOverride } else { $permanentRoot }),
        '-PureRuntimeRoot',$pure,
        '-NormalizedOctaveRoot',$octave,
        '-BridgeRoot',$bridge,
        '-BridgeModuleSource',$(if ($BridgeModuleOverride) { $BridgeModuleOverride } else { Join-Path $bridge 'octave.pure' }),
        '-ProbeRoot',$probe,
        '-PatchedLiboctave',$patched,
        '-ExpectedPatchedSha256',$(if ($ExpectedPatchedOverride) { $ExpectedPatchedOverride } else { Get-Sha256File $patched }),
        '-ExpectedLibgccSha256',(Get-Sha256File (Join-Path $octave 'mingw64\bin\libgcc_s_seh-1.dll')),
        '-ExpectedPureFileCount',[string]$pureManifest.FileCount,
        '-ExpectedPureTotalBytes',[string]$pureManifest.TotalBytes,
        '-ExpectedPureManifestSha256',$pureManifest.Sha256,
        '-ExpectedBridgeFileCount',[string]$bridgeManifest.FileCount,
        '-ExpectedBridgeTotalBytes',[string]$bridgeManifest.TotalBytes,
        '-ExpectedBridgeManifestSha256',$bridgeManifest.Sha256,
        '-ExpectedBridgeModuleSha256',(Get-Sha256File (Join-Path $bridge 'octave.pure')),
        '-ExpectedProbeSha256',(Get-Sha256File (Join-Path $probe 'embed_probe.cc'))
    )
    if (-not $OmitSyntheticTools) {
        $args += @(
            '-SyntheticImportManifest',$importFile,
            '-SyntheticSystemMappingManifest',$systemFile,
            '-SyntheticArtifactEvidence',$artifactEvidence,
            '-SyntheticObjectEvidence',$objectEvidence,
            '-SyntheticBuildEvidence',$buildEvidence
        )
    }
    if (-not $NoTestMode) { $args += '-TestMode' }
    if ($InjectGnuplotCaseCollision) { $args += '-InjectGnuplotCaseCollision' }
    if ($InjectGnuplotAuditFault) { $args += @('-InjectGnuplotAuditFault',$InjectGnuplotAuditFault) }
    if ($InjectGnuplotPostAuditFault) { $args += @('-InjectGnuplotPostAuditFault',$InjectGnuplotPostAuditFault) }
    if ($InjectGnuplotApiSetReleaseFailure) { $args += '-InjectGnuplotApiSetReleaseFailure' }
    if ($InjectPlatformIdentityFault) { $args += @('-InjectPlatformIdentityFault',$InjectPlatformIdentityFault) }
    if ($InjectSupplementDestinationCollision) { $args += '-InjectSupplementDestinationCollision' }
    if ($InjectSupplementMappingMismatch) { $args += '-InjectSupplementMappingMismatch' }
    if ($InjectFourthSupplementDependency) { $args += '-InjectFourthSupplementDependency' }
    if ($InjectSupplementContractSchemaFault) { $args += '-InjectSupplementContractSchemaFault' }
    if ($InjectSupplementPostconditionFault) { $args += '-InjectSupplementPostconditionFault' }
    if ($InjectSupplementPostAuditFault) { $args += @('-InjectSupplementPostAuditFault',$InjectSupplementPostAuditFault) }
    $args += $ExtraArguments
    $savedPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = @(& powershell.exe @args 2>&1 | ForEach-Object { $_.ToString() })
        $exitCode = $LASTEXITCODE
    }
    finally { $ErrorActionPreference = $savedPreference }
    return [pscustomobject]@{ ExitCode=$exitCode; Output=($output -join "`n"); Stage=$stage }
}

function Assert-Failure {
    param($Result, [string]$Pattern, [string]$Label)
    Assert-True ($Result.ExitCode -ne 0) "$Label was accepted."
    Assert-True ($Result.Output -match $Pattern) "$Label failed for the wrong reason: $($Result.Output)"
}

try {
    $productionSource = Get-Content -LiteralPath $scriptPath -Raw
    $productionPeCount = [regex]::Match($productionSource, '(?m)^\$acceptedAuditedPeFileCount\s*=\s*(?<count>\d+)\s*$')
    $productionOctCount = [regex]::Match($productionSource, '(?m)^\$acceptedAuditedOctFileCount\s*=\s*(?<count>\d+)\s*$')
    $productionPlaceholder = [regex]::Match($productionSource, '(?s)\$approvedInertPlaceholders\s*=\s*@\(.*?Relative\s*=\s*''mingw64/qt6/bin/qhelpgenerator\.exe''.*?Length\s*=\s*\[long\]0.*?Sha256\s*=\s*''E3B0C44298FC1C149AFBF4C8996FB92427AE41E4649B934CA495991B7852B855''.*?\)')
    $productionPlaceholderCount = if ($productionPlaceholder.Success) { [regex]::Matches($productionPlaceholder.Value, 'Relative\s*=').Count } else { 0 }
    Assert-True ($productionPeCount.Success -and [long]$productionPeCount.Groups['count'].Value -eq 1536 -and $productionOctCount.Success -and [long]$productionOctCount.Groups['count'].Value -eq 219 -and $productionPlaceholderCount -eq 1) 'Production static-import contract must hard-bind 1,536 PE + 1 pinned inert placeholder + 219 .oct files.'
    Write-Output 'PASS Test-HardBindsProductionAuditCardinalityTo1536PePlusOnePlaceholderAnd219Oct'
    foreach ($assignment in @(
        "`$acceptedOsVersion = 'Microsoft Windows NT 10.0.26200.0'",
        "`$acceptedCurrentBuild = '26200'",
        "`$acceptedCurrentBuildKind = 'String'",
        '$acceptedUbr = [int]8973',
        "`$acceptedUbrKind = 'DWord'",
        "`$acceptedApiSchemaFileVersion = '10.0.26100.8972 (WinBuild.160101.0800)'",
        "`$acceptedApiSchemaProductVersion = '10.0.26100.8972'",
        '$acceptedApiSchemaLength = [long]194048',
        "`$acceptedApiSchemaSha256 = 'E485E3CF63919CD5DC5EC8624E94C3645E8BF3C4445AE937FBA045BEA3D88BB8'"
    )) {
        Assert-True ([regex]::IsMatch($productionSource, ('(?m)^' + [regex]::Escape($assignment) + '\r?$'))) "Production platform identity contract omits exact literal assignment: $assignment"
    }
    foreach ($field in @('WindowsOsVersion','WindowsCurrentBuild','WindowsUbr','ApiSetSchemaPath','ApiSetSchemaFileVersion','ApiSetSchemaProductVersion','ApiSetSchemaLength','ApiSetSchemaSha256')) {
        Assert-True ($productionSource -match ("(?m)^\s+" + [regex]::Escape($field) + '\s*=')) "Production final JSON omits platform identity field: $field"
    }
    $forbiddenPlatformParameters = @((Get-Command $scriptPath).Parameters.Keys | Where-Object { $_ -match '^(ExpectedWindows|ExpectedUbr|ExpectedCurrentBuild|ExpectedApiSet)' })
    Assert-True ($forbiddenPlatformParameters.Count -eq 0) "Production exposes caller-controlled platform identity parameters: $([string]::Join(', ', [string[]]$forbiddenPlatformParameters))"
    Write-Output 'PASS Test-HardBindsWindowsPlatformIdentityContract'
    $syntheticIdentityFlow = [regex]::Match($productionSource, '(?s)\$platformIdentity\s*=\s*\[pscustomobject\]@\{(?<Identity>.*?)\r?\n\s*\}\s*\r?\n\s*\$expectedPlatformIdentity\s*=\s*\$platformIdentity\.PSObject\.Copy\(\)\s*\r?\n\s*switch \(\$InjectPlatformIdentityFault\) \{(?<Faults>.*?)\r?\n\s*\}\s*\r?\n\s*\}\s*\r?\n\s*else')
    $literalExpectedIdentityCount = [regex]::Matches($productionSource, '\$expectedPlatformIdentity\s*=\s*\[pscustomobject\]@\{').Count
    Assert-True (
        $syntheticIdentityFlow.Success -and $literalExpectedIdentityCount -eq 1 -and
        $syntheticIdentityFlow.Groups['Faults'].Value -notmatch '\$expectedPlatformIdentity\.'
    ) 'Production TestMode must construct one synthetic platform identity, snapshot it before fault injection, and mutate only the actual object.'
    Write-Output 'PASS Test-SnapshotsSingleSyntheticPlatformIdentityBeforeFaultInjection'
    foreach ($assignment in @(
        "`$acceptedGnuplotRelativeRoot = 'pure/tools/gnuplot/bin'",
        '$acceptedGnuplotFileCount = 65',
        '$acceptedGnuplotPeFileCount = 63',
        '$acceptedGnuplotImportEdgeCount = 1002',
        '$acceptedGnuplotApplicationDirectoryEdgeCount = 249',
        '$acceptedGnuplotApiSetEdgeCount = 563',
        '$acceptedGnuplotSystem32EdgeCount = 190',
        '$acceptedGnuplotUnresolvedEdgeCount = 0'
    )) {
        Assert-True ([regex]::IsMatch($productionSource, ('(?m)^' + [regex]::Escape($assignment) + '$'))) "Production Gnuplot loader contract omits exact literal assignment: $assignment"
    }
    $gnuplotPostAuditValidateSet = [regex]::Match($productionSource, "(?m)^\s*\[ValidateSet\('FileCount','PeCount','ImportEdgeCount','ApplicationDirectoryEdgeCount','ApiSetEdgeCount','System32EdgeCount','UnresolvedEdgeCount'\)\]\[string\] \`$InjectGnuplotPostAuditFault = '',\s*$")
    Assert-True $gnuplotPostAuditValidateSet.Success 'Production Gnuplot post-audit fault switch does not expose exactly the seven approved values.'
    $gnuplotApiSetCatch = [regex]::Match($productionSource, '(?s)\$resolved = Resolve-ApiSetContract \$dll \$system32\s*}\s*catch \{(?<Body>.*?)\s*throw\s*}')
    Assert-True ($gnuplotApiSetCatch.Success -and
        $gnuplotApiSetCatch.Groups['Body'].Value -match '\$isUnresolvedApiSetEdge\s*=' -and
        $gnuplotApiSetCatch.Groups['Body'].Value -match 'no authoritative local OS mapping' -and
        $gnuplotApiSetCatch.Groups['Body'].Value -match 'escapes its explicit provenance root' -and
        $gnuplotApiSetCatch.Groups['Body'].Value -match ' is missing:' -and
        $gnuplotApiSetCatch.Groups['Body'].Value -match "(?s)if \(\`$pe\.Group -ceq 'pure-gnuplot-app' -and \`$isUnresolvedApiSetEdge\) \{ \`$gnuplotUnresolvedEdgeCount\+\+ \}" -and
        $gnuplotApiSetCatch.Groups['Body'].Value -notmatch 'mapping path could not be read|mapping could not be freed') 'Production Gnuplot API-set accounting must count only missing or cross-domain resolution failures as unresolved edges.'
    Write-Output 'PASS Test-HardBindsProductionGnuplotLoaderContract'

    [IO.Directory]::CreateDirectory($parent) | Out-Null
    [IO.Directory]::CreateDirectory($permanentRoot) | Out-Null
    Write-TestPe (Join-Path $pure 'bin\pure.exe') 'pure-exe'
    Write-TestPe (Join-Path $pure 'bin\libpure.dll') 'pure-runtime'
    Write-TestPe (Join-Path $pure 'bin\libgcc_s_seh-1.dll') 'pure-gcc'
    Write-TestFile (Join-Path $pure 'lib\pure\prelude.pure') 'prelude'
    Write-TestPe (Join-Path $octave 'mingw64\bin\liboctave-13.dll') 'original-octave'
    Write-TestPe (Join-Path $octave 'mingw64\bin\libgcc_s_seh-1.dll') 'canonical-gcc'
    [IO.Directory]::CreateDirectory((Join-Path $octave 'mingw64\qt6\bin')) | Out-Null
    [IO.File]::WriteAllBytes((Join-Path $octave 'mingw64\qt6\bin\qhelpgenerator.exe'), [byte[]]@())
    Write-TestFile (Join-Path $octave 'mingw64\share\octave\11.3.0\m\optimization\__all_opts__.m') 'opts'
    Write-TestPe (Join-Path $octave 'mingw64\lib\octave\packages\hidden_module.oct') 'hidden-oct'
    Write-TestPe (Join-Path $bridge 'octave_embed.dll') 'loader'
    Write-TestPe (Join-Path $bridge 'octave_bridge_impl.dll') 'implementation'
    Write-TestFile (Join-Path $bridge 'octave.pure') 'module'
    Write-TestFile (Join-Path $probe 'embed_probe.cc') 'probe'
    Write-TestPe $patched 'patched-octave'
    Write-TestFile $artifactEvidence 'artifact-evidence-v1'
    Write-TestFile $objectEvidence 'object-evidence-v1'
    Write-TestFile $buildEvidence 'build-evidence-v1'
    Reset-SupplementFixture
    Reset-PlatformIdentityFixture

    $platformSuccess = Invoke-Stage 'platform-identity-success' (New-BaseImports)
    Assert-True ($platformSuccess.ExitCode -eq 0) "Synthetic platform identity fixture failed: $($platformSuccess.Output)"
    $platformReport = $platformSuccess.Output | ConvertFrom-Json
    Assert-True (
        $platformReport.WindowsOsVersion -ceq $syntheticPlatformOsVersion -and
        $platformReport.WindowsCurrentBuild -ceq $syntheticPlatformCurrentBuild -and
        [int]$platformReport.WindowsUbr -eq $syntheticPlatformUbr -and
        $platformReport.ApiSetSchemaPath -ceq $syntheticApiSetSchema -and
        $platformReport.ApiSetSchemaFileVersion -ceq $syntheticPlatformFileVersion -and
        $platformReport.ApiSetSchemaProductVersion -ceq $syntheticPlatformProductVersion -and
        [long]$platformReport.ApiSetSchemaLength -eq $syntheticPlatformLength -and
        $platformReport.ApiSetSchemaSha256 -ceq $syntheticPlatformSha256
    ) "Final JSON did not report the exact synthetic platform identity: $($platformSuccess.Output)"
    Write-Output 'PASS Test-ReportsExactSyntheticWindowsPlatformIdentity'

    $platformFaultMessages = [ordered]@{
        OsVersion = 'Windows OS version does not match the expected platform identity'
        CurrentBuild = 'Windows CurrentBuild does not match the expected platform identity'
        Ubr = 'Windows UBR does not match the expected platform identity'
        MissingCurrentBuild = 'Windows CurrentBuild is missing'
        MissingUbr = 'Windows UBR is missing'
        CurrentBuildKind = 'Windows CurrentBuild registry kind does not match the expected platform identity'
        UbrKind = 'Windows UBR registry kind does not match the expected platform identity'
        FileVersion = 'Windows API-set schema file version does not match the expected platform identity'
        ProductVersion = 'Windows API-set schema product version does not match the expected platform identity'
        Length = 'Windows API-set schema length does not match the expected platform identity'
        Sha256 = 'Windows API-set schema SHA-256 does not match the expected platform identity'
        OutsideSystem32 = 'Windows API-set schema path does not match the expected platform identity'
        ReparseSchema = 'Windows API-set schema.*reparse point|reparse point.*Windows API-set schema'
        NonRegularSchema = 'Windows API-set schema is missing'
    }
    foreach ($fault in $platformFaultMessages.Keys) {
        Assert-Failure (Invoke-Stage ("platform-identity-$($fault.ToLowerInvariant())") (New-BaseImports) -InjectPlatformIdentityFault $fault) $platformFaultMessages[$fault] "Platform identity $fault fault"
    }
    Write-Output 'PASS Test-RejectsEverySyntheticWindowsPlatformIdentityFault'

    $productionPlatformInjection = Invoke-Stage 'production-platform-identity-injection' (New-BaseImports) @{} -NoTestMode -OmitSyntheticTools -InjectPlatformIdentityFault OsVersion
    Assert-Failure $productionPlatformInjection 'Platform identity fault injection is TestMode-only and has no production access' 'Production platform identity injection'
    Write-Output 'PASS Test-RejectsProductionPlatformIdentityInjection'

    $gnuplotApi = 'api-ms-win-core-synch-l1-2-0.dll'
    $gnuplotSystemMappings = @{$gnuplotApi='kernelbase.dll'; 'kernel32.dll'='kernel32.dll'; 'user32.dll'='user32.dll'}
    $gnuplotSuccess = Invoke-Stage 'gnuplot-appdir-success' (Add-GnuplotFixture (New-BaseImports)) $gnuplotSystemMappings
    Assert-True ($gnuplotSuccess.ExitCode -eq 0) "Gnuplot application-directory fixture failed: $($gnuplotSuccess.Output)"
    $closure = Get-Content -LiteralPath (Join-Path $gnuplotSuccess.Stage 'stage-import-closure.tsv') -Raw
    Assert-True ($closure -match 'gnuplot_qt\.exe"\tpure-gnuplot-app\tQt6Core\.dll\t"[^"\r\n]+\\pure\\tools\\gnuplot\\bin\\Qt6Core\.dll"') 'Gnuplot Qt6Core import did not resolve in its exact application directory.'
    Assert-True ($closure -match 'gnuplot_qt\.exe"\tpure-gnuplot-app\tapi-ms-win-core-synch-l1-2-0\.dll\t"synthetic-system32\\kernelbase\.dll"') 'Gnuplot API-set import did not resolve through its explicit synthetic mapping.'
    Assert-True ($closure -match 'gnuplot_qt\.exe"\tpure-gnuplot-app\tkernel32\.dll\t"synthetic-system32\\kernel32\.dll"') 'Gnuplot ordinary System32 import did not resolve through its explicit synthetic mapping.'
    $gnuplotReport = $gnuplotSuccess.Output | ConvertFrom-Json
    Assert-True (
        $gnuplotReport.GnuplotLoaderFileCount -eq 3 -and
        $gnuplotReport.GnuplotLoaderPeFileCount -eq 3 -and
        $gnuplotReport.GnuplotLoaderImportEdgeCount -eq 3 -and
        $gnuplotReport.GnuplotLoaderApplicationDirectoryEdgeCount -eq 1 -and
        $gnuplotReport.GnuplotLoaderApiSetEdgeCount -eq 1 -and
        $gnuplotReport.GnuplotLoaderSystem32EdgeCount -eq 1 -and
        $gnuplotReport.GnuplotLoaderUnresolvedEdgeCount -eq 0
    ) 'Gnuplot loader JSON audit did not report exact 3 / 3 / 3 / 1 / 1 / 1 / 0 fixture cardinalities.'
    Remove-GnuplotFixture
    Write-Output 'PASS Test-ReportsExactGnuplotLoaderCardinalitiesAndOrigins'

    $gnuplotPlatformSuccess = Invoke-Stage 'gnuplot-platform-plugin-success' (Add-GnuplotPlatformPluginFixture (Add-GnuplotFixture (New-BaseImports))) @{$gnuplotApi='kernelbase.dll'; 'kernel32.dll'='kernel32.dll'; 'user32.dll'='user32.dll'}
    Assert-True ($gnuplotPlatformSuccess.ExitCode -eq 0) "Gnuplot platform-plugin fixture failed: $($gnuplotPlatformSuccess.Output)"
    $gnuplotPlatformClosure = Get-Content -LiteralPath (Join-Path $gnuplotPlatformSuccess.Stage 'stage-import-closure.tsv') -Raw
    foreach ($plugin in @('qminimal.dll','qwindows.dll')) {
        foreach ($target in @('Qt6Gui.dll','Qt6Core.dll')) {
            $pluginSource = '\platforms\' + $plugin + '"' + "`tpure-gnuplot-platform-plugin`t$target`t"
            $pluginRows = @($gnuplotPlatformClosure -split "`r?`n" | Where-Object { $_.Contains($pluginSource) })
            Assert-True ($pluginRows.Count -eq 1) "Gnuplot platform plugin $plugin did not record exactly one $target closure row in its approved group."
            Assert-True ($pluginRows[0].EndsWith(('\pure\tools\gnuplot\bin\' + $target + '"'))) "Gnuplot platform plugin $plugin did not resolve $target in the direct Gnuplot bin root."
        }
    }
    Remove-GnuplotFixture
    Write-Output 'PASS Test-ResolvesApprovedGnuplotPlatformPluginsOnlyInDirectGnuplotLoaderRoot'
    $changedCanonicalGnuplotImports = Add-GnuplotFixture (New-BaseImports)
    Write-TestPe (Join-Path $pure 'tools\gnuplot\bin\canonical-inventory-mutation.dll') 'canonical-inventory-mutation'
    $changedCanonicalGnuplotImports['pure/tools/gnuplot/bin/canonical-inventory-mutation.dll'] = @()
    Assert-Failure (Invoke-Stage 'gnuplot-canonical-inventory-mutation' $changedCanonicalGnuplotImports $gnuplotSystemMappings) 'TestMode input expectations must equal the exact versioned synthetic fixture' 'Changed canonical Gnuplot fixture inventory'
    Remove-GnuplotFixture
    Write-Output 'PASS Test-RejectsChangedCanonicalGnuplotFixtureInventory'
    $thirdPlatformImports = Add-GnuplotPlatformPluginFixture (Add-GnuplotFixture (New-BaseImports))
    Assert-Failure (Invoke-Stage 'gnuplot-unapproved-platform-plugin' $thirdPlatformImports $gnuplotSystemMappings -InjectGnuplotAuditFault UnapprovedPlatformPlugin) 'Unapproved Gnuplot platform plugin PE' 'Unapproved Gnuplot platform plugin PE'
    Remove-GnuplotFixture
    Write-Output 'PASS Test-RejectsUnapprovedGnuplotPlatformPluginPe'
    $pluginDirectoryFallbackImports = Add-GnuplotPlatformPluginFixture (Add-GnuplotFixture (New-BaseImports))
    $pluginDirectoryFallbackImports['pure/tools/gnuplot/bin/platforms/qminimal.dll'] = @('qwindows.dll')
    Assert-Failure (Invoke-Stage 'gnuplot-platform-plugin-no-plugin-directory-fallback' $pluginDirectoryFallbackImports $gnuplotSystemMappings) 'Missing effective import qwindows\.dll' 'Gnuplot platform-plugin directory fallback'
    Remove-GnuplotFixture
    Write-Output 'PASS Test-RejectsGnuplotPlatformPluginDirectoryFallback'

    foreach ($dependency in @('libpure.dll','liboctave-13.dll')) {
        $pluginCrossDomainImports = Add-GnuplotPlatformPluginFixture (Add-GnuplotFixture (New-BaseImports))
        $pluginCrossDomainImports['pure/tools/gnuplot/bin/platforms/qminimal.dll'] = @($dependency)
        Assert-Failure (Invoke-Stage ('gnuplot-platform-plugin-no-' + $dependency + '-fallback') $pluginCrossDomainImports $gnuplotSystemMappings) ('Missing effective import ' + [regex]::Escape($dependency)) "Gnuplot platform-plugin $dependency fallback"
        Remove-GnuplotFixture
    }
    Write-Output 'PASS Test-RejectsGnuplotPlatformPluginCrossDomainFallbacks'

    $pluginPathOnly = Join-Path $testRoot 'platform-plugin-path-only'
    Write-TestPe (Join-Path $pluginPathOnly 'path-only.dll') 'path-only'
    $savedPluginPath = $env:PATH
    try {
        $env:PATH = $pluginPathOnly + [IO.Path]::PathSeparator + $savedPluginPath
        $pluginPathImports = Add-GnuplotPlatformPluginFixture (Add-GnuplotFixture (New-BaseImports))
        $pluginPathImports['pure/tools/gnuplot/bin/platforms/qminimal.dll'] = @('path-only.dll')
        Assert-Failure (Invoke-Stage 'gnuplot-platform-plugin-no-path-fallback' $pluginPathImports $gnuplotSystemMappings) 'Missing effective import path-only\.dll' 'Gnuplot platform-plugin PATH fallback'
    }
    finally { $env:PATH = $savedPluginPath; Remove-GnuplotFixture }
    Write-Output 'PASS Test-RejectsGnuplotPlatformPluginPathFallback'
    $nonPePluginImports = Add-GnuplotPlatformPluginFixture (Add-GnuplotFixture (New-BaseImports))
    Assert-Failure (Invoke-Stage 'gnuplot-platform-plugin-non-pe' $nonPePluginImports -InjectGnuplotAuditFault NonPePlatformPlugin) 'Staged loadable file does not contain a PE image' 'Non-PE approved Gnuplot platform plugin'
    Remove-GnuplotFixture
    Write-Output 'PASS Test-RejectsNonPeApprovedGnuplotPlatformPlugin'

    $reparsePlatformsImports = Add-GnuplotPlatformPluginFixture (Add-GnuplotFixture (New-BaseImports))
    Assert-Failure (Invoke-Stage 'gnuplot-platform-plugin-reparse-platforms' $reparsePlatformsImports -InjectGnuplotAuditFault ReparsePlatformDirectory) 'reparse point' 'Gnuplot platform-plugin directory reparse point'
    Remove-GnuplotFixture
    Write-Output 'PASS Test-RejectsGnuplotPlatformPluginDirectoryReparsePoint'

    $reparsePluginImports = Add-GnuplotPlatformPluginFixture (Add-GnuplotFixture (New-BaseImports))
    Assert-Failure (Invoke-Stage 'gnuplot-platform-plugin-reparse-file' $reparsePluginImports -InjectGnuplotAuditFault ReparsePlatformFile) 'reparse point' 'Approved Gnuplot platform-plugin file reparse point'
    Remove-GnuplotFixture
    Write-Output 'PASS Test-RejectsApprovedGnuplotPlatformPluginReparsePoint'

    $gnuplotPostAuditFailures = [ordered]@{
        FileCount = 'Gnuplot loader file count does not match the expected postcondition'
        PeCount = 'Gnuplot loader PE file count does not match the expected postcondition'
        ImportEdgeCount = 'Gnuplot loader import edge count does not match the expected postcondition'
        ApplicationDirectoryEdgeCount = 'Gnuplot loader application-directory edge count does not match the expected postcondition'
        ApiSetEdgeCount = 'Gnuplot loader API-set edge count does not match the expected postcondition'
        System32EdgeCount = 'Gnuplot loader System32 edge count does not match the expected postcondition'
        UnresolvedEdgeCount = 'Gnuplot loader unresolved edge count does not match the expected postcondition'
    }
    foreach ($fault in $gnuplotPostAuditFailures.Keys) {
        $faultImports = Add-GnuplotFixture (New-BaseImports)
        Assert-Failure (Invoke-Stage ("gnuplot-post-audit-$fault") $faultImports $gnuplotSystemMappings -InjectGnuplotPostAuditFault $fault) $gnuplotPostAuditFailures[$fault] "Gnuplot $fault postcondition fault"
        Remove-GnuplotFixture
    }
    Write-Output 'PASS Test-RejectsEveryGnuplotPostAuditCardinalityFault'

    $unknownGnuplotApiImports = Add-GnuplotFixture (New-BaseImports)
    $unknownGnuplotApiImports['pure/tools/gnuplot/bin/gnuplot_qt.exe'] = @('api-ms-win-core-unapproved-l1-1-0.dll')
    Assert-Failure (Invoke-Stage 'gnuplot-unknown-api-set' $unknownGnuplotApiImports @{}) 'API-set contract.*authoritative.*mapping|authoritative.*API-set' 'Unknown Gnuplot API-set mapping'
    Remove-GnuplotFixture
    Write-Output 'PASS Test-RejectsUnknownGnuplotApiSetMapping'

    $missingGnuplotSystemImports = Add-GnuplotFixture (New-BaseImports)
    $missingGnuplotSystemImports['pure/tools/gnuplot/bin/gnuplot_qt.exe'] = @('Qt6Core.dll','kernel32.dll')
    Assert-Failure (Invoke-Stage 'gnuplot-missing-system32' $missingGnuplotSystemImports @{}) 'Missing effective import kernel32\.dll' 'Missing Gnuplot System32 mapping'
    Remove-GnuplotFixture
    Write-Output 'PASS Test-RejectsMissingGnuplotSystem32Mapping'

    $gnuplotReleaseImports = Add-GnuplotFixture (New-BaseImports)
    Assert-Failure (Invoke-Stage 'gnuplot-api-set-release-failure' $gnuplotReleaseImports $gnuplotSystemMappings -InjectGnuplotApiSetReleaseFailure) 'API-set contract mapping could not be freed' 'Gnuplot API-set release failure'
    Remove-GnuplotFixture
    Write-Output 'PASS Test-RejectsGnuplotApiSetReleaseFailure'

    $onlyPure = Add-GnuplotFixture (New-BaseImports)
    $onlyPure['pure/tools/gnuplot/bin/gnuplot_qt.exe'] = @('libpure.dll')
    Assert-Failure (Invoke-Stage 'gnuplot-no-pure-fallback' $onlyPure) 'Missing effective import libpure\.dll' 'Gnuplot Pure fallback'
    Remove-GnuplotFixture
    Write-Output 'PASS Test-RejectsGnuplotPureFallback'

    $onlyOctave = Add-GnuplotFixture (New-BaseImports)
    $onlyOctave['pure/tools/gnuplot/bin/gnuplot_qt.exe'] = @('liboctave-13.dll')
    Assert-Failure (Invoke-Stage 'gnuplot-no-octave-fallback' $onlyOctave) 'Missing effective import liboctave-13\.dll' 'Gnuplot Octave fallback'
    Remove-GnuplotFixture
    Write-Output 'PASS Test-RejectsGnuplotOctaveFallback'

    $pathOnly = Join-Path $testRoot 'path-only'
    Write-TestPe (Join-Path $pathOnly 'path-only.dll') 'path-only'
    $savedPath = $env:PATH
    try {
        $env:PATH = $pathOnly + [IO.Path]::PathSeparator + $savedPath
        $pathImports = Add-GnuplotFixture (New-BaseImports)
        $pathImports['pure/tools/gnuplot/bin/gnuplot_qt.exe'] = @('path-only.dll')
        Assert-Failure (Invoke-Stage 'gnuplot-no-path-fallback' $pathImports) 'Missing effective import path-only\.dll' 'Gnuplot PATH fallback'
    }
    finally { $env:PATH = $savedPath; Remove-GnuplotFixture }
    Write-Output 'PASS Test-RejectsGnuplotPathFallback'

    $caseCollisionImports = Add-GnuplotFixture (New-BaseImports)
    Assert-Failure (Invoke-Stage 'gnuplot-case-collision' $caseCollisionImports -InjectGnuplotCaseCollision) 'Ambiguous effective staged import Qt6Core\.dll|ambiguous case-insensitive filename' 'Gnuplot case collision'
    Remove-GnuplotFixture
    Write-Output 'PASS Test-RejectsGnuplotCaseCollision'

    $productionGnuplotInjection = Invoke-Stage 'production-gnuplot-injection' (New-BaseImports) @{} -NoTestMode -OmitSyntheticTools -InjectGnuplotCaseCollision
    $productionGnuplotPostAuditInjection = Invoke-Stage 'production-gnuplot-post-audit-injection' (New-BaseImports) @{} -InjectGnuplotPostAuditFault FileCount -NoTestMode -OmitSyntheticTools
    $productionGnuplotReleaseInjection = Invoke-Stage 'production-gnuplot-release-injection' (New-BaseImports) @{} -InjectGnuplotApiSetReleaseFailure -NoTestMode -OmitSyntheticTools
    $siblingImports = Add-GnuplotFixture (New-BaseImports)
    $siblingImports['pure/tools/gnuplot/bin/gnuplot_qt.exe'] = @('sibling-only.dll')
    Assert-Failure (Invoke-Stage 'gnuplot-no-sibling-fallback' $siblingImports -InjectGnuplotAuditFault Sibling) 'Missing effective import sibling-only\.dll' 'Gnuplot sibling fallback'
    Remove-GnuplotFixture
    Write-Output 'PASS Test-RejectsGnuplotSiblingFallback'

    $nestedImports = Add-GnuplotFixture (New-BaseImports)
    $nestedImports['pure/tools/gnuplot/bin/gnuplot_qt.exe'] = @('nested-only.dll')
    Assert-Failure (Invoke-Stage 'gnuplot-no-nested-fallback' $nestedImports -InjectGnuplotAuditFault Nested) 'Missing effective import nested-only\.dll' 'Gnuplot nested fallback'
    Remove-GnuplotFixture
    Write-Output 'PASS Test-RejectsGnuplotNestedFallback'

    $nonPeImports = Add-GnuplotFixture (New-BaseImports)
    Assert-Failure (Invoke-Stage 'gnuplot-non-pe' $nonPeImports -InjectGnuplotAuditFault NonPe) 'Staged loadable file does not contain a PE image' 'Gnuplot non-PE file'
    Remove-GnuplotFixture
    Write-Output 'PASS Test-RejectsGnuplotNonPeFile'

    $reparseRootImports = Add-GnuplotFixture (New-BaseImports)
    Assert-Failure (Invoke-Stage 'gnuplot-reparse-root' $reparseRootImports -InjectGnuplotAuditFault ReparseRoot) 'Staged Gnuplot application loader root.*reparse point|reparse point.*Staged Gnuplot application loader root' 'Gnuplot loader root reparse point'
    Remove-GnuplotFixture
    Write-Output 'PASS Test-RejectsGnuplotLoaderRootReparsePoint'

    $reparseFileImports = Add-GnuplotFixture (New-BaseImports)
    Assert-Failure (Invoke-Stage 'gnuplot-reparse-file' $reparseFileImports -InjectGnuplotAuditFault ReparseFile) 'Staged Gnuplot application loader root file.*reparse point|reparse point.*Staged Gnuplot application loader root file' 'Gnuplot loader file reparse point'
    Remove-GnuplotFixture
    Write-Output 'PASS Test-RejectsGnuplotLoaderFileReparsePoint'

    Assert-Failure $productionGnuplotInjection 'Gnuplot case-collision injection is TestMode-only' 'Production Gnuplot case-collision injection'
    Assert-Failure $productionGnuplotPostAuditInjection 'Gnuplot post-audit fault injection is TestMode-only' 'Production Gnuplot post-audit fault injection'
    Assert-Failure $productionGnuplotReleaseInjection 'Gnuplot API-set release injection is TestMode-only' 'Production Gnuplot API-set release injection'
    Write-Output 'PASS Test-RejectsProductionGnuplotTestInjections'


    $success = Invoke-Stage 'success' (New-BaseImports)
    Assert-True ($success.ExitCode -eq 0) "Success fixture failed: $($success.Output)"
    Assert-True (Test-Path -LiteralPath (Join-Path $success.Stage 'pure\bin\pure.exe') -PathType Leaf) 'Stage omitted the separate Pure loader tree.'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $success.Stage 'mingw64\bin\pure.exe'))) 'Pure executable was unsafely merged into the Octave loader root.'
    Assert-True ((Get-Sha256File (Join-Path $success.Stage 'mingw64\bin\liboctave-13.dll')) -eq (Get-Sha256File $patched)) 'Stage retained original liboctave.'
    Assert-True ((Get-Sha256File (Join-Path $octave 'mingw64\bin\liboctave-13.dll')) -ne (Get-Sha256File $patched)) 'Assembler modified its source Octave tree.'
    Assert-True (Test-Path -LiteralPath (Join-Path $success.Stage 'stage-import-closure.tsv') -PathType Leaf) 'Stage omitted its static import closure.'
    $successReport = $success.Output | ConvertFrom-Json
    Assert-True ($successReport.AuditedPeFileCount -eq 11 -and $successReport.AuditedOctFileCount -eq 1 -and $successReport.PinnedPureRsvgSupplementCount -eq 3) 'Every synthetic PE, including the pinned supplement and .oct module, was not audited.'
    Assert-True ($successReport.PinnedInertPlaceholderCount -eq 1) 'The exact inert placeholder was not recorded separately.'
    $placeholderRecord = Get-Content -LiteralPath (Join-Path $success.Stage 'stage-pinned-inert-placeholders.tsv') -Raw
    Assert-True ($placeholderRecord -eq "mingw64/qt6/bin/qhelpgenerator.exe`t0`tE3B0C44298FC1C149AFBF4C8996FB92427AE41E4649B934CA495991B7852B855`n") 'The staged inert-placeholder report is not the exact pinned record.'
    Write-Output 'PASS Test-AcceptsAndRecordsPinnedInertQtDocumentationPlaceholder'

    $productionPlaceholderOverride = Invoke-Stage 'production-placeholder-override' (New-BaseImports) @{} -NoTestMode -OmitSyntheticTools -ExtraArguments @('-ExpectedPinnedInertPlaceholderSha256','0000000000000000000000000000000000000000000000000000000000000000')
    Assert-Failure $productionPlaceholderOverride 'parameter cannot be found' 'Caller-controlled pinned placeholder approval'
    Write-Output 'PASS Test-RejectsCallerControlledPinnedPlaceholderApproval'

    $placeholder = Join-Path $octave 'mingw64\qt6\bin\qhelpgenerator.exe'
    [IO.File]::WriteAllBytes($placeholder, [byte[]](0x51))
    $nonzeroPlaceholder = Invoke-Stage 'nonzero-placeholder' (New-BaseImports)
    Assert-Failure $nonzeroPlaceholder 'Pinned inert placeholder.*length.*SHA-256|Pinned inert placeholder.*SHA-256.*length' 'Nonzero or wrong-hash pinned placeholder'
    [IO.File]::WriteAllBytes($placeholder, [byte[]]@())
    Write-Output 'PASS Test-RejectsNonzeroOrWrongHashPinnedPlaceholder'

    foreach ($extension in @('.exe','.dll','.oct')) {
        $unapproved = Join-Path $octave ('mingw64\qt6\bin\unapproved-placeholder' + $extension)
        [IO.File]::WriteAllBytes($unapproved, [byte[]]@())
        $unapprovedResult = Invoke-Stage ('unapproved-' + $extension.Substring(1)) (New-BaseImports)
        Assert-Failure $unapprovedResult 'Staged loadable file does not contain a PE image' "Unapproved non-PE $extension"
        Remove-Item -LiteralPath $unapproved -Force
    }
    $sameNameElsewhere = Join-Path $octave 'mingw64\bin\qhelpgenerator.exe'
    [IO.File]::WriteAllBytes($sameNameElsewhere, [byte[]]@())
    $sameNameResult = Invoke-Stage 'same-name-elsewhere' (New-BaseImports)
    Assert-Failure $sameNameResult 'Staged loadable file does not contain a PE image' 'Same filename outside the pinned path'
    Remove-Item -LiteralPath $sameNameElsewhere -Force
    Write-Output 'PASS Test-RejectsAllOtherNonPeLoadableExtensionsAndSameNameElsewhere'

    $outsideGuard = Invoke-Stage 'guard-reject' (New-BaseImports) @{} -DisposableParentOverride $testRoot
    Assert-Failure $outsideGuard 'exact synthetic fixture' 'Unsafe TestMode fixture root'
    Write-Output 'PASS Test-RejectsUnsafeTestModeFixture'

    $legacyOverride = Invoke-Stage 'legacy-override' (New-BaseImports) @{} -ExtraArguments @('-SeparateLoaderRoots')
    Assert-Failure $legacyOverride 'parameter name.*Sepa\s*rateLoaderRoots|Sepa\s*rateLoaderRoots.*parameter' 'Legacy loader-root override'
    Write-Output 'PASS Test-RejectsUnsafeLoaderOverride'

    $productionOverride = Invoke-Stage 'production-override' (New-BaseImports) @{} -NoTestMode -OmitSyntheticTools
    Assert-Failure $productionOverride 'Non-test staging rejects caller-controlled evidence or inventory overrides' 'Caller-controlled production evidence'
    Write-Output 'PASS Test-RejectsCallerControlledProductionEvidence'

    $savedArtifact = [IO.File]::ReadAllBytes($artifactEvidence)
    Write-TestFile $artifactEvidence 'artifact-evidence-v2'
    $evidenceFailure = Invoke-Stage 'evidence-reject' (New-BaseImports)
    Assert-Failure $evidenceFailure 'artifact evidence.*approved|approved.*artifact evidence' 'Changed exact evidence'
    [IO.File]::WriteAllBytes($artifactEvidence, $savedArtifact)
    Write-Output 'PASS Test-BindsExactProductionEvidencePath'

    Write-TestFile (Join-Path $pure 'lib\pure\prelude.pure') 'PRELUDE'
    $inventoryFailure = Invoke-Stage 'inventory-reject' (New-BaseImports)
    Assert-Failure $inventoryFailure 'exact versioned synthetic fixture|exact approved inventory' 'Changed exact Pure inventory'
    Write-TestFile (Join-Path $pure 'lib\pure\prelude.pure') 'prelude'
    Write-Output 'PASS Test-BindsExactInputInventory'

    $missingImports = New-BaseImports
    $missingImports['pure/bin/pure.exe'] = @('missing-runtime.dll')
    $missing = Invoke-Stage 'missing-import' $missingImports
    Assert-Failure $missing 'Missing effective import missing-runtime.dll' 'Missing ordinary import'
    Write-Output 'PASS Test-RejectsMissingImport'

    $ambiguousImports = New-BaseImports
    $ambiguousImports['bridge/octave_embed.dll'] = @('libgcc_s_seh-1.dll')
    $ambiguous = Invoke-Stage 'ambiguous-import' $ambiguousImports
    Assert-Failure $ambiguous 'Ambiguous effective staged import libgcc_s_seh-1.dll' 'Bridge union collision'
    Write-Output 'PASS Test-RejectsBridgeUnionCollision'

    $mappedApi = 'api-ms-win-core-synch-l1-2-0.dll'
    $mappedImports = New-BaseImports
    $mappedImports['bridge/octave_embed.dll'] = @($mappedApi)
    $mapped = Invoke-Stage 'mapped-api-set' $mappedImports @{$mappedApi='kernelbase.dll'}
    Assert-True ($mapped.ExitCode -eq 0) "Authoritative API-set fixture failed: $($mapped.Output)"
    Assert-True ((Get-Content -LiteralPath (Join-Path $mapped.Stage 'stage-api-set-contracts.tsv') -Raw) -match 'api-ms-win-core-synch-l1-2-0\.dll\tkernelbase\.dll|api-ms-win-core-synch-l1-2-0\.dll\tsynthetic-system32\\kernelbase\.dll') 'API-set audit omitted the exact authoritative host mapping.'
    Write-Output 'PASS Test-RecordsAuthoritativeApiSetMapping'

    $apiImports = New-BaseImports
    $apiImports['bridge/octave_embed.dll'] = @('api-ms-win-core-unapproved-l1-1-0.dll')
    $unknownApi = Invoke-Stage 'unknown-api-set' $apiImports @{}
    Assert-Failure $unknownApi 'API-set contract.*authoritative.*mapping|authoritative.*API-set' 'Unknown API-set lookalike'
    Write-Output 'PASS Test-RejectsUnknownApiSetLookalike'

    $moduleImports = New-BaseImports
    $moduleImports['mingw64/lib/octave/packages/hidden_module.oct'] = @('missing-module-runtime.dll')
    $moduleFailure = Invoke-Stage 'full-tree-module' $moduleImports
    Assert-Failure $moduleFailure 'Missing effective import missing-module-runtime.dll' 'Full-tree PE module coverage'
    Write-Output 'PASS Test-AuditsLoadablePeOutsideBin'

    $outsideModule = Join-Path $testRoot 'outside-module.pure'
    Write-TestFile $outsideModule 'module'
    $boundary = Invoke-Stage 'bridge-boundary' (New-BaseImports) @{} -BridgeModuleOverride $outsideModule
    Assert-Failure $boundary 'Bridge module source is not a strict child' 'Bridge module provenance boundary'
    Write-Output 'PASS Test-RejectsBridgeModuleOutsideBridgeRoot'

    $originalHash = Get-Sha256File $patched
    $originalTime = (Get-Item -LiteralPath $patched).LastWriteTimeUtc
    Write-TestPe $patched 'broken--octave'
    [IO.File]::SetLastWriteTimeUtc($patched, $originalTime)
    $content = Invoke-Stage 'content-hash' (New-BaseImports) @{} -ExpectedPatchedOverride $originalHash
    Assert-Failure $content 'Patched liboctave SHA-256' 'Same-length same-mtime content change'
    Write-TestPe $patched 'patched-octave'
    Write-Output 'PASS Test-RejectsSameLengthSameMtimeContentChange'

    $existing = Invoke-Stage 'existing-stage' (New-BaseImports)
    Assert-True ($existing.ExitCode -eq 0) "Existing-stage setup failed: $($existing.Output)"
    $existingAgain = Invoke-Stage 'existing-stage' (New-BaseImports)
    Assert-Failure $existingAgain 'Stage root must be absent' 'Existing stage root'
    Write-Output 'PASS Test-RejectsExistingStage'

    $permanentAlias = Invoke-Stage 'permanent-alias' (New-BaseImports) @{} -PermanentRootOverride $octave
    Assert-Failure $permanentAlias 'resolves to the permanent Octave root' 'Permanent root input'
    Write-Output 'PASS Test-RejectsPermanentOctaveRoot'

    Write-TestPe (Join-Path $octave 'pure\lib\gdk-pixbuf-2.0\2.10.0\loaders\pixbufloader_svg.dll') 'svg-loader'
    $supplementSuccess = Invoke-Stage 'supplement-success' (New-SupplementImports)
    Assert-True ($supplementSuccess.ExitCode -eq 0) "Pinned supplement fixture failed: $($supplementSuccess.Output)"
    foreach ($record in $supplementContract.Files) {
        $staged = Join-Path $supplementSuccess.Stage ('pure\bin\' + $record.Name)
        Assert-True (Test-Path -LiteralPath $staged -PathType Leaf) "Stage omitted pinned supplement file $($record.Name)."
        Assert-True ((Get-Item -LiteralPath $staged).Length -eq [long]$record.Length -and (Get-Sha256File $staged) -eq $record.Sha256) "Staged supplement identity changed for $($record.Name)."
    }
    $supplementClosure = Get-Content -LiteralPath (Join-Path $supplementSuccess.Stage 'stage-import-closure.tsv') -Raw
    Assert-True ($supplementClosure -match 'pixbufloader_svg\.dll"\tpure\tlibrsvg-2-2\.dll\t"[^"\r\n]+\\pure\\bin\\librsvg-2-2\.dll"') 'SVG loader did not resolve uniquely to stage/pure/bin/librsvg-2-2.dll.'
    foreach ($name in $supplementNames) { Assert-True ($supplementClosure -match ([regex]::Escape("pure\bin\$name") + '"\tpure\t')) "Supplement closure member left the Pure loader group: $name" }
    Write-Output 'PASS Test-AcceptsExactPinnedPureRsvgSupplement'

    Reset-SupplementFixture
    Remove-Item -LiteralPath (Join-Path $supplementSnapshot 'libunwind.dll') -Force
    $missingSupplement = Invoke-Stage 'supplement-missing' (New-SupplementImports)
    Assert-Failure $missingSupplement 'Supplement snapshot.*exactly three|missing.*libunwind|inventory' 'Missing supplement file'
    Reset-SupplementFixture
    Write-TestFile (Join-Path $supplementSnapshot 'extra.dll') 'MZextra'
    $extraSupplement = Invoke-Stage 'supplement-extra' (New-SupplementImports)
    Assert-Failure $extraSupplement 'Supplement snapshot.*exactly three|unlisted.*snapshot|inventory' 'Extra supplement file'
    Write-Output 'PASS Test-RejectsMissingOrExtraSupplementFile'

    Reset-SupplementFixture
    $hashPath = Join-Path $supplementSnapshot 'libunwind.dll'
    $hashBytes = [IO.File]::ReadAllBytes($hashPath); $hashBytes[$hashBytes.Length - 1] = $hashBytes[$hashBytes.Length - 1] -bxor 0x01; [IO.File]::WriteAllBytes($hashPath, $hashBytes)
    $changedHash = Invoke-Stage 'supplement-hash' (New-SupplementImports)
    Assert-Failure $changedHash 'Supplement snapshot.*SHA-256|hash' 'Changed supplement hash'
    Reset-SupplementFixture
    Set-TestPeMachine (Join-Path $supplementSnapshot 'libxml2-16.dll') 0x014c
    $changedMachine = Invoke-Stage 'supplement-machine' (New-SupplementImports)
    Assert-Failure $changedMachine 'Supplement snapshot.*machine|PE machine' 'Changed supplement machine'
    Write-Output 'PASS Test-RejectsChangedSupplementHashOrMachine'

    Reset-SupplementFixture
    $snapshotReal = $supplementSnapshot + '-real'
    [IO.Directory]::Move($supplementSnapshot, $snapshotReal)
    cmd.exe /c "mklink /J `"$supplementSnapshot`" `"$snapshotReal`"" | Out-Null
    Assert-True (Test-Path -LiteralPath $supplementSnapshot) 'Could not create the synthetic supplement reparse fixture.'
    $reparseSupplement = Invoke-Stage 'supplement-reparse' (New-SupplementImports)
    Assert-Failure $reparseSupplement 'Supplement snapshot.*reparse point|reparse point.*Supplement snapshot' 'Reparse supplement snapshot'
    [IO.Directory]::Delete($supplementSnapshot)
    Remove-Item -LiteralPath $snapshotReal -Recurse -Force
    Reset-SupplementFixture
    $sourcePath = Join-Path $supplementSource 'librsvg-2-2.dll'
    $sourceBytes = [IO.File]::ReadAllBytes($sourcePath); $sourceBytes[$sourceBytes.Length - 1] = $sourceBytes[$sourceBytes.Length - 1] -bxor 0x01; [IO.File]::WriteAllBytes($sourcePath, $sourceBytes)
    $sourceSubstitution = Invoke-Stage 'supplement-source-substitution' (New-SupplementImports)
    Assert-Failure $sourceSubstitution 'Supplement source.*SHA-256|source.*hash' 'Supplement source substitution'
    Write-Output 'PASS Test-RejectsSupplementReparseAndSourceSubstitution'

    Reset-SupplementFixture
    $collision = Invoke-Stage 'supplement-collision' (New-SupplementImports) @{} -InjectSupplementDestinationCollision
    Assert-Failure $collision 'pinned-pure-rsvg-supplement' 'Supplement destination collision'
    Reset-SupplementFixture
    $mappingMismatch = Invoke-Stage 'supplement-mapping' (New-SupplementImports) @{} -InjectSupplementMappingMismatch
    Assert-Failure $mappingMismatch 'tracked-copy mapping mismatch' 'Supplement tracked-copy mapping mismatch'
    Write-Output 'PASS Test-RejectsSupplementDestinationCollision'

    Reset-SupplementFixture
    $fourthDependency = Invoke-Stage 'supplement-fourth-dependency' (New-SupplementImports) @{} -InjectFourthSupplementDependency
    Assert-Failure $fourthDependency 'Missing effective import libunexpected-fourth\.dll' 'Fourth transitive supplement dependency'
    Write-Output 'PASS Test-RejectsFourthTransitiveDependency'

    Reset-SupplementFixture
    $schemaFault = Invoke-Stage 'supplement-schema' (New-SupplementImports) @{} -InjectSupplementContractSchemaFault
    Assert-Failure $schemaFault 'exactly the declared schema keys' 'Changed supplement contract schema'
    Reset-SupplementFixture
    $postconditionFault = Invoke-Stage 'supplement-postcondition' (New-SupplementImports) @{} -InjectSupplementPostconditionFault
    Assert-Failure $postconditionFault 'Supplement contract.*fixed.*postcondition|fixed arithmetic' 'Changed supplement postcondition'
    $postAuditAssertionFailures = New-Object 'Collections.Generic.List[string]'
    foreach ($fault in @(
        @('PeCount','Staged PE audit count does not match the expected postcondition'),
        @('OctCount','Staged \.oct audit count does not match the expected postcondition'),
        @('PlaceholderCount','Pinned inert placeholder audit count does not match the expected postcondition'),
        @('FileCount','Final stage file count does not match the expected postcondition'),
        @('ByteCount','Final stage byte count does not match the expected postcondition'),
        @('ManifestSha256','Final stage manifest SHA-256 does not match the expected postcondition'))) {
        Reset-SupplementFixture
        $postAuditFault = Invoke-Stage ('supplement-post-audit-' + $fault[0].ToLowerInvariant()) (New-SupplementImports) @{} -InjectSupplementPostAuditFault $fault[0]
        try { Assert-Failure $postAuditFault $fault[1] "Post-audit $($fault[0]) fault" }
        catch { $postAuditAssertionFailures.Add($_.Exception.Message) }
    }
    Assert-True ($postAuditAssertionFailures.Count -eq 0) ([string]::Join("`n", $postAuditAssertionFailures))
    $supplementOverride = Invoke-Stage 'supplement-override' (New-SupplementImports) @{} -ExtraArguments @('-SupplementRoot',$supplementSnapshot)
    Assert-Failure $supplementOverride 'parameter cannot be found' 'Caller supplement path override'
    Write-Output 'PASS Test-HardBindsSupplementStagePostconditions'

    $link = Join-Path $testRoot 'linked-parent'
    cmd.exe /c "mklink /J `"$link`" `"$parent`"" | Out-Null
    if (Test-Path -LiteralPath $link) {
        $reparse = Invoke-Stage 'reparse-stage' (New-BaseImports) @{} -DisposableParentOverride $link
        Assert-Failure $reparse 'reparse point|exact synthetic fixture|not a strict child' 'Reparse disposable parent'
        Write-Output 'PASS Test-RejectsReparseParent'
    }

    Write-Output 'PASS all task3 staging tests'
}
finally {
    $resolved = [IO.Path]::GetFullPath($testRoot).TrimEnd('\')
    if ($resolved -match '^C:\\tmp\\todo51-stage-tests-[0-9a-f]{32}$' -and (Test-Path -LiteralPath $resolved)) {
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
}
