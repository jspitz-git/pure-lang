[CmdletBinding()]
param([Parameter(Mandatory = $true)][string] $ContractPath)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$utf8NoBom = [Text.UTF8Encoding]::new($false, $true)
$allowedFields = [string[]]@(
    'SchemaVersion','Phase','OwnerPath','OwnerSha256','PowerShellPath',
    'PowerShellSha256','ChildScriptPath','ChildScriptSha256','Arguments',
    'WorkingDirectory','EvidenceRoot','PidPath','StdoutPath','StderrPath',
    'OwnerExitPath','OwnerErrorPath'
)
$taskRoot = 'C:\tmp\todo51-task3'
$requiredWorkingDirectory = 'C:\pure-lang'
$pinnedPowerShellPath = 'C:\Program Files\WindowsApps\Microsoft.PowerShell_7.6.4.0_x64__8wekyb3d8bbwe\pwsh.exe'
$pinnedPowerShellSha256 = 'DB6DD81183FE57D22E03B911EC9A30A2FD7C40542E97743615355A6FB44F458F'

function Get-CanonicalPath([string] $Path) {
    if ([string]::IsNullOrEmpty($Path) -or -not [IO.Path]::IsPathFullyQualified($Path)) {
        throw "Path must be absolute: $Path"
    }
    $canonicalPath = [IO.Path]::GetFullPath($Path)
    if (-not [string]::Equals($canonicalPath, $Path, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Path is not canonical: $Path"
    }
    return $canonicalPath
}

function Assert-NoReparseOrLink([IO.FileSystemInfo] $Item, [string] $Path) {
    if (($Item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "Reparse point is not allowed: $Path"
    }
    $linkTypeProperty = $Item.PSObject.Properties['LinkType']
    if ($null -ne $linkTypeProperty -and -not [string]::IsNullOrEmpty([string]$linkTypeProperty.Value)) {
        throw "Link is not allowed: $Path"
    }
}

function Assert-RegularNonReparseFile([string] $Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Regular file is required: $Path"
    }
    $item = Get-Item -LiteralPath $Path -Force
    if ($item -isnot [IO.FileInfo]) {
        throw "Regular file is required: $Path"
    }
    Assert-NoReparseOrLink -Item $item -Path $Path
}

function Assert-RegularNonReparseDirectory([string] $Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        throw "Regular directory is required: $Path"
    }
    $item = Get-Item -LiteralPath $Path -Force
    if ($item -isnot [IO.DirectoryInfo]) {
        throw "Regular directory is required: $Path"
    }
    Assert-NoReparseOrLink -Item $item -Path $Path
}

