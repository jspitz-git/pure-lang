[CmdletBinding()]
param([switch] $PhaseContractOnly)

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

function Assert-NoReservedVariableAssignment(
    [Management.Automation.Language.ScriptBlockAst] $Ast
) {
    $reserved = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($name in @('HOME','Error','Args','Input','Matches','MyInvocation',
        'PSBoundParameters','PSScriptRoot','PSCommandPath','LASTEXITCODE')) {
        [void] $reserved.Add($name)
    }
    $runtimeReservedNames = & $pinnedPwsh -NoProfile -NonInteractive -Command `
        'Get-Variable | Where-Object { ($_.Options -band ([Management.Automation.ScopedItemOptions]::ReadOnly -bor [Management.Automation.ScopedItemOptions]::Constant)) -ne 0 } | ForEach-Object Name'
    if ($LASTEXITCODE -ne 0) {
        throw "Pinned PowerShell reserved-variable inventory exited $LASTEXITCODE."
    }
    foreach ($name in [string[]]$runtimeReservedNames) {
        [void] $reserved.Add($name)
    }

    $assignments = $Ast.FindAll({
        param($node)
        $node -is [Management.Automation.Language.AssignmentStatementAst]
    }, $true)
    foreach ($assignment in $assignments) {
        $targets = $assignment.Left.FindAll({
            param($node)
            $node -is [Management.Automation.Language.VariableExpressionAst]
        }, $true)
        foreach ($target in $targets) {
            $isAssignmentTarget = $true
            $ancestor = $target.Parent
            while ($null -ne $ancestor -and $ancestor -ne $assignment) {
                if ($ancestor -is [Management.Automation.Language.IndexExpressionAst] -or
                    $ancestor -is [Management.Automation.Language.MemberExpressionAst]) {
                    $isAssignmentTarget = $false
                    break
                }
                $ancestor = $ancestor.Parent
            }
            if (-not $isAssignmentTarget) { continue }
            $name = $target.VariablePath.UserPath
            $scopeSeparator = $name.IndexOf([char]':')
            if ($scopeSeparator -gt 0) {
                $scopeName = $name.Substring(0, $scopeSeparator)
                if ($scopeName -in [string[]]@('global', 'script', 'local', 'private')) {
                    $name = $name.Substring($scopeSeparator + 1)
                }
            }
            if ($reserved.Contains($name)) {
                throw "Reserved automatic variable assignment: $name"
            }
        }
    }
}

$parseTokens = $null
$parseErrors = $null
$ownerAst = [Management.Automation.Language.Parser]::ParseFile(
    $ownerPath, [ref]$parseTokens, [ref]$parseErrors)
if ($parseErrors.Count -ne 0) {
    throw "Owner parser errors: $($parseErrors.Message -join '; ')"
}
$mutatedOwnerSource = $ownerAst.Extent.Text.Replace('$childPid', '$pid')
$mutatedTokens = $null
$mutatedErrors = $null
$mutatedOwnerAst = [Management.Automation.Language.Parser]::ParseInput(
    $mutatedOwnerSource, [ref]$mutatedTokens, [ref]$mutatedErrors)
if ($mutatedErrors.Count -ne 0) {
    throw "Mutated owner parser errors: $($mutatedErrors.Message -join '; ')"
}
try {
    Assert-NoReservedVariableAssignment -Ast $mutatedOwnerAst
    throw 'Reserved-variable mutation was accepted.'
}
catch {
    if (-not [string]::Equals($_.Exception.Message,
        'Reserved automatic variable assignment: pid',
        [StringComparison]::Ordinal)) {
        throw
    }
}
$scopedMutatedOwnerSource = $ownerAst.Extent.Text.Replace('$childPid', '$script:pid')
$scopedMutatedTokens = $null
$scopedMutatedErrors = $null
$scopedMutatedOwnerAst = [Management.Automation.Language.Parser]::ParseInput(
    $scopedMutatedOwnerSource, [ref]$scopedMutatedTokens, [ref]$scopedMutatedErrors)
if ($scopedMutatedErrors.Count -ne 0) {
    throw "Scoped mutated owner parser errors: $($scopedMutatedErrors.Message -join '; ')"
}
try {
    Assert-NoReservedVariableAssignment -Ast $scopedMutatedOwnerAst
    throw 'Scoped reserved-variable mutation was accepted.'
}
catch {
    if (-not [string]::Equals($_.Exception.Message,
        'Reserved automatic variable assignment: pid',
        [StringComparison]::Ordinal)) {
        throw
    }
}
$indexedReferenceSource = $ownerAst.Extent.Text + "`n`$buffer[`$PID] = 1`n"
$indexedReferenceTokens = $null
$indexedReferenceErrors = $null
$indexedReferenceAst = [Management.Automation.Language.Parser]::ParseInput(
    $indexedReferenceSource, [ref]$indexedReferenceTokens, [ref]$indexedReferenceErrors)
if ($indexedReferenceErrors.Count -ne 0) {
    throw "Indexed-reference parser errors: $($indexedReferenceErrors.Message -join '; ')"
}
Assert-NoReservedVariableAssignment -Ast $indexedReferenceAst
Assert-NoReservedVariableAssignment -Ast $ownerAst

$testRoot = Join-Path $taskRoot ("process-owner-tests-" + [guid]::NewGuid().ToString('N'))
$evidenceRoot = Join-Path $testRoot 'evidence'
$childPath = Join-Path $testRoot 'fixture-child.ps1'
$childMarkerPath = Join-Path $testRoot 'fixture-child.marker.txt'
$successChildPath = Join-Path $testRoot 'success-child.ps1'
$failureChildPath = Join-Path $testRoot 'failure-child.ps1'
$volumeChildPath = Join-Path $testRoot 'volume-child.ps1'
$mutationChildPath = Join-Path $testRoot 'mutation-child.ps1'
$interruptionChildPath = Join-Path $testRoot 'interruption-child.ps1'
$interruptionStartPath = Join-Path $testRoot 'interruption-child.start.txt'
$interruptionEndPath = Join-Path $testRoot 'interruption-child.end.txt'
$junctionTargetPath = Join-Path $testRoot 'junction-target'
$junctionPath = Join-Path $testRoot 'junction-component'
$junctionEvidenceRoot = Join-Path $junctionPath 'evidence'
$symbolicLinkChildPath = Join-Path $testRoot 'symbolic-link-child.ps1'
$hardLinkSourcePath = Join-Path $testRoot 'hard-link-source.ps1'
$hardLinkChildPath = Join-Path $testRoot 'hard-link-child.ps1'
$escapeRoot = Join-Path 'C:\tmp' ("todo51-task3-escape-" + [guid]::NewGuid().ToString('N'))
$escapeSentinelPath = Join-Path $escapeRoot 'cleanup-confinement.sentinel.txt'
$untrustedOwnerErrorPath = Join-Path $escapeRoot 'untrusted-owner.error.json'
$escapeFixtureCreated = $false
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

function Assert-ExactBytes([byte[]] $Actual, [byte[]] $Expected, [string] $Description) {
    if ($Actual.Length -ne $Expected.Length) {
        throw "$Description has $($Actual.Length) bytes instead of $($Expected.Length)."
    }
    for ($index = 0; $index -lt $Expected.Length; $index++) {
        if ($Actual[$index] -ne $Expected[$index]) {
            throw "$Description differs at byte $index."
        }
    }
}

function Assert-RepeatedByte([byte[]] $Actual, [byte] $Expected, [string] $Description) {
    for ($index = 0; $index -lt $Actual.Length; $index++) {
        if ($Actual[$index] -ne $Expected) {
            throw "$Description differs at byte $index."
        }
    }
}

function Assert-ExactProperties([PSCustomObject] $Object, [string[]] $ExpectedNames, [string] $Description) {
    $actualNames = [string[]]@($Object.PSObject.Properties.Name)
    if ($actualNames.Length -ne $ExpectedNames.Length) {
        throw "$Description has $($actualNames.Length) fields instead of $($ExpectedNames.Length)."
    }
    for ($index = 0; $index -lt $ExpectedNames.Length; $index++) {
        if (-not [string]::Equals($actualNames[$index], $ExpectedNames[$index], [StringComparison]::Ordinal)) {
            throw "$Description field $index is $($actualNames[$index]) instead of $($ExpectedNames[$index])."
        }
    }
}

function New-LifecycleContract(
    [string] $CaseName,
    [string] $LifecycleChildPath,
    [string] $Phase = 'Preflight'
) {
    $caseRoot = Join-Path $testRoot $CaseName
    $caseEvidenceRoot = Join-Path $caseRoot 'evidence'
    [IO.Directory]::CreateDirectory($caseEvidenceRoot) | Out-Null
    $contractPath = Join-Path $caseRoot 'owner-contract.json'
    Write-Contract -Path $contractPath -Overrides @{
        ChildScriptPath = $LifecycleChildPath
        ChildScriptSha256 = (Get-FileHash -LiteralPath $LifecycleChildPath -Algorithm SHA256).Hash
        Phase = $Phase
        EvidenceRoot = $caseEvidenceRoot
        PidPath = Join-Path $caseEvidenceRoot 'child.pid.txt'
        StdoutPath = Join-Path $caseEvidenceRoot 'child.stdout.log'
        StderrPath = Join-Path $caseEvidenceRoot 'child.stderr.log'
        OwnerExitPath = Join-Path $caseEvidenceRoot 'owner.exit.json'
        OwnerErrorPath = Join-Path $caseEvidenceRoot 'owner.error.json'
    }
    return $contractPath
}

function Invoke-OwnerWithTimeout([string] $ContractPath, [int] $TimeoutMilliseconds = 30000) {
    $timeoutContract = Get-Content -LiteralPath $ContractPath -Raw | ConvertFrom-Json -NoEnumerate
    $startInfo = [Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $pinnedPwsh
    $startInfo.WorkingDirectory = $repoRoot
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    [void]$startInfo.ArgumentList.Add('-NoProfile')
    [void]$startInfo.ArgumentList.Add('-NonInteractive')
    [void]$startInfo.ArgumentList.Add('-File')
    [void]$startInfo.ArgumentList.Add($ownerPath)
    [void]$startInfo.ArgumentList.Add('-ContractPath')
    [void]$startInfo.ArgumentList.Add($ContractPath)

    $ownerProcess = [Diagnostics.Process]::new()
    try {
        $ownerProcess.StartInfo = $startInfo
        if (-not $ownerProcess.Start()) { throw 'Owner Process.Start returned false.' }
        $ownerStdout = $ownerProcess.StandardOutput.ReadToEndAsync()
        $ownerStderr = $ownerProcess.StandardError.ReadToEndAsync()
        if (-not $ownerProcess.WaitForExit($TimeoutMilliseconds)) {
            Stop-DisposableOwnerAndWaitNaturalChild -OwnerProcess $ownerProcess `
                -PidPath $timeoutContract.PidPath
            throw "Owner timed out after $TimeoutMilliseconds milliseconds."
        }
        [Threading.Tasks.Task]::WaitAll([Threading.Tasks.Task[]]@($ownerStdout, $ownerStderr))
        return [PSCustomObject]@{
            ExitCode = $ownerProcess.ExitCode
            Stdout = $ownerStdout.Result
            Stderr = $ownerStderr.Result
        }
    }
    finally {
        $ownerProcess.Dispose()
    }
}

