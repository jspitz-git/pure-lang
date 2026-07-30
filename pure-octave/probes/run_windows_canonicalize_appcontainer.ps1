<#
.SYNOPSIS
Build and run the Windows canonicalization probe in ordinary and AppContainer
modes, assert the expected results, and remove the disposable stage.

.EXAMPLE
pwsh -NoProfile -File .\run_windows_canonicalize_appcontainer.ps1 `
    -ScratchRoot C:\pure-lang
#>

[CmdletBinding()]
param(
    [string] $ScratchRoot = "",
    [string] $FixturePath = "",
    [string] $VsWherePath =
        "C:\Program Files (x86)\Microsoft Visual Studio\Installer\vswhere.exe"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-CanonicalExistingPath {
    param([Parameter(Mandatory = $true)][string] $Path)

    $item = Get-Item -Force -LiteralPath $Path -ErrorAction Stop
    return [System.IO.Path]::GetFullPath($item.FullName)
}

function Assert-StrictDescendant {
    param(
        [Parameter(Mandatory = $true)][string] $Child,
        [Parameter(Mandatory = $true)][string] $Parent,
        [Parameter(Mandatory = $true)][string] $Label
    )

    $childFull = [System.IO.Path]::GetFullPath($Child)
    $parentFull = ([System.IO.Path]::GetFullPath($Parent)).TrimEnd(
        [System.IO.Path]::DirectorySeparatorChar,
        [System.IO.Path]::AltDirectorySeparatorChar)
    $prefix = $parentFull + [System.IO.Path]::DirectorySeparatorChar
    if ($childFull.Equals($parentFull,
                          [System.StringComparison]::OrdinalIgnoreCase) -or
        -not $childFull.StartsWith(
            $prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "$Label is not a strict descendant of $parentFull`: $childFull"
    }
}

