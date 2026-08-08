[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = 'C:\pure-lang'
$taskRoot = 'C:\tmp\todo51-task3'
$ownerPath = Join-Path $repoRoot 'pure-octave\probes\invoke_task3_process_owner.ps1'
$pinnedPwsh = 'C:\Program Files\WindowsApps\Microsoft.PowerShell_7.6.4.0_x64__8wekyb3d8bbwe\pwsh.exe'
$pinnedPwshSha256 = 'DB6DD81183FE57D22E03B911EC9A30A2FD7C40542E97743615355A6FB44F458F'
$productionV17Paths = [string[]]@(
    'C:\tmp\todo51-task3\stage-runtime-v17',
    'C:\tmp\todo51-task3\stage_v17_wrapper.ps1',
    'C:\tmp\todo51-task3\stage_v17_preflight_audit.ps1',
    'C:\tmp\todo51-task3\stage_v17_postaudit.ps1',
    'C:\tmp\todo51-task3\stage-runtime-v17.preflight.owner-contract.json',
    'C:\tmp\todo51-task3\stage-runtime-v17.assembler.owner-contract.json',
    'C:\tmp\todo51-task3\stage-runtime-v17.postaudit.owner-contract.json'
)

function Assert-ProductionV17PathsAbsent {
    foreach ($productionPath in $productionV17Paths) {
        if (Test-Path -LiteralPath $productionPath) {
            throw "Production v17 path exists: $productionPath"
        }
    }
}

Assert-ProductionV17PathsAbsent

$testRoot = Join-Path $taskRoot ("process-owner-tests-" + [guid]::NewGuid().ToString('N'))
$evidenceRoot = Join-Path $testRoot 'evidence'
$childPath = Join-Path $testRoot 'fixture-child.ps1'
$childMarkerPath = Join-Path $testRoot 'fixture-child.marker.txt'
$utf8NoBom = [Text.UTF8Encoding]::new($false)

function Assert-RegularNonReparseDirectory([string] $Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        throw "Regular directory is required: $Path"
    }
    $item = Get-Item -LiteralPath $Path -Force
    if ($item -isnot [IO.DirectoryInfo] -or
        (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0)) {
        throw "Reparse directory is not allowed: $Path"
    }
    $linkTypeProperty = $item.PSObject.Properties['LinkType']
    if ($null -ne $linkTypeProperty -and -not [string]::IsNullOrEmpty([string]$linkTypeProperty.Value)) {
        throw "Linked directory is not allowed: $Path"
    }
}

function Write-Contract([string] $Path, [hashtable] $Overrides = @{}) {
    $contract = [ordered]@{
        SchemaVersion = 1
        Phase = 'Preflight'
        OwnerPath = $ownerPath
        OwnerSha256 = (Get-FileHash -LiteralPath $ownerPath -Algorithm SHA256).Hash
        PowerShellPath = $pinnedPwsh
        PowerShellSha256 = $pinnedPwshSha256
        ChildScriptPath = $childPath
        ChildScriptSha256 = (Get-FileHash -LiteralPath $childPath -Algorithm SHA256).Hash
        Arguments = [string[]]@()
        WorkingDirectory = $repoRoot
        EvidenceRoot = $evidenceRoot
        PidPath = Join-Path $evidenceRoot 'child.pid.txt'
        StdoutPath = Join-Path $evidenceRoot 'child.stdout.log'
        StderrPath = Join-Path $evidenceRoot 'child.stderr.log'
        OwnerExitPath = Join-Path $evidenceRoot 'owner.exit.json'
        OwnerErrorPath = Join-Path $evidenceRoot 'owner.error.json'
    }
    foreach ($key in $Overrides.Keys) { $contract[$key] = $Overrides[$key] }
    $json = $contract | ConvertTo-Json -Depth 4 -Compress
    [IO.File]::WriteAllText($Path, $json, [Text.UTF8Encoding]::new($false))
}

function Get-MatchingChildProcessIds {
    $ids = [Collections.Generic.List[int]]::new()
    foreach ($process in Get-CimInstance -ClassName Win32_Process) {
        if ($null -ne $process.CommandLine -and
            $process.CommandLine.IndexOf($childPath, [StringComparison]::OrdinalIgnoreCase) -ge 0) {
            $ids.Add([int]$process.ProcessId)
        }
    }
    return [int[]]$ids.ToArray()
}