function Wait-PathExists([string] $Path, [int] $TimeoutMilliseconds) {
    $stopwatch = [Diagnostics.Stopwatch]::StartNew()
    while (-not (Test-Path -LiteralPath $Path)) {
        if ($stopwatch.ElapsedMilliseconds -ge $TimeoutMilliseconds) {
            throw "Timed out waiting for path: $Path"
        }
        Start-Sleep -Milliseconds 25
    }
}

function Wait-ProcessNaturalExit([int] $ProcessId, [int] $TimeoutMilliseconds) {
    $stopwatch = [Diagnostics.Stopwatch]::StartNew()
    while ($null -ne (Get-Process -Id $ProcessId -ErrorAction SilentlyContinue)) {
        if ($stopwatch.ElapsedMilliseconds -ge $TimeoutMilliseconds) {
            throw "Timed out waiting for child PID $ProcessId to exit naturally."
        }
        Start-Sleep -Milliseconds 25
    }
}

function Stop-DisposableOwnerAndWaitNaturalChild(
    [Diagnostics.Process] $OwnerProcess,
    [object] $KnownChildPid = $null,
    [string] $PidPath = $null,
    [Collections.Generic.List[int]] $TerminatedProcessIds = $null,
    [int] $OwnerTimeoutMilliseconds = 10000,
    [int] $ChildTimeoutMilliseconds = 15000
) {
    $ownerId = $OwnerProcess.Id
    if (-not $OwnerProcess.HasExited) {
        $OwnerProcess.Kill()
        if ($null -ne $TerminatedProcessIds) { [void]$TerminatedProcessIds.Add($ownerId) }
        if (-not $OwnerProcess.WaitForExit($OwnerTimeoutMilliseconds)) {
            throw "Disposable owner PID $ownerId did not exit after owner-only termination."
        }
    }

    $childPidToWait = $KnownChildPid
    if ($null -eq $childPidToWait -and
        -not [string]::IsNullOrEmpty($PidPath) -and
        (Test-Path -LiteralPath $PidPath -PathType Leaf)) {
        $pidText = [Text.Encoding]::UTF8.GetString([IO.File]::ReadAllBytes($PidPath))
        if ($pidText -notmatch '^([0-9]+)\n$') {
            throw "Disposable child PID evidence is malformed: $PidPath"
        }
        $childPidToWait = [int]$Matches[1]
    }
    if ($null -ne $childPidToWait) {
        $childPidValue = [int]$childPidToWait
        if ($childPidValue -eq $ownerId) {
            throw 'Disposable child PID unexpectedly equals the owner PID.'
        }
        Wait-ProcessNaturalExit -ProcessId $childPidValue `
            -TimeoutMilliseconds $ChildTimeoutMilliseconds
    }
}

function Get-ExternalOwnerClassification(
    [Diagnostics.Process] $OwnerProcess,
    [PSCustomObject] $Contract
) {
    if (-not $OwnerProcess.HasExited) { return 'RUNNING' }
    if (Test-Path -LiteralPath $Contract.OwnerExitPath -PathType Leaf) { return 'COMPLETE' }
    return 'BLOCKED'
}

function Read-OwnerExit(
    [PSCustomObject] $Contract,
    [string] $ExpectedContractSha256,
    [string] $ExpectedPhase = 'Preflight'
) {
    if (-not (Test-Path -LiteralPath $Contract.OwnerExitPath -PathType Leaf)) {
        throw "Owner exit evidence is missing: $($Contract.OwnerExitPath)"
    }
    if (Test-Path -LiteralPath $Contract.OwnerErrorPath) {
        throw "Unexpected owner error evidence exists: $($Contract.OwnerErrorPath)"
    }
    $ownerExit = Get-Content -LiteralPath $Contract.OwnerExitPath -Raw | ConvertFrom-Json -NoEnumerate
    Assert-ExactProperties -Object $ownerExit -ExpectedNames ([string[]]@(
        'SchemaVersion', 'Phase', 'State', 'ChildPid', 'ChildExitCode',
        'OwnerSha256', 'ContractSha256'
    )) -Description 'owner-exit JSON'
    if ($ownerExit.SchemaVersion -isnot [long] -or $ownerExit.SchemaVersion -ne 1 -or
        $ownerExit.Phase -isnot [string] -or
        -not [string]::Equals($ownerExit.Phase, $ExpectedPhase, [StringComparison]::Ordinal) -or
        $ownerExit.State -isnot [string] -or $ownerExit.State -ne 'Completed' -or
        $ownerExit.ChildPid -isnot [long] -or
        $ownerExit.ChildExitCode -isnot [long] -or
        $ownerExit.OwnerSha256 -isnot [string] -or
        $ownerExit.ContractSha256 -isnot [string]) {
        throw 'owner-exit JSON has an incorrect value type or fixed value.'
    }
    if (-not [string]::Equals($ownerExit.OwnerSha256, $Contract.OwnerSha256, [StringComparison]::Ordinal) -or
        -not [string]::Equals($ownerExit.ContractSha256, $ExpectedContractSha256, [StringComparison]::Ordinal)) {
        throw 'owner-exit JSON does not contain the validated owner and contract hashes.'
    }
    return $ownerExit
}

function Read-OwnerError(
    [PSCustomObject] $Contract,
    [string] $ExpectedContractSha256,
    [string] $ExpectedState,
    [string] $ExpectedMessage,
    [object] $ExpectedChildPid,
    [string] $ExpectedPhase = 'Preflight'
) {
    if (Test-Path -LiteralPath $Contract.OwnerExitPath) {
        throw "Unexpected owner exit evidence exists: $($Contract.OwnerExitPath)"
    }
    if (-not (Test-Path -LiteralPath $Contract.OwnerErrorPath -PathType Leaf)) {
        throw "Owner error evidence is missing: $($Contract.OwnerErrorPath)"
    }
    $ownerError = Get-Content -LiteralPath $Contract.OwnerErrorPath -Raw | ConvertFrom-Json -NoEnumerate
    Assert-ExactProperties -Object $ownerError -ExpectedNames ([string[]]@(
        'SchemaVersion', 'Phase', 'State', 'ExceptionType', 'Message',
        'ChildPid', 'ContractSha256'
    )) -Description 'owner-error JSON'
    if ($ownerError.SchemaVersion -isnot [long] -or $ownerError.SchemaVersion -ne 1 -or
        $ownerError.Phase -isnot [string] -or
        -not [string]::Equals($ownerError.Phase, $ExpectedPhase, [StringComparison]::Ordinal) -or
        $ownerError.State -isnot [string] -or $ownerError.State -ne $ExpectedState -or
        $ownerError.ExceptionType -isnot [string] -or
        $ownerError.Message -isnot [string] -or
        $ownerError.ContractSha256 -isnot [string]) {
        throw 'owner-error JSON has an incorrect value type or fixed value.'
    }
    if (-not [string]::Equals($ownerError.ExceptionType, 'System.Management.Automation.RuntimeException', [StringComparison]::Ordinal) -or
        -not [string]::Equals($ownerError.Message, $ExpectedMessage, [StringComparison]::Ordinal) -or
        -not [string]::Equals($ownerError.ContractSha256, $ExpectedContractSha256, [StringComparison]::Ordinal)) {
        throw "owner-error mismatch: ExceptionType='$($ownerError.ExceptionType)'; Message='$($ownerError.Message)'; ContractSha256='$($ownerError.ContractSha256)'; expected Message='$ExpectedMessage'; expected ContractSha256='$ExpectedContractSha256'."
    }
    if ($null -eq $ExpectedChildPid) {
        if ($null -ne $ownerError.ChildPid) { throw 'owner-error JSON has an unexpected child PID.' }
    }
    elseif ($ownerError.ChildPid -isnot [long] -or $ownerError.ChildPid -ne [long]$ExpectedChildPid) {
        throw 'owner-error JSON child PID is missing or incorrect.'
    }
    return $ownerError
}

function Invoke-SuccessLifecycleTest {
    $contractPath = New-LifecycleContract -CaseName 'success' -LifecycleChildPath $successChildPath
    $contractSha256 = (Get-FileHash -LiteralPath $contractPath -Algorithm SHA256).Hash
    $contract = Get-Content -LiteralPath $contractPath -Raw | ConvertFrom-Json -NoEnumerate
    $result = Invoke-OwnerWithTimeout -ContractPath $contractPath
    if ($result.ExitCode -ne 0) {
        throw "Success owner exited $($result.ExitCode): $($result.Stderr)"
    }
    if (-not [string]::IsNullOrEmpty($result.Stdout) -or -not [string]::IsNullOrEmpty($result.Stderr)) {
        throw 'Success owner wrote unexpected process-level output.'
    }

    $stdoutBytes = [IO.File]::ReadAllBytes($contract.StdoutPath)
    $stdoutText = [Text.Encoding]::UTF8.GetString($stdoutBytes)
    if ($stdoutText -notmatch '^OWNER_STDOUT_SENTINEL CHILD_PID=([0-9]+)$') {
        throw "Success stdout has unexpected bytes: $stdoutText"
    }
    $stdoutChildPid = [long]$Matches[1]
    Assert-ExactBytes -Actual $stdoutBytes -Expected ([Text.Encoding]::UTF8.GetBytes("OWNER_STDOUT_SENTINEL CHILD_PID=$stdoutChildPid")) -Description 'success stdout'
    Assert-ExactBytes -Actual ([IO.File]::ReadAllBytes($contract.StderrPath)) -Expected ([Text.Encoding]::UTF8.GetBytes('OWNER_STDERR_SENTINEL')) -Description 'success stderr'
    $pidBytes = [IO.File]::ReadAllBytes($contract.PidPath)
    Assert-ExactBytes -Actual $pidBytes -Expected ([Text.Encoding]::UTF8.GetBytes(([string]$stdoutChildPid + "`n"))) -Description 'PID evidence'

    $ownerExit = Read-OwnerExit -Contract $contract -ExpectedContractSha256 $contractSha256
    if ($ownerExit.ChildPid -ne $stdoutChildPid -or $ownerExit.ChildExitCode -ne 0) {
        throw 'Success owner-exit PID or child exit code is incorrect.'
    }
}

function Invoke-SupportedPhaseLifecycleTest([string] $Phase) {
    $contractPath = New-LifecycleContract -CaseName ("phase-" + $Phase) `
        -LifecycleChildPath $successChildPath -Phase $Phase
    $contractSha256 = (Get-FileHash -LiteralPath $contractPath -Algorithm SHA256).Hash
    $contract = Get-Content -LiteralPath $contractPath -Raw | ConvertFrom-Json -NoEnumerate
    $result = Invoke-OwnerWithTimeout -ContractPath $contractPath
    if ($result.ExitCode -ne 0) {
        throw "$Phase owner exited $($result.ExitCode): $($result.Stderr)"
    }
    $ownerExit = Read-OwnerExit -Contract $contract `
        -ExpectedContractSha256 $contractSha256 -ExpectedPhase $Phase
    if ($ownerExit.ChildExitCode -ne 0) {
        throw "$Phase owner-exit child exit code is incorrect."
    }
}

function Invoke-FailureLifecycleTest {
    $contractPath = New-LifecycleContract -CaseName 'failure' -LifecycleChildPath $failureChildPath
    $contractSha256 = (Get-FileHash -LiteralPath $contractPath -Algorithm SHA256).Hash
    $contract = Get-Content -LiteralPath $contractPath -Raw | ConvertFrom-Json -NoEnumerate
    $result = Invoke-OwnerWithTimeout -ContractPath $contractPath
    if ($result.ExitCode -ne 23) {
        throw "Failure owner exited $($result.ExitCode) instead of 23: $($result.Stderr)"
    }
    Assert-ExactBytes -Actual ([IO.File]::ReadAllBytes($contract.StdoutPath)) -Expected ([byte[]]::new(0)) -Description 'failure stdout'
    Assert-ExactBytes -Actual ([IO.File]::ReadAllBytes($contract.StderrPath)) -Expected ([Text.Encoding]::UTF8.GetBytes('OWNER_FAILURE_SENTINEL')) -Description 'failure stderr'
    $pidText = [Text.Encoding]::UTF8.GetString([IO.File]::ReadAllBytes($contract.PidPath))
    if ($pidText -notmatch '^([0-9]+)\n$') { throw 'Failure PID evidence is malformed.' }
    $ownerExit = Read-OwnerExit -Contract $contract -ExpectedContractSha256 $contractSha256
    if ($ownerExit.ChildPid -ne [long]$Matches[1] -or $ownerExit.ChildExitCode -ne 23) {
        throw 'Failure owner-exit PID or child exit code is incorrect.'
    }
}

function Invoke-VolumeLifecycleTest {
    $contractPath = New-LifecycleContract -CaseName 'volume' -LifecycleChildPath $volumeChildPath
    $contractSha256 = (Get-FileHash -LiteralPath $contractPath -Algorithm SHA256).Hash
    $contract = Get-Content -LiteralPath $contractPath -Raw | ConvertFrom-Json -NoEnumerate
    $result = Invoke-OwnerWithTimeout -ContractPath $contractPath -TimeoutMilliseconds 30000
    if ($result.ExitCode -ne 0) {
        throw "Volume owner exited $($result.ExitCode): $($result.Stderr)"
    }
    $stdoutBytes = [IO.File]::ReadAllBytes($contract.StdoutPath)
    $stderrBytes = [IO.File]::ReadAllBytes($contract.StderrPath)
    if ($stdoutBytes.Length -ne 1048576 -or $stderrBytes.Length -ne 1048576) {
        throw "Volume streams have lengths $($stdoutBytes.Length) and $($stderrBytes.Length)."
    }
    Assert-RepeatedByte -Actual $stdoutBytes -Expected 0x4f -Description 'volume stdout'
    Assert-RepeatedByte -Actual $stderrBytes -Expected 0x45 -Description 'volume stderr'
    $ownerExit = Read-OwnerExit -Contract $contract -ExpectedContractSha256 $contractSha256
    if ($ownerExit.ChildExitCode -ne 0) { throw 'Volume owner-exit child exit code is incorrect.' }
}

function Invoke-MutationLifecycleTest {
    $contractPath = New-LifecycleContract -CaseName 'mutation' `
        -LifecycleChildPath $mutationChildPath -Phase 'Assembler'
    $contractSha256 = (Get-FileHash -LiteralPath $contractPath -Algorithm SHA256).Hash
    $contract = Get-Content -LiteralPath $contractPath -Raw | ConvertFrom-Json -NoEnumerate
    $result = Invoke-OwnerWithTimeout -ContractPath $contractPath
    if ($result.ExitCode -ne 125) {
        throw "Mutation owner exited $($result.ExitCode) instead of 125: $($result.Stderr)"
    }
    if (-not [string]::IsNullOrEmpty($result.Stdout) -or -not [string]::IsNullOrEmpty($result.Stderr)) {
        throw 'Mutation owner wrote unexpected process-level output.'
    }
    Assert-ExactBytes -Actual ([IO.File]::ReadAllBytes($contract.StdoutPath)) -Expected ([Text.Encoding]::UTF8.GetBytes('OWNER_MUTATION_STDOUT')) -Description 'mutation stdout'
    Assert-ExactBytes -Actual ([IO.File]::ReadAllBytes($contract.StderrPath)) -Expected ([Text.Encoding]::UTF8.GetBytes('OWNER_MUTATION_STDERR')) -Description 'mutation stderr'
    $pidText = [Text.Encoding]::UTF8.GetString([IO.File]::ReadAllBytes($contract.PidPath))
    if ($pidText -notmatch '^([0-9]+)\n$') { throw 'Mutation PID evidence is malformed.' }
    $mutationChildPid = [long]$Matches[1]
    [void](Read-OwnerError -Contract $contract -ExpectedContractSha256 $contractSha256 `
        -ExpectedState 'Draining' `
        -ExpectedMessage 'Validated owner, contract, PowerShell executable, or child script changed during execution.' `
        -ExpectedChildPid $mutationChildPid -ExpectedPhase 'Assembler')
    $temporaryFiles = @(Get-ChildItem -LiteralPath $contract.EvidenceRoot -Force -Filter '*.tmp')
    if ($temporaryFiles.Count -ne 0) { throw 'Mutation owner left an atomic-write temporary file.' }
}

