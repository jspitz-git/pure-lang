param([ValidateSet('','Create','Workflow','Scan')][string]$Mode='',
      [string]$SourceDir, [string]$OutputDir, [string]$Manifest,
      [string]$DistRoot, [string]$Clang64Prefix, [string]$PurePrefix,
      [string]$CheckoutPath)
$ErrorActionPreference='Stop'

function Assert-SourcePath([string]$Path,[bool]$Directory=$false) {
 if(-not [IO.Path]::IsPathRooted($Path) -or $Path -match '[;|\r\n]' -or $Path.StartsWith('\\')) { throw 'source path must be a local absolute path' }
 $full=[IO.Path]::GetFullPath($Path)
 $item=Get-Item -LiteralPath $full -Force -ErrorAction Stop
 if([bool]$item.PSIsContainer -ne $Directory) { throw "source path is not a regular $(if($Directory){'directory'}else{'file'}): $full" }
 for($part=$full; $part; $part=[IO.Path]::GetDirectoryName($part)) {
  $attributes=[IO.File]::GetAttributes($part)
  if(($attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or ($attributes -band [IO.FileAttributes]::Device) -ne 0) { throw "source reparse/device path rejected: $part" }
 }
 return $full.TrimEnd('\','/')
}
function Get-SourceHash([string]$Path) {
 $sha=[Security.Cryptography.SHA256]::Create(); $stream=[IO.File]::OpenRead($Path)
 try { return [BitConverter]::ToString($sha.ComputeHash($stream)).Replace('-','').ToLowerInvariant() }
 finally { $stream.Dispose(); $sha.Dispose() }
}
function Get-SourceNames([string]$Declaration) {
 $names=$Declaration.Split('|'); $seen=New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
 foreach($name in $names) {
  if($name -notmatch '^[A-Za-z0-9_+.-]+(/[A-Za-z0-9_+.-]+)*$' -or
     $name -match '(^|/)\.{1,2}(/|$)|[.](/|$)|(^|/)(con|prn|aux|nul|com[0-9]|lpt[0-9])([./]|$)' -or
     $name -match '(^|/)(\.git|\.svn|\.cache|CMakeFiles|build|cache)(/|$)|\.(dll|exe|o|obj|a|tar|gz|tmp|log)$|(^|/)CMakeCache[.]txt$' -or
     -not $seen.Add($name)) { throw "source manifest invalid or generated input: $name" }
 }
 [Array]::Sort($names,[StringComparer]::Ordinal)
 return ,$names
}
function New-SourceLeaf([string]$Root) {
 $Root=[IO.Path]::GetFullPath($Root)
 # Only an immediate child of an existing canonical parent may become the fixed
 # contract root. Every cleanup later proves that exact root/leaf relationship.
 if(-not [IO.Directory]::Exists($Root)) {
  Assert-SourcePath ([IO.Path]::GetDirectoryName($Root)) $true | Out-Null
  [IO.Directory]::CreateDirectory($Root) | Out-Null
 }
 $Root=Assert-SourcePath $Root $true
 $rng=[Security.Cryptography.RandomNumberGenerator]::Create(); $random=New-Object byte[] 32
 try { $rng.GetBytes($random) } finally { $rng.Dispose() }
 $nonce=[BitConverter]::ToString($random).Replace('-','').ToLowerInvariant()
 # Short directory identity leaves room for unchanged native runner contracts.
 $path=Join-Path $Root ('s'+$nonce.Substring(0,12))
 if([IO.Directory]::Exists($path) -or [IO.File]::Exists($path)) { throw 'source owned leaf collision' }
 [IO.Directory]::CreateDirectory($path) | Out-Null
 $marker=[IO.File]::Open("$path/.source-owner",[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
 try { $bytes=[Text.Encoding]::ASCII.GetBytes($nonce); $marker.Write($bytes,0,$bytes.Length) } finally { $marker.Dispose() }
 return @{Path=$path.Replace('\','/');Nonce=$nonce}
}
function Get-RegularSourceTree([string]$Root) {
 $Root=Assert-SourcePath $Root $true
 $pending=New-Object 'Collections.Generic.Stack[string]'; $pending.Push($Root)
 $files=New-Object 'Collections.Generic.List[string]'
 while($pending.Count) {
  foreach($item in Get-ChildItem -LiteralPath $pending.Pop() -Force) {
   Assert-SourcePath $item.FullName ([bool]$item.PSIsContainer) | Out-Null
   if($item.PSIsContainer) { $pending.Push($item.FullName) } else { $files.Add($item.FullName) }
  }
 }
 return ,$files.ToArray()
}
function Remove-SourceLeaf([string]$Root,[string]$Leaf,[string]$Nonce) {
 $Root=Assert-SourcePath $Root $true; $Leaf=Assert-SourcePath $Leaf $true
 if([IO.Path]::GetDirectoryName($Leaf) -cne $Root -or [IO.Path]::GetFileName($Leaf) -notmatch '^s[a-f0-9]{12}$' -or
    $Nonce -cnotmatch '^[a-f0-9]{64}$') { throw 'source cleanup ownership scope rejected' }
 $marker=Assert-SourcePath "$Leaf/.source-owner"
 if([IO.File]::ReadAllText($marker) -cne $Nonce) { throw 'source cleanup ownership sentinel rejected' }
 # Preflight the complete tree before removing anything. Revalidate each exact
 # endpoint; no recursive Delete or Remove-Item, wildcard, or caller leaf escape.
 $files=Get-RegularSourceTree $Leaf
 $directories=@(Get-ChildItem -LiteralPath $Leaf -Directory -Recurse -Force | ForEach-Object { $_.FullName })
 foreach($file in $files) { if($file -cne $marker) { Assert-SourcePath $file | Out-Null; [IO.File]::Delete($file) } }
 foreach($directory in ($directories | Sort-Object Length -Descending)) { Assert-SourcePath $directory $true | Out-Null; [IO.Directory]::Delete($directory,$false) }
 Assert-SourcePath $marker | Out-Null; [IO.File]::Delete($marker); [IO.Directory]::Delete($Leaf,$false)
}

if(-not ('MidiSourceArchive' -as [type])) {
 Add-Type -TypeDefinition @'
using System;
using System.IO;
using System.IO.Compression;
using System.Text;
using System.Collections.Generic;
using System.Security.Cryptography;
public static class MidiSourceArchive {
 static void PublicationIO(Action operation) {
  for(int attempt=0;;attempt++) {
   try {
    operation();
    return;
   } catch(IOException error) {
    int code=error.HResult & 0xffff;
    // A scanner/reader may briefly deny the atomic replacement. Retry only
    // sharing/lock and unable-to-remove-replaced errors for at most 5 seconds;
    // persistent locks, permission failures and all other errors fail closed.
    if(attempt==100 || (code!=32 && code!=33 && code!=1175)) throw;
    System.Threading.Thread.Sleep(50);
   }
  }
 }
 public static void Publish(string source,string destination) {
  PublicationIO(delegate() {
   if(File.Exists(destination)) File.Replace(source,destination,null);
   else File.Move(source,destination);
  });
 }
 public static void RemovePublished(string path) { PublicationIO(delegate() { File.Delete(path); }); }
 public static string Hash(byte[] bytes) { using(var h=SHA256.Create()) return BitConverter.ToString(h.ComputeHash(bytes)).Replace("-", "").ToLowerInvariant(); }
 static void Text(byte[] h,int offset,int length,string text) {
  byte[] bytes=Encoding.ASCII.GetBytes(text);
  if(bytes.Length>length) throw new Exception("archive field overflow");
  Array.Copy(bytes,0,h,offset,bytes.Length);
 }
 static void Octal(byte[] h,int offset,int length,long n) { Text(h,offset,length,Convert.ToString(n,8).PadLeft(length-1,'0')+"\0"); }
 static byte[] Header(string name,long size) {
  byte[] h=new byte[512]; Text(h,0,100,"pure-midi-0.6/"+name);
  Octal(h,100,8,name=="debian/rules"?493:420); Octal(h,108,8,0); Octal(h,116,8,0);
  Octal(h,124,12,size); Octal(h,136,12,0); h[156]=(byte)'0';
  Text(h,257,6,"ustar\0"); Text(h,263,2,"00");
  for(int i=148;i<156;i++) h[i]=32;
  int sum=0; foreach(byte b in h) sum+=b;
  Text(h,148,8,Convert.ToString(sum,8).PadLeft(6,'0')+"\0 "); return h;
 }
 public static byte[] Compress(byte[] bytes) {
  using(var output=new MemoryStream()) {
   using(var gz=new GZipStream(output,CompressionLevel.Optimal,true)) gz.Write(bytes,0,bytes.Length);
   byte[] result=output.ToArray();
   byte[] fixedHeader={31,139,8,0,0,0,0,0,0,255}; Array.Copy(fixedHeader,result,10); return result;
  }
 }
 public static byte[] Create(string root,string[] names) {
  using(var tar=new MemoryStream()) {
   foreach(string name in names) {
    byte[] payload=File.ReadAllBytes(Path.Combine(root,name)); byte[] h=Header(name,payload.Length);
    tar.Write(h,0,h.Length); tar.Write(payload,0,payload.Length);
    int pad=(512-payload.Length%512)%512; tar.Write(new byte[pad],0,pad);
   }
   tar.Write(new byte[1024],0,1024); return Compress(tar.ToArray());
  }
 }
 public static Dictionary<string,byte[]> Read(string path,string[] rows) {
  byte[] packed=File.ReadAllBytes(path), fixedHeader={31,139,8,0,0,0,0,0,0,255};
  if(packed.Length<18) throw new Exception("archive truncated gzip");
  for(int i=0;i<10;i++) if(packed[i]!=fixedHeader[i]) throw new Exception("archive nondeterministic gzip header");
  long expectedLength=1024;
  foreach(string row in rows) { string[] f=row.Split('|'); expectedLength+=512+((long.Parse(f[2])+511)/512)*512; }
  if(expectedLength>128*1024*1024) throw new Exception("archive manifest exceeds source size bound");
  byte[] bytes;
  using(var input=new MemoryStream(packed)) using(var gz=new GZipStream(input,CompressionMode.Decompress)) using(var output=new MemoryStream()) {
   byte[] buffer=new byte[65536]; int n;
   while((n=gz.Read(buffer,0,buffer.Length))!=0) { if(output.Length+n>expectedLength) throw new Exception("archive extra files or data"); output.Write(buffer,0,n); }
   bytes=output.ToArray();
  }
  if(bytes.Length!=expectedLength) throw new Exception("archive missing files or terminator");
  byte[] canonical=Compress(bytes);
  if(canonical.Length!=packed.Length) throw new Exception("archive noncanonical gzip bytes");
  for(int i=0;i<packed.Length;i++) if(packed[i]!=canonical[i]) throw new Exception("archive noncanonical gzip bytes");
  var result=new Dictionary<string,byte[]>(StringComparer.Ordinal); int pos=0;
  foreach(string row in rows) {
   string[] f=row.Split('|'); int size=int.Parse(f[2]); byte[] header=Header(f[0],size);
   for(int i=0;i<512;i++) if(bytes[pos+i]!=header[i]) throw new Exception("archive metadata/order/path mismatch: "+f[0]);
   pos+=512; byte[] payload=new byte[size]; Array.Copy(bytes,pos,payload,0,size);
   if(Hash(payload)!=f[3]) throw new Exception("archive payload hash mismatch: "+f[0]);
   pos+=size; int pad=(512-size%512)%512;
   for(int i=0;i<pad;i++) if(bytes[pos+i]!=0) throw new Exception("archive nonzero payload padding");
   pos+=pad; result.Add(f[0],payload);
  }
  for(;pos<bytes.Length;pos++) if(bytes[pos]!=0) throw new Exception("archive trailing data");
  return result;
 }
 // Byte windows preserve overlap for UTF-8 and UTF-16LE/BE paths, including
 // arbitrarily large logs/binaries. Slash variants and ordinal Windows case fold
 // are checked without loading entire files or imposing a 9 MiB scan ceiling.
 public static void Scan(string path,string checkout) {
  string[] needles={checkout.Replace('\\','/'),checkout.Replace('/','\\'),checkout.Replace('/','\\').Replace("\\","\\\\")};
  int overlap=0; foreach(string n in needles) overlap=Math.Max(overlap,n.Length*4+4);
  byte[] buf=new byte[65536+overlap]; int kept=0;
  using(var stream=File.OpenRead(path)) {
   int read;
   while((read=stream.Read(buf,kept,65536))>0) {
    int total=kept+read;
    foreach(Encoding encoding in new[]{Encoding.UTF8,Encoding.Unicode,Encoding.BigEndianUnicode})
     for(int alignment=0;alignment<(encoding==Encoding.UTF8?1:2);alignment++) {
      string text=encoding.GetString(buf,alignment,total-alignment);
      foreach(string needle in needles)
       if(text.IndexOf(needle,StringComparison.OrdinalIgnoreCase)>=0) throw new Exception("checkout path leak: "+path);
     }
    kept=Math.Min(overlap,total); Array.Copy(buf,total-kept,buf,0,kept);
   }
  }
 }
}
'@
}
function Get-SourceRows([string[]]$Rows) {
 $names=New-Object 'Collections.Generic.List[string]'
 foreach($row in $Rows) {
  if($row -cnotmatch '^([^|]+)\|f\|(0|[1-9][0-9]*)\|([a-f0-9]{64})$') { throw 'source manifest malformed row' }
  $names.Add($Matches[1])
 }
 $sorted=Get-SourceNames ($names -join '|')
 if(($sorted -join '|') -cne ($names -join '|')) { throw 'source manifest not ordered' }
 return ,$Rows
}
function Publish-SourcePair([string]$Temporary,[string]$ManifestTemp,[string]$Output) {
 $Output=Assert-SourcePath $Output $true
 $destinations=@("$Output/pure-midi-0.6.tar.gz","$Output/pure-midi-0.6.manifest.tsv")
 $marker="$Output/.source-recovery"
 # Serialize cooperating publishers without a persistent lock-file or unsafe
 # lock-file unlink. This is not hostile same-user or power-loss atomicity.
 $identity=[MidiSourceArchive]::Hash([Text.Encoding]::UTF8.GetBytes($Output.ToUpperInvariant()))
 $mutex=New-Object Threading.Mutex($false,"Local\PureMidiSourcePair-$identity")
 $acquired=$false; $keepRecovery=$false; $markerOwned=$false
 $backups=New-Object 'Collections.Generic.List[string]'
 try {
  try { $acquired=$mutex.WaitOne(30000) } catch [Threading.AbandonedMutexException] { $acquired=$true }
  if(-not $acquired) { throw 'source pair publication already active' }
  if(Test-Path -LiteralPath $marker) { Assert-SourcePath $marker | Out-Null; throw "source pair recovery required at $marker; previous evidence retained" }
  foreach($destination in $destinations) { if(Test-Path -LiteralPath $destination) { Assert-SourcePath $destination | Out-Null } }
  $present=[IO.File]::Exists($destinations[0])
  if($present -ne [IO.File]::Exists($destinations[1])) { throw 'source pair recovery required: incomplete previous archive/manifest pair' }
  $oldHashes=@(); $snapshotHandles=New-Object 'Collections.Generic.List[IO.FileStream]'
  try {
   if($present) {
    foreach($destination in $destinations) { $snapshotHandles.Add([IO.File]::Open($destination,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)) }
    $previousRows=Get-SourceRows ([IO.File]::ReadAllLines($destinations[1]))
    try { Read-SourceArchive $destinations[0] $previousRows | Out-Null }
    catch { throw "source pair recovery required: mismatched previous archive/manifest pair: $($_.Exception.Message)" }
    $token=[Guid]::NewGuid().ToString('N')
    for($index=0;$index -lt 2;$index++) {
     $bytes=[IO.File]::ReadAllBytes($destinations[$index]); $oldHashes+=,[MidiSourceArchive]::Hash($bytes)
     $backup="$Output/.source-$token.previous-$index.tmp"
     $saved=[IO.File]::Open($backup,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
     $backups.Add($backup)
     try { $saved.Write($bytes,0,$bytes.Length) } finally { $saved.Dispose() }
    }
   }
  } finally { foreach($handle in $snapshotHandles) { $handle.Dispose() } }
  # A marker is published before either replacement. Failed rollback preserves
  # it and the old bytes, and subsequent cooperating calls refuse to proceed.
  $journal=[IO.File]::Open($marker,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
  $markerOwned=$true
  try {
   $record=if($present) { "prior=pair`narchive=$([IO.Path]::GetFileName($backups[0]))`nmanifest=$([IO.Path]::GetFileName($backups[1]))`n" } else { "prior=absent`n" }
   $bytes=[Text.Encoding]::UTF8.GetBytes($record); $journal.Write($bytes,0,$bytes.Length)
  } finally { $journal.Dispose() }
  try {
   [MidiSourceArchive]::Publish($Temporary,$destinations[0])
   [MidiSourceArchive]::Publish($ManifestTemp,$destinations[1])
  } catch {
   $publicationError=$_.Exception.Message
   try {
    for($index=1;$index -ge 0;$index--) {
     if(Test-Path -LiteralPath $destinations[$index]) { Assert-SourcePath $destinations[$index] | Out-Null }
     if($present) {
      # Inspect actual bytes after failure instead of assuming a failed OS call
      # had no side effect. Unchanged locked destinations need no replacement.
      if(-not [IO.File]::Exists($destinations[$index]) -or (Get-SourceHash $destinations[$index]) -cne $oldHashes[$index]) {
       Assert-SourcePath $backups[$index] | Out-Null
       [MidiSourceArchive]::Publish($backups[$index],$destinations[$index])
      }
      if((Get-SourceHash $destinations[$index]) -cne $oldHashes[$index]) { throw 'restored artifact hash mismatch' }
     } elseif([IO.File]::Exists($destinations[$index])) { [MidiSourceArchive]::RemovePublished($destinations[$index]) }
    }
   } catch {
    $keepRecovery=$true
    throw "source pair publication failed; recovery required at $marker; publication: $publicationError; rollback: $($_.Exception.Message)"
   }
   $restored=if($present) { 'pair' } else { 'absence' }
   throw "source pair publication failed; previous $restored restored: $publicationError"
  }
 } finally {
  try {
   if(-not $keepRecovery) {
    try {
     foreach($backup in $backups) { if([IO.File]::Exists($backup)) { Assert-SourcePath $backup | Out-Null; [MidiSourceArchive]::RemovePublished($backup) } }
     if($markerOwned) { Assert-SourcePath $marker | Out-Null; [MidiSourceArchive]::RemovePublished($marker) }
    } catch { throw "source pair recovery required at $marker; cleanup failed: $($_.Exception.Message)" }
   }
  } finally { if($acquired) { $mutex.ReleaseMutex() }; $mutex.Dispose() }
 }
}
function New-SourceArchive([string]$Root,[string]$Output,[string]$Declaration) {
 $Root=Assert-SourcePath $Root $true; $Output=Assert-SourcePath $Output $true
 $names=Get-SourceNames $Declaration; $rows=New-Object 'Collections.Generic.List[string]'
 $handles=New-Object 'Collections.Generic.List[IO.FileStream]'
 try {
  foreach($name in $names) {
   $path=Assert-SourcePath "$Root/$name"
   # Retain files against replacement/writes while their hashes and bytes form
   # the archive. Cooperative callers cannot change one between these reads.
   $handles.Add([IO.File]::Open($path,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read))
   $rows.Add("$name|f|$((Get-Item -LiteralPath $path).Length)|$(Get-SourceHash $path)")
  }
  $bytes=[MidiSourceArchive]::Create($Root,$names)
  $token=[Guid]::NewGuid().ToString('N'); $temporary="$Output/.source-$token.tmp"
  $stream=[IO.File]::Open($temporary,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
  try { $stream.Write($bytes,0,$bytes.Length) } finally { $stream.Dispose() }
  try {
   [MidiSourceArchive]::Read($temporary,$rows.ToArray()) | Out-Null
   # The pair coordinator snapshots and restores old bytes on publication
   # failure. All backup/temp cleanup remains exact and non-recursive.
   $manifestTemp="$Output/.manifest-$token.tmp"
   $m=[IO.File]::Open($manifestTemp,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
   try { $content=[Text.Encoding]::UTF8.GetBytes(($rows -join "`n")+"`n"); $m.Write($content,0,$content.Length) } finally { $m.Dispose() }
   try {
    Publish-SourcePair $temporary $manifestTemp $Output
   } finally { if([IO.File]::Exists($manifestTemp)) { Assert-SourcePath $manifestTemp | Out-Null; [MidiSourceArchive]::RemovePublished($manifestTemp) } }
  } finally { if([IO.File]::Exists($temporary)) { Assert-SourcePath $temporary | Out-Null; [MidiSourceArchive]::RemovePublished($temporary) } }
  "SOURCE_ARCHIVE_OK files=$($names.Count) sha256=$([MidiSourceArchive]::Hash($bytes)) archive=$Output/pure-midi-0.6.tar.gz"
 } finally { foreach($handle in $handles) { $handle.Dispose() } }
}
function Read-SourceArchive([string]$Archive,[string[]]$Rows) {
 Assert-SourcePath $Archive | Out-Null; $Rows=Get-SourceRows $Rows
 return [MidiSourceArchive]::Read($Archive,$Rows)
}
function Test-SourceTree([string]$Root,[string[]]$Rows) {
 $Root=(Assert-SourcePath $Root $true).Replace('\','/'); $Rows=Get-SourceRows $Rows
 $files=Get-RegularSourceTree $Root
 if($files.Count -ne $Rows.Count) { throw 'exact source tree file count mismatch' }
 foreach($row in $Rows) {
  $f=$row.Split('|'); $path=Assert-SourcePath "$Root/$($f[0])"
  if((Get-Item -LiteralPath $path).Length -ne [long]$f[2] -or (Get-SourceHash $path) -cne $f[3]) { throw 'source tree manifest hash mismatch' }
 }
}
function Expand-SourceArchive([string]$Archive,[string[]]$Rows,[string]$Destination) {
 $entries=Read-SourceArchive $Archive $Rows
 if(Test-Path -LiteralPath $Destination) { throw 'source extraction destination must be absent' }
 Assert-SourcePath ([IO.Path]::GetDirectoryName($Destination)) $true | Out-Null
 [IO.Directory]::CreateDirectory("$Destination/pure-midi-0.6") | Out-Null
 foreach($row in $Rows) {
  $name=$row.Split('|')[0]; $path="$Destination/pure-midi-0.6/$name"
  [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($path)) | Out-Null
  Assert-SourcePath ([IO.Path]::GetDirectoryName($path)) $true | Out-Null
  $stream=[IO.File]::Open($path,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
  try { $bytes=$entries[$name]; $stream.Write($bytes,0,$bytes.Length) } finally { $stream.Dispose() }
 }
 Test-SourceTree "$Destination/pure-midi-0.6" $Rows
}
function Test-CheckoutLeaks([string]$Root,[string]$Checkout) {
 if(-not [IO.Path]::IsPathRooted($Checkout) -or $Checkout.Length -lt 8) { throw 'leak scan requires the absolute checkout path' }
 $files=Get-RegularSourceTree $Root
 foreach($file in $files) { [MidiSourceArchive]::Scan($file,$Checkout.TrimEnd('\','/')) }
 "SOURCE_LEAK_SCAN_OK files=$($files.Count) encodings=UTF8,UTF16LE,UTF16BE case_insensitive=1 full_length=1 overlap=1"
}
function Remove-SourceRunnerFixtures([string]$Root,[string]$Leaf,[string]$Nonce) {
 $Root=Assert-SourcePath $Root $true; $Leaf=Assert-SourcePath $Leaf $true
 if([IO.Path]::GetDirectoryName($Leaf) -cne $Root -or [IO.Path]::GetFileName($Leaf) -notmatch '^s[a-f0-9]{12}$' -or
    $Nonce -cnotmatch '^[a-f0-9]{64}$' -or [IO.File]::ReadAllText((Assert-SourcePath "$Leaf/.source-owner")) -cne $Nonce) { throw 'source fixture cleanup ownership rejected' }
 $contract=Assert-SourcePath "$Leaf/b/pure-midi-contract-root" $true
 $fixtures=Assert-SourcePath "$contract/fixtures" $true
 $pristine=Assert-SourcePath "$fixtures/pristine.pure"
 $before=Get-SourceHash $pristine; $count=0
 foreach($record in @(@('fixtures-junction',$fixtures,'Junction'),@('script-symlink.pure',$pristine,'SymbolicLink'))) {
  $path="$contract/$($record[0])"
  $item=Get-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
  if($null -eq $item) { continue }
  if(($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0 -or $item.LinkType -cne $record[2]) { throw 'source fixture reparse type mismatch' }
  $targets=@($item.Target)
  if($targets.Count -ne 1 -or -not [string]::Equals([IO.Path]::GetFullPath($targets[0]),$record[1],[StringComparison]::OrdinalIgnoreCase)) { throw 'source fixture target mismatch' }
  # These exact two names belong to Task4's retained test fixtures under our
  # nonce-owned build. Unlink only the entry, preserving the regular targets.
  if($item.PSIsContainer) { [IO.Directory]::Delete($path,$false) } else { [IO.File]::Delete($path) }
  $count++
 }
 if((Get-SourceHash $pristine) -cne $before) { throw 'source fixture target changed' }
 "SOURCE_RUNNER_FIXTURES_UNLINKED count=$count"
}
function Invoke-SourceWorkflow {
 $SourceDir=Assert-SourcePath $SourceDir $true
 $owned=New-SourceLeaf $DistRoot; $work=$owned.Path; $nonce=$owned.Nonce
 "SOURCE_WORKFLOW_WORK=$work nonce=$nonce"
 & "$Clang64Prefix/bin/mingw32-make.exe" -C $SourceDir dist 'DLL=.dll' "CMAKE=$Clang64Prefix/bin/cmake.exe" "DIST_DIR=$work"
 if($LASTEXITCODE -ne 0) { throw 'first public source archive failed' }
 $archive="$work/pure-midi-0.6.tar.gz"; $rows=[IO.File]::ReadAllLines("$work/pure-midi-0.6.manifest.tsv")
 $first=Get-SourceHash $archive
 & "$Clang64Prefix/bin/mingw32-make.exe" -C $SourceDir dist 'DLL=.dll' "CMAKE=$Clang64Prefix/bin/cmake.exe" "DIST_DIR=$work"
 if($LASTEXITCODE -ne 0) { throw 'second public source archive failed' }
 if((Get-SourceHash $archive) -cne $first) { throw 'source workflow archive reproducibility failed' }
 Expand-SourceArchive $archive $rows "$work/source with spaces"
 $extracted="$work/source with spaces/pure-midi-0.6"
 # Deny access to every checkout input while the extracted driver configures,
 # builds, tests and installs. This includes this running script and its driver.
 $locks=New-Object 'Collections.Generic.List[IO.FileStream]'
 try {
  foreach($row in $rows) { $locks.Add([IO.File]::Open("$SourceDir/$($row.Split('|')[0])",[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::None)) }
  foreach($rel in @('cmake/SourceWorkflow.cmake','cmake/SourceArchiveTools.ps1','CMakeLists.txt','tests/run_pure_test.c')) {
   $denied=$false
   try { $probe=[IO.File]::OpenRead("$SourceDir/$rel"); $probe.Dispose() } catch [IO.IOException] { $denied=$true }
   if(-not $denied) { throw 'checkout helper denial failed' }
  }
  "SOURCE_CHECKOUT_DENIED files=$($locks.Count) driver_probes=4"
  $saved=Get-Location; Set-Location -LiteralPath $extracted
  try {
   & "$Clang64Prefix/bin/cmake.exe" -DEXTRACTED_SOURCE_WORKFLOW=ON "-DSOURCE_DIR=$extracted" "-DWORK_DIR=$work" "-DCLANG64_PREFIX=$Clang64Prefix" "-DPURE_PREFIX=$PurePrefix" -P "$extracted/cmake/SourceWorkflow.cmake"
   if($LASTEXITCODE -ne 0) { throw 'extracted-only configure/build/test/install workflow failed' }
  } finally { Set-Location -LiteralPath $saved }
  Remove-SourceRunnerFixtures $DistRoot $work $nonce
  Test-CheckoutLeaks $work $SourceDir
  Test-SourceTree $extracted $rows
 } finally { foreach($handle in $locks) { $handle.Dispose() } }
 "SOURCE_WORKFLOW_OK files=$($rows.Count) sha256=$first extracted=$extracted build=$work/b stage=$work/stage"
 # Retain the successful owned leaf and manifests for inspection. Cleanup is
 # explicit via Remove-SourceLeaf with the printed root, leaf and nonce.
}
if($Mode -eq 'Create') { New-SourceArchive $SourceDir $OutputDir $Manifest }
elseif($Mode -eq 'Workflow') { Invoke-SourceWorkflow }
elseif($Mode -eq 'Scan') { Test-CheckoutLeaks $OutputDir $CheckoutPath }
