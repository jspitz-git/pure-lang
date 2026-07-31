[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$scriptPath = Join-Path $PSScriptRoot 'stage_task3_runtime.ps1'
$testRoot = Join-Path $env:TEMP ('todo51-stage-tests-' + [guid]::NewGuid().ToString('N'))
$permanentRoot = Join-Path $testRoot 'permanent-octave'
$parent = Join-Path $testRoot 'parent'
$stage = Join-Path $parent 'stage'
$pure = Join-Path $testRoot 'pure'
$octave = Join-Path $testRoot 'normalized-octave'
$bridge = Join-Path $testRoot 'bridge'
$probe = Join-Path $testRoot 'probe'
$patched = Join-Path $testRoot 'liboctave-13.dll'

function Write-TestFile {
  param([string]$Path, [string]$Text)
  $dir = Split-Path -Parent $Path
  [System.IO.Directory]::CreateDirectory($dir) | Out-Null
  [System.IO.File]::WriteAllText($Path, $Text, [System.Text.Encoding]::ASCII)
}

function Assert-True {
  param([bool]$Condition, [string]$Message)
  if (-not $Condition) { throw $Message }
}

function Invoke-ExpectedFailure {
  param([scriptblock]$Action, [string]$Label)
  $failed = $false
  try { & $Action; if ($LASTEXITCODE -ne 0) { $failed = $true } } catch { $failed = $true }
  Assert-True $failed "$Label was accepted."
}

try {
  [System.IO.Directory]::CreateDirectory($parent) | Out-Null
  [System.IO.Directory]::CreateDirectory($permanentRoot) | Out-Null
  Write-TestFile (Join-Path $pure 'bin\pure.exe') 'pure-exe'
  Write-TestFile (Join-Path $pure 'bin\libpure.dll') 'pure-runtime'
  Write-TestFile (Join-Path $pure 'lib\pure\prelude.pure') 'prelude'
  Write-TestFile (Join-Path $octave 'mingw64\bin\liboctave-13.dll') 'original-octave'
  Write-TestFile (Join-Path $octave 'mingw64\bin\libgcc_s_seh-1.dll') 'canonical-gcc'
  Write-TestFile (Join-Path $octave 'mingw64\share\octave\11.3.0\m\optimization\__all_opts__.m') 'opts'
  Write-TestFile (Join-Path $bridge 'octave_embed.dll') 'loader'
  Write-TestFile (Join-Path $bridge 'octave_bridge_impl.dll') 'implementation'
  Write-TestFile (Join-Path $bridge 'octave.pure') 'module'
  Write-TestFile (Join-Path $probe 'embed_probe.cc') 'probe'
  Write-TestFile $patched 'patched-octave'

  # This must fail before the assembler exists.  Once it exists, this case
  # catches a stage that copies the original liboctave or fails to write an
  # audit manifest.
  & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $scriptPath `
    -StageRoot $stage -DisposableParent $parent -PermanentOctaveRoot $permanentRoot `
    -PureRuntimeRoot $pure -NormalizedOctaveRoot $octave -BridgeRoot $bridge -BridgeModuleSource (Join-Path $bridge 'octave.pure') `
    -ProbeRoot $probe -PatchedLiboctave $patched -ExpectedPatchedSha256 `
    ((Get-FileHash -LiteralPath $patched -Algorithm SHA256).Hash) `
    -ExpectedLibgccSha256 ((Get-FileHash -LiteralPath (Join-Path $octave 'mingw64\bin\libgcc_s_seh-1.dll') -Algorithm SHA256).Hash) `
    -TestMode
  Assert-True (Test-Path -LiteralPath (Join-Path $stage 'mingw64\bin\liboctave-13.dll') -PathType Leaf) 'Stage omitted liboctave.'
  Assert-True ((Get-FileHash -LiteralPath (Join-Path $stage 'mingw64\bin\liboctave-13.dll') -Algorithm SHA256).Hash -eq (Get-FileHash -LiteralPath $patched -Algorithm SHA256).Hash) 'Stage retained original liboctave.'
  Assert-True ((Get-FileHash -LiteralPath (Join-Path $octave 'mingw64\bin\liboctave-13.dll') -Algorithm SHA256).Hash -ne (Get-FileHash -LiteralPath $patched -Algorithm SHA256).Hash) 'Assembler modified its source Octave tree.'
  Assert-True (Test-Path -LiteralPath (Join-Path $stage 'stage-manifest.tsv') -PathType Leaf) 'Stage omitted its manifest.'
  Assert-True ((Get-Content -LiteralPath (Join-Path $stage 'stage-mapping.tsv') -Raw) -match 'patched-liboctave') 'Stage mapping omitted the patched-DLL provenance.'
  Write-Output 'PASS Test-SuccessCopiesOnlyTheStage'

  # Same length and timestamp must not hide a content change from the
  # streaming SHA-256 preflight.
  $originalHash = (Get-FileHash -LiteralPath $patched -Algorithm SHA256).Hash
  $originalTime = (Get-Item -LiteralPath $patched).LastWriteTimeUtc
  Write-TestFile $patched 'broken--octave'
  [IO.File]::SetLastWriteTimeUtc($patched, $originalTime)
  Invoke-ExpectedFailure { & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $scriptPath -StageRoot (Join-Path $parent 'content-hash-reject') -DisposableParent $parent -PermanentOctaveRoot $permanentRoot -PureRuntimeRoot $pure -NormalizedOctaveRoot $octave -BridgeRoot $bridge -BridgeModuleSource (Join-Path $bridge 'octave.pure') -ProbeRoot $probe -PatchedLiboctave $patched -ExpectedPatchedSha256 $originalHash -ExpectedLibgccSha256 ((Get-FileHash (Join-Path $octave 'mingw64\bin\libgcc_s_seh-1.dll') -Algorithm SHA256).Hash) -TestMode } 'Same-length same-mtime content change'
  Write-TestFile $patched 'patched-octave'
  Write-Output 'PASS Test-RejectsSameLengthSameMtimeContentChange'

  Invoke-ExpectedFailure { & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $scriptPath -StageRoot $stage -DisposableParent $parent -PermanentOctaveRoot $permanentRoot -PureRuntimeRoot $pure -NormalizedOctaveRoot $octave -BridgeRoot $bridge -BridgeModuleSource (Join-Path $bridge 'octave.pure') -ProbeRoot $probe -PatchedLiboctave $patched -ExpectedPatchedSha256 ((Get-FileHash $patched -Algorithm SHA256).Hash) -ExpectedLibgccSha256 ((Get-FileHash (Join-Path $octave 'mingw64\bin\libgcc_s_seh-1.dll') -Algorithm SHA256).Hash) -TestMode } 'Existing stage root'
  Write-Output 'PASS Test-RejectsExistingStage'

  Invoke-ExpectedFailure { & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $scriptPath -StageRoot (Join-Path $parent 'permanent-alias') -DisposableParent $parent -PermanentOctaveRoot $octave -PureRuntimeRoot $pure -NormalizedOctaveRoot $octave -BridgeRoot $bridge -BridgeModuleSource (Join-Path $bridge 'octave.pure') -ProbeRoot $probe -PatchedLiboctave $patched -ExpectedPatchedSha256 ((Get-FileHash $patched -Algorithm SHA256).Hash) -ExpectedLibgccSha256 ((Get-FileHash (Join-Path $octave 'mingw64\bin\libgcc_s_seh-1.dll') -Algorithm SHA256).Hash) -TestMode } 'Permanent root input'
  Write-Output 'PASS Test-RejectsPermanentOctaveRoot'

  $link = Join-Path $testRoot 'linked-parent'
  cmd.exe /c "mklink /J `"$link`" `"$parent`"" | Out-Null
  if (Test-Path -LiteralPath $link) {
    Invoke-ExpectedFailure { & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $scriptPath -StageRoot (Join-Path $link 'reparse-stage') -DisposableParent $link -PermanentOctaveRoot $permanentRoot -PureRuntimeRoot $pure -NormalizedOctaveRoot $octave -BridgeRoot $bridge -BridgeModuleSource (Join-Path $bridge 'octave.pure') -ProbeRoot $probe -PatchedLiboctave $patched -ExpectedPatchedSha256 ((Get-FileHash $patched -Algorithm SHA256).Hash) -ExpectedLibgccSha256 ((Get-FileHash (Join-Path $octave 'mingw64\bin\libgcc_s_seh-1.dll') -Algorithm SHA256).Hash) -TestMode } 'Reparse disposable parent'
    Write-Output 'PASS Test-RejectsReparseParent'
  }
  Write-Output 'PASS all task3 staging tests'
}
finally {
  if (Test-Path -LiteralPath $testRoot) { Remove-Item -LiteralPath $testRoot -Recurse -Force }
}
