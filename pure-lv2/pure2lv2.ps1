Set-StrictMode -Version 2.0
$Arguments = @($args)
$ErrorActionPreference = 'Stop'

function Show-Usage {
  @'
USAGE: pure2lv2 [-h|-s] [-o bundle-name] [-u uri-prefix] script-name ...
-h, --help:      print this message and exit
-o, --output:    specify the bundle directory
-s, --script:    include the source script in the bundle
-u, --uriprefix: specify the URI prefix of the bundle
'@ | Write-Output
}

function Resolve-RequiredFile([string] $Path, [string] $Description) {
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
    throw "$Description not found: $Path"
  }
  return [IO.Path]::GetFullPath($Path)
}

function Split-NativeCommandLine([string] $CommandLine) {
  $matches = [regex]::Matches($CommandLine, '"(?:[^"]|"")*"|\S+')
  $tokens = @()
  foreach ($match in $matches) {
    $token = $match.Value
    if ($token.Length -ge 2 -and
        $token[0] -eq '"' -and $token[$token.Length - 1] -eq '"') {
      $token = $token.Substring(1, $token.Length - 2).Replace('""', '"')
    }
    $tokens += $token
  }
  return $tokens
}

function Invoke-Checked(
  [string] $Executable,
  [string[]] $NativeArguments,
  [string] $Description
) {
  & $Executable @NativeArguments
  if ($LASTEXITCODE -ne 0) {
    throw "$Description failed with exit code $LASTEXITCODE"
  }
}

$sourceMode = $false
$bundleArgument = $null
$uriPrefix = 'http://purelang.bitbucket.org'
$positionals = @()
for ($index = 0; $index -lt $Arguments.Count; ++$index) {
  switch ($Arguments[$index]) {
    { $_ -eq '-h' -or $_ -eq '--help' } {
      Show-Usage
      exit 0
    }
    { $_ -eq '-s' -or $_ -eq '--script' } {
      $sourceMode = $true
      continue
    }
    { $_ -eq '-o' -or $_ -eq '--output' } {
      if (++$index -ge $Arguments.Count) {
        throw "$($Arguments[$index - 1]) requires a bundle directory"
      }
      $bundleArgument = $Arguments[$index]
      continue
    }
    { $_ -eq '-u' -or $_ -eq '--uriprefix' } {
      if (++$index -ge $Arguments.Count) {
        throw "$($Arguments[$index - 1]) requires a URI prefix"
      }
      $uriPrefix = $Arguments[$index]
      continue
    }
    { $_ -eq '--' } {
      if ($index + 1 -lt $Arguments.Count) {
        $positionals += $Arguments[($index + 1)..($Arguments.Count - 1)]
      }
      $index = $Arguments.Count
      continue
    }
    { $_.StartsWith('-') } {
      throw "unknown option: $_"
    }
    default {
      $positionals += $Arguments[$index]
    }
  }
}

if ($positionals.Count -eq 0) {
  throw "no script name specified (try 'pure2lv2 --help')"
}

$scriptPath = Resolve-RequiredFile $positionals[0] 'Pure plugin script'
$additionalSources = @()
if ($positionals.Count -gt 1) {
  foreach ($source in $positionals[1..($positionals.Count - 1)]) {
    $additionalSources += Resolve-RequiredFile $source 'Additional source'
  }
}
$pluginName = [IO.Path]::GetFileNameWithoutExtension($scriptPath)
$cName = [regex]::Replace($pluginName, '[^A-Za-z0-9]', '_')
$loaderName = "__${cName}_main__"
$bundlePath = if ($bundleArgument) {
  [IO.Path]::GetFullPath($bundleArgument)
} else {
  [IO.Path]::GetFullPath((Join-Path (Get-Location) "${pluginName}.lv2"))
}
$bundleRoot = [IO.Path]::GetPathRoot($bundlePath)
if ($bundlePath -eq $bundleRoot) {
  throw "refusing to use a filesystem root as the bundle directory"
}

