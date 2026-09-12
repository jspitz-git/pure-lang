param([string]$Runner,[string]$Compiler,[string]$Root,[string]$Source)
$ErrorActionPreference='Stop'
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class GlRetentionProbe {
 [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)] public static extern IntPtr CreateFileW(string p,uint a,uint s,IntPtr sa,uint c,uint f,IntPtr t);
 [DllImport("kernel32.dll")] public static extern bool CloseHandle(IntPtr h);
}
'@
$probe=Join-Path $Root 'retained probe.exe'
& $Compiler -std=c11 -Wall -Wextra -Werror -municode (Join-Path $Source 'tests/runner_retention_fixture.c') -o $probe
if($LASTEXITCODE -ne 0) { throw 'Cannot compile retained-input fixture' }
$script=Join-Path $Root 'retained input.pure'
$input=Join-Path $Root 'retained module.dll'
[IO.File]::WriteAllText($input,'immutable test input')
foreach($aliasMode in @($false,$true)) {
 $id=[Guid]::NewGuid().ToString('N')
 $ready=[Threading.EventWaitHandle]::new($false,[Threading.EventResetMode]::ManualReset,"Local\gl-ready-$id")
 $release=[Threading.EventWaitHandle]::new($false,[Threading.EventResetMode]::ManualReset,"Local\gl-release-$id")
 [IO.File]::WriteAllText($script,"Local\gl-ready-$id`nLocal\gl-release-$id`n")
 $argsList=@('--pure',$probe,'--script',$script,'--cwd','C:/Windows','--timeout-ms','15000','--include',$Root,'--library',$Root,'--input',$input,'--path-entry','C:/Windows/System32')
 if($aliasMode) {
  $alias=& $Runner --print-pure-executable-alias $probe
  if($LASTEXITCODE -ne 0) { throw 'Cannot obtain retained fixture alias' }
  $argsList+=@('--pure-executable-alias',$alias)
 }
 $start=[Diagnostics.ProcessStartInfo]::new($Runner, (($argsList | ForEach-Object { '"'+$_.Replace('/','\')+'"' }) -join ' '))
 $start.UseShellExecute=$false; $start.CreateNoWindow=$true
 $start.RedirectStandardOutput=$true; $start.RedirectStandardError=$true
 $process=[Diagnostics.Process]::Start($start)
 try {
  if(-not $ready.WaitOne(10000)) { throw 'Owned child did not reach retention handoff' }
  foreach($target in @($script,$input,$probe,$Root)) {
   $handle=[GlRetentionProbe]::CreateFileW($target,0x40000000,7,[IntPtr]::Zero,3,0x02200000,[IntPtr]::Zero)
   if($handle.ToInt64() -ne -1) {
    [GlRetentionProbe]::CloseHandle($handle) | Out-Null
    throw "Owned input still permits writes: $target alias=$aliasMode"
   }
   if([Runtime.InteropServices.Marshal]::GetLastWin32Error() -ne 32) { throw "Input write failed for unrelated reason: $target" }
  }
 } finally {
  $release.Set() | Out-Null
  if(-not $process.WaitForExit(20000)) { $process.Kill(); throw 'Retention fixture did not stop' }
  $out=$process.StandardOutput.ReadToEnd(); $err=$process.StandardError.ReadToEnd()
  $ready.Dispose(); $release.Dispose()
 }
 if($process.ExitCode -ne 0 -or $err -ne '' -or $out -notmatch 'PURE_GL_TEST_OK') { throw "Retention fixture completion failed: $out $err" }
 # After ownership ends, the same data path must become writable again.
 $stream=[IO.File]::Open($input,[IO.FileMode]::Open,[IO.FileAccess]::Write,[IO.FileShare]::Read)
 $stream.Dispose()
}
Write-Output 'PURE_GL_RUNNER_RETENTION_OK synchronized=2 writes_denied=8 released=2'
