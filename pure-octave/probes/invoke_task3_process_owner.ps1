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

    $canonicalOwnerPath = Get-CanonicalPath -Path $PSCommandPath
    if (-not [string]::Equals($canonicalOwnerPath, $contract.OwnerPath, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'OwnerPath does not name this exact owner script.'
    }
    if (-not [string]::Equals((Get-Sha256File -Path $canonicalOwnerPath), $contract.OwnerSha256, [StringComparison]::Ordinal)) {
        throw 'Owner SHA-256 does not match.'
    }
    if (-not [string]::Equals((Get-Sha256File -Path $pinnedPowerShellPath), $pinnedPowerShellSha256, [StringComparison]::Ordinal)) {
        throw 'Pinned PowerShell SHA-256 does not match.'
    }
    if (-not [string]::Equals((Get-Sha256File -Path $contract.ChildScriptPath), $contract.ChildScriptSha256, [StringComparison]::Ordinal)) {
        throw 'Child script SHA-256 does not match.'
    }

    return $contract
}

try {
    $contract = Read-StrictContract -Path $ContractPath
    [void]$contract
}
catch {
    [Console]::Error.WriteLine($_.Exception.Message)
    exit 125
}
