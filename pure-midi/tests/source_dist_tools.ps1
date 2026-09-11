param([Parameter(Mandatory=$true)][string]$SourceDir,
      [Parameter(Mandatory=$true)][string]$Clang64Prefix,
      [Parameter(Mandatory=$true)][string]$DistRoot, [switch]$RedOnly,
      [switch]$PublishRedOnly, [switch]$PairRedOnly)
$ErrorActionPreference='Stop'
# Independent literal release inventory: an omitted producer entry must fail.
[string[]]$expected=@(
 'CMakeLists.txt','COPYING','Makefile','README','THIRD_PARTY.md','WINDOWS.md',
 'cmake/CreateSourceArchive.cmake','cmake/Install.cmake','cmake/RunHardwareTest.cmake',
 'cmake/RunPureTest.cmake','cmake/SourceArchiveTools.ps1','cmake/SourceWorkflow.cmake',
 'cmake/VerifyInstalledPackage.cmake','cmake/VerifyWindowsDependencies.cmake','cmake/install_guard.c',
 'debian/changelog','debian/compat','debian/control','debian/copyright','debian/docs',
 'debian/rules','debian/source/format','debian/watch','examples/midi_examp.pure','examples/prelude3.mid',
 'licenses/PortMidi.txt','licenses/origins.tsv','midi.pure','midi_bounds.c','midi_bounds.h',
 'midi_stream.c','midi_stream.h','midifile/Makefile','midifile/mf.c','midifile/mf.h',
 'midifile/midifile.c','midifile/midifile.h','midifile/midifile.pure','pmdev.c','pmdev.h',
 'portmidi.h','portmidi.pure','porttime.h','tests/bounds.pure','tests/cleanup_contract.cmake',
 'tests/configure_contract.cmake','tests/device-timing.pure','tests/hardware-output.pure',
 'tests/install_contract.cmake','tests/install_guard_contract.ps1','tests/midi_boundary_harness.c',
 'tests/midi_lifecycle_harness.c','tests/midifile_fault_harness.c','tests/midifile_test_api.h',
 'tests/run_pure_test.c','tests/runner_contract.cmake','tests/runner_fixture.c',
 'tests/runner_hardware_fixture.c','tests/runtime_verifier_contract.cmake','tests/smoke.pure',
 'tests/source_dist_contract.cmake','tests/source_dist_extracted.cmake','tests/source_dist_tools.ps1')
