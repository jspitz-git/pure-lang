#ifndef PURE_AUDIO_RUNNER_FIXTURE
#define _WIN32_WINNT 0x0601
#endif
#include <wchar.h>

/* Shared by the production PATH builder and its deterministic boundary seam.
 * The caller supplies a validated canonical absolute executable path. */
static void executable_parent(wchar_t *path)
{
  wchar_t *separator = wcsrchr(path, L'\\');
  if (separator == path+2) separator[1] = 0;
  else *separator = 0;
}

/* Native adversarial child, compiled separately from the runner. */
#ifdef PURE_AUDIO_RUNNER_FIXTURE
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
int main(int argc, char **argv)
{
  if (argc == 2 && !strcmp(argv[1], "--parent-boundaries")) {
    wchar_t root[] = L"C:\\pure.exe", lower_root[] = L"z:\\pure.exe";
    wchar_t nested[] = L"C:\\bin with spaces\\pure.exe";
    executable_parent(root); executable_parent(lower_root); executable_parent(nested);
    int failures = 0;
    if (wcscmp(root, L"C:\\")) { fputs("FAIL executable parent must preserve C:\\\n", stderr); ++failures; }
    if (wcscmp(lower_root, L"z:\\")) { fputs("FAIL executable parent must preserve z:\\\n", stderr); ++failures; }
    if (wcscmp(nested, L"C:\\bin with spaces")) { fputs("FAIL nested executable parent\n", stderr); ++failures; }
    if (failures) { fprintf(stderr, "%d of 3 executable-parent boundary checks failed\n", failures); return 1; }
    puts("EXECUTABLE_PARENT_BOUNDARIES_OK checks=3"); return 0;
  }
  const char *mode = "", *token = argv[argc-1];
  for (int i = 1; i+1 < argc; ++i)
    if (!strcmp(argv[i], "-x")) mode = argv[i+1];
  if (strstr(mode, "parser")) fputs("fixture.pure:1: syntax error\n", stderr);
  else if (strstr(mode, "exception")) fputs("unhandled exception 'failed'\n", stderr);
  else if (strstr(mode, "wrong")) { puts("WRONG_TOKEN"); return 0; }
  else if (strstr(mode, "forged")) { puts("PURE_AUDIO_DONE_forged"); return 0; }
  else if (strstr(mode, "duplicate")) puts(token);
  else if (strstr(mode, "near-notice")) fputs("expected backend notice: syntax error\n", stderr);
  else if (strstr(mode, "notice")) fputs("expected backend notice\n", stderr);
  else if (strstr(mode, "exit37")) { puts(token); return 37; }
  else if (strstr(mode, "hang")) {
    char bytes[8192]; memset(bytes, 'x', sizeof(bytes));
    for (;;) { fwrite(bytes, 1, sizeof(bytes), stdout); fflush(stdout);
      fwrite(bytes, 1, sizeof(bytes), stderr); fflush(stderr); }
  } else if (strstr(mode, "inherited")) {
    char exe[MAX_PATH], command[MAX_PATH+30];
    STARTUPINFOA si = {0}; PROCESS_INFORMATION pi = {0};
    GetModuleFileNameA(NULL, exe, MAX_PATH);
    snprintf(command, sizeof(command), "\"%s\" --hold", exe);
    si.cb = sizeof(si); si.dwFlags = STARTF_USESTDHANDLES;
    si.hStdInput = GetStdHandle(STD_INPUT_HANDLE);
    si.hStdOutput = GetStdHandle(STD_OUTPUT_HANDLE);
    si.hStdError = GetStdHandle(STD_ERROR_HANDLE);
    if (!CreateProcessA(exe, command, NULL, NULL, TRUE, CREATE_NO_WINDOW,
                        NULL, NULL, &si, &pi)) return 61;
    FILE *pid = fopen("descendant.pid", "w");
    if (!pid) return 62;
    fprintf(pid, "%lu", pi.dwProcessId); fclose(pid);
    CloseHandle(pi.hThread); CloseHandle(pi.hProcess);
  } else if (argc == 2 && !strcmp(argv[1], "--hold")) Sleep(60000);
  else if (argc == 3 && !strcmp(argv[1], "--dead")) {
    HANDLE p = OpenProcess(SYNCHRONIZE, FALSE, strtoul(argv[2], NULL, 10));
    if (!p) return 0;
    DWORD wait = WaitForSingleObject(p, 5000); CloseHandle(p);
    return wait == WAIT_OBJECT_0 ? 0 : 64;
  } else if (argc == 4 && !strcmp(argv[1], "--lock")) {
    HANDLE h = CreateFileA(argv[2], GENERIC_READ|GENERIC_WRITE, 0, NULL,
                           OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, NULL);
    if (h == INVALID_HANDLE_VALUE) return 65;
    FILE *ready = fopen(argv[3], "w");
    if (!ready) return 66;
    fclose(ready); Sleep(3000); CloseHandle(h); return 0;
  } else if (argc == 4 && !strcmp(argv[1], "--start-lock")) {
    char exe[MAX_PATH], command[4*MAX_PATH];
    STARTUPINFOA si = {0}; PROCESS_INFORMATION pi = {0};
    GetModuleFileNameA(NULL, exe, MAX_PATH);
    snprintf(command, sizeof(command), "\"%s\" --lock \"%s\" \"%s\"", exe, argv[2], argv[3]);
    si.cb = sizeof(si);
    if (!CreateProcessA(exe, command, NULL, NULL, FALSE, CREATE_NO_WINDOW,
                        NULL, NULL, &si, &pi)) return 67;
    for (int i = 0; i < 100 && GetFileAttributesA(argv[3]) == INVALID_FILE_ATTRIBUTES; ++i)
      Sleep(10);
    printf("%lu", pi.dwProcessId);
    CloseHandle(pi.hThread); CloseHandle(pi.hProcess);
    return GetFileAttributesA(argv[3]) == INVALID_FILE_ATTRIBUTES ? 68 : 0;
  }
  else if (strstr(mode, "environment")) {
    if (getenv("PURELIB") || getenv("PURE_INCLUDE") || getenv("PURE_LIBRARY") ||
        strstr(getenv("PATH") ? getenv("PATH") : "", "poison")) return 63;
  } else if (strstr(mode, "directory-lock")) {
    char cwd[MAX_PATH]; GetCurrentDirectoryA(MAX_PATH, cwd);
    HANDLE write = CreateFileA(cwd, GENERIC_WRITE, FILE_SHARE_READ|FILE_SHARE_WRITE|FILE_SHARE_DELETE,
      NULL, OPEN_EXISTING, FILE_FLAG_BACKUP_SEMANTICS, NULL);
    if (write != INVALID_HANDLE_VALUE) { CloseHandle(write); return 69; }
  }
  puts(token);
  if (strstr(mode, "nonfinal")) puts("output after completion");
  return 0;
}
#else
/* One native Windows owner for Pure launches and contract scratch leaves.
 * No shell, inherited environment, caller-selected recursive root, or fixed
 * completion marker participates in the success decision. */
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <bcrypt.h>
#include <stdio.h>
#include <stdlib.h>
#include <wchar.h>
#include <string.h>
#include <stdint.h>
#include <io.h>
#include <fcntl.h>

