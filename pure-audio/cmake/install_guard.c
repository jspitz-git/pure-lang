/* Strict Windows install transaction guard. Not shipped in the package.
 * CMake retains inventory/PE/fixture policy; this helper owns only exclusion,
 * directory identities, no-follow file publication, and the child lifetime.
 * A private pipe authenticates clients as direct children of the guarded CMake
 * process. No CMake -D flag or environment string can assert guard ownership.
 */
#define WIN32_LEAN_AND_MEAN
#define _WIN32_WINNT 0x0602
#include <windows.h>
#include <winternl.h>
#include <tlhelp32.h>
#include <bcrypt.h>
#include <stdio.h>
#include <stdlib.h>
#include <wchar.h>
#include <stddef.h>
#include <stdint.h>

#define PATH_CAP 4096
#define TEXT_CAP 16384
#define MAX_HELD 16384
typedef struct { wchar_t path[PATH_CAP]; HANDLE handle; } Held;
typedef struct { DWORD op; wchar_t a[PATH_CAP], b[PATH_CAP], text[TEXT_CAP]; } Request;
static Held *held;
static size_t held_count;
static wchar_t stage[PATH_CAP], build[PATH_CAP], pipe_name[128];
static DWORD child_pid;
static volatile LONG stopping;
static HANDLE server_ready;
typedef NTSTATUS (NTAPI *NativeSetInfo)(HANDLE,PIO_STATUS_BLOCK,PVOID,ULONG,FILE_INFORMATION_CLASS);

static int error(const char *message) {
  fprintf(stderr, "install guard: %s (Windows error %lu)\n", message, GetLastError());
  return 0;
}
static int path_copy(wchar_t *out, const wchar_t *in) {
  if (wcslen(in) >= PATH_CAP) return error("path too long");
  wcscpy(out, in); return 1;
}
static int canonical(const wchar_t *in, wchar_t *out) {
  DWORD n = GetFullPathNameW(in, PATH_CAP, out, NULL);
  if (!n || n >= PATH_CAP || out[1] != L':' || out[2] != L'\\')
    return error("local absolute path required");
  while (n > 3 && out[n-1] == L'\\') out[--n] = 0;
  return 1;
}
static int under(const wchar_t *path, const wchar_t *root) {
  size_t n = wcslen(root);
  return !_wcsnicmp(path, root, n) && (!path[n] || path[n] == L'\\');
}
static int held_index(const wchar_t *path) {
  for (size_t i=0; i<held_count; ++i)
    if (!_wcsicmp(path, held[i].path)) return (int)i;
  return -1;
}
static int hold(const wchar_t *path, int directory) {
  if (held_index(path) >= 0) return 1;
  if (held_count == MAX_HELD) return error("identity handle limit exceeded");
  HANDLE h = CreateFileW(path, GENERIC_READ, FILE_SHARE_READ, NULL, OPEN_EXISTING,
    FILE_FLAG_OPEN_REPARSE_POINT | FILE_FLAG_BACKUP_SEMANTICS, NULL);
  if (h == INVALID_HANDLE_VALUE) return error("cannot retain exclusive file/directory identity");
  BY_HANDLE_FILE_INFORMATION info;
  if (!GetFileInformationByHandle(h, &info) ||
      (info.dwFileAttributes & FILE_ATTRIBUTE_REPARSE_POINT) ||
      !!(info.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) != directory) {
    CloseHandle(h); return error("reparse point or wrong endpoint type");
  }
  path_copy(held[held_count].path, path);
  held[held_count++].handle = h;
  return 1;
}
/* Each existing ancestor is pinned before its child is accessed. A directory
 * created by an uncooperative writer in the mkdir/open gap is opened NOFOLLOW
 * and rejected if redirected, before any access to its children. Retained
 * share-read handles deny delete/rename and generic-write reparse conversion.
 */
