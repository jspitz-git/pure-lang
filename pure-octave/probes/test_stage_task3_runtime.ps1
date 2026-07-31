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

function Invoke-Stage {
    param(
        [string]$Name,
        [hashtable]$Imports,
        [hashtable]$SystemMappings = @{},
        [switch]$NoTestMode,
        [switch]$OmitSyntheticTools,
        [string]$DisposableParentOverride = '',
        [string]$BridgeModuleOverride = '',
        [string]$PermanentRootOverride = '',
        [string]$ExpectedPatchedOverride = '',
        [string[]]$ExtraArguments = @()
    )
    $stage = Join-Path $parent $Name
    $importFile = Join-Path $testRoot ("fixtures\$Name-imports.tsv")
    $systemFile = Join-Path $testRoot ("fixtures\$Name-system.tsv")
    Write-ImportFixture $importFile $Imports
    Write-SystemFixture $systemFile $SystemMappings
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

    $success = Invoke-Stage 'success' (New-BaseImports)
    Assert-True ($success.ExitCode -eq 0) "Success fixture failed: $($success.Output)"
    Assert-True (Test-Path -LiteralPath (Join-Path $success.Stage 'pure\bin\pure.exe') -PathType Leaf) 'Stage omitted the separate Pure loader tree.'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $success.Stage 'mingw64\bin\pure.exe'))) 'Pure executable was unsafely merged into the Octave loader root.'
    Assert-True ((Get-Sha256File (Join-Path $success.Stage 'mingw64\bin\liboctave-13.dll')) -eq (Get-Sha256File $patched)) 'Stage retained original liboctave.'
    Assert-True ((Get-Sha256File (Join-Path $octave 'mingw64\bin\liboctave-13.dll')) -ne (Get-Sha256File $patched)) 'Assembler modified its source Octave tree.'
    Assert-True (Test-Path -LiteralPath (Join-Path $success.Stage 'stage-import-closure.tsv') -PathType Leaf) 'Stage omitted its static import closure.'
    $successReport = $success.Output | ConvertFrom-Json
    Assert-True ($successReport.AuditedPeFileCount -eq 8 -and $successReport.AuditedOctFileCount -eq 1) 'Every synthetic PE, including the .oct module, was not audited.'
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
