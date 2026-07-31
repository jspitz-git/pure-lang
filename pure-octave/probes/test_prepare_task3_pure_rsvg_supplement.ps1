[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$preparer = Join-Path $PSScriptRoot 'prepare_task3_pure_rsvg_supplement.ps1'
$repoContract = Join-Path $PSScriptRoot 'task3-pure-rsvg-supplement-contract.psd1'
$testRoot = 'C:\tmp\todo51-task3\supplement-preparer-tests'
$sourceBin = 'C:\msys64\clang64\bin'
$pureRoot = 'C:\tmp\Relocated Pure Gplot Final Bundle 20260729'
$acceptedManifest = 'C:\tmp\todo51-task3\stage-runtime-v5\stage-manifest.tsv'
$names = @('librsvg-2-2.dll','libunwind.dll','libxml2-16.dll')
$expectedBytes = [long]7241216

function Assert-True([bool] $Condition, [string] $Message) {
    if (-not $Condition) { throw "ASSERT: $Message" }
}

function Assert-Equal($Actual, $Expected, [string] $Message) {
    if ($Actual -ne $Expected) { throw "ASSERT: $Message (actual '$Actual', expected '$Expected')" }
}

function Get-Sha256([string] $Path) {
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
}

function Write-ExpectedFiles([string] $Path, [string[]] $Files) {
    $lines = @($Files | ForEach-Object {
        $file = Join-Path $sourceBin $_
        $hash = Get-Sha256 $file
        "$_`t$((Get-Item -LiteralPath $file).Length)`t$hash`tpei-x86-64"
    })
    [IO.File]::WriteAllText($Path, (($lines -join "`n") + "`n"), [Text.UTF8Encoding]::new($false))
}

function Write-ImportOverride([string] $Path, [string] $ExtraImport) {
    [IO.File]::WriteAllText($Path, "librsvg-2-2.dll`t$ExtraImport`n", [Text.UTF8Encoding]::new($false))
}

function Invoke-Preparer {
    param(
        [string[]] $Files = $names,
        [string] $Mutate = '',
        [string] $ExtraImport = '',
        [switch] $ReparseSnapshotParent,
        [switch] $ExistingSnapshot,
        [ValidateSet('Plan','Apply')][string] $Mode = 'Plan',
        [string] $Case = 'case',
        [switch] $InjectFailureAfterFirstCopy,
        [switch] $InjectApiSetReleaseFailure
    )
    $caseRoot = Join-Path $testRoot $Case
    [IO.Directory]::CreateDirectory($caseRoot) | Out-Null
    $expected = Join-Path $caseRoot 'expected-files.tsv'
    $imports = Join-Path $caseRoot 'imports.tsv'
    $contract = Join-Path $caseRoot 'contract.psd1'
    Write-ExpectedFiles $expected $Files
    $invokeSourceBin = $sourceBin
    if ($Mutate) {
        $invokeSourceBin = Join-Path $caseRoot 'mutated-source'
        [IO.Directory]::CreateDirectory($invokeSourceBin) | Out-Null
        foreach ($name in $names) { [IO.File]::Copy((Join-Path $sourceBin $name), (Join-Path $invokeSourceBin $name), $false) }
        $mutatedPath = Join-Path $invokeSourceBin $Mutate
        $stream = [IO.File]::Open($mutatedPath, [IO.FileMode]::Open, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
        try { $stream.Position = $stream.Length - 1; $value = $stream.ReadByte(); $stream.Position = $stream.Length - 1; $stream.WriteByte($value -bxor 1) }
        finally { $stream.Dispose() }
    }
    $snapshotParent = $caseRoot
    if ($ReparseSnapshotParent) {
        $target = Join-Path $caseRoot 'junction-target'
        [IO.Directory]::CreateDirectory($target) | Out-Null
        $snapshotParent = Join-Path $caseRoot 'junction'
        New-Item -ItemType Junction -Path $snapshotParent -Target $target | Out-Null
    }
    $snapshot = Join-Path $snapshotParent 'snapshot'
    if ($ExistingSnapshot) { [IO.Directory]::CreateDirectory($snapshot) | Out-Null }
    if ($ExtraImport) { Write-ImportOverride $imports $ExtraImport }
    $arguments = @{
        SourceBin=$invokeSourceBin
        PureRoot=$pureRoot
        AcceptedStageManifest=$acceptedManifest
        SnapshotRoot=$snapshot
        ContractOutput=$contract
        Mode=$Mode
        TestMode=$true
        SyntheticExpectedFiles=$expected
    }
    if ($ExtraImport) { $arguments.SyntheticImportManifest = $imports }
    if ($InjectFailureAfterFirstCopy) { $arguments.InjectFailureAfterFirstCopy = $true }
    if ($InjectApiSetReleaseFailure) { $arguments.InjectApiSetReleaseFailure = $true }
    $json = & $preparer @arguments
    return [pscustomobject]@{
        Result = ($json | ConvertFrom-Json)
        Snapshot = $snapshot
        Temporary = $snapshot + '.tmp'
        Contract = $contract
    }
}

function Assert-Throws([scriptblock] $Action, [string] $Expected) {
    $caught = $null
    try { $null = & $Action }
    catch {
        $caught = $_
    }
    if ($null -eq $caught) { throw "ASSERT: expected failure containing '$Expected'" }
    if ($caught.Exception.Message -notlike "*$Expected*") { throw "ASSERT: wrong failure: $($caught.Exception.Message)" }
}

if (-not (Test-Path -LiteralPath $preparer -PathType Leaf)) { throw "TDD RED: preparer does not exist: $preparer" }
if (-not (Test-Path -LiteralPath $repoContract -PathType Leaf)) { throw "TDD RED: repository contract does not exist: $repoContract" }

if (Test-Path -LiteralPath $testRoot) { Remove-Item -LiteralPath $testRoot -Recurse -Force }
[IO.Directory]::CreateDirectory($testRoot) | Out-Null

try {
    Assert-Throws { Invoke-Preparer -Files @('librsvg-2-2.dll','libunwind.dll') -Case 'wrong-set' } 'Supplement file set is not exact'
    Write-Output 'PASS Test-RejectsInexactSupplementSet'

    Assert-Throws { Invoke-Preparer -Mutate 'libxml2-16.dll' -Case 'mutated' } 'Supplement SHA-256 mismatch'
    Write-Output 'PASS Test-RejectsSupplementHashMismatch'

    Assert-Throws { Invoke-Preparer -ExtraImport 'libunexpected.dll' -Case 'unresolved' } 'Unresolved supplement import'
    Write-Output 'PASS Test-RejectsUnresolvedSupplementImport'

    Assert-Throws { Invoke-Preparer -ExtraImport 'api-ms-win-fabricated-l1-1-0.dll' -Case 'fabricated-api-set' } 'Unresolved supplement import'
    Write-Output 'PASS Test-RejectsFabricatedApiSetImport'

    Assert-Throws { Invoke-Preparer -InjectApiSetReleaseFailure -Case 'api-set-release' } 'Failed to release API-set module'
    Write-Output 'PASS Test-RejectsApiSetReleaseFailure'

    Assert-Throws { Invoke-Preparer -ReparseSnapshotParent -Case 'reparse' } 'contains a reparse point'
    Write-Output 'PASS Test-RejectsReparseSnapshotParent'

    Assert-Throws { Invoke-Preparer -ExistingSnapshot -Mode Apply -Case 'existing' } 'Snapshot root must be absent'
    Write-Output 'PASS Test-RejectsExistingSnapshotOnApply'

    $plan = Invoke-Preparer -Case 'plan'
    Assert-Equal $plan.Result.Changes 3 'Plan predicts three additions'
    Assert-Equal $plan.Result.AddedBytes $expectedBytes 'Plan predicts exact added bytes'
    Assert-Equal $plan.Result.ExpectedStageFileCount 64312 'Plan predicts exact stage file count'
    Assert-Equal $plan.Result.ExpectedStageBytes 3334971045 'Plan predicts exact stage bytes'
    Assert-Equal $plan.Result.ExpectedStageManifestSha256 '115AC1F8843FFC60A4FFD103DCB7CD9C3099CAE14F2B3B674EF5D6230DF22DE0' 'Plan predicts deterministic stage manifest'
    Assert-Equal $plan.Result.ExpectedAuditedPeCount 1539 'Plan predicts exact PE audit count'
    Assert-Equal $plan.Result.ExpectedAuditedOctCount 219 'Plan preserves exact OCT audit count'
    Assert-Equal $plan.Result.ExpectedPinnedPlaceholderCount 1 'Plan preserves placeholder count'
    Assert-Equal ([string]::Join(',', [string[]]$plan.Result.Files.Name)) ([string]::Join(',', $names)) 'Plan preserves exact file ordering'
    foreach ($file in $plan.Result.Files) { Assert-Equal $file.PeMachine 'pei-x86-64' "PE machine for $($file.Name)" }
    foreach ($required in @('zlib1.dll','libiconv-2.dll')) {
        Assert-True ($required -in [string[]]$plan.Result.ReusedPureDependencies.Name) "closure includes $required"
    }
    foreach ($reused in $plan.Result.ReusedPureDependencies) {
        Assert-Equal $reused.PureSha256 $reused.SourceSha256 "Pure dependency is byte-identical to clang64: $($reused.Name)"
    }
    Write-Output 'PASS Test-PlansExactImmutableContract'

    $sourceBefore = @{}; foreach ($name in $names) { $sourceBefore[$name] = Get-Sha256 (Join-Path $sourceBin $name) }
    $rollback = $null
    try { $rollback = Invoke-Preparer -Mode Apply -InjectFailureAfterFirstCopy -Case 'rollback'; throw 'ASSERT: injected failure did not fire' }
    catch { Assert-True ($_.Exception.Message -like '*Injected failure after first copied file*') 'rollback failure was injected at exact checkpoint' }
    $rollbackSnapshot = Join-Path (Join-Path $testRoot 'rollback') 'snapshot'
    Assert-True (-not (Test-Path -LiteralPath $rollbackSnapshot)) 'rollback leaves final snapshot absent'
    Assert-True (-not (Test-Path -LiteralPath ($rollbackSnapshot + '.tmp'))) 'rollback removes exact temporary sibling'
    foreach ($name in $names) { Assert-Equal (Get-Sha256 (Join-Path $sourceBin $name)) $sourceBefore[$name] "rollback preserves source $name" }
    Write-Output 'PASS Test-RollsBackInjectedCopyFailure'

    $apply = Invoke-Preparer -Mode Apply -Case 'apply'
    Assert-True (Test-Path -LiteralPath $apply.Snapshot -PathType Container) 'Apply creates final immutable snapshot'
    Assert-True (-not (Test-Path -LiteralPath $apply.Temporary)) 'Apply leaves no temporary sibling'
    $contract = Import-PowerShellDataFile -LiteralPath $apply.Contract
    Assert-Equal $contract.AddedFileCount 3 'contract records three files'
    Assert-Equal $contract.AddedBytes $expectedBytes 'contract records exact bytes'
    foreach ($name in $names) {
        Assert-Equal (Get-Sha256 (Join-Path $apply.Snapshot $name)) (Get-Sha256 (Join-Path $sourceBin $name)) "snapshot is byte-identical: $name"
    }
    $idempotent = & $preparer -SourceBin $sourceBin -PureRoot $pureRoot -AcceptedStageManifest $acceptedManifest -SnapshotRoot $apply.Snapshot -ContractOutput $apply.Contract -Mode Plan -TestMode -SyntheticExpectedFiles (Join-Path (Join-Path $testRoot 'apply') 'expected-files.tsv') | ConvertFrom-Json
    Assert-Equal $idempotent.Changes 0 'Plan is idempotent against matching snapshot'
    Write-Output 'PASS Test-AppliesTransactionallyAndPlansIdempotently'

    $nested = Join-Path $apply.Snapshot 'nested'
    [IO.Directory]::CreateDirectory($nested) | Out-Null
    [IO.File]::WriteAllText((Join-Path $nested 'contaminant.txt'), 'contaminant', [Text.UTF8Encoding]::new($false))
    Assert-Throws {
        & $preparer -SourceBin $sourceBin -PureRoot $pureRoot -AcceptedStageManifest $acceptedManifest -SnapshotRoot $apply.Snapshot -ContractOutput $apply.Contract -Mode Plan -TestMode -SyntheticExpectedFiles (Join-Path (Join-Path $testRoot 'apply') 'expected-files.tsv')
    } 'Existing snapshot file set is not exact'
    Write-Output 'PASS Test-RejectsContaminatedExistingSnapshot'

    Write-Output 'PASS all supplement preparer tests'
}
finally {
    if (Test-Path -LiteralPath $testRoot) { Remove-Item -LiteralPath $testRoot -Recurse -Force }
}
