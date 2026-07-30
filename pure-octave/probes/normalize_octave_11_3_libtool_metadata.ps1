[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string] $ToolchainRoot,
    [Parameter(Mandatory = $true)][string] $DisposableParentRoot,
    [Parameter(Mandatory = $true)][long] $ExpectedFileCount,
    [Parameter(Mandatory = $true)][long] $ExpectedTotalBytes,
    [Parameter(Mandatory = $true)][ValidatePattern("^[0-9A-Fa-f]{64}$")]
    [string] $ExpectedManifestSha256,
    [ValidateSet("Plan", "Apply")][string] $Mode = "Plan",
    [ValidateSet("OrdinalLfV1", "PowerShellTsvV1")]
    [string] $ManifestFormat = "OrdinalLfV1",
    [string] $ManifestOrderReferencePath = "",
    [string] $ExpectedManifestOrderReferenceSha256 = "",
    [string] $LaSelectionManifestPath = "",
    [string] $ExpectedLaSelectionManifestSha256 = "",
    [ValidateRange(1, 100)]
    [int] $ExpectedLaRootCount = 1,
    [string] $SeedLibraryManifestPath = "",
    [string] $ExpectedSeedLibraryManifestSha256 = "",
    [ValidateRange(0, 100)]
    [int] $ExpectedSeedLibraryCount = 0,
    [ValidateSet(
        "None",
        "CompilerFailureAfterTempCreation",
        "RootIdentityMismatchBeforeSecondReplacement",
        "BeforeSecondReplacement",
        "RemoveEmittedTargetAfterReplacement")]
    [string] $TestFailurePoint = "None"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$ascii = [Text.Encoding]::ASCII

$directoryIdentitySource = @'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Text;
using Microsoft.Win32.SafeHandles;

public sealed class Todo51DirectoryIdentity : IDisposable
{
    [StructLayout(LayoutKind.Sequential)]
    private struct ByHandleFileInformation
    {
        public uint FileAttributes;
        public System.Runtime.InteropServices.ComTypes.FILETIME CreationTime;
        public System.Runtime.InteropServices.ComTypes.FILETIME LastAccessTime;
        public System.Runtime.InteropServices.ComTypes.FILETIME LastWriteTime;
        public uint VolumeSerialNumber;
        public uint FileSizeHigh;
        public uint FileSizeLow;
        public uint NumberOfLinks;
        public uint FileIndexHigh;
        public uint FileIndexLow;
    }

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern SafeFileHandle CreateFile(
        string fileName, uint desiredAccess, uint shareMode, IntPtr securityAttributes,
        uint creationDisposition, uint flagsAndAttributes, IntPtr templateFile);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool GetFileInformationByHandle(
        SafeFileHandle file, out ByHandleFileInformation information);

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern uint GetFinalPathNameByHandle(
        SafeFileHandle file, StringBuilder path, uint pathLength, uint flags);

    private readonly SafeFileHandle handle;

    private Todo51DirectoryIdentity(SafeFileHandle handle)
    {
        this.handle = handle;
    }

    public static Todo51DirectoryIdentity Open(string path)
    {
        const uint FileShareRead = 1;
        const uint FileShareWrite = 2;
        const uint OpenExisting = 3;
        const uint FileFlagBackupSemantics = 0x02000000;
        SafeFileHandle handle = CreateFile(
            path, 0, FileShareRead | FileShareWrite, IntPtr.Zero,
            OpenExisting, FileFlagBackupSemantics, IntPtr.Zero);
        if (handle.IsInvalid)
        {
            int error = Marshal.GetLastWin32Error();
            handle.Dispose();
            throw new Win32Exception(error, "Unable to open directory identity handle.");
        }
        return new Todo51DirectoryIdentity(handle);
    }

    public string Identity
    {
        get
        {
            ByHandleFileInformation information;
            if (!GetFileInformationByHandle(this.handle, out information))
                throw new Win32Exception(Marshal.GetLastWin32Error());
            return String.Format(
                "{0:X8}:{1:X8}{2:X8}",
                information.VolumeSerialNumber,
                information.FileIndexHigh,
                information.FileIndexLow);
        }
    }

    public string FinalPath
    {
        get
        {
            StringBuilder path = new StringBuilder(32768);
            uint length = GetFinalPathNameByHandle(
                this.handle, path, (uint)path.Capacity, 0);
            if (length == 0 || length >= path.Capacity)
                throw new Win32Exception(Marshal.GetLastWin32Error());
            return path.ToString();
        }
    }

    public void Dispose()
    {
        this.handle.Dispose();
    }
}
'@

function Get-Sha256Bytes {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [byte[]] $Bytes
    )

    $algorithm = [Security.Cryptography.SHA256]::Create()
    try {
        return (($algorithm.ComputeHash($Bytes) |
                    ForEach-Object { $_.ToString("x2") }) -join "").ToUpperInvariant()
    }
    finally {
        $algorithm.Dispose()
    }
}