function Assert-NoReparseComponents {
    param([Parameter(Mandatory = $true)][string] $Path)

    $current = Get-Item -Force -LiteralPath $Path -ErrorAction Stop
    while ($null -ne $current) {
        if (($current.Attributes -band
             [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "Reparse component rejected: $($current.FullName)"
        }

        $parentPath = Split-Path -Parent $current.FullName
        if ([string]::IsNullOrEmpty($parentPath) -or
            $parentPath.Equals(
                $current.FullName,
                [System.StringComparison]::OrdinalIgnoreCase)) {
            break
        }
        $current = Get-Item -Force -LiteralPath $parentPath -ErrorAction Stop
    }
}

function Assert-NoReparseTree {
    param([Parameter(Mandatory = $true)][string] $Root)

    Assert-NoReparseComponents -Path $Root
    foreach ($item in Get-ChildItem -Force -Recurse -LiteralPath $Root) {
        if (($item.Attributes -band
             [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "Reparse entry rejected: $($item.FullName)"
        }
    }
}

function Assert-ExitCode {
    param(
        [Parameter(Mandatory = $true)][int] $Actual,
        [Parameter(Mandatory = $true)][int] $Expected,
        [Parameter(Mandatory = $true)][string] $Label
    )

    if ($Actual -ne $Expected) {
        throw "$Label exit code $Actual; expected $Expected"
    }
}

function Assert-OutputMatch {
    param(
        [Parameter(Mandatory = $true)][string] $Text,
        [Parameter(Mandatory = $true)][string] $Pattern,
        [Parameter(Mandatory = $true)][string] $Label
    )

    if ($Text -notmatch $Pattern) {
        throw "$Label did not match /$Pattern/`n$Text"
    }
}

function ConvertFrom-ProbeOutput {
    param([Parameter(Mandatory = $true)][string] $Text)

    $values = @{}
    foreach ($line in ($Text -split "\r?\n")) {
        if ([string]::IsNullOrEmpty($line)) {
            continue
        }
        if ($line -notmatch "^([^=]+)=(.*)$") {
            throw "Malformed probe output line: $line"
        }
        $key = $Matches[1]
        if ($values.ContainsKey($key)) {
            throw "Duplicate probe output key: $key"
        }
        $values[$key] = $Matches[2]
    }
    return $values
}

function Get-RequiredOutputValue {
    param(
        [Parameter(Mandatory = $true)][hashtable] $Values,
        [Parameter(Mandatory = $true)][string] $Key,
        [Parameter(Mandatory = $true)][string] $Label
    )

    if (-not $Values.ContainsKey($Key) -or
        [string]::IsNullOrEmpty([string] $Values[$Key])) {
        throw "$Label is missing or empty: $Key"
    }
    return [string] $Values[$Key]
}

function Assert-WindowsPathEqual {
    param(
        [Parameter(Mandatory = $true)][string] $Actual,
        [Parameter(Mandatory = $true)][string] $Expected,
        [Parameter(Mandatory = $true)][string] $Label
    )

    if (-not [string]::Equals(
        $Actual, $Expected, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "$Label path mismatch`nactual:   $Actual`nexpected: $Expected"
    }
}

$repoRoot = [System.IO.Path]::GetFullPath(
    (Join-Path $PSScriptRoot "..\.."))
if ([string]::IsNullOrWhiteSpace($ScratchRoot)) {
    $ScratchRoot = $repoRoot
}
if ([string]::IsNullOrWhiteSpace($FixturePath)) {
    $FixturePath = Join-Path $PSScriptRoot "embed_probe.cc"
}

$scratchCanonical = Get-CanonicalExistingPath -Path $ScratchRoot
$sourceCanonical = Get-CanonicalExistingPath -Path (
    Join-Path $PSScriptRoot "windows_canonicalize_appcontainer.c")
$fixtureCanonical = Get-CanonicalExistingPath -Path $FixturePath
Assert-NoReparseComponents -Path $scratchCanonical
Assert-NoReparseComponents -Path $sourceCanonical
Assert-NoReparseComponents -Path $fixtureCanonical

$runId = [guid]::NewGuid().ToString("N")
$profileName = "PureTask51.$runId"
$stageRoot = [System.IO.Path]::GetFullPath(
    (Join-Path $scratchCanonical ".task1-harness-$runId"))
Assert-StrictDescendant -Child $stageRoot -Parent $scratchCanonical `
    -Label "stage"

$binDirectory = Join-Path $stageRoot "bin"
$fixtureDirectory = Join-Path $stageRoot "fixture"
$workDirectory = Join-Path $stageRoot "work"
$probePath = Join-Path $binDirectory "windows_canonicalize_appcontainer.exe"
$objectPath = Join-Path $binDirectory "windows_canonicalize_appcontainer.obj"
$targetPath = Join-Path $fixtureDirectory "embed_probe.cc"
$ordinaryOutputPath = Join-Path $workDirectory "ordinary.txt"
$packagedOutputPath = Join-Path $workDirectory "appcontainer.txt"
$junctionDirectory = Join-Path $stageRoot "junction"
$junctionOutputPath = Join-Path $workDirectory "junction.txt"
$forcedFallbackOutputPath = Join-Path $workDirectory "forced-fallback.txt"
$volumeMutationOutputPath = Join-Path $workDirectory "volume-mismatch.txt"
$reparseMutationOutputPath = Join-Path $workDirectory "reparse.txt"
$pathMutationOutputPath = Join-Path $workDirectory "malformed-path.txt"
$maximumInfoOutputPath = Join-Path $workDirectory "file-name-info-max.txt"

$profileMayExist = $false
$probeAvailable = $false
$ordinaryOutput = ""
$packagedOutput = ""
$packagedConsole = ""
$cleanupConsole = ""
$scratchAclBefore = (Get-Acl -LiteralPath $scratchCanonical).Sddl

try {
    New-Item -ItemType Directory -Path $binDirectory, $fixtureDirectory,
        $workDirectory | Out-Null
    Copy-Item -LiteralPath $fixtureCanonical -Destination $targetPath

    $stageCanonical = Get-CanonicalExistingPath -Path $stageRoot
    $binCanonical = Get-CanonicalExistingPath -Path $binDirectory
    $fixtureDirectoryCanonical =
        Get-CanonicalExistingPath -Path $fixtureDirectory
    $workCanonical = Get-CanonicalExistingPath -Path $workDirectory
    $targetCanonical = Get-CanonicalExistingPath -Path $targetPath

    Assert-StrictDescendant -Child $stageCanonical -Parent $scratchCanonical `
        -Label "canonical stage"
    Assert-StrictDescendant -Child $binCanonical -Parent $stageCanonical `
        -Label "bin"
    Assert-StrictDescendant -Child $fixtureDirectoryCanonical `
        -Parent $stageCanonical -Label "fixture directory"
    Assert-StrictDescendant -Child $workCanonical -Parent $stageCanonical `
        -Label "work"
    Assert-StrictDescendant -Child $targetCanonical -Parent $stageCanonical `
        -Label "target"
    Assert-NoReparseTree -Root $stageCanonical

    $targetVolumeRoot = [System.IO.Path]::GetPathRoot($targetCanonical)
    if ($targetVolumeRoot -notmatch "^[A-Za-z]:\\$") {
        throw "Probe target must be on a local drive: $targetCanonical"
    }
    $expectedFinalPath = "\\?\$targetCanonical"
    $expectedFileNameInfoPath =
        "\" + $targetCanonical.Substring($targetVolumeRoot.Length)
    $ordinaryTargetArgument = $targetCanonical
    $packagedTargetArgument = $targetCanonical
    Assert-WindowsPathEqual -Actual $packagedTargetArgument `
        -Expected $ordinaryTargetArgument -Label "probe invocation target"

    if (-not (Test-Path -LiteralPath $VsWherePath -PathType Leaf)) {
        throw "vswhere not found: $VsWherePath"
    }
    $installationPath = (& $VsWherePath -latest -products * `
        -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 `
        -property installationPath | Select-Object -First 1)
    if ([string]::IsNullOrWhiteSpace($installationPath)) {
        throw "Visual Studio C++ Build Tools installation not found"
    }
    $vcvarsPath = Join-Path $installationPath `
        "VC\Auxiliary\Build\vcvars64.bat"
    if (-not (Test-Path -LiteralPath $vcvarsPath -PathType Leaf)) {
        throw "vcvars64.bat not found: $vcvarsPath"
    }

    $buildCommand =
        "`"$vcvarsPath`" >nul && cl /nologo /W4 /WX /TC " +
        "/Fo:`"$objectPath`" /Fe:`"$probePath`" `"$sourceCanonical`" " +
        "/link userenv.lib advapi32.lib"
    & "$env:SystemRoot\System32\cmd.exe" /d /s /c $buildCommand
    Assert-ExitCode -Actual $LASTEXITCODE -Expected 0 -Label "MSVC build"

    $probeCanonical = Get-CanonicalExistingPath -Path $probePath
    Assert-StrictDescendant -Child $probeCanonical -Parent $stageCanonical `
        -Label "probe"
    Assert-NoReparseTree -Root $stageCanonical
    $probeAvailable = $true

    & $probeCanonical --probe $ordinaryTargetArgument `
        $ordinaryOutputPath
    $ordinaryExit = $LASTEXITCODE
    Assert-ExitCode -Actual $ordinaryExit -Expected 0 `
        -Label "ordinary probe"
    $ordinaryOutput = Get-Content -Raw -LiteralPath $ordinaryOutputPath

    Assert-OutputMatch -Text $ordinaryOutput `
        -Pattern "(?m)^CREATEFILE_HANDLE=1 ERROR=0\r?$" `
        -Label "ordinary CreateFileW"
    Assert-OutputMatch -Text $ordinaryOutput `
        -Pattern "(?m)^GETFINAL_NORMALIZED_LENGTH=[1-9][0-9]* ERROR=0 NONEMPTY=1\r?$" `
        -Label "ordinary normalized path"
    Assert-OutputMatch -Text $ordinaryOutput `
        -Pattern "(?m)^GETFINAL_OPENED_LENGTH=[1-9][0-9]* ERROR=0 NONEMPTY=1\r?$" `
        -Label "ordinary opened path"
    Assert-OutputMatch -Text $ordinaryOutput `
        -Pattern "(?m)^FILE_NAME_INFO_OK=1 LENGTH=[1-9][0-9]* ERROR=0 NONEMPTY=1\r?$" `
        -Label "ordinary FileNameInfo"
    Assert-OutputMatch -Text $ordinaryOutput `
        -Pattern "(?m)^READFILE=1 ERROR=0 BYTES=1 BYTE=[0-9]+\r?$" `
        -Label "ordinary ReadFile"
    Assert-OutputMatch -Text $ordinaryOutput `
        -Pattern "(?m)^ENUMERATION=1 ERROR=0\r?$" `
        -Label "ordinary enumeration"

    $ordinaryValues = ConvertFrom-ProbeOutput -Text $ordinaryOutput
    $ordinaryNormalizedPath = Get-RequiredOutputValue `
        -Values $ordinaryValues -Key "GETFINAL_NORMALIZED_PATH" `
        -Label "ordinary normalized path"
    $ordinaryOpenedPath = Get-RequiredOutputValue `
        -Values $ordinaryValues -Key "GETFINAL_OPENED_PATH" `
        -Label "ordinary opened path"
    $ordinaryFileNameInfoPath = Get-RequiredOutputValue `
        -Values $ordinaryValues -Key "FILE_NAME_INFO_PATH" `
        -Label "ordinary FileNameInfo path"
    Assert-WindowsPathEqual -Actual $ordinaryNormalizedPath `
        -Expected $expectedFinalPath -Label "ordinary normalized"
    Assert-WindowsPathEqual -Actual $ordinaryOpenedPath `
        -Expected $expectedFinalPath -Label "ordinary opened"
    Assert-WindowsPathEqual -Actual $ordinaryFileNameInfoPath `
        -Expected $expectedFileNameInfoPath -Label "ordinary FileNameInfo"
    Assert-OutputMatch -Text $ordinaryOutput `
        -Pattern "(?m)^CANDIDATE_SOURCE=NORMALIZED ERROR=0 NONEMPTY=1\r?$" `
        -Label "ordinary candidate"
    $ordinaryCandidatePath = Get-RequiredOutputValue `
        -Values $ordinaryValues -Key "CANDIDATE_PATH" `
        -Label "ordinary candidate path"
    Assert-WindowsPathEqual -Actual $ordinaryCandidatePath `
        -Expected $expectedFinalPath -Label "ordinary candidate"

    & $probeCanonical --probe-mutation force-fallback `
        $ordinaryTargetArgument $forcedFallbackOutputPath
    Assert-ExitCode -Actual $LASTEXITCODE -Expected 0 `
        -Label "forced safe fallback"
    $forcedFallbackOutput = Get-Content -Raw -LiteralPath $forcedFallbackOutputPath
    Assert-OutputMatch -Text $forcedFallbackOutput `
        -Pattern "(?m)^CANDIDATE_SOURCE=FALLBACK ERROR=0 NONEMPTY=1\r?$" `
        -Label "forced safe fallback"
    $forcedFallbackValues = ConvertFrom-ProbeOutput -Text $forcedFallbackOutput
    $forcedFallbackPath = Get-RequiredOutputValue `
        -Values $forcedFallbackValues -Key "CANDIDATE_PATH" `
        -Label "forced safe fallback path"
    Assert-WindowsPathEqual -Actual $forcedFallbackPath `
        -Expected $expectedFinalPath -Label "forced safe fallback"
    New-Item -ItemType Junction -Path $junctionDirectory `
        -Target $fixtureDirectoryCanonical | Out-Null
    if (((Get-Item -Force -LiteralPath $junctionDirectory).Attributes -band
         [System.IO.FileAttributes]::ReparsePoint) -eq 0) {
        throw "junction fixture is not a reparse point"
    }
    $junctionTarget = Join-Path $junctionDirectory "embed_probe.cc"
    & $probeCanonical --probe-mutation force-fallback `
        $junctionTarget $junctionOutputPath
    Assert-ExitCode -Actual $LASTEXITCODE -Expected 25 `
        -Label "real junction fail-closed fallback"
    $junctionOutput = Get-Content -Raw -LiteralPath $junctionOutputPath
    Assert-OutputMatch -Text $junctionOutput `
        -Pattern "(?m)^CANDIDATE_SOURCE=REJECTED ERROR=5 NONEMPTY=0\r?$" `
        -Label "real junction fail-closed fallback"
    $junctionValues = ConvertFrom-ProbeOutput -Text $junctionOutput
    if ($junctionValues["CANDIDATE_PATH"] -ne "") {
        throw "real junction returned a candidate path"
    }


    $mutationCases = @(
        @("volume-mismatch", $volumeMutationOutputPath),
        @("reparse", $reparseMutationOutputPath),
        @("malformed-path", $pathMutationOutputPath)
    )
    foreach ($mutationCase in $mutationCases) {
        $mutationName = $mutationCase[0]
        $mutationOutputPath = $mutationCase[1]
        & $probeCanonical --probe-mutation $mutationName `
            $ordinaryTargetArgument $mutationOutputPath
        Assert-ExitCode -Actual $LASTEXITCODE -Expected 25 `
            -Label "$mutationName fail-closed fallback"
        $mutationOutput = Get-Content -Raw -LiteralPath $mutationOutputPath
        Assert-OutputMatch -Text $mutationOutput `
            -Pattern "(?m)^CANDIDATE_SOURCE=REJECTED ERROR=5 NONEMPTY=0\r?$" `
            -Label "$mutationName fail-closed fallback"
        $mutationValues = ConvertFrom-ProbeOutput -Text $mutationOutput
        if ($mutationValues["CANDIDATE_PATH"] -ne "") {
            throw "$mutationName returned a candidate path"
        }
    }

    & $probeCanonical --file-name-info-max $maximumInfoOutputPath
    Assert-ExitCode -Actual $LASTEXITCODE -Expected 0 `
        -Label "FileNameInfo exact maximum allocation"
    $maximumInfoOutput = Get-Content -Raw -LiteralPath $maximumInfoOutputPath
    Assert-OutputMatch -Text $maximumInfoOutput `
        -Pattern "(?m)^FILE_NAME_INFO_MAX_ATTEMPTS=7 LAST_CAPACITY=65538 ERROR=111\r?$" `
        -Label "FileNameInfo exact maximum allocation"

    $profileMayExist = $true
    $packagedLines = & $probeCanonical --appcontainer $profileName `
        $stageCanonical $workCanonical $probeCanonical `
        $packagedTargetArgument 2>&1
    $packagedExit = $LASTEXITCODE
    $packagedConsole = $packagedLines -join [Environment]::NewLine
    $packagedOutput = Get-Content -Raw -LiteralPath $packagedOutputPath
    Assert-ExitCode -Actual $packagedExit -Expected 0 `
        -Label "AppContainer probe`n$packagedOutput"

    Assert-OutputMatch -Text $packagedConsole `
        -Pattern "(?m)^TOKEN_IS_APPCONTAINER=1 TOKEN_SID_MATCH=1 TOKEN_CAPABILITIES=0\r?$" `
        -Label "AppContainer token"
    Assert-OutputMatch -Text $packagedConsole `
        -Pattern "(?m)^PROFILE_DELETE_HRESULT=0x00000000\r?$" `
        -Label "AppContainer profile deletion"
    Assert-OutputMatch -Text $packagedOutput `
        -Pattern "(?m)^CREATEFILE_HANDLE=1 ERROR=0\r?$" `
        -Label "AppContainer CreateFileW"
    Assert-OutputMatch -Text $packagedOutput `
        -Pattern "(?m)^GETFINAL_NORMALIZED_LENGTH=0 ERROR=5 NONEMPTY=0\r?$" `
        -Label "AppContainer normalized API failure"
    Assert-OutputMatch -Text $packagedOutput `
        -Pattern "(?m)^GETFINAL_OPENED_LENGTH=0 ERROR=5 NONEMPTY=0\r?$" `
        -Label "AppContainer opened RED"
    Assert-OutputMatch -Text $packagedOutput `
        -Pattern "(?m)^FILE_NAME_INFO_OK=1 LENGTH=[1-9][0-9]* ERROR=0 NONEMPTY=1\r?$" `
        -Label "AppContainer FileNameInfo"
    Assert-OutputMatch -Text $packagedOutput `
        -Pattern "(?m)^READFILE=1 ERROR=0 BYTES=1 BYTE=[0-9]+\r?$" `
        -Label "AppContainer ReadFile"
    Assert-OutputMatch -Text $packagedOutput `
        -Pattern "(?m)^ENUMERATION=1 ERROR=0\r?$" `
        -Label "AppContainer enumeration"

    $packagedValues = ConvertFrom-ProbeOutput -Text $packagedOutput
    $packagedFileNameInfoPath = Get-RequiredOutputValue `
        -Values $packagedValues -Key "FILE_NAME_INFO_PATH" `
        -Label "AppContainer FileNameInfo path"
    Assert-WindowsPathEqual -Actual $packagedFileNameInfoPath `
        -Expected $expectedFileNameInfoPath `
        -Label "AppContainer FileNameInfo"
    Assert-WindowsPathEqual -Actual $packagedFileNameInfoPath `
        -Expected $ordinaryFileNameInfoPath `
        -Label "ordinary/AppContainer FileNameInfo"
    Assert-OutputMatch -Text $packagedOutput `
        -Pattern "(?m)^CANDIDATE_SOURCE=FALLBACK ERROR=0 NONEMPTY=1\r?$" `
        -Label "AppContainer candidate fallback"
    $packagedCandidatePath = Get-RequiredOutputValue `
        -Values $packagedValues -Key "CANDIDATE_PATH" `
        -Label "AppContainer candidate path"
    Assert-WindowsPathEqual -Actual $packagedCandidatePath `
        -Expected $expectedFinalPath -Label "AppContainer candidate"

    $scratchAclAfter = (Get-Acl -LiteralPath $scratchCanonical).Sddl
    if ($scratchAclAfter -ne $scratchAclBefore) {
        throw "ACL outside the disposable stage changed: $scratchCanonical"
    }
}
finally {
    $cleanupFailures = [System.Collections.Generic.List[string]]::new()

    try {
        if ($profileMayExist -and $probeAvailable -and
            (Test-Path -LiteralPath $probePath -PathType Leaf)) {
            $cleanupLines = & $probePath --delete-profile $profileName 2>&1
            $cleanupExit = $LASTEXITCODE
            $cleanupConsole = $cleanupLines -join [Environment]::NewLine
            if ($cleanupExit -ne 0) {
                $cleanupFailures.Add(
                    "Profile cleanup failed with exit $cleanupExit`n" +
                    $cleanupConsole)
            }
        }
    }
    catch {
        $cleanupFailures.Add("Profile cleanup threw: $($_.Exception.Message)")
    }

    try {
        $cleanupStage = [System.IO.Path]::GetFullPath($stageRoot)
        Assert-StrictDescendant -Child $cleanupStage -Parent $scratchCanonical `
            -Label "cleanup stage"
        if (Test-Path -LiteralPath $cleanupStage) {
            Remove-Item -LiteralPath $cleanupStage -Recurse -Force
        }
        if (Test-Path -LiteralPath $cleanupStage) {
            $cleanupFailures.Add("Stage cleanup failed: $cleanupStage")
        }
    }
    catch {
        $cleanupFailures.Add("Stage cleanup threw: $($_.Exception.Message)")
    }

    if ($cleanupFailures.Count -ne 0) {
        throw ($cleanupFailures -join [Environment]::NewLine)
    }
}

Write-Output "BUILD_EXIT=0"
Write-Output "FORCED_FALLBACK_EXIT=0"
Write-Output "VOLUME_MISMATCH_EXIT=25"
Write-Output "REPARSE_MUTATION_EXIT=25"
Write-Output "MALFORMED_PATH_EXIT=25"
Write-Output "REAL_JUNCTION_EXIT=25"
Write-Output $maximumInfoOutput.TrimEnd()
Write-Output "ORDINARY_EXIT=0"
Write-Output $ordinaryOutput.TrimEnd()
Write-Output "PACKAGED_EXIT=0"
Write-Output $packagedConsole.TrimEnd()
Write-Output $packagedOutput.TrimEnd()
Write-Output $cleanupConsole.TrimEnd()
Write-Output "STAGE_EXISTS_AFTER_CLEANUP=False"
