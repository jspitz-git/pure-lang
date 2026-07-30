[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string] $ToolchainRoot,
    [Parameter(Mandatory = $true)][string] $DisposableParentRoot,
    [Parameter(Mandatory = $true)][long] $ExpectedFileCount,
    [Parameter(Mandatory = $true)][long] $ExpectedTotalBytes,
    [Parameter(Mandatory = $true)][ValidatePattern("^[0-9A-Fa-f]{64}$")]
    [string] $ExpectedManifestSha256,
    [ValidateSet("Plan", "Apply")][string] $Mode = "Plan"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$ascii = [Text.Encoding]::ASCII

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
Assert-NoReparsePoints -Root $root

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
                    if ($directoryMap.ContainsKey($directory)) {
                        $newTokens.Add($prefix + $directoryMap[$directory])
                    }
                    elseif ($directory -match '^(?i:/usr(?:/|$))') {
                        throw "unsupported absolute directory token '$token' in $($file.FullName)"
                    }
                    elseif ($directory -match '(?i:^C:[\\/]+Tools[\\/]+GNU Octave)') {
                        throw "permanent absolute directory token '$token' is forbidden"
                    }
                    else {
                        $newTokens.Add($token)
                    }
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
                    $newTokens.Add((Convert-ToPortablePath `
                        -Path $candidates[0] -MingwRoot $mingwRoot))
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
            if (-not $directoryMap.ContainsKey($value)) {
                throw "unsupported libdir '$value' in $($file.FullName)"
            }
            $outputLines.Add(("{0}='{1}'{2}{3}" -f
                    $key, $directoryMap[$value], $suffix, $ending))
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
        $replacementBytes[$file.FullName] = $newBytes
        $changedInventory.Add([pscustomobject] @{
            Path = $file.FullName.Substring($root.Length + 1).Replace("\", "/")
            OldSha256 = Get-Sha256Bytes -Bytes $originalBytes
            NewSha256 = Get-Sha256Bytes -Bytes $newBytes
        })
    }
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
    try {
        [int] $index = 0
        foreach ($path in @($replacementBytes.Keys | Sort-Object)) {
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
                    [IO.File]::Replace($entry.Backup, $entry.Path, $null, $true)
                }
            }
        }
        if (Test-Path -LiteralPath $transactionRoot) {
            Remove-Item -LiteralPath $transactionRoot -Recurse -Force
        }
    }
}

$result | ConvertTo-Json -Depth 5