static int directories(const wchar_t *input, int create) {
  wchar_t path[PATH_CAP];
  if (!canonical(input, path)) return 0;
  size_t n = wcslen(path);
  for (size_t i=3; i<=n; ++i) if (i == n || path[i] == L'\\') {
    wchar_t saved = path[i]; path[i] = 0;
    if (held_index(path) < 0) {
      DWORD attr = GetFileAttributesW(path);
      if (attr == INVALID_FILE_ATTRIBUTES && create &&
          !CreateDirectoryW(path, NULL) && GetLastError() != ERROR_ALREADY_EXISTS)
        return error("cannot create guarded directory");
      if (!hold(path, 1)) return 0;
    }
    path[i] = saved;
  }
  return 1;
}
static int parent_dirs(const wchar_t *path, int create) {
  wchar_t parent[PATH_CAP];
  if (!path_copy(parent, path)) return 0;
  wchar_t *slash = wcsrchr(parent, L'\\');
  if (!slash || slash == parent+2) return error("invalid destination parent");
  *slash = 0;
  return directories(parent, create);
}
static int snapshot(const wchar_t *root) {
  wchar_t pattern[PATH_CAP], path[PATH_CAP];
  if (!directories(root, 0) || wcslen(root)+3 >= PATH_CAP) return 0;
  swprintf(pattern, PATH_CAP, L"%ls\\*", root);
  WIN32_FIND_DATAW data;
  HANDLE search = FindFirstFileW(pattern, &data);
  if (search == INVALID_HANDLE_VALUE) return GetLastError() == ERROR_FILE_NOT_FOUND;
  int ok=1;
  do {
    if (!wcscmp(data.cFileName,L".") || !wcscmp(data.cFileName,L"..")) continue;
    if (wcslen(root)+wcslen(data.cFileName)+2 >= PATH_CAP) { ok=0; break; }
    swprintf(path, PATH_CAP, L"%ls\\%ls", root, data.cFileName);
    if (data.dwFileAttributes & FILE_ATTRIBUTE_REPARSE_POINT) {
      ok=error("reparse point in retained tree"); break;
    }
    ok = (data.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) ? snapshot(path) : hold(path,0);
  } while (ok && FindNextFileW(search,&data));
  DWORD end = GetLastError(); FindClose(search);
  return ok && (end == ERROR_NO_MORE_FILES);
}
static int sha_handle(HANDLE file, wchar_t output[65]) {
  BCRYPT_ALG_HANDLE alg=NULL; BCRYPT_HASH_HANDLE hash=NULL;
  BYTE digest[32], buffer[65536]; DWORD n; LARGE_INTEGER zero; zero.QuadPart=0;
  int ok = SetFilePointerEx(file,zero,NULL,FILE_BEGIN) &&
    !BCryptOpenAlgorithmProvider(&alg,BCRYPT_SHA256_ALGORITHM,NULL,0) &&
    !BCryptCreateHash(alg,&hash,NULL,0,NULL,0,0);
  while (ok) {
    if (!ReadFile(file,buffer,sizeof(buffer),&n,NULL)) { ok=0; break; }
    if (!n) break;
    ok = !BCryptHashData(hash,buffer,n,0);
  }
  if (ok) ok = !BCryptFinishHash(hash,digest,sizeof(digest),0);
  if (hash) BCryptDestroyHash(hash);
  if (alg) BCryptCloseAlgorithmProvider(alg,0);
  if (!ok) return error("cannot hash held input");
  for (int i=0;i<32;++i) swprintf(output+i*2,3,L"%02x",digest[i]);
  return SetFilePointerEx(file,zero,NULL,FILE_BEGIN) != 0;
}
static int allowed(const wchar_t *dest, int text) {
  if (!text) return under(dest,stage) && _wcsicmp(dest,stage);
  wchar_t prefix[PATH_CAP];
  swprintf(prefix,PATH_CAP,L"%ls\\install-audits",build);
  if (under(dest,prefix) && _wcsicmp(dest,prefix)) return 1;
  for (int i=0;i<2;++i) {
    swprintf(prefix,PATH_CAP,L"%ls\\install_manifest_%ls.txt",build,i?L"documentation":L"runtime");
    if (!_wcsicmp(dest,prefix)) return 1;
  }
  return 0;
}
static int atomic_file(const wchar_t *destination, HANDLE source, const char *text, DWORD length, int replace) {
  wchar_t temp[PATH_CAP]; BYTE random[16];
  if (!parent_dirs(destination,1) || BCryptGenRandom(NULL,random,sizeof(random),BCRYPT_USE_SYSTEM_PREFERRED_RNG))
    return error("cannot prepare atomic destination");
  wchar_t *slash=wcsrchr(destination,L'\\');
  size_t parent_length=(size_t)(slash-destination);
  if (parent_length+60>=PATH_CAP) return error("atomic destination too long");
  wmemcpy(temp,destination,parent_length); temp[parent_length]=0;
  wcscat(temp,L"\\.audio-install-");
  size_t offset=wcslen(temp);
  for (int i=0;i<16;++i) swprintf(temp+offset+i*2,3,L"%02x",random[i]);
  HANDLE out=CreateFileW(temp,GENERIC_WRITE|DELETE,FILE_SHARE_READ,NULL,CREATE_NEW,
    FILE_ATTRIBUTE_NORMAL|FILE_FLAG_OPEN_REPARSE_POINT,NULL);
  if (out==INVALID_HANDLE_VALUE) return error("cannot create owned atomic temporary file");
  BYTE buffer[65536]; DWORD n,written; int ok=1;
  if (source!=INVALID_HANDLE_VALUE) {
    while (ok) {
      if (!ReadFile(source,buffer,sizeof(buffer),&n,NULL)) { ok=0; break; }
      if (!n) break;
      ok=WriteFile(out,buffer,n,&written,NULL) && written==n;
    }
  } else ok=WriteFile(out,text,length,&written,NULL) && written==length;
  ok=ok && FlushFileBuffers(out);
  /* A native same-directory rename uses the exact open temporary file's
   * parent and a simple basename, not Win32's absolute-path resolution.
   * RootDirectory must be NULL for this operation. No parent write handle
   * needs to be opened, so the no-write/no-delete directory pins stay held.
   * Replacing a manifest replaces its entry, never a symlink target.
   */
  size_t bytes=wcslen(slash+1)*sizeof(wchar_t);
  FILE_RENAME_INFO *rename=calloc(1,offsetof(FILE_RENAME_INFO,FileName)+bytes);
  if (!rename) ok=0;
  if (ok) {
    rename->ReplaceIfExists=(BOOLEAN)replace;
    rename->FileNameLength=(DWORD)bytes;
    memcpy(rename->FileName,slash+1,bytes);
    NativeSetInfo set_info=(NativeSetInfo)(uintptr_t)GetProcAddress(GetModuleHandleW(L"ntdll.dll"),"NtSetInformationFile");
    IO_STATUS_BLOCK status;
    NTSTATUS code=set_info?set_info(out,&status,rename,
      (ULONG)(offsetof(FILE_RENAME_INFO,FileName)+bytes),(FILE_INFORMATION_CLASS)10):(NTSTATUS)0xc0000002;
    ok=code>=0;
    if (!ok) fprintf(stderr,"install guard: same-directory native rename status 0x%08lx\n",(unsigned long)code);
  }
  free(rename);
  if (!ok) {
    FILE_DISPOSITION_INFO remove={TRUE};
    SetFileInformationByHandle(out,FileDispositionInfo,&remove,sizeof(remove));
    error("atomic publication failed (collision or identity change)");
  }
  CloseHandle(out);
  /* Re-open NOFOLLOW and retain the published endpoint. An endpoint swapped
   * in this gap cannot redirect any write: publication is already finished.
   * The subsequent CMake full-tree hashes must still match the sealed policy.
   */
  return ok && hold(destination,0);
}
#ifdef PURE_AUDIO_INSTALL_GUARD_FIXTURE
static void fixture_gate(void) {
  static int reached;
  wchar_t ready[128], release[128];
  if (reached++ || !GetEnvironmentVariableW(L"AUDIO_GUARD_TEST_READY",ready,128) ||
      !GetEnvironmentVariableW(L"AUDIO_GUARD_TEST_RELEASE",release,128)) return;
  HANDLE a=OpenEventW(EVENT_MODIFY_STATE,FALSE,ready), b=OpenEventW(SYNCHRONIZE,FALSE,release);
  if (!a || !b || !SetEvent(a) || WaitForSingleObject(b,30000)!=WAIT_OBJECT_0) ExitProcess(90);
  CloseHandle(a); CloseHandle(b);
}
#endif
static int handle_request(Request *r) {
  r->a[PATH_CAP-1]=r->b[PATH_CAP-1]=r->text[TEXT_CAP-1]=0;
  if (r->op==1) return 1;
  wchar_t dest[PATH_CAP];
  if (!canonical(r->op==3?r->b:r->a,dest) || !allowed(dest,r->op!=3))
    return error("request outside owned stage/session");
  if (r->op==2) return directories(dest,1);
  if (r->op==3) {
#ifdef PURE_AUDIO_INSTALL_GUARD_FIXTURE
    fixture_gate();
#endif
    wchar_t src[PATH_CAP], hash[65];
    if (!canonical(r->a,src) || !parent_dirs(src,0) || !hold(src,0)) return 0;
    HANDLE input=held[held_index(src)].handle;
    if (!sha_handle(input,hash) || wcscmp(hash,r->text)) return error("held source SHA256 mismatch");
    return atomic_file(dest,input,NULL,0,0);
  }
  if (r->op==4) {
    int n=WideCharToMultiByte(CP_UTF8,WC_ERR_INVALID_CHARS,r->text,-1,NULL,0,NULL,NULL);
    if (!n) return error("manifest UTF-8 conversion failed");
    char *bytes=malloc((size_t)n);
    if (!bytes) return error("manifest allocation failed");
    WideCharToMultiByte(CP_UTF8,WC_ERR_INVALID_CHARS,r->text,-1,bytes,n,NULL,NULL);
    int replace=!_wcsnicmp(dest+wcslen(build),L"\\install_manifest_",18);
    int ok=atomic_file(dest,INVALID_HANDLE_VALUE,bytes,(DWORD)n-1,replace);
    free(bytes); return ok;
  }
  return error("unknown authenticated operation");
}
static DWORD parent_pid(DWORD pid) {
  HANDLE snap=CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS,0);
  if (snap==INVALID_HANDLE_VALUE) return 0;
  PROCESSENTRY32W entry; entry.dwSize=sizeof(entry); DWORD parent=0;
  if (Process32FirstW(snap,&entry)) do {
    if (entry.th32ProcessID==pid) { parent=entry.th32ParentProcessID; break; }
  } while(Process32NextW(snap,&entry));
  CloseHandle(snap); return parent;
}
static DWORD WINAPI serve(void *unused) {
  (void)unused;
  HANDLE pipe=CreateNamedPipeW(pipe_name,PIPE_ACCESS_DUPLEX|FILE_FLAG_FIRST_PIPE_INSTANCE,
    PIPE_TYPE_MESSAGE|PIPE_READMODE_MESSAGE|PIPE_WAIT|PIPE_REJECT_REMOTE_CLIENTS,
    1,sizeof(Request),sizeof(Request),0,NULL);
  if (pipe==INVALID_HANDLE_VALUE) return 1;
  Request *r=calloc(1,sizeof(*r));
  if (!r) { CloseHandle(pipe); return 1; }
  SetEvent(server_ready);
  while (!InterlockedCompareExchange(&stopping,0,0)) {
    if (!ConnectNamedPipe(pipe,NULL) && GetLastError()!=ERROR_PIPE_CONNECTED) break;
    DWORD n,pid=0,answer=0;
    if (!InterlockedCompareExchange(&stopping,0,0) &&
        GetNamedPipeClientProcessId(pipe,&pid) && parent_pid(pid)==child_pid &&
        ReadFile(pipe,r,sizeof(*r),&n,NULL) && n==sizeof(*r))
      answer=handle_request(r)?0x41554449:0;
    WriteFile(pipe,&answer,sizeof(answer),&n,NULL);
    FlushFileBuffers(pipe); DisconnectNamedPipe(pipe);
  }
  free(r); CloseHandle(pipe); return 0;
}
static int client(int argc,wchar_t **argv) {
  Request *r=calloc(1,sizeof(*r));
  if (!r) return 1;
  if (argc==2 && !wcscmp(argv[1],L"--probe")) r->op=1;
  else if (argc==3 && !wcscmp(argv[1],L"--mkdir")) { r->op=2; path_copy(r->a,argv[2]); }
  else if (argc==5 && !wcscmp(argv[1],L"--copy") && wcslen(argv[4])==64) {
    r->op=3; path_copy(r->a,argv[2]); path_copy(r->b,argv[3]); wcscpy(r->text,argv[4]);
  } else if (argc==4 && !wcscmp(argv[1],L"--write") && wcslen(argv[3])<TEXT_CAP) {
    r->op=4; path_copy(r->a,argv[2]); wcscpy(r->text,argv[3]);
  }
  if (!r->op || !GetEnvironmentVariableW(L"PURE_AUDIO_INSTALL_CHANNEL",pipe_name,128) ||
      wcsncmp(pipe_name,L"\\\\.\\pipe\\pure-audio-install-",wcslen(L"\\\\.\\pipe\\pure-audio-install-"))) {
    free(r); return !error("authenticated owner channel required");
  }
  if (!WaitNamedPipeW(pipe_name,10000)) { free(r); return !error("owner channel unavailable"); }
  HANDLE pipe=CreateFileW(pipe_name,GENERIC_READ|GENERIC_WRITE,0,NULL,OPEN_EXISTING,0,NULL);
  DWORD n=0,answer=0;
  int ok=pipe!=INVALID_HANDLE_VALUE && WriteFile(pipe,r,sizeof(*r),&n,NULL) && n==sizeof(*r) &&
    ReadFile(pipe,&answer,sizeof(answer),&n,NULL) && n==sizeof(answer) && answer==0x41554449;
  if (pipe!=INVALID_HANDLE_VALUE) CloseHandle(pipe);
  free(r); return ok?0:!error("owner authentication or guarded operation failed");
}
/* All arguments are paths/options generated by trusted CMake. Reject embedded
 * quotes; quote each argument, doubling trailing backslashes for Windows CRT.
 */
