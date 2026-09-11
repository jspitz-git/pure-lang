/* Native Windows Pure test supervisor. Exit 124 = deadline, 125 = contract.
 * --cwd is the fixed contract root; each launch creates its own owned leaf.
 * --owned-create prints leaf/nonce for package/source contracts; --owned-clean
 * accepts only a direct owned leaf of this binary's compiled-in root.
 * The cooperating-installer boundary excludes a hostile same-user process.
 */
#define WIN32_LEAN_AND_MEAN
#define _WIN32_WINNT 0x0601
#include <windows.h>
#include <bcrypt.h>
#include <wchar.h>
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>

#ifndef PURE_MIDI_CONTRACT_ROOT
#error A fixed PURE_MIDI_CONTRACT_ROOT is required
#endif
#define LIMIT 32768
#define CAPTURE_LIMIT (8u*1024u*1024u)
#define BAD 125u
#define DEADLINE 124u

typedef struct { HANDLE *v; size_t n,cap; } Handles;
typedef struct { wchar_t *v; size_t n,cap; } Text;
typedef struct { HANDLE pipe; char *data; size_t n; int failed; } Capture;
typedef struct { HANDLE h; wchar_t *path; } Entry;
typedef struct { Entry *v; size_t n,cap; } Tree;
static Handles held;

static void *grow(void *p,size_t n) { void *q=realloc(p,n); if(!q) ExitProcess(BAD); return q; }
static wchar_t *copy(const wchar_t *s) { size_t n=wcslen(s)+1; wchar_t *p=grow(NULL,n*sizeof(*p)); memcpy(p,s,n*sizeof(*p)); return p; }
static void retain(HANDLE h) {
  if(held.n==held.cap) { held.cap=held.cap ? held.cap*2:32; held.v=grow(held.v,held.cap*sizeof(*held.v)); }
  held.v[held.n++]=h;
}
static void release(void) { while(held.n) CloseHandle(held.v[--held.n]); }
static void appendn(Text *s,const wchar_t *v,size_t n) {
  if(s->n+n+2>s->cap) { s->cap=(s->n+n+2)*2; s->v=grow(s->v,s->cap*sizeof(*s->v)); }
  memcpy(s->v+s->n,v,n*sizeof(*v)); s->n+=n; s->v[s->n]=0;
}
static void append(Text *s,const wchar_t *v) { appendn(s,v,wcslen(v)); }
static void argument(Text *s,const wchar_t *v) {
  size_t slash=0; append(s,s->n ? L" \"":L"\"");
  for(;;++v) {
    if(*v==L'\\') { ++slash; continue; }
    if(*v==L'\"' || !*v) {
      for(size_t i=0;i<slash*2;++i) append(s,L"\\");
      if(*v==L'\"') append(s,L"\\");
    } else for(size_t i=0;i<slash;++i) append(s,L"\\");
    slash=0; if(!*v) break; appendn(s,v,1);
  }
  append(s,L"\"");
}
static wchar_t *join(const wchar_t *a,const wchar_t *b) {
  Text s={0}; append(&s,a); append(&s,L"\\"); append(&s,b); return s.v;
}
/* Refuse aliases (., .., relative, UNC/device paths, ADS, trailing-dot/space).
 * Lock every opened component against rename until launch/cleanup completes.
 */