function Assert-NoReparseComponents([string] $Path, [bool] $AllowMissingLeaf = $false) {
    $root = [IO.Path]::GetPathRoot($Path)
    Assert-RegularNonReparseDirectory -Path $root
    $remainingPath = $Path.Substring($root.Length)
    $components = $remainingPath.Split([char[]]@([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar), [StringSplitOptions]::RemoveEmptyEntries)
    $currentPath = $root
    for ($index = 0; $index -lt $components.Length; $index++) {
        $currentPath = Join-Path $currentPath $components[$index]
        $item = Get-Item -LiteralPath $currentPath -Force -ErrorAction SilentlyContinue
        if ($null -eq $item) {
            if ($AllowMissingLeaf -and $index -eq ($components.Length - 1)) {
                return
            }
            throw "Path component does not exist: $currentPath"
        }
        Assert-NoReparseOrLink -Item $item -Path $currentPath
    }
}

function Get-Sha256File([string] $Path) {
    Assert-RegularNonReparseFile -Path $Path
    Assert-NoReparseComponents -Path $Path
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
}

function Get-Sha256Bytes([byte[]] $Bytes) {
    return [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($Bytes))
}

function Write-AtomicUtf8([string] $Path, [string] $Text) {
    $directoryPath = [IO.Path]::GetDirectoryName($Path)
    $temporaryName = '.' + [IO.Path]::GetFileName($Path) + '.' + [guid]::NewGuid().ToString('N') + '.tmp'
    $temporaryPath = Join-Path $directoryPath $temporaryName
    $temporaryCreated = $false
    $renamed = $false
    $atomicStream = $null
    try {
        $bytes = $utf8NoBom.GetBytes($Text)
        $atomicStream = [IO.File]::Open($temporaryPath, 'CreateNew', 'Write', 'None')
        $temporaryCreated = $true
        $atomicStream.Write($bytes, 0, $bytes.Length)
        $atomicStream.Flush($true)
        $atomicStream.Dispose()
        $atomicStream = $null
        [IO.File]::Move($temporaryPath, $Path, $false)
        $renamed = $true
    }
    finally {
        if ($null -ne $atomicStream) {
            $atomicStream.Dispose()
        }
        if ($temporaryCreated -and -not $renamed -and (Test-Path -LiteralPath $temporaryPath)) {
            [IO.File]::Delete($temporaryPath)
        }
    }
}

function Close-CaptureStreamBestEffort([IO.FileStream] $CaptureStream) {
    if ($null -eq $CaptureStream) { return }
    try { $CaptureStream.Flush($true) } catch { }
    try { $CaptureStream.Dispose() } catch { }
}

function Wait-NaturalExitAndCaptureTasks(
    [Diagnostics.Process] $ChildProcess,
    [IO.Stream] $StdoutSource,
    [IO.Stream] $StderrSource,
    [Threading.Tasks.Task] $StdoutCopy,
    [Threading.Tasks.Task] $StderrCopy
) {
    $stdoutCompletion = $StdoutCopy
    $stderrCompletion = $StderrCopy
    if ($null -eq $stdoutCompletion -and $null -ne $StdoutSource) {
        $stdoutCompletion = $StdoutSource.CopyToAsync([IO.Stream]::Null)
    }
    if ($null -eq $stderrCompletion -and $null -ne $StderrSource) {
        $stderrCompletion = $StderrSource.CopyToAsync([IO.Stream]::Null)
    }

    $copyFailure = $null
    do {
        if ($null -ne $StdoutCopy -and
            [object]::ReferenceEquals($stdoutCompletion, $StdoutCopy) -and
            $StdoutCopy.IsFaulted) {
            if ($null -eq $copyFailure) { $copyFailure = $StdoutCopy.Exception.GetBaseException() }
            $stdoutCompletion = $StdoutSource.CopyToAsync([IO.Stream]::Null)
        }
        if ($null -ne $StderrCopy -and
            [object]::ReferenceEquals($stderrCompletion, $StderrCopy) -and
            $StderrCopy.IsFaulted) {
            if ($null -eq $copyFailure) { $copyFailure = $StderrCopy.Exception.GetBaseException() }
            $stderrCompletion = $StderrSource.CopyToAsync([IO.Stream]::Null)
        }
        $childHasExited = $ChildProcess.WaitForExit(50)
    } while (-not $childHasExited)

    if ($null -ne $StdoutCopy -and
        [object]::ReferenceEquals($stdoutCompletion, $StdoutCopy) -and
        $StdoutCopy.IsFaulted) {
        if ($null -eq $copyFailure) { $copyFailure = $StdoutCopy.Exception.GetBaseException() }
        $stdoutCompletion = $StdoutSource.CopyToAsync([IO.Stream]::Null)
    }
    if ($null -ne $StderrCopy -and
        [object]::ReferenceEquals($stderrCompletion, $StderrCopy) -and
        $StderrCopy.IsFaulted) {
        if ($null -eq $copyFailure) { $copyFailure = $StderrCopy.Exception.GetBaseException() }
        $stderrCompletion = $StderrSource.CopyToAsync([IO.Stream]::Null)
    }

    $completionTasks = [Collections.Generic.List[Threading.Tasks.Task]]::new()
    if ($null -ne $stdoutCompletion) { $completionTasks.Add($stdoutCompletion) }
    if ($null -ne $stderrCompletion) { $completionTasks.Add($stderrCompletion) }
    if ($completionTasks.Count -gt 0) {
        [Threading.Tasks.Task]::WaitAll($completionTasks.ToArray())
    }
    if ($null -ne $copyFailure) { throw $copyFailure }
}

function Test-EqualOrDescendant([string] $Path, [string] $Root) {
    if ([string]::Equals($Path, $Root, [StringComparison]::OrdinalIgnoreCase)) {
        return $true
    }
    $prefix = $Root + [IO.Path]::DirectorySeparatorChar
    return $Path.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)
}

function Test-StrictDescendant([string] $Path, [string] $Root) {
    $prefix = $Root + [IO.Path]::DirectorySeparatorChar
    return $Path.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)
}

function Assert-ExactString([object] $Value, [string] $FieldName) {
    if ($Value -isnot [string]) {
        throw "$FieldName must be a JSON string."
    }
}