static int argument(wchar_t *line,const wchar_t *value) {
  size_t n=wcslen(line), len=wcslen(value);
  if (wcschr(value,L'"') || n+len*2+4>=32768) return error("invalid child argument");
  wcscat(line,L" \""); wcscat(line,value);
  for (size_t i=len;i>0 && value[i-1]==L'\\';--i) wcscat(line,L"\\");
  wcscat(line,L"\""); return 1;
}
int wmain(int argc,wchar_t **argv) {
#ifdef PURE_AUDIO_INSTALL_GUARD_FIXTURE
  if (argc==3 && !wcscmp(argv[1],L"--test-global-owner")) {
    HANDLE h=CreateFileW(argv[2],GENERIC_READ,FILE_SHARE_READ,NULL,OPEN_EXISTING,
      FILE_FLAG_BACKUP_SEMANTICS|FILE_FLAG_OPEN_REPARSE_POINT,NULL);
    BY_HANDLE_FILE_INFORMATION info;
    if (h==INVALID_HANDLE_VALUE || !GetFileInformationByHandle(h,&info)) return 1;
    CloseHandle(h);
    wchar_t name[128];
    swprintf(name,128,L"Global\\pure-audio-stage-%08lx-%08lx%08lx",
      info.dwVolumeSerialNumber,info.nFileIndexHigh,info.nFileIndexLow);
    HANDLE owner=OpenMutexW(SYNCHRONIZE,FALSE,name);
    if (!owner) return !error("global stage identity is not owned");
    DWORD result=WaitForSingleObject(owner,0); CloseHandle(owner);
    return result==WAIT_TIMEOUT?0:1;
  }
  if (argc==3 && !wcscmp(argv[1],L"--test-directory-write")) {
    HANDLE h=CreateFileW(argv[2],GENERIC_WRITE,FILE_SHARE_READ|FILE_SHARE_WRITE|FILE_SHARE_DELETE,
      NULL,OPEN_EXISTING,FILE_FLAG_BACKUP_SEMANTICS|FILE_FLAG_OPEN_REPARSE_POINT,NULL);
    if (h==INVALID_HANDLE_VALUE && GetLastError()==ERROR_SHARING_VIOLATION) return 0;
    if (h!=INVALID_HANDLE_VALUE) CloseHandle(h);
    return !error("retained directory admitted reparse write access");
  }
#endif
  if (argc<2 || wcscmp(argv[1],L"--run")) return client(argc,argv);
  if (argc!=9) return !error("--run stage build cmake context script mode component required");
  held=calloc(MAX_HELD,sizeof(*held));
  if (!held || !canonical(argv[2],stage) || !canonical(argv[3],build) ||
      !directories(build,0) || !directories(stage,0)) return 1;
  wchar_t lock_path[PATH_CAP]; swprintf(lock_path,PATH_CAP,L"%ls\\install-operation.lock",build);
  HANDLE lock=CreateFileW(lock_path,GENERIC_READ|GENERIC_WRITE,0,NULL,OPEN_ALWAYS,
    FILE_FLAG_OPEN_REPARSE_POINT,NULL);
  if (lock==INVALID_HANDLE_VALUE) return !error("exclusive install operation already owned");
  BY_HANDLE_FILE_INFORMATION info;
  if (!GetFileInformationByHandle(lock,&info) || (info.dwFileAttributes&FILE_ATTRIBUTE_REPARSE_POINT))
    return !error("redirected operation lock");
  if (!GetFileInformationByHandle(held[held_index(stage)].handle,&info)) return 1;
  wchar_t mutex_name[128];
  swprintf(mutex_name,128,L"Global\\pure-audio-stage-%08lx-%08lx%08lx",
    info.dwVolumeSerialNumber,info.nFileIndexHigh,info.nFileIndexLow);
  HANDLE mutex=CreateMutexW(NULL,FALSE,mutex_name);
  DWORD wait=mutex?WaitForSingleObject(mutex,0):WAIT_FAILED;
  if (wait!=WAIT_OBJECT_0 && wait!=WAIT_ABANDONED) return !error("stage identity already owned by another installer");
  if (!snapshot(stage)) return 1;
  wchar_t sessions[PATH_CAP]; swprintf(sessions,PATH_CAP,L"%ls\\install-audits",build);
  if (GetFileAttributesW(sessions)!=INVALID_FILE_ATTRIBUTES && !snapshot(sessions)) return 1;
  BYTE nonce[16]; if (BCryptGenRandom(NULL,nonce,sizeof(nonce),BCRYPT_USE_SYSTEM_PREFERRED_RNG)) return 1;
  wcscpy(pipe_name,L"\\\\.\\pipe\\pure-audio-install-"); size_t offset=wcslen(pipe_name);
  for (int i=0;i<16;++i) swprintf(pipe_name+offset+i*2,3,L"%02x",nonce[i]);
  if (!SetEnvironmentVariableW(L"PURE_AUDIO_INSTALL_CHANNEL",pipe_name)) return 1;
  wchar_t *command=calloc(32768,sizeof(wchar_t)), option[PATH_CAP+64];
  if (!command || !argument(command,argv[4])) return 1;
  const wchar_t *names[]={L"STAGE_PREFIX",L"AUDIO_INSTALL_CONTEXT",L"AUDIO_INSTALL_MODE",L"AUDIO_INSTALL_COMPONENT"};
  const wchar_t *values[]={stage,argv[5],argv[7],argv[8]};
  for (int i=0;i<4;++i) {
    swprintf(option,PATH_CAP+64,L"-D%ls=%ls",names[i],values[i]);
    if (!argument(command,option)) return 1;
  }
  if (!argument(command,L"-P") || !argument(command,argv[6])) return 1;
  HANDLE job=CreateJobObjectW(NULL,NULL);
  JOBOBJECT_EXTENDED_LIMIT_INFORMATION limits={0}; limits.BasicLimitInformation.LimitFlags=JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;
  if (!job || !SetInformationJobObject(job,JobObjectExtendedLimitInformation,&limits,sizeof(limits))) return 1;
  STARTUPINFOW startup={0}; startup.cb=sizeof(startup); PROCESS_INFORMATION process={0};
  SECURITY_ATTRIBUTES input_security={sizeof(input_security),NULL,TRUE};
  HANDLE input=CreateFileW(L"NUL",GENERIC_READ,FILE_SHARE_READ|FILE_SHARE_WRITE,
    &input_security,OPEN_EXISTING,FILE_ATTRIBUTE_NORMAL,NULL);
  startup.dwFlags=STARTF_USESTDHANDLES;
  startup.hStdInput=input;
  startup.hStdOutput=GetStdHandle(STD_OUTPUT_HANDLE);
  startup.hStdError=GetStdHandle(STD_ERROR_HANDLE);
  if (input==INVALID_HANDLE_VALUE ||
      !SetHandleInformation(startup.hStdOutput,HANDLE_FLAG_INHERIT,HANDLE_FLAG_INHERIT) ||
      !SetHandleInformation(startup.hStdError,HANDLE_FLAG_INHERIT,HANDLE_FLAG_INHERIT))
    return !error("cannot preserve guarded diagnostics");
  if (!CreateProcessW(argv[4],command,NULL,NULL,TRUE,CREATE_SUSPENDED|CREATE_NO_WINDOW,NULL,NULL,&startup,&process))
    return !error("cannot launch guarded CMake");
  free(command);
  CloseHandle(input);
  if (!AssignProcessToJobObject(job,process.hProcess)) { TerminateProcess(process.hProcess,1); return 1; }
  child_pid=process.dwProcessId;
  server_ready=CreateEventW(NULL,TRUE,FALSE,NULL);
  HANDLE server=CreateThread(NULL,0,serve,NULL,0,NULL);
  if (!server_ready || !server || WaitForSingleObject(server_ready,10000)!=WAIT_OBJECT_0 ||
      ResumeThread(process.hThread)==(DWORD)-1) return 1;
  DWORD rc=1;
  if (WaitForSingleObject(process.hProcess,240000)==WAIT_OBJECT_0) GetExitCodeProcess(process.hProcess,&rc);
  else { error("guarded operation timed out"); rc=124; }
  TerminateJobObject(job,rc); /* No descendant survives beyond retained identities. */
  InterlockedExchange(&stopping,1);
  CancelSynchronousIo(server);
  if (WaitForSingleObject(server,10000)!=WAIT_OBJECT_0) return !error("owner server teardown failed");
  CloseHandle(server_ready);
  CloseHandle(server); CloseHandle(process.hThread); CloseHandle(process.hProcess); CloseHandle(job);
  for (size_t i=held_count;i>0;--i) CloseHandle(held[i-1].handle);
  free(held); ReleaseMutex(mutex); CloseHandle(mutex); CloseHandle(lock);
  if (!rc) fprintf(stdout,"INSTALL_GUARD_OK retained_identity=1 atomic_publish=1 teardown=1\n");
  return (int)rc;
}