static wchar_t *regular(const wchar_t *input,int directory,int keep) {
  wchar_t full[LIMIT],*p=copy(input); size_t n=wcslen(p); HANDLE h;
  if(n<3 || n>=LIMIT || p[1]!=L':' || (p[2]!=L'/' && p[2]!=L'\\') ||
     !((p[0]>=L'A' && p[0]<=L'Z') || (p[0]>=L'a' && p[0]<=L'z'))) goto fail;
  for(size_t i=0;i<n;++i) {
    if(p[i]==L'/') p[i]=L'\\';
    if(p[i]<32 || p[i]==L';' || p[i]==L'"' || (p[i]==L':' && i!=1)) goto fail;
    if(i>=3 && (p[i]==L'\\' || i==n-1)) {
      size_t last=p[i]==L'\\' ? i-1:i;
      if(p[last]==L' ' || p[last]==L'.' || p[last]==L'\\') goto fail;
    }
  }
  if(GetFullPathNameW(p,LIMIT,full,NULL)==0 || _wcsicmp(p,full)) goto fail;
  for(size_t i=3;i<=n;++i) if(i==n || p[i]==L'\\') {
    wchar_t saved=p[i]; BY_HANDLE_FILE_INFORMATION info;
    p[i]=0;
    h=CreateFileW(p,(i==n && !directory) ? GENERIC_READ:FILE_READ_ATTRIBUTES,
      FILE_SHARE_READ|((i<n || directory) ? FILE_SHARE_WRITE:0),NULL,OPEN_EXISTING,
      FILE_FLAG_BACKUP_SEMANTICS|FILE_FLAG_OPEN_REPARSE_POINT,NULL);
    p[i]=saved;
    if(h==INVALID_HANDLE_VALUE) goto fail;
    if(!GetFileInformationByHandle(h,&info) || (info.dwFileAttributes&FILE_ATTRIBUTE_REPARSE_POINT) ||
       (!!(info.dwFileAttributes&FILE_ATTRIBUTE_DIRECTORY)!=(i<n || directory))) {
      CloseHandle(h); goto fail;
    }
    DWORD length=GetFinalPathNameByHandleW(h,full,LIMIT,FILE_NAME_NORMALIZED|VOLUME_NAME_DOS);
    p[i]=0;
    int canonical=length>4 && length<LIMIT && !wcsncmp(full,L"\\\\?\\",4) && !_wcsicmp(p,full+4);
    p[i]=saved;
    if(!canonical) { CloseHandle(h); goto fail; }
    if(keep) retain(h); else CloseHandle(h);
  }
  return p;
fail:
  fwprintf(stderr,L"runner: noncanonical, missing, reparse, or wrong-type path: %ls\n",input);
  free(p); return NULL;
}
static int nonce_valid(const wchar_t *s) {
  if(!s || wcslen(s)!=64) return 0;
  return wcsspn(s,L"0123456789abcdef")==64;
}
static int nonce(wchar_t out[65]) {
  unsigned char bytes[32]; static const wchar_t hex[]=L"0123456789abcdef";
  if(BCryptGenRandom(NULL,bytes,sizeof(bytes),BCRYPT_USE_SYSTEM_PREFERRED_RNG)!=0) return 0;
  for(size_t i=0;i<32;++i) { out[i*2]=hex[bytes[i]>>4]; out[i*2+1]=hex[bytes[i]&15]; }
  out[64]=0; return 1;
}
static wchar_t *root_path(void) {
  wchar_t root[LIMIT];
  if(!MultiByteToWideChar(CP_UTF8,MB_ERR_INVALID_CHARS,PURE_MIDI_CONTRACT_ROOT,-1,root,LIMIT)) return NULL;
  return regular(root,1,1);
}
static int owned_create(const wchar_t *root,wchar_t **leaf,wchar_t owner[65]) {
  wchar_t id[65]; Text name={0}; HANDLE h; DWORD done; char bytes[64];
  if(!nonce(id) || !nonce(owner)) return 0;
  append(&name,L"owned-"); append(&name,id); *leaf=join(root,name.v); free(name.v);
  if(!CreateDirectoryW(*leaf,NULL)) return 0;
  wchar_t *sentinel=join(*leaf,L".pure-midi-owner");
  h=CreateFileW(sentinel,GENERIC_WRITE,0,NULL,CREATE_NEW,FILE_ATTRIBUTE_NORMAL,NULL);
  free(sentinel);
  if(h==INVALID_HANDLE_VALUE) return 0;
  for(size_t i=0;i<64;++i) bytes[i]=(char)owner[i];
  int ok=WriteFile(h,bytes,64,&done,NULL) && done==64 && FlushFileBuffers(h);
  CloseHandle(h); return ok;
}
static void tree_close(Tree *t) {
  for(size_t i=0;i<t->n;++i) { if(t->v[i].h!=INVALID_HANDLE_VALUE) CloseHandle(t->v[i].h); free(t->v[i].path); }
  free(t->v);
}
/* Preflight the complete tree before deleting anything. Open handles deny
 * rename/reparse replacement during our cooperating cleanup transaction. */
