param([Parameter(Mandatory=$true)][ValidateSet('clean','realclean','generate','dist','distcheck')][string]$Mode,
 [Parameter(Mandatory=$true)][string]$SourceRoot,
 [Parameter(Mandatory=$true)][string]$CMake,[string]$DistFiles,[string]$AuditBuild)
$ErrorActionPreference='Stop'
trap { [Console]::Error.WriteLine($_.Exception.GetBaseException().Message); exit 1 }
# The script location is the authority. No caller controls a deletion root,
# archive basename, recursive leaf, suffix expansion, or output inventory.
$taskSource=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
if($SourceRoot.Replace('/','\') -cne $taskSource) { throw 'Source root case/noncanonical alias' }
Add-Type -TypeDefinition @'
using System;
using System.IO;
using System.Text;
using System.Collections.Generic;
using System.Runtime.InteropServices;
public static class GlLegacyOwner {
 [StructLayout(LayoutKind.Sequential)] struct Info {
  public uint Attr; public System.Runtime.InteropServices.ComTypes.FILETIME Creation,Access,Write;
  public uint Volume,SizeHigh,SizeLow,Links,IndexHigh,IndexLow;
 }
 [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern IntPtr CreateFileW(string p,uint a,uint s,IntPtr sa,uint c,uint f,IntPtr t);
 [DllImport("kernel32.dll",SetLastError=true)] static extern bool GetFileInformationByHandle(IntPtr h,out Info i);
 [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern uint GetFinalPathNameByHandleW(IntPtr h,StringBuilder b,uint n,uint f);
 [DllImport("kernel32.dll",SetLastError=true)] static extern bool SetFileInformationByHandle(IntPtr h,int c,ref int data,uint n);
 [DllImport("kernel32.dll",SetLastError=true)] static extern bool SetFilePointerEx(IntPtr h,long d,out long p,uint m);
 [DllImport("kernel32.dll",SetLastError=true)] static extern bool ReadFile(IntPtr h,byte[] b,uint n,out uint got,IntPtr o);
 [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr h);
 static Dictionary<string,IntPtr> held=new Dictionary<string,IntPtr>(StringComparer.OrdinalIgnoreCase);
 static HashSet<string> directories=new HashSet<string>(StringComparer.OrdinalIgnoreCase);
 static void Fail(string s) { throw new IOException(s+" (Windows error "+Marshal.GetLastWin32Error()+")"); }
 static void Hold(string p,bool deleting) {
  if(held.ContainsKey(p)) return;
  IntPtr h=CreateFileW(p,0x80000000u|(deleting?0x10000u:0),1,IntPtr.Zero,3,0x02200000,IntPtr.Zero);
  if(h.ToInt64()==-1) Fail("Cannot retain owned path "+p);
  Info i; var final=new StringBuilder(32768);
  uint n=GetFinalPathNameByHandleW(h,final,32768,0);
  if(!GetFileInformationByHandle(h,out i)||(i.Attr&0x400)!=0||
    ((i.Attr&0x10)==0&&i.Links!=1)||n<4||n>=32768||final.ToString().Substring(4)!=p) {
   CloseHandle(h); Fail("reparse, hardlink or case alias: "+p);
  }
  held.Add(p,h); if((i.Attr&0x10)!=0) directories.Add(p);
 }
 public static void Ancestors(string p) {
  var chain=new Stack<string>();
  for(string q=p;q!=null&&q.Length>3;q=Path.GetDirectoryName(q)) chain.Push(q);
  while(chain.Count>0) Hold(chain.Pop(),false);
 }
 public static void Tree(string p) {
  Hold(p,true);
  if(!directories.Contains(p)) return;
  var seen=new HashSet<string>(StringComparer.OrdinalIgnoreCase);
  foreach(string child in Directory.GetFileSystemEntries(p)) {
   string name=Path.GetFileName(child);
   if(!seen.Add(name)) Fail("Case-folded duplicate: "+child);
   if(name.Equals(".git",StringComparison.OrdinalIgnoreCase)||name.Equals(".codex",StringComparison.OrdinalIgnoreCase)||
      name.Equals(".agents",StringComparison.OrdinalIgnoreCase)||name.Equals(".pure-gl-protected",StringComparison.OrdinalIgnoreCase))
     Fail("protected descendant: "+child);
   Tree(child);
  }
 }
 public static void FileOnly(string p) {
  if(held.ContainsKey(p)) {
   if(directories.Contains(p)) Fail("Expected regular package output: "+p);
   var final=new StringBuilder(32768); GetFinalPathNameByHandleW(held[p],final,32768,0);
   if(final.ToString().Substring(4)!=p) Fail("Case alias output: "+p);
  }
 }
 public static byte[] Read(string p) {
  FileOnly(p);
  if(!held.ContainsKey(p)||directories.Contains(p)) Fail("Missing regular source/sentinel: "+p);
  var output=new MemoryStream(); byte[] b=new byte[65536]; uint n; long at;
  if(!SetFilePointerEx(held[p],0,out at,0)) Fail("Cannot rewind owned file");
  for(;;) { if(!ReadFile(held[p],b,(uint)b.Length,out n,IntPtr.Zero)) Fail("Cannot read owned file");
   if(n==0) break; output.Write(b,0,(int)n); }
  return output.ToArray();
 }
 public static void DeleteFile(string p) {
  if(!held.ContainsKey(p)) return;
  int remove=1;
  if(!SetFileInformationByHandle(held[p],4,ref remove,4)) Fail("Owned deletion refused: "+p);
  CloseHandle(held[p]); held.Remove(p); directories.Remove(p);
 }
 public static void DeleteTree(string p) {
  var paths=new List<string>();
  foreach(string q in held.Keys) if(q==p||q.StartsWith(p+"\\",StringComparison.Ordinal)) paths.Add(q);
  paths.Sort((a,b)=>b.Length.CompareTo(a.Length));
  foreach(string q in paths) DeleteFile(q);
 }
 public static void CopyNew(string source,string destination) {
  byte[] bytes=Read(source);
  using(var f=new FileStream(destination,FileMode.CreateNew,FileAccess.Write,FileShare.None)) f.Write(bytes,0,bytes.Length);
 }
 public static void Close() { foreach(IntPtr h in held.Values) CloseHandle(h); held.Clear(); directories.Clear(); }
}
'@
$taskUtf8=New-Object Text.UTF8Encoding($false,$true)
$taskLeaf=Join-Path $taskSource '.pure-gl-dist'
$taskArchive=Join-Path $taskSource 'pure-gl-0.9.tar.gz'
$taskLeafOwner="pure-gl legacy dist leaf`nsource=$($taskSource.Replace('\','/'))`n"
function Assert-LeafOwner {
 $actual=$taskUtf8.GetString([GlLegacyOwner]::Read((Join-Path $taskLeaf '.pure-gl-owner')))
 if($actual -cne $taskLeafOwner) { throw 'Dist leaf sentinel mismatch' }
}
try {
 [GlLegacyOwner]::Ancestors($taskSource)
 [GlLegacyOwner]::Tree($taskSource)
 $taskOwner=$taskUtf8.GetString([GlLegacyOwner]::Read((Join-Path $taskSource '.pure-gl-source')))
 # Git text checkouts use LF or CRLF. Both have one exact, single-line record;
 # additional whitespace, extra records and altered contents are rejected.
 if($taskOwner -cne "pure-gl source 0.9`n" -and $taskOwner -cne "pure-gl source 0.9`r`n") { throw 'Source sentinel mismatch' }
 $taskOutputs=@('pure-gl.dll','pure-gl.so','pure-gl.dylib','pure-gl.a','pure-gl.dll.a','pure-gl-0.9.tar.gz')
 foreach($name in @('GL','GL_ARB','GL_EXT','GL_NV','GL_ATI','GLU','GLUT')) {
  $taskOutputs+=@("$name.o","$name.obj")
  if($Mode -eq 'realclean') { $taskOutputs+=@("$name.c","$name.pure") }
 }
 foreach($name in $taskOutputs) { [GlLegacyOwner]::FileOnly((Join-Path $taskSource $name)) }
 if(Test-Path -LiteralPath $taskLeaf) { Assert-LeafOwner }
 if($Mode -eq 'distcheck') {
  if(-not [IO.Path]::IsPathRooted($AuditBuild) -or -not (Test-Path -LiteralPath (Join-Path $AuditBuild 'CMakeCache.txt'))) {
   throw 'distcheck requires DIST_AUDIT_BUILD=<strict configured and built directory>'
  }
  $taskCache=[IO.File]::ReadAllText((Join-Path $AuditBuild 'CMakeCache.txt'))
  if($taskCache -notmatch '(?m)^PURE_GL_STRICT_AUDIT:BOOL=ON\r?$') { throw 'distcheck requires a strict audit build' }
  [GlLegacyOwner]::Close()
  & (Join-Path ([IO.Path]::GetDirectoryName($CMake)) 'ctest.exe') --test-dir $AuditBuild -R '^pure-gl-source-dist-contract$' --no-tests=error --output-on-failure
  if($LASTEXITCODE -ne 0) { throw 'Independent source distribution contract failed' }
 } elseif($Mode -eq 'dist') {
  $taskNames=@($DistFiles.Trim() -split '\s+')
  $taskSeen=New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
  foreach($name in $taskNames) {
   if($name -notmatch '^[A-Za-z0-9_+./-]+$' -or $name -match '^/|(^|/)\.\.(/|$)' -or -not $taskSeen.Add($name)) { throw "Invalid/duplicate release input: $name" }
   [GlLegacyOwner]::FileOnly((Join-Path $taskSource $name))
   $null=[GlLegacyOwner]::Read((Join-Path $taskSource $name))
  }
  if(Test-Path -LiteralPath $taskLeaf) { [GlLegacyOwner]::DeleteTree($taskLeaf) }
  $null=[IO.Directory]::CreateDirectory($taskLeaf)
  [IO.File]::WriteAllText((Join-Path $taskLeaf '.pure-gl-owner'),$taskLeafOwner,$taskUtf8)
  $taskPackage=Join-Path $taskLeaf 'pure-gl-0.9'
  # The release's complete directory inventory is explicit as well.
  foreach($name in @('','GL','cmake','debian','debian/source','examples','examples/flexi-line','tests','tests/fixtures')) {
   $null=[IO.Directory]::CreateDirectory((Join-Path $taskPackage $name))
  }
  foreach($name in $taskNames) {
   $destination=Join-Path $taskPackage $name
   if($name -eq 'README') {
    $readme=$taskUtf8.GetString([GlLegacyOwner]::Read((Join-Path $taskSource $name)))
    $today=[DateTime]::Now.ToString('MMMM d, yyyy',[Globalization.CultureInfo]::InvariantCulture)
    [IO.File]::WriteAllText($destination,$readme.Replace('@version@','0.9').Replace('|today|',$today),$taskUtf8)
   } else { [GlLegacyOwner]::CopyNew((Join-Path $taskSource $name),$destination) }
  }
  $env:TAR_OPTIONS=$null; $env:GZIP=$null
  Push-Location -LiteralPath $taskLeaf
  try { & $CMake -E tar cfz payload.tar.gz --format=gnutar pure-gl-0.9; if($LASTEXITCODE -ne 0) { throw 'Archive creation failed' } }
  finally { Pop-Location }
  [GlLegacyOwner]::Tree($taskLeaf)
  Assert-LeafOwner
  [GlLegacyOwner]::DeleteFile($taskArchive)
  [GlLegacyOwner]::CopyNew((Join-Path $taskLeaf 'payload.tar.gz'),$taskArchive)
  [GlLegacyOwner]::DeleteTree($taskLeaf)
  Write-Output "PURE_GL_SOURCE_ARCHIVE_OK files=$($taskNames.Count) archive=$taskArchive"
 } else {
  foreach($name in $taskOutputs) {
   if($name -ne 'pure-gl-0.9.tar.gz') { [GlLegacyOwner]::DeleteFile((Join-Path $taskSource $name)) }
  }
  Write-Output "PURE_GL_LEGACY_CLEAN_OK mode=$Mode"
 }
} finally { [GlLegacyOwner]::Close() }
