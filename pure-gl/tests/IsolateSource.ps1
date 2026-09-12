param([string]$SourceRoot,[string]$BuildRoot,[string]$CMake,[string]$Bootstrap,[string]$Authority,[string]$CheckTree)
$ErrorActionPreference='Stop'
trap { [Console]::Error.WriteLine($_.Exception.GetBaseException().Message); exit 1 }
Add-Type -TypeDefinition @'
using System;
using System.IO;
using System.Collections.Generic;
using System.Runtime.InteropServices;
public static class GlSourceIsolation {
 [StructLayout(LayoutKind.Sequential)] struct Info {
  public uint Attr; public System.Runtime.InteropServices.ComTypes.FILETIME Creation,Access,Write;
  public uint Volume,SizeHigh,SizeLow,Links,IndexHigh,IndexLow;
 }
 [StructLayout(LayoutKind.Sequential)] struct Overlapped { public IntPtr Internal,InternalHigh; public uint Offset,OffsetHigh; public IntPtr Event; }
 [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern IntPtr CreateFileW(string p,uint a,uint s,IntPtr sa,uint c,uint f,IntPtr t);
 [DllImport("kernel32.dll",SetLastError=true)] static extern bool GetFileInformationByHandle(IntPtr h,out Info i);
 [DllImport("kernel32.dll",SetLastError=true)] static extern bool LockFileEx(IntPtr h,uint f,uint r,uint low,uint high,ref Overlapped o);
 [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr h);
 static List<IntPtr> held=new List<IntPtr>();
 public static void Check(string path) {
  IntPtr h=CreateFileW(path,0x80,7,IntPtr.Zero,3,0x02200000,IntPtr.Zero);
  Info i;
  if(h.ToInt64()==-1) throw new IOException("Cannot inspect extracted input: "+path);
  bool ok=GetFileInformationByHandle(h,out i); CloseHandle(h);
  if(!ok||(i.Attr&0x400)!=0||((i.Attr&0x10)==0&&i.Links!=1)) throw new IOException("Non-regular/reparse extracted input: "+path);
  if((i.Attr&0x10)!=0) foreach(string child in Directory.GetFileSystemEntries(path)) Check(child);
 }
 public static void DenyRead(string path,bool dispatchCache) {
  // All checkout inputs deny new opens, including mapped reads. The dispatch
  // cache is already consumed explicit configuration metadata; its owner's
  // retained reader remains live, so lock its bytes while retaining identity.
  IntPtr h=CreateFileW(path,0x80000000u,dispatchCache?7u:0u,IntPtr.Zero,3,0x00200000,IntPtr.Zero);
  if(h.ToInt64()==-1) throw new IOException("Cannot isolate original input: "+path);
  var o=new Overlapped();
  if(dispatchCache&&!LockFileEx(h,3,0,0xffffffff,0xffffffff,ref o)) { CloseHandle(h); throw new IOException("Cannot lock original input: "+path); }
  held.Add(h);
 }
 public static void Close() { foreach(IntPtr h in held) CloseHandle(h); held.Clear(); }
}
'@
if($CheckTree) { [GlSourceIsolation]::Check($CheckTree); exit 0 }
try {
 [GlSourceIsolation]::Check($SourceRoot)
 $paths=@(Get-ChildItem -LiteralPath $SourceRoot -File -Recurse -Force)
 # The original build's audit workspace and CTest log directory remain the
 # driver's outputs. No original executable, script, header, or sealed input is
 # an extracted-build dependency; toolchain/SDK roots are passed explicitly.
 $paths+=@(Get-ChildItem -LiteralPath $BuildRoot -File -Force)
 foreach($directory in @(Get-ChildItem -LiteralPath $BuildRoot -Directory -Force)) {
  if($directory.Name -notin @('pure-gl-audits','Testing','install-audits')) {
   [GlSourceIsolation]::Check($directory.FullName)
   $paths+=@(Get-ChildItem -LiteralPath $directory.FullName -File -Recurse -Force)
  }
 }
 foreach($path in $paths) {
  [GlSourceIsolation]::DenyRead($path.FullName,($path.FullName -eq [IO.Path]::GetFullPath((Join-Path $BuildRoot 'CMakeCache.txt'))))
 }
 & $CMake "-DARCHIVE_AUTHORITY=$Authority" -P $Bootstrap
 if($LASTEXITCODE -ne 0) { throw 'Isolated extracted verification failed' }
 Write-Output "PURE_GL_SOURCE_ISOLATION_OK blocked_files=$($paths.Count) original_helpers_unavailable=1"
} finally { [GlSourceIsolation]::Close() }