#define PATH_CAP 4096
#define TEXT_CAP 32768
#define CAPTURE_CAP (1024*1024)
#define MAX_HANDLES 8192
static HANDLE held[MAX_HANDLES];
static size_t held_count;
static wchar_t root[PATH_CAP];
static const char root_owner[] = "pure-audio-runner-root-v1\n";
static _Noreturn void fail(const char *message)
{
  fprintf(stderr, "pure-audio runner: %s (Windows error %lu)\n", message, GetLastError());
  ExitProcess(2);
}
static HANDLE retain(HANDLE h)
{
  if (h == INVALID_HANDLE_VALUE || !h) fail("cannot lock canonical input");
  if (held_count == MAX_HANDLES) fail("too many input objects");
  held[held_count++] = h;
  return h;
}
static void join(wchar_t *out, const wchar_t *a, const wchar_t *b)
{
  if (wcslen(a)+wcslen(b)+2 >= PATH_CAP) fail("path too long");
  wcscpy(out, a); wcscat(out, L"\\"); wcscat(out, b);
}
/* Canonical lexical input and every component must be ordinary disk objects.
 * Keep ancestor handles without write/delete sharing until the operation ends;
 * neither rename nor an in-place reparse mutation can exchange an ancestor. */
static void canonical(const wchar_t *input, wchar_t *out)
{
  size_t n = wcslen(input);
  if (n < 3 || n >= PATH_CAP || input[1] != L':' ||
      (input[2] != L'/' && input[2] != L'\\') ||
      !((input[0] >= L'A' && input[0] <= L'Z') || (input[0] >= L'a' && input[0] <= L'z')))
    fail("absolute drive path required");
  wcscpy(out, input);
  for (size_t i = 0; i < n; ++i) {
    if (out[i] == L'/') out[i] = L'\\';
    if (out[i] == L';' || out[i] == L'"' || out[i] == L'\n' || out[i] == L'\r' ||
        (i != 1 && out[i] == L':')) fail("unsafe path character");
  }
  wchar_t full[PATH_CAP];
  DWORD got = GetFullPathNameW(out, PATH_CAP, full, NULL);
  if (!got || got >= PATH_CAP || _wcsicmp(out, full)) fail("noncanonical path");
  if (n > 3 && out[n-1] == L'\\') fail("trailing path separator");
  for (size_t i = 3; i <= n; ++i)
    if ((!out[i] || out[i] == L'\\') && (out[i-1] == L'.' || out[i-1] == L' '))
      fail("ambiguous path component");
}
static HANDLE object(const wchar_t *path, int directory, DWORD access, DWORD share)
{
  HANDLE h = retain(CreateFileW(path, access, share, NULL, OPEN_EXISTING,
    FILE_FLAG_OPEN_REPARSE_POINT | FILE_FLAG_BACKUP_SEMANTICS, NULL));
  BY_HANDLE_FILE_INFORMATION info;
  if (!GetFileInformationByHandle(h, &info) || GetFileType(h) != FILE_TYPE_DISK ||
      (info.dwFileAttributes & FILE_ATTRIBUTE_REPARSE_POINT) ||
      !!(info.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) != directory)
    fail("reparse or wrong input type");
  wchar_t final[PATH_CAP+4];
  DWORD n = GetFinalPathNameByHandleW(h, final, PATH_CAP+4, FILE_NAME_NORMALIZED);
  if (!n || n >= PATH_CAP+4 || wcsncmp(final, L"\\\\?\\", 4) ||
      _wcsicmp(final+4, path)) fail("noncanonical filesystem alias");
  return h;
}
static HANDLE checked(const wchar_t *input, wchar_t *out, int directory)
{
  canonical(input, out);
  size_t n = wcslen(out);
  wchar_t part[PATH_CAP]; wcscpy(part, out);
  for (size_t i = 3; i < n; ++i) if (part[i] == L'\\') {
    part[i] = 0;
    object(part, 1, GENERIC_READ, FILE_SHARE_READ);
    part[i] = L'\\';
  }
  return object(out, directory, GENERIC_READ, FILE_SHARE_READ);
}
static void random_hex(wchar_t out[33])
{
  unsigned char bytes[16];
  if (BCryptGenRandom(NULL, bytes, sizeof(bytes), BCRYPT_USE_SYSTEM_PREFERRED_RNG))
    fail("system random generator failed");
  for (int i = 0; i < 16; ++i) swprintf(out+2*i, 3, L"%02x", bytes[i]);
}
static void exact_file(const wchar_t *path, const char *expected, int create, int exclusive)
{
  HANDLE h = retain(CreateFileW(path, create ? GENERIC_READ|GENERIC_WRITE : GENERIC_READ,
    exclusive ? 0 : FILE_SHARE_READ, NULL, create ? CREATE_NEW : OPEN_EXISTING,
    FILE_FLAG_OPEN_REPARSE_POINT, NULL));
  BY_HANDLE_FILE_INFORMATION info;
  if (!GetFileInformationByHandle(h, &info) ||
      (info.dwFileAttributes & (FILE_ATTRIBUTE_REPARSE_POINT|FILE_ATTRIBUTE_DIRECTORY)) ||
      info.nNumberOfLinks != 1) fail("sentinel is not a unique regular file");
  DWORD count = 0;
  size_t n = strlen(expected);
  if (create && (!WriteFile(h, expected, (DWORD)n, &count, NULL) || count != n))
    fail("cannot write ownership sentinel");
  SetFilePointer(h, 0, NULL, FILE_BEGIN);
  char bytes[256];
  if (!ReadFile(h, bytes, sizeof(bytes), &count, NULL) || count != n || memcmp(bytes, expected, n))
    fail("ownership sentinel mismatch");
}
static void init_root(void)
{
  wchar_t exe[PATH_CAP], dir[PATH_CAP], owner[PATH_CAP], mutex_name[80];
  DWORD n = GetModuleFileNameW(NULL, exe, PATH_CAP);
  if (!n || n >= PATH_CAP) fail("cannot locate runner");
  checked(exe, dir, 0);
  *wcsrchr(dir, L'\\') = 0;
  join(root, dir, L"pure-audio-contract-root");
  uint64_t hash = 1469598103934665603ULL;
  for (const wchar_t *p = root; *p; ++p) { hash ^= (uint16_t)towlower(*p); hash *= 1099511628211ULL; }
  swprintf(mutex_name, 80, L"Local\\pure-audio-root-%016llx", (unsigned long long)hash);
  HANDLE mutex = CreateMutexW(NULL, FALSE, mutex_name);
  if (!mutex || WaitForSingleObject(mutex, 5000) != WAIT_OBJECT_0) fail("root initialization busy");
  BOOL created = CreateDirectoryW(root, NULL);
  if (!created && GetLastError() != ERROR_ALREADY_EXISTS) fail("cannot create fixed contract root");
  checked(root, dir, 1);
  join(owner, root, L".pure-audio-root-owner");
  exact_file(owner, root_owner, created, 0);
  if (created) {
    CloseHandle(held[--held_count]);
    exact_file(owner, root_owner, 0, 0);
  }
  ReleaseMutex(mutex); CloseHandle(mutex);
}
static void leaf_expected(const wchar_t *leaf, char expected[128])
{
  const wchar_t *name = leaf+wcslen(root)+1;
  if (wcslen(name) != 36 || wcsncmp(name, L"run-", 4)) fail("invalid unique leaf name");
  for (const wchar_t *p = name+4; *p; ++p)
    if (!(*p >= L'0' && *p <= L'9') && !(*p >= L'a' && *p <= L'f')) fail("invalid leaf nonce");
  char narrow[37];
  for (int i = 0; i <= 36; ++i) narrow[i] = (char)name[i];
  snprintf(expected, 128, "pure-audio-owned-leaf-v1\n%s\n", narrow);
}
static void owned_leaf(const wchar_t *input, wchar_t *leaf, int lock_sentinel)
{
  canonical(input, leaf);
  size_t n = wcslen(root);
  if (_wcsnicmp(leaf, root, n) || leaf[n] != L'\\' || !leaf[n+1] || wcschr(leaf+n+1, L'\\'))
    fail("cleanup/CWD must be a direct owned leaf below fixed root");
  wchar_t checked_leaf[PATH_CAP], owner[PATH_CAP]; char expected[128];
  checked(leaf, checked_leaf, 1);
  leaf_expected(leaf, expected);
  join(owner, leaf, L".pure-audio-owner");
  exact_file(owner, expected, 0, lock_sentinel);
}
static void print_path(const wchar_t *path)
{
  char bytes[PATH_CAP*4];
  if (!WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, path, -1, bytes, sizeof(bytes), NULL, NULL))
    fail("cannot encode path");
  for (char *p = bytes; *p; ++p) if (*p == '\\') *p = '/';
  puts(bytes);
}
static void create_leaf(void)
{
  wchar_t nonce[33], name[40], leaf[PATH_CAP], owner[PATH_CAP]; char expected[128];
  random_hex(nonce); swprintf(name, 40, L"run-%ls", nonce);
  join(leaf, root, name);
  if (!CreateDirectoryW(leaf, NULL)) fail("unique leaf creation failed");
  join(owner, leaf, L".pure-audio-owner"); leaf_expected(leaf, expected);
  exact_file(owner, expected, 1, 1);
  print_path(leaf);
}
typedef struct { HANDLE h; } Deletion;
static Deletion deletion[MAX_HANDLES];
static size_t deletion_count;
/* Preflight the entire tree while retaining identity-stable handles. Deletion
 * acts on those handles, not a path that could have been exchanged meanwhile. */
