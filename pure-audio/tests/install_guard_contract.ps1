param([Parameter(Mandatory=$true)][string]$SourceDir,
      [Parameter(Mandatory=$true)][string]$BuildDir,
      [Parameter(Mandatory=$true)][string]$PurePrefix,
      [switch]$LockRedOnly, [switch]$SwapRedOnly,
      [switch]$CounterfeitOnly, [string]$PristineStage,
      [switch]$LateCollisionOnly, [switch]$WriteFailureOnly,
      [switch]$ReservedRaceOnly, [switch]$ScopeOnly, [switch]$ManifestCollisionOnly,
      [switch]$MetadataFailureOnly)
$ErrorActionPreference = 'Stop'
$auditCmake = 'C:/msys64/clang64/bin/cmake.exe'
$auditRunner = "$BuildDir/run_pure_test.exe"
$auditWork = (& $auditRunner --create-leaf).Trim()
if ($LASTEXITCODE -ne 0 -or -not $auditWork) { throw 'Cannot create native-owned fixture leaf' }
$auditStage = "$auditWork/stage"
New-Item -ItemType Directory -Path $auditStage | Out-Null
Copy-Item -Path "$PurePrefix/*" -Destination $auditStage -Recurse
if ($CounterfeitOnly) {
  if (-not (Test-Path -LiteralPath "$PristineStage/share/doc/pure-audio/licenses" -PathType Container)) { throw 'Real installed pristine stage required' }
  $auditFakeName = 'pure-audio-install-counterfeit-' + [Guid]::NewGuid().ToString('N')
  $auditFakeReadyName = 'Local\audio-counterfeit-' + [Guid]::NewGuid().ToString('N')
  $auditFakeReady = New-Object Threading.EventWaitHandle($false, [Threading.EventResetMode]::ManualReset, $auditFakeReadyName)
  $auditFakeScript = @'
param([string]$PipeName,[string]$ReadyName)
$ErrorActionPreference='Stop'
$pipe=New-Object IO.Pipes.NamedPipeServerStream($PipeName,[IO.Pipes.PipeDirection]::InOut,1,[IO.Pipes.PipeTransmissionMode]::Message,[IO.Pipes.PipeOptions]::None,131072,131072)
$ready=[Threading.EventWaitHandle]::OpenExisting($ReadyName)
$ready.Set() | Out-Null
$ready.Dispose()
while($true) {
  $pipe.WaitForConnection()
  $buffer=New-Object byte[] 131072
  try { $n=$pipe.Read($buffer,0,$buffer.Length); if($n -gt 0) { $answer=[BitConverter]::GetBytes([uint32]0x41554449); $pipe.Write($answer,0,4); $pipe.Flush() } } catch {}
  $pipe.Disconnect()
}
'@
  [IO.File]::WriteAllText("$auditWork/counterfeit.ps1", $auditFakeScript)
  $auditFakeStart=New-Object Diagnostics.ProcessStartInfo
  $auditFakeStart.FileName='C:/Windows/System32/WindowsPowerShell/v1.0/powershell.exe'
  $auditFakeStart.Arguments="-NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$auditWork/counterfeit.ps1`" -PipeName $auditFakeName -ReadyName $auditFakeReadyName"
  $auditFakeStart.UseShellExecute=$false
  $auditFakeStart.CreateNoWindow=$true
  $auditFake=[Diagnostics.Process]::Start($auditFakeStart)
  try {
    if(-not $auditFakeReady.WaitOne(10000)) { throw 'Counterfeit server did not become ready' }
    $env:PURE_AUDIO_INSTALL_CHANNEL='\\.\pipe\'+$auditFakeName
    $ErrorActionPreference='Continue'
    $auditOutput=& $auditCmake "-DAUDIO_INSTALL_CONTEXT=$BuildDir/windows-install-context.cmake" "-DSTAGE_PREFIX=$PristineStage" -P "$SourceDir/cmake/VerifyInstalledPackage.cmake" 2>&1
    $auditRc=$LASTEXITCODE
    $ErrorActionPreference='Stop'
    [IO.File]::WriteAllText("$auditWork/counterfeit-verifier.log",($auditOutput -join "`n"))
    if($auditRc -eq 0) { throw "RED: live counterfeit magic server bypassed real guard ownership ($auditWork)" }
    if("$auditOutput" -notmatch 'server identity|guard ancestry') { throw "Counterfeit rejected for unrelated reason: $auditOutput" }
  } finally {
    $ErrorActionPreference='Stop'
    Remove-Item Env:PURE_AUDIO_INSTALL_CHANNEL -ErrorAction SilentlyContinue
    if(-not $auditFake.HasExited) { $auditFake.Kill(); $auditFake.WaitForExit() }
    $auditFake.Dispose(); $auditFakeReady.Dispose()
  }
  'COUNTERFEIT_GUARD_OK negatives=1 live_magic_server=1'
  & $auditRunner --cleanup --cwd $auditWork
  if($LASTEXITCODE -ne 0) { throw 'Counterfeit owned cleanup failed' }
  exit 0
}
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
# Use a private configured profile pinned to the fixture executable itself.
# Production clients never accept a differently named/image fixture server.
$auditConfiguredBuild=$BuildDir
$auditFixtureBuild="$auditWork/guard-build"
New-Item -ItemType Directory -Path $auditFixtureBuild | Out-Null
Copy-Item -LiteralPath "$BuildDir/install_guard_fixture.exe" -Destination "$auditFixtureBuild/install_guard.exe"
Copy-Item -LiteralPath "$BuildDir/install_guard_fixture.exe" -Destination "$auditFixtureBuild/install_guard_fixture.exe"
Copy-Item -LiteralPath $auditRunner -Destination "$auditFixtureBuild/run_pure_test.exe"
foreach($auditModule in @('audio.dll','fftw.dll','srcprocess.dll','sfinfo.dll','realtime.dll')) {
  Copy-Item -LiteralPath "$BuildDir/$auditModule" -Destination "$auditFixtureBuild/$auditModule"
}
$auditFixtureContext=[IO.File]::ReadAllText("$BuildDir/windows-install-context.cmake").Replace("set(AUDIO_INSTALL_BUILD_DIR [==[$BuildDir]==])","set(AUDIO_INSTALL_BUILD_DIR [==[$auditFixtureBuild]==])").Replace("set(AUDIO_INSTALL_GUARD [==[$BuildDir/install_guard.exe]==])","set(AUDIO_INSTALL_GUARD [==[$auditFixtureBuild/install_guard.exe]==])")
[IO.File]::WriteAllText("$auditFixtureBuild/windows-install-context.cmake",$auditFixtureContext)
[IO.File]::WriteAllText("$auditFixtureBuild/cmake_install.cmake",[IO.File]::ReadAllText("$BuildDir/cmake_install.cmake").Replace("$BuildDir/windows-install-context.cmake","$auditFixtureBuild/windows-install-context.cmake"))
$auditHasher=[Security.Cryptography.SHA256]::Create()
$auditInput=[IO.File]::OpenRead("$auditFixtureBuild/install_guard.exe")
try { $auditFixtureHash=[BitConverter]::ToString($auditHasher.ComputeHash($auditInput)).Replace('-','').ToLowerInvariant() }
finally { $auditHasher.Dispose(); $auditInput.Dispose() }
[IO.File]::WriteAllText("$auditFixtureBuild/install-guard.sha256",$auditFixtureHash+"`n")
$BuildDir=$auditFixtureBuild

