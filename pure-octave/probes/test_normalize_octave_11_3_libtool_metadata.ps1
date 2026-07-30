Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$normalizer = Join-Path $PSScriptRoot "normalize_octave_11_3_libtool_metadata.ps1"
$testRoot = Join-Path "C:\tmp" ("todo51-normalizer-tests-" + [guid]::NewGuid().ToString("N"))
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)

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

function Get-TreeManifest {
    param(
        [Parameter(Mandatory = $true)][string] $Root,
        [ValidateSet("OrdinalLfV1", "PowerShellTsvV1")]
        [string] $ManifestFormat = "OrdinalLfV1",
        [string] $ManifestOrderReferencePath = ""
    )

    $canonical = [IO.Path]::GetFullPath($Root).TrimEnd("\")
    $files = @(Get-ChildItem -LiteralPath $canonical -Recurse -Force -File)
    $relativePaths = [string[]] @($files | ForEach-Object {
        $_.FullName.Substring($canonical.Length + 1).Replace("\", "/")
    })
    if ($ManifestFormat -eq "PowerShellTsvV1") {
        if ($ManifestOrderReferencePath.Length -ne 0) {
            $relativePaths = [string[]] @(
                [IO.File]::ReadAllLines($ManifestOrderReferencePath) |
                    ForEach-Object { $_.Split("`t")[0] })
        }
        else {
            [Array]::Sort($relativePaths, [StringComparer]::CurrentCulture)
        }
    }
    else {
        [Array]::Sort($relativePaths, [StringComparer]::Ordinal)
    }

    $lines = New-Object Collections.Generic.List[string]
    [long] $bytes = 0
    foreach ($relative in $relativePaths) {
        $path = Join-Path $canonical $relative.Replace("/", "\")
        $file = Get-Item -LiteralPath $path
        $bytes += $file.Length
        $hash = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
        $lines.Add(("{0}`t{1}`t{2}" -f $relative, $file.Length, $hash))
    }

    $serialized = if ($ManifestFormat -eq "PowerShellTsvV1") {
        if ($lines.Count -eq 0) { "" } else { ($lines -join "`r`n") + "`r`n" }
    }
    else {
        $lines -join "`n"
    }
    $manifestBytes = $utf8NoBom.GetBytes($serialized)
    return [pscustomobject] @{
        FileCount = $relativePaths.Count
        TotalBytes = $bytes
        Sha256 = Get-Sha256Bytes -Bytes $manifestBytes
        ManifestFormat = $ManifestFormat
        ManifestByteCount = $manifestBytes.Length
        FirstPath = if ($relativePaths.Count -eq 0) { $null } else {
            $relativePaths[0]
        }
        EndsWithCrlf = ($manifestBytes.Length -ge 2 -and
            $manifestBytes[$manifestBytes.Length - 2] -eq 13 -and
            $manifestBytes[$manifestBytes.Length - 1] -eq 10)
        ManifestOrderReferencePath = $ManifestOrderReferencePath
        ExpectedManifestOrderReferenceSha256 =
            if ($ManifestOrderReferencePath.Length -eq 0) {
                ""
            }
            else {
                (Get-FileHash -LiteralPath $ManifestOrderReferencePath `
                    -Algorithm SHA256).Hash
            }
    }
}

function New-ManifestOrderReference {
    param(
        [Parameter(Mandatory = $true)][string] $Root,
        [Parameter(Mandatory = $true)][string] $Path
    )

    $canonical = [IO.Path]::GetFullPath($Root).TrimEnd("\")
    $files = @(Get-ChildItem -LiteralPath $canonical -Recurse -Force -File |
        Sort-Object {
            $_.FullName.Substring($canonical.Length + 1).Replace("\", "/")
        })
    $lines = @($files | ForEach-Object {
        $relative = $_.FullName.Substring($canonical.Length + 1).Replace("\", "/")
        "{0}`t{1}`t{2}" -f
            $relative, $_.Length,
            (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
    })
    [IO.File]::WriteAllBytes(
        $Path,
        $utf8NoBom.GetBytes(($lines -join "`r`n") + "`r`n"))
    return [pscustomobject] @{
        Path = $Path
        Sha256 = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
    }
}

function New-LaSelectionContract {
    param(
        [Parameter(Mandatory = $true)][string] $ParentRoot,
        [Parameter(Mandatory = $true)][string[]] $Roots,
        [string[]] $Dependencies = @(),
        [string[]] $RawLines
    )

    $path = Join-Path $ParentRoot (
        "la-selection-" + [guid]::NewGuid().ToString("N") + ".tsv")
    $lines = if ($null -ne $RawLines) {
        [string[]] $RawLines
    }
    else {
        [string[]] @(
            @($Roots | ForEach-Object { "root`t$_" }) +
            @($Dependencies | ForEach-Object { "dependency`t$_" }))
    }
    [IO.File]::WriteAllBytes(
        $path,
        $utf8NoBom.GetBytes(($lines -join "`r`n") + "`r`n"))
    return [pscustomobject] @{
        Path = $path
        Sha256 = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
        RootCount = @($Roots).Count
        Lines = $lines
    }
}

function New-SeedLibraryContract {
    param(
        [Parameter(Mandatory = $true)][string] $ParentRoot,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()]
        [string[]] $Tokens
    )

    $path = Join-Path $ParentRoot (
        "seed-libraries-" + [guid]::NewGuid().ToString("N") + ".txt")
    [IO.File]::WriteAllBytes(
        $path,
        $utf8NoBom.GetBytes(($Tokens -join "`r`n") + "`r`n"))
    return [pscustomobject] @{
        Path = $path
        Sha256 = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
        Count = @($Tokens).Count
        Tokens = [string[]] $Tokens
    }
}

function Write-AsciiFile {
    param(
        [Parameter(Mandatory = $true)][string] $Path,
        [Parameter(Mandatory = $true)][string] $Text
    )

    $parent = Split-Path -Parent $Path
    [void] (New-Item -ItemType Directory -Path $parent -Force)
    [IO.File]::WriteAllText($Path, $Text, [Text.Encoding]::ASCII)
}

function New-Fixture {
    param(
        [Parameter(Mandatory = $true)][string] $Name,
        [switch] $NoCandidate,
        [switch] $AmbiguousCandidate,
        [string] $ExtraDependencyToken = ""
    )

    $root = Join-Path $testRoot $Name
    $mingw = Join-Path $root "mingw64"
    $mappedDirectories = @(
        "lib",
        "lib\gcc\x86_64-w64-mingw32\15.2.0",
        "lib\GraphicsMagick-1.3.46\modules-Q16\coders",
        "lib\GraphicsMagick-1.3.46\modules-Q16\filters",
        "lib\octave\11.3.0",
        "lib\pstoedit",
        "libexec\gcc\x86_64-w64-mingw32\15.2.0",
        "qt6\lib",
        "x86_64-w64-mingw32\lib"
    )
    foreach ($relative in $mappedDirectories) {
        [void] (New-Item -ItemType Directory -Path (Join-Path $mingw $relative) -Force)
    }

    $gccDir = Join-Path $mingw "lib\gcc\x86_64-w64-mingw32\15.2.0"
    $allDirectoryTokens = @(
        "-L/usr//lib",
        "-L/usr//usr/lib",
        "-L/usr/lib",
        "-L/usr/lib/../lib",
        "-L/usr/lib/gcc/x86_64-w64-mingw32/15.2.0",
        "-L/usr/lib/GraphicsMagick-1.3.46/modules-Q16/coders",
        "-L/usr/lib/GraphicsMagick-1.3.46/modules-Q16/filters",
        "-L/usr/lib/octave/11.3.0",
        "-L/usr/lib/pstoedit",
        "-L/usr/libexec/gcc/x86_64-w64-mingw32/15.2.0",
        "-L/usr/mingw/lib",
        "-L/usr/qt6/lib",
        "-L/usr/x86_64-w64-mingw32/lib"
    )
    $dependencies = ($allDirectoryTokens + @(
        "/usr/lib/gcc/x86_64-w64-mingw32/15.2.0/libssp.la",
        $ExtraDependencyToken
    ) | Where-Object { $_ }) -join " "

    Write-AsciiFile -Path (Join-Path $gccDir "libstdc++.la") -Text @"
# synthetic libtool archive
dependency_libs=' $dependencies'
libdir='/usr/lib/gcc/x86_64-w64-mingw32/15.2.0'
"@

    if (-not $NoCandidate) {
        Write-AsciiFile -Path (Join-Path $gccDir "libssp.la") -Text @"
# synthetic dependency
dependency_libs=' -L/usr/x86_64-w64-mingw32/lib -L/usr/mingw/lib'
libdir='/usr/lib/gcc/x86_64-w64-mingw32/15.2.0'
"@
    }

    if ($AmbiguousCandidate) {
        Write-AsciiFile -Path (Join-Path $mingw "lib\alternate\libssp.la") -Text @"
# ambiguous synthetic dependency
dependency_libs=''
libdir='/usr/lib'
"@
    }

    return $root
}

function Invoke-Normalizer {
    param(
        [Parameter(Mandatory = $true)][string] $Root,
        [Parameter(Mandatory = $true)] $Manifest,
        [ValidateSet("Plan", "Apply")][string] $Mode = "Apply",
        [string] $ParentRoot = $testRoot,
        [ValidateSet(
            "None",
            "CompilerFailureAfterTempCreation",
            "RootIdentityMismatchBeforeSecondReplacement",
            "BeforeSecondReplacement",
            "RemoveEmittedTargetAfterReplacement")]
        [string] $TestFailurePoint = "None",
        [string] $CompilerTempOverride = "",
        [ValidateSet("OrdinalLfV1", "PowerShellTsvV1")]
        [string] $ManifestFormat = "OrdinalLfV1",
        $Selection,
        $SeedLibraries
    )

    $stdout = Join-Path $testRoot ("stdout-" + [guid]::NewGuid().ToString("N") + ".log")
    $stderr = Join-Path $testRoot ("stderr-" + [guid]::NewGuid().ToString("N") + ".log")
    function Quote-ProcessArgument {
        param([Parameter(Mandatory = $true)][string] $Value)

        return '"' + $Value.Replace('"', '\"') + '"'
    }

    if ($null -eq $Selection) {
        if ($Root -match '^[A-Za-z]:\\' -and
                (Test-Path -LiteralPath $Root -PathType Container)) {
            $defaultRoot =
                "mingw64/lib/gcc/x86_64-w64-mingw32/15.2.0/libstdc++.la"
            $defaultDependency =
                "mingw64/lib/gcc/x86_64-w64-mingw32/15.2.0/libssp.la"
            $dependencies = if (Test-Path -LiteralPath (
                    Join-Path $Root $defaultDependency.Replace("/", "\")) `
                    -PathType Leaf) {
                @($defaultDependency)
            }
            else {
                @()
            }
            $Selection = New-LaSelectionContract -ParentRoot $ParentRoot `
                -Roots @($defaultRoot) -Dependencies $dependencies
        }
        else {
            $Selection = [pscustomobject] @{
                Path = Join-Path $testRoot "missing-selection.tsv"
                Sha256 = ("0" * 64)
                RootCount = 1
            }
        }
    }
    if ($null -eq $SeedLibraries) {
        if ($Selection.PSObject.Properties.Name -contains "Lines") {
            $rootTokens = @($Selection.Lines | Where-Object {
                $_.StartsWith("root`t", [StringComparison]::Ordinal)
            } | ForEach-Object {
                $name = [IO.Path]::GetFileName($_.Substring(5))
                if ($name.StartsWith(
                        "lib", [StringComparison]::OrdinalIgnoreCase)) {
                    $name.Substring(3, $name.Length - 6)
                }
                else {
                    $name.Substring(0, $name.Length - 3)
                }
            })
            $SeedLibraries = New-SeedLibraryContract -ParentRoot $ParentRoot `
                -Tokens $rootTokens
        }
        else {
            $SeedLibraries = [pscustomobject] @{
                Path = Join-Path $testRoot "missing-seed-libraries.txt"
                Sha256 = ("0" * 64)
                Count = 0
            }
        }
    }

    $arguments = @(
        "-NoProfile",
        "-ExecutionPolicy", "Bypass",
        "-File", (Quote-ProcessArgument -Value $normalizer),
        "-ToolchainRoot", (Quote-ProcessArgument -Value $Root),
        "-DisposableParentRoot", (Quote-ProcessArgument -Value $ParentRoot),
        "-ExpectedFileCount", [string] $Manifest.FileCount,
        "-ExpectedTotalBytes", [string] $Manifest.TotalBytes,
        "-ExpectedManifestSha256", [string] $Manifest.Sha256,
        "-Mode", $Mode,
        "-ManifestFormat", $ManifestFormat,
        "-LaSelectionManifestPath",
        (Quote-ProcessArgument -Value $Selection.Path),
        "-ExpectedLaSelectionManifestSha256", [string] $Selection.Sha256,
        "-ExpectedLaRootCount", [string] $Selection.RootCount,
        "-SeedLibraryManifestPath",
        (Quote-ProcessArgument -Value $SeedLibraries.Path),
        "-ExpectedSeedLibraryManifestSha256", [string] $SeedLibraries.Sha256,
        "-ExpectedSeedLibraryCount", [string] $SeedLibraries.Count
    )
    if ($TestFailurePoint -ne "None") {
        $arguments += @("-TestFailurePoint", $TestFailurePoint)
    }
    if ($ManifestFormat -eq "PowerShellTsvV1") {
        $arguments += @(
            "-ManifestOrderReferencePath",
            (Quote-ProcessArgument -Value $Manifest.ManifestOrderReferencePath),
            "-ExpectedManifestOrderReferenceSha256",
            [string] $Manifest.ExpectedManifestOrderReferenceSha256
        )
    }
    $savedCompilerEnvironment = @{}
    try {
        if ($CompilerTempOverride.Length -ne 0) {
            foreach ($name in @("TEMP", "TMP", "TMPDIR")) {
                $savedCompilerEnvironment[$name] = [pscustomobject] @{
                    WasPresent = Test-Path -LiteralPath "Env:$name"
                    Value = [Environment]::GetEnvironmentVariable(
                        $name, "Process")
                }
                [Environment]::SetEnvironmentVariable(
                    $name, $CompilerTempOverride, "Process")
            }
        }
        $process = Start-Process -FilePath "powershell.exe" -ArgumentList $arguments `
            -RedirectStandardOutput $stdout -RedirectStandardError $stderr `
            -WindowStyle Hidden -Wait -PassThru
    }
    finally {
        foreach ($name in $savedCompilerEnvironment.Keys) {
            $saved = $savedCompilerEnvironment[$name]
            if ($saved.WasPresent) {
                [Environment]::SetEnvironmentVariable(
                    $name, $saved.Value, "Process")
            }
            else {
                [Environment]::SetEnvironmentVariable(
                    $name, $null, "Process")
            }
        }
    }
    return [pscustomobject] @{
        ExitCode = $process.ExitCode
        Stdout = [IO.File]::ReadAllText($stdout)
        Stderr = [IO.File]::ReadAllText($stderr)
    }
}

function Assert-True {
    param(
        [Parameter(Mandatory = $true)][bool] $Condition,
        [Parameter(Mandatory = $true)][string] $Message
    )
    if (-not $Condition) {
        throw $Message
    }
}

function Assert-FailureWithoutWrites {
    param(
        [Parameter(Mandatory = $true)][string] $Root,
        [Parameter(Mandatory = $true)] $Manifest,
        [Parameter(Mandatory = $true)][string] $ExpectedMessage,
        [ValidateSet(
            "None",
            "CompilerFailureAfterTempCreation",
            "RootIdentityMismatchBeforeSecondReplacement",
            "BeforeSecondReplacement",
            "RemoveEmittedTargetAfterReplacement")]
        [string] $TestFailurePoint = "None",
        $Selection,
        $SeedLibraries
    )

    $before = Get-TreeManifest -Root $Root
    $result = Invoke-Normalizer -Root $Root -Manifest $Manifest -Mode Apply `
        -TestFailurePoint $TestFailurePoint -Selection $Selection `
        -SeedLibraries $SeedLibraries
    $after = Get-TreeManifest -Root $Root
    Assert-True ($result.ExitCode -ne 0) "Expected normalization failure."
    Assert-True (($result.Stdout + $result.Stderr) -match $ExpectedMessage) `
        "Expected failure message '$ExpectedMessage', got: $($result.Stdout)$($result.Stderr)"
    Assert-True ($before.Sha256 -eq $after.Sha256) "Failure modified fixture bytes."
    Assert-True ($before.FileCount -eq $after.FileCount) "Failure changed fixture inventory."
    Assert-True ($before.TotalBytes -eq $after.TotalBytes) "Failure changed fixture byte count."
    $transactions = @(Get-ChildItem -LiteralPath $testRoot -Force -Directory |
        Where-Object { $_.Name -like ".todo51-la-normalize-*" })
    Assert-True ($transactions.Count -eq 0) "Failure retained a transaction directory."
}

function Test-SuccessAndAnomalies {
    $root = New-Fixture -Name "success"
    $manifest = Get-TreeManifest -Root $root
    $result = Invoke-Normalizer -Root $root -Manifest $manifest -Mode Apply
    Assert-True ($result.ExitCode -eq 0) "Success fixture failed: $($result.Stderr)"
    $allText = (Get-ChildItem -LiteralPath $root -Recurse -File -Filter "*.la" |
        ForEach-Object { [IO.File]::ReadAllText($_.FullName) }) -join "`n"
    Assert-True ($allText -notmatch "/usr") "Success fixture retained stale /usr text."
    Assert-True ($allText -match "/mingw64/libssp\.la|/mingw64/lib/gcc/.*/libssp\.la") `
        "Unique libssp candidate was not used."
    $json = $result.Stdout | ConvertFrom-Json
    Assert-True ($json.ChangedFileCount -eq 2) "Unexpected changed-file count."

    $normalizedManifest = Get-TreeManifest -Root $root
    $secondResult = Invoke-Normalizer -Root $root `
        -Manifest $normalizedManifest -Mode Apply
    Assert-True ($secondResult.ExitCode -eq 0) `
        "Idempotence fixture failed: $($secondResult.Stderr)"
    $secondJson = $secondResult.Stdout | ConvertFrom-Json
    Assert-True ($secondJson.ChangedFileCount -eq 0) `
        "Idempotence run unexpectedly reported changes."
    $afterSecond = Get-TreeManifest -Root $root
    Assert-True ($afterSecond.Sha256 -eq $normalizedManifest.Sha256) `
        "Idempotence run changed normalized fixture bytes."
}

function Test-AmbiguousCandidate {
    $root = New-Fixture -Name "ambiguous" -AmbiguousCandidate
    $manifest = Get-TreeManifest -Root $root
    Assert-FailureWithoutWrites -Root $root -Manifest $manifest -ExpectedMessage "ambiguous"
}

function Test-MissingCandidate {
    $root = New-Fixture -Name "missing" -NoCandidate
    $manifest = Get-TreeManifest -Root $root
    $selection = New-LaSelectionContract -ParentRoot $testRoot `
        -Roots @(
            "mingw64/lib/gcc/x86_64-w64-mingw32/15.2.0/libstdc++.la")
    Assert-FailureWithoutWrites -Root $root -Manifest $manifest `
        -ExpectedMessage "missing" -Selection $selection
}

function Test-UnknownAbsolutePath {
    $root = New-Fixture -Name "unknown" -ExtraDependencyToken "-L/usr/not-in-policy"
    $manifest = Get-TreeManifest -Root $root
    Assert-FailureWithoutWrites -Root $root -Manifest $manifest -ExpectedMessage "unsupported"
}

function Test-UnsupportedAssignment {
    $root = New-Fixture -Name "unsupported-assignment"
    $path = Join-Path $root "mingw64\lib\unsupported.la"
    Write-AsciiFile -Path $path -Text "dependency_libs=`"/usr/lib/libssp.la`"`n"
    $manifest = Get-TreeManifest -Root $root
    $selection = New-LaSelectionContract -ParentRoot $testRoot `
        -Roots @("mingw64/lib/unsupported.la")
    Assert-FailureWithoutWrites -Root $root -Manifest $manifest `
        -ExpectedMessage "assignment" -Selection $selection
}

function Test-UnsupportedQuoteForm {
    $root = New-Fixture -Name "unsupported-quote" `
        -ExtraDependencyToken "'/usr/lib/libssp.la'"
    $manifest = Get-TreeManifest -Root $root
    Assert-FailureWithoutWrites -Root $root -Manifest $manifest -ExpectedMessage "quote"
}

function Test-NonAsciiRejection {
    $root = New-Fixture -Name "non-ascii"
    $path = Join-Path $root "mingw64\lib\non-ascii.la"
    [IO.File]::WriteAllBytes($path, [byte[]] @(
        0x23, 0x20, 0xff, 0x0a,
        0x6c, 0x69, 0x62, 0x64, 0x69, 0x72, 0x3d, 0x27,
        0x2f, 0x75, 0x73, 0x72, 0x2f, 0x6c, 0x69, 0x62, 0x27, 0x0a
    ))
    $manifest = Get-TreeManifest -Root $root
    $selection = New-LaSelectionContract -ParentRoot $testRoot `
        -Roots @("mingw64/lib/non-ascii.la")
    Assert-FailureWithoutWrites -Root $root -Manifest $manifest `
        -ExpectedMessage "non-ASCII" -Selection $selection
}

function Test-SelectionIgnoresUnrelatedScratchMetadata {
    $root = New-Fixture -Name "selection-ignores-scratch"
    $unselected = Join-Path $root "mingw64\lib\libbfd.la"
    Write-AsciiFile -Path $unselected -Text @"
dependency_libs=' -L/scratch/build/gdb/.build/zlib -lz -liberty'
libdir='/scratch/build/gdb/install/lib'
"@
    $before = (Get-FileHash -LiteralPath $unselected -Algorithm SHA256).Hash
    $manifest = Get-TreeManifest -Root $root
    $result = Invoke-Normalizer -Root $root -Manifest $manifest -Mode Apply
    Assert-True ($result.ExitCode -eq 0) `
        "Unselected scratch metadata was not ignored: $($result.Stderr)"
    $after = (Get-FileHash -LiteralPath $unselected -Algorithm SHA256).Hash
    Assert-True ($after -eq $before) `
        "Unselected scratch metadata changed."
    $json = $result.Stdout | ConvertFrom-Json
    Assert-True ($json.SelectionFileCount -eq 2) `
        "Selection did not report its exact two-file fixture closure."
    Assert-True ($json.UnselectedLaFileCount -eq 1) `
        "Selection did not report the unrelated archive."
}

function Test-SelectedScratchAndClosureEscapeFail {
    $scratchRoot = New-Fixture -Name "selected-scratch"
    $scratchPath = Join-Path $scratchRoot "mingw64\lib\scratch.la"
    Write-AsciiFile -Path $scratchPath -Text @"
dependency_libs=' -L/scratch/build/gdb/.build/zlib -lz'
libdir='/usr/lib'
"@
    $scratchManifest = Get-TreeManifest -Root $scratchRoot
    $scratchSelection = New-LaSelectionContract -ParentRoot $testRoot `
        -Roots @("mingw64/lib/scratch.la")
    Assert-FailureWithoutWrites -Root $scratchRoot `
        -Manifest $scratchManifest -Selection $scratchSelection `
        -ExpectedMessage "unsupported absolute directory|scratch"

    $escapeRoot = New-Fixture -Name "selected-closure-escape"
    $escapePath = Join-Path $escapeRoot "mingw64\lib\escape.la"
    Write-AsciiFile -Path $escapePath -Text @"
dependency_libs=' ../../outside.la'
libdir='/usr/lib'
"@
    $escapeManifest = Get-TreeManifest -Root $escapeRoot
    $escapeSelection = New-LaSelectionContract -ParentRoot $testRoot `
        -Roots @("mingw64/lib/escape.la")
    Assert-FailureWithoutWrites -Root $escapeRoot `
        -Manifest $escapeManifest -Selection $escapeSelection `
        -ExpectedMessage "closure|relative.*la|escape"
}

function Test-SelectionEntryRejections {
    $root = New-Fixture -Name "selection-entry-rejections"
    $manifest = Get-TreeManifest -Root $root
    $rootPath =
        "mingw64/lib/gcc/x86_64-w64-mingw32/15.2.0/libstdc++.la"
    $dependencyPath =
        "mingw64/lib/gcc/x86_64-w64-mingw32/15.2.0/libssp.la"

    $cases = @(
        [pscustomobject] @{
            Name = "missing"
            Lines = @("root`t$rootPath")
            Message = "selection.*missing|closure.*selection"
        },
        [pscustomobject] @{
            Name = "extra"
            Lines = @(
                "root`t$rootPath",
                "dependency`t$dependencyPath",
                "dependency`tmingw64/lib/unrelated.la")
            Message = "extra|unreachable"
            CreateUnrelated = $true
        },
        [pscustomobject] @{
            Name = "duplicate"
            Lines = @(
                "root`t$rootPath",
                "dependency`t$dependencyPath",
                "dependency`t$dependencyPath")
            Message = "duplicate"
        },
        [pscustomobject] @{
            Name = "unsafe"
            Lines = @(
                "root`t$rootPath",
                "dependency`t../escape.la")
            Message = "unsafe"
        }
    )
    foreach ($case in $cases) {
        if ($case.PSObject.Properties.Name -contains "CreateUnrelated" -and
                $case.CreateUnrelated) {
            Write-AsciiFile -Path (
                Join-Path $root "mingw64\lib\unrelated.la") -Text @"
dependency_libs=''
libdir='/usr/lib'
"@
            $manifest = Get-TreeManifest -Root $root
        }
        $selection = New-LaSelectionContract -ParentRoot $testRoot `
            -Roots @($rootPath) -RawLines $case.Lines
        Assert-FailureWithoutWrites -Root $root -Manifest $manifest `
            -Selection $selection -ExpectedMessage $case.Message
    }
}

function Test-RecursiveLibraryClosure {
    $root = New-Fixture -Name "recursive-library-closure"
    $rootPath = Join-Path $root "mingw64\lib\closure-root.la"
    $dependencyPath = Join-Path $root "mingw64\lib\libsynthetic.la"
    Write-AsciiFile -Path $rootPath -Text @"
dependency_libs=' -L/usr/lib -lsynthetic'
libdir='/usr/lib'
"@
    Write-AsciiFile -Path $dependencyPath -Text @"
dependency_libs=''
libdir='/usr/lib'
"@
    $manifest = Get-TreeManifest -Root $root
    $incomplete = New-LaSelectionContract -ParentRoot $testRoot `
        -Roots @("mingw64/lib/closure-root.la")
    Assert-FailureWithoutWrites -Root $root -Manifest $manifest `
        -Selection $incomplete -ExpectedMessage "selection.*missing|closure"

    $complete = New-LaSelectionContract -ParentRoot $testRoot `
        -Roots @("mingw64/lib/closure-root.la") `
        -Dependencies @("mingw64/lib/libsynthetic.la")
    $result = Invoke-Normalizer -Root $root -Manifest $manifest -Mode Plan `
        -Selection $complete
    Assert-True ($result.ExitCode -eq 0) `
        "Complete recursive -l closure failed: $($result.Stderr)"
    $json = $result.Stdout | ConvertFrom-Json
    Assert-True ($json.ClosureEdgeCount -eq 1) `
        "Recursive -l closure did not report its exact edge."
    Assert-True ($json.UniqueLibraryTokenCount -eq 2) `
        "Seed and recursive -l union did not report its exact two tokens."
}

function Test-ClosureCyclesAndUniqueResolution {
    $cycleRoot = New-Fixture -Name "closure-cycle"
    Write-AsciiFile -Path (Join-Path $cycleRoot "mingw64\lib\libcycle-a.la") `
        -Text @"
dependency_libs=' -L/usr/lib -lcycle-b'
libdir='/usr/lib'
"@
    Write-AsciiFile -Path (Join-Path $cycleRoot "mingw64\lib\libcycle-b.la") `
        -Text @"
dependency_libs=' -L/usr/lib -lcycle-a'
libdir='/usr/lib'
"@
    $cycleManifest = Get-TreeManifest -Root $cycleRoot
    $cycleSelection = New-LaSelectionContract -ParentRoot $testRoot `
        -Roots @("mingw64/lib/libcycle-a.la") `
        -Dependencies @("mingw64/lib/libcycle-b.la")
    $cycle = Invoke-Normalizer -Root $cycleRoot -Manifest $cycleManifest `
        -Mode Plan -Selection $cycleSelection
    Assert-True ($cycle.ExitCode -eq 0) `
        "Recursive closure cycle did not terminate: $($cycle.Stderr)"
    $cycleJson = $cycle.Stdout | ConvertFrom-Json
    Assert-True ($cycleJson.ClosureEdgeCount -eq 2) `
        "Closure cycle did not report its two exact edges."

    $ambiguousRoot = New-Fixture -Name "closure-ambiguous-library"
    Write-AsciiFile -Path (
        Join-Path $ambiguousRoot "mingw64\lib\ambiguous-root.la") -Text @"
dependency_libs=' -L/usr/lib -lduplicate'
libdir='/usr/lib'
"@
    Write-AsciiFile -Path (
        Join-Path $ambiguousRoot "mingw64\lib\libduplicate.la") -Text @"
dependency_libs=''
libdir='/usr/lib'
"@
    Write-AsciiFile -Path (
        Join-Path $ambiguousRoot "mingw64\qt6\lib\libduplicate.la") -Text @"
dependency_libs=''
libdir='/usr/qt6/lib'
"@
    $ambiguousManifest = Get-TreeManifest -Root $ambiguousRoot
    $ambiguousSelection = New-LaSelectionContract -ParentRoot $testRoot `
        -Roots @("mingw64/lib/ambiguous-root.la") `
        -Dependencies @(
            "mingw64/lib/libduplicate.la",
            "mingw64/qt6/lib/libduplicate.la")
    Assert-FailureWithoutWrites -Root $ambiguousRoot `
        -Manifest $ambiguousManifest -Selection $ambiguousSelection `
        -ExpectedMessage "ambiguous selected"
}

function Test-SeedLibraryContractRejections {
    $root = New-Fixture -Name "seed-contract-rejections"
    $manifest = Get-TreeManifest -Root $root
    $stdcpp =
        "mingw64/lib/gcc/x86_64-w64-mingw32/15.2.0/libstdc++.la"
    $ssp = "mingw64/lib/gcc/x86_64-w64-mingw32/15.2.0/libssp.la"
    $selection = New-LaSelectionContract -ParentRoot $testRoot `
        -Roots @($stdcpp) -Dependencies @($ssp)

    $missing = New-SeedLibraryContract -ParentRoot $testRoot -Tokens @()
    Assert-FailureWithoutWrites -Root $root -Manifest $manifest `
        -Selection $selection -SeedLibraries $missing `
        -ExpectedMessage "seed.*root|root.*seed"

    $extra = New-SeedLibraryContract -ParentRoot $testRoot `
        -Tokens @("stdc++", "ssp")
    Assert-FailureWithoutWrites -Root $root -Manifest $manifest `
        -Selection $selection -SeedLibraries $extra `
        -ExpectedMessage "seed.*root|root.*seed"

    $changed = New-SeedLibraryContract -ParentRoot $testRoot `
        -Tokens @("stdcxx")
    Assert-FailureWithoutWrites -Root $root -Manifest $manifest `
        -Selection $selection -SeedLibraries $changed `
        -ExpectedMessage "missing library candidate"

    $hashChanged = New-SeedLibraryContract -ParentRoot $testRoot `
        -Tokens @("stdc++")
    [IO.File]::WriteAllBytes(
        $hashChanged.Path, $utf8NoBom.GetBytes("ssp`r`n"))
    Assert-FailureWithoutWrites -Root $root -Manifest $manifest `
        -Selection $selection -SeedLibraries $hashChanged `
        -ExpectedMessage "seed library manifest hash mismatch"

    $swappedSelection = New-LaSelectionContract -ParentRoot $testRoot `
        -Roots @($ssp) -Dependencies @($stdcpp)
    $rootMismatch = New-SeedLibraryContract -ParentRoot $testRoot `
        -Tokens @("stdc++")
    Assert-FailureWithoutWrites -Root $root -Manifest $manifest `
        -Selection $swappedSelection -SeedLibraries $rootMismatch `
        -ExpectedMessage "seed.*root|root.*seed"
}

function Test-ZeroByteFiles {
    $root = New-Fixture -Name "zero-byte-files"
    [IO.File]::WriteAllBytes(
        (Join-Path $root "mingw64\lib\empty.la"), [byte[]] @())
    [IO.File]::WriteAllBytes(
        (Join-Path $root "empty.dat"), [byte[]] @())
    $manifest = Get-TreeManifest -Root $root
    $result = Invoke-Normalizer -Root $root -Manifest $manifest -Mode Plan
    Assert-True ($result.ExitCode -eq 0) `
        "Zero-byte file fixture failed: $($result.Stderr)"
}

function Test-EstablishedManifestFormat {
    $root = New-Fixture -Name "established-manifest-format"
    Write-AsciiFile -Path (Join-Path $root "clang64.ico") -Text "culture-first"
    Write-AsciiFile -Path (Join-Path $root "HG-ID") -Text "ordinal-first"

    $reference = New-ManifestOrderReference -Root $root `
        -Path (Join-Path $testRoot "established-order.tsv")
    $established = Get-TreeManifest -Root $root `
        -ManifestFormat PowerShellTsvV1 `
        -ManifestOrderReferencePath $reference.Path
    $ordinal = Get-TreeManifest -Root $root -ManifestFormat OrdinalLfV1

    $canonical = [IO.Path]::GetFullPath($root).TrimEnd("\")
    $independentFiles = @(Get-ChildItem -LiteralPath $canonical -Recurse -Force -File |
        Sort-Object {
            $_.FullName.Substring($canonical.Length + 1).Replace("\", "/")
        })
    $independentLines = @($independentFiles | ForEach-Object {
        $relative = $_.FullName.Substring($canonical.Length + 1).Replace("\", "/")
        "{0}`t{1}`t{2}" -f
            $relative, $_.Length,
            (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
    })
    $independentBytes = $utf8NoBom.GetBytes(
        ($independentLines -join "`r`n") + "`r`n")
    $independentHash = Get-Sha256Bytes -Bytes $independentBytes

    Assert-True ($established.Sha256 -eq $independentHash) `
        "PowerShellTsvV1 hash did not match independent serialization."
    Assert-True ($established.ManifestByteCount -eq $independentBytes.Length) `
        "PowerShellTsvV1 serialized byte count differed."
    Assert-True $established.EndsWithCrlf `
        "PowerShellTsvV1 did not retain its trailing CRLF."
    Assert-True ($established.FirstPath -eq "clang64.ico") `
        "PowerShellTsvV1 did not use the established culture ordering."
    Assert-True ($ordinal.FirstPath -eq "HG-ID") `
        "OrdinalLfV1 did not retain ordinal ordering."
    Assert-True (-not $ordinal.EndsWithCrlf) `
        "OrdinalLfV1 unexpectedly gained a trailing CRLF."
    Assert-True ($ordinal.Sha256 -ne $established.Sha256) `
        "The distinguishing fixture produced identical manifest hashes."

    $result = Invoke-Normalizer -Root $root -Manifest $established -Mode Plan `
        -ManifestFormat PowerShellTsvV1
    Assert-True ($result.ExitCode -eq 0) `
        "PowerShellTsvV1 normalizer plan failed: $($result.Stderr)"
    $json = $result.Stdout | ConvertFrom-Json
    Assert-True ($json.ManifestFormat -eq "PowerShellTsvV1") `
        "Normalizer result did not report the selected manifest format."
}

function Test-EstablishedManifestReferenceRejections {
    $root = New-Fixture -Name "reference-rejections"
    Write-AsciiFile -Path (Join-Path $root "clang64.ico") -Text "culture-first"
    Write-AsciiFile -Path (Join-Path $root "HG-ID") -Text "ordinal-first"
    $valid = New-ManifestOrderReference -Root $root `
        -Path (Join-Path $testRoot "reference-valid.tsv")
    $validManifest = Get-TreeManifest -Root $root `
        -ManifestFormat PowerShellTsvV1 `
        -ManifestOrderReferencePath $valid.Path
    $rootBefore = Get-TreeManifest -Root $root

    $cases = New-Object Collections.Generic.List[object]
    $cases.Add([pscustomobject] @{
        Name = "missing"
        Path = (Join-Path $testRoot "reference-missing.tsv")
        ExpectedSha = ("0" * 64)
        Message = "reference.*missing"
    })

    $corruptPath = Join-Path $testRoot "reference-corrupt.tsv"
    [IO.File]::WriteAllBytes(
        $corruptPath, [IO.File]::ReadAllBytes($valid.Path))
    [IO.File]::WriteAllText(
        $corruptPath,
        [IO.File]::ReadAllText($corruptPath).Replace(
            "clang64.ico", "clang64.icx"),
        $utf8NoBom)
    $cases.Add([pscustomobject] @{
        Name = "corrupt"
        Path = $corruptPath
        ExpectedSha = $valid.Sha256
        Message = "reference hash"
    })

    $validLines = [IO.File]::ReadAllLines($valid.Path)
    $variants = @(
        [pscustomobject] @{
            Name = "duplicate"
            Lines = [string[]] @($validLines + $validLines[0])
            Message = "duplicate"
        },
        [pscustomobject] @{
            Name = "unsafe"
            Lines = [string[]] @(
                ("../escape`t" + (($validLines[0].Split("`t"))[1..2] -join "`t")),
                $validLines[1..($validLines.Length - 1)])
            Message = "unsafe"
        },
        [pscustomobject] @{
            Name = "path-set"
            Lines = [string[]] $validLines[1..($validLines.Length - 1)]
            Message = "path set|path count"
        }
    )
    foreach ($variant in $variants) {
        $path = Join-Path $testRoot ("reference-" + $variant.Name + ".tsv")
        [IO.File]::WriteAllBytes(
            $path,
            $utf8NoBom.GetBytes(($variant.Lines -join "`r`n") + "`r`n"))
        $cases.Add([pscustomobject] @{
            Name = $variant.Name
            Path = $path
            ExpectedSha = (Get-FileHash -LiteralPath $path `
                -Algorithm SHA256).Hash
            Message = $variant.Message
        })
    }

    foreach ($case in $cases) {
        $manifest = $validManifest.PSObject.Copy()
        $manifest.ManifestOrderReferencePath = $case.Path
        $manifest.ExpectedManifestOrderReferenceSha256 = $case.ExpectedSha
        $result = Invoke-Normalizer -Root $root -Manifest $manifest -Mode Apply `
            -ManifestFormat PowerShellTsvV1
        Assert-True ($result.ExitCode -ne 0) `
            "Invalid reference '$($case.Name)' unexpectedly succeeded."
        Assert-True (($result.Stdout + $result.Stderr) -match $case.Message) `
            "Invalid reference '$($case.Name)' did not identify its cause."
        $rootAfter = Get-TreeManifest -Root $root
        Assert-True ($rootAfter.Sha256 -eq $rootBefore.Sha256) `
            "Invalid reference '$($case.Name)' changed root bytes."
    }
}

function Test-ReparseRejection {
    $root = New-Fixture -Name "reparse"
    $target = Join-Path $testRoot "reparse-target"
    [void] (New-Item -ItemType Directory -Path $target)
    [void] (New-Item -ItemType Junction -Path (Join-Path $root "junction") -Target $target)
    $dummy = [pscustomobject] @{ FileCount = 0; TotalBytes = 0; Sha256 = ("0" * 64) }
    $result = Invoke-Normalizer -Root $root -Manifest $dummy -Mode Apply
    Assert-True ($result.ExitCode -ne 0) "Reparse fixture unexpectedly succeeded."
    Assert-True (($result.Stdout + $result.Stderr) -match "reparse") `
        "Reparse rejection did not identify the cause."
}

function Test-PermanentRootRejection {
    $dummy = [pscustomobject] @{ FileCount = 0; TotalBytes = 0; Sha256 = ("0" * 64) }
    $result = Invoke-Normalizer -Root "C:\Tools\GNU Octave\11.3.0" `
        -Manifest $dummy -Mode Apply
    Assert-True ($result.ExitCode -ne 0) "Permanent root unexpectedly accepted."
    Assert-True (($result.Stdout + $result.Stderr) -match "permanent") `
        "Permanent-root rejection did not identify the cause."
}

function Test-NamespaceRejection {
    $dummy = [pscustomobject] @{ FileCount = 0; TotalBytes = 0; Sha256 = ("0" * 64) }
    $cases = @(
        [pscustomobject] @{
            Root = "\\?\C:\Tools\GNU Octave\11.3.0"
            Parent = "\\?\C:\Tools\GNU Octave"
        },
        [pscustomobject] @{
            Root = "\\.\C:\Tools\GNU Octave\11.3.0"
            Parent = "\\.\C:\Tools\GNU Octave"
        },
        [pscustomobject] @{
            Root = "\\?\Volume{00000000-0000-0000-0000-000000000000}\Octave"
            Parent = "\\?\Volume{00000000-0000-0000-0000-000000000000}"
        },
        [pscustomobject] @{
            Root = "\\localhost\C$\Tools\GNU Octave\11.3.0"
            Parent = "\\localhost\C$\Tools\GNU Octave"
        }
    )
    foreach ($case in $cases) {
        $result = Invoke-Normalizer -Root $case.Root -ParentRoot $case.Parent `
            -Manifest $dummy -Mode Apply
        Assert-True ($result.ExitCode -ne 0) `
            "Namespaced path unexpectedly succeeded: $($case.Root)"
        Assert-True (($result.Stdout + $result.Stderr) -match "namespace") `
            "Namespaced path was not rejected lexically: $($case.Root)"
    }
}

function Test-NegativePathSkipsHelperCompilation {
    $poison = Join-Path "C:\tmp" `
        ("todo51-external-temp-poison-" + [guid]::NewGuid().ToString("N"))
    try {
        Write-AsciiFile -Path $poison -Text "compiler temp must not be consulted"
        $before = (Get-FileHash -LiteralPath $poison -Algorithm SHA256).Hash
        $dummy = [pscustomobject] @{
            FileCount = 0
            TotalBytes = 0
            Sha256 = ("0" * 64)
        }
        $result = Invoke-Normalizer `
            -Root "\\?\C:\Tools\GNU Octave\11.3.0" `
            -ParentRoot "\\?\C:\Tools\GNU Octave" `
            -Manifest $dummy -Mode Apply -CompilerTempOverride $poison
        Assert-True ($result.ExitCode -ne 0) `
            "Namespaced path unexpectedly succeeded with poisoned TEMP/TMP."
        Assert-True (($result.Stdout + $result.Stderr) -match "namespace") `
            "Helper compilation ran before negative path rejection."
        $after = (Get-FileHash -LiteralPath $poison -Algorithm SHA256).Hash
        Assert-True ($before -eq $after) "Negative path handling modified poison TEMP/TMP."
    }
    finally {
        if (Test-Path -LiteralPath $poison) {
            Remove-Item -LiteralPath $poison -Force
        }
    }
}

function Test-CompilerTempConfinementAndCleanup {
    $poisonRoot = Join-Path "C:\tmp" `
        ("todo51-external-temp-poison-" + [guid]::NewGuid().ToString("N"))
    try {
        [void] (New-Item -ItemType Directory -Path $poisonRoot)
        Write-AsciiFile -Path (Join-Path $poisonRoot "sentinel.txt") `
            -Text "external compiler temp poison"
        $poisonBefore = Get-TreeManifest -Root $poisonRoot

        $successRoot = New-Fixture -Name "compiler-temp-success"
        $successManifest = Get-TreeManifest -Root $successRoot
        $success = Invoke-Normalizer -Root $successRoot `
            -Manifest $successManifest -Mode Plan `
            -CompilerTempOverride $poisonRoot
        Assert-True ($success.ExitCode -eq 0) `
            "Confined helper compilation failed: $($success.Stderr)"
        $successJson = $success.Stdout | ConvertFrom-Json
        $expectedPrefix = [IO.Path]::GetFullPath($testRoot).TrimEnd("\") + "\"
        Assert-True ($successJson.CompilerTempRoot.StartsWith(
                $expectedPrefix, [StringComparison]::OrdinalIgnoreCase)) `
            "Compiler temp was not located under the synthetic disposable parent."
        Assert-True ((Split-Path -Leaf $successJson.CompilerTempRoot) -match
                '^\.todo51-add-type-[0-9a-f]{32}$') `
            "Compiler temp did not use the exact unique helper name."
        Assert-True ([bool] $successJson.CompilerEnvironmentRestored) `
            "Normalizer did not confirm compiler environment restoration."

        $customSavedEnvironment = @{}
        try {
            foreach ($name in @("TEMP", "TMP", "TMPDIR")) {
                $customSavedEnvironment[$name] = [pscustomobject] @{
                    WasPresent = Test-Path -LiteralPath "Env:$name"
                    Value = [Environment]::GetEnvironmentVariable(
                        $name, "Process")
                }
            }
            [Environment]::SetEnvironmentVariable(
                "TEMP", $poisonRoot, "Process")
            [Environment]::SetEnvironmentVariable("TMP", "", "Process")
            [Environment]::SetEnvironmentVariable("TMPDIR", $null, "Process")
            $mixedState = Invoke-Normalizer -Root $successRoot `
                -Manifest $successManifest -Mode Plan
            Assert-True ($mixedState.ExitCode -eq 0) `
                "Mixed compiler environment state failed: $($mixedState.Stderr)"
            $mixedJson = $mixedState.Stdout | ConvertFrom-Json
            Assert-True ([bool] $mixedJson.CompilerEnvironmentRestored) `
                "Unset and empty compiler environment states were not restored."
        }
        finally {
            foreach ($name in $customSavedEnvironment.Keys) {
                $saved = $customSavedEnvironment[$name]
                if ($saved.WasPresent) {
                    [Environment]::SetEnvironmentVariable(
                        $name, $saved.Value, "Process")
                }
                else {
                    [Environment]::SetEnvironmentVariable(
                        $name, $null, "Process")
                }
            }
        }

        $failureRoot = New-Fixture -Name "compiler-temp-failure"
        $failureManifest = Get-TreeManifest -Root $failureRoot
        $failure = Invoke-Normalizer -Root $failureRoot `
            -Manifest $failureManifest -Mode Apply `
            -CompilerTempOverride $poisonRoot `
            -TestFailurePoint CompilerFailureAfterTempCreation
        Assert-True ($failure.ExitCode -ne 0) `
            "Injected compiler failure unexpectedly succeeded."
        Assert-True (($failure.Stdout + $failure.Stderr) -match
                "injected compiler failure") `
            "Injected compiler failure did not reach the intended point."

        $helperTemps = @(Get-ChildItem -LiteralPath $testRoot -Force -Directory |
            Where-Object { $_.Name -like ".todo51-add-type-*" })
        Assert-True ($helperTemps.Count -eq 0) `
            "Helper compiler temp directory remained after success or failure."
        $poisonAfter = Get-TreeManifest -Root $poisonRoot
        Assert-True ($poisonAfter.FileCount -eq $poisonBefore.FileCount) `
            "External poison TEMP/TMP inventory changed."
        Assert-True ($poisonAfter.TotalBytes -eq $poisonBefore.TotalBytes) `
            "External poison TEMP/TMP byte count changed."
        Assert-True ($poisonAfter.Sha256 -eq $poisonBefore.Sha256) `
            "External poison TEMP/TMP bytes changed."
    }
    finally {
        if (Test-Path -LiteralPath $poisonRoot) {
            Remove-Item -LiteralPath $poisonRoot -Recurse -Force
        }
    }
}

function Test-RootIdentityGuard {
    $root = New-Fixture -Name "identity-guard"
    $manifest = Get-TreeManifest -Root $root
    Assert-FailureWithoutWrites -Root $root -Manifest $manifest `
        -ExpectedMessage "identity" `
        -TestFailurePoint RootIdentityMismatchBeforeSecondReplacement
}

function Test-RollbackBeforeSecondReplacement {
    $root = New-Fixture -Name "rollback-second"
    $manifest = Get-TreeManifest -Root $root
    Assert-FailureWithoutWrites -Root $root -Manifest $manifest `
        -ExpectedMessage "injected failure before replacement 2" `
        -TestFailurePoint BeforeSecondReplacement
}

function Test-EmittedTargetPostcondition {
    $root = New-Fixture -Name "emitted-target-postcondition"
    $manifest = Get-TreeManifest -Root $root
    Assert-FailureWithoutWrites -Root $root -Manifest $manifest `
        -ExpectedMessage "emitted target" `
        -TestFailurePoint RemoveEmittedTargetAfterReplacement
    Assert-True (Test-Path -LiteralPath (
            Join-Path $root "mingw64\lib\GraphicsMagick-1.3.46\modules-Q16\coders") `
            -PathType Container) `
        "Injected emitted directory was not restored after rollback."
}

function Test-FailureInjectionScope {
    $outsideParent = Join-Path "C:\tmp" `
        ("todo51-normalizer-nontest-" + [guid]::NewGuid().ToString("N"))
    try {
        [void] (New-Item -ItemType Directory -Path $outsideParent)
        $source = New-Fixture -Name "injection-scope-source"
        $root = Join-Path $outsideParent "fixture"
        Copy-Item -LiteralPath $source -Destination $root -Recurse
        $manifest = Get-TreeManifest -Root $root
        $result = Invoke-Normalizer -Root $root -ParentRoot $outsideParent `
            -Manifest $manifest -Mode Apply `
            -TestFailurePoint BeforeSecondReplacement
        Assert-True ($result.ExitCode -ne 0) `
            "Failure injection unexpectedly ran outside the synthetic test scope."
        Assert-True (($result.Stdout + $result.Stderr) -match
                "failure injection is forbidden") `
            "Out-of-scope failure injection did not identify the cause."
        $after = Get-TreeManifest -Root $root
        Assert-True ($after.Sha256 -eq $manifest.Sha256) `
            "Out-of-scope failure injection changed fixture bytes."
    }
    finally {
        if (Test-Path -LiteralPath $outsideParent) {
            Remove-Item -LiteralPath $outsideParent -Recurse -Force
        }
    }
}

function Test-ManifestRejection {
    $root = New-Fixture -Name "manifest"
    $manifest = Get-TreeManifest -Root $root
    $wrong = [pscustomobject] @{
        FileCount = $manifest.FileCount + 1
        TotalBytes = $manifest.TotalBytes
        Sha256 = $manifest.Sha256
    }
    Assert-FailureWithoutWrites -Root $root -Manifest $wrong -ExpectedMessage "manifest"
}

function Test-NoPartialWrites {
    $root = New-Fixture -Name "no-partial"
    Write-AsciiFile -Path (Join-Path $root "mingw64\lib\z-invalid.la") -Text @"
dependency_libs=' -L/usr/not-in-policy'
libdir='/usr/lib'
"@
    $manifest = Get-TreeManifest -Root $root
    $selection = New-LaSelectionContract -ParentRoot $testRoot `
        -Roots @("mingw64/lib/z-invalid.la")
    Assert-FailureWithoutWrites -Root $root -Manifest $manifest `
        -ExpectedMessage "unsupported" -Selection $selection
}

function Test-PlanDoesNotWrite {
    $root = New-Fixture -Name "plan"
    $manifest = Get-TreeManifest -Root $root
    $result = Invoke-Normalizer -Root $root -Manifest $manifest -Mode Plan
    $after = Get-TreeManifest -Root $root
    Assert-True ($result.ExitCode -eq 0) "Plan fixture failed."
    Assert-True ($manifest.Sha256 -eq $after.Sha256) "Plan mode changed fixture bytes."
    $json = $result.Stdout | ConvertFrom-Json
    Assert-True ($json.ChangedFileCount -eq 2) "Plan did not report expected changes."
}

$tests = @(
    "Test-SuccessAndAnomalies",
    "Test-AmbiguousCandidate",
    "Test-MissingCandidate",
    "Test-UnknownAbsolutePath",
    "Test-UnsupportedAssignment",
    "Test-UnsupportedQuoteForm",
    "Test-NonAsciiRejection",
    "Test-SelectionIgnoresUnrelatedScratchMetadata",
    "Test-SelectedScratchAndClosureEscapeFail",
    "Test-SelectionEntryRejections",
    "Test-RecursiveLibraryClosure",
    "Test-ClosureCyclesAndUniqueResolution",
    "Test-SeedLibraryContractRejections",
    "Test-ZeroByteFiles",
    "Test-EstablishedManifestFormat",
    "Test-EstablishedManifestReferenceRejections",
    "Test-ReparseRejection",
    "Test-PermanentRootRejection",
    "Test-NamespaceRejection",
    "Test-NegativePathSkipsHelperCompilation",
    "Test-CompilerTempConfinementAndCleanup",
    "Test-RootIdentityGuard",
    "Test-RollbackBeforeSecondReplacement",
    "Test-EmittedTargetPostcondition",
    "Test-FailureInjectionScope",
    "Test-ManifestRejection",
    "Test-NoPartialWrites",
    "Test-PlanDoesNotWrite"
)

try {
    [void] (New-Item -ItemType Directory -Path $testRoot)
    if (-not (Test-Path -LiteralPath $normalizer -PathType Leaf)) {
        throw "RED: normalizer implementation is missing: $normalizer"
    }

    $failures = New-Object Collections.Generic.List[string]
    foreach ($test in $tests) {
        try {
            & $test
            Write-Output "PASS $test"
        }
        catch {
            $failures.Add(("{0}: {1}" -f $test, $_.Exception.Message))
            Write-Output "FAIL $test"
        }
    }
    if ($failures.Count -ne 0) {
        throw ("{0} test(s) failed:`n{1}" -f $failures.Count,
            ($failures -join "`n"))
    }
    Write-Output ("PASS all {0} normalizer tests" -f $tests.Count)
}
finally {
    if (Test-Path -LiteralPath $testRoot) {
        $canonicalTestRoot = [IO.Path]::GetFullPath($testRoot)
        $canonicalTemp = [IO.Path]::GetFullPath("C:\tmp").TrimEnd("\") + "\"
        if (-not $canonicalTestRoot.StartsWith(
                $canonicalTemp, [StringComparison]::OrdinalIgnoreCase)) {
            throw "Refusing unsafe test cleanup: $canonicalTestRoot"
        }
        Remove-Item -LiteralPath $canonicalTestRoot -Recurse -Force
    }
}