static int tree_open(Tree *t,const wchar_t *path,unsigned depth) {
  BY_HANDLE_FILE_INFORMATION info; HANDLE h;
  if(depth>64 || t->n>=100000) return 0;
  h=CreateFileW(path,DELETE|FILE_READ_ATTRIBUTES,FILE_SHARE_READ|FILE_SHARE_WRITE,NULL,
    OPEN_EXISTING,FILE_FLAG_OPEN_REPARSE_POINT|FILE_FLAG_BACKUP_SEMANTICS,NULL);
  if(h==INVALID_HANDLE_VALUE) return 0;
  if(!GetFileInformationByHandle(h,&info) || (info.dwFileAttributes&FILE_ATTRIBUTE_REPARSE_POINT)) {
    CloseHandle(h); return 0;
  }
  if(t->n==t->cap) { t->cap=t->cap ? t->cap*2:32; t->v=grow(t->v,t->cap*sizeof(*t->v)); }
  t->v[t->n++]=(Entry){h,copy(path)};
  if(info.dwFileAttributes&FILE_ATTRIBUTE_DIRECTORY) {
    WIN32_FIND_DATAW data; wchar_t *pattern=join(path,L"*"); HANDLE find=FindFirstFileW(pattern,&data);
    free(pattern);
    if(find==INVALID_HANDLE_VALUE) return GetLastError()==ERROR_FILE_NOT_FOUND;
    do {
      if(!wcscmp(data.cFileName,L".") || !wcscmp(data.cFileName,L"..")) continue;
      wchar_t *child=join(path,data.cFileName); int ok=tree_open(t,child,depth+1); free(child);
      if(!ok) { FindClose(find); return 0; }
    } while(FindNextFileW(find,&data));
    DWORD err=GetLastError(); FindClose(find); if(err!=ERROR_NO_MORE_FILES) return 0;
  }
  return 1;
}
static int owned_clean(const wchar_t *root,const wchar_t *candidate,const wchar_t *owner) {
  size_t n=wcslen(root); wchar_t *leaf=NULL,*sentinel=NULL; HANDLE h=INVALID_HANDLE_VALUE;
  BY_HANDLE_FILE_INFORMATION info; char bytes[65]; DWORD done; Tree tree={0}; int ok=0;
  if(!nonce_valid(owner) || !candidate) goto finish;
  leaf=regular(candidate,1,0); if(!leaf) goto finish;
  if(_wcsnicmp(leaf,root,n) || leaf[n]!=L'\\' || wcsncmp(leaf+n+1,L"owned-",6) ||
     !nonce_valid(leaf+n+7)) goto finish;
  sentinel=join(leaf,L".pure-midi-owner");
  h=CreateFileW(sentinel,GENERIC_READ,FILE_SHARE_READ|FILE_SHARE_DELETE,NULL,OPEN_EXISTING,
    FILE_FLAG_OPEN_REPARSE_POINT,NULL);
  if(h==INVALID_HANDLE_VALUE || !GetFileInformationByHandle(h,&info) ||
     (info.dwFileAttributes&(FILE_ATTRIBUTE_REPARSE_POINT|FILE_ATTRIBUTE_DIRECTORY)) || info.nNumberOfLinks!=1 ||
     info.nFileSizeHigh || info.nFileSizeLow!=64 || !ReadFile(h,bytes,sizeof(bytes),&done,NULL) || done!=64) goto finish;
  for(size_t i=0;i<64;++i) if(bytes[i]!=(char)owner[i]) goto finish;
  if(!tree_open(&tree,leaf,0)) goto finish;
  CloseHandle(h); h=INVALID_HANDLE_VALUE;
  for(size_t i=tree.n;i>0;--i) {
    FILE_DISPOSITION_INFO disposition={TRUE};
    if(!SetFileInformationByHandle(tree.v[i-1].h,FileDispositionInfo,&disposition,sizeof(disposition))) goto finish;
    CloseHandle(tree.v[i-1].h); tree.v[i-1].h=INVALID_HANDLE_VALUE;
  }
  ok=1;
finish:
  if(h!=INVALID_HANDLE_VALUE) CloseHandle(h);
  tree_close(&tree); free(sentinel); free(leaf);
  if(!ok) fputs("runner: refused owned cleanup (path, sentinel, reparse, or open handle)\n",stderr);
  return ok;
}
static DWORD WINAPI drain(void *arg) {
  Capture *c=arg; char block[8192]; DWORD n;
  while(ReadFile(c->pipe,block,sizeof(block),&n,NULL) && n) {
    if(c->n+n>CAPTURE_LIMIT) { c->failed=1; continue; }
    c->data=grow(c->data,c->n+n+1); memcpy(c->data+c->n,block,n); c->n+=n; c->data[c->n]=0;
  }
  if(GetLastError()!=ERROR_BROKEN_PIPE) c->failed=1;
  return 0;
}
static void env(Text *e,const wchar_t *name,const wchar_t *value) {
  append(e,name); append(e,L"="); append(e,value); appendn(e,L"",1);
}
/* Stdout is a tiny protocol: INFO lines followed by one exact final nonce.
 * Any stderr, unexpected expression, embedded NUL, early or duplicate token
 * fails even if Pure returns zero. Child failure codes always take priority. */
