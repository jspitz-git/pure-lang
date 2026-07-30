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
    [string] $MinGWCompiler = "",
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
$hardlinkPath = Join-Path $fixtureDirectory "embed_probe-hardlink.cc"
$junctionHardlinkOutputPath = Join-Path $workDirectory "junction-hardlink.txt"
$substOutputPath = Join-Path $workDirectory "subst.txt"
$forcedFallbackOutputPath = Join-Path $workDirectory "forced-fallback.txt"
$maximumInfoOutputPath = Join-Path $workDirectory "file-name-info-max.txt"

$sharedValidationOutputPath = Join-Path $workDirectory "shared-validation.txt"
$profileMayExist = $false
$probeAvailable = $false
$substDrive = $null
$substAvailable = $false
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

    if ([string]::IsNullOrWhiteSpace($MinGWCompiler)) {
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
        $buildToolchain = "MSVC"
    }
    else {
        $compilerCanonical = Get-CanonicalExistingPath -Path $MinGWCompiler
        $env:PATH = (Split-Path -Parent $compilerCanonical) + ";" + $env:PATH
        & $compilerCanonical -x c++ -std=gnu++17 -Wall -Wextra -Werror -municode `
            -DNTDDI_VERSION=0x0A000007 -D_WIN32_WINNT=0x0A00 `
            $sourceCanonical -o $probePath -luserenv -ladvapi32
        Assert-ExitCode -Actual $LASTEXITCODE -Expected 0 -Label "MinGW build"
        $buildToolchain = "MinGW-G++"
    }

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
        -Pattern "(?m)^FILE_NORMALIZED_NAME_INFO_OK=1 LENGTH=[1-9][0-9]* ERROR=0 NONEMPTY=1\r?$" `
        -Label "ordinary FileNormalizedNameInfo"
    Assert-OutputMatch -Text $ordinaryOutput `
        -Pattern "(?m)^SYSTEM_WINDOWS_DIRECTORY_LENGTH=[1-9][0-9]* ERROR=0 NONEMPTY=1\r?$" `
        -Label "ordinary GetSystemWindowsDirectoryW"
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
    $ordinaryFileNormalizedNameInfoPath = Get-RequiredOutputValue `
        -Values $ordinaryValues -Key "FILE_NORMALIZED_NAME_INFO_PATH" `
        -Label "ordinary FileNormalizedNameInfo path"
    Assert-WindowsPathEqual -Actual $ordinaryNormalizedPath `
        -Expected $expectedFinalPath -Label "ordinary normalized"
    Assert-WindowsPathEqual -Actual $ordinaryOpenedPath `
        -Expected $expectedFinalPath -Label "ordinary opened"
    Assert-WindowsPathEqual -Actual $ordinaryFileNameInfoPath `
        -Expected $expectedFileNameInfoPath -Label "ordinary FileNameInfo"
    Assert-WindowsPathEqual -Actual $ordinaryFileNormalizedNameInfoPath `
        -Expected $expectedFileNameInfoPath `
        -Label "ordinary FileNormalizedNameInfo"
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
    Assert-ExitCode -Actual $LASTEXITCODE -Expected 0 `
        -Label "real junction normalized fallback"
    $junctionOutput = Get-Content -Raw -LiteralPath $junctionOutputPath
    Assert-OutputMatch -Text $junctionOutput `
        -Pattern "(?m)^FILE_NORMALIZED_NAME_INFO_OK=1 LENGTH=[1-9][0-9]* ERROR=0 NONEMPTY=1\r?$" `
        -Label "junction FileNormalizedNameInfo"
    Assert-OutputMatch -Text $junctionOutput `
        -Pattern "(?m)^CANDIDATE_SOURCE=FALLBACK ERROR=0 NONEMPTY=1\r?$" `
        -Label "real junction normalized fallback"
    $junctionValues = ConvertFrom-ProbeOutput -Text $junctionOutput
    $junctionFileNormalizedNameInfoPath = Get-RequiredOutputValue `
        -Values $junctionValues -Key "FILE_NORMALIZED_NAME_INFO_PATH" `
        -Label "junction FileNormalizedNameInfo path"
    Assert-WindowsPathEqual -Actual $junctionFileNormalizedNameInfoPath `
        -Expected $expectedFileNameInfoPath `
        -Label "junction FileNormalizedNameInfo"
    $junctionCandidatePath = Get-RequiredOutputValue `
        -Values $junctionValues -Key "CANDIDATE_PATH" `
        -Label "junction candidate path"
    Assert-WindowsPathEqual -Actual $junctionCandidatePath `
        -Expected $expectedFinalPath -Label "junction underlying candidate"

    New-Item -ItemType HardLink -Path $hardlinkPath -Target $targetCanonical |
        Out-Null
    $hardlinkCanonical = Get-CanonicalExistingPath -Path $hardlinkPath
    $expectedHardlinkInfoPath =
        "\" + $hardlinkCanonical.Substring($targetVolumeRoot.Length)
    $junctionHardlinkTarget =
        Join-Path $junctionDirectory "embed_probe-hardlink.cc"
    & $probeCanonical --probe-mutation force-fallback `
        $junctionHardlinkTarget $junctionHardlinkOutputPath
    Assert-ExitCode -Actual $LASTEXITCODE -Expected 0 `
        -Label "junction+hardlink normalized fallback"
    $junctionHardlinkOutput =
        Get-Content -Raw -LiteralPath $junctionHardlinkOutputPath
    $junctionHardlinkValues =
        ConvertFrom-ProbeOutput -Text $junctionHardlinkOutput
    $junctionHardlinkNormalizedPath = Get-RequiredOutputValue `
        -Values $junctionHardlinkValues -Key "FILE_NORMALIZED_NAME_INFO_PATH" `
        -Label "junction+hardlink normalized path"
    Assert-WindowsPathEqual -Actual $junctionHardlinkNormalizedPath `
        -Expected $expectedHardlinkInfoPath `
        -Label "junction+hardlink FileNormalizedNameInfo"
    $junctionHardlinkCandidatePath = Get-RequiredOutputValue `
        -Values $junctionHardlinkValues -Key "CANDIDATE_PATH" `
        -Label "junction+hardlink candidate path"
    $expectedHardlinkCandidatePath = "\\?\" + $hardlinkCanonical
    Assert-WindowsPathEqual -Actual $junctionHardlinkCandidatePath `
        -Expected $expectedHardlinkCandidatePath `
        -Label "junction+hardlink underlying candidate"

    $substExe = Join-Path $env:SystemRoot "System32\subst.exe"
    if (Test-Path -LiteralPath $substExe -PathType Leaf) {
        foreach ($letterCode in 90..68) {
            $candidateDrive = ([char]$letterCode).ToString() + ":"
            if (Test-Path -LiteralPath ($candidateDrive + "\")) {
                continue
            }
            & $substExe $candidateDrive $fixtureDirectoryCanonical
            if ($LASTEXITCODE -eq 0) {
                $substDrive = $candidateDrive
                $substAvailable = $true
                break
            }
        }
    }

    if ($substAvailable) {
        $substTarget = $substDrive + "\embed_probe.cc"
        & $probeCanonical --probe-mutation force-fallback `
            $substTarget $substOutputPath
        Assert-ExitCode -Actual $LASTEXITCODE -Expected 25 `
            -Label "real SUBST fail-closed fallback"
        $substOutput = Get-Content -Raw -LiteralPath $substOutputPath
        $substValues = ConvertFrom-ProbeOutput -Text $substOutput
        $substNormalizedPath = Get-RequiredOutputValue `
            -Values $substValues -Key "FILE_NORMALIZED_NAME_INFO_PATH" `
            -Label "SUBST FileNormalizedNameInfo path"
        Assert-WindowsPathEqual -Actual $substNormalizedPath `
            -Expected $expectedFileNameInfoPath `
            -Label "SUBST underlying normalized path"
        if ($substValues["CANDIDATE_PATH"] -ne "") {
            throw "SUBST alias returned a candidate path"
        }
    }

    & $probeCanonical --shared-helper-validation $sharedValidationOutputPath
    Assert-ExitCode -Actual $LASTEXITCODE -Expected 0 `
        -Label "shared helper validation"
    $sharedValidationOutput =
        Get-Content -Raw -LiteralPath $sharedValidationOutputPath
    Assert-OutputMatch -Text $sharedValidationOutput `
        -Pattern "(?m)^SHARED_VALID=1 MALFORMED_ROOT=0 PARENT=0 SLASH=0 COLON=0 INVALID_HANDLE_ERROR=6\r?$" `
        -Label "shared helper malformed/error validation"


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
        -Pattern "(?m)^FILE_NORMALIZED_NAME_INFO_OK=1 LENGTH=[1-9][0-9]* ERROR=0 NONEMPTY=1\r?$" `
        -Label "AppContainer FileNormalizedNameInfo"
    Assert-OutputMatch -Text $packagedOutput `
        -Pattern "(?m)^SYSTEM_WINDOWS_DIRECTORY_LENGTH=[1-9][0-9]* ERROR=0 NONEMPTY=1\r?$" `
        -Label "AppContainer GetSystemWindowsDirectoryW"
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
    $packagedFileNormalizedNameInfoPath = Get-RequiredOutputValue `
        -Values $packagedValues -Key "FILE_NORMALIZED_NAME_INFO_PATH" `
        -Label "AppContainer FileNormalizedNameInfo path"
    Assert-WindowsPathEqual -Actual $packagedFileNameInfoPath `
        -Expected $expectedFileNameInfoPath `
        -Label "AppContainer FileNameInfo"
    Assert-WindowsPathEqual -Actual $packagedFileNameInfoPath `
        -Expected $ordinaryFileNameInfoPath `
        -Label "ordinary/AppContainer FileNameInfo"
    Assert-WindowsPathEqual -Actual $packagedFileNormalizedNameInfoPath `
        -Expected $expectedFileNameInfoPath `
        -Label "AppContainer FileNormalizedNameInfo"
    Assert-WindowsPathEqual -Actual $packagedFileNormalizedNameInfoPath `
        -Expected $ordinaryFileNormalizedNameInfoPath `
        -Label "ordinary/AppContainer FileNormalizedNameInfo"
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
        if ($null -ne $substDrive) {
            & $substExe $substDrive /D
            if ($LASTEXITCODE -ne 0) {
                throw "SUBST cleanup failed: $substDrive"
            }
            $substDrive = $null
        }
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
Write-Output "REAL_JUNCTION_EXIT=0"
Write-Output "JUNCTION_HARDLINK_EXIT=0"
Write-Output "SUBST_AVAILABLE=$substAvailable"
if ($substAvailable) {
    Write-Output "SUBST_EXIT=25"
}
Write-Output $sharedValidationOutput.TrimEnd()
Write-Output $maximumInfoOutput.TrimEnd()
Write-Output "ORDINARY_EXIT=0"
Write-Output $ordinaryOutput.TrimEnd()
Write-Output "PACKAGED_EXIT=0"
Write-Output "BUILD_TOOLCHAIN=$buildToolchain"
Write-Output $packagedConsole.TrimEnd()
Write-Output $packagedOutput.TrimEnd()
Write-Output $cleanupConsole.TrimEnd()
Write-Output "STAGE_EXISTS_AFTER_CLEANUP=False"