function Read-StrictContract([string] $Path) {
    $canonicalContractPath = Get-CanonicalPath -Path $Path
    $canonicalTaskRoot = Get-CanonicalPath -Path $taskRoot
    if (-not (Test-EqualOrDescendant -Path $canonicalContractPath -Root $canonicalTaskRoot)) {
        throw "Contract path escapes the task root: $canonicalContractPath"
    }
    Assert-RegularNonReparseFile -Path $canonicalContractPath
    Assert-NoReparseComponents -Path $canonicalContractPath

    $bytes = [IO.File]::ReadAllBytes($canonicalContractPath)
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xef -and $bytes[1] -eq 0xbb -and $bytes[2] -eq 0xbf) {
        throw 'Contract JSON must not have a UTF-8 BOM.'
    }
    try {
        $jsonText = $utf8NoBom.GetString($bytes)
        $contract = $jsonText | ConvertFrom-Json -NoEnumerate -ErrorAction Stop
    }
    catch {
        throw "Contract JSON is invalid: $($_.Exception.Message)"
    }
    if ($contract -isnot [PSCustomObject]) {
        throw 'Contract JSON must contain exactly one object.'
    }

    $actualFields = [string[]]@($contract.PSObject.Properties.Name | Sort-Object)
    $expectedFields = [string[]]@($allowedFields | Sort-Object)
    if ($actualFields.Length -ne $expectedFields.Length) {
        throw 'Contract JSON fields do not match the closed schema.'
    }
    for ($index = 0; $index -lt $expectedFields.Length; $index++) {
        if (-not [string]::Equals($actualFields[$index], $expectedFields[$index], [StringComparison]::Ordinal)) {
            throw 'Contract JSON fields do not match the closed schema.'
        }
    }

    if ($contract.SchemaVersion -isnot [long] -or $contract.SchemaVersion -ne 1) {
        throw 'SchemaVersion must be the integer 1.'
    }
    if ($contract.Phase -isnot [string] -or $contract.Phase -ne 'Preflight') {
        throw 'Phase must be Preflight.'
    }
    foreach ($fieldName in [string[]]@(
        'OwnerPath', 'OwnerSha256', 'PowerShellPath', 'PowerShellSha256',
        'ChildScriptPath', 'ChildScriptSha256', 'WorkingDirectory', 'EvidenceRoot',
        'PidPath', 'StdoutPath', 'StderrPath', 'OwnerExitPath', 'OwnerErrorPath'
    )) {
        Assert-ExactString -Value $contract.$fieldName -FieldName $fieldName
    }
    if ($contract.Arguments -isnot [object[]]) {
        throw 'Arguments must be a JSON array of strings.'
    }
    foreach ($argument in $contract.Arguments) {
        if ($argument -isnot [string]) {
            throw 'Arguments must be a JSON array of strings.'
        }
    }

    $contract.OwnerPath = Get-CanonicalPath -Path $contract.OwnerPath
    $contract.PowerShellPath = Get-CanonicalPath -Path $contract.PowerShellPath
    $contract.ChildScriptPath = Get-CanonicalPath -Path $contract.ChildScriptPath
    $contract.WorkingDirectory = Get-CanonicalPath -Path $contract.WorkingDirectory
    $contract.EvidenceRoot = Get-CanonicalPath -Path $contract.EvidenceRoot
    $contract.PidPath = Get-CanonicalPath -Path $contract.PidPath
    $contract.StdoutPath = Get-CanonicalPath -Path $contract.StdoutPath
    $contract.StderrPath = Get-CanonicalPath -Path $contract.StderrPath
    $contract.OwnerExitPath = Get-CanonicalPath -Path $contract.OwnerExitPath
    $contract.OwnerErrorPath = Get-CanonicalPath -Path $contract.OwnerErrorPath

    if (-not (Test-EqualOrDescendant -Path $contract.EvidenceRoot -Root $canonicalTaskRoot)) {
        throw "EvidenceRoot escapes the task root: $($contract.EvidenceRoot)"
    }
    if (-not (Test-StrictDescendant -Path $contract.ChildScriptPath -Root $canonicalTaskRoot)) {
        throw "ChildScriptPath escapes the task root: $($contract.ChildScriptPath)"
    }
    if (-not [string]::Equals($contract.WorkingDirectory, $requiredWorkingDirectory, [StringComparison]::OrdinalIgnoreCase)) {
        throw "WorkingDirectory must be $requiredWorkingDirectory."
    }
    if (-not [string]::Equals($contract.PowerShellPath, $pinnedPowerShellPath, [StringComparison]::OrdinalIgnoreCase) -or
        -not [string]::Equals($contract.PowerShellSha256, $pinnedPowerShellSha256, [StringComparison]::Ordinal)) {
        throw 'PowerShell path or SHA-256 does not match the pinned literal.'
    }

    Assert-RegularNonReparseDirectory -Path $contract.EvidenceRoot
    Assert-NoReparseComponents -Path $contract.EvidenceRoot
    Assert-RegularNonReparseDirectory -Path $contract.WorkingDirectory
    Assert-NoReparseComponents -Path $contract.WorkingDirectory
    Assert-RegularNonReparseFile -Path $contract.ChildScriptPath
    Assert-NoReparseComponents -Path $contract.ChildScriptPath

    $evidencePaths = [string[]]@(
        $contract.PidPath, $contract.StdoutPath, $contract.StderrPath,
        $contract.OwnerExitPath, $contract.OwnerErrorPath
    )
    $evidencePrefix = $contract.EvidenceRoot + [IO.Path]::DirectorySeparatorChar
    $uniqueEvidencePaths = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($evidencePath in $evidencePaths) {
        if (-not $evidencePath.StartsWith($evidencePrefix, [StringComparison]::OrdinalIgnoreCase)) {
            throw "Evidence path escapes EvidenceRoot: $evidencePath"
        }
        if (-not $uniqueEvidencePaths.Add($evidencePath)) {
            throw "Duplicate evidence path: $evidencePath"
        }
        Assert-NoReparseComponents -Path $evidencePath -AllowMissingLeaf $true
        if (Test-Path -LiteralPath $evidencePath) {
            throw "Evidence path already exists: $evidencePath"
        }
    }

    $script:trustedOwnerErrorPath = $contract.OwnerErrorPath
    $script:trustedPhase = $contract.Phase
    $script:initialContractSha256 = Get-Sha256Bytes -Bytes $bytes
    $script:ownerErrorTrusted = $true

    $canonicalOwnerPath = Get-CanonicalPath -Path $PSCommandPath
    if (-not [string]::Equals($canonicalOwnerPath, $contract.OwnerPath, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'OwnerPath does not name this exact owner script.'
    }
    $actualOwnerSha256 = Get-Sha256File -Path $canonicalOwnerPath
    if (-not [string]::Equals($actualOwnerSha256, $contract.OwnerSha256, [StringComparison]::Ordinal)) {
        throw 'Owner SHA-256 does not match.'
    }
    $actualPowerShellSha256 = Get-Sha256File -Path $pinnedPowerShellPath
    if (-not [string]::Equals($actualPowerShellSha256, $pinnedPowerShellSha256, [StringComparison]::Ordinal)) {
        throw 'Pinned PowerShell SHA-256 does not match.'
    }
    $actualChildScriptSha256 = Get-Sha256File -Path $contract.ChildScriptPath
    if (-not [string]::Equals($actualChildScriptSha256, $contract.ChildScriptSha256, [StringComparison]::Ordinal)) {
        throw 'Child script SHA-256 does not match.'
    }

    $script:validatedContractPath = $canonicalContractPath
    $script:validatedOwnerSha256 = $actualOwnerSha256
    $script:validatedContractSha256 = $initialContractSha256
    $script:validatedPowerShellSha256 = $actualPowerShellSha256
    $script:validatedChildScriptSha256 = $actualChildScriptSha256

    return $contract
}