static int completed(Capture *out,Capture *err,const wchar_t *token) {
  char t[65]; size_t start=0; int seen=0;
  for(size_t i=0;i<65;++i) t[i]=(char)token[i];
  if(out->failed || err->failed || err->n || !out->n) return 0;
  size_t occurrences=0;
  for(size_t i=0;i+64<=out->n;++i) if(!memcmp(out->data+i,t,64)) ++occurrences;
  if(occurrences!=1) return 0;
  while(start<out->n) {
    size_t end=start; while(end<out->n && out->data[end]!='\n') ++end;
    if(end==out->n || seen) return 0;
    size_t length=end-start; if(length && out->data[end-1]=='\r') --length;
    if(length==64 && !memcmp(out->data+start,t,64)) seen=1;
    else if(length<6 || memcmp(out->data+start,"INFO: ",6) || memchr(out->data+start,0,length)) return 0;
    start=end+1;
  }
  return seen;
}
static DWORD launch(Text *cmd,Text *environment,const wchar_t *exe,const wchar_t *cwd,DWORD timeout,const wchar_t *token) {
  SECURITY_ATTRIBUTES sa={sizeof(sa),NULL,TRUE}; STARTUPINFOEXW si={0}; PROCESS_INFORMATION pi={0};
  HANDLE job=NULL,wr[2]={NULL,NULL},reader[2]={NULL,NULL},nullin=INVALID_HANDLE_VALUE;
  Capture capture[2]={{0},{0}}; JOBOBJECT_EXTENDED_LIMIT_INFORMATION limits={0};
  SIZE_T attr_size=0; DWORD result=BAD,child=BAD; int started=0,timedout=0;
  job=CreateJobObjectW(NULL,NULL); if(!job) goto done;
  limits.BasicLimitInformation.LimitFlags=JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;
  if(!SetInformationJobObject(job,JobObjectExtendedLimitInformation,&limits,sizeof(limits))) goto done;
  for(size_t i=0;i<2;++i) if(!CreatePipe(&capture[i].pipe,&wr[i],&sa,0) ||
      !SetHandleInformation(capture[i].pipe,HANDLE_FLAG_INHERIT,0)) goto done;
  nullin=CreateFileW(L"NUL",GENERIC_READ,FILE_SHARE_READ|FILE_SHARE_WRITE,&sa,OPEN_EXISTING,0,NULL);
  if(nullin==INVALID_HANDLE_VALUE) goto done;
  InitializeProcThreadAttributeList(NULL,1,0,&attr_size);
  si.lpAttributeList=grow(NULL,attr_size);
  if(!InitializeProcThreadAttributeList(si.lpAttributeList,1,0,&attr_size)) goto done;
  HANDLE inherit[]={nullin,wr[0],wr[1]};
  if(!UpdateProcThreadAttribute(si.lpAttributeList,0,PROC_THREAD_ATTRIBUTE_HANDLE_LIST,inherit,sizeof(inherit),NULL,NULL)) goto done;
  si.StartupInfo.cb=sizeof(si); si.StartupInfo.dwFlags=STARTF_USESTDHANDLES;
  si.StartupInfo.hStdInput=nullin; si.StartupInfo.hStdOutput=wr[0]; si.StartupInfo.hStdError=wr[1];
  if(!CreateProcessW(exe,cmd->v,NULL,NULL,TRUE,CREATE_SUSPENDED|CREATE_UNICODE_ENVIRONMENT|
      EXTENDED_STARTUPINFO_PRESENT|CREATE_NO_WINDOW,environment->v,cwd,&si.StartupInfo,&pi)) goto done;
  started=1;
  if(!AssignProcessToJobObject(job,pi.hProcess)) goto done;
  for(size_t i=0;i<2;++i) {
    CloseHandle(wr[i]); wr[i]=NULL;
    reader[i]=CreateThread(NULL,0,drain,&capture[i],0,NULL); if(!reader[i]) goto done;
  }
  ULONGLONG until=GetTickCount64()+timeout;
  if(ResumeThread(pi.hThread)==(DWORD)-1) goto done;
  for(;;) {
    JOBOBJECT_BASIC_ACCOUNTING_INFORMATION accounting;
    if(!QueryInformationJobObject(job,JobObjectBasicAccountingInformation,&accounting,sizeof(accounting),NULL)) goto done;
    if(!accounting.ActiveProcesses) break;
    if(GetTickCount64()>=until) { timedout=1; break; }
    Sleep(5);
  }
  if(timedout) {
    if(!TerminateJobObject(job,DEADLINE)) goto done;
    result=DEADLINE;
  } else {
    if(WaitForSingleObject(pi.hProcess,0)!=WAIT_OBJECT_0 || !GetExitCodeProcess(pi.hProcess,&child)) goto done;
    result=child;
  }
done:
  if(started && result==BAD) { TerminateJobObject(job,BAD); TerminateProcess(pi.hProcess,BAD); }
  if(started) WaitForSingleObject(pi.hProcess,5000);
  for(size_t i=0;i<2;++i) if(wr[i]) CloseHandle(wr[i]);
  if(job) CloseHandle(job); /* last resort also kills any remaining descendants */
  for(size_t i=0;i<2;++i) if(reader[i]) {
    if(WaitForSingleObject(reader[i],5000)!=WAIT_OBJECT_0) {
      CancelSynchronousIo(reader[i]); WaitForSingleObject(reader[i],INFINITE); result=BAD;
    }
    CloseHandle(reader[i]);
  }
  if(result==0 && !completed(&capture[0],&capture[1],token)) result=BAD;
  if(capture[0].n) fwrite(capture[0].data,1,capture[0].n,stdout);
  if(capture[1].n) fwrite(capture[1].data,1,capture[1].n,stderr);
  for(size_t i=0;i<2;++i) { if(capture[i].pipe) CloseHandle(capture[i].pipe); free(capture[i].data); }
  if(nullin!=INVALID_HANDLE_VALUE) CloseHandle(nullin);
  if(pi.hThread) CloseHandle(pi.hThread); if(pi.hProcess) CloseHandle(pi.hProcess);
  if(si.lpAttributeList) { DeleteProcThreadAttributeList(si.lpAttributeList); free(si.lpAttributeList); }
  if(result==BAD) fputs("runner: launch or completion protocol failed\n",stderr);
  if(result==DEADLINE) fputs("runner: process-tree deadline exceeded\n",stderr);
  return result;
}

