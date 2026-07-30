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
    param([Parameter(Mandatory = $true)][string] $Root)

    $canonical = [IO.Path]::GetFullPath($Root).TrimEnd("\")
    $files = @(Get-ChildItem -LiteralPath $canonical -Recurse -Force -File)
    $relativePaths = [string[]] @($files | ForEach-Object {
        $_.FullName.Substring($canonical.Length + 1).Replace("\", "/")
    })
    [Array]::Sort($relativePaths, [StringComparer]::Ordinal)

    $lines = New-Object Collections.Generic.List[string]
    [long] $bytes = 0
    foreach ($relative in $relativePaths) {
        $path = Join-Path $canonical $relative.Replace("/", "\")
        $file = Get-Item -LiteralPath $path
        $bytes += $file.Length
        $hash = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
        $lines.Add(("{0}`t{1}`t{2}" -f $relative, $file.Length, $hash))
    }

    $manifestBytes = $utf8NoBom.GetBytes(($lines -join "`n"))
    return [pscustomobject] @{
        FileCount = $relativePaths.Count
        TotalBytes = $bytes
        Sha256 = Get-Sha256Bytes -Bytes $manifestBytes
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
            "RootIdentityMismatchBeforeSecondReplacement",
            "BeforeSecondReplacement",
            "RemoveEmittedTargetAfterReplacement")]
        [string] $TestFailurePoint = "None"
    )

    $stdout = Join-Path $testRoot ("stdout-" + [guid]::NewGuid().ToString("N") + ".log")
    $stderr = Join-Path $testRoot ("stderr-" + [guid]::NewGuid().ToString("N") + ".log")
    function Quote-ProcessArgument {
        param([Parameter(Mandatory = $true)][string] $Value)

        return '"' + $Value.Replace('"', '\"') + '"'
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
        "-Mode", $Mode
    )
    if ($TestFailurePoint -ne "None") {
        $arguments += @("-TestFailurePoint", $TestFailurePoint)
    }
    $process = Start-Process -FilePath "powershell.exe" -ArgumentList $arguments `
        -RedirectStandardOutput $stdout -RedirectStandardError $stderr `
        -WindowStyle Hidden -Wait -PassThru
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
            "RootIdentityMismatchBeforeSecondReplacement",
            "BeforeSecondReplacement",
            "RemoveEmittedTargetAfterReplacement")]
        [string] $TestFailurePoint = "None"
    )

    $before = Get-TreeManifest -Root $Root
    $result = Invoke-Normalizer -Root $Root -Manifest $Manifest -Mode Apply `
        -TestFailurePoint $TestFailurePoint
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
    Assert-FailureWithoutWrites -Root $root -Manifest $manifest -ExpectedMessage "missing"
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
    Assert-FailureWithoutWrites -Root $root -Manifest $manifest -ExpectedMessage "assignment"
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
    Assert-FailureWithoutWrites -Root $root -Manifest $manifest -ExpectedMessage "non-ASCII"
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
    Assert-FailureWithoutWrites -Root $root -Manifest $manifest -ExpectedMessage "unsupported"
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
    "Test-ReparseRejection",
    "Test-PermanentRootRejection",
    "Test-NamespaceRejection",
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
