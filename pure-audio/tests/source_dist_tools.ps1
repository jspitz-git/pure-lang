param([Parameter(Mandatory=$true)][ValidateSet('Attributes','Scan','ScannerSelfTest','VerifyArchive','Isolate','ReserveBuild','CleanupBuild','BuildSelfTest')][string]$Mode,
      [Parameter(Mandatory=$true)][string]$Directory,[string]$SourceTools,
      [string]$Forbidden,[string]$Archive,[string]$Snapshot,[string]$CMake,
      [string]$ClangPrefix,[string]$PurePrefix,[string]$Original,[string]$Work,
      [string]$Ticket,[string]$BuildDirectory)
$ErrorActionPreference='Stop'

function Import-PathValidator {
  $tokens=$null; $parseErrors=$null
  $ast=[Management.Automation.Language.Parser]::ParseFile($SourceTools,[ref]$tokens,[ref]$parseErrors)
  if($parseErrors.Count) { throw 'Cannot parse actual archive path validator' }
  foreach($definition in $ast.FindAll({param($node)
      $node -is [Management.Automation.Language.FunctionDefinitionAst] -and
      $node.Name -in @('Assert-ArchivePath','Get-ArchiveAttributes')},$false)) {
    # The functions must live in this script's scope, not this import function.
    . ([scriptblock]::Create(($definition.Extent.Text -replace '^function ', 'function script:')))
  }
}
if($Mode -in @('ReserveBuild','CleanupBuild','BuildSelfTest')) {
  Import-PathValidator
  Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class SourceBuildDirectory {
  [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)]
  public static extern bool CreateDirectory(string path,IntPtr attributes);
}
'@
  function Reserve-Build([string]$Root,[string]$TicketPath) {
    $rootPath=Assert-ArchivePath $Root 'directory'
    # Task6's nested guard fixture adds 202 characters to its build root when
    # forming an atomic session temporary. Stay below legacy MAX_PATH.
    if($rootPath.Length+25+202 -ge 260) { throw 'Use a shorter strict build directory for the extracted MAX_PATH contract' }
    $null=Assert-ArchivePath ([IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($TicketPath))) 'directory'
    $random=New-Object byte[] 16; $rng=[Security.Cryptography.RandomNumberGenerator]::Create()
    try { $rng.GetBytes($random) } finally { $rng.Dispose() }
    $nonce=[Convert]::ToBase64String($random).TrimEnd('=').Replace('+','-').Replace('/','_')
    $path=Join-Path $rootPath ('d-'+$nonce)
    if(-not [SourceBuildDirectory]::CreateDirectory($path,[IntPtr]::Zero)) { throw "Atomic build directory reservation failed: $([Runtime.InteropServices.Marshal]::GetLastWin32Error())" }
    $text="pure-audio-source-build-v1`n$path`n$nonce`n"
    foreach($file in @((Join-Path $path '.source-dist-owner'),$TicketPath)) {
      $stream=[IO.File]::Open($file,'CreateNew','Write','None')
      try { $bytes=[Text.Encoding]::UTF8.GetBytes($text); $stream.Write($bytes,0,$bytes.Length) } finally { $stream.Dispose() }
    }
    return $path.Replace('\','/')
  }
  function Cleanup-Build([string]$Root,[string]$TicketPath) {
    $rootPath=Assert-ArchivePath $Root 'directory'
    $ticketPath=Assert-ArchivePath $TicketPath 'file'
    $text=[IO.File]::ReadAllText($ticketPath); $lines=$text.Split("`n")
    if($lines.Count -ne 4 -or $lines[0] -cne 'pure-audio-source-build-v1' -or $lines[2] -cnotmatch '^[A-Za-z0-9_-]{22}$' -or $lines[3] -cne '') { throw 'Build ownership ticket mismatch' }
    $path=Assert-ArchivePath $lines[1] 'directory'
    if([IO.Path]::GetDirectoryName($path) -ine $rootPath -or [IO.Path]::GetFileName($path) -cne ('d-'+$lines[2])) { throw 'Build ownership root/name mismatch' }
    $owner=Assert-ArchivePath (Join-Path $path '.source-dist-owner') 'file'
    if([IO.File]::ReadAllText($owner) -cne $text) { throw 'Build ownership sentinel mismatch' }
    $pending=New-Object 'Collections.Generic.Stack[string]'; $pending.Push($path)
    $files=New-Object 'Collections.Generic.List[string]'; $directories=New-Object 'Collections.Generic.List[string]'
    while($pending.Count) {
      $current=$pending.Pop(); $directories.Add($current)
      foreach($entry in [IO.Directory]::EnumerateFileSystemEntries($current)) {
        $attr=Get-ArchiveAttributes $entry
        if($attr -band [IO.FileAttributes]::ReparsePoint) { throw 'Build cleanup refuses reparse entry' }
        if($attr -band [IO.FileAttributes]::Directory) { $pending.Push($entry) } else { $files.Add($entry) }
      }
    }
    # Complete preflight precedes every deletion; no recursive delete API.
    foreach($file in $files) { [IO.File]::Delete($file) }
    foreach($directory in ($directories | Sort-Object Length -Descending)) { [IO.Directory]::Delete($directory,$false) }
    [IO.File]::Delete($ticketPath)
  }
  if($Mode -eq 'ReserveBuild') { Reserve-Build $Directory $Ticket }
  elseif($Mode -eq 'CleanupBuild') { Cleanup-Build $Directory $Ticket }
  else {
    $longTicket=Join-Path $Work 'too-long-build.ticket'
    $rejected=$false
    try { $null=Reserve-Build $Work $longTicket } catch { if("$_" -notmatch 'shorter strict build directory') { throw }; $rejected=$true }
    if(-not $rejected -or [IO.File]::Exists($longTicket)) { throw 'MAX_PATH preflight did not reject before reservation' }
    $testTicket=Join-Path $Work 'build-selftest.ticket'
    $path=Reserve-Build $Directory $testTicket
    $owner=Join-Path $path '.source-dist-owner'; $expected=[IO.File]::ReadAllText($owner)
    [IO.File]::WriteAllText((Join-Path $path 'payload.bin'),'owned payload')
    [IO.File]::WriteAllText($owner,'wrong owner')
    $rejected=$false
    try { Cleanup-Build $Directory $testTicket } catch { if("$_" -notmatch 'sentinel mismatch') { throw }; $rejected=$true }
    if(-not $rejected -or [IO.File]::ReadAllText((Join-Path $path 'payload.bin')) -cne 'owned payload') { throw 'Build ownership mismatch was not fail-closed' }
    [IO.File]::WriteAllText($owner,$expected)
    $outside=Join-Path $Work 'build-cleanup-outside'; $null=[IO.Directory]::CreateDirectory($outside)
    [IO.File]::WriteAllText((Join-Path $outside 'sentinel'),'outside')
    $junction=Join-Path $path 'junction'; $null=New-Item -ItemType Junction -Path $junction -Target $outside
    if(-not ((Get-Item -LiteralPath $junction -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'Invalid cleanup junction fixture' }
    $rejected=$false
    try { Cleanup-Build $Directory $testTicket } catch { if("$_" -notmatch 'refuses reparse') { throw }; $rejected=$true }
    if(-not $rejected -or [IO.File]::ReadAllText((Join-Path $outside 'sentinel')) -cne 'outside' -or -not [IO.File]::Exists((Join-Path $path 'payload.bin'))) { throw 'Build reparse cleanup changed owned/outside bytes' }
    [IO.Directory]::Delete($junction,$false)
    Cleanup-Build $Directory $testTicket
    if([IO.Directory]::Exists($path) -or [IO.File]::Exists($testTicket)) { throw 'Owned build cleanup left state' }
    'SOURCE_DIST_BUILD_OWNER_OK negatives=3 cleanup=1 outside_unchanged=1 max_path_budget=202'
  }
}

if($Mode -in @('Scan','ScannerSelfTest')) {
  Add-Type -TypeDefinition @'
using System;
using System.IO;
using System.Text;
public static class CheckoutScan {
  static byte Fold(byte b) { return b==92 ? (byte)47 : b>=65 && b<=90 ? (byte)(b+32) : b; }
  public static bool Contains(string file, string[] roots) {
    var patterns=new byte[roots.Length*2][];
    var tables=new int[patterns.Length][]; var states=new int[patterns.Length];
    for(int i=0;i<roots.Length;i++) {
      if(roots[i].Length<4) throw new ArgumentException("Empty/short forbidden root");
      patterns[2*i]=Encoding.UTF8.GetBytes(roots[i]);
      patterns[2*i+1]=Encoding.Unicode.GetBytes(roots[i]);
    }
    for(int p=0;p<patterns.Length;p++) {
      byte[] a=patterns[p]; for(int j=0;j<a.Length;j++) a[j]=Fold(a[j]);
      int[] t=tables[p]=new int[a.Length];
      for(int j=1,k=0;j<a.Length;j++) { while(k>0 && a[j]!=a[k]) k=t[k-1]; if(a[j]==a[k]) k++; t[j]=k; }
    }
    using(var f=new FileStream(file,FileMode.Open,FileAccess.Read,FileShare.Read)) {
      byte[] buffer=new byte[65536]; int n;
      while((n=f.Read(buffer,0,buffer.Length))!=0) {
        for(int i=0;i<n;i++) {
          byte b=Fold(buffer[i]);
          for(int p=0;p<patterns.Length;p++) {
            byte[] a=patterns[p]; int k=states[p];
            while(k>0 && b!=a[k]) k=tables[p][k-1];
            if(b==a[k]) k++; if(k==a.Length) return true; states[p]=k;
          }
        }
      }
    }
    return false;
  }
}
'@
}
if($Mode -eq 'ScannerSelfTest') {
  $root='C:/Checkout/Forbidden-source'
  $positive=Join-Path $Directory 'clean.bin'
  [IO.File]::WriteAllBytes($positive,[byte[]](0,255,0,128,65))
  if([CheckoutScan]::Contains($positive,@($root))) { throw 'Scanner rejected pristine binary' }
  $cases=@(@('mixed',3,$false),@('boundary',65530,$false),@('late',10485767,$false),@('utf16-late',10485767,$true))
  foreach($case in $cases) {
    $path=Join-Path $Directory ($case[0]+'.bin')
    $bytes=if($case[2]) { [Text.Encoding]::Unicode.GetBytes('c:\cHeCkOuT\FORBIDDEN-SOURCE') } else { [Text.Encoding]::UTF8.GetBytes('c:\cHeCkOuT\FORBIDDEN-SOURCE') }
    $f=[IO.File]::Open($path,'CreateNew','Write','None')
    try { $f.SetLength($case[1]); $f.Position=$case[1]; $f.Write($bytes,0,$bytes.Length); $f.WriteByte(255) } finally { $f.Dispose() }
    if(-not [CheckoutScan]::Contains($path,@($root))) { throw "Scanner accepted $($case[0]) binary checkout leak" }
  }
  'SOURCE_DIST_SCANNER_OK negatives=4 controls=1 bytes_after_9MiB=2'
}
if($Mode -eq 'Scan') {
  Import-PathValidator
  $roots=$Forbidden.Split('|')
  $pending=New-Object 'Collections.Generic.Stack[string]'
  $pending.Push((Assert-ArchivePath $Directory 'directory')); $count=0
  while($pending.Count) {
    foreach($entry in [IO.Directory]::EnumerateFileSystemEntries($pending.Pop())) {
      $attributes=Get-ArchiveAttributes $entry
      if($attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Leak scan refuses reparse entry' }
      if($attributes -band [IO.FileAttributes]::Directory) { $pending.Push($entry) }
      else { if([CheckoutScan]::Contains($entry,$roots)) { throw "Checkout leak detected: $entry" }; $count++ }
    }
  }
  "SOURCE_DIST_SCAN_OK files=$count unbounded=1 binary=1"
}
if($Mode -eq 'VerifyArchive') {
  Import-PathValidator
  $archivePath=Assert-ArchivePath $Archive 'file'
  $null=Assert-ArchivePath $Directory 'directory'
  $expected=@{}
  foreach($line in [IO.File]::ReadAllLines($Snapshot)) {
    $fields=$line.Split('|'); if($fields.Count -ne 2 -or $expected.ContainsKey($fields[0])) { throw 'Invalid independent snapshot' }
    $expected.Add($fields[0],$fields[1])
  }
  $seen=@{}; $file=[IO.File]::OpenRead($archivePath)
  $gzip=New-Object IO.Compression.GZipStream($file,[IO.Compression.CompressionMode]::Decompress)
  function Read-Exact([byte[]]$Buffer,[int]$Length) {
    for($offset=0;$offset -lt $Length;) { $n=$gzip.Read($Buffer,$offset,$Length-$offset); if(-not $n) { throw 'Truncated source archive' }; $offset+=$n }
  }
  try {
    $header=New-Object byte[] 512; $buffer=New-Object byte[] 65536
    while($true) {
      Read-Exact $header 512
      if(($header | Where-Object {$_ -ne 0}).Count -eq 0) {
        # All trailing uncompressed bytes must be zero; no concatenated hidden entries.
        while(($n=$gzip.Read($buffer,0,$buffer.Length)) -ne 0) { for($i=0;$i -lt $n;$i++) { if($buffer[$i]) { throw 'Unexpected data after tar terminator' } } }
        break
      }
      $sum=0; for($i=0;$i -lt 512;$i++) { $sum+= $(if($i -ge 148 -and $i -lt 156) {32} else {$header[$i]}) }
      $stored=[Convert]::ToInt64([Text.Encoding]::ASCII.GetString($header,148,8).Trim([char]0,' '),8)
      if($sum -ne $stored) { throw 'Bad tar checksum' }
      $name=[Text.Encoding]::ASCII.GetString($header,0,100).TrimEnd([char]0)
      $prefix=[Text.Encoding]::ASCII.GetString($header,345,155).TrimEnd([char]0)
      if($prefix) { $name="$prefix/$name" }
      if($header[156] -ne 48 -and $header[156] -ne 0) { throw 'Archive contains nonregular entry' }
      if($name -notmatch '^pure-audio-0\.6/([A-Za-z0-9_+./-]+)$') { throw 'Unexpected archive root/name' }
      $relative=$Matches[1]
      if(-not $expected.ContainsKey($relative) -or $seen.ContainsKey($relative)) { throw "Unexpected/duplicate archive input: $relative" }
      $seen.Add($relative,$true)
      $size=[Convert]::ToInt64([Text.Encoding]::ASCII.GetString($header,124,12).Trim([char]0,' '),8)
      $hash=[Security.Cryptography.SHA256]::Create()
      try {
        for($left=$size;$left -gt 0;) { $n=[int][Math]::Min($left,$buffer.Length); Read-Exact $buffer $n; $null=$hash.TransformBlock($buffer,0,$n,$null,0); $left-=$n }
        $null=$hash.TransformFinalBlock($buffer,0,0)
        $actual=[BitConverter]::ToString($hash.Hash).Replace('-','').ToLowerInvariant()
      } finally { $hash.Dispose() }
      if($actual -cne $expected[$relative]) { throw "Archive hash mismatch: $relative" }
      $padding=[int]((512-($size%512))%512); if($padding) { Read-Exact $buffer $padding }
    }
  } finally { $gzip.Dispose(); $file.Dispose() }
  if($seen.Count -ne $expected.Count) { throw 'Omitted archive input' }
  "SOURCE_DIST_CONTENT_OK files=$($seen.Count) hashes=$($seen.Count)"
}
if($Mode -eq 'Isolate') {
  $handles=New-Object 'Collections.Generic.List[IDisposable]'
  $names=[IO.File]::ReadAllLines($Snapshot) | ForEach-Object {$_.Split('|')[0]}
  try {
    foreach($root in $Forbidden.Split('|')) {
      foreach($name in $names) { $handles.Add([IO.File]::Open((Join-Path $root $name),'Open','Read','None')) }
      $blocked=$false
      try { $probe=[IO.File]::OpenRead((Join-Path $root 'Makefile')); $probe.Dispose() }
      catch [IO.IOException] { if(($_.Exception.HResult -band 65535) -ne 32) { throw }; $blocked=$true }
      if(-not $blocked) { throw 'Checkout read-exclusion probe failed' }
    }
    # Every relevant checkout input is held unavailable for the entire child.
    # Arguments carry forbidden roots only in memory, never a generated cache.
    $arguments=@("-DWORK=$Work","-DEXTRACTED_BUILD=$BuildDirectory","-DCLANG64_PREFIX=$ClangPrefix","-DPURE_PREFIX=$PurePrefix",
      "-DFORBIDDEN=$Forbidden",'-P',"$Directory/tests/source_dist_extracted.cmake")
    if(($arguments | Where-Object {$_ -match '["\r\n]'}).Count) { throw 'Invalid isolated argument' }
    $quoted=($arguments | ForEach-Object {'"'+$_+'"'}) -join ' '
    $info=New-Object Diagnostics.ProcessStartInfo
    $info.FileName=$CMake; $info.Arguments=$quoted; $info.WorkingDirectory=$Directory
    $info.UseShellExecute=$false; $info.CreateNoWindow=$true
    $info.RedirectStandardOutput=$true; $info.RedirectStandardError=$true
    $stdout=[IO.File]::Open("$Work/isolated.stdout",'CreateNew','Write','Read')
    $stderr=[IO.File]::Open("$Work/isolated.stderr",'CreateNew','Write','Read')
    $process=New-Object Diagnostics.Process; $process.StartInfo=$info
    try {
      if(-not $process.Start()) { throw 'Cannot launch extracted-source child' }
      $outCopy=$process.StandardOutput.BaseStream.CopyToAsync($stdout)
      $errCopy=$process.StandardError.BaseStream.CopyToAsync($stderr)
      $process.WaitForExit(); $outCopy.Wait(); $errCopy.Wait()
      if($process.ExitCode -ne 0) { throw "Extracted-source child failed: $($process.ExitCode); see isolated.stdout/stderr" }
    } finally { $stdout.Dispose(); $stderr.Dispose(); $process.Dispose() }
    "SOURCE_DIST_ISOLATION_OK held=$($handles.Count) roots=$($Forbidden.Split('|').Count) denied_read=1"
  } finally { foreach($handle in $handles) { $handle.Dispose() } }
  foreach($root in $Forbidden.Split('|')) { $probe=[IO.File]::OpenRead((Join-Path $root 'Makefile')); $probe.Dispose() }
  # Also scan the isolated driver's complete captures and generated preset,
  # after the native child has exited and both raw stream copies are complete.
  foreach($name in @('isolated.stdout','isolated.stderr','strict.cmake')) {
    [IO.File]::Copy((Join-Path $Work $name),(Join-Path "$Work/logs" $name),$false)
  }
  & C:/Windows/System32/WindowsPowerShell/v1.0/powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $PSCommandPath -Mode Scan -Directory "$Work/logs" -Forbidden $Forbidden -SourceTools "$Directory/cmake/SourceArchiveTools.ps1"
  if($LASTEXITCODE -ne 0) { throw 'Final isolated output/preset leak scan failed' }
  'SOURCE_DIST_ISOLATION_RELEASED_OK'
}

if($Mode -eq 'Attributes') {
  # Non-production seam: load only the real validation function declarations
  # from their AST, without executing the producer's CLI or adding a public
  # helpers-only/attribute-override switch to it.
  $tokens=$null; $parseErrors=$null
  $ast=[Management.Automation.Language.Parser]::ParseFile($SourceTools,[ref]$tokens,[ref]$parseErrors)
  if($parseErrors.Count) { throw 'Cannot parse actual archive path validator' }
  foreach($definition in $ast.FindAll({param($node)
      $node -is [Management.Automation.Language.FunctionDefinitionAst] -and
      $node.Name -in @('Assert-ArchivePath','Get-ArchiveAttributes')},$false)) {
    Invoke-Expression $definition.Extent.Text
  }
  $fixture=[IO.Path]::GetFullPath("$Directory/injected-file.bin")
  $stream=[IO.File]::Open($fixture,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
  $stream.WriteByte(65); $stream.Dispose()
  $actual=Assert-ArchivePath $fixture 'file'
  if($actual -cne $fixture) { throw 'Pristine actual path validation failed' }
  function Get-ArchiveAttributes([string]$Path) {
    $attributes=[IO.File]::GetAttributes($Path)
    if($Path -ieq $fixture) { $attributes=$attributes -bor [IO.FileAttributes]::ReparsePoint }
    return $attributes
  }
  $rejected=$false
  try { $null=Assert-ArchivePath $fixture 'file' }
  catch { if("$_" -notmatch 'Archive reparse component') { throw }; $rejected=$true }
  if(-not $rejected) { throw 'RED: file reparse attribute bypassed the actual path validator' }
  'SOURCE_DIST_ATTRIBUTE_OK negatives=1 controls=1 injected_file_reparse=1'
}