int wmain(int argc,wchar_t **argv) {
  wchar_t *root=NULL,*exe=NULL,*script=NULL,*cwd=NULL,*token=NULL,*selector=NULL,*fixture=NULL;
  wchar_t *leaf=NULL,owner[65]; DWORD result=BAD,timeout=0; int create=0,clean=0;
  Text cmd={0},paths={0},environment={0};
  wchar_t windows[LIMIT],system[LIMIT];
  if(argc==2 && !wcscmp(argv[1],L"--nonce")) {
    if(!nonce(owner)) return BAD; wprintf(L"%ls\n",owner); return 0;
  }
  root=root_path(); if(!root) goto done;
  for(int i=1;i<argc;++i) {
    wchar_t *key=argv[i],*value;
    if(!wcscmp(key,L"--owned-create")) { create=1; continue; }
    if(!wcscmp(key,L"--owned-clean")) { clean=1; continue; }
    if(++i>=argc) goto done; value=argv[i];
    if(!wcscmp(key,L"--token")) { if(token) goto done; token=value; }
    else if(!wcscmp(key,L"--timeout-ms")) {
      wchar_t *end; unsigned long n=wcstoul(value,&end,10);
      if(timeout || !*value || *end || n<1 || n>180000) goto done; timeout=(DWORD)n;
    } else if(!wcscmp(key,L"--pure")) { if(exe || !(exe=regular(value,0,1))) goto done; }
    else if(!wcscmp(key,L"--script")) { if(script || !(script=regular(value,0,1))) goto done; }
    else if(!wcscmp(key,L"--cwd")) { if(cwd) goto done; cwd=value; }
    else if(!wcscmp(key,L"--selector")) { if(selector || !*value) goto done; selector=value; }
    else if(!wcscmp(key,L"--fixture")) { if(fixture || !(fixture=regular(value,0,1))) goto done; }
    else if(!wcscmp(key,L"--input")) { wchar_t *p=regular(value,0,1); if(!p) goto done; free(p); }
    else if(!wcscmp(key,L"--path-entry") || !wcscmp(key,L"--include") || !wcscmp(key,L"--library")) {
      wchar_t *p=regular(value,1,1); if(!p) goto done;
      if(!wcscmp(key,L"--path-entry")) { if(paths.n) append(&paths,L";"); append(&paths,p); }
      else { argument(&cmd,!wcscmp(key,L"--include") ? L"-I":L"-L"); argument(&cmd,p); }
      free(p);
    } else goto done;
  }
  if(clean) { if(create || exe || script || timeout || !cwd) goto done; result=owned_clean(root,cwd,token) ? 0:BAD; goto done; }
  if(create) {
    if(argc!=2 || !owned_create(root,&leaf,owner)) goto done;
    wprintf(L"leaf=%ls\nnonce=%ls\n",leaf,owner); result=0; goto done;
  }
  if(!exe || !script || !cwd || !timeout || !nonce_valid(token)) goto done;
  wchar_t *requested=regular(cwd,1,1);
  if(!requested || _wcsicmp(requested,root)) { free(requested); goto done; } free(requested);
  if(!GetWindowsDirectoryW(windows,LIMIT) || !GetSystemDirectoryW(system,LIMIT)) goto done;
  wchar_t *win=regular(windows,1,1),*sys=regular(system,1,1);
  if(!win || !sys) { free(win); free(sys); goto done; }
  if(paths.n) append(&paths,L";"); append(&paths,sys); append(&paths,L";"); append(&paths,win);
  if(!owned_create(root,&leaf,owner)) { free(win); free(sys); goto done; }
  // Environment keys are sorted, explicit, double-NUL terminated. No parent
  // Pure, MIDI selectors, loader settings, HOME, or shell search path leaks in.
  env(&environment,L"PATH",paths.v);
  if(fixture) env(&environment,L"PURE_MIDI_TEST_FIXTURE",fixture);
  if(selector) env(&environment,L"PURE_MIDI_TEST_OUTPUT",selector);
  env(&environment,L"PURE_MIDI_TEST_TOKEN",token);
  env(&environment,L"SystemRoot",win); env(&environment,L"TEMP",leaf);
  env(&environment,L"TMP",leaf); env(&environment,L"WINDIR",win); appendn(&environment,L"",1);
  free(win); free(sys);
  Text command={0}; argument(&command,exe); argument(&command,L"--norc");
  if(cmd.n) { append(&command,L" "); append(&command,cmd.v); }
  argument(&command,L"-x"); argument(&command,script);
  result=launch(&command,&environment,exe,leaf,timeout,token); free(command.v);
  if(!owned_clean(root,leaf,owner) && result==0) result=BAD;
done:
  release(); free(held.v); free(root); free(exe); free(script); free(fixture); free(leaf);
  free(cmd.v); free(paths.v); free(environment.v);
  if(result==BAD) fputs("runner: contract rejected\n",stderr);
  fflush(stdout); fflush(stderr); ExitProcess(result);
}
