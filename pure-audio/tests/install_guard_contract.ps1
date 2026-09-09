param([Parameter(Mandatory=$true)][string]$SourceDir,
      [Parameter(Mandatory=$true)][string]$BuildDir,
      [Parameter(Mandatory=$true)][string]$PurePrefix,
      [switch]$LockRedOnly, [switch]$SwapRedOnly)
$ErrorActionPreference = 'Stop'
$auditCmake = 'C:/msys64/clang64/bin/cmake.exe'
$auditRunner = "$BuildDir/run_pure_test.exe"
$auditWork = (& $auditRunner --create-leaf).Trim()
if ($LASTEXITCODE -ne 0 -or -not $auditWork) { throw 'Cannot create native-owned fixture leaf' }
$auditStage = "$auditWork/stage"
New-Item -ItemType Directory -Path $auditStage | Out-Null
Copy-Item -Path "$PurePrefix/*" -Destination $auditStage -Recurse
function Get-AudioTree([string]$Root) {
  @(Get-ChildItem -LiteralPath $Root -Recurse -File | ForEach-Object {
    $auditHasher = [Security.Cryptography.SHA256]::Create()
    $auditInput = [IO.File]::OpenRead($_.FullName)
    try { $auditHash = [BitConverter]::ToString($auditHasher.ComputeHash($auditInput)).Replace('-','') }
    finally { $auditInput.Dispose(); $auditHasher.Dispose() }
    $_.FullName.Substring($Root.Length).Replace('\','/') + '|' + $auditHash
  } | Sort-Object)
}
if ($LockRedOnly) {
  $auditBefore = Get-AudioTree $auditStage
  $auditLock = [IO.File]::Open("$BuildDir/install-operation.lock", [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
  try {
    $ErrorActionPreference = 'Continue'
    $auditOutput = & $auditCmake --install $BuildDir --prefix $auditStage --component runtime 2>&1
    $auditRc = $LASTEXITCODE
  } finally { $ErrorActionPreference = 'Stop'; $auditLock.Dispose() }
  $auditAfter = Get-AudioTree $auditStage
  if ($auditRc -eq 0 -or (Compare-Object $auditBefore $auditAfter)) {
    throw "RED: actual installer ignored exclusive operation ownership ($auditWork)"
  }
  'INSTALL_EXCLUSIVE_LOCK_OK'
  & $auditRunner --cleanup --cwd $auditWork
  if ($LASTEXITCODE -ne 0) { throw 'Owned cleanup failed' }
  exit 0
}
if ($SwapRedOnly) {
  # The CMake wrapper adds an observation gate immediately before the real
  # first COPY_FILE call. All source selection, preflight and copying remains
  # the production implementation; the outside sentinel is our oracle.
  $auditOutside = "$auditWork/outside"
  New-Item -ItemType Directory -Path $auditOutside | Out-Null
  $auditTemplate = @'
set(AUDIO_INSTALL_CONTEXT [==[@BUILD@/windows-install-context.cmake]==])
set(STAGE_PREFIX [==[@STAGE@]==])
set(AUDIO_INSTALL_MODE install)
set(AUDIO_INSTALL_COMPONENT runtime)
macro(file)
  if("${ARGV0}" STREQUAL "COPY_FILE" AND NOT swapped)
    execute_process(COMMAND C:/Windows/System32/WindowsPowerShell/v1.0/powershell.exe -NoProfile -NonInteractive -Command
      "$ErrorActionPreference='Stop'; $root=[IO.Path]::GetFullPath('@WORK@/'); $old=[IO.Path]::GetFullPath('@STAGE@/lib/pure'); $new=[IO.Path]::GetFullPath('@WORK@/original-pure'); if(-not $old.StartsWith($root,[StringComparison]::OrdinalIgnoreCase) -or -not $new.StartsWith($root,[StringComparison]::OrdinalIgnoreCase)) { throw 'outside fixture' }; Move-Item -LiteralPath $old -Destination $new; New-Item -ItemType Junction -Path $old -Target '@OUTSIDE@' | Out-Null"
      RESULT_VARIABLE rc)
    if(NOT rc EQUAL 0)
      message(FATAL_ERROR "Could not perform controlled ancestor swap")
    endif()
    set(swapped TRUE CACHE INTERNAL "fixture observation gate")
  endif()
  _file(${ARGV})
endmacro()
include([==[@SOURCE@/cmake/VerifyInstalledPackage.cmake]==])
'@
  # Test fixture generation, not production source editing.
  $auditText = $auditTemplate.Replace('@BUILD@',$BuildDir).Replace('@STAGE@',$auditStage).Replace('@WORK@',$auditWork).Replace('@OUTSIDE@',$auditOutside).Replace('@SOURCE@',$SourceDir)
  [IO.File]::WriteAllText("$auditWork/swap-gate.cmake", $auditText)
  $ErrorActionPreference = 'Continue'
  $auditOutput = & $auditCmake -P "$auditWork/swap-gate.cmake" 2>&1
  $auditRc = $LASTEXITCODE
  $ErrorActionPreference = 'Stop'
  if (-not (Test-Path -LiteralPath "$auditWork/original-pure" -PathType Container)) {
    throw "Observation gate was not reached ($auditWork): $auditOutput"
  }
  $auditOutsideFiles = @(Get-ChildItem -LiteralPath $auditOutside -Recurse -File)
  $auditLink = "$auditStage/lib/pure"
  if ((Get-Item -LiteralPath $auditLink -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) {
    [IO.Directory]::Delete($auditLink)
  }
  if ($auditOutsideFiles.Count -ne 0) {
    throw "RED: post-preflight ancestor swap redirected $($auditOutsideFiles.Count) writes outside the stage ($auditWork)"
  }
  if ($auditRc -eq 0) { throw 'Swap unexpectedly succeeded' }
  'INSTALL_POST_PREFLIGHT_SWAP_OK'
  & $auditRunner --cleanup --cwd $auditWork
  if ($LASTEXITCODE -ne 0) { throw 'Owned cleanup failed' }
  exit 0
}
# The fixture is compiled from the same guard implementation with one
# observation gate before the first actual copy. That gate is absent from the
# production executable. The launched child is the real installed verifier.
$auditReadyName = 'Local\pure-audio-ready-' + [Guid]::NewGuid().ToString('N')
$auditReleaseName = 'Local\pure-audio-release-' + [Guid]::NewGuid().ToString('N')
$auditReady = New-Object Threading.EventWaitHandle($false, [Threading.EventResetMode]::ManualReset, $auditReadyName)
$auditRelease = New-Object Threading.EventWaitHandle($false, [Threading.EventResetMode]::ManualReset, $auditReleaseName)
$auditStart = New-Object Diagnostics.ProcessStartInfo
$auditStart.FileName = "$BuildDir/install_guard_fixture.exe"
$auditArguments = @('--run', $auditStage, $BuildDir, $auditCmake, "$BuildDir/windows-install-context.cmake", "$SourceDir/cmake/VerifyInstalledPackage.cmake", 'install', 'runtime')
$auditStart.Arguments = ($auditArguments | ForEach-Object { '"' + $_ + '"' }) -join ' '
$auditStart.UseShellExecute = $false
$auditStart.CreateNoWindow = $true
$auditStart.RedirectStandardOutput = $true
$auditStart.RedirectStandardError = $true
$auditStart.EnvironmentVariables['AUDIO_GUARD_TEST_READY'] = $auditReadyName
$auditStart.EnvironmentVariables['AUDIO_GUARD_TEST_RELEASE'] = $auditReleaseName
$auditProcess = [Diagnostics.Process]::Start($auditStart)
$auditStdout = $auditProcess.StandardOutput.ReadToEndAsync()
$auditStderr = $auditProcess.StandardError.ReadToEndAsync()
try {
  if (-not $auditReady.WaitOne(25000)) {
    $auditRelease.Set() | Out-Null
    $auditProcess.WaitForExit(10000) | Out-Null
    throw "Actual-copy observation gate was not reached ($auditWork): $($auditStdout.Result) $($auditStderr.Result)"
  }
  $auditBefore = Get-AudioTree $auditStage
  & "$BuildDir/install_guard_fixture.exe" --test-global-owner $auditStage
  if ($LASTEXITCODE -ne 0) { throw 'Global stage ownership contract failed' }
  & "$BuildDir/install_guard_fixture.exe" --test-directory-write "$auditStage/lib/pure"
  if ($LASTEXITCODE -ne 0) { throw 'Reparse conversion write access was not excluded' }
  # A second genuine component installer must fail while the first is paused.
  $ErrorActionPreference = 'Continue'
  $auditOutput = & $auditCmake --install $BuildDir --prefix $auditStage --component documentation 2>&1
  $auditRc = $LASTEXITCODE
  $ErrorActionPreference = 'Stop'
  if ($auditRc -eq 0 -or "$auditOutput" -notmatch 'already owned' -or (Compare-Object $auditBefore (Get-AudioTree $auditStage))) {
    throw "Concurrent actual installer failed exclusion: $auditOutput"
  }
  # A different build has a different operation file, but the same volume/file
  # stage identity. Exercise an actual cmake --install entry point for it too.
  $auditOtherBuild = "$auditWork/other-build"
  New-Item -ItemType Directory -Path $auditOtherBuild | Out-Null
  $auditOtherContext = [IO.File]::ReadAllText("$BuildDir/windows-install-context.cmake").Replace("set(AUDIO_INSTALL_BUILD_DIR [==[$BuildDir]==])", "set(AUDIO_INSTALL_BUILD_DIR [==[$auditOtherBuild]==])")
  [IO.File]::WriteAllText("$auditOtherBuild/windows-install-context.cmake", $auditOtherContext)
  $auditOtherInstall = [IO.File]::ReadAllText("$BuildDir/cmake_install.cmake").Replace("$BuildDir/windows-install-context.cmake", "$auditOtherBuild/windows-install-context.cmake")
  [IO.File]::WriteAllText("$auditOtherBuild/cmake_install.cmake", $auditOtherInstall)
  Copy-Item -LiteralPath "$BuildDir/install-guard.sha256" -Destination "$auditOtherBuild/install-guard.sha256"
  $ErrorActionPreference = 'Continue'
  $auditOutput = & $auditCmake --install $auditOtherBuild --prefix $auditStage --component runtime 2>&1
  $auditRc = $LASTEXITCODE
  $ErrorActionPreference = 'Stop'
  if ($auditRc -eq 0 -or "$auditOutput" -notmatch 'stage identity already owned' -or (Compare-Object $auditBefore (Get-AudioTree $auditStage))) {
    throw "Cross-build stage identity exclusion failed: $auditOutput"
  }
  # A junction replacement requires deleting/renaming the retained ancestor.
  # Attempt it after real preflight, just before native atomic publication.
  $auditOutside = "$auditWork/outside"
  New-Item -ItemType Directory -Path $auditOutside | Out-Null
  $auditOld = [IO.Path]::GetFullPath("$auditStage/lib/pure")
  $auditBackup = [IO.Path]::GetFullPath("$auditWork/original-pure")
  $auditRoot = [IO.Path]::GetFullPath("$auditWork/")
  if (-not $auditOld.StartsWith($auditRoot,[StringComparison]::OrdinalIgnoreCase) -or -not $auditBackup.StartsWith($auditRoot,[StringComparison]::OrdinalIgnoreCase)) { throw 'Unsafe fixture move path' }
  $auditSwapBlocked = $false
  try { Move-Item -LiteralPath $auditOld -Destination $auditBackup -ErrorAction Stop }
  catch { $auditSwapBlocked = $true }
  if (-not $auditSwapBlocked) { throw 'Retained ancestor was renamed after preflight' }
  if ((Get-ChildItem -LiteralPath $auditOutside -Force).Count -ne 0) { throw 'Outside write before release' }
  $auditRelease.Set() | Out-Null
  if (-not $auditProcess.WaitForExit(90000)) { throw 'Guarded installer did not finish' }
  if ($auditProcess.ExitCode -ne 0 -or $auditStdout.Result -notmatch 'INSTALL_GUARD_OK') {
    throw "First installer failed: $($auditStdout.Result) $($auditStderr.Result)"
  }
  if ((Get-ChildItem -LiteralPath $auditOutside -Force).Count -ne 0) { throw 'Outside write after release' }
  # Every identity and operation lock must be released, including failure paths.
  $auditLock = [IO.File]::Open("$BuildDir/install-operation.lock",[IO.FileMode]::Open,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
  $auditLock.Dispose()
  Move-Item -LiteralPath $auditOld -Destination $auditBackup
  Move-Item -LiteralPath $auditBackup -Destination $auditOld
  $auditOutput = & $auditCmake --install $BuildDir --prefix $auditStage --component documentation 2>&1
  if ($LASTEXITCODE -ne 0) { throw "Post-teardown install failed: $auditOutput" }
  $auditOutput = & $auditCmake "-DAUDIO_INSTALL_CONTEXT=$BuildDir/windows-install-context.cmake" "-DSTAGE_PREFIX=$auditStage" -P "$SourceDir/cmake/VerifyInstalledPackage.cmake" 2>&1
  if ($LASTEXITCODE -ne 0 -or "$auditOutput" -notmatch 'PURE_AUDIO_DONE_[a-f0-9]+' -or "$auditOutput" -notmatch 'PE_CLOSURE_OK count=29') {
    throw "Guarded pristine PE/smoke failed: $auditOutput"
  }
  $auditBefore = Get-AudioTree $auditStage
  $env:PURE_AUDIO_INSTALL_CHANNEL = '\\.\pipe\pure-audio-install-forged'
  try {
    $ErrorActionPreference = 'Continue'
    $auditOutput = & $auditCmake "-DAUDIO_INSTALL_CONTEXT=$BuildDir/windows-install-context.cmake" "-DSTAGE_PREFIX=$auditStage" -DAUDIO_INSTALL_MODE=install -DAUDIO_INSTALL_COMPONENT=runtime -P "$SourceDir/cmake/VerifyInstalledPackage.cmake" 2>&1
    $auditRc = $LASTEXITCODE
  } finally { $ErrorActionPreference = 'Stop'; Remove-Item Env:PURE_AUDIO_INSTALL_CHANNEL }
  if ($auditRc -eq 0 -or (Compare-Object $auditBefore (Get-AudioTree $auditStage))) { throw 'Forged ownership channel bypassed guard' }
} finally {
  $auditRelease.Set() | Out-Null
  if (-not $auditProcess.HasExited) { $auditProcess.Kill(); $auditProcess.WaitForExit() }
  $auditProcess.Dispose(); $auditReady.Dispose(); $auditRelease.Dispose()
}
# Independent post-preflight endpoint collision: the first runtime destination
# receives a junction after preflight, before publication. Atomic rename must
# not overwrite it or write through it; its owned temporary must be removed.
$auditStage = "$auditWork/atomic-stage"
New-Item -ItemType Directory -Path $auditStage | Out-Null
Copy-Item -Path "$PurePrefix/*" -Destination $auditStage -Recurse
$auditReady = New-Object Threading.EventWaitHandle($false, [Threading.EventResetMode]::ManualReset, $auditReadyName)
$auditRelease = New-Object Threading.EventWaitHandle($false, [Threading.EventResetMode]::ManualReset, $auditReleaseName)
$auditArguments[1] = $auditStage
$auditStart.Arguments = ($auditArguments | ForEach-Object { '"' + $_ + '"' }) -join ' '
$auditProcess = [Diagnostics.Process]::Start($auditStart)
$auditStdout = $auditProcess.StandardOutput.ReadToEndAsync()
$auditStderr = $auditProcess.StandardError.ReadToEndAsync()
try {
  if (-not $auditReady.WaitOne(25000)) { throw "Atomic publication gate not reached ($auditWork)" }
  $auditBefore = Get-AudioTree $auditStage
  $auditLink = "$auditStage/bin/libFLAC.dll"
  New-Item -ItemType Junction -Path $auditLink -Target $auditOutside | Out-Null
  $auditRelease.Set() | Out-Null
  if (-not $auditProcess.WaitForExit(90000)) { throw 'Atomic collision installer did not finish' }
  if ($auditProcess.ExitCode -eq 0 -or $auditStderr.Result -notmatch 'atomic publication failed') {
    throw "Atomic endpoint collision not rejected: $($auditStdout.Result) $($auditStderr.Result)"
  }
  if ((Get-ChildItem -LiteralPath $auditOutside -Force).Count -ne 0) { throw 'Atomic publication followed endpoint junction' }
  if (((Get-Item -LiteralPath $auditLink -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0) { throw 'Collision entry was replaced' }
  [IO.Directory]::Delete($auditLink)
  if (Compare-Object $auditBefore (Get-AudioTree $auditStage)) { throw 'Failed atomic publication left changed bytes/temporary files' }
  $auditLock = [IO.File]::Open("$BuildDir/install-operation.lock",[IO.FileMode]::Open,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
  $auditLock.Dispose()
  $auditOutput = & $auditCmake --install $BuildDir --prefix $auditStage --component runtime 2>&1
  if ($LASTEXITCODE -ne 0) { throw "Post-failure teardown retry failed: $auditOutput" }
} finally {
  $auditRelease.Set() | Out-Null
  if (-not $auditProcess.HasExited) { $auditProcess.Kill(); $auditProcess.WaitForExit() }
  $auditProcess.Dispose(); $auditReady.Dispose(); $auditRelease.Dispose()
}
# Conventional all-components entry point and idempotent repetition retain
# the same two disjoint manifests, without CMake writing after the guard exits.
$auditStage = "$auditWork/all-components"
New-Item -ItemType Directory -Path $auditStage | Out-Null
Copy-Item -Path "$PurePrefix/*" -Destination $auditStage -Recurse
$auditOutput = & $auditCmake --install $BuildDir --prefix $auditStage 2>&1
if ($LASTEXITCODE -ne 0) { throw "All-components installation failed: $auditOutput" }
$auditBefore = Get-AudioTree $auditStage
$auditOutput = & $auditCmake --install $BuildDir --prefix $auditStage 2>&1
if ($LASTEXITCODE -ne 0 -or (Compare-Object $auditBefore (Get-AudioTree $auditStage))) { throw 'Idempotent all-components install changed bytes' }
$auditOutput = & $auditCmake "-DAUDIO_INSTALL_CONTEXT=$BuildDir/windows-install-context.cmake" "-DSTAGE_PREFIX=$auditStage" -P "$SourceDir/cmake/VerifyInstalledPackage.cmake" 2>&1
if ($LASTEXITCODE -ne 0 -or "$auditOutput" -notmatch 'PURE_AUDIO_DONE_[a-f0-9]+') { throw "All-components pristine smoke failed: $auditOutput" }
$auditLock = [IO.File]::Open("$BuildDir/install-operation.lock",[IO.FileMode]::Open,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
try {
  $ErrorActionPreference = 'Continue'
  $auditOutput = & $auditCmake --install $BuildDir --prefix $auditStage --component runtime 2>&1
  $auditRc = $LASTEXITCODE
} finally { $ErrorActionPreference = 'Stop'; $auditLock.Dispose() }
if ($auditRc -eq 0 -or (Compare-Object $auditBefore (Get-AudioTree $auditStage))) { throw 'Actual installer ignored held operation lock' }
'INSTALL_GUARD_CONTRACT_OK negatives=7 controls=8 pristine=2 concurrent_installers=3 outside_writes=0 teardown=2'
& $auditRunner --cleanup --cwd $auditWork
if ($LASTEXITCODE -ne 0) { throw 'Owned cleanup failed after guard teardown' }