if($MetadataFailureOnly) {
  foreach($auditFailureIndex in @(23,24)) {
    $auditStage="$auditWork/metadata-$auditFailureIndex"
    New-Item -ItemType Directory -Path $auditStage | Out-Null
    Copy-Item -Path "$PurePrefix/*" -Destination $auditStage -Recurse
    $auditBefore=Get-AudioTree $auditStage
    $auditPrevious="PREVIOUS COMPONENT MANIFEST`n"
    [IO.File]::WriteAllText("$BuildDir/install_manifest_runtime.txt",$auditPrevious)
    try {
      $env:AUDIO_GUARD_TEST_FAIL_AFTER_WRITE=[string]$auditFailureIndex
      $ErrorActionPreference='Continue'
      $auditOutput=& $auditCmake --install $BuildDir --prefix $auditStage --component runtime 2>&1
      $auditRc=$LASTEXITCODE
    } finally { $ErrorActionPreference='Stop'; Remove-Item Env:AUDIO_GUARD_TEST_FAIL_AFTER_WRITE -ErrorAction SilentlyContinue }
    [IO.File]::WriteAllText("$auditWork/metadata-$auditFailureIndex.log",($auditOutput -join "`n"))
    if($auditRc -eq 0) { throw "RED: final metadata write is outside rollback batch ($auditWork)" }
    if("$auditOutput" -notmatch 'injected pre-commit write failure') { throw "Wrong metadata failure: $auditOutput" }
    if((Compare-Object $auditBefore (Get-AudioTree $auditStage)) -or
       [IO.File]::ReadAllText("$BuildDir/install_manifest_runtime.txt") -cne $auditPrevious) { throw 'Metadata rollback failed to restore exact bytes' }
    $auditOutput=& $auditCmake --install $BuildDir --prefix $auditStage --component runtime 2>&1
    if($LASTEXITCODE -ne 0) { throw "Metadata retry failed: $auditOutput" }
  }
  'METADATA_FAILURE_ROLLBACK_OK negatives=2 retries=2 after_records=23,24 previous_manifest_restored=1'
  & $auditRunner --cleanup --cwd $auditWork
  if($LASTEXITCODE -ne 0) { throw 'Metadata rollback cleanup failed' }
  exit 0
}
if($ManifestCollisionOnly) {
  $auditBefore=Get-AudioTree $auditStage
  $auditLock=[IO.File]::Open("$BuildDir/install_manifest_runtime.txt",[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
  try {
    $ErrorActionPreference='Continue'
    $auditOutput=& $auditCmake --install $BuildDir --prefix $auditStage --component runtime 2>&1
    $auditRc=$LASTEXITCODE
  } finally { $ErrorActionPreference='Stop'; $auditLock.Dispose() }
  [IO.File]::WriteAllText("$auditWork/manifest-collision.log",($auditOutput -join "`n"))
  if($auditRc -eq 0) { throw 'Locked final manifest was accepted' }
  if(Compare-Object $auditBefore (Get-AudioTree $auditStage)) { throw "RED: final manifest collision left prefix files installed ($auditWork)" }
  $auditOutput=& $auditCmake --install $BuildDir --prefix $auditStage --component runtime 2>&1
  if($LASTEXITCODE -ne 0) { throw "Manifest-collision retry failed: $auditOutput" }
  'MANIFEST_COLLISION_ROLLBACK_OK negatives=1 retries=1 prefix_unchanged=1'
  & $auditRunner --cleanup --cwd $auditWork
  if($LASTEXITCODE -ne 0) { throw 'Manifest collision cleanup failed' }
  exit 0
}
if($ScopeOnly) {
  $auditOtherStage="$auditWork/other-scope"
  New-Item -ItemType Directory -Path $auditOtherStage | Out-Null
  Copy-Item -Path "$PurePrefix/*" -Destination $auditOtherStage -Recurse
  $auditBefore=Get-AudioTree $auditStage
  $auditOtherBefore=Get-AudioTree $auditOtherStage
  foreach($auditMutation in @('stage','capability')) {
    if($auditMutation -eq 'stage') { $auditPrelude="set(STAGE_PREFIX [==[$auditOtherStage]==])`n" }
    else { $auditPrelude='set(ENV{PURE_AUDIO_INSTALL_CAPABILITY} '+('0'*64)+")`n" }
    [IO.File]::WriteAllText("$auditWork/scope-$auditMutation.cmake",$auditPrelude+"include([==[$SourceDir/cmake/VerifyInstalledPackage.cmake]==])`n")
    $ErrorActionPreference='Continue'
    $auditOutput=& "$BuildDir/install_guard.exe" --run $auditStage $BuildDir $auditCmake "$BuildDir/windows-install-context.cmake" "$auditWork/scope-$auditMutation.cmake" verify all 2>&1
    $auditRc=$LASTEXITCODE
    $ErrorActionPreference='Stop'
    if($auditRc -eq 0 -or "$auditOutput" -notmatch 'stage identity/capability mismatch' -or
       (Compare-Object $auditBefore (Get-AudioTree $auditStage)) -or
       (Compare-Object $auditOtherBefore (Get-AudioTree $auditOtherStage))) { throw "Scope authentication failed: $auditOutput" }
  }
  'GUARD_SCOPE_OK negatives=2 stage_and_capability=1'
  & $auditRunner --cleanup --cwd $auditWork
  if($LASTEXITCODE -ne 0) { throw 'Scope cleanup failed' }
  exit 0
}
if($LateCollisionOnly -or $WriteFailureOnly -or $ReservedRaceOnly) {
  $auditCase=0
  $auditDestinations=@('bin/libFLAC.dll','lib/pure/audio.dll','lib/pure/srcprocess.dll')
  $auditCases=$auditDestinations
  if($ReservedRaceOnly) { $auditCases=@('all-reserved') }
  foreach($auditDestination in $auditCases) {
    $auditCase++
    $auditStage="$auditWork/collision-$auditCase"
    New-Item -ItemType Directory -Path $auditStage | Out-Null
    Copy-Item -Path "$PurePrefix/*" -Destination $auditStage -Recurse
    $auditBefore=Get-AudioTree $auditStage
    $auditOutside="$auditWork/outside-$auditCase"
    New-Item -ItemType Directory -Path $auditOutside | Out-Null
    $auditReadyName='Local\audio-late-ready-'+[Guid]::NewGuid().ToString('N')
    $auditReleaseName='Local\audio-late-release-'+[Guid]::NewGuid().ToString('N')
    $auditReady=New-Object Threading.EventWaitHandle($false,[Threading.EventResetMode]::ManualReset,$auditReadyName)
    $auditRelease=New-Object Threading.EventWaitHandle($false,[Threading.EventResetMode]::ManualReset,$auditReleaseName)
    $auditStart=New-Object Diagnostics.ProcessStartInfo
    $auditStart.FileName="$BuildDir/install_guard.exe"
    $auditArguments=@('--run',$auditStage,$BuildDir,$auditCmake,"$BuildDir/windows-install-context.cmake","$SourceDir/cmake/VerifyInstalledPackage.cmake",'install','runtime')
    $auditStart.Arguments=($auditArguments | ForEach-Object { '"'+$_+'"' }) -join ' '
    $auditStart.UseShellExecute=$false; $auditStart.CreateNoWindow=$true
    $auditStart.RedirectStandardOutput=$true; $auditStart.RedirectStandardError=$true
    $auditStart.EnvironmentVariables['AUDIO_GUARD_TEST_READY']=$auditReadyName
    $auditStart.EnvironmentVariables['AUDIO_GUARD_TEST_RELEASE']=$auditReleaseName
    if($WriteFailureOnly -or $ReservedRaceOnly) {
      $auditStart.EnvironmentVariables['AUDIO_GUARD_TEST_PHASE']='reserved'
      $auditFailureIndex=@(1,12,22)[$auditCase-1]
      if($ReservedRaceOnly) { $auditFailureIndex=12 }
      $auditStart.EnvironmentVariables['AUDIO_GUARD_TEST_FAIL_AFTER_WRITE']=[string]$auditFailureIndex
    }
    $auditProcess=[Diagnostics.Process]::Start($auditStart)
    $auditStdout=$auditProcess.StandardOutput.ReadToEndAsync(); $auditStderr=$auditProcess.StandardError.ReadToEndAsync()
    try {
      if(-not $auditReady.WaitOne(25000)) { throw "Late collision gate not reached ($auditWork)" }
      if($LateCollisionOnly) {
        $auditLink="$auditStage/$auditDestination"
        New-Item -ItemType Junction -Path $auditLink -Target $auditOutside | Out-Null
      }
      if($ReservedRaceOnly) {
        foreach($auditReserved in $auditDestinations) {
          $auditBlocked=$false
          try { $auditUnwanted=[IO.File]::Open("$auditStage/$auditReserved",[IO.FileMode]::CreateNew,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None); $auditUnwanted.Dispose() }
          catch [IO.IOException] { $auditBlocked=$true }
          if(-not $auditBlocked) { throw 'Reserved name admitted concurrent creation' }
          & "$BuildDir/install_guard.exe" --test-directory-write "$auditStage/$auditReserved"
          if($LASTEXITCODE -ne 0) { throw 'Reserved endpoint admitted reparse/write access' }
        }
      }
      $auditRelease.Set() | Out-Null
      if(-not $auditProcess.WaitForExit(90000)) { throw 'Late collision install did not finish' }
      [IO.File]::WriteAllText("$auditWork/collision-$auditCase.log",$auditStdout.Result+$auditStderr.Result)
      if($auditProcess.ExitCode -eq 0) { throw 'Expected pre-commit failure was accepted' }
      if(($WriteFailureOnly -or $ReservedRaceOnly) -and $auditStderr.Result -notmatch 'injected pre-commit write failure') { throw "Wrong failure cause: $($auditStderr.Result)" }
      if(@(Get-ChildItem -LiteralPath $auditOutside -Force).Count) { throw 'Late collision wrote outside stage' }
      if($LateCollisionOnly) {
        if(((Get-Item -LiteralPath $auditLink -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0) { throw 'Concurrent collision entry was overwritten' }
        # Remove only our test-created junction, never the other actor's files.
        [IO.Directory]::Delete($auditLink)
      }
      if(Compare-Object $auditBefore (Get-AudioTree $auditStage)) { throw "RED: collision at $auditDestination left a partial installation ($auditWork)" }
      $auditOutput=& $auditCmake --install $BuildDir --prefix $auditStage --component runtime 2>&1
      if($LASTEXITCODE -ne 0) { throw "Post-rollback retry failed: $auditOutput" }
    } finally {
      $auditRelease.Set() | Out-Null
      if(-not $auditProcess.HasExited) { $auditProcess.Kill(); $auditProcess.WaitForExit() }
      $auditProcess.Dispose(); $auditReady.Dispose(); $auditRelease.Dispose()
    }
  }
  if($LateCollisionOnly) { 'LATE_COLLISION_ROLLBACK_OK negatives=3 retries=3 positions=early,middle,last outside_writes=0' }
  elseif($WriteFailureOnly) { 'WRITE_FAILURE_ROLLBACK_OK negatives=3 retries=3 after_payloads=1,12,22' }
  else { 'RESERVED_RACE_ROLLBACK_OK negatives=7 retries=1 creation=3 reparse_write=3 rollback=1 outside_writes=0' }
  & $auditRunner --cleanup --cwd $auditWork
  if($LASTEXITCODE -ne 0) { throw 'Late collision cleanup failed' }
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
$auditStart.FileName = "$BuildDir/install_guard.exe"
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
foreach($auditControl in @('CounterfeitOnly','ScopeOnly','LateCollisionOnly','WriteFailureOnly','ReservedRaceOnly','ManifestCollisionOnly','MetadataFailureOnly')) {
  # Each recursive control gets a fresh sibling leaf from the original runner,
  # rather than nesting test roots until Win32's legacy path limit is exceeded.
  $auditControlBuild=$auditConfiguredBuild
  if($auditControl -eq 'CounterfeitOnly') { $auditControlBuild=$BuildDir }
  $auditOutput=& C:/Windows/System32/WindowsPowerShell/v1.0/powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $PSCommandPath -SourceDir $SourceDir -BuildDir $auditControlBuild -PurePrefix $PurePrefix "-$auditControl" -PristineStage $auditStage 2>&1
  if($LASTEXITCODE -ne 0) { throw "Extended guard control $auditControl failed: $auditOutput" }
  [IO.File]::WriteAllText("$auditWork/$auditControl.log",($auditOutput -join "`n"))
  $auditOutput
}
'INSTALL_GUARD_CONTRACT_OK negatives=26 controls=18 pristine=2 concurrent_installers=3 outside_writes=0 teardown=2 precommit_rollback_cases=10 retries=10'
& $auditRunner --cleanup --cwd $auditWork
if ($LASTEXITCODE -ne 0) { throw 'Owned cleanup failed after guard teardown' }