$prefix = if ($env:PURE2LV2_PREFIX) {
  [IO.Path]::GetFullPath($env:PURE2LV2_PREFIX)
} else {
  [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
}
$moduleDir = Join-Path $prefix 'lib\pure'
$pureExe = if ($env:PURE2LV2_PURE) {
  Resolve-RequiredFile $env:PURE2LV2_PURE 'Pure interpreter'
} else {
  Resolve-RequiredFile (Join-Path $prefix 'bin\pure.exe') 'Pure interpreter'
}
$bridgeSource = Resolve-RequiredFile(
  (Join-Path $moduleDir 'lv2pure.c')) 'Pure LV2 bridge source'
$manifestTemplate = Resolve-RequiredFile(
  (Join-Path $moduleDir 'lv2-manifest-template.ttl')) 'LV2 manifest template'
$pureInclude = Resolve-RequiredFile(
  (Join-Path $prefix 'include\pure\runtime.h')) 'Pure runtime header'
$pureImportLibrary = Resolve-RequiredFile(
  (Join-Path $prefix 'lib\libpure.dll.a')) 'Pure import library'
$lv2Include = if ($env:PURE2LV2_LV2_INCLUDE) {
  [IO.Path]::GetFullPath($env:PURE2LV2_LV2_INCLUDE)
} else {
  Join-Path $prefix 'include'
}
if (-not (Test-Path -LiteralPath(
    (Join-Path $lv2Include 'lv2\lv2plug.in\ns\lv2core\lv2.h')) -PathType Leaf)) {
  throw "LV2 headers not found below: $lv2Include"
}

$compiler = if ($env:PURE2LV2_CC) {
  Resolve-RequiredFile $env:PURE2LV2_CC 'C compiler'
} elseif (Test-Path -LiteralPath(
    (Join-Path $prefix 'tools\bin\clang.exe')) -PathType Leaf) {
  Join-Path $prefix 'tools\bin\clang.exe'
} else {
  $command = Get-Command clang.exe -CommandType Application -ErrorAction Stop
  $command.Source
}
$toolDirectory = if ($env:PURE2LV2_TOOL_DIR) {
  [IO.Path]::GetFullPath($env:PURE2LV2_TOOL_DIR)
} else {
  Split-Path -Parent $compiler
}
$env:PATH = "$toolDirectory;$(Join-Path $prefix 'bin');$env:PATH"

$temporaryDirectory = Join-Path(
  [IO.Path]::GetTempPath()) ('pure2lv2-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $temporaryDirectory | Out-Null
$createdBundle = $false
try {
  $linkArguments = @()
  $objectName = "${pluginName}.o"
  if (-not $sourceMode) {
    $requiredScript = Join-Path $temporaryDirectory 'required.pure'
    [IO.File]::WriteAllText(
      $requiredScript,
      "#! --required manifest`n#! --required plugin`n",
      [Text.UTF8Encoding]::new($false))

    Push-Location $temporaryDirectory
    try {
      $pureArguments = @(
        '-v0100',
        '-I', $moduleDir,
        '-L', $moduleDir,
        '-c', 'required.pure', $scriptPath,
        '-o', $objectName,
        "--main=$loaderName")
      $savedErrorActionPreference = $ErrorActionPreference
      $ErrorActionPreference = 'Continue'
      try {
        $compilerOutput = @(& $pureExe @pureArguments 2>&1 |
          ForEach-Object { $_.ToString() })
        $compilerResult = $LASTEXITCODE
      } finally {
        $ErrorActionPreference = $savedErrorActionPreference
      }
      $compilerOutput | Write-Output
      if ($compilerResult -ne 0) {
        throw "Pure batch compilation failed with exit code $compilerResult"
      }
      if (-not (Test-Path -LiteralPath $objectName -PathType Leaf)) {
        throw "Pure batch compilation did not create $objectName"
      }
      $linkLine = @($compilerOutput |
        Where-Object { $_.StartsWith('Link with: ') } |
        Select-Object -Last 1)
      if ($linkLine.Count -ne 1) {
        throw 'Pure batch compilation did not report linker dependencies'
      }
      $tokens = @(Split-NativeCommandLine(
        $linkLine[0].Substring('Link with: '.Length)))
      if ($tokens.Count -lt 2) {
        throw "Invalid Pure linker dependency line: $($linkLine[0])"
      }
      if ($tokens.Count -gt 2) {
        $linkArguments = $tokens[2..($tokens.Count - 1)]
      }
    } finally {
      Pop-Location
    }
  }

  if (Test-Path -LiteralPath $bundlePath) {
    Remove-Item -LiteralPath $bundlePath -Recurse -Force
  }
  New-Item -ItemType Directory -Path $bundlePath | Out-Null
  $createdBundle = $true
  $pluginBinary = Join-Path $bundlePath "${pluginName}.dll"
  $definitions = @(
    '-DDLLEXT=\".dll\"',
    "-DURI_PREFIX=\`"$($uriPrefix.TrimEnd('/'))/\`"",
    "-DPLUGIN_NAME=\`"$pluginName\`"")
  if ($sourceMode) {
    $definitions += "-DPLUGIN_SCRIPT=\`"$([IO.Path]::GetFileName($scriptPath))\`""
  } else {
    $definitions += "-DLOADER_NAME=$loaderName"
  }
  $nativeArguments = @(
    '-shared',
    '-O3',
    '-std=c99',
    '-Wno-dll-attribute-on-redeclaration',
    '-I', (Join-Path $prefix 'include'),
    '-I', $lv2Include) + $definitions + @(
    '-o', $pluginBinary,
    $bridgeSource)
  if (-not $sourceMode) {
    $nativeArguments += Join-Path $temporaryDirectory $objectName
    $nativeArguments += $linkArguments
  } else {
    $nativeArguments += @(
      '-L', (Join-Path $prefix 'lib'),
      '-lpure')
  }
  Invoke-Checked $compiler $nativeArguments 'LV2 plugin linkage'

  if ($sourceMode) {
    Copy-Item -LiteralPath $scriptPath -Destination $bundlePath
    foreach ($source in $additionalSources) {
      Copy-Item -LiteralPath $source -Destination $bundlePath
    }
  }
  $pluginUri = "$($uriPrefix.TrimEnd('/'))/$pluginName"
  $manifest = [IO.File]::ReadAllText($manifestTemplate)
  $manifest = $manifest.Replace('@name@', $pluginName).
    Replace('@uri@', $pluginUri).
    Replace('@dllext@', '.dll')
  [IO.File]::WriteAllText(
    (Join-Path $bundlePath 'manifest.ttl'),
    $manifest,
    [Text.UTF8Encoding]::new($false))
  Write-Output "bundle written to $bundlePath"
} catch {
  if ($createdBundle -and (Test-Path -LiteralPath $bundlePath)) {
    Remove-Item -LiteralPath $bundlePath -Recurse -Force
  }
  Write-Error $_
  exit 1
} finally {
  if (Test-Path -LiteralPath $temporaryDirectory) {
    Remove-Item -LiteralPath $temporaryDirectory -Recurse -Force
  }
}