$state = 'Validating'
$ownerErrorTrusted = $false
$contract = $null
$childProcess = $null
$childStarted = $false
$childPid = $null
$stdoutCopy = $null
$stderrCopy = $null
$stdoutSource = $null
$stderrSource = $null
$stdoutStream = $null
$stderrStream = $null
$trustedOwnerErrorPath = $null
$trustedPhase = $null
$initialContractSha256 = $null
$ownerProcessExitCode = 125

try {
    $contract = Read-StrictContract -Path $ContractPath
    $initialOwnerSha256 = $validatedOwnerSha256
    $initialPowerShellSha256 = $validatedPowerShellSha256
    $initialChildScriptSha256 = $validatedChildScriptSha256

    $state = 'EvidenceReady'
    $stdoutStream = [IO.File]::Open($contract.StdoutPath, 'CreateNew', 'Write', 'Read')
    $stderrStream = [IO.File]::Open($contract.StderrPath, 'CreateNew', 'Write', 'Read')
    $startInfo = [Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $contract.PowerShellPath
    $startInfo.WorkingDirectory = $contract.WorkingDirectory
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    [void] $startInfo.ArgumentList.Add('-NoProfile')
    [void] $startInfo.ArgumentList.Add('-NonInteractive')
    [void] $startInfo.ArgumentList.Add('-File')
    [void] $startInfo.ArgumentList.Add($contract.ChildScriptPath)
    foreach ($argument in [string[]] $contract.Arguments) {
        [void] $startInfo.ArgumentList.Add($argument)
    }
    $childProcess = [Diagnostics.Process]::new()
    $childProcess.StartInfo = $startInfo
    if (-not $childProcess.Start()) { throw 'Process.Start returned false.' }
    $childStarted = $true
    $state = 'Started'
    $stdoutSource = $childProcess.StandardOutput.BaseStream
    $stderrSource = $childProcess.StandardError.BaseStream
    $stdoutCopy = $stdoutSource.CopyToAsync($stdoutStream)
    $stderrCopy = $stderrSource.CopyToAsync($stderrStream)
    $childPid = $childProcess.Id
    Write-AtomicUtf8 -Path $contract.PidPath -Text ([string]$childPid + "`n")
    $state = 'Draining'
    Wait-NaturalExitAndCaptureTasks -ChildProcess $childProcess `
        -StdoutSource $stdoutSource -StderrSource $stderrSource `
        -StdoutCopy $stdoutCopy -StderrCopy $stderrCopy
    $childExitCode = $childProcess.ExitCode

    $finalOwnerSha256 = Get-Sha256File -Path $contract.OwnerPath
    $finalContractSha256 = Get-Sha256File -Path $validatedContractPath
    $finalPowerShellSha256 = Get-Sha256File -Path $contract.PowerShellPath
    $finalChildScriptSha256 = Get-Sha256File -Path $contract.ChildScriptPath
    if (-not [string]::Equals($finalOwnerSha256, $initialOwnerSha256, [StringComparison]::Ordinal) -or
        -not [string]::Equals($finalContractSha256, $initialContractSha256, [StringComparison]::Ordinal) -or
        -not [string]::Equals($finalPowerShellSha256, $initialPowerShellSha256, [StringComparison]::Ordinal) -or
        -not [string]::Equals($finalChildScriptSha256, $initialChildScriptSha256, [StringComparison]::Ordinal)) {
        throw 'Validated owner, contract, PowerShell executable, or child script changed during execution.'
    }

    $stdoutStream.Flush($true)
    $stderrStream.Flush($true)
    $stdoutStream.Dispose()
    $stdoutStream = $null
    $stderrStream.Dispose()
    $stderrStream = $null
    $childProcess.Dispose()
    $childProcess = $null
    $state = 'Completed'
    $ownerExit = [ordered]@{
        SchemaVersion = 1
        Phase = $contract.Phase
        State = $state
        ChildPid = $childPid
        ChildExitCode = $childExitCode
        OwnerSha256 = $initialOwnerSha256
        ContractSha256 = $initialContractSha256
    }
    Write-AtomicUtf8 -Path $contract.OwnerExitPath -Text (($ownerExit | ConvertTo-Json -Compress) + "`n")
    $ownerProcessExitCode = $childExitCode
}
catch {
    $failureException = $_.Exception
    if ($childStarted -and $null -ne $childProcess) {
        try {
            Wait-NaturalExitAndCaptureTasks -ChildProcess $childProcess `
                -StdoutSource $stdoutSource -StderrSource $stderrSource `
                -StdoutCopy $stdoutCopy -StderrCopy $stderrCopy
        } catch { }
    }
    Close-CaptureStreamBestEffort -CaptureStream $stdoutStream
    Close-CaptureStreamBestEffort -CaptureStream $stderrStream
    $stdoutStream = $null
    $stderrStream = $null

    if ($ownerErrorTrusted) {
        $ownerError = [ordered]@{
            SchemaVersion = 1
            Phase = $trustedPhase
            State = $state
            ExceptionType = $failureException.GetType().FullName
            Message = $failureException.Message
            ChildPid = $childPid
            ContractSha256 = $initialContractSha256
        }
        try {
            Write-AtomicUtf8 -Path $trustedOwnerErrorPath -Text (($ownerError | ConvertTo-Json -Compress) + "`n")
        }
        catch {
            [Console]::Error.WriteLine($failureException.Message)
            [Console]::Error.WriteLine("Could not write owner-error evidence: $($_.Exception.Message)")
        }
    }
    else {
        [Console]::Error.WriteLine($failureException.Message)
    }
    $ownerProcessExitCode = 125
}
finally {
    Close-CaptureStreamBestEffort -CaptureStream $stdoutStream
    Close-CaptureStreamBestEffort -CaptureStream $stderrStream
    if ($null -ne $childProcess) {
        try { $childProcess.Dispose() } catch { }
    }
}

exit $ownerProcessExitCode