function Invoke-InterruptionLifecycleTest {
    $contractPath = New-LifecycleContract -CaseName 'interruption' -LifecycleChildPath $interruptionChildPath
    $contract = Get-Content -LiteralPath $contractPath -Raw | ConvertFrom-Json -NoEnumerate
    $startInfo = [Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $pinnedPwsh
    $startInfo.WorkingDirectory = $repoRoot
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    [void]$startInfo.ArgumentList.Add('-NoProfile')
    [void]$startInfo.ArgumentList.Add('-NonInteractive')
    [void]$startInfo.ArgumentList.Add('-File')
    [void]$startInfo.ArgumentList.Add($ownerPath)
    [void]$startInfo.ArgumentList.Add('-ContractPath')
    [void]$startInfo.ArgumentList.Add($contractPath)

    $ownerProcess = [Diagnostics.Process]::new()
    $terminatedProcessIds = [Collections.Generic.List[int]]::new()
    $ownerStarted = $false
    $interruptionChildPid = $null
    try {
        $ownerProcess.StartInfo = $startInfo
        if (-not $ownerProcess.Start()) { throw 'Interruption owner Process.Start returned false.' }
        $ownerStarted = $true
        Wait-PathExists -Path $contract.PidPath -TimeoutMilliseconds 10000
        Wait-PathExists -Path $interruptionStartPath -TimeoutMilliseconds 10000
        $pidText = [Text.Encoding]::UTF8.GetString([IO.File]::ReadAllBytes($contract.PidPath))
        if ($pidText -notmatch '^([0-9]+)\n$') { throw 'Interruption PID evidence is malformed.' }
        $interruptionChildPid = [int]$Matches[1]
        if ($interruptionChildPid -eq $ownerProcess.Id) {
            throw 'Interruption child PID unexpectedly equals the disposable owner PID.'
        }
        if ($null -eq (Get-Process -Id $interruptionChildPid -ErrorAction SilentlyContinue)) {
            throw 'Interruption child exited before the disposable owner was terminated.'
        }

        Stop-DisposableOwnerAndWaitNaturalChild -OwnerProcess $ownerProcess `
            -KnownChildPid $interruptionChildPid -TerminatedProcessIds $terminatedProcessIds

        if ($terminatedProcessIds.Count -ne 1 -or $terminatedProcessIds[0] -ne $ownerProcess.Id) {
            throw 'Interruption harness terminated a process other than the disposable owner.'
        }
        Assert-ExactBytes -Actual ([IO.File]::ReadAllBytes($interruptionStartPath)) `
            -Expected ([Text.Encoding]::UTF8.GetBytes('INTERRUPTION_CHILD_STARTED')) `
            -Description 'interruption start sentinel'
        Assert-ExactBytes -Actual ([IO.File]::ReadAllBytes($interruptionEndPath)) `
            -Expected ([Text.Encoding]::UTF8.GetBytes('INTERRUPTION_CHILD_ENDED')) `
            -Description 'interruption end sentinel'
        foreach ($retainedPath in [string[]]@($contract.PidPath, $contract.StdoutPath, $contract.StderrPath)) {
            if (-not (Test-Path -LiteralPath $retainedPath -PathType Leaf)) {
                throw "Interrupted owner did not retain evidence: $retainedPath"
            }
        }
        if (Test-Path -LiteralPath $contract.OwnerExitPath) {
            throw 'Interrupted owner published owner-exit evidence.'
        }
        $classification = Get-ExternalOwnerClassification -OwnerProcess $ownerProcess -Contract $contract
        if (-not [string]::Equals($classification, 'BLOCKED', [StringComparison]::Ordinal)) {
            throw "Interrupted owner classified as $classification instead of BLOCKED."
        }
    }
    finally {
        try {
            if ($ownerStarted) {
                Stop-DisposableOwnerAndWaitNaturalChild -OwnerProcess $ownerProcess `
                    -KnownChildPid $interruptionChildPid -PidPath $contract.PidPath `
                    -TerminatedProcessIds $terminatedProcessIds
            }
        }
        finally {
            $ownerProcess.Dispose()
        }
    }
}

function Get-MatchingChildProcessIds {
    $ids = [Collections.Generic.List[int]]::new()
    foreach ($process in Get-CimInstance -ClassName Win32_Process) {
        if ($null -ne $process.CommandLine -and
            $process.CommandLine.IndexOf($testRoot, [StringComparison]::OrdinalIgnoreCase) -ge 0) {
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
        'Empty phase' { Write-Contract -Path $Path -Overrides @{ Phase = '' } }
        'Wrong-case phase' { Write-Contract -Path $Path -Overrides @{ Phase = 'assembler' } }
        'Non-string phase' { Write-Contract -Path $Path -Overrides @{ Phase = 7 } }
        'Non-string owner hash' { Write-Contract -Path $Path -Overrides @{ OwnerSha256 = 7 } }
        'Arguments not array' { Write-Contract -Path $Path -Overrides @{ Arguments = 'argument' } }
        'Arguments non-string element' { Write-Contract -Path $Path -Overrides @{ Arguments = [object[]]@('argument', 7) } }
        'Duplicate PID and stdout paths' {
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
        'Junction evidence component' {
            Write-Contract -Path $Path -Overrides @{
                EvidenceRoot = $junctionEvidenceRoot
                PidPath = Join-Path $junctionEvidenceRoot 'child.pid.txt'
                StdoutPath = Join-Path $junctionEvidenceRoot 'child.stdout.log'
                StderrPath = Join-Path $junctionEvidenceRoot 'child.stderr.log'
                OwnerExitPath = Join-Path $junctionEvidenceRoot 'owner.exit.json'
                OwnerErrorPath = Join-Path $junctionEvidenceRoot 'owner.error.json'
            }
        }
        'Symbolic-link child script' {
            Write-Contract -Path $Path -Overrides @{
                ChildScriptPath = $symbolicLinkChildPath
                ChildScriptSha256 = (Get-FileHash -LiteralPath $symbolicLinkChildPath -Algorithm SHA256).Hash
            }
        }
        'Hard-linked child script' {
            Write-Contract -Path $Path -Overrides @{
                ChildScriptPath = $hardLinkChildPath
                ChildScriptSha256 = (Get-FileHash -LiteralPath $hardLinkChildPath -Algorithm SHA256).Hash
            }
        }
        'Canonical dot-dot escape' {
            Write-Contract -Path $Path -Overrides @{
                StderrPath = Join-Path $evidenceRoot '..\outside-canonical.stderr.log'
            }
        }
        'Sibling-prefix evidence escape' {
            Write-Contract -Path $Path -Overrides @{
                EvidenceRoot = $escapeRoot
                PidPath = Join-Path $escapeRoot 'sibling.child.pid.txt'
                StdoutPath = Join-Path $escapeRoot 'sibling.child.stdout.log'
                StderrPath = Join-Path $escapeRoot 'sibling.child.stderr.log'
                OwnerExitPath = Join-Path $escapeRoot 'sibling.owner.exit.json'
                OwnerErrorPath = Join-Path $escapeRoot 'sibling.owner.error.json'
            }
        }
        'Untrusted early owner-error path' {
            Write-Contract -Path $Path -Overrides @{ OwnerErrorPath = $untrustedOwnerErrorPath }
        }
        'Existing stdout file' {
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
    $ownerOutput = [string[]]@(
        & $pinnedPwsh -NoProfile -NonInteractive -File $ownerPath -ContractPath $contractPath 2>&1)
    $exitCode = $LASTEXITCODE
    $afterIds = @(Get-MatchingChildProcessIds)

    $postTrustCases = [string[]]@(
        'Incorrect owner path', 'Incorrect owner hash', 'Incorrect child hash'
    )

    if ($exitCode -ne 125) {
        throw "$CaseName exited $exitCode instead of validation failure 125."
    }
    $phaseRejectionCases = [string[]]@(
        'Unsupported phase', 'Empty phase', 'Wrong-case phase', 'Non-string phase')
    if ($CaseName -in $phaseRejectionCases) {
        $expectedPhaseMessage = 'Phase must be Preflight, Assembler, or PostAudit.'
        if ($ownerOutput.Length -ne 1 -or
            -not [string]::Equals($ownerOutput[0], $expectedPhaseMessage, [StringComparison]::Ordinal)) {
            throw "$CaseName emitted an incorrect rejection message: $($ownerOutput -join ' | ')"
        }
    }

    if (Test-Path -LiteralPath $childMarkerPath) {
        throw "$CaseName launched the fixture child."
    }
    if ($afterIds.Count -ne 0 -or $beforeIds.Count -ne 0) {
        throw "$CaseName left a matching fixture child process."
    }
    if ($CaseName -in $postTrustCases) {
        $expectedMessages = @{
            'Incorrect owner path' = 'OwnerPath does not name this exact owner script.'
            'Incorrect owner hash' = 'Owner SHA-256 does not match.'
            'Incorrect child hash' = 'Child script SHA-256 does not match.'
        }
        $contractSha256 = (Get-FileHash -LiteralPath $contractPath -Algorithm SHA256).Hash
        [void](Read-OwnerError -Contract $writtenContract -ExpectedContractSha256 $contractSha256 `
            -ExpectedState 'Validating' -ExpectedMessage $expectedMessages[$CaseName] -ExpectedChildPid $null)
    }
    foreach ($evidencePath in $evidencePaths) {
        $allowedOwnerError = $CaseName -in $postTrustCases -and
            [string]::Equals($evidencePath, $writtenContract.OwnerErrorPath, [StringComparison]::OrdinalIgnoreCase)
        if ((Test-Path -LiteralPath $evidencePath) -and
            -not $preexistingEvidencePaths.Contains($evidencePath) -and
            -not $allowedOwnerError) {
            throw "$CaseName created evidence: $evidencePath"
        }
    }
    if ($CaseName -in $postTrustCases -and (Test-Path -LiteralPath $writtenContract.OwnerErrorPath -PathType Leaf)) {
        [IO.File]::Delete($writtenContract.OwnerErrorPath)
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
    if (Test-Path -LiteralPath $escapeRoot) {
        throw "Disposable sibling escape root already exists: $escapeRoot"
    }
    [IO.Directory]::CreateDirectory($evidenceRoot) | Out-Null
    [IO.Directory]::CreateDirectory($escapeRoot) | Out-Null
    [IO.File]::WriteAllText($escapeSentinelPath, 'CLEANUP_CONFINEMENT_SENTINEL', $utf8NoBom)
    $escapeFixtureCreated = $true
    $childScript = "[IO.File]::WriteAllText('$($childMarkerPath.Replace("'", "''"))', 'CHILD_LAUNCHED', [Text.UTF8Encoding]::new(`$false))`r`nexit 0`r`n"
    [IO.File]::WriteAllText($childPath, $childScript, $utf8NoBom)
    [IO.File]::WriteAllText($hardLinkSourcePath, $childScript, $utf8NoBom)
    [IO.File]::WriteAllText($successChildPath, @'
[Console]::Out.Write("OWNER_STDOUT_SENTINEL CHILD_PID=$PID")
[Console]::Error.Write('OWNER_STDERR_SENTINEL')
exit 0
'@, $utf8NoBom)
    [IO.File]::WriteAllText($failureChildPath, @'
[Console]::Error.Write('OWNER_FAILURE_SENTINEL')
exit 23
'@, $utf8NoBom)
    [IO.File]::WriteAllText($volumeChildPath, @'
$out = [byte[]]::new(1048576); [Array]::Fill[byte]($out, 0x4f)
$err = [byte[]]::new(1048576); [Array]::Fill[byte]($err, 0x45)
[Console]::OpenStandardOutput().Write($out, 0, $out.Length)
[Console]::OpenStandardError().Write($err, 0, $err.Length)
exit 0
'@, $utf8NoBom)
    [IO.File]::WriteAllText($mutationChildPath, @'
[IO.File]::AppendAllText($PSCommandPath, "`n# MUTATED", [Text.UTF8Encoding]::new($false))
[Console]::Out.Write('OWNER_MUTATION_STDOUT')
[Console]::Error.Write('OWNER_MUTATION_STDERR')
exit 0
'@, $utf8NoBom)
    $interruptionChildScript = @"
[IO.File]::WriteAllText('$($interruptionStartPath.Replace("'", "''"))', 'INTERRUPTION_CHILD_STARTED', [Text.UTF8Encoding]::new(`$false))
[Console]::Out.Write('INTERRUPTION_STDOUT')
[Console]::Error.Write('INTERRUPTION_STDERR')
Start-Sleep -Seconds 5
[IO.File]::WriteAllText('$($interruptionEndPath.Replace("'", "''"))', 'INTERRUPTION_CHILD_ENDED', [Text.UTF8Encoding]::new(`$false))
exit 0
"@
    [IO.File]::WriteAllText($interruptionChildPath, $interruptionChildScript, $utf8NoBom)
    [IO.Directory]::CreateDirectory($junctionTargetPath) | Out-Null
    [IO.Directory]::CreateDirectory((Join-Path $junctionTargetPath 'evidence')) | Out-Null
    if (-not $PhaseContractOnly) {
        New-Item -ItemType Junction -Path $junctionPath -Target $junctionTargetPath -ErrorAction Stop | Out-Null
        New-Item -ItemType SymbolicLink -Path $symbolicLinkChildPath -Target $childPath -ErrorAction Stop | Out-Null
        New-Item -ItemType HardLink -Path $hardLinkChildPath -Target $hardLinkSourcePath -ErrorAction Stop | Out-Null
    }

    if (-not (Test-Path -LiteralPath $ownerPath -PathType Leaf)) {
        throw "Owner script is missing: $ownerPath"
    }

    $contractCases = [Collections.Generic.List[string]]::new()
    if (-not $PhaseContractOnly) {
        foreach ($caseName in [string[]]@(
        'Unknown field',
        'Missing field',
        'Schema version',
        'String schema version',
        'Fractional schema version',
        'Non-string owner hash',
        'Arguments not array',
        'Arguments non-string element',
        'Duplicate PID and stdout paths',
        'Relative path',
        'Evidence path outside root',
        'Junction evidence component',
        'Symbolic-link child script',
        'Hard-linked child script',
        'Canonical dot-dot escape',
        'Sibling-prefix evidence escape',
        'Untrusted early owner-error path',
        'Incorrect owner path',
        'Incorrect owner hash',
        'Incorrect PowerShell hash',
        'Incorrect child hash',
        'Existing stdout file'
        )) {
            $contractCases.Add($caseName)
        }
    }
    foreach ($caseName in $contractCases) {
        Invoke-ContractCase -CaseName $caseName
    }

    Invoke-SuccessLifecycleTest
    Invoke-SupportedPhaseLifecycleTest -Phase 'Assembler'
    Invoke-SupportedPhaseLifecycleTest -Phase 'PostAudit'
    Invoke-MutationLifecycleTest
    foreach ($caseName in [string[]]@(
        'Unsupported phase',
        'Empty phase',
        'Wrong-case phase',
        'Non-string phase'
    )) {
        Invoke-ContractCase -CaseName $caseName
    }
    if (-not $PhaseContractOnly) {
        Write-Output 'PASS owner contract validation tests'
    }
    Write-Output 'PASS owner phase domain tests'
    if (-not $PhaseContractOnly) {
        Invoke-FailureLifecycleTest
        Invoke-VolumeLifecycleTest
        Write-Output 'PASS owner adversarial safety tests'
        Invoke-InterruptionLifecycleTest
        Write-Output 'PASS owner interruption classification tests'
    }
    Assert-ProductionV17PathsAbsent
    if (-not $PhaseContractOnly) {
        Write-Output 'PASS owner lifecycle tests'
    }
}
finally {
    $cleanupFailure = $null
    if (Test-Path -LiteralPath $testRoot) {
        try { Remove-Item -LiteralPath $testRoot -Recurse -Force }
        catch { $cleanupFailure = $_.Exception }
    }
    if ($escapeFixtureCreated) {
        if (-not (Test-Path -LiteralPath $escapeSentinelPath -PathType Leaf)) {
            $cleanupFailure = [InvalidOperationException]::new(
                'Test-root cleanup escaped into the sibling-prefix fixture.')
        }
        if (Test-Path -LiteralPath $escapeRoot) {
            try { Remove-Item -LiteralPath $escapeRoot -Recurse -Force }
            catch { if ($null -eq $cleanupFailure) { $cleanupFailure = $_.Exception } }
        }
    }
    if ($null -ne $cleanupFailure) {
        throw $cleanupFailure
    }
}