function Write-CaseContract([string] $Path, [string] $CaseName) {
    switch ($CaseName) {
        'Valid' { Write-Contract -Path $Path }
        'Unknown field' { Write-Contract -Path $Path -Overrides @{ Unexpected = 'rejected' } }
        'Missing field' {
            Write-Contract -Path $Path
            $contract = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json -NoEnumerate
            [void]$contract.PSObject.Properties.Remove('Phase')
            [IO.File]::WriteAllText($Path, ($contract | ConvertTo-Json -Depth 4 -Compress), $utf8NoBom)
        }
        'Schema version' { Write-Contract -Path $Path -Overrides @{ SchemaVersion = 2 } }
        'String schema version' { Write-Contract -Path $Path -Overrides @{ SchemaVersion = '1' } }
        'Fractional schema version' { Write-Contract -Path $Path -Overrides @{ SchemaVersion = 1.5 } }
        'Unsupported phase' { Write-Contract -Path $Path -Overrides @{ Phase = 'Postflight' } }
        'Non-string owner hash' { Write-Contract -Path $Path -Overrides @{ OwnerSha256 = 7 } }
        'Arguments not array' { Write-Contract -Path $Path -Overrides @{ Arguments = 'argument' } }
        'Arguments non-string element' { Write-Contract -Path $Path -Overrides @{ Arguments = [object[]]@('argument', 7) } }
        'Duplicate evidence paths' {
            $duplicatePath = Join-Path $evidenceRoot 'duplicate.log'
            Write-Contract -Path $Path -Overrides @{ PidPath = $duplicatePath; StdoutPath = $duplicatePath }
        }
        'Relative path' { Write-Contract -Path $Path -Overrides @{ ChildScriptPath = 'fixture-child.ps1' } }
        'Evidence path outside root' {
            Write-Contract -Path $Path -Overrides @{ StderrPath = (Join-Path $taskRoot 'outside-evidence.stderr.log') }
        }
        'Incorrect owner path' {
            Write-Contract -Path $Path -Overrides @{ OwnerPath = (Join-Path $testRoot 'other-owner.ps1') }
        }
        'Incorrect owner hash' { Write-Contract -Path $Path -Overrides @{ OwnerSha256 = ('0' * 64) } }
        'Incorrect PowerShell hash' { Write-Contract -Path $Path -Overrides @{ PowerShellSha256 = ('0' * 64) } }
        'Incorrect child hash' { Write-Contract -Path $Path -Overrides @{ ChildScriptSha256 = ('0' * 64) } }
        'Existing evidence path' {
            Write-Contract -Path $Path
            [IO.File]::WriteAllText((Join-Path $evidenceRoot 'child.stdout.log'), 'pre-existing', $utf8NoBom)
        }
        default { throw "Unknown test case: $CaseName" }
    }
}

function Invoke-ContractCase([string] $CaseName) {
    $contractPath = Join-Path $testRoot (([guid]::NewGuid().ToString('N')) + '.json')
    Write-CaseContract -Path $contractPath -CaseName $CaseName
    $writtenContract = Get-Content -LiteralPath $contractPath -Raw | ConvertFrom-Json -NoEnumerate
    $evidencePaths = [string[]]@(
        $writtenContract.PidPath, $writtenContract.StdoutPath, $writtenContract.StderrPath,
        $writtenContract.OwnerExitPath, $writtenContract.OwnerErrorPath
    )
    $preexistingEvidencePaths = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($evidencePath in $evidencePaths) {
        if (Test-Path -LiteralPath $evidencePath) {
            [void]$preexistingEvidencePaths.Add($evidencePath)
        }
    }
    $beforeIds = @(Get-MatchingChildProcessIds)
    & $pinnedPwsh -NoProfile -NonInteractive -File $ownerPath -ContractPath $contractPath 2>&1 | Out-Null
    $exitCode = $LASTEXITCODE
    $afterIds = @(Get-MatchingChildProcessIds)

    if ($CaseName -eq 'Valid') {
        if ($exitCode -ne 0) { throw "Valid contract was rejected with exit code $exitCode." }
    }
    elseif ($exitCode -ne 125) {
        throw "$CaseName exited $exitCode instead of validation failure 125."
    }

    if (Test-Path -LiteralPath $childMarkerPath) {
        throw "$CaseName launched the fixture child."
    }
    if ($afterIds.Count -ne 0 -or $beforeIds.Count -ne 0) {
        throw "$CaseName left a matching fixture child process."
    }
    foreach ($evidencePath in $evidencePaths) {
        if ((Test-Path -LiteralPath $evidencePath) -and -not $preexistingEvidencePaths.Contains($evidencePath)) {
            throw "$CaseName created evidence: $evidencePath"
        }
    }
}

try {
    Assert-RegularNonReparseDirectory -Path ([IO.Path]::GetDirectoryName($taskRoot))
    if (Test-Path -LiteralPath $taskRoot) {
        Assert-RegularNonReparseDirectory -Path $taskRoot
    }
    else {
        [IO.Directory]::CreateDirectory($taskRoot) | Out-Null
        Assert-RegularNonReparseDirectory -Path $taskRoot
    }
    if (Test-Path -LiteralPath $testRoot) {
        throw "Disposable test root already exists: $testRoot"
    }
    [IO.Directory]::CreateDirectory($evidenceRoot) | Out-Null
    $childScript = "[IO.File]::WriteAllText('$($childMarkerPath.Replace("'", "''"))', 'CHILD_LAUNCHED', [Text.UTF8Encoding]::new(`$false))`r`nexit 0`r`n"
    [IO.File]::WriteAllText($childPath, $childScript, $utf8NoBom)

    if (-not (Test-Path -LiteralPath $ownerPath -PathType Leaf)) {
        throw "Owner script is missing: $ownerPath"
    }

    foreach ($caseName in [string[]]@(
        'Valid',
        'Unknown field',
        'Missing field',
        'Schema version',
        'String schema version',
        'Fractional schema version',
        'Unsupported phase',
        'Non-string owner hash',
        'Arguments not array',
        'Arguments non-string element',
        'Duplicate evidence paths',
        'Relative path',
        'Evidence path outside root',
        'Incorrect owner path',
        'Incorrect owner hash',
        'Incorrect PowerShell hash',
        'Incorrect child hash',
        'Existing evidence path'
    )) {
        Invoke-ContractCase -CaseName $caseName
    }

    Assert-ProductionV17PathsAbsent
    Write-Output 'PASS owner contract validation tests'
}
finally {
    if (Test-Path -LiteralPath $testRoot) {
        Remove-Item -LiteralPath $testRoot -Recurse -Force
    }
}