[Array]::Sort($expected,[StringComparer]::Ordinal)
function Hash([string]$Path) {
 $sha=[Security.Cryptography.SHA256]::Create(); $f=[IO.File]::OpenRead($Path)
 try { [BitConverter]::ToString($sha.ComputeHash($f)).Replace('-','').ToLowerInvariant() }
 finally { $f.Dispose(); $sha.Dispose() }
}
function PublicDist([string]$Root,[string]$Output,[bool]$Good=$true) {
 $old=$ErrorActionPreference; $ErrorActionPreference='Continue'
 $out=& "$Clang64Prefix/bin/mingw32-make.exe" -C $Root dist 'DLL=.dll' "SHELL=$Clang64Prefix/../usr/bin/sh.exe" "CMAKE=$Clang64Prefix/bin/cmake.exe" "DIST_DIR=$Output" 2>&1
 $rc=$LASTEXITCODE; $ErrorActionPreference=$old
 $script:lastPublicOutput=$out -join "`n"
 if(($Good -and $rc -ne 0) -or (-not $Good -and $rc -eq 0)) { throw "RED: public dist expected success=$Good exit=$rc : $out" }
 $out | Write-Host
 return $rc
}
$env:PATH="$Clang64Prefix/bin;$Clang64Prefix/../usr/bin;C:/Windows/System32;C:/Windows"
if($RedOnly) {
 # The only legacy recursive target is confined to this fresh, verified leaf.
 # No caller-provided dist/version variables reach that old Makefile.
 $DistRoot=[IO.Path]::GetFullPath($DistRoot)
 if(-not [IO.Directory]::Exists($DistRoot)) { [IO.Directory]::CreateDirectory($DistRoot) | Out-Null }
 $work=Join-Path $DistRoot ([Guid]::NewGuid().ToString('N'))
 [IO.Directory]::CreateDirectory($work) | Out-Null
 foreach($rel in $expected) {
  if([IO.File]::Exists("$SourceDir/$rel")) {
   [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName("$work/$rel")) | Out-Null
   [IO.File]::Copy("$SourceDir/$rel","$work/$rel")
  }
 }
 "SOURCE_RED_WORK=$work"
 PublicDist $work $work | Out-Null
 $first=Hash "$work/pure-midi-0.6.tar.gz"
 Start-Sleep -Seconds 2
 PublicDist $work $work | Out-Null
 $second=Hash "$work/pure-midi-0.6.tar.gz"
 $listing=& "$Clang64Prefix/bin/cmake.exe" -E tar tf "$work/pure-midi-0.6.tar.gz"
 if($LASTEXITCODE -ne 0) { throw 'Cannot inspect actual legacy archive' }
 $missing=@($expected | Where-Object { "pure-midi-0.6/$_" -cnotin $listing })
 "SOURCE_RED_ARCHIVES first=$first second=$second entries=$($listing.Count) expected_files=$($expected.Count)"
 "SOURCE_RED_MISSING=$($missing -join ',')"
 if($first -cne $second -or $missing.Count) { throw 'RED: public dist is nondeterministic or omits declared release sources' }
 throw 'RED control unexpectedly passed'
}
# Full producer, archive, extraction and leak mutations below use the shipped
# production entrypoints; fixture edits never touch the checkout.
. "$SourceDir/cmake/SourceArchiveTools.ps1" -SourceDir $SourceDir -Clang64Prefix $Clang64Prefix -DistRoot $DistRoot
$owned=New-SourceLeaf $DistRoot
$work=$owned.Path; $nonce=$owned.Nonce
"SOURCE_CONTRACT_WORK=$work"
$negative=0; $positive=0
function Reject([string]$CaseLabel,[scriptblock]$Action,[string]$Reason) {
 $caught=$null
 try { & $Action | Out-Null } catch { $caught=$_.Exception.Message }
 if(-not $caught -or $caught -notmatch $Reason) { throw "Mutation $CaseLabel did not reject for $Reason : $caught" }
 $script:negative++; "SOURCE_CASE_OK $CaseLabel"
}
# Task4 deliberately retains these shared reparse fixtures. The source workflow
# may unlink only their exact owned names/targets after tests, never follow them.
$runnerFixtures="$work/b/pure-midi-contract-root/fixtures"
[IO.Directory]::CreateDirectory($runnerFixtures) | Out-Null
[IO.File]::WriteAllText("$runnerFixtures/pristine.pure",'KEEP FIXTURE TARGET')
$runnerLink="$work/b/pure-midi-contract-root/fixtures-junction"
New-Item -ItemType Junction -Path $runnerLink -Target $runnerFixtures | Out-Null
Reject fixture-cleanup-wrong-owner { Remove-SourceRunnerFixtures $DistRoot $work ('0'*64) } 'ownership'
[IO.Directory]::Delete($runnerLink)
New-Item -ItemType Junction -Path $runnerLink -Target $work | Out-Null
Reject fixture-cleanup-wrong-target { Remove-SourceRunnerFixtures $DistRoot $work $nonce } 'fixture target'
[IO.Directory]::Delete($runnerLink); [IO.Directory]::CreateDirectory($runnerLink) | Out-Null
Reject fixture-cleanup-regular-directory { Remove-SourceRunnerFixtures $DistRoot $work $nonce } 'fixture reparse'
[IO.Directory]::Delete($runnerLink)
New-Item -ItemType Junction -Path $runnerLink -Target $runnerFixtures | Out-Null
Remove-SourceRunnerFixtures $DistRoot $work $nonce
if((Test-Path -LiteralPath $runnerLink) -or [IO.File]::ReadAllText("$runnerFixtures/pristine.pure") -cne 'KEEP FIXTURE TARGET') { throw 'Runner fixture unlink changed target or retained link' }
$positive++; 'SOURCE_CASE_OK fixture-cleanup-preserves-target'
$source="$work/source with spaces"
[IO.Directory]::CreateDirectory($source) | Out-Null
foreach($rel in $expected) {
 [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName("$source/$rel")) | Out-Null
 [IO.File]::Copy("$SourceDir/$rel","$source/$rel")
}
$out="$work/output with spaces"; [IO.Directory]::CreateDirectory($out) | Out-Null
PublicDist $source $out | Out-Null
$archive="$out/pure-midi-0.6.tar.gz"; $manifest="$out/pure-midi-0.6.manifest.tsv"
$first=Hash $archive
[IO.File]::Copy($archive,"$work/first.tar.gz")
Add-Type -TypeDefinition @'
using System.IO;
using System;
using System.Security.Cryptography;
using System.Threading;
public static class SourceArchiveReaderLock {
 public static Thread ReleaseAfter(string path,int delay) {
  var file=File.Open(path,FileMode.Open,FileAccess.Read,FileShare.Read);
  var thread=new Thread(delegate() { Thread.Sleep(delay); file.Dispose(); });
  thread.Start(); return thread;
 }
}
public sealed class SourceArchiveChangeLock : IDisposable {
 readonly ManualResetEvent stop=new ManualResetEvent(false);
 readonly Thread thread;
 public volatile bool Locked;
 public string Error;
 public SourceArchiveChangeLock(string path,string wanted) {
  thread=new Thread(delegate() {
   var until=DateTime.UtcNow.AddSeconds(20);
   while(!stop.WaitOne(0) && DateTime.UtcNow<until) {
    FileStream file=null;
    try {
     file=File.Open(path,FileMode.Open,FileAccess.Read,FileShare.Read);
     string got;
     using(var sha=SHA256.Create()) got=BitConverter.ToString(sha.ComputeHash(file)).Replace("-", "").ToLowerInvariant();
     if(got==wanted) { Locked=true; stop.WaitOne(20000); return; }
    } catch(IOException) { }
    catch(Exception error) { Error=error.Message; return; }
    finally { if(file!=null) file.Dispose(); }
    Thread.Sleep(10);
   }
   if(!Locked) Error="changed archive was not observed";
  });
  thread.Start();
 }
 public void Dispose() { stop.Set(); thread.Join(); stop.Dispose(); }
}
'@
# A failure after the archive swap must not leave a new archive paired with the
# old manifest. Changed input bytes are essential: unchanged-byte retries hide it.
$pairInput="$source/midi_bounds.c"; $pairSaved=[IO.File]::ReadAllBytes($pairInput)
$oldPair=@((Hash $archive),(Hash $manifest))
$pairFailures=New-Object 'Collections.Generic.List[string]'
function PairCopy([string]$Destination) {
 [IO.Directory]::CreateDirectory($Destination) | Out-Null
 [IO.File]::Copy($archive,"$Destination/pure-midi-0.6.tar.gz")
 [IO.File]::Copy($manifest,"$Destination/pure-midi-0.6.manifest.tsv")
}
function PairCase([string]$Label,[scriptblock]$Action) {
 try { & $Action; $script:negative++; "SOURCE_CASE_OK $Label" }
 catch { $pairFailures.Add("${Label}: $($_.Exception.Message)"); "SOURCE_PAIR_RED ${Label}: $($_.Exception.Message)" }
}
try {
 [IO.File]::AppendAllText($pairInput,"`n/* changed publication fixture */`n")
 $changedPairOut="$work/changed pair"; [IO.Directory]::CreateDirectory($changedPairOut) | Out-Null
 PublicDist $source $changedPairOut | Out-Null
 $newPair=@((Hash "$changedPairOut/pure-midi-0.6.tar.gz"),(Hash "$changedPairOut/pure-midi-0.6.manifest.tsv"))
 if($newPair[0] -ceq $oldPair[0] -or $newPair[1] -ceq $oldPair[1]) { throw 'Changed input did not change both public artifacts' }
 $positive++; 'SOURCE_CASE_OK changed-pair-from-absent'
 $changedExistingOut="$work/changed existing pair"; PairCopy $changedExistingOut
 PublicDist $source $changedExistingOut | Out-Null
 if((Hash "$changedExistingOut/pure-midi-0.6.tar.gz") -cne $newPair[0] -or (Hash "$changedExistingOut/pure-midi-0.6.manifest.tsv") -cne $newPair[1] -or @(Get-ChildItem -LiteralPath $changedExistingOut -Force).Count -ne 2) { throw 'Successful changed publication did not commit exactly the new pair' }
 $positive++; 'SOURCE_CASE_OK changed-pair-replaces-existing'
 # Real simultaneous public writers must serialize while a manifest reader
 # delays one transaction. The final pair must be wholly one source generation.
 $parallelOut="$work/concurrent pair"; PairCopy $parallelOut
 $parallelReader=[SourceArchiveReaderLock]::ReleaseAfter("$parallelOut/pure-midi-0.6.manifest.tsv",3500)
 $pairJobs=@()
 try {
  foreach($writerSource in @($source,$SourceDir)) {
   $pairJobs+=Start-Job -ArgumentList $Clang64Prefix,$writerSource,$parallelOut -ScriptBlock {
    param($prefix,$inputRoot,$outputRoot)
    $ErrorActionPreference='Continue'
    $transcript=& "$prefix/bin/mingw32-make.exe" -C $inputRoot dist 'DLL=.dll' "SHELL=$prefix/../usr/bin/sh.exe" "CMAKE=$prefix/bin/cmake.exe" "DIST_DIR=$outputRoot" 2>&1
    [pscustomobject]@{ExitCode=$LASTEXITCODE;Output=($transcript -join "`n")}
   }
  }
  $pairJobs | Wait-Job -Timeout 60 | Out-Null
  foreach($job in $pairJobs) {
   if($job.State -ne 'Completed') { throw "Concurrent public writer did not complete: $($job.State)" }
   $result=Receive-Job -Job $job
   if($result.ExitCode -ne 0) { throw "Concurrent public writer failed: $($result.Output)" }
  }
 } finally { $parallelReader.Join(); foreach($job in $pairJobs) { if($job.State -eq 'Running') { Stop-Job -Job $job }; Remove-Job -Job $job -Force } }
 $parallelPair=@((Hash "$parallelOut/pure-midi-0.6.tar.gz"),(Hash "$parallelOut/pure-midi-0.6.manifest.tsv"))
 if(($parallelPair -join '|') -cnotin @(($oldPair -join '|'),($newPair -join '|')) -or @(Get-ChildItem -LiteralPath $parallelOut -Force).Count -ne 2) { throw 'Concurrent public writers left a mixed pair or recovery artifacts' }
 $positive++; 'SOURCE_CASE_OK concurrent-public-pair'
 foreach($endpoint in @('archive','manifest')) {
  foreach($blocker in @('reader','readonly')) {
   $pairCaseOut="$work/pair-$endpoint-$blocker"; PairCopy $pairCaseOut
   $pairArchive="$pairCaseOut/pure-midi-0.6.tar.gz"; $pairManifest="$pairCaseOut/pure-midi-0.6.manifest.tsv"
   $blocked=if($endpoint -ceq 'archive') { $pairArchive } else { $pairManifest }
   PairCase "changed-pair-$endpoint-$blocker" {
    $held=$null; $attributes=[IO.File]::GetAttributes($blocked)
    try {
     if($blocker -ceq 'reader') { $held=[IO.File]::Open($blocked,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read) }
     else { [IO.File]::SetAttributes($blocked,$attributes -bor [IO.FileAttributes]::ReadOnly) }
     PublicDist $source $pairCaseOut $false | Out-Null
    } finally { if($null -ne $held) { $held.Dispose() }; [IO.File]::SetAttributes($blocked,$attributes) }
    $after=@((Hash $pairArchive),(Hash $pairManifest))
    "SOURCE_PAIR_OBSERVED endpoint=$endpoint blocker=$blocker old_archive=$($oldPair[0]) archive=$($after[0]) old_manifest=$($oldPair[1]) manifest=$($after[1])"
    if($after[0] -cne $oldPair[0] -or $after[1] -cne $oldPair[1]) { throw 'Rejected publication left a partial changed archive/manifest pair' }
    if(@(Get-ChildItem -LiteralPath $pairCaseOut -Force).Count -ne 2) { throw 'Recovered publication leaked temporary/recovery artifacts' }
   }
  }
 }
 foreach($endpoint in @('archive','manifest')) {
  $absentOut="$work/absent-$endpoint"; [IO.Directory]::CreateDirectory($absentOut) | Out-Null
  $unavailable=if($endpoint -ceq 'archive') { "$absentOut/pure-midi-0.6.tar.gz" } else { "$absentOut/pure-midi-0.6.manifest.tsv" }
  [IO.Directory]::CreateDirectory($unavailable) | Out-Null
  PairCase "absent-pair-unavailable-$endpoint" {
   PublicDist $source $absentOut $false | Out-Null
   if(@(Get-ChildItem -LiteralPath $absentOut -Force).Count -ne 1 -or -not [IO.Directory]::Exists($unavailable)) { throw 'Absent-pair rejection left a partial artifact or removed the blocker' }
  }
 }
 $incompleteOut="$work/incomplete-pair"; [IO.Directory]::CreateDirectory($incompleteOut) | Out-Null
 [IO.File]::Copy($archive,"$incompleteOut/pure-midi-0.6.tar.gz")
 PairCase incomplete-previous-pair {
  PublicDist $source $incompleteOut $false | Out-Null
  if((Hash "$incompleteOut/pure-midi-0.6.tar.gz") -cne $oldPair[0] -or @(Get-ChildItem -LiteralPath $incompleteOut -Force).Count -ne 1) { throw 'Incomplete prior pair changed on rejection' }
 }
 $mismatchedOut="$work/mismatched-pair"; PairCopy $mismatchedOut
 [IO.File]::Copy("$changedPairOut/pure-midi-0.6.manifest.tsv","$mismatchedOut/pure-midi-0.6.manifest.tsv",$true)
 PairCase mismatched-previous-pair {
  PublicDist $source $mismatchedOut $false | Out-Null
  if((Hash "$mismatchedOut/pure-midi-0.6.tar.gz") -cne $oldPair[0] -or (Hash "$mismatchedOut/pure-midi-0.6.manifest.tsv") -cne $newPair[1]) { throw 'Mismatched prior pair changed on rejection' }
 }
 # The coordinator must also restore absence if the second candidate becomes
 # unavailable after preparation. A real read handle denies moving that file.
 $absentRollbackOut="$work/absent rollback"; [IO.Directory]::CreateDirectory($absentRollbackOut) | Out-Null
 $absentCandidate="$absentRollbackOut/candidate.tmp"; $absentManifest="$absentRollbackOut/candidate-manifest.tmp"
 [IO.File]::Copy("$changedPairOut/pure-midi-0.6.tar.gz",$absentCandidate)
 [IO.File]::Copy("$changedPairOut/pure-midi-0.6.manifest.tsv",$absentManifest)
 PairCase absent-pair-rollback-after-first {
  $candidateReader=[IO.File]::Open($absentManifest,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
  $caught=$null
  try { Publish-SourcePair $absentCandidate $absentManifest $absentRollbackOut }
  catch { $caught=$_.Exception.Message }
  finally { $candidateReader.Dispose() }
  if(-not $caught -or $caught -notmatch 'previous absence restored') { throw "Absent-pair rollback did not restore and report absence: $caught" }
  if([IO.File]::Exists("$absentRollbackOut/pure-midi-0.6.tar.gz") -or [IO.File]::Exists("$absentRollbackOut/pure-midi-0.6.manifest.tsv") -or [IO.File]::Exists("$absentRollbackOut/.source-recovery")) { throw 'Absent-pair rollback left published/recovery artifacts' }
 }
 # Force a genuine rollback failure: hold the old manifest, then acquire a real
 # reader on the changed archive after its atomic swap. No production failpoint.
 $recoveryOut="$work/rollback failure"; PairCopy $recoveryOut
 PairCase rollback-failure-retains-pair-recovery {
  $manifestReader=[IO.File]::Open("$recoveryOut/pure-midi-0.6.manifest.tsv",[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
  $changedReader=New-Object SourceArchiveChangeLock("$recoveryOut/pure-midi-0.6.tar.gz",$newPair[0])
  try { PublicDist $source $recoveryOut $false | Out-Null }
  finally { $changedReader.Dispose(); $manifestReader.Dispose() }
  if(-not $changedReader.Locked -or $changedReader.Error) { throw "Rollback fixture failed to lock changed archive: $($changedReader.Error)" }
  if($lastPublicOutput -notmatch 'recovery required') { throw 'Rollback failure did not report required recovery' }
  $recoveryMarker="$recoveryOut/.source-recovery"
  if(-not [IO.File]::Exists($recoveryMarker)) { throw 'Rollback failure did not retain a recovery marker' }
  $recoverable=@(Get-ChildItem -LiteralPath $recoveryOut -File -Force | ForEach-Object { Hash $_.FullName })
  if($oldPair[0] -cnotin $recoverable -or $oldPair[1] -cnotin $recoverable) { throw 'Rollback failure discarded a previous artifact' }
  $recoveryBefore=@(Get-ChildItem -LiteralPath $recoveryOut -File -Force | Sort-Object Name | ForEach-Object { $_.Name+'|'+(Hash $_.FullName) }) -join "`n"
  PublicDist $source $recoveryOut $false | Out-Null
  if($lastPublicOutput -notmatch 'recovery required') { throw 'Unrecovered publication did not fail closed' }
  $recoveryAfter=@(Get-ChildItem -LiteralPath $recoveryOut -File -Force | Sort-Object Name | ForEach-Object { $_.Name+'|'+(Hash $_.FullName) }) -join "`n"
  if($recoveryBefore -cne $recoveryAfter) { throw 'Unrecovered publication modified recovery evidence' }
 }
} finally { [IO.File]::WriteAllBytes($pairInput,$pairSaved) }
if($pairFailures.Count) { throw "Changed-pair publication RED: $($pairFailures -join '; ')" }
if($PairRedOnly) { "SOURCE_PAIR_CONTRACT_OK negative=$negative positive=$positive"; Remove-SourceLeaf $DistRoot $work $nonce; exit 0 }
# Real Windows readers (including indexers) may briefly deny replacement.
# Require eventual publication, and separately reject a persistent lock without
# changing either existing output. This exercises the real filesystem API.
$reader=[SourceArchiveReaderLock]::ReleaseAfter($archive,3000)
try { New-SourceArchive $source $out ($expected -join '|') | Out-Null }
finally { $reader.Join() }
if((Hash $archive) -cne $first) { throw 'Retry changed deterministic archive bytes' }
$positive++; 'SOURCE_CASE_OK transient-output-reader'
if($PublishRedOnly) { Remove-SourceLeaf $DistRoot $work $nonce; exit 0 }
$manifestBefore=Hash $manifest
$reader=[IO.File]::Open($archive,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
try { Reject persistent-output-reader { New-SourceArchive $source $out ($expected -join '|') } 'Publish' }
finally { $reader.Dispose() }
if((Hash $archive) -cne $first -or (Hash $manifest) -cne $manifestBefore) { throw 'Locked publication changed existing outputs' }
foreach($rel in $expected) { [IO.File]::SetLastWriteTimeUtc("$source/$rel",[DateTime]::UtcNow.AddYears(-7)) }
# Undeclared checkout/build/cache artifacts must not enter the public archive.
foreach($rel in @('extra.c','pmlib.dll','pmdev.o','CMakeCache.txt','.git/config','build/CMakeCache.txt','cache/stale.tmp')) {
 [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName("$source/$rel")) | Out-Null
 [IO.File]::WriteAllText("$source/$rel",'NOT A RELEASE INPUT')
}
PublicDist $source $out | Out-Null
$second=Hash $archive
if($first -cne $second) { throw 'Archive changed with only source metadata or undeclared artifacts' }
$positive+=2
$rows=[IO.File]::ReadAllLines($manifest)
if($rows.Count -ne $expected.Count) { throw 'Incorrect manifest file count' }
for($i=0;$i -lt $expected.Count;$i++) {
 $rel=$expected[$i]; $file=Get-Item -LiteralPath "$source/$rel"
 if($rows[$i] -cne "$rel|f|$($file.Length)|$(Hash $file.FullName)") { throw "Incorrect literal source manifest row $rel" }
}
$entries=Read-SourceArchive $archive $rows
if($entries.Count -ne $expected.Count) { throw 'Incorrect archive file count' }
$positive++
foreach($rel in @('midi_bounds.c','cmake/install_guard.c','tests/run_pure_test.c','licenses/PortMidi.txt','tests/source_dist_extracted.cmake')) {
 $path="$source/$rel"; $saved="$work/missing.saved"; [IO.File]::Move($path,$saved)
 try { Reject "missing-$rel" { PublicDist $source $out } 'public dist expected success=True' }
 finally { [IO.File]::Move($saved,$path) }
}
$path="$source/midi_stream.h"; [IO.File]::Move($path,"$work/header.saved"); [IO.Directory]::CreateDirectory($path) | Out-Null
try { Reject directory-source { PublicDist $source $out } 'public dist expected success=True' }
finally { [IO.Directory]::Delete($path); [IO.File]::Move("$work/header.saved",$path) }
$alias="$work/junction"
New-Item -ItemType Junction -Path $alias -Target $source | Out-Null
try { Reject reparse-source-ancestor { New-SourceArchive $alias $out ($expected -join '|') } 'reparse' }
finally { [IO.Directory]::Delete($alias) }
$nested="$source/examples"; [IO.Directory]::Move($nested,"$work/examples.saved")
New-Item -ItemType Junction -Path $nested -Target "$work/examples.saved" | Out-Null
try { Reject reparse-input-parent { PublicDist $source $out } 'public dist expected success=True' }
finally { [IO.Directory]::Delete($nested); [IO.Directory]::Move("$work/examples.saved",$nested) }
foreach($name in @('build/CMakeCache.txt','cache/extra.c','.git/config','pmlib.dll','pmdev.o','extra.tmp','../escape.c','midi.pure|midi.pure')) {
 Reject "invalid-manifest-$name" { New-SourceArchive $source $out (($expected -join '|')+'|'+$name) } 'manifest invalid or generated'
}
$extract="$work/extracted source"; Expand-SourceArchive $archive $rows $extract
$positive++
[IO.File]::WriteAllText("$extract/pure-midi-0.6/extra.c",'EXTRA')
Reject extra-extracted { Test-SourceTree "$extract/pure-midi-0.6" $rows } 'exact source tree'
[IO.File]::Delete("$extract/pure-midi-0.6/extra.c")
[IO.File]::AppendAllText("$extract/pure-midi-0.6/midi_bounds.c",'CHANGED')
Reject changed-extracted { Test-SourceTree "$extract/pure-midi-0.6" $rows } 'hash|manifest'
# Archive byte mutations are made independently of the producer's tar encoder.
$compressed=[IO.File]::OpenRead($archive); $gzip=New-Object IO.Compression.GZipStream($compressed,[IO.Compression.CompressionMode]::Decompress)
$memory=New-Object IO.MemoryStream
try { $gzip.CopyTo($memory); $tar=$memory.ToArray() } finally { $gzip.Dispose(); $compressed.Dispose(); $memory.Dispose() }
# Independent positive metadata assertions prevent encoder/verifier agreement
# from silently changing the distribution's fixed public format.
$pos=0
foreach($row in $rows) {
 $fields=$row.Split('|'); $name=$fields[0]; $size=[int]$fields[2]
 $header=[Text.Encoding]::ASCII.GetString($tar,$pos,512)
 $expectedMode=if($name -ceq 'debian/rules') { "0000755`0" } else { "0000644`0" }
 if($header.Substring(0,100).Trim([char]0) -cne "pure-midi-0.6/$name" -or
    $header.Substring(100,8) -cne $expectedMode -or $header.Substring(108,8) -cne "0000000`0" -or
    $header.Substring(116,8) -cne "0000000`0" -or $header.Substring(136,12) -cne "00000000000`0" -or
    $header[156] -cne '0' -or $header.Substring(257,8) -cne "ustar`000" -or
    $header.Substring(265).Trim([char]0).Length -ne 0) { throw "Independent archive metadata mismatch $name" }
 $pos+=512+[int]([Math]::Ceiling($size/512.0)*512)
}
if($tar.Length -ne $pos+1024) { throw 'Independent archive terminator size mismatch' }
$positive++
function RejectTarBytes([string]$Name,[byte[]]$Bytes,[string]$Reason='archive') {
 $file="$work/$Name.tar.gz"; $stream=[IO.File]::Create($file)
 $gz=New-Object IO.Compression.GZipStream($stream,[IO.Compression.CompressionLevel]::Optimal)
 try { $gz.Write($Bytes,0,$Bytes.Length) } finally { $gz.Dispose(); $stream.Dispose() }
 $packed=[IO.File]::ReadAllBytes($file); $packed[8]=0; $packed[9]=255; [IO.File]::WriteAllBytes($file,$packed)
 Reject $Name { Read-SourceArchive $file $rows } $Reason
}
function MutatedTar([string]$Name,[int]$Offset,[byte]$Value,[bool]$Checksum=$true) {
 $bytes=[byte[]]$tar.Clone(); $bytes[$Offset]=$Value
 if($Checksum) {
  for($j=148;$j -lt 156;$j++) { $bytes[$j]=32 }
  $sum=0; for($j=0;$j -lt 512;$j++) { $sum+=$bytes[$j] }
  $check=[Text.Encoding]::ASCII.GetBytes([Convert]::ToString($sum,8).PadLeft(6,'0')+"`0 ")
  [Array]::Copy($check,0,$bytes,148,8)
 }
 RejectTarBytes $Name $bytes
}
foreach($case in @(@('mode',105,55),@('uid',112,49),@('gid',120,49),@('mtime',143,49),@('link',156,50),@('directory',156,53),@('device',156,51),@('owner-name',265,120),@('group-name',297,120),@('prefix',345,120),@('path-traversal',0,46),@('wrong-name',15,120),@('padding',500,49),@('order',15,90))) {
 MutatedTar $case[0] $case[1] $case[2]
}
MutatedTar checksum 148 49 $false
MutatedTar payload 512 0
$firstLength=512+[int]([Math]::Ceiling([int]$rows[0].Split('|')[2]/512.0)*512)
$secondLength=512+[int]([Math]::Ceiling([int]$rows[1].Split('|')[2]/512.0)*512)
RejectTarBytes extra-archive-member ([byte[]]($tar[0..($firstLength-1)]+$tar)) 'extra files'
RejectTarBytes missing-archive-member ([byte[]]$tar[$firstLength..($tar.Length-1)]) 'missing files'
$swapped=[byte[]]($tar[$firstLength..($firstLength+$secondLength-1)]+$tar[0..($firstLength-1)]+$tar[($firstLength+$secondLength)..($tar.Length-1)])
RejectTarBytes reordered-archive $swapped 'metadata/order/path'
RejectTarBytes truncated-archive ([byte[]]$tar[0..($tar.Length-514)]) 'missing files'
$bad=[byte[]][IO.File]::ReadAllBytes($archive); $bad[4]=1
[IO.File]::WriteAllBytes("$work/gzip-time.tar.gz",$bad)
Reject gzip-time { Read-SourceArchive "$work/gzip-time.tar.gz" $rows } 'gzip'
$scan="$work/scan"; [IO.Directory]::CreateDirectory($scan) | Out-Null
$checkout='C:/NoSuchCheckout/Release Source'
foreach($variant in @($checkout,$checkout.ToUpperInvariant(),$checkout.Replace('/','\').ToLowerInvariant())) {
 foreach($offset in @(0,65530,(9MB+131))) {
  foreach($encoding in @([Text.Encoding]::UTF8,[Text.Encoding]::Unicode,[Text.Encoding]::BigEndianUnicode)) {
   $stream=[IO.File]::Create("$scan/leak.bin")
   try { $stream.SetLength($offset); $stream.Position=$offset; $bytes=$encoding.GetBytes($variant); $stream.Write($bytes,0,$bytes.Length) } finally { $stream.Dispose() }
   Reject "checkout-leak-$offset-$($encoding.WebName)" { Test-CheckoutLeaks $scan $checkout } 'checkout path leak'
  }
 }
}
[IO.File]::WriteAllText("$scan/leak.bin",'Unrelated regular output')
Test-CheckoutLeaks $scan $checkout; $positive++
$unicodeCheckout='C:/NoSuchCheckout/R'+[char]0xe9+'lease Source'
foreach($encoding in @([Text.Encoding]::UTF8,[Text.Encoding]::Unicode,[Text.Encoding]::BigEndianUnicode)) {
 [IO.File]::WriteAllBytes("$scan/leak.bin",$encoding.GetBytes($unicodeCheckout.ToUpperInvariant()))
 Reject "checkout-unicode-case-$($encoding.WebName)" { Test-CheckoutLeaks $scan $unicodeCheckout } 'checkout path leak'
}
$outside="$work/outside.txt"; [IO.File]::WriteAllText($outside,'KEEP OUTSIDE')
$cleanup=New-SourceLeaf $DistRoot
Reject cleanup-wrong-owner { Remove-SourceLeaf $DistRoot $cleanup.Path ('0'*64) } 'sentinel'
Reject cleanup-wrong-root { Remove-SourceLeaf $work $cleanup.Path $cleanup.Nonce } 'scope'
$link="$($cleanup.Path)/junction"; New-Item -ItemType Junction -Path $link -Target $work | Out-Null
try { Reject cleanup-reparse { Remove-SourceLeaf $DistRoot $cleanup.Path $cleanup.Nonce } 'reparse' }
finally { [IO.Directory]::Delete($link) }
Remove-SourceLeaf $DistRoot $cleanup.Path $cleanup.Nonce
if([IO.File]::ReadAllText($outside) -cne 'KEEP OUTSIDE') { throw 'Cleanup changed outside file' }; $positive++
PublicDist $source $out | Out-Null
if((Hash $archive) -cne $first) { throw 'Final pristine archive changed' }; $positive++
"SOURCE_DIST_CONTRACT_OK negative=$negative positive=$positive files=$($expected.Count) sha256=$first second=$second"
Remove-SourceLeaf $DistRoot $work $nonce
