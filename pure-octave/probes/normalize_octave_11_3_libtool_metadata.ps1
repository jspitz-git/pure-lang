[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string] $ToolchainRoot,
    [Parameter(Mandatory = $true)][string] $DisposableParentRoot,
    [Parameter(Mandatory = $true)][long] $ExpectedFileCount,
    [Parameter(Mandatory = $true)][long] $ExpectedTotalBytes,
    [Parameter(Mandatory = $true)][ValidatePattern("^[0-9A-Fa-f]{64}$")]
    [string] $ExpectedManifestSha256,
    [ValidateSet("Plan", "Apply")][string] $Mode = "Plan",
    [ValidateSet(
        "None",
        "RootIdentityMismatchBeforeSecondReplacement",
        "BeforeSecondReplacement",
        "RemoveEmittedTargetAfterReplacement")]
    [string] $TestFailurePoint = "None"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$ascii = [Text.Encoding]::ASCII

Add-Type -TypeDefinition @'
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
    param([Parameter(Mandatory = $true)][byte[]] $Bytes)

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

function Get-TreeManifest {
    param(
        [Parameter(Mandatory = $true)][string] $Root,
        [hashtable] $ReplacementBytes
    )

    $files = @(Get-ChildItem -LiteralPath $Root -Recurse -Force -File)
    $relativePaths = [string[]] @($files | ForEach-Object {
        $_.FullName.Substring($Root.Length + 1).Replace("\", "/")
    })
    [Array]::Sort($relativePaths, [StringComparer]::Ordinal)

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

    $manifestBytes = $utf8NoBom.GetBytes(($lines -join "`n"))
    return [pscustomobject] @{
        FileCount = [long] $relativePaths.Count
        TotalBytes = $totalBytes
        Sha256 = Get-Sha256Bytes -Bytes $manifestBytes
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
Assert-NoReparsePoints -Root $root

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

if ($TestFailurePoint -ne "None") {
    $testParentPattern = '^C:\\tmp\\todo51-normalizer-tests-[0-9a-f]{32}$'
    if ($disposableParent -notmatch $testParentPattern -or
            -not (Test-IsStrictDescendant -Path $root -Parent $disposableParent)) {
        $rootIdentityHandle.Dispose()
        throw "test failure injection is forbidden outside a synthetic test root"
    }
}

try {
Assert-StableRootIdentity -HeldIdentity $rootIdentityHandle `
    -ExpectedIdentity $expectedRootIdentity -ExpectedPath $root

$baseline = Get-TreeManifest -Root $root
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

$laFiles = @(Get-ChildItem -LiteralPath $mingwRoot -Recurse -Force -File `
    -Filter "*.la")
$candidatesByName = @{}
foreach ($file in $laFiles) {
    Assert-RegularFile -Path $file.FullName -Description "libtool archive candidate"
    $key = $file.Name.ToLowerInvariant()
    if (-not $candidatesByName.ContainsKey($key)) {
        $candidatesByName[$key] = New-Object Collections.Generic.List[string]
    }
    $candidatesByName[$key].Add($file.FullName)
}

$replacementBytes = @{}
$changedInventory = New-Object Collections.Generic.List[object]
$emittedTargetsByKey = @{}
$stalePattern = '(?i)(?:/usr(?:/|$)|C:[\\/]+Tools[\\/]+GNU Octave[\\/]+11\.3\.0)'

foreach ($file in @($laFiles | Sort-Object FullName)) {
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

$predicted = Get-TreeManifest -Root $root -ReplacementBytes $replacementBytes
$result = [ordered] @{
    Mode = $Mode
    ToolchainRoot = $root
    BaselineFileCount = $baseline.FileCount
    BaselineTotalBytes = $baseline.TotalBytes
    BaselineManifestSha256 = $baseline.Sha256
    ChangedFileCount = $changedInventory.Count
    ChangedFiles = $changedInventory.ToArray()
    ResultFileCount = $predicted.FileCount
    ResultTotalBytes = $predicted.TotalBytes
    ResultManifestSha256 = $predicted.Sha256
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
        $actual = Get-TreeManifest -Root $root
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
