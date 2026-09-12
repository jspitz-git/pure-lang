#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <stdio.h>
#include <wchar.h>
static int retained(const wchar_t *path) {
  HANDLE h=CreateFileW(path,GENERIC_WRITE,FILE_SHARE_READ|FILE_SHARE_WRITE|FILE_SHARE_DELETE,
    NULL,OPEN_EXISTING,FILE_FLAG_BACKUP_SEMANTICS|FILE_FLAG_OPEN_REPARSE_POINT,NULL);
  if(h==INVALID_HANDLE_VALUE && GetLastError()==ERROR_SHARING_VIOLATION) return 1;
  if(h!=INVALID_HANDLE_VALUE) CloseHandle(h);
  fwprintf(stderr,L"Legacy authority released before child access: %ls\n",path);
  return 0;
}
int wmain(int argc,wchar_t **argv) {
  if(argc==3 && !wcscmp(argv[1],L"--directory")) return retained(argv[2])?0:1;
  if(argc<3 || wcscmp(argv[1],L"--test-dir")) return 91;
  wchar_t cache[32768],line[32768],source[32768]=L"";
  swprintf(cache,32768,L"%ls/CMakeCache.txt",argv[2]);
  FILE *f=_wfopen(cache,L"rt");
  if(!f) return 92;
  while(fgetws(line,32768,f))
    if(!wcsncmp(line,L"CMAKE_HOME_DIRECTORY:INTERNAL=",30)) wcscpy(source,line+30);
  fclose(f);
  source[wcscspn(source,L"\r\n")]=0;
  if(!*source) return 93;
  wchar_t child[32768];
  swprintf(child,32768,L"%ls/cmake",source);
  if(!retained(cache) || !retained(source) || !retained(child)) return 1;
  HANDLE reader=CreateFileW(child,GENERIC_READ,FILE_SHARE_READ,NULL,OPEN_EXISTING,
    FILE_FLAG_BACKUP_SEMANTICS|FILE_FLAG_OPEN_REPARSE_POINT,NULL);
  if(reader==INVALID_HANDLE_VALUE) {
    fputs("Retained dispatch authority prevents compatible child reads\n",stderr);
    return 1;
  }
  CloseHandle(reader);
  return 0;
}