static void collect(const wchar_t *dir, int top)
{
  wchar_t pattern[PATH_CAP]; join(pattern, dir, L"*");
  WIN32_FIND_DATAW data;
  HANDLE find = FindFirstFileW(pattern, &data);
  if (find == INVALID_HANDLE_VALUE) fail("cannot enumerate owned tree");
  do {
    if (!wcscmp(data.cFileName, L".") || !wcscmp(data.cFileName, L"..") ||
        (top && !wcscmp(data.cFileName, L".pure-audio-owner"))) continue;
    if (data.dwFileAttributes & FILE_ATTRIBUTE_REPARSE_POINT) fail("reparse in owned tree");
    wchar_t path[PATH_CAP]; join(path, dir, data.cFileName);
    int isdir = !!(data.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY);
    HANDLE h = object(path, isdir, GENERIC_READ|DELETE, FILE_SHARE_READ);
    if (isdir) collect(path, 0);
    if (deletion_count == MAX_HANDLES) fail("owned tree too large");
    deletion[deletion_count++].h = h;
  } while (FindNextFileW(find, &data));
  DWORD error = GetLastError(); FindClose(find);
  if (error != ERROR_NO_MORE_FILES) fail("incomplete owned tree enumeration");
}
static void dispose(HANDLE h)
{
  FILE_DISPOSITION_INFO info = {TRUE};
  if (!SetFileInformationByHandle(h, FileDispositionInfo, &info, sizeof(info)))
    fail("owned object deletion failed");
  CloseHandle(h);
  for (size_t i = 0; i < held_count; ++i) if (held[i] == h) { held[i] = NULL; break; }
}
static void cleanup_leaf(const wchar_t *input)
{
  wchar_t leaf[PATH_CAP], owner[PATH_CAP]; char expected[128];
  /* Open the leaf itself with DELETE once; a separate no-delete directory
   * handle would prevent handle-based disposition at the end. */
  canonical(input, leaf);
  size_t n = wcslen(root);
  if (_wcsnicmp(leaf, root, n) || leaf[n] != L'\\' || wcschr(leaf+n+1, L'\\'))
    fail("cleanup target outside fixed root or not a leaf");
  leaf_expected(leaf, expected);
  HANDLE leaf_handle = object(leaf, 1, GENERIC_READ|DELETE, FILE_SHARE_READ);
  join(owner, leaf, L".pure-audio-owner");
  HANDLE sentinel = object(owner, 0, GENERIC_READ|DELETE, 0);
  BY_HANDLE_FILE_INFORMATION info; DWORD count; char bytes[256];
  if (!GetFileInformationByHandle(sentinel, &info) || info.nNumberOfLinks != 1 ||
      !ReadFile(sentinel, bytes, sizeof(bytes), &count, NULL) ||
      count != strlen(expected) || memcmp(bytes, expected, count)) fail("ownership sentinel mismatch");
  collect(leaf, 1);
  for (size_t i = 0; i < deletion_count; ++i) dispose(deletion[i].h);
  dispose(sentinel); dispose(leaf_handle);
}
static void append(wchar_t *dst, const wchar_t *src)
{
  if (wcslen(dst)+wcslen(src)+1 >= TEXT_CAP) fail("command/environment too long");
  wcscat(dst, src);
}
/* Windows CRT quoting, including trailing backslashes and embedded quotes. */
static void argument(wchar_t *cmd, const wchar_t *arg)
{
  if (*cmd) append(cmd, L" ");
  append(cmd, L"\"");
  for (const wchar_t *p = arg; *p;) {
    size_t slash = 0;
    while (*p == L'\\') { ++slash; ++p; }
    size_t copies = (*p == L'"' || !*p) ? 2*slash : slash;
    while (copies--) append(cmd, L"\\");
    if (!*p) break;
    if (*p == L'"') append(cmd, L"\\");
    wchar_t one[] = {*p++, 0}; append(cmd, one);
  }
  append(cmd, L"\"");
}
typedef struct { HANDLE pipe; char bytes[CAPTURE_CAP+1]; size_t used; int overflow, error; } Capture;
static DWORD WINAPI drain(void *arg)
{
  Capture *c = arg; char bytes[8192]; DWORD n;
  while (ReadFile(c->pipe, bytes, sizeof(bytes), &n, NULL) && n) {
    if (n > CAPTURE_CAP-c->used) c->overflow = 1;
    size_t copy = n < CAPTURE_CAP-c->used ? n : CAPTURE_CAP-c->used;
    memcpy(c->bytes+c->used, bytes, copy); c->used += copy;
  }
  DWORD error = GetLastError();
  if (error != ERROR_BROKEN_PIPE && error != ERROR_SUCCESS) c->error = 1;
  return 0;
}
static int diagnostics(Capture *c, const wchar_t **allow, size_t nallow)
{
  size_t pos = 0;
  while (pos < c->used) {
    size_t end = pos; while (end < c->used && c->bytes[end] != '\n') ++end;
    if (end == c->used) return 0;
    size_t n = end-pos;
    if (n && c->bytes[pos+n-1] == '\r') --n;
    int found = 0;
    for (size_t i = 0; i < nallow; ++i) {
      char exact[2048];
      int len = WideCharToMultiByte(CP_UTF8, 0, allow[i], -1, exact, sizeof(exact), NULL, NULL);
      if (len > 0 && (size_t)len-1 == n && !memcmp(exact, c->bytes+pos, n)) found = 1;
    }
    if (!found) return 0;
    pos = end+1;
  }
  return 1;
}
static int completion(Capture *c, const wchar_t *token)
{
  char exact[128]; size_t len = wcslen(token);
  for (size_t i = 0; i <= len; ++i) exact[i] = (char)token[i];
  size_t occurrences = 0;
  for (size_t i = 0; i+len <= c->used; ++i)
    if (!memcmp(c->bytes+i, exact, len)) ++occurrences;
  size_t end = c->used;
  if (!end || c->bytes[--end] != '\n') return 0;
  if (end && c->bytes[end-1] == '\r') --end;
  return occurrences == 1 && end >= len && !memcmp(c->bytes+end-len, exact, len) &&
    (end == len || c->bytes[end-len-1] == '\n');
}
static void scan_inputs(const wchar_t *dir)
{
  /* Validate immediate module/interface files, including reparse endpoints.
   * Explicit search directories are validated separately, component by component. */
  wchar_t pattern[PATH_CAP]; join(pattern, dir, L"*");
  WIN32_FIND_DATAW data; HANDLE f = FindFirstFileW(pattern, &data);
  if (f == INVALID_HANDLE_VALUE) fail("cannot enumerate module directory");
  do {
    const wchar_t *dot = wcsrchr(data.cFileName, L'.');
    if (dot && (!_wcsicmp(dot, L".dll") || !_wcsicmp(dot, L".pure"))) {
      wchar_t path[PATH_CAP]; join(path, dir, data.cFileName);
      object(path, 0, GENERIC_READ, FILE_SHARE_READ);
    }
  } while (FindNextFileW(f, &data));
  DWORD err = GetLastError(); FindClose(f);
  if (err != ERROR_NO_MORE_FILES) fail("module enumeration failed");
}
int wmain(int argc, wchar_t **argv)
{
  _setmode(_fileno(stdout), _O_BINARY); _setmode(_fileno(stderr), _O_BINARY);
  const wchar_t *pure = NULL, *script = NULL, *cwd = NULL;
  const wchar_t *paths[128], *includes[128], *modules[128], *allow[128];
  size_t npath = 0, ninclude = 0, nmodule = 0, nallow = 0;
  DWORD timeout = 30000; int create = 0, cleanup = 0;
  for (int i = 1; i < argc; ++i) {
    const wchar_t *key = argv[i];
    if (!wcscmp(key, L"--create-leaf")) { create = 1; continue; }
    if (!wcscmp(key, L"--cleanup")) { cleanup = 1; continue; }
    if (++i == argc) fail("missing option value");
    const wchar_t *value = argv[i];
    if (!wcscmp(key, L"--pure")) pure = value;
    else if (!wcscmp(key, L"--script")) script = value;
    else if (!wcscmp(key, L"--cwd")) cwd = value;
    else if (!wcscmp(key, L"--token")) { if (wcscmp(value, L"auto")) fail("token must be generated (auto)"); }
    else if (!wcscmp(key, L"--timeout")) {
      wchar_t *end; unsigned long n = wcstoul(value, &end, 10);
      if (!*value || *end || n < 100 || n > 120000) fail("timeout must be 100..120000 milliseconds");
      timeout = n;
    } else if (!wcscmp(key, L"--path-entry") && npath < 128) paths[npath++] = value;
    else if (!wcscmp(key, L"--include") && ninclude < 128) includes[ninclude++] = value;
    else if (!wcscmp(key, L"--module-dir") && nmodule < 128) modules[nmodule++] = value;
    else if (!wcscmp(key, L"--allow-stderr") && nallow < 128) allow[nallow++] = value;
    else fail("unknown option or too many entries");
  }
  init_root();
  if (create) { if (argc != 2) fail("create-leaf accepts no other options"); create_leaf(); return 0; }
  if (cleanup) { if (argc != 4 || !cwd) fail("cleanup requires only --cwd"); cleanup_leaf(cwd); return 0; }
  if (!pure || !script || !cwd) fail("--pure, --script and --cwd required");
  wchar_t executable[PATH_CAP], source[PATH_CAP], work[PATH_CAP], path[PATH_CAP];
  wchar_t command[TEXT_CAP] = L"", search[TEXT_CAP] = L"";
  checked(pure, executable, 0); checked(script, source, 0); owned_leaf(cwd, work, 1);
  argument(command, executable); argument(command, L"--norc");
  /* The executable directory is always the first runtime source. */
  wcscpy(path, executable); executable_parent(path); append(search, path);
  for (size_t i = 0; i < npath; ++i) { checked(paths[i], path, 1); append(search, L";"); append(search, path); }
  for (size_t i = 0; i < ninclude; ++i) {
    checked(includes[i], path, 1); scan_inputs(path); argument(command, L"-I"); argument(command, path);
  }
  for (size_t i = 0; i < nmodule; ++i) {
    checked(modules[i], path, 1); scan_inputs(path); argument(command, L"-L"); argument(command, path);
  }
  wchar_t windows[PATH_CAP], system[PATH_CAP], validated[PATH_CAP];
  if (!GetWindowsDirectoryW(windows, PATH_CAP) || !GetSystemDirectoryW(system, PATH_CAP)) fail("cannot locate Windows");
  checked(windows, validated, 1); checked(system, validated, 1);
  append(search, L";"); append(search, system); append(search, L";"); append(search, windows);
  wchar_t nonce[33], token[80]; random_hex(nonce);
  swprintf(token, 80, L"PURE_AUDIO_DONE_%ls", nonce);
  argument(command, L"-x"); argument(command, source); argument(command, token);
  wchar_t environment[TEXT_CAP] = L""; size_t used = 0;
  const wchar_t *names[] = {L"PATH", L"SystemRoot", L"TEMP", L"TMP", L"WINDIR"};
  const wchar_t *values[] = {search, windows, work, work, windows};
  for (size_t i = 0; i < 5; ++i) {
    size_t n = wcslen(names[i])+wcslen(values[i])+2;
    if (used+n+1 > TEXT_CAP) fail("environment too long");
    swprintf(environment+used, TEXT_CAP-used, L"%ls=%ls", names[i], values[i]); used += n;
  }
  environment[used] = 0;
  SECURITY_ATTRIBUTES sa = {sizeof(sa), NULL, TRUE};
  HANDLE out_write, err_write;
  Capture *out = calloc(1, sizeof(*out)), *err = calloc(1, sizeof(*err));
  if (!out || !err || !CreatePipe(&out->pipe, &out_write, &sa, 0) ||
      !CreatePipe(&err->pipe, &err_write, &sa, 0) ||
      !SetHandleInformation(out->pipe, HANDLE_FLAG_INHERIT, 0) ||
      !SetHandleInformation(err->pipe, HANDLE_FLAG_INHERIT, 0)) fail("cannot create capture pipes");
  HANDLE input = CreateFileW(L"NUL", GENERIC_READ, FILE_SHARE_READ|FILE_SHARE_WRITE,
                            &sa, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, NULL);
  if (input == INVALID_HANDLE_VALUE) fail("cannot open null stdin");
  HANDLE job = CreateJobObjectW(NULL, NULL);
  JOBOBJECT_EXTENDED_LIMIT_INFORMATION limits = {0};
  limits.BasicLimitInformation.LimitFlags = JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;
  if (!job || !SetInformationJobObject(job, JobObjectExtendedLimitInformation, &limits, sizeof(limits)))
    fail("cannot establish child tree containment");
  STARTUPINFOEXW si = {0}; PROCESS_INFORMATION pi = {0}; SIZE_T attr_size = 0;
  InitializeProcThreadAttributeList(NULL, 1, 0, &attr_size);
  si.lpAttributeList = malloc(attr_size);
  HANDLE inherited[] = {input, out_write, err_write};
  if (!si.lpAttributeList || !InitializeProcThreadAttributeList(si.lpAttributeList, 1, 0, &attr_size) ||
      !UpdateProcThreadAttribute(si.lpAttributeList, 0, PROC_THREAD_ATTRIBUTE_HANDLE_LIST,
                                inherited, sizeof(inherited), NULL, NULL)) fail("cannot restrict inherited handles");
  si.StartupInfo.cb = sizeof(si); si.StartupInfo.dwFlags = STARTF_USESTDHANDLES;
  si.StartupInfo.hStdInput = input; si.StartupInfo.hStdOutput = out_write; si.StartupInfo.hStdError = err_write;
  if (!CreateProcessW(executable, command, NULL, NULL, TRUE,
      CREATE_SUSPENDED|DETACHED_PROCESS|CREATE_UNICODE_ENVIRONMENT|EXTENDED_STARTUPINFO_PRESENT,
      environment, work, &si.StartupInfo, &pi)) fail("CreateProcess failed");
  if (!AssignProcessToJobObject(job, pi.hProcess)) {
    TerminateProcess(pi.hProcess, 2); WaitForSingleObject(pi.hProcess, 5000); fail("cannot contain suspended child");
  }
  CloseHandle(out_write); CloseHandle(err_write); CloseHandle(input);
  HANDLE readers[] = {CreateThread(NULL, 0, drain, out, 0, NULL), CreateThread(NULL, 0, drain, err, 0, NULL)};
  if (!readers[0] || !readers[1]) fail("cannot start concurrent capture");
  if (ResumeThread(pi.hThread) == (DWORD)-1) fail("cannot resume child");
  DWORD wait = WaitForSingleObject(pi.hProcess, timeout), exit_code = 1;
  int timed_out = wait == WAIT_TIMEOUT, descendant = 0;
  if (wait == WAIT_OBJECT_0) {
    if (!GetExitCodeProcess(pi.hProcess, &exit_code)) fail("cannot read child exit status");
    struct { DWORD assigned, listed; ULONG_PTR ids[128]; } members;
    if (!QueryInformationJobObject(job, JobObjectBasicProcessIdList, &members, sizeof(members), NULL)) {
      if (GetLastError() != ERROR_MORE_DATA) fail("cannot inspect child tree");
      descendant = 1;
    } else {
      /* A signaled process can remain in job accounting briefly. It is the
       * other identities, rather than that lagging count, which must fail. */
      for (DWORD i = 0; i < members.listed; ++i)
        if (members.ids[i] != pi.dwProcessId) descendant = 1;
    }
  } else if (!timed_out) fail("child wait failed");
  /* Always kill surviving descendants before joining pipe readers. */
  if (!TerminateJobObject(job, timed_out ? 124 : 1)) fail("cannot terminate child tree");
  if (WaitForSingleObject(pi.hProcess, 5000) != WAIT_OBJECT_0) fail("child did not terminate");
  ULONGLONG tree_deadline = GetTickCount64()+5000;
  for (;;) {
    JOBOBJECT_BASIC_ACCOUNTING_INFORMATION account;
    if (!QueryInformationJobObject(job, JobObjectBasicAccountingInformation,
                                   &account, sizeof(account), NULL)) fail("cannot join child tree");
    if (!account.ActiveProcesses) break;
    if (GetTickCount64() >= tree_deadline) fail("child tree did not terminate");
    Sleep(1);
  }
  if (WaitForMultipleObjects(2, readers, TRUE, 5000) != WAIT_OBJECT_0) {
    CancelSynchronousIo(readers[0]); CancelSynchronousIo(readers[1]);
    if (WaitForMultipleObjects(2, readers, TRUE, 5000) != WAIT_OBJECT_0) fail("capture threads did not terminate");
    fail("capture did not drain after tree termination");
  }
  for (int i = 0; i < 2; ++i) CloseHandle(readers[i]);
  CloseHandle(out->pipe); CloseHandle(err->pipe); CloseHandle(pi.hThread); CloseHandle(pi.hProcess); CloseHandle(job);
  DeleteProcThreadAttributeList(si.lpAttributeList); free(si.lpAttributeList);
  int valid = !out->overflow && !err->overflow && !out->error && !err->error &&
              !descendant && completion(out, token) && diagnostics(err, allow, nallow);
  /* Captured bytes remain available for diagnosis, with bounded memory/output. */
  fwrite(out->bytes, 1, out->used, stdout); fwrite(err->bytes, 1, err->used, stderr);
  free(out); free(err);
  for (size_t i = 0; i < held_count; ++i) if (held[i]) CloseHandle(held[i]);
  if (timed_out) { fputs("pure-audio runner: child timeout\n", stderr); return 124; }
  if (exit_code) ExitProcess(exit_code);
  if (!valid) { fprintf(stderr, "pure-audio runner: invalid completion or diagnostics (descendant=%d)\n", descendant); return 1; }
  return 0;
}
#endif