function Get-CanonicalDirectory {
    param(
        [Parameter(Mandatory = $true)][string] $Path,
        [Parameter(Mandatory = $true)][string] $Description
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        throw "$Description does not exist or is not a directory: $Path"
    }
    return [IO.Path]::GetFullPath($Path).TrimEnd("\")
}

function Test-IsStrictDescendant {
    param(
        [Parameter(Mandatory = $true)][string] $Path,
        [Parameter(Mandatory = $true)][string] $Parent
    )

    return $Path.StartsWith(
        ($Parent.TrimEnd("\") + "\"),
        [StringComparison]::OrdinalIgnoreCase)
}

function Assert-NoReparsePoints {
    param([Parameter(Mandatory = $true)][string] $Root)

    $cursor = Get-Item -LiteralPath $Root -Force
    while ($null -ne $cursor) {
        if (($cursor.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "reparse point is forbidden in toolchain path: $($cursor.FullName)"
        }
        $cursor = $cursor.Parent
    }

    foreach ($item in @(Get-ChildItem -LiteralPath $Root -Recurse -Force)) {
        if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "reparse point is forbidden in toolchain tree: $($item.FullName)"
        }
    }
}

function Assert-NoReparsePathComponents {
    param([Parameter(Mandatory = $true)][string] $Path)

    $canonical = [IO.Path]::GetFullPath($Path).TrimEnd("\")
    $cursor = [IO.Path]::GetPathRoot($canonical).TrimEnd("\")
    $relative = $canonical.Substring(
        [IO.Path]::GetPathRoot($canonical).Length)
    foreach ($component in @($relative -split '\\' |
            Where-Object { $_.Length -ne 0 })) {
        $cursor = Join-Path $cursor $component
        $item = Get-Item -LiteralPath $cursor -Force
        if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "reparse point is forbidden in validated path: $cursor"
        }
    }
}

function Get-TreeManifest {
    param(
        [Parameter(Mandatory = $true)][string] $Root,
        [hashtable] $ReplacementBytes,
        [ValidateSet("OrdinalLfV1", "PowerShellTsvV1")]
        [string] $ManifestFormat = "OrdinalLfV1",
        [string[]] $ManifestOrderPaths
    )

    $files = @(Get-ChildItem -LiteralPath $Root -Recurse -Force -File)
    $relativePaths = [string[]] @($files | ForEach-Object {
        $_.FullName.Substring($Root.Length + 1).Replace("\", "/")
    })
    if ($ManifestFormat -eq "PowerShellTsvV1") {
        if ($null -eq $ManifestOrderPaths -or
                $ManifestOrderPaths.Count -ne $relativePaths.Count) {
            throw "PowerShellTsvV1 requires a validated reference path order."
        }
        $relativePaths = [string[]] $ManifestOrderPaths.Clone()
    }
    else {
        [Array]::Sort($relativePaths, [StringComparer]::Ordinal)
    }

    $lines = New-Object Collections.Generic.List[string]
    [long] $totalBytes = 0
    foreach ($relative in $relativePaths) {
        $path = Join-Path $Root $relative.Replace("/", "\")
        $bytes = $null
        if ($null -ne $ReplacementBytes -and
                $ReplacementBytes.ContainsKey($path)) {
            $bytes = [byte[]] $ReplacementBytes[$path]
        }
        else {
            $bytes = [IO.File]::ReadAllBytes($path)
        }
        $totalBytes += $bytes.LongLength
        $lines.Add(("{0}`t{1}`t{2}" -f
                    $relative, $bytes.LongLength, (Get-Sha256Bytes -Bytes $bytes)))
    }

    $serialized = if ($ManifestFormat -eq "PowerShellTsvV1") {
        if ($lines.Count -eq 0) { "" } else { ($lines -join "`r`n") + "`r`n" }
    }
    else {
        $lines -join "`n"
    }
    $manifestBytes = $utf8NoBom.GetBytes($serialized)
    return [pscustomobject] @{
        FileCount = [long] $relativePaths.Count
        TotalBytes = $totalBytes
        Sha256 = Get-Sha256Bytes -Bytes $manifestBytes
        ManifestFormat = $ManifestFormat
        ManifestByteCount = $manifestBytes.Length
    }
}

function Assert-RegularFile {
    param(
        [Parameter(Mandatory = $true)][string] $Path,
        [Parameter(Mandatory = $true)][string] $Description
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "$Description is missing: $Path"
    }
    $item = Get-Item -LiteralPath $Path -Force
    if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "$Description is a reparse point: $Path"
    }
}

function Convert-ToPortablePath {
    param(
        [Parameter(Mandatory = $true)][string] $Path,
        [Parameter(Mandatory = $true)][string] $MingwRoot
    )

    $relative = $Path.Substring($MingwRoot.Length + 1).Replace("\", "/")
    return "/mingw64/$relative"
}

function Assert-LocalDosPathSyntax {
    param(
        [Parameter(Mandatory = $true)][string] $Path,
        [Parameter(Mandatory = $true)][string] $Description
    )

    if ($Path -notmatch '^[A-Za-z]:\\' -or $Path.Contains("/")) {
        throw "$Description uses a forbidden namespace or non-drive-letter path: $Path"
    }
}

function Convert-FinalPathToDos {
    param(
        [Parameter(Mandatory = $true)][string] $Path,
        [Parameter(Mandatory = $true)][string] $Description
    )

    if ($Path.StartsWith("\\?\", [StringComparison]::Ordinal)) {
        $Path = $Path.Substring(4)
    }
    if ($Path -notmatch '^[A-Za-z]:\\') {
        throw "$Description resolved to a forbidden namespace: $Path"
    }
    return [IO.Path]::GetFullPath($Path).TrimEnd("\")
}

function Assert-StableRootIdentity {
    param(
        [Parameter(Mandatory = $true)] $HeldIdentity,
        [Parameter(Mandatory = $true)][string] $ExpectedIdentity,
        [Parameter(Mandatory = $true)][string] $ExpectedPath
    )

    if ($HeldIdentity.Identity -ne $ExpectedIdentity) {
        throw "root identity changed on the held directory handle"
    }
    $current = [Todo51DirectoryIdentity]::Open($ExpectedPath)
    try {
        $currentPath = Convert-FinalPathToDos -Path $current.FinalPath `
            -Description "Current toolchain root"
        if ($current.Identity -ne $ExpectedIdentity -or
                -not $currentPath.Equals(
                    $ExpectedPath, [StringComparison]::OrdinalIgnoreCase)) {
            throw "root identity or resolved path changed"
        }
    }
    finally {
        $current.Dispose()
    }
}

function Get-NativeEmittedTargetPath {
    param(
        [Parameter(Mandatory = $true)][string] $PortablePath,
        [Parameter(Mandatory = $true)][string] $Root
    )

    if ($PortablePath -notmatch '^/mingw64/.+') {
        throw "emitted target uses an unsupported path: $PortablePath"
    }
    $native = [IO.Path]::GetFullPath(
        (Join-Path $Root $PortablePath.TrimStart("/").Replace("/", "\")))
    if (-not (Test-IsStrictDescendant -Path $native -Parent $Root)) {
        throw "emitted target escapes the toolchain root: $PortablePath"
    }
    return $native
}

function Assert-EmittedTargets {
    param(
        [Parameter(Mandatory = $true)][object[]] $Targets,
        [Parameter(Mandatory = $true)] $HeldRootIdentity,
        [Parameter(Mandatory = $true)][string] $ExpectedRootIdentity,
        [Parameter(Mandatory = $true)][string] $Root
    )

    foreach ($target in $Targets) {
        Assert-StableRootIdentity -HeldIdentity $HeldRootIdentity `
            -ExpectedIdentity $ExpectedRootIdentity -ExpectedPath $Root
        $native = Get-NativeEmittedTargetPath `
            -PortablePath $target.PortablePath -Root $Root
        $requiredPathType = if ($target.Kind -eq "Directory") {
            "Container"
        }
        else {
            "Leaf"
        }
        if (-not (Test-Path -LiteralPath $native -PathType $requiredPathType)) {
            throw ("emitted target is missing or has the wrong type: {0} ({1})" -f
                $target.PortablePath, $target.Kind)
        }

        $targetItem = Get-Item -LiteralPath $native -Force
        if (($targetItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "emitted target is a reparse point: $($target.PortablePath)"
        }
        $cursor = if ($targetItem.PSIsContainer) {
            $targetItem
        }
        else {
            $targetItem.Directory
        }
        while (-not $cursor.FullName.Equals(
                $Root, [StringComparison]::OrdinalIgnoreCase)) {
            if (($cursor.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw "emitted target traverses a reparse point: $($target.PortablePath)"
            }
            $cursor = $cursor.Parent
            if ($null -eq $cursor) {
                throw "emitted target is not contained by the toolchain root"
            }
        }

        $targetIdentity = [Todo51DirectoryIdentity]::Open($native)
        try {
            $resolved = Convert-FinalPathToDos -Path $targetIdentity.FinalPath `
                -Description "Emitted target"
            if (-not $resolved.Equals(
                    $native, [StringComparison]::OrdinalIgnoreCase) -or
                    -not (Test-IsStrictDescendant -Path $resolved -Parent $Root)) {
                throw "emitted target resolved outside its planned contained path"
            }
        }
        finally {
            $targetIdentity.Dispose()
        }
    }
}

function Add-EmittedTarget {
    param(
        [Parameter(Mandatory = $true)][hashtable] $Targets,
        [Parameter(Mandatory = $true)][ValidateSet("Directory", "File")]
        [string] $Kind,
        [Parameter(Mandatory = $true)][string] $PortablePath
    )

    $Targets["$Kind|$PortablePath"] = [pscustomobject] @{
        Kind = $Kind
        PortablePath = $PortablePath
    }
}

function Register-EmittedTargetsFromText {
    param(
        [Parameter(Mandatory = $true)][string] $Text,
        [Parameter(Mandatory = $true)][hashtable] $Targets,
        [Parameter(Mandatory = $true)][string] $Description
    )

    foreach ($line in [regex]::Split($Text, '\r\n|\n|\r')) {
        $assignment = [regex]::Match(
            $line, "^(?<key>[A-Za-z_][A-Za-z0-9_]*)='(?<value>.*)'\s*$")
        if (-not $assignment.Success) {
            continue
        }
        $key = $assignment.Groups["key"].Value
        $value = $assignment.Groups["value"].Value
        if ($key -eq "dependency_libs") {
            if ($value.Contains("'")) {
                throw "unsupported quote form in emitted dependency_libs: $Description"
            }
            foreach ($token in @($value.Trim() -split '\s+' |
                    Where-Object { $_.Length -ne 0 })) {
                if ($token.StartsWith("-L") -or $token.StartsWith("-R")) {
                    $directory = $token.Substring(2)
                    if ($directory -notmatch '^/mingw64/.+') {
                        throw "unsupported emitted directory token '$token': $Description"
                    }
                    Add-EmittedTarget -Targets $Targets -Kind Directory `
                        -PortablePath $directory
                }
                elseif ($token -match '^/mingw64/.+\.la$') {
                    Add-EmittedTarget -Targets $Targets -Kind File `
                        -PortablePath $token
                }
                elseif ($token.StartsWith("/")) {
                    throw "unsupported emitted absolute token '$token': $Description"
                }
            }
        }
        elseif ($key -eq "libdir") {
            if ($value -notmatch '^/mingw64/.+') {
                throw "unsupported emitted libdir '$value': $Description"
            }
            Add-EmittedTarget -Targets $Targets -Kind Directory `
                -PortablePath $value
        }
    }
}

Assert-LocalDosPathSyntax -Path $ToolchainRoot -Description "Toolchain root"
Assert-LocalDosPathSyntax -Path $DisposableParentRoot `
    -Description "Disposable parent root"

$permanentRoot = [IO.Path]::GetFullPath("C:\Tools\GNU Octave\11.3.0").TrimEnd("\")
$requestedRoot = [IO.Path]::GetFullPath($ToolchainRoot).TrimEnd("\")
if ($requestedRoot.Equals($permanentRoot, [StringComparison]::OrdinalIgnoreCase) -or
        (Test-IsStrictDescendant -Path $requestedRoot -Parent $permanentRoot)) {
    throw "permanent Octave root is forbidden: $requestedRoot"
}

$root = Get-CanonicalDirectory -Path $ToolchainRoot -Description "Toolchain root"
$disposableParent = Get-CanonicalDirectory -Path $DisposableParentRoot `
    -Description "Disposable parent root"
if (-not (Test-IsStrictDescendant -Path $root -Parent $disposableParent)) {
    throw "Toolchain root must be a strict child of the disposable parent root."
}
$approvedDisposableBase = [IO.Path]::GetFullPath("C:\tmp").TrimEnd("\")
if (-not (Test-IsStrictDescendant `
        -Path $disposableParent -Parent $approvedDisposableBase)) {
    throw "Disposable parent root must be a strict child of C:\tmp."
}
Assert-NoReparsePathComponents -Path $disposableParent
Assert-NoReparsePathComponents -Path $root
Assert-NoReparsePoints -Root $root

$testParentPattern = '^C:\\tmp\\todo51-normalizer-tests-[0-9a-f]{32}$'
if ($TestFailurePoint -ne "None" -and
        $disposableParent -notmatch $testParentPattern) {
    throw "test failure injection is forbidden outside a synthetic test root"
}

$manifestOrderPaths = $null
$manifestOrderReferenceCanonical = $null
$manifestOrderReferenceSha256 = $null
if ($ManifestFormat -eq "OrdinalLfV1") {
    if ($ManifestOrderReferencePath.Length -ne 0 -or
            $ExpectedManifestOrderReferenceSha256.Length -ne 0) {
        throw "OrdinalLfV1 does not accept a manifest order reference."
    }
}
else {
    if ($ManifestOrderReferencePath.Length -eq 0 -or
            $ExpectedManifestOrderReferenceSha256 -notmatch
                '^[0-9A-Fa-f]{64}$') {
        throw "PowerShellTsvV1 requires a reference path and reference SHA-256."
    }
    Assert-LocalDosPathSyntax -Path $ManifestOrderReferencePath `
        -Description "Manifest order reference"
    if (-not (Test-Path -LiteralPath $ManifestOrderReferencePath -PathType Leaf)) {
        throw "manifest order reference is missing: $ManifestOrderReferencePath"
    }
    $manifestOrderReferenceCanonical =
        [IO.Path]::GetFullPath($ManifestOrderReferencePath)
    if (-not (Test-IsStrictDescendant `
            -Path $manifestOrderReferenceCanonical -Parent $disposableParent) -or
            $manifestOrderReferenceCanonical.Equals(
                $root, [StringComparison]::OrdinalIgnoreCase) -or
            (Test-IsStrictDescendant `
                -Path $manifestOrderReferenceCanonical -Parent $root)) {
        throw ("manifest order reference must be under the disposable parent " +
            "and outside the toolchain root")
    }
    Assert-NoReparsePathComponents -Path $manifestOrderReferenceCanonical
    $referenceItem = Get-Item -LiteralPath $manifestOrderReferenceCanonical -Force
    if (($referenceItem.Attributes -band
            [IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "manifest order reference is a reparse point"
    }
    $referenceBytes = [IO.File]::ReadAllBytes($manifestOrderReferenceCanonical)
    $manifestOrderReferenceSha256 =
        Get-Sha256Bytes -Bytes $referenceBytes
    if (-not $manifestOrderReferenceSha256.Equals(
            $ExpectedManifestOrderReferenceSha256,
            [StringComparison]::OrdinalIgnoreCase)) {
        throw ("manifest order reference hash mismatch: actual {0}, expected {1}" -f
            $manifestOrderReferenceSha256,
            $ExpectedManifestOrderReferenceSha256.ToUpperInvariant())
    }

    if ($referenceBytes.Length -lt 2 -or
            $referenceBytes[$referenceBytes.Length - 2] -ne 13 -or
            $referenceBytes[$referenceBytes.Length - 1] -ne 10 -or
            ($referenceBytes.Length -ge 3 -and
                $referenceBytes[0] -eq 0xef -and
                $referenceBytes[1] -eq 0xbb -and
                $referenceBytes[2] -eq 0xbf)) {
        throw ("manifest order reference must be UTF-8 without BOM and end " +
            "with CRLF")
    }
    $strictUtf8 = New-Object Text.UTF8Encoding($false, $true)
    try {
        $referenceText = $strictUtf8.GetString($referenceBytes)
    }
    catch {
        throw "manifest order reference is not valid UTF-8"
    }
    $referenceLines = [string[]] @(
        $referenceText.Substring(0, $referenceText.Length - 2) -split "`r`n")
    if ((($referenceLines -join "`r`n") + "`r`n") -cne $referenceText) {
        throw "manifest order reference contains unsupported line endings"
    }

    $manifestOrderPathList = New-Object Collections.Generic.List[string]
    $referencePathSet =
        New-Object Collections.Generic.HashSet[string](
            [StringComparer]::OrdinalIgnoreCase)
    foreach ($line in $referenceLines) {
        $fields = $line.Split("`t")
        if ($fields.Count -ne 3 -or $fields[1] -notmatch '^[0-9]+$' -or
                $fields[2] -notmatch '^[0-9A-Fa-f]{64}$') {
            throw "manifest order reference has an invalid 3-field record"
        }
        $relative = $fields[0]
        $segments = @($relative -split '/')
        if ($relative.Length -eq 0 -or $relative.Contains("\") -or
                $relative.StartsWith("/") -or
                $relative -match '^[A-Za-z]:' -or
                @($segments | Where-Object {
                    $_.Length -eq 0 -or $_ -eq "." -or $_ -eq ".."
                }).Count -ne 0) {
            throw "manifest order reference contains an unsafe relative path"
        }
        if (-not $referencePathSet.Add($relative)) {
            throw "manifest order reference contains a duplicate path"
        }
        $manifestOrderPathList.Add($relative)
    }

    $currentRelativePaths = [string[]] @(
        Get-ChildItem -LiteralPath $root -Recurse -Force -File |
            ForEach-Object {
                $_.FullName.Substring($root.Length + 1).Replace("\", "/")
            })
    if ($currentRelativePaths.Count -ne $manifestOrderPathList.Count) {
        throw "manifest order reference path count differs from the toolchain"
    }
    $currentPathSet =
        New-Object Collections.Generic.HashSet[string](
            $currentRelativePaths, [StringComparer]::OrdinalIgnoreCase)
    foreach ($relative in $manifestOrderPathList) {
        if (-not $currentPathSet.Contains($relative)) {
            throw "manifest order reference path set differs from the toolchain"
        }
    }
    $manifestOrderPaths = $manifestOrderPathList.ToArray()
}

$laSelectionCanonical = $null
$laSelectionSha256 = $null
$selectionPathSet =
    New-Object Collections.Generic.HashSet[string](
        [StringComparer]::OrdinalIgnoreCase)
$selectionRootPathSet =
    New-Object Collections.Generic.HashSet[string](
        [StringComparer]::OrdinalIgnoreCase)
$selectionRoleByPath = @{}

if ($LaSelectionManifestPath.Length -eq 0 -or
        $ExpectedLaSelectionManifestSha256 -notmatch '^[0-9A-Fa-f]{64}$') {
    throw "an explicit .la selection manifest path and SHA-256 are required"
}
Assert-LocalDosPathSyntax -Path $LaSelectionManifestPath `
    -Description ".la selection manifest"
Assert-RegularFile -Path $LaSelectionManifestPath `
    -Description ".la selection manifest"
$laSelectionCanonical = [IO.Path]::GetFullPath($LaSelectionManifestPath)
if (-not (Test-IsStrictDescendant `
        -Path $laSelectionCanonical -Parent $disposableParent) -or
        $laSelectionCanonical.Equals(
            $root, [StringComparison]::OrdinalIgnoreCase) -or
        (Test-IsStrictDescendant -Path $laSelectionCanonical -Parent $root)) {
    throw (".la selection manifest must be under the disposable parent " +
        "and outside the toolchain root")
}
Assert-NoReparsePathComponents -Path $laSelectionCanonical
$selectionBytes = [IO.File]::ReadAllBytes($laSelectionCanonical)
$laSelectionSha256 = Get-Sha256Bytes -Bytes $selectionBytes
if (-not $laSelectionSha256.Equals(
        $ExpectedLaSelectionManifestSha256,
        [StringComparison]::OrdinalIgnoreCase)) {
    throw (".la selection manifest hash mismatch: actual {0}, expected {1}" -f
        $laSelectionSha256,
        $ExpectedLaSelectionManifestSha256.ToUpperInvariant())
}
if ($selectionBytes.Length -lt 2 -or
        $selectionBytes[$selectionBytes.Length - 2] -ne 13 -or
        $selectionBytes[$selectionBytes.Length - 1] -ne 10 -or
        ($selectionBytes.Length -ge 3 -and
            $selectionBytes[0] -eq 0xef -and
            $selectionBytes[1] -eq 0xbb -and
            $selectionBytes[2] -eq 0xbf)) {
    throw (".la selection manifest must be UTF-8 without BOM and end " +
        "with CRLF")
}
$strictSelectionUtf8 = New-Object Text.UTF8Encoding($false, $true)
try {
    $selectionText = $strictSelectionUtf8.GetString($selectionBytes)
}
catch {
    throw ".la selection manifest is not valid UTF-8"
}
$selectionLines = [string[]] @(
    $selectionText.Substring(0, $selectionText.Length - 2) -split "`r`n")
if ((($selectionLines -join "`r`n") + "`r`n") -cne $selectionText) {
    throw ".la selection manifest contains unsupported line endings"
}

foreach ($line in $selectionLines) {
    $fields = $line.Split("`t")
    if ($fields.Count -ne 2 -or
            $fields[0] -notin @("root", "dependency")) {
        throw ".la selection manifest has an invalid 2-field record"
    }
    $role = $fields[0]
    $relative = $fields[1]
    $segments = @($relative -split '/')
    if ($relative.Length -eq 0 -or $relative.Contains("\") -or
            $relative.StartsWith("/") -or
            $relative -match '^[A-Za-z]:' -or
            $relative -notmatch '(?i:^mingw64/.+\.la$)' -or
            @($segments | Where-Object {
                $_.Length -eq 0 -or $_ -eq "." -or $_ -eq ".."
            }).Count -ne 0) {
        throw ".la selection manifest contains an unsafe relative .la path"
    }
    if (-not $selectionPathSet.Add($relative)) {
        throw ".la selection manifest contains a duplicate path"
    }
    $native = [IO.Path]::GetFullPath(
        (Join-Path $root $relative.Replace("/", "\")))
    if (-not (Test-IsStrictDescendant -Path $native -Parent $root)) {
        throw ".la selection path escapes the toolchain root"
    }
    Assert-NoReparsePathComponents -Path $native
    Assert-RegularFile -Path $native -Description "selected libtool archive"
    $selectionRoleByPath[$relative] = $role
    if ($role -eq "root") {
        [void] $selectionRootPathSet.Add($relative)
    }
}
if ($selectionRootPathSet.Count -ne $ExpectedLaRootCount) {
    throw (".la selection root count mismatch: actual {0}, expected {1}" -f
        $selectionRootPathSet.Count, $ExpectedLaRootCount)
}

$seedLibraryCanonical = $null
$seedLibrarySha256 = $null
$seedLibraryTokens = New-Object Collections.Generic.List[string]
$seedLibraryTokenSet =
    New-Object Collections.Generic.HashSet[string](
        [StringComparer]::OrdinalIgnoreCase)
if ($SeedLibraryManifestPath.Length -eq 0 -or
        $ExpectedSeedLibraryManifestSha256 -notmatch '^[0-9A-Fa-f]{64}$') {
    throw "an explicit seed library manifest path and SHA-256 are required"
}
Assert-LocalDosPathSyntax -Path $SeedLibraryManifestPath `
    -Description "seed library manifest"
Assert-RegularFile -Path $SeedLibraryManifestPath `
    -Description "seed library manifest"
$seedLibraryCanonical = [IO.Path]::GetFullPath($SeedLibraryManifestPath)
if (-not (Test-IsStrictDescendant `
        -Path $seedLibraryCanonical -Parent $disposableParent) -or
        $seedLibraryCanonical.Equals(
            $root, [StringComparison]::OrdinalIgnoreCase) -or
        (Test-IsStrictDescendant -Path $seedLibraryCanonical -Parent $root)) {
    throw ("seed library manifest must be under the disposable parent " +
        "and outside the toolchain root")
}
Assert-NoReparsePathComponents -Path $seedLibraryCanonical
$seedBytes = [IO.File]::ReadAllBytes($seedLibraryCanonical)
$seedLibrarySha256 = Get-Sha256Bytes -Bytes $seedBytes
if (-not $seedLibrarySha256.Equals(
        $ExpectedSeedLibraryManifestSha256,
        [StringComparison]::OrdinalIgnoreCase)) {
    throw ("seed library manifest hash mismatch: actual {0}, expected {1}" -f
        $seedLibrarySha256,
        $ExpectedSeedLibraryManifestSha256.ToUpperInvariant())
}
if ($seedBytes.Length -lt 2 -or
        $seedBytes[$seedBytes.Length - 2] -ne 13 -or
        $seedBytes[$seedBytes.Length - 1] -ne 10 -or
        ($seedBytes.Length -ge 3 -and
            $seedBytes[0] -eq 0xef -and
            $seedBytes[1] -eq 0xbb -and
            $seedBytes[2] -eq 0xbf)) {
    throw ("seed library manifest must be UTF-8 without BOM and end " +
        "with CRLF")
}
$strictSeedUtf8 = New-Object Text.UTF8Encoding($false, $true)
try {
    $seedText = $strictSeedUtf8.GetString($seedBytes)
}
catch {
    throw "seed library manifest is not valid UTF-8"
}
$seedLines = if ($seedText -ceq "`r`n") {
    [string[]] @()
}
else {
    [string[]] @(
        $seedText.Substring(0, $seedText.Length - 2) -split "`r`n")
}
if ((($seedLines -join "`r`n") +
        $(if (@($seedLines).Count -eq 0) { "" } else { "`r`n" })) -cne
        $(if (@($seedLines).Count -eq 0) { "" } else { $seedText })) {
    throw "seed library manifest contains unsupported line endings"
}
foreach ($token in $seedLines) {
    if ($token -match '\.\.' -or
            $token -notmatch '^[A-Za-z0-9_+][A-Za-z0-9_+.-]*$') {
        throw "seed library manifest contains an unsafe library token"
    }
    if (-not $seedLibraryTokenSet.Add($token)) {
        throw "seed library manifest contains a duplicate library token"
    }
    $seedLibraryTokens.Add($token)
}
if ($seedLibraryTokens.Count -ne $ExpectedSeedLibraryCount) {
    throw ("seed library count mismatch: actual {0}, expected {1}" -f
        $seedLibraryTokens.Count, $ExpectedSeedLibraryCount)
}

$expectedRealRootPaths = @(
    "mingw64/lib/libcurl.la",
    "mingw64/lib/libarpack.la",
    "mingw64/lib/libqrupdate.la",
    "mingw64/lib/libfftw3.la",
    "mingw64/lib/libfftw3f.la",
    "mingw64/lib/libpcre2-8.la",
    "mingw64/lib/gcc/x86_64-w64-mingw32/15.2.0/libgfortran.la",
    "mingw64/lib/gcc/x86_64-w64-mingw32/15.2.0/libquadmath.la",
    "mingw64/lib/libiconv.la"
)
if ($disposableParent -notmatch $testParentPattern) {
    $expectedRealSeedLibraries = @(
        "curl", "cholmod", "umfpack", "amd", "camd", "colamd", "ccolamd",
        "cxsparse", "suitesparseconfig", "spqr", "arpack", "qrupdate",
        "fftw3", "fftw3f", "lapack", "openblas", "readline", "pcre2-8",
        "pthread", "m", "gfortran", "mingw32", "mingwex", "msvcrt",
        "kernel32", "quadmath", "advapi32", "shell32", "user32", "shlwapi",
        "gdi32", "ws2_32", "bcrypt", "iconv"
    )
    if ($seedLibraryTokens.Count -ne $expectedRealSeedLibraries.Count) {
        throw "seed library manifest must contain the exact 34-token contract"
    }
    for ($index = 0; $index -lt $expectedRealSeedLibraries.Count; $index++) {
        if ($seedLibraryTokens[$index] -cne $expectedRealSeedLibraries[$index]) {
            throw ("seed library manifest differs from the version-scoped " +
                "Octave 11.3.0 contract at record $($index + 1)")
        }
    }
    $expectedRealRootSet =
        New-Object Collections.Generic.HashSet[string](
            [StringComparer]::OrdinalIgnoreCase)
    foreach ($relative in $expectedRealRootPaths) {
        [void] $expectedRealRootSet.Add($relative)
    }
    if ($selectionRootPathSet.Count -ne $expectedRealRootSet.Count) {
        throw ".la selection must contain the exact nine liboctave roots"
    }
    foreach ($relative in $selectionRootPathSet) {
        if (-not $expectedRealRootSet.Contains($relative)) {
            throw ".la selection contains an unexpected liboctave root: $relative"
        }
    }
    if ($selectionPathSet.Count -ne 22) {
        throw (".la selection must contain the exact 22-file liboctave " +
            "closure; actual count: $($selectionPathSet.Count)")
    }
}

$compilerTempRoot = Join-Path $disposableParent `
    (".todo51-add-type-" + [guid]::NewGuid().ToString("N"))
$savedCompilerEnvironment = @{}
try {
    [void] (New-Item -ItemType Directory -Path $compilerTempRoot)
    foreach ($name in @("TEMP", "TMP", "TMPDIR")) {
        $savedCompilerEnvironment[$name] = [pscustomobject] @{
            WasPresent = Test-Path -LiteralPath "Env:$name"
            Value = [Environment]::GetEnvironmentVariable($name, "Process")
        }
        [Environment]::SetEnvironmentVariable(
            $name, $compilerTempRoot, "Process")
    }
    if ($TestFailurePoint -eq "CompilerFailureAfterTempCreation") {
        throw "injected compiler failure after temp creation"
    }
    Add-Type -TypeDefinition $directoryIdentitySource
}
finally {
    foreach ($name in $savedCompilerEnvironment.Keys) {
        $saved = $savedCompilerEnvironment[$name]
        if ($saved.WasPresent) {
            [Environment]::SetEnvironmentVariable(
                $name, $saved.Value, "Process")
        }
        else {
            [Environment]::SetEnvironmentVariable($name, $null, "Process")
        }
    }
    if (Test-Path -LiteralPath $compilerTempRoot) {
        $compilerTempCanonical =
            [IO.Path]::GetFullPath($compilerTempRoot).TrimEnd("\")
        if (-not (Test-IsStrictDescendant `
                -Path $compilerTempCanonical -Parent $disposableParent) -or
                (Split-Path -Leaf $compilerTempCanonical) -notmatch
                    '^\.todo51-add-type-[0-9a-f]{32}$') {
            throw "refusing unsafe compiler-temp cleanup: $compilerTempCanonical"
        }
        Remove-Item -LiteralPath $compilerTempCanonical -Recurse -Force
    }
}
foreach ($name in @("TEMP", "TMP", "TMPDIR")) {
    $saved = $savedCompilerEnvironment[$name]
    $isPresent = Test-Path -LiteralPath "Env:$name"
    $restored = [Environment]::GetEnvironmentVariable($name, "Process")
    if ($isPresent -ne $saved.WasPresent -or $restored -ne $saved.Value) {
        throw "compiler environment restoration failed for $name"
    }
}
if (Test-Path -LiteralPath $compilerTempRoot) {
    throw "compiler temp cleanup failed: $compilerTempRoot"
}

$rootIdentityHandle = [Todo51DirectoryIdentity]::Open($root)
$root = Convert-FinalPathToDos -Path $rootIdentityHandle.FinalPath `
    -Description "Toolchain root"
$expectedRootIdentity = $rootIdentityHandle.Identity

$parentIdentityHandle = [Todo51DirectoryIdentity]::Open($disposableParent)
try {
    $disposableParent = Convert-FinalPathToDos `
        -Path $parentIdentityHandle.FinalPath -Description "Disposable parent root"
}
finally {
    $parentIdentityHandle.Dispose()
}
if (-not (Test-IsStrictDescendant -Path $root -Parent $disposableParent)) {
    $rootIdentityHandle.Dispose()
    throw "Toolchain root must be a strict child of the disposable parent root."
}

$permanentIdentityHandle = [Todo51DirectoryIdentity]::Open($permanentRoot)
try {
    $resolvedPermanentRoot = Convert-FinalPathToDos `
        -Path $permanentIdentityHandle.FinalPath -Description "Permanent Octave root"
    if ($expectedRootIdentity -eq $permanentIdentityHandle.Identity -or
            $root.Equals(
                $resolvedPermanentRoot, [StringComparison]::OrdinalIgnoreCase) -or
            (Test-IsStrictDescendant -Path $root -Parent $resolvedPermanentRoot)) {
        $rootIdentityHandle.Dispose()
        throw "permanent Octave filesystem identity is forbidden: $root"
    }
}
finally {
    $permanentIdentityHandle.Dispose()
}

try {
Assert-StableRootIdentity -HeldIdentity $rootIdentityHandle `
    -ExpectedIdentity $expectedRootIdentity -ExpectedPath $root

$baseline = Get-TreeManifest -Root $root -ManifestFormat $ManifestFormat `
    -ManifestOrderPaths $manifestOrderPaths
if ($baseline.FileCount -ne $ExpectedFileCount -or
        $baseline.TotalBytes -ne $ExpectedTotalBytes -or
        -not $baseline.Sha256.Equals(
            $ExpectedManifestSha256, [StringComparison]::OrdinalIgnoreCase)) {
    throw ("manifest mismatch: actual {0}/{1}/{2}, expected {3}/{4}/{5}" -f
        $baseline.FileCount, $baseline.TotalBytes, $baseline.Sha256,
        $ExpectedFileCount, $ExpectedTotalBytes,
        $ExpectedManifestSha256.ToUpperInvariant())
}

$mingwRoot = Join-Path $root "mingw64"
if (-not (Test-Path -LiteralPath $mingwRoot -PathType Container)) {
    throw "Expected mingw64 directory is missing: $mingwRoot"
}

$directoryMap = @{
    "/usr//lib" = "/mingw64/lib"
    "/usr//usr/lib" = "/mingw64/lib"
    "/usr/lib" = "/mingw64/lib"
    "/usr/lib/../lib" = "/mingw64/lib"
    "/usr/lib/gcc/x86_64-w64-mingw32/15.2.0" =
        "/mingw64/lib/gcc/x86_64-w64-mingw32/15.2.0"
    "/usr/lib/GraphicsMagick-1.3.46/modules-Q16/coders" =
        "/mingw64/lib/GraphicsMagick-1.3.46/modules-Q16/coders"
    "/usr/lib/GraphicsMagick-1.3.46/modules-Q16/filters" =
        "/mingw64/lib/GraphicsMagick-1.3.46/modules-Q16/filters"
    "/usr/lib/octave/11.3.0" = "/mingw64/lib/octave/11.3.0"
    "/usr/lib/pstoedit" = "/mingw64/lib/pstoedit"
    "/usr/libexec/gcc/x86_64-w64-mingw32/15.2.0" =
        "/mingw64/libexec/gcc/x86_64-w64-mingw32/15.2.0"
    "/usr/mingw/lib" = "/mingw64/lib"
    "/usr/qt6/lib" = "/mingw64/qt6/lib"
    "/usr/x86_64-w64-mingw32/lib" = "/mingw64/x86_64-w64-mingw32/lib"
}

foreach ($portableDirectory in @($directoryMap.Values | Select-Object -Unique)) {
    $nativeDirectory = Join-Path $root $portableDirectory.TrimStart("/").Replace("/", "\")
    if (-not (Test-Path -LiteralPath $nativeDirectory -PathType Container)) {
        throw "mapped directory is missing: $portableDirectory ($nativeDirectory)"
    }
    $item = Get-Item -LiteralPath $nativeDirectory -Force
    if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "mapped directory is a reparse point: $nativeDirectory"
    }
}

$allLaFiles = @(Get-ChildItem -LiteralPath $mingwRoot -Recurse -Force -File `
    -Filter "*.la")
$candidatesByName = @{}
foreach ($file in $allLaFiles) {
    Assert-RegularFile -Path $file.FullName -Description "libtool archive candidate"
    $key = $file.Name.ToLowerInvariant()
    if (-not $candidatesByName.ContainsKey($key)) {
        $candidatesByName[$key] = New-Object Collections.Generic.List[string]
    }
    $candidatesByName[$key].Add($file.FullName)
}

$selectedLaFiles = @($selectionPathSet | ForEach-Object {
    Get-Item -LiteralPath (Join-Path $root $_.Replace("/", "\")) -Force
} | Sort-Object FullName)
$unselectedLaFiles = @($allLaFiles | Where-Object {
    $relative = $_.FullName.Substring($root.Length + 1).Replace("\", "/")
    -not $selectionPathSet.Contains($relative)
})
$unselectedHashes = @{}
foreach ($file in $unselectedLaFiles) {
    $unselectedHashes[$file.FullName] =
        Get-Sha256Bytes -Bytes ([IO.File]::ReadAllBytes($file.FullName))
}

$effectiveSearchDirectoryRelatives = @(
    "mingw64/lib",
    "mingw64/qt6/lib",
    "mingw64/lib/gcc/x86_64-w64-mingw32/15.2.0",
    "mingw64/lib/gcc",
    "mingw64/x86_64-w64-mingw32/lib",
    "mingw64/lib/octave/11.3.0"
)
$effectiveSearchDirectories = New-Object Collections.Generic.List[string]
foreach ($relative in $effectiveSearchDirectoryRelatives) {
    $native = [IO.Path]::GetFullPath(
        (Join-Path $root $relative.Replace("/", "\")))
    if (-not (Test-IsStrictDescendant -Path $native -Parent $root) -or
            -not (Test-Path -LiteralPath $native -PathType Container)) {
        throw "audited library search directory is missing or escapes: $relative"
    }
    Assert-NoReparsePathComponents -Path $native
    $effectiveSearchDirectories.Add($native)
}

$closureQueue = New-Object Collections.Generic.Queue[string]
foreach ($relative in $selectionRootPathSet) {
    $closureQueue.Enqueue(
        [IO.Path]::GetFullPath((Join-Path $root $relative.Replace("/", "\"))))
}
$closureVisited =
    New-Object Collections.Generic.HashSet[string](
        [StringComparer]::OrdinalIgnoreCase)
$closureEdges =
    New-Object Collections.Generic.HashSet[string](
        [StringComparer]::OrdinalIgnoreCase)
$uniqueLibraryTokens =
    New-Object Collections.Generic.HashSet[string](
        [StringComparer]::OrdinalIgnoreCase)
$resolvedLibraryTokens =
    New-Object Collections.Generic.HashSet[string](
        [StringComparer]::OrdinalIgnoreCase)
$resolvedSeedRootSet =
    New-Object Collections.Generic.HashSet[string](
        [StringComparer]::OrdinalIgnoreCase)

while ($closureQueue.Count -ne 0) {
    $closurePath = $closureQueue.Dequeue()
    if (-not $closureVisited.Add($closurePath)) {
        continue
    }
    $closureRelative =
        $closurePath.Substring($root.Length + 1).Replace("\", "/")
    $closureBytes = [IO.File]::ReadAllBytes($closurePath)
    if (@($closureBytes | Where-Object { $_ -gt 0x7f }).Count -ne 0) {
        throw "unsupported non-ASCII libtool archive in closure: $closureRelative"
    }
    $closureText = $ascii.GetString($closureBytes)
    $dependencyAssignments = @([regex]::Matches(
        $closureText,
        "(?m)^dependency_libs='(?<value>.*)'\s*(?:\r?$)"))
    if ($dependencyAssignments.Count -ne 1) {
        throw "malformed or missing dependency_libs assignment in closure: $closureRelative"
    }
    $closureValue = $dependencyAssignments[0].Groups["value"].Value
    $closureCleanValue = [regex]::Replace(
        $closureValue,
        "(^|\s)'(?<path>/usr/[^'\s]+)'(?=/[^'\s]+\.la(?:\s|$))",
        '${1}${path}')
    if ($closureCleanValue.Contains("'")) {
        throw "unsupported quote form in closure: $closureRelative"
    }
    $closureTokens = @($closureCleanValue.Trim() -split "\s+" |
        Where-Object { $_.Length -ne 0 })
    foreach ($token in $closureTokens) {
        $dependencyPath = $null
        if ($token.StartsWith("-L") -or $token.StartsWith("-R")) {
            $directory = $token.Substring(2)
            if (-not $directoryMap.ContainsKey($directory) -and
                    $directory -notmatch '^/mingw64/.+') {
                throw "unsupported absolute directory token '$token' in closure: $closureRelative"
            }
            continue
        }
        elseif ($token -match '^(?i:/usr/.+\.la)$') {
            $name = [IO.Path]::GetFileName($token).ToLowerInvariant()
            if (-not $candidatesByName.ContainsKey($name)) {
                throw "missing libtool archive candidate in closure for '$token'"
            }
            $candidates = $candidatesByName[$name].ToArray()
            if ($candidates.Count -ne 1) {
                throw "ambiguous libtool archive candidate in closure for '$token'"
            }
            $dependencyPath = $candidates[0]
        }
        elseif ($token -match '^/mingw64/.+\.la$') {
            $dependencyPath = [IO.Path]::GetFullPath(
                (Join-Path $root $token.TrimStart("/").Replace("/", "\")))
            if (-not (Test-IsStrictDescendant `
                    -Path $dependencyPath -Parent $root) -or
                    -not (Test-Path -LiteralPath $dependencyPath -PathType Leaf)) {
                throw "portable .la closure dependency escapes or is missing: $token"
            }
        }
        elseif ($token -match '(?i)\.la$') {
            throw "unsupported relative or escaping .la closure dependency '$token'"
        }
        elseif ($token -match '^-l(?<name>[A-Za-z0-9_+.-]+)$') {
            $libraryName = $Matches["name"]
            if ($libraryName -match '\.\.' -or
                    $libraryName -notmatch '^[A-Za-z0-9_+]') {
                throw "unsafe library token in closure: $token"
            }
            [void] $uniqueLibraryTokens.Add($libraryName)
            $laName = ("lib" + $libraryName + ".la").ToLowerInvariant()
            $selectedCandidates = @()
            if ($candidatesByName.ContainsKey($laName)) {
                $selectedCandidates = @(
                    $candidatesByName[$laName].ToArray() | Where-Object {
                        $candidateRelative =
                            $_.Substring($root.Length + 1).Replace("\", "/")
                        $selectionPathSet.Contains($candidateRelative)
                    })
            }
            if ($selectedCandidates.Count -gt 1) {
                throw "ambiguous selected .la candidate for '$token'"
            }
            if ($selectedCandidates.Count -eq 1) {
                $dependencyPath = $selectedCandidates[0]
                $dependencyDirectory = Split-Path -Parent $dependencyPath
                if (-not @($effectiveSearchDirectories | Where-Object {
                        $_.Equals(
                            $dependencyDirectory,
                            [StringComparison]::OrdinalIgnoreCase)
                    }).Count) {
                    throw "selected .la candidate is outside audited search directories: $token"
                }
            }
            else {
                $resolvedArchive = $null
                foreach ($searchDirectory in $effectiveSearchDirectories) {
                    foreach ($candidateName in @(
                            "lib$libraryName.la",
                            "lib$libraryName.dll.a",
                            "lib$libraryName.a")) {
                        $candidate = Join-Path $searchDirectory $candidateName
                        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
                            Assert-RegularFile -Path $candidate `
                                -Description "resolved library candidate"
                            $resolvedArchive = $candidate
                            break
                        }
                    }
                    if ($null -ne $resolvedArchive) {
                        break
                    }
                }
                if ($null -eq $resolvedArchive) {
                    throw "missing library candidate in audited search directories: $token"
                }
                if ($resolvedArchive.EndsWith(
                        ".la", [StringComparison]::OrdinalIgnoreCase)) {
                    $dependencyPath = $resolvedArchive
                }
            }
            [void] $resolvedLibraryTokens.Add($libraryName)
        }
        elseif ($token.StartsWith("/") -or
                $token -match '^[A-Za-z]:[\\/]') {
            throw "unsupported absolute token in closure: $token"
        }

        if ($null -ne $dependencyPath) {
            Assert-RegularFile -Path $dependencyPath `
                -Description "closure libtool archive"
            $dependencyRelative =
                $dependencyPath.Substring($root.Length + 1).Replace("\", "/")
            if (-not $selectionPathSet.Contains($dependencyRelative)) {
                throw (".la selection is missing closure dependency: {0} -> {1}" -f
                    $closureRelative, $dependencyRelative)
            }
            [void] $closureEdges.Add(
                $closureRelative + "`t" + $dependencyRelative)
            if (-not $closureVisited.Contains($dependencyPath)) {
                $closureQueue.Enqueue($dependencyPath)
            }
        }
    }
}

foreach ($libraryName in $seedLibraryTokens) {
    [void] $uniqueLibraryTokens.Add($libraryName)
    $token = "-l$libraryName"
    $laNames = @(
        ("lib" + $libraryName + ".la").ToLowerInvariant())
    if ($disposableParent -match $testParentPattern) {
        $laNames += ($libraryName + ".la").ToLowerInvariant()
    }
    $selectedCandidates = @()
    foreach ($laName in $laNames) {
        if ($candidatesByName.ContainsKey($laName)) {
            $selectedCandidates += @(
                $candidatesByName[$laName].ToArray() | Where-Object {
                    $candidateRelative =
                        $_.Substring($root.Length + 1).Replace("\", "/")
                    $selectionPathSet.Contains($candidateRelative)
                })
        }
    }
    if ($selectedCandidates.Count -gt 1) {
        throw "ambiguous selected .la candidate for seed '$token'"
    }
    if ($selectedCandidates.Count -eq 1) {
        $seedPath = $selectedCandidates[0]
        $seedRelative =
            $seedPath.Substring($root.Length + 1).Replace("\", "/")
        if (-not $selectionRootPathSet.Contains($seedRelative)) {
            throw "seed library resolves to a selected non-root .la: $token"
        }
        $seedDirectory = Split-Path -Parent $seedPath
        if (-not @($effectiveSearchDirectories | Where-Object {
                $_.Equals(
                    $seedDirectory,
                    [StringComparison]::OrdinalIgnoreCase)
            }).Count) {
            throw "seed .la root is outside audited search directories: $token"
        }
        Assert-RegularFile -Path $seedPath -Description "seed .la root"
        [void] $resolvedSeedRootSet.Add($seedRelative)
    }
    else {
        $resolvedArchive = $null
        foreach ($searchDirectory in $effectiveSearchDirectories) {
            foreach ($candidateName in @(
                    "lib$libraryName.la",
                    "lib$libraryName.dll.a",
                    "lib$libraryName.a")) {
                $candidate = Join-Path $searchDirectory $candidateName
                if (Test-Path -LiteralPath $candidate -PathType Leaf) {
                    Assert-RegularFile -Path $candidate `
                        -Description "resolved seed library candidate"
                    $resolvedArchive = $candidate
                    break
                }
            }
            if ($null -ne $resolvedArchive) {
                break
            }
        }
        if ($null -eq $resolvedArchive) {
            throw "missing library candidate in audited search directories: $token"
        }
        if ($resolvedArchive.EndsWith(
                ".la", [StringComparison]::OrdinalIgnoreCase)) {
            $relative =
                $resolvedArchive.Substring($root.Length + 1).Replace("\", "/")
            throw "seed library resolves to an unselected .la: $relative"
        }
    }
    [void] $resolvedLibraryTokens.Add($libraryName)
}
if ($resolvedSeedRootSet.Count -ne $selectionRootPathSet.Count) {
    throw "seed library roots do not equal the declared .la roots"
}
foreach ($relative in $selectionRootPathSet) {
    if (-not $resolvedSeedRootSet.Contains($relative)) {
        throw "declared .la root was not resolved by the seed libraries: $relative"
    }
}

foreach ($relative in $selectionPathSet) {
    $native = [IO.Path]::GetFullPath(
        (Join-Path $root $relative.Replace("/", "\")))
    if (-not $closureVisited.Contains($native)) {
        throw ".la selection contains an extra unreachable entry: $relative"
    }
}
if ($resolvedLibraryTokens.Count -ne $uniqueLibraryTokens.Count) {
    throw "not every unique -l token resolved in the audited search directories"
}
if ($disposableParent -notmatch $testParentPattern) {
    if ($closureEdges.Count -ne 30 -or
            $uniqueLibraryTokens.Count -ne 44 -or
            $resolvedLibraryTokens.Count -ne 44) {
        throw ("Octave 11.3.0 closure contract mismatch: edges={0}, " +
            "unique-l={1}, resolved-l={2}" -f
            $closureEdges.Count,
            $uniqueLibraryTokens.Count,
            $resolvedLibraryTokens.Count)
    }
}

$replacementBytes = @{}
$changedInventory = New-Object Collections.Generic.List[object]
$emittedTargetsByKey = @{}
$stalePattern = '(?i)(?:/usr(?:/|$)|C:[\\/]+Tools[\\/]+GNU Octave[\\/]+11\.3\.0)'

foreach ($file in $selectedLaFiles) {
    $originalBytes = [IO.File]::ReadAllBytes($file.FullName)
    if (@($originalBytes | Where-Object { $_ -gt 0x7f }).Count -ne 0) {
        throw "unsupported non-ASCII libtool archive: $($file.FullName)"
    }
    $text = $ascii.GetString($originalBytes)
    $lines = [regex]::Split($text, '(?<=\n)')
    $outputLines = New-Object Collections.Generic.List[string]

    foreach ($lineWithEnding in $lines) {
        if ($lineWithEnding.Length -eq 0) {
            continue
        }
        $line = $lineWithEnding
        $ending = ""
        if ($line.EndsWith("`r`n")) {
            $line = $line.Substring(0, $line.Length - 2)
            $ending = "`r`n"
        }
        elseif ($line.EndsWith("`n") -or $line.EndsWith("`r")) {
            $ending = $line.Substring($line.Length - 1)
            $line = $line.Substring(0, $line.Length - 1)
        }

        if ($line -notmatch $stalePattern) {
            $outputLines.Add($line + $ending)
            continue
        }

        $assignment = [regex]::Match(
            $line, "^(?<key>[A-Za-z_][A-Za-z0-9_]*)='(?<value>.*)'(?<suffix>\s*)$")
        if (-not $assignment.Success) {
            throw "unsupported assignment containing an absolute stale path in $($file.FullName): $line"
        }

        $key = $assignment.Groups["key"].Value
        $value = $assignment.Groups["value"].Value
        $suffix = $assignment.Groups["suffix"].Value
        if ($key -eq "dependency_libs") {
            $cleanValue = [regex]::Replace(
                $value,
                "(^|\s)'(?<path>/usr/[^'\s]+)'(?=/[^'\s]+\.la(?:\s|$))",
                '${1}${path}')
            if ($cleanValue.Contains("'")) {
                throw "unsupported quote form in dependency_libs in $($file.FullName)"
            }
            $tokens = @($cleanValue.Trim() -split "\s+" |
                Where-Object { $_.Length -ne 0 })
            $newTokens = New-Object Collections.Generic.List[string]
            foreach ($token in $tokens) {
                if ($token.StartsWith("-L") -or $token.StartsWith("-R")) {
                    $prefix = $token.Substring(0, 2)
                    $directory = $token.Substring(2)
                    $emittedDirectory = $null
                    if ($directoryMap.ContainsKey($directory)) {
                        $emittedDirectory = $directoryMap[$directory]
                    }
                    elseif ($directory -match '^/mingw64/.+') {
                        $emittedDirectory = $directory
                    }
                    elseif ($directory -match '(?i:^C:[\\/]+Tools[\\/]+GNU Octave)') {
                        throw "permanent absolute directory token '$token' is forbidden"
                    }
                    else {
                        throw "unsupported absolute directory token '$token' in $($file.FullName)"
                    }
                    $newTokens.Add($prefix + $emittedDirectory)
                    Add-EmittedTarget -Targets $emittedTargetsByKey `
                        -Kind Directory -PortablePath $emittedDirectory
                }
                elseif ($token -match '^(?i:/usr/.+\.la)$') {
                    $name = [IO.Path]::GetFileName($token).ToLowerInvariant()
                    if (-not $candidatesByName.ContainsKey($name)) {
                        throw "missing libtool archive candidate for '$token'"
                    }
                    $candidates = $candidatesByName[$name].ToArray()
                    if ($candidates.Count -ne 1) {
                        throw "ambiguous libtool archive candidate for '$token': $($candidates -join ', ')"
                    }
                    Assert-RegularFile -Path $candidates[0] `
                        -Description "resolved libtool archive"
                    $emittedFile = Convert-ToPortablePath `
                        -Path $candidates[0] -MingwRoot $mingwRoot
                    $newTokens.Add($emittedFile)
                    Add-EmittedTarget -Targets $emittedTargetsByKey `
                        -Kind File -PortablePath $emittedFile
                }
                elseif ($token -match '^/mingw64/.+\.la$') {
                    $newTokens.Add($token)
                    Add-EmittedTarget -Targets $emittedTargetsByKey `
                        -Kind File -PortablePath $token
                }
                elseif ($token -match '^(?i:/usr(?:/|$))') {
                    throw "unsupported absolute dependency token '$token' in $($file.FullName)"
                }
                elseif ($token -match '(?i:^C:[\\/]+Tools[\\/]+GNU Octave)') {
                    throw "permanent absolute dependency token '$token' is forbidden"
                }
                else {
                    $newTokens.Add($token)
                }
            }
            $newValue = if ($newTokens.Count -eq 0) {
                ""
            }
            else {
                " " + ($newTokens -join " ")
            }
            $outputLines.Add(("{0}='{1}'{2}{3}" -f
                    $key, $newValue, $suffix, $ending))
        }
        elseif ($key -eq "libdir") {
            if ($directoryMap.ContainsKey($value)) {
                $emittedDirectory = $directoryMap[$value]
            }
            elseif ($value -match '^/mingw64/.+') {
                $emittedDirectory = $value
            }
            else {
                throw "unsupported libdir '$value' in $($file.FullName)"
            }
            $outputLines.Add(("{0}='{1}'{2}{3}" -f
                    $key, $emittedDirectory, $suffix, $ending))
            Add-EmittedTarget -Targets $emittedTargetsByKey `
                -Kind Directory -PortablePath $emittedDirectory
        }
        else {
            throw "unsupported assignment '$key' containing a stale absolute path in $($file.FullName)"
        }
    }

    $newText = $outputLines -join ""
    if ($newText -match $stalePattern) {
        throw "postcondition failed while planning $($file.FullName): stale absolute path remains"
    }
    $newBytes = $ascii.GetBytes($newText)
    if ((Get-Sha256Bytes -Bytes $newBytes) -ne
            (Get-Sha256Bytes -Bytes $originalBytes)) {
        Register-EmittedTargetsFromText -Text $newText `
            -Targets $emittedTargetsByKey -Description $file.FullName
        $replacementBytes[$file.FullName] = $newBytes
        $changedInventory.Add([pscustomobject] @{
            Path = $file.FullName.Substring($root.Length + 1).Replace("\", "/")
            OldSha256 = Get-Sha256Bytes -Bytes $originalBytes
            NewSha256 = Get-Sha256Bytes -Bytes $newBytes
        })
    }
}

$emittedTargets = [object[]] @($emittedTargetsByKey.Values |
    Sort-Object Kind, PortablePath)
if ($emittedTargets.Count -ne 0) {
    Assert-EmittedTargets -Targets $emittedTargets `
        -HeldRootIdentity $rootIdentityHandle `
        -ExpectedRootIdentity $expectedRootIdentity -Root $root
}

$predicted = Get-TreeManifest -Root $root `
    -ReplacementBytes $replacementBytes -ManifestFormat $ManifestFormat `
    -ManifestOrderPaths $manifestOrderPaths
foreach ($file in $unselectedLaFiles) {
    $current = Get-Sha256Bytes -Bytes ([IO.File]::ReadAllBytes($file.FullName))
    if ($current -ne $unselectedHashes[$file.FullName]) {
        throw "unselected libtool archive changed during planning: $($file.FullName)"
    }
}
$result = [ordered] @{
    Mode = $Mode
    ManifestFormat = $ManifestFormat
    ManifestCulture = if ($ManifestFormat -eq "PowerShellTsvV1") {
        [Globalization.CultureInfo]::CurrentCulture.Name
    }
    else {
        $null
    }
    ManifestOrderReferencePath = $manifestOrderReferenceCanonical
    ManifestOrderReferenceSha256 = $manifestOrderReferenceSha256
    LaSelectionManifestPath = $laSelectionCanonical
    LaSelectionManifestSha256 = $laSelectionSha256
    SeedLibraryManifestPath = $seedLibraryCanonical
    SeedLibraryManifestSha256 = $seedLibrarySha256
    SeedLibraryTokenCount = $seedLibraryTokens.Count
    SelectionFileCount = $selectionPathSet.Count
    SelectionRootCount = $selectionRootPathSet.Count
    UnselectedLaFileCount = $unselectedLaFiles.Count
    ClosureEdgeCount = $closureEdges.Count
    UniqueLibraryTokenCount = $uniqueLibraryTokens.Count
    ResolvedLibraryTokenCount = $resolvedLibraryTokens.Count
    EffectiveSearchDirectoryCount = $effectiveSearchDirectories.Count
    EffectiveSearchDirectories = $effectiveSearchDirectoryRelatives
    ToolchainRoot = $root
    BaselineFileCount = $baseline.FileCount
    BaselineTotalBytes = $baseline.TotalBytes
    BaselineManifestSha256 = $baseline.Sha256
    ChangedFileCount = $changedInventory.Count
    ChangedFiles = $changedInventory.ToArray()
    ResultFileCount = $predicted.FileCount
    ResultTotalBytes = $predicted.TotalBytes
    ResultManifestSha256 = $predicted.Sha256
    CompilerTempRoot = $compilerTempRoot
    CompilerEnvironmentRestored = $true
}

if ($Mode -eq "Apply" -and $replacementBytes.Count -ne 0) {
    $transactionRoot = Join-Path $disposableParent `
        (".todo51-la-normalize-" + [guid]::NewGuid().ToString("N"))
    [void] (New-Item -ItemType Directory -Path $transactionRoot)
    $replaced = New-Object Collections.Generic.List[object]
    $committed = $false
    $testRemovedDirectory = $null
    try {
        [int] $index = 0
        foreach ($path in @($replacementBytes.Keys | Sort-Object)) {
            if ($index -eq 1 -and
                    $TestFailurePoint -eq "BeforeSecondReplacement") {
                throw "injected failure before replacement 2"
            }
            if ($index -eq 1 -and $TestFailurePoint -eq
                    "RootIdentityMismatchBeforeSecondReplacement") {
                Assert-StableRootIdentity -HeldIdentity $rootIdentityHandle `
                    -ExpectedIdentity "TEST-IDENTITY-MISMATCH" -ExpectedPath $root
            }
            Assert-StableRootIdentity -HeldIdentity $rootIdentityHandle `
                -ExpectedIdentity $expectedRootIdentity -ExpectedPath $root
            $writeTarget = [pscustomobject] @{
                Kind = "File"
                PortablePath = "/" + $path.Substring(
                    $root.Length + 1).Replace("\", "/")
            }
            Assert-EmittedTargets -Targets ([object[]] @($writeTarget)) `
                -HeldRootIdentity $rootIdentityHandle `
                -ExpectedRootIdentity $expectedRootIdentity -Root $root
            $currentHash = Get-Sha256Bytes -Bytes ([IO.File]::ReadAllBytes($path))
            $inventoryEntry = @($changedInventory |
                Where-Object {
                    $_.Path -eq $path.Substring($root.Length + 1).Replace("\", "/")
                })[0]
            if ($currentHash -ne $inventoryEntry.OldSha256) {
                throw "source changed after planning: $path"
            }

            $temp = Join-Path $transactionRoot ("{0:D4}.new" -f $index)
            $backup = Join-Path $transactionRoot ("{0:D4}.bak" -f $index)
            [IO.File]::WriteAllBytes($temp, [byte[]] $replacementBytes[$path])
            [IO.File]::Replace($temp, $path, $backup, $true)
            $replaced.Add([pscustomobject] @{ Path = $path; Backup = $backup })
            $index++
        }

        Assert-StableRootIdentity -HeldIdentity $rootIdentityHandle `
            -ExpectedIdentity $expectedRootIdentity -ExpectedPath $root
        if ($TestFailurePoint -eq "RemoveEmittedTargetAfterReplacement") {
            foreach ($target in @($emittedTargets |
                    Where-Object { $_.Kind -eq "Directory" } |
                    Sort-Object PortablePath -Descending)) {
                $candidate = Get-NativeEmittedTargetPath `
                    -PortablePath $target.PortablePath -Root $root
                if (@(Get-ChildItem -LiteralPath $candidate -Force).Count -eq 0) {
                    Remove-Item -LiteralPath $candidate
                    $testRemovedDirectory = $candidate
                    break
                }
            }
            if ($null -eq $testRemovedDirectory) {
                throw "test injection could not find an empty emitted target directory"
            }
        }
        if ($emittedTargets.Count -ne 0) {
            Assert-EmittedTargets -Targets $emittedTargets `
                -HeldRootIdentity $rootIdentityHandle `
                -ExpectedRootIdentity $expectedRootIdentity -Root $root
        }
        foreach ($entry in $changedInventory) {
            $path = Join-Path $root $entry.Path.Replace("/", "\")
            Assert-RegularFile -Path $path -Description "normalized libtool archive"
            $actualHash = Get-Sha256Bytes -Bytes ([IO.File]::ReadAllBytes($path))
            if ($actualHash -ne $entry.NewSha256) {
                throw "normalized file hash mismatch: $path"
            }
            if ($ascii.GetString([IO.File]::ReadAllBytes($path)) -match $stalePattern) {
                throw "normalized file retained a stale absolute path: $path"
            }
        }
        foreach ($file in $unselectedLaFiles) {
            $actualUnselectedHash =
                Get-Sha256Bytes -Bytes ([IO.File]::ReadAllBytes($file.FullName))
            if ($actualUnselectedHash -ne $unselectedHashes[$file.FullName]) {
                throw "unselected libtool archive changed: $($file.FullName)"
            }
        }
        $actual = Get-TreeManifest -Root $root -ManifestFormat $ManifestFormat `
            -ManifestOrderPaths $manifestOrderPaths
        if ($actual.FileCount -ne $predicted.FileCount -or
                $actual.TotalBytes -ne $predicted.TotalBytes -or
                $actual.Sha256 -ne $predicted.Sha256) {
            throw "result manifest differs from the fully planned manifest"
        }
        $committed = $true
    }
    finally {
        if (-not $committed) {
            for ($i = $replaced.Count - 1; $i -ge 0; $i--) {
                $entry = $replaced[$i]
                if (Test-Path -LiteralPath $entry.Backup -PathType Leaf) {
                    $discard = Join-Path $transactionRoot `
                        ("rollback-{0:D4}.discard" -f $i)
                    [IO.File]::Replace(
                        $entry.Backup, $entry.Path, $discard, $true)
                }
            }
            if ($null -ne $testRemovedDirectory -and
                    -not (Test-Path -LiteralPath $testRemovedDirectory)) {
                [void] (New-Item -ItemType Directory -Path $testRemovedDirectory)
            }
            $rollbackManifest = Get-TreeManifest -Root $root `
                -ManifestFormat $ManifestFormat `
                -ManifestOrderPaths $manifestOrderPaths
            if ($rollbackManifest.FileCount -ne $baseline.FileCount -or
                    $rollbackManifest.TotalBytes -ne $baseline.TotalBytes -or
                    $rollbackManifest.Sha256 -ne $baseline.Sha256) {
                throw "rollback manifest differs from the selected baseline format"
            }
        }
        if (Test-Path -LiteralPath $transactionRoot) {
            Remove-Item -LiteralPath $transactionRoot -Recurse -Force
        }
    }
}

$result | ConvertTo-Json -Depth 5
}
finally {
    $rootIdentityHandle.Dispose()
}
