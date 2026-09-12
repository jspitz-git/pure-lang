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
#include "pure_gl_install_authority.h"

#define PATH_CAP 4096
#define TEXT_CAP 16384
#define MAX_HELD 16384
typedef struct { wchar_t path[PATH_CAP]; HANDLE handle; } Held;
typedef struct {
  DWORD op;
  wchar_t a[PATH_CAP], b[PATH_CAP], text[TEXT_CAP];
  wchar_t stage_path[PATH_CAP], build_path[PATH_CAP], capability[65];
} Request;
typedef struct {
  DWORD magic, owner, child, volume, high, low;
  wchar_t capability[65];
} Answer;
static Held *held;
static size_t held_count;
static wchar_t (*created_dirs)[PATH_CAP];
static size_t created_count;
static wchar_t stage[PATH_CAP], build[PATH_CAP], pipe_name[128];
static wchar_t capability[65];
static DWORD child_pid;
static volatile LONG stopping;
static HANDLE server_ready;
#define MAX_BATCH 256
typedef struct {
  wchar_t path[PATH_CAP], hash[65]; HANDLE source, output;
  int kind, replace, existed, modified; /* 0 reservation, 1 payload, 2 manifest */
  char *text, *previous; DWORD length, previous_length;
} BatchFile;
static BatchFile batch[MAX_BATCH];
static size_t batch_count;
static int batch_started, batch_committed;
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
  wchar_t final[PATH_CAP];
  DWORD final_length=GetFinalPathNameByHandleW(h,final,PATH_CAP,FILE_NAME_NORMALIZED|VOLUME_NAME_DOS);
  if (!GetFileInformationByHandle(h, &info) ||
      (info.dwFileAttributes & FILE_ATTRIBUTE_REPARSE_POINT) ||
      !!(info.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) != directory ||
      (!directory && info.nNumberOfLinks != 1) ||
      final_length<4 || final_length>=PATH_CAP || wcsncmp(final,L"\\\\?\\",4) ||
      _wcsicmp(final+4,path)) {
    CloseHandle(h); return error("reparse, hardlink, noncanonical alias or wrong endpoint type");
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
      if (attr == INVALID_FILE_ATTRIBUTES && create) {
        if (created_count == MAX_HELD) return error("created directory limit exceeded");
        if (CreateDirectoryW(path,NULL)) path_copy(created_dirs[created_count++],path);
        else if (GetLastError()!=ERROR_ALREADY_EXISTS) return error("cannot create guarded directory");
      }
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
static int snapshot(const wchar_t *input) {
  wchar_t root[PATH_CAP], pattern[PATH_CAP], path[PATH_CAP];
  if (!canonical(input,root)) return 0;
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
  wcscat(temp,L"\\.gl-install-");
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
#ifdef PURE_GL_INSTALL_GUARD_FIXTURE
static void fixture_gate(const wchar_t *phase) {
  static int reached;
  wchar_t ready[128], release[128], selected[32]=L"queued";
  GetEnvironmentVariableW(L"GL_GUARD_TEST_PHASE",selected,32);
  if (wcscmp(selected,phase)) return;
  if (reached++ || !GetEnvironmentVariableW(L"GL_GUARD_TEST_READY",ready,128) ||
      !GetEnvironmentVariableW(L"GL_GUARD_TEST_RELEASE",release,128)) return;
  HANDLE a=OpenEventW(EVENT_MODIFY_STATE,FALSE,ready), b=OpenEventW(SYNCHRONIZE,FALSE,release);
  if (!a || !b || !SetEvent(a) || WaitForSingleObject(b,30000)!=WAIT_OBJECT_0) ExitProcess(90);
  CloseHandle(a); CloseHandle(b);
}
#endif
static int queue_file(const wchar_t *destination,HANDLE source,const wchar_t *hash) {
  if (batch_started || batch_count==MAX_BATCH) return error("batch state/limit exceeded");
  for (size_t i=0;i<batch_count;++i)
    if (!_wcsicmp(batch[i].path,destination)) return error("duplicate batch destination");
  BatchFile *item=&batch[batch_count++];
  if (!path_copy(item->path,destination)) return 0;
  item->source=source; item->output=INVALID_HANDLE_VALUE;
  item->kind=source==INVALID_HANDLE_VALUE?0:1;
  if (hash) wcscpy(item->hash,hash);
  return 1;
}
static int write_bytes(HANDLE out,const char *bytes,DWORD length) {
  LARGE_INTEGER zero; zero.QuadPart=0; DWORD written;
  return SetFilePointerEx(out,zero,NULL,FILE_BEGIN) &&
    WriteFile(out,bytes,length,&written,NULL) && written==length &&
    SetEndOfFile(out) && FlushFileBuffers(out);
}
/* Build and verify a private sibling, then rename that exact handle over our
 * empty reservation. NOREPLACE ensures a late unowned collision is preserved.
 * The retained output handle owns rollback and denies mutation until commit.
 */
static int atomic_payload(BatchFile *item) {
  wchar_t temp[PATH_CAP], hash[65]; BYTE nonce[16], buffer[65536];
  wchar_t *slash=wcsrchr(item->path,L'\\');
  size_t parent=(size_t)(slash-item->path);
  if (parent+60>=PATH_CAP || BCryptGenRandom(NULL,nonce,sizeof(nonce),BCRYPT_USE_SYSTEM_PREFERRED_RNG))
    return error("cannot prepare atomic payload");
  wmemcpy(temp,item->path,parent); temp[parent]=0; wcscat(temp,L"\\.gl-install-");
  size_t offset=wcslen(temp);
  for (int i=0;i<16;++i) swprintf(temp+offset+i*2,3,L"%02x",nonce[i]);
  HANDLE output=CreateFileW(temp,GENERIC_READ|GENERIC_WRITE|DELETE,FILE_SHARE_READ,NULL,
    CREATE_NEW,FILE_ATTRIBUTE_NORMAL|FILE_FLAG_OPEN_REPARSE_POINT,NULL);
  if (output==INVALID_HANDLE_VALUE) return error("cannot create owned payload temporary");
  LARGE_INTEGER zero; zero.QuadPart=0;
  int ok=SetFilePointerEx(item->source,zero,NULL,FILE_BEGIN)!=0;
  while(ok) {
    DWORD n,written;
    if (!ReadFile(item->source,buffer,sizeof(buffer),&n,NULL)) { ok=0; break; }
    if (!n) break;
    ok=WriteFile(output,buffer,n,&written,NULL) && written==n;
  }
  ok=ok && FlushFileBuffers(output) && sha_handle(output,hash) && !wcscmp(hash,item->hash);
  if (ok) {
    FILE_DISPOSITION_INFO remove={TRUE};
    ok=SetFileInformationByHandle(item->output,FileDispositionInfo,&remove,sizeof(remove))!=0;
    if (ok) { CloseHandle(item->output); item->output=INVALID_HANDLE_VALUE; }
  }
  size_t bytes=wcslen(slash+1)*sizeof(wchar_t);
  FILE_RENAME_INFO *rename=calloc(1,offsetof(FILE_RENAME_INFO,FileName)+bytes);
  if (!rename) ok=0;
  if (ok) {
    rename->ReplaceIfExists=FALSE; rename->FileNameLength=(DWORD)bytes;
    memcpy(rename->FileName,slash+1,bytes);
    NativeSetInfo set_info=(NativeSetInfo)(uintptr_t)GetProcAddress(GetModuleHandleW(L"ntdll.dll"),"NtSetInformationFile");
    IO_STATUS_BLOCK status;
    ok=set_info && set_info(output,&status,rename,
      (ULONG)(offsetof(FILE_RENAME_INFO,FileName)+bytes),(FILE_INFORMATION_CLASS)10)>=0;
  }
  free(rename);
  if (!ok) {
    FILE_DISPOSITION_INFO remove={TRUE};
    SetFileInformationByHandle(output,FileDispositionInfo,&remove,sizeof(remove));
    CloseHandle(output); return error("hash-checked atomic payload publication failed");
  }
  item->output=output;
  return 1;
}
/* Remove only empty directories created by this operation. Existing prefix
 * directories are never removed. The parent identities stay retained while
 * the exact child pin is released; a nonempty child is immediately re-pinned.
 * This is controlled rollback for cooperating installers, not crash atomicity.
 */
static int prune_created_dirs(void) {
  for (size_t i=created_count;i>0;--i) {
    wchar_t *path=created_dirs[i-1];
    if (!*path) continue;
    int index=held_index(path);
    if (index>=0) {
      CloseHandle(held[index].handle);
      held[index]=held[--held_count];
    }
    if (RemoveDirectoryW(path)) *path=0;
    else if (GetLastError()!=ERROR_DIR_NOT_EMPTY || !hold(path,1))
      return error("cannot remove owned empty transaction directory");
  }
  return 1;
}
/* Delete only reservations created by this batch, using the original handles.
 * Restore an existing conventional manifest through its still-exclusive handle.
 * Pre-existing prefix files and collision entries are never modified.
 */
static int rollback_batch(void) {
  int ok=1;
  size_t removed=0;
  if (batch_committed) return 1;
  for (size_t i=batch_count;i>0;--i) {
    BatchFile *item=&batch[i-1];
    if (item->output!=INVALID_HANDLE_VALUE) {
      if (item->existed) {
        if (item->modified && !write_bytes(item->output,item->previous,item->previous_length)) ok=0;
      } else {
        FILE_DISPOSITION_INFO remove={TRUE};
        if (!SetFileInformationByHandle(item->output,FileDispositionInfo,&remove,sizeof(remove))) ok=0;
        else ++removed;
      }
      CloseHandle(item->output); item->output=INVALID_HANDLE_VALUE;
    }
  }
  if (!prune_created_dirs()) ok=0;
  if (!ok) return error("pre-commit rollback could not restore owned files");
  if (removed) fprintf(stdout,"INSTALL_BATCH_ROLLBACK_OK removed=%zu\n",removed);
  return 1;
}
static int publish_batch(void) {
  if (batch_started) return error("batch already published/failed");
  batch_started=1;
  /* Reserve the full absent destination set before writing a single payload.
   * Every parent remains pinned, and CREATE_NEW cannot follow or replace a
   * collision. These handles deny concurrent writes, renames and reparse edits.
   */
  int ok=1;
  for (size_t i=0;ok && i<batch_count;++i) {
    BatchFile *item=&batch[i];
    ok=parent_dirs(item->path,1);
    if (ok) {
      item->output=CreateFileW(item->path,GENERIC_READ|GENERIC_WRITE|DELETE,
        FILE_SHARE_READ,NULL,item->replace?OPEN_ALWAYS:CREATE_NEW,
        FILE_ATTRIBUTE_NORMAL|FILE_FLAG_OPEN_REPARSE_POINT,NULL);
      item->existed=item->output!=INVALID_HANDLE_VALUE && item->replace && GetLastError()==ERROR_ALREADY_EXISTS;
      ok=item->output!=INVALID_HANDLE_VALUE;
      BY_HANDLE_FILE_INFORMATION info;
      if (ok) ok=GetFileInformationByHandle(item->output,&info) &&
        !(info.dwFileAttributes&(FILE_ATTRIBUTE_DIRECTORY|FILE_ATTRIBUTE_REPARSE_POINT));
      /* NOFOLLOW does not reject hardlinks. Validate the actual retained
       * writable object before ANY batch write, not just its directory entry.
       * This same no-share-write/delete handle is used for copy and rollback.
       */
      if (ok && info.nNumberOfLinks!=1) {
        SetLastError(ERROR_TOO_MANY_LINKS);
        ok=error("hardlinked writable batch endpoint");
      }
      if (ok && item->existed) {
        LARGE_INTEGER size;
        ok=GetFileSizeEx(item->output,&size) && size.QuadPart<=TEXT_CAP*4;
        if (ok) {
          DWORD n;
          item->previous_length=(DWORD)size.QuadPart;
          item->previous=malloc((size_t)item->previous_length+1);
          ok=item->previous && ReadFile(item->output,item->previous,item->previous_length,&n,NULL) && n==item->previous_length;
        }
      }
    }
    if (!ok) error("batch reservation collision (atomic publication failed)");
  }
#ifdef PURE_GL_INSTALL_GUARD_FIXTURE
  if (ok) fixture_gate(L"reserved");
#endif
  size_t written_count=0, payload_count=0;
  /* Payloads must all succeed before any final manifest contents are written. */
  for (int pass=1;ok && pass<=2;++pass) for (size_t i=0;ok && i<batch_count;++i) {
    BatchFile *item=&batch[i];
    if (item->kind!=pass) continue;
    LARGE_INTEGER zero; zero.QuadPart=0;
    BYTE buffer[65536]; DWORD n;
    item->modified=1;
    if (item->kind==2) {
      ok=write_bytes(item->output,item->text,item->length) &&
        SetFilePointerEx(item->output,zero,NULL,FILE_BEGIN) &&
        ReadFile(item->output,buffer,item->length,&n,NULL) && n==item->length &&
        !memcmp(buffer,item->text,n);
    } else {
      ok=atomic_payload(item);
      ++payload_count;
    }
    ++written_count;
#ifdef PURE_GL_INSTALL_GUARD_FIXTURE
    wchar_t failure[16];
    if (GetEnvironmentVariableW(L"GL_GUARD_TEST_FAIL_AFTER_WRITE",failure,16) &&
        wcstoul(failure,NULL,10)==written_count) {
      SetLastError(ERROR_WRITE_FAULT); ok=error("injected pre-commit write failure");
    }
#endif
  }
  /* Other-component slots were reserved too. They are not this component's
   * delta, so remove them by handle before the commit point.
   */
  for (size_t i=0;ok && i<batch_count;++i) if (!batch[i].kind) {
    FILE_DISPOSITION_INFO remove={TRUE};
    ok=SetFileInformationByHandle(batch[i].output,FileDispositionInfo,&remove,sizeof(remove))!=0;
    if (ok) { CloseHandle(batch[i].output); batch[i].output=INVALID_HANDLE_VALUE; }
  }
  if (ok) ok=prune_created_dirs();
  if (!ok) { rollback_batch(); return error("batch failed before commit"); }
  /* COMMIT POINT: selected payloads AND final manifests are verified/flushed;
   * every unused reservation has been removed. No later payload can collide.
   * Abrupt process/power failure is not a durable whole-tree transaction.
   */
  batch_committed=1;
  for (size_t i=0;i<batch_count;++i) if (batch[i].output!=INVALID_HANDLE_VALUE) {
    CloseHandle(batch[i].output); batch[i].output=INVALID_HANDLE_VALUE;
    if (!hold(batch[i].path,0)) ok=0;
  }
  if (!ok) return error("post-commit endpoint identity changed");
  fprintf(stdout,"INSTALL_BATCH_COMMIT_OK artifacts=%zu manifests=%zu reserved=%zu\n",payload_count,written_count-payload_count,batch_count);
  return 1;
}
static int handle_request(Request *r) {
  r->a[PATH_CAP-1]=r->b[PATH_CAP-1]=r->text[TEXT_CAP-1]=0;
  if (r->op==1) return 1;
  if (r->op==5) return publish_batch();
  wchar_t dest[PATH_CAP];
  if (!canonical(r->op==3?r->b:r->a,dest) || !allowed(dest,r->op!=3 && r->op!=6))
    return error("request outside owned stage/session");
  if (r->op==2) return directories(dest,1);
  if (r->op==6) return queue_file(dest,INVALID_HANDLE_VALUE,NULL);
  if (r->op==3) {
#ifdef PURE_GL_INSTALL_GUARD_FIXTURE
    fixture_gate(L"queued");
#endif
    wchar_t src[PATH_CAP], hash[65];
    if (!canonical(r->a,src) || !parent_dirs(src,0) || !hold(src,0)) return 0;
    HANDLE input=held[held_index(src)].handle;
    if (!sha_handle(input,hash) || wcscmp(hash,r->text)) return error("held source SHA256 mismatch");
    return queue_file(dest,input,hash);
  }
  if (r->op==4 || r->op==7) {
    int n=WideCharToMultiByte(CP_UTF8,WC_ERR_INVALID_CHARS,r->text,-1,NULL,0,NULL,NULL);
    if (!n) return error("manifest UTF-8 conversion failed");
    char *bytes=malloc((size_t)n);
    if (!bytes) return error("manifest allocation failed");
    WideCharToMultiByte(CP_UTF8,WC_ERR_INVALID_CHARS,r->text,-1,bytes,n,NULL,NULL);
    int replace=!_wcsnicmp(dest+wcslen(build),L"\\install_manifest_",18);
    if (r->op==7) {
      if (!queue_file(dest,INVALID_HANDLE_VALUE,NULL)) { free(bytes); return 0; }
      BatchFile *item=&batch[batch_count-1];
      item->kind=2; item->replace=replace; item->text=bytes; item->length=(DWORD)n-1;
      return 1;
    }
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
/* The OS-reported pipe server must be this client's live grandparent: the
 * exact pinned guard executable launched the CMake parent. Public environment
 * fields cannot establish this process relationship or image identity.
 */
static int server_identity(HANDLE pipe, HANDLE *owner, HANDLE *parent) {
  DWORD pid=0, caller=parent_pid(GetCurrentProcessId()), count=PATH_CAP;
  wchar_t own_path[PATH_CAP], server_path[PATH_CAP], own_canonical[PATH_CAP], server_canonical[PATH_CAP];
  if (!GetNamedPipeServerProcessId(pipe,&pid) || !caller || parent_pid(caller)!=pid)
    return error("server identity/guard ancestry mismatch");
  *parent=OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION|SYNCHRONIZE,FALSE,caller);
  *owner=OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION|SYNCHRONIZE,FALSE,pid);
  if (!*parent || !*owner || WaitForSingleObject(*parent,0)!=WAIT_TIMEOUT ||
      WaitForSingleObject(*owner,0)!=WAIT_TIMEOUT ||
      !GetModuleFileNameW(NULL,own_path,PATH_CAP) ||
      !QueryFullProcessImageNameW(*owner,0,server_path,&count) ||
      !canonical(own_path,own_canonical) || !canonical(server_path,server_canonical) ||
      _wcsicmp(own_canonical,server_canonical))
    return error("server identity/pinned image mismatch");
  return 1;
}
static int request_scope(Request *r, Answer *answer) {
  wchar_t requested_stage[PATH_CAP], requested_build[PATH_CAP];
  r->stage_path[PATH_CAP-1]=r->build_path[PATH_CAP-1]=r->capability[64]=0;
  if (!canonical(r->stage_path,requested_stage) || !canonical(r->build_path,requested_build) ||
      _wcsicmp(requested_stage,stage) || _wcsicmp(requested_build,build) ||
      wcscmp(r->capability,capability)) return error("stage identity/capability mismatch");
  BY_HANDLE_FILE_INFORMATION info;
  int index=held_index(stage);
  if (index<0 || !GetFileInformationByHandle(held[index].handle,&info))
    return error("stage identity is not retained");
  answer->owner=GetCurrentProcessId(); answer->child=child_pid;
  answer->volume=info.dwVolumeSerialNumber;
  answer->high=info.nFileIndexHigh; answer->low=info.nFileIndexLow;
  wcscpy(answer->capability,capability);
  return 1;
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
    DWORD n,pid=0; Answer answer={0};
    if (!InterlockedCompareExchange(&stopping,0,0) &&
        GetNamedPipeClientProcessId(pipe,&pid) && parent_pid(pid)==child_pid &&
        ReadFile(pipe,r,sizeof(*r),&n,NULL) && n==sizeof(*r) && request_scope(r,&answer))
      answer.magic=handle_request(r)?0x41554449:0;
    WriteFile(pipe,&answer,sizeof(answer),&n,NULL);
    FlushFileBuffers(pipe); DisconnectNamedPipe(pipe);
  }
  free(r); CloseHandle(pipe); return 0;
}
static int client(int argc,wchar_t **argv) {
  Request *r=calloc(1,sizeof(*r));
  if (!r) return 1;
  if (argc<5 || wcscmp(argv[argc-3],L"--scope") ||
      !canonical(argv[argc-2],r->stage_path) || !canonical(argv[argc-1],r->build_path)) {
    free(r); return !error("explicit stage/build scope required");
  }
  argc-=3;
  if (argc==2 && !wcscmp(argv[1],L"--probe")) r->op=1;
  else if (argc==2 && !wcscmp(argv[1],L"--publish")) r->op=5;
  else if (argc==3 && !wcscmp(argv[1],L"--reserve")) { r->op=6; path_copy(r->a,argv[2]); }
  else if (argc==3 && !wcscmp(argv[1],L"--mkdir")) { r->op=2; path_copy(r->a,argv[2]); }
  else if (argc==5 && !wcscmp(argv[1],L"--copy") && wcslen(argv[4])==64) {
    r->op=3; path_copy(r->a,argv[2]); path_copy(r->b,argv[3]); wcscpy(r->text,argv[4]);
  } else if (argc==4 && (!wcscmp(argv[1],L"--write") || !wcscmp(argv[1],L"--queue-write")) && wcslen(argv[3])<TEXT_CAP) {
    r->op=!wcscmp(argv[1],L"--write")?4:7; path_copy(r->a,argv[2]); wcscpy(r->text,argv[3]);
  }
  if (!r->op || !GetEnvironmentVariableW(L"PURE_GL_INSTALL_CHANNEL",pipe_name,128) ||
      wcsncmp(pipe_name,L"\\\\.\\pipe\\pure-gl-install-",wcslen(L"\\\\.\\pipe\\pure-gl-install-"))) {
    free(r); return !error("authenticated owner channel required");
  }
  if (!WaitNamedPipeW(pipe_name,10000)) { free(r); return !error("owner channel unavailable"); }
  HANDLE pipe=CreateFileW(pipe_name,GENERIC_READ|GENERIC_WRITE,0,NULL,OPEN_EXISTING,0,NULL);
  HANDLE owner=NULL, parent=NULL, directory=INVALID_HANDLE_VALUE;
  DWORD n=0; Answer answer={0}; BY_HANDLE_FILE_INFORMATION identity;
  int ok=pipe!=INVALID_HANDLE_VALUE && server_identity(pipe,&owner,&parent);
  if (ok) {
    directory=CreateFileW(r->stage_path,GENERIC_READ,FILE_SHARE_READ,NULL,OPEN_EXISTING,
      FILE_FLAG_BACKUP_SEMANTICS|FILE_FLAG_OPEN_REPARSE_POINT,NULL);
    ok=directory!=INVALID_HANDLE_VALUE && GetFileInformationByHandle(directory,&identity) &&
      !(identity.dwFileAttributes&FILE_ATTRIBUTE_REPARSE_POINT) &&
      (identity.dwFileAttributes&FILE_ATTRIBUTE_DIRECTORY);
    if (!ok) error("client stage identity check failed");
    if (ok && GetEnvironmentVariableW(L"PURE_GL_INSTALL_CAPABILITY",r->capability,65)!=64)
      ok=error("client capability size mismatch");
    if (ok && (!WriteFile(pipe,r,sizeof(*r),&n,NULL) || n!=sizeof(*r)))
      ok=error("client request transport failed");
    if (ok && (!ReadFile(pipe,&answer,sizeof(answer),&n,NULL) || n!=sizeof(answer)))
      ok=error("client answer transport failed");
    if (ok) ok=answer.magic==0x41554449 && answer.owner==GetProcessId(owner) &&
      answer.child==GetProcessId(parent) && !wcscmp(answer.capability,r->capability) &&
      answer.volume==identity.dwVolumeSerialNumber && answer.high==identity.nFileIndexHigh &&
      answer.low==identity.nFileIndexLow && WaitForSingleObject(owner,0)==WAIT_TIMEOUT &&
      WaitForSingleObject(parent,0)==WAIT_TIMEOUT;
    if (!ok) error("authenticated transaction response rejected");
  }
  if (directory!=INVALID_HANDLE_VALUE) CloseHandle(directory);
  if (owner) CloseHandle(owner);
  if (parent) CloseHandle(parent);
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
static int validate_context(const wchar_t *input) {
  wchar_t expected[PATH_CAP], actual[PATH_CAP], own[PATH_CAP], wanted[PATH_CAP], hash[65];
  if (!canonical(GL_NATIVE_CONTEXT,expected) || !canonical(input,actual) ||
      _wcsicmp(expected,actual)) return error("configured context path mismatch");
  if (!GetModuleFileNameW(NULL,own,PATH_CAP) || !canonical(own,actual)) return 0;
  swprintf(own,PATH_CAP,L"%ls/pure-gl-install-guard.exe",GL_NATIVE_BUILD_DIR);
  if (!canonical(own,wanted) || _wcsicmp(actual,wanted))
    return error("configured native guard build identity mismatch");
  if (!parent_dirs(expected,0) || !hold(expected,0) ||
      !sha_handle(held[held_index(expected)].handle,hash) || wcscmp(hash,GL_NATIVE_CONTEXT_HASH))
    return error("configured context identity mismatch");
  if (!canonical(GL_NATIVE_SCRIPT,expected) || !parent_dirs(expected,0) || !hold(expected,0) ||
      !sha_handle(held[held_index(expected)].handle,hash) || wcscmp(hash,GL_NATIVE_SCRIPT_HASH))
    return error("configured verifier source identity mismatch");
  return 1;
}

/* Cleanup is deliberately not a generic path-taking command. It derives two
 * fixed leaves from the compiled build authority, validates both sentinels,
 * then retains DELETE/NOFOLLOW handles to the complete tree before deleting
 * any object. Protected markers and reparse points fail the entire preflight.
 */
static Held *clean_items;
static size_t clean_count;
static int clean_scan(const wchar_t *path) {
  if (clean_count==MAX_HELD) return error("audit cleanup handle limit");
  HANDLE h=CreateFileW(path,GENERIC_READ|DELETE,FILE_SHARE_READ,NULL,OPEN_EXISTING,
    FILE_FLAG_OPEN_REPARSE_POINT|FILE_FLAG_BACKUP_SEMANTICS,NULL);
  BY_HANDLE_FILE_INFORMATION info;
  if (h==INVALID_HANDLE_VALUE) return error("cannot retain owned cleanup endpoint");
  if (!GetFileInformationByHandle(h,&info) || (info.dwFileAttributes&FILE_ATTRIBUTE_REPARSE_POINT) ||
      (!(info.dwFileAttributes&FILE_ATTRIBUTE_DIRECTORY) && info.nNumberOfLinks!=1)) {
    CloseHandle(h); return error("reparse or hardlink in audit cleanup leaf");
  }
  clean_items[clean_count].handle=h;
  path_copy(clean_items[clean_count++].path,path);
  if (!(info.dwFileAttributes&FILE_ATTRIBUTE_DIRECTORY)) return 1;
  wchar_t pattern[PATH_CAP], child[PATH_CAP];
  if (wcslen(path)+3>=PATH_CAP) return error("cleanup path too long");
  swprintf(pattern,PATH_CAP,L"%ls\\*",path);
  WIN32_FIND_DATAW data;
  HANDLE search=FindFirstFileW(pattern,&data);
  if (search==INVALID_HANDLE_VALUE) return GetLastError()==ERROR_FILE_NOT_FOUND;
  int ok=1;
  do {
    if (!wcscmp(data.cFileName,L".") || !wcscmp(data.cFileName,L"..")) continue;
    if (!_wcsicmp(data.cFileName,L".git") || !_wcsicmp(data.cFileName,L".codex") ||
        !_wcsicmp(data.cFileName,L".agents") || !_wcsicmp(data.cFileName,L".pure-gl-protected")) {
      ok=error("protected descendant beneath audit cleanup leaf"); break;
    }
    if (wcslen(path)+wcslen(data.cFileName)+2>=PATH_CAP) { ok=0; break; }
    swprintf(child,PATH_CAP,L"%ls\\%ls",path,data.cFileName);
    if (!clean_scan(child)) { ok=0; break; }
  } while(FindNextFileW(search,&data));
  DWORD end=GetLastError(); FindClose(search);
  return ok && end==ERROR_NO_MORE_FILES;
}
static int sentinel(HANDLE h,const wchar_t *wanted) {
  char bytes[PATH_CAP*3], expected[PATH_CAP*3]; DWORD n;
  int size=WideCharToMultiByte(CP_UTF8,WC_ERR_INVALID_CHARS,wanted,-1,expected,sizeof(expected),NULL,NULL);
  LARGE_INTEGER zero; zero.QuadPart=0;
  return size>0 && SetFilePointerEx(h,zero,NULL,FILE_BEGIN) &&
    ReadFile(h,bytes,sizeof(bytes),&n,NULL) && n==(DWORD)size-1 && !memcmp(bytes,expected,n);
}
static int clean_audit(const wchar_t *leaf) {
  if (wcscmp(leaf,L"install-contract") && wcscmp(leaf,L"install-guard-contract"))
    return error("unknown fixed audit leaf");
  wchar_t root[PATH_CAP], path[PATH_CAP], marker[PATH_CAP], expected[PATH_CAP*2], compiled[PATH_CAP];
  swprintf(path,PATH_CAP,L"%ls/pure-gl-audits",GL_NATIVE_BUILD_DIR);
  if (!canonical(path,root) || !directories(root,0)) return 0;
  swprintf(marker,PATH_CAP,L"%ls\\.pure-gl-owner",root);
  swprintf(expected,PATH_CAP*2,L"pure-gl audit root\r\nbuild=%ls\r\nsource=%ls\r\n",GL_NATIVE_BUILD_DIR,GL_NATIVE_SOURCE_DIR);
  if (!hold(marker,0) || !sentinel(held[held_index(marker)].handle,expected))
    return error("audit root sentinel mismatch");
  swprintf(path,PATH_CAP,L"%ls\\%ls",root,leaf);
  const wchar_t *protected_roots[]={GL_NATIVE_SOURCE_DIR,GL_NATIVE_BUILD_DIR,
    GL_NATIVE_PURE_PREFIX,GL_NATIVE_CLANG64_PREFIX,GL_NATIVE_SYSTEM};
  for (size_t i=0;i<sizeof(protected_roots)/sizeof(*protected_roots);++i) {
    if (!canonical(protected_roots[i],compiled) || under(compiled,path))
      return error("protected descendant beneath audit cleanup leaf");
  }
  clean_items=calloc(MAX_HELD,sizeof(*clean_items));
  int ok=clean_items && clean_scan(path);
  swprintf(marker,PATH_CAP,L"%ls\\.pure-gl-owner",path);
  swprintf(expected,PATH_CAP*2,L"pure-gl audit leaf\r\nleaf=%ls\r\nbuild=%ls\r\nsource=%ls\r\n",leaf,GL_NATIVE_BUILD_DIR,GL_NATIVE_SOURCE_DIR);
  int found=0;
  for (size_t i=0;ok && i<clean_count;++i) if (!_wcsicmp(clean_items[i].path,marker))
    found=sentinel(clean_items[i].handle,expected);
  if (ok && !found) ok=error("audit leaf sentinel mismatch");
  for (size_t i=clean_count;i>0;--i) {
    if (ok) {
      FILE_DISPOSITION_INFO remove={TRUE};
      if (!SetFileInformationByHandle(clean_items[i-1].handle,FileDispositionInfo,&remove,sizeof(remove)))
        ok=error("owned audit endpoint deletion refused");
    }
    CloseHandle(clean_items[i-1].handle);
  }
  free(clean_items); clean_items=NULL;
  return ok;
}
int wmain(int argc,wchar_t **argv) {
  if (argc>=3 && !wcscmp(argv[1],L"--check-paths")) {
    held=calloc(MAX_HELD,sizeof(*held));
    int ok=held!=NULL;
    for (int i=2;ok && i<argc;++i) {
      wchar_t path[PATH_CAP];
      ok=canonical(argv[i],path) && parent_dirs(path,0);
      DWORD attr=ok?GetFileAttributesW(path):INVALID_FILE_ATTRIBUTES;
      ok=ok && attr!=INVALID_FILE_ATTRIBUTES && hold(path,!!(attr&FILE_ATTRIBUTE_DIRECTORY));
    }
    for (size_t i=held_count;i>0;--i) CloseHandle(held[i-1].handle);
    free(held); return ok?0:1;
  }
  if (argc==3 && (!wcscmp(argv[1],L"--validate-context") || !wcscmp(argv[1],L"--clean-audit"))) {
    held=calloc(MAX_HELD,sizeof(*held));
    int ok=held && (!wcscmp(argv[1],L"--validate-context")?validate_context(argv[2]):clean_audit(argv[2]));
    for (size_t i=held_count;i>0;--i) CloseHandle(held[i-1].handle);
    free(held); return ok?0:1;
  }
  if (argc==3 && !wcscmp(argv[1],L"--check-tree")) {
    held=calloc(MAX_HELD,sizeof(*held));
    int ok=held && snapshot(argv[2]);
    for (size_t i=held_count;i>0;--i) CloseHandle(held[i-1].handle);
    free(held); return ok?0:1;
  }
#ifdef PURE_GL_INSTALL_GUARD_FIXTURE
  if (argc==3 && !wcscmp(argv[1],L"--test-global-owner")) {
    HANDLE h=CreateFileW(argv[2],GENERIC_READ,FILE_SHARE_READ,NULL,OPEN_EXISTING,
      FILE_FLAG_BACKUP_SEMANTICS|FILE_FLAG_OPEN_REPARSE_POINT,NULL);
    BY_HANDLE_FILE_INFORMATION info;
    if (h==INVALID_HANDLE_VALUE || !GetFileInformationByHandle(h,&info)) return 1;
    CloseHandle(h);
    wchar_t name[128];
    swprintf(name,128,L"Global\\pure-gl-stage-%08lx-%08lx%08lx",
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
  created_dirs=calloc(MAX_HELD,sizeof(*created_dirs));
  if (!held || !created_dirs || !canonical(argv[2],stage) || !canonical(argv[3],build) ||
      !directories(build,0) || !directories(stage,0)) return 1;
  wchar_t trusted_build[PATH_CAP], trusted_script[PATH_CAP], requested_script[PATH_CAP];
  if (!canonical(GL_NATIVE_BUILD_DIR,trusted_build) || _wcsicmp(build,trusted_build) ||
      !canonical(GL_NATIVE_SCRIPT,trusted_script) || !canonical(argv[6],requested_script) ||
      _wcsicmp(trusted_script,requested_script) || !validate_context(argv[5]))
    return !error("configured native transaction authority mismatch");
  wchar_t lock_path[PATH_CAP]; swprintf(lock_path,PATH_CAP,L"%ls\\install-operation.lock",build);
  HANDLE lock=CreateFileW(lock_path,GENERIC_READ|GENERIC_WRITE,0,NULL,OPEN_ALWAYS,
    FILE_FLAG_OPEN_REPARSE_POINT,NULL);
  if (lock==INVALID_HANDLE_VALUE) return !error("exclusive install operation already owned");
  BY_HANDLE_FILE_INFORMATION info;
  if (!GetFileInformationByHandle(lock,&info) || (info.dwFileAttributes&FILE_ATTRIBUTE_REPARSE_POINT) || info.nNumberOfLinks!=1)
    return !error("redirected or hardlinked operation lock");
  if (!GetFileInformationByHandle(held[held_index(stage)].handle,&info)) return 1;
  wchar_t mutex_name[128];
  swprintf(mutex_name,128,L"Global\\pure-gl-stage-%08lx-%08lx%08lx",
    info.dwVolumeSerialNumber,info.nFileIndexHigh,info.nFileIndexLow);
  HANDLE mutex=CreateMutexW(NULL,FALSE,mutex_name);
  DWORD wait=mutex?WaitForSingleObject(mutex,0):WAIT_FAILED;
  if (wait!=WAIT_OBJECT_0 && wait!=WAIT_ABANDONED) return !error("stage identity already owned by another installer");
  if (!snapshot(stage)) return 1;
  wchar_t sessions[PATH_CAP]; swprintf(sessions,PATH_CAP,L"%ls\\install-audits",build);
  if (GetFileAttributesW(sessions)!=INVALID_FILE_ATTRIBUTES && !snapshot(sessions)) return 1;
  BYTE nonce[16]; if (BCryptGenRandom(NULL,nonce,sizeof(nonce),BCRYPT_USE_SYSTEM_PREFERRED_RNG)) return 1;
  wcscpy(pipe_name,L"\\\\.\\pipe\\pure-gl-install-"); size_t offset=wcslen(pipe_name);
  for (int i=0;i<16;++i) swprintf(pipe_name+offset+i*2,3,L"%02x",nonce[i]);
  if (!SetEnvironmentVariableW(L"PURE_GL_INSTALL_CHANNEL",pipe_name)) return 1;
  BYTE secret[32];
  if (BCryptGenRandom(NULL,secret,sizeof(secret),BCRYPT_USE_SYSTEM_PREFERRED_RNG)) return 1;
  for (int i=0;i<32;++i) swprintf(capability+i*2,3,L"%02x",secret[i]);
  if (!SetEnvironmentVariableW(L"PURE_GL_INSTALL_CAPABILITY",capability)) return 1;
  wchar_t *command=calloc(32768,sizeof(wchar_t)), option[PATH_CAP+64];
  if (!command || !argument(command,argv[4])) return 1;
  const wchar_t *names[]={L"STAGE_PREFIX",L"GL_INSTALL_CONTEXT",L"GL_INSTALL_MODE",L"GL_INSTALL_COMPONENT"};
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
  if (!batch_committed && !rollback_batch()) rc=1;
  for (size_t i=0;i<batch_count;++i) { free(batch[i].text); free(batch[i].previous); }
  for (size_t i=held_count;i>0;--i) CloseHandle(held[i-1].handle);
  free(held); free(created_dirs); ReleaseMutex(mutex); CloseHandle(mutex); CloseHandle(lock);
  if (!rc) fprintf(stdout,"INSTALL_GUARD_OK retained_identity=1 batch_commit=%d teardown=1\n",batch_committed);
  return (int)rc;
}
