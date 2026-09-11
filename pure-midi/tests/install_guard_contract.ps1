param([Parameter(Mandatory=$true)][string]$SourceDir,
      [Parameter(Mandatory=$true)][string]$BuildDir,
      [Parameter(Mandatory=$true)][string]$PurePrefix,
      [Parameter(Mandatory=$true)][string]$Runner,
      [ValidateSet('component','guard')][string]$Suite='guard', [switch]$RedOnly,
      [switch]$IdentityRedOnly)
$ErrorActionPreference='Stop'
$cmake='C:/msys64/clang64/bin/cmake.exe'
$BuildDir=$BuildDir.Replace('\','/'); $SourceDir=$SourceDir.Replace('\','/')
$reservation=(& $Runner --owned-create) -join "`n"
if($LASTEXITCODE -ne 0 -or $reservation -notmatch 'leaf=([^\r\n]+)[\r\n]+nonce=([a-f0-9]+)') { throw 'Cannot reserve owned install test leaf' }
$work=$Matches[1].Replace('\','/'); $owner=$Matches[2]
"INSTALL_CONTRACT_WORK=$work"
$negative=0; $positive=0
function Hash([string]$Path) {
  $h=[Security.Cryptography.SHA256]::Create(); $f=[IO.File]::OpenRead($Path)
  try { return [BitConverter]::ToString($h.ComputeHash($f)).Replace('-','').ToLowerInvariant() }
  finally { $f.Dispose(); $h.Dispose() }
}
function Tree([string]$Root) {
  @(Get-ChildItem -LiteralPath $Root -Recurse -Force | ForEach-Object {
    $rel=$_.FullName.Substring($Root.Length+1).Replace('\','/')
    if($_.PSIsContainer) { "$rel|d|0|-" }
    else { "$rel|f|$($_.Length)|$(Hash $_.FullName)" }
  } | Sort-Object -CaseSensitive)
}
function Fresh([string]$Name) {
  $p="$work/$Name"; New-Item -ItemType Directory -Path $p | Out-Null
  Copy-Item -Path "$PurePrefix/*" -Destination $p -Recurse
  return $p
}
function Run([string]$Name,[bool]$Good,[string[]]$Arguments,[string]$Reason='') {
  $ErrorActionPreference='Continue'
  $out=& $cmake @Arguments 2>&1; $rc=$LASTEXITCODE
  $ErrorActionPreference='Stop'
  [IO.File]::WriteAllText("$work/$Name.log",($out -join "`n"))
  if(($Good -and $rc -ne 0) -or (-not $Good -and $rc -eq 0) -or ($Reason -and "$out" -notmatch $Reason)) {
    throw "RED: $Name expected success=$Good, exit=$rc reason=$Reason ($work): $out"
  }
  if($Good) { $script:positive++ } else { $script:negative++ }
  "INSTALL_CASE_OK $Name exit=$rc" | Write-Host
  return ($out -join "`n")
}
function InstallArgs([string]$Stage,[string]$Component) { @('--install',$BuildDir,'--prefix',$Stage,'--component',$Component) }
function VerifyArgs([string]$Stage,[string]$Context="$BuildDir/windows-install-context.cmake") {
  @("-DMIDI_INSTALL_CONTEXT=$Context","-DSTAGE_PREFIX=$Stage",'-P',"$SourceDir/cmake/VerifyInstalledPackage.cmake")
}
function Same([object[]]$Before,[string]$Stage) {
  if(Compare-Object $Before (Tree $Stage)) { throw "Changed tree on failed operation: $Stage" }
}
function Clean {
  & $Runner --owned-clean --cwd $work --token $owner
  if($LASTEXITCODE -ne 0) { throw "Owned cleanup failed: $work" }
}
if($RedOnly) {
  $stage=Fresh 'red'
  $before=Tree $stage
  if($Suite -eq 'component') {
    [IO.File]::WriteAllText("$stage/lib/pure/midi.pure","KEEP COLLISION`n")
    $before=Tree $stage
    Run collision $false (InstallArgs $stage runtime) | Out-Null
  } else {
    # The held build operation file must serialize the actual CMake installer.
    $lock=[IO.File]::Open("$BuildDir/install-operation.lock",[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
    try { Run locked-installer $false (InstallArgs $stage runtime) | Out-Null } finally { $lock.Dispose() }
  }
  Same $before $stage; Clean; exit 0
}
if($Suite -eq 'component') {
  if((Hash "$BuildDir/windows-install-inventory.tsv") -cne [IO.File]::ReadAllText("$BuildDir/windows-install-inventory.tsv.sha256").Trim()) { throw 'RED: inventory seal is not the SHA-256 of its actual bytes' }
  # Independent package declaration, including own COPYING and the full local license.
  $runtime=@('bin/libportmidi.dll','lib/pure/midi.pure','lib/pure/midifile.dll','lib/pure/midifile.pure','lib/pure/pmlib.dll','lib/pure/portmidi.pure')
  $docs=@('COPYING','README','THIRD_PARTY.md','WINDOWS.md','examples/midi_examp.pure','examples/prelude3.mid','licenses/PortMidi.txt','licenses/origins.tsv','tests/device-timing.pure','tests/hardware-output.pure','tests/smoke.pure') | ForEach-Object { "share/doc/pure-midi/$_" }
  foreach($case in @('collision','identical-collision','changed-baseline','extra-baseline','empty-extra-directory','ancestor-file')) {
    $stage=Fresh $case
    switch($case) {
      collision { [IO.File]::WriteAllText("$stage/lib/pure/midi.pure",'COLLISION') }
      identical-collision { Copy-Item -LiteralPath "$SourceDir/midi.pure" -Destination "$stage/lib/pure/midi.pure" }
      changed-baseline { [IO.File]::AppendAllText("$stage/lib/pure/prelude.pure",'CHANGED') }
      extra-baseline { [IO.File]::WriteAllText("$stage/extra",'EXTRA') }
      empty-extra-directory { New-Item -ItemType Directory -Path "$stage/extra" | Out-Null }
      ancestor-file { [IO.File]::WriteAllText("$stage/share/doc",'FILE') }
    }
    $before=Tree $stage
    Run $case $false (InstallArgs $stage runtime) | Out-Null
    Same $before $stage
  }
  $stage=Fresh 'pristine'; $baseline=Tree $stage
  Run runtime $true (InstallArgs $stage runtime) | Out-Null
  $after=Tree $stage
  $newFiles=@(Get-ChildItem -LiteralPath $stage -Recurse -File | ForEach-Object { $_.FullName.Substring($stage.Length+1).Replace('\','/') } | Where-Object { $_ -in $runtime })
  if($newFiles.Count -ne 6 -or @(Get-ChildItem -LiteralPath "$stage/share" -Recurse -File).Count -ne 1) { throw 'Runtime component ownership mismatch' }
  Run documentation $true (InstallArgs $stage documentation) | Out-Null
  $all=Tree $stage
  if($all.Count -ne $baseline.Count+22) { throw "Expected 17 files + 5 directories, got delta $($all.Count-$baseline.Count)" }
  foreach($component in @('runtime','documentation')) {
    $want=if($component -eq 'runtime') { $runtime } else { $docs }
    $manifest=@([IO.File]::ReadAllLines("$BuildDir/install_manifest_$component.txt") | ForEach-Object { $_.Substring($stage.Length+1) })
    if(Compare-Object $want $manifest) { throw "$component manifest mismatch" }
  }
  $verified=Run pristine $true (VerifyArgs $stage) 'INSTALL_PACKAGE_OK.*runtime=6.*documentation=11.*pe=16'
  if($verified -notmatch 'installed_tests=2') { throw 'Installed public tests did not execute' }
  Run idempotent $true (InstallArgs $stage runtime) | Out-Null; Same $all $stage
  # Full-tree mutations each keep all unrelated inputs intact.
  foreach($relative in @('lib/pure/prelude.pure','lib/pure/pmlib.dll','lib/pure/portmidi.pure','bin/libportmidi.dll','share/doc/pure-midi/licenses/PortMidi.txt','share/doc/pure-midi/licenses/origins.tsv','share/doc/pure-midi/tests/smoke.pure')) {
    $saved=[IO.File]::ReadAllBytes("$stage/$relative")
    try { [IO.File]::AppendAllText("$stage/$relative",'CHANGED'); Run ('changed-'+($relative -replace '/','_')) $false (VerifyArgs $stage) | Out-Null }
    finally { [IO.File]::WriteAllBytes("$stage/$relative",$saved) }
  }
  foreach($kind in @('extra-file','extra-directory','missing-file')) {
    switch($kind) {
      extra-file { [IO.File]::WriteAllText("$stage/extra",'EXTRA') }
      extra-directory { New-Item -ItemType Directory -Path "$stage/extra" | Out-Null }
      missing-file { [IO.File]::Move("$stage/lib/pure/midi.pure","$work/midi.saved") }
    }
    try { Run $kind $false (VerifyArgs $stage) | Out-Null }
    finally {
      if($kind -eq 'extra-file') { [IO.File]::Delete("$stage/extra") }
      elseif($kind -eq 'extra-directory') { [IO.Directory]::Delete("$stage/extra") }
      else { [IO.File]::Move("$work/midi.saved","$stage/lib/pure/midi.pure") }
    }
  }
  # Session manifests are data; every component and baseline is checked exactly.
  $hash=[Security.Cryptography.SHA256]::Create()
  try { $key=[BitConverter]::ToString($hash.ComputeHash([Text.Encoding]::UTF8.GetBytes($stage.ToLowerInvariant()))).Replace('-','').ToLowerInvariant() } finally { $hash.Dispose() }
  $session="$BuildDir/install-audits/$key"
  foreach($kind in @('missing','extra','cross','duplicate','unsorted','changed-baseline','missing-manifest')) {
    $p=if($kind -eq 'changed-baseline') { "$session/baseline.tsv" } else { "$session/runtime.tsv" }
    $saved=[IO.File]::ReadAllBytes($p); $lines=[IO.File]::ReadAllLines($p)
    try {
      switch($kind) {
        missing { [IO.File]::WriteAllText($p,($lines[1..($lines.Count-1)] -join "`n")+"`n") }
        extra { [IO.File]::AppendAllText($p,"extra|f|0|"+('0'*64)+"`n") }
        cross { [IO.File]::AppendAllText($p,[IO.File]::ReadAllLines("$session/documentation.tsv")[0]+"`n") }
        duplicate { [IO.File]::AppendAllText($p,$lines[0]+"`n") }
        unsorted { [array]::Reverse($lines); [IO.File]::WriteAllText($p,($lines -join "`n")+"`n") }
        changed-baseline { [IO.File]::AppendAllText($p,'CHANGED') }
        missing-manifest { [IO.File]::Delete($p) }
      }
      Run "manifest-$kind" $false (VerifyArgs $stage) | Out-Null
    } finally { [IO.File]::WriteAllBytes($p,$saved) }
  }
  # All mutations to configured input paths use owned copies of context/data.
  $context=[IO.File]::ReadAllText("$BuildDir/windows-install-context.cmake")
  foreach($kind in @('source-hash','runtime-origin','runtime-hash','license-mapping','license-url','license-hash','inventory-extra')) {
    $text=$context
    switch($kind) {
      source-hash {
        Copy-Item -LiteralPath "$SourceDir/midi.pure" -Destination "$work/midi.pure"
        [IO.File]::AppendAllText("$work/midi.pure",'CHANGED')
        $text=$text.Replace("$SourceDir/midi.pure","$work/midi.pure")
      }
      runtime-origin { Copy-Item -LiteralPath 'C:/msys64/clang64/bin/libportmidi.dll' -Destination "$work/libportmidi.dll"; $text=$text.Replace('C:/msys64/clang64/bin/libportmidi.dll',"$work/libportmidi.dll") }
      runtime-hash { $text=$text.Replace('99454395751bfad786db9c457b93db62f31f7d68dc2bebb2281f33289d43cb49',('0'*64)) }
      license-mapping { $text=$text.Replace('|share/doc/pure-midi/licenses/PortMidi.txt','|share/doc/pure-midi/COPYING') }
      license-url { $text=$text.Replace('https://github.com/PortMidi/portmidi','https://invalid.example/portmidi') }
      license-hash { $text=$text.Replace('8d187c40c782da0e24489c4c4bf7590635e072dc0b70b0afda7b0652d290c1ea',('0'*64)) }
      inventory-extra { $p="$work/inventory.tsv"; [IO.File]::WriteAllText($p,[IO.File]::ReadAllText("$BuildDir/windows-install-inventory.tsv")+'extra'); Copy-Item -LiteralPath "$BuildDir/windows-install-inventory.tsv.sha256" -Destination "$p.sha256"; $text=$text.Replace("$BuildDir/windows-install-inventory.tsv",$p) }
    }
    if($text -ceq $context) { throw "Invalid unchanged mutation $kind" }
    [IO.File]::WriteAllText("$work/context.cmake",$text)
    Run $kind $false (VerifyArgs $stage "$work/context.cmake") | Out-Null
  }
  # Real Task4 runner, direct installed paths, deliberately poisoned parent.
  # Removing a transitive DLL while host PATH/Pure settings point at a valid
  # installation must fail (the verifier also rejects the altered baseline).
  $savedPath=$env:PATH; $savedPure=$env:PURELIB
  try {
    $env:PATH="$PurePrefix/bin;C:/msys64/clang64/bin;$savedPath"; $env:PURELIB="$PurePrefix/lib/pure"
    [IO.File]::Move("$stage/bin/libgmp-10.dll","$work/gmp.saved")
    Run host-rescue-verifier $false (VerifyArgs $stage) | Out-Null
    $token=(& $Runner --nonce).Trim()
    $ErrorActionPreference='Continue'
    $out=& $Runner --pure "$stage/bin/pure.exe" --script "$stage/share/doc/pure-midi/tests/smoke.pure" --token $token --timeout-ms 10000 --cwd "$BuildDir/pure-midi-contract-root" --include "$stage/lib/pure" --library "$stage/lib/pure" --path-entry "$stage/bin" --path-entry "$stage/lib/pure" --fixture "$stage/share/doc/pure-midi/examples/prelude3.mid" 2>&1
    $rc=$LASTEXITCODE; $ErrorActionPreference='Stop'
    [IO.File]::WriteAllText("$work/host-rescue-runner.log",($out -join "`n")+"`nexit=$rc`n")
    if($rc -eq 0) { throw 'Installed smoke rescued by host' }; $negative++
  } finally { [IO.File]::Move("$work/gmp.saved","$stage/bin/libgmp-10.dll"); $env:PATH=$savedPath; $env:PURELIB=$savedPure }
  Run restored-pristine $true (VerifyArgs $stage) 'PE_CLOSURE_OK count=16' | Out-Null
  "INSTALL_COMPONENT_CONTRACT_OK negative=$negative positive=$positive baseline=$($baseline.Count) runtime=6 documentation=11 delta_files=17 delta_directories=5 final=$($all.Count)"
  Clean; exit 0
}
# Guard failures must happen before payload publication and restore exact trees.
# The fixture executable is the production source with observation/failure gates
# compiled only into this test target. It is never an installed artifact.
$configuredBuild=$BuildDir
$fixtureBuild="$work/build"; New-Item -ItemType Directory -Path $fixtureBuild | Out-Null
foreach($name in @('pmlib.dll','midifile.dll','README','windows-install-inventory.tsv','windows-install-context.cmake')) {
  Copy-Item -LiteralPath "$BuildDir/$name" -Destination "$fixtureBuild/$name"
}
Copy-Item -LiteralPath "$BuildDir/install_guard_fixture.exe" -Destination "$fixtureBuild/install_guard.exe"
$fixtureContext=[IO.File]::ReadAllText("$fixtureBuild/windows-install-context.cmake").Replace($BuildDir,$fixtureBuild)
$fixtureContext=$fixtureContext.Replace("$fixtureBuild/run_pure_test.exe","$configuredBuild/run_pure_test.exe").Replace("$fixtureBuild/pure-midi-contract-root","$configuredBuild/pure-midi-contract-root")
[IO.File]::WriteAllText("$fixtureBuild/windows-install-context.cmake",$fixtureContext)
$inv=[IO.File]::ReadAllText("$fixtureBuild/windows-install-inventory.tsv").Replace($BuildDir,$fixtureBuild).Replace("`r`n","`n")
[IO.File]::WriteAllText("$fixtureBuild/windows-install-inventory.tsv",$inv)
[IO.File]::WriteAllText("$fixtureBuild/windows-install-inventory.tsv.sha256",(Hash "$fixtureBuild/windows-install-inventory.tsv")+"`n")
[IO.File]::WriteAllText("$fixtureBuild/install-guard.sha256",(Hash "$fixtureBuild/install_guard.exe")+"`n")
Copy-Item -LiteralPath "$BuildDir/windows-runtime-sources.txt" -Destination "$fixtureBuild/windows-runtime-sources.txt"
[IO.File]::WriteAllText("$fixtureBuild/cmake_install.cmake", "set(MIDI_INSTALL_CONTEXT [==[$fixtureBuild/windows-install-context.cmake]==])`nset(STAGE_PREFIX `"`${CMAKE_INSTALL_PREFIX}`")`nset(MIDI_INSTALL_MODE install)`nset(MIDI_INSTALL_COMPONENT `"`${CMAKE_INSTALL_COMPONENT}`")`ninclude([==[$SourceDir/cmake/VerifyInstalledPackage.cmake]==])`n")
$BuildDir=$fixtureBuild
$stage=Fresh 'guard-identity'
[IO.File]::WriteAllText("$work/guard-context.cmake",$fixtureContext.Replace("$BuildDir/install_guard.exe","$configuredBuild/pure-midi-runner-fixture.exe"))
Run guard-substitution $false (VerifyArgs $stage "$work/guard-context.cmake") 'frozen native guard identity mismatch' | Out-Null
if($IdentityRedOnly) { Clean; exit 0 }
foreach($case in @('stage-hardlink','manifest-hardlink','stage-junction','ancestor-junction','endpoint-junction','operation-lock','reparse-context')) {
  $stage=Fresh $case; $before=Tree $stage; $link=$null
  try {
    switch($case) {
      stage-hardlink { $link="$work/alias"; New-Item -ItemType HardLink -Path $link -Target "$stage/lib/pure/prelude.pure" | Out-Null }
      manifest-hardlink { [IO.File]::WriteAllText("$work/manifest-target",'KEEP'); $link="$BuildDir/install_manifest_runtime.txt"; if(Test-Path -LiteralPath $link) { [IO.File]::Delete($link) }; New-Item -ItemType HardLink -Path $link -Target "$work/manifest-target" | Out-Null }
      stage-junction { $link="$stage/junction"; New-Item -ItemType Junction -Path $link -Target "$work" | Out-Null }
      ancestor-junction { $link="$stage/share/doc"; New-Item -ItemType Junction -Path $link -Target "$work" | Out-Null }
      endpoint-junction { $link="$stage/lib/pure/pmlib.dll"; New-Item -ItemType Junction -Path $link -Target "$work" | Out-Null }
      operation-lock { $lock=[IO.File]::Open("$BuildDir/install-operation.lock",[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None) }
      reparse-context { $link="$work/context-link"; New-Item -ItemType Junction -Path $link -Target $BuildDir | Out-Null }
    }
    $arguments=if($case -eq 'reparse-context') { VerifyArgs $stage "$link/windows-install-context.cmake" } else { InstallArgs $stage runtime }
    $reason=switch($case) {
      stage-hardlink { 'hardlink' }
      manifest-hardlink { 'hardlinked writable' }
      operation-lock { 'already owned' }
      reparse-context { 'redirected path origin|reparse' }
      default { 'reparse' }
    }
    Run $case $false $arguments $reason | Out-Null
  } finally {
    if($case -eq 'operation-lock') { $lock.Dispose() }
    if($link) { if($case -match 'junction|reparse-context') { [IO.Directory]::Delete($link) } else { [IO.File]::Delete($link) } }
  }
  Same $before $stage
  if($case -eq 'manifest-hardlink' -and [IO.File]::ReadAllText("$work/manifest-target") -cne 'KEEP') { throw 'Hardlink target changed' }
}
foreach($phase in @('queued','reserved','failure-1','failure-6','failure-9')) {
  $stage=Fresh $phase; $before=Tree $stage
  $manifestPath="$BuildDir/install_manifest_runtime.txt"
  $manifestBefore=if(Test-Path -LiteralPath $manifestPath) { [IO.File]::ReadAllText($manifestPath) } else { $null }
  $readyName='Local\midi-ready-'+[Guid]::NewGuid().ToString('N'); $releaseName='Local\midi-release-'+[Guid]::NewGuid().ToString('N')
  $ready=New-Object Threading.EventWaitHandle($false,[Threading.EventResetMode]::ManualReset,$readyName)
  $release=New-Object Threading.EventWaitHandle($false,[Threading.EventResetMode]::ManualReset,$releaseName)
  $start=New-Object Diagnostics.ProcessStartInfo
  $start.FileName="$BuildDir/install_guard.exe"
  $start.Arguments=(@('--run',$stage,$BuildDir,$cmake,"$BuildDir/windows-install-context.cmake","$SourceDir/cmake/VerifyInstalledPackage.cmake",'install','runtime') | ForEach-Object { '"'+$_+'"' }) -join ' '
  $start.UseShellExecute=$false; $start.CreateNoWindow=$true; $start.RedirectStandardOutput=$true; $start.RedirectStandardError=$true
  $start.EnvironmentVariables['MIDI_GUARD_TEST_READY']=$readyName; $start.EnvironmentVariables['MIDI_GUARD_TEST_RELEASE']=$releaseName
  $start.EnvironmentVariables['MIDI_GUARD_TEST_PHASE']=if($phase -eq 'queued') { 'queued' } else { 'reserved' }
  if($phase -match '^failure-(\d+)$') { $start.EnvironmentVariables['MIDI_GUARD_TEST_FAIL_AFTER_WRITE']=$Matches[1] }
  $process=[Diagnostics.Process]::Start($start); $stdout=$process.StandardOutput.ReadToEndAsync(); $stderr=$process.StandardError.ReadToEndAsync()
  try {
    if(-not $ready.WaitOne(30000)) {
      if(-not $process.HasExited) { $process.Kill(); $process.WaitForExit() }
      [IO.File]::WriteAllText("$work/gate-$phase.log",$stdout.Result+$stderr.Result)
      throw "Guard gate not reached: $phase : $($stdout.Result) $($stderr.Result)"
    }
    if($phase -eq 'queued') {
      Run cooperating-installer $false (InstallArgs $stage documentation) 'already owned' | Out-Null
      # Same stage identity, different build lock.
      $ErrorActionPreference='Continue'
      $out=& "$configuredBuild/install_guard.exe" --run $stage $configuredBuild $cmake "$configuredBuild/windows-install-context.cmake" "$SourceDir/cmake/VerifyInstalledPackage.cmake" install documentation 2>&1
      $rc=$LASTEXITCODE; $ErrorActionPreference='Stop'
      if($rc -eq 0 -or "$out" -notmatch 'stage identity already owned') { throw "Cross-build exclusion failed: $out" }; $negative++
      $blocked=$false
      try { [IO.Directory]::Move("$stage/lib/pure","$work/moved") } catch [IO.IOException] { $blocked=$true }
      if(-not $blocked) { throw 'Retained ancestor renamed' }; $negative++
      # Late unowned collision must not be overwritten and must cause rollback.
      New-Item -ItemType Junction -Path "$stage/bin/libportmidi.dll" -Target $work | Out-Null
    } elseif($phase -eq 'reserved') {
      foreach($p in @("$stage/bin/libportmidi.dll","$stage/lib/pure/pmlib.dll","$stage/share/doc/pure-midi/README")) {
        $blocked=$false
        try { $f=[IO.File]::Open($p,[IO.FileMode]::Open,[IO.FileAccess]::ReadWrite,[IO.FileShare]::ReadWrite); $f.Dispose() } catch [IO.IOException] { $blocked=$true }
        if(-not $blocked) { throw 'Reserved endpoint admitted write' }; $negative++
      }
    }
    $release.Set() | Out-Null
    if(-not $process.WaitForExit(120000)) { throw 'Guard deadline exceeded' }
    [IO.File]::WriteAllText("$work/$phase.log",$stdout.Result+$stderr.Result)
    if($phase -eq 'reserved') {
      if($process.ExitCode -ne 0) { throw "Reserved pristine failed: $($stderr.Result)" }; $positive++
    } else {
      if($process.ExitCode -eq 0) { throw 'Expected controlled failure accepted' }; $negative++
      if($phase -eq 'queued') { [IO.Directory]::Delete("$stage/bin/libportmidi.dll") }
      elseif($stderr.Result -notmatch 'injected pre-commit write failure' -or $stdout.Result -notmatch 'INSTALL_BATCH_ROLLBACK_OK') { throw 'Wrong rollback failure cause' }
      Same $before $stage
      if($null -ne $manifestBefore -and [IO.File]::ReadAllText($manifestPath) -cne $manifestBefore) { throw 'Rollback changed previous conventional component manifest' }
      Run "retry-$phase" $true (InstallArgs $stage runtime) | Out-Null
    }
  } finally {
    $release.Set() | Out-Null
    if(-not $process.HasExited) { $process.Kill(); $process.WaitForExit() }
    $process.Dispose(); $ready.Dispose(); $release.Dispose()
  }
}
foreach($order in @('all','documentation-first')) {
  $stage=Fresh $order
  if($order -eq 'all') { Run all-components $true (InstallArgs $stage all) | Out-Null }
  else {
    Run documentation-first $true (InstallArgs $stage documentation) | Out-Null
    if(Test-Path -LiteralPath "$stage/lib/pure/pmlib.dll") { throw 'Documentation installed runtime payloads' }
    Run runtime-second $true (InstallArgs $stage runtime) | Out-Null
  }
  Run "verify-$order" $true (VerifyArgs $stage) 'INSTALL_PACKAGE_OK.*installed_tests=2' | Out-Null
}
"INSTALL_GUARD_CONTRACT_OK negative=$negative positive=$positive outside_writes=0 controlled_rollback=4"
Clean
