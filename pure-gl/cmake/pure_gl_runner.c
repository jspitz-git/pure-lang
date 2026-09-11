#ifdef PURE_GL_RUNNER_FIXTURE
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(int argc, char **argv)
{
  if (argc == 2 && !strcmp(argv[1], "--descendant")) {
    Sleep(30000);
    return 0;
  }
  const char *script = NULL;
  for (int i = 1; i+1 < argc; ++i)
    if (!strcmp(argv[i], "-x")) script = argv[i+1];
  if (!script || argc < 2) return 90;
  FILE *input = fopen(script, "rb");
  char mode[64] = {0};
  if (!input || !fgets(mode, sizeof(mode), input)) return 91;
  fclose(input);
  mode[strcspn(mode, "\r\n")] = 0;
  const char *token = argv[argc-1];
  if (!strcmp(mode, "stderr")) {
    fputs("ZERO_EXIT_STDERR_SENTINEL\n", stderr);
  } else if (!strcmp(mode, "wrong")) {
    puts("PURE_GL_TEST_OK wrong-token");
    return 0;
  } else if (!strcmp(mode, "hang")) {
    char executable[32768], command[32780];
    STARTUPINFOA startup = {0};
    PROCESS_INFORMATION child = {0};
    if (!GetModuleFileNameA(NULL, executable, sizeof(executable))) return 92;
    snprintf(command, sizeof(command), "\"%s\" --descendant", executable);
    startup.cb = sizeof(startup);
    startup.dwFlags = STARTF_USESTDHANDLES;
    startup.hStdInput = GetStdHandle(STD_INPUT_HANDLE);
    startup.hStdOutput = GetStdHandle(STD_OUTPUT_HANDLE);
    startup.hStdError = GetStdHandle(STD_ERROR_HANDLE);
    if (!CreateProcessA(executable, command, NULL, NULL, TRUE,
        CREATE_NO_WINDOW, NULL, NULL, &startup, &child)) return 93;
    printf("DESCENDANT_PID=%lu\n", (unsigned long)child.dwProcessId);
    fflush(stdout);
    CloseHandle(child.hThread);
    CloseHandle(child.hProcess);
    Sleep(30000);
    return 0;
  } else if (!strcmp(mode, "pristine")) {
    char cwd[32768];
    if (!GetCurrentDirectoryA(sizeof(cwd), cwd)) return 94;
    printf("EFFECTIVE_CWD=%s\n", cwd);
    printf("EFFECTIVE_PATH=%s\n", getenv("PATH") ? getenv("PATH") : "<absent>");
    printf("EFFECTIVE_PURELIB=%s\n",
      getenv("PURELIB") ? getenv("PURELIB") : "UNSET");
  } else {
    return 95;
  }
  printf("PURE_GL_TEST_OK %s\n", token);
  return 0;
}

#else

#define WIN32_LEAN_AND_MEAN
#define _WIN32_WINNT 0x0601
#include <windows.h>
#include <bcrypt.h>
#include <wchar.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define PATH_LIMIT 32768
#define CAPTURE_LIMIT (8u*1024u*1024u)
#define CONTRACT_ERROR 125u
#define DEADLINE_ERROR 124u
#define MAX_VALUES 128u

typedef struct { wchar_t *data; size_t used, capacity; } Text;
typedef struct { wchar_t *values[MAX_VALUES]; size_t count; } Paths;
typedef struct { HANDLE values[4*MAX_VALUES]; size_t count; } Handles;
typedef struct { HANDLE pipe; char *data; size_t used; int failed; } Capture;

static Handles held;

static void reject(const char *message)
{
  fprintf(stderr, "pure-gl runner: %s\n", message);
  ExitProcess(CONTRACT_ERROR);
}

static void *grow(void *memory, size_t bytes)
{
  void *result = realloc(memory, bytes);
  if (!result) reject("out of memory");
  return result;
}

static wchar_t *duplicate(const wchar_t *value)
{
  size_t length = wcslen(value)+1;
  wchar_t *result = grow(NULL, length*sizeof(*result));
  memcpy(result, value, length*sizeof(*result));
  return result;
}

static void append_n(Text *text, const wchar_t *value, size_t length)
{
  if (text->used+length+2 > text->capacity) {
    text->capacity = (text->used+length+2)*2;
    text->data = grow(text->data, text->capacity*sizeof(*text->data));
  }
  memcpy(text->data+text->used, value, length*sizeof(*value));
  text->used += length;
  text->data[text->used] = 0;
}

static void append(Text *text, const wchar_t *value)
{
  append_n(text, value, wcslen(value));
}

/* Apply the documented Windows CRT command-line quoting rules. */
static void argument(Text *command, const wchar_t *value)
{
  size_t slashes = 0;
  if (command->used) append(command, L" ");
  append(command, L"\"");
  for (;; ++value) {
    if (*value == L'\\') {
      ++slashes;
      continue;
    }
    if (*value == L'\"' || !*value) {
      for (size_t i = 0; i < slashes*2; ++i) append(command, L"\\");
      if (*value == L'\"') append(command, L"\\");
    } else {
      for (size_t i = 0; i < slashes; ++i) append(command, L"\\");
    }
    slashes = 0;
    if (!*value) break;
    append_n(command, value, 1);
  }
  append(command, L"\"");
}

/* Open and retain every component to reject aliases and reparse replacement. */
static wchar_t *regular_path(const wchar_t *input, int directory)
{
  wchar_t final_path[PATH_LIMIT];
  wchar_t *path = duplicate(input);
  size_t length = wcslen(path);
  if (length < 3 || length >= PATH_LIMIT || path[1] != L':' ||
      (path[2] != L'/' && path[2] != L'\\') ||
      !((path[0] >= L'A' && path[0] <= L'Z') ||
        (path[0] >= L'a' && path[0] <= L'z'))) goto invalid;
  for (size_t i = 0; i < length; ++i) {
    if (path[i] == L'/') path[i] = L'\\';
    if (path[i] < 32 || path[i] == L';' || path[i] == L'\"' ||
        (path[i] == L':' && i != 1)) goto invalid;
    if (i >= 3 && (path[i] == L'\\' || i == length-1)) {
      size_t last = path[i] == L'\\' ? i-1 : i;
      if (path[last] == L' ' || path[last] == L'.' ||
          path[last] == L'\\') goto invalid;
    }
  }
  if (!GetFullPathNameW(path, PATH_LIMIT, final_path, NULL) ||
      _wcsicmp(path, final_path)) goto invalid;
  for (size_t i = 3; i <= length; ++i) {
    if (i != length && path[i] != L'\\') continue;
    wchar_t saved = path[i];
    BY_HANDLE_FILE_INFORMATION information;
    path[i] = 0;
    HANDLE handle = CreateFileW(path, FILE_READ_ATTRIBUTES,
      FILE_SHARE_READ|FILE_SHARE_WRITE, NULL, OPEN_EXISTING,
      FILE_FLAG_BACKUP_SEMANTICS|FILE_FLAG_OPEN_REPARSE_POINT, NULL);
    path[i] = saved;
    if (handle == INVALID_HANDLE_VALUE) goto invalid;
    if (!GetFileInformationByHandle(handle, &information) ||
        (information.dwFileAttributes & FILE_ATTRIBUTE_REPARSE_POINT) ||
        (!!(information.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) !=
         (i < length || directory))) {
      CloseHandle(handle);
      goto invalid;
    }
    DWORD count = GetFinalPathNameByHandleW(handle, final_path, PATH_LIMIT,
      FILE_NAME_NORMALIZED|VOLUME_NAME_DOS);
    path[i] = 0;
    int canonical = count > 4 && count < PATH_LIMIT &&
      !wcsncmp(final_path, L"\\\\?\\", 4) && !_wcsicmp(path, final_path+4);
    path[i] = saved;
    if (!canonical) {
      CloseHandle(handle);
      goto invalid;
    }
    if (held.count == sizeof(held.values)/sizeof(held.values[0])) {
      CloseHandle(handle);
      reject("too many path components");
    }
    held.values[held.count++] = handle;
  }
  return path;

invalid:
  fwprintf(stderr,
    L"pure-gl runner: noncanonical, missing, reparse, or wrong-type path: %ls\n",
    input);
  free(path);
  ExitProcess(CONTRACT_ERROR);
}

static void add_path(Paths *paths, const wchar_t *input, int directory,
                     const wchar_t *option)
{
  if (paths->count == MAX_VALUES) reject("too many repeated path options");
  wchar_t *path = regular_path(input, directory);
  for (size_t i = 0; i < paths->count; ++i) {
    if (!_wcsicmp(paths->values[i], path)) {
      fwprintf(stderr, L"pure-gl runner: duplicate %ls value\n", option);
      free(path);
      ExitProcess(CONTRACT_ERROR);
    }
  }
  paths->values[paths->count++] = path;
}

static void environment_entry(Text *environment, const wchar_t *name,
                              const wchar_t *value)
{
  append(environment, name);
  append(environment, L"=");
  append(environment, value);
  append_n(environment, L"", 1);
}

static int random_token(wchar_t token[65])
{
  unsigned char bytes[32];
  static const wchar_t hexadecimal[] = L"0123456789abcdef";
  if (BCryptGenRandom(NULL, bytes, sizeof(bytes),
      BCRYPT_USE_SYSTEM_PREFERRED_RNG) != 0) return 0;
  for (size_t i = 0; i < sizeof(bytes); ++i) {
    token[2*i] = hexadecimal[bytes[i] >> 4];
    token[2*i+1] = hexadecimal[bytes[i] & 15];
  }
  token[64] = 0;
  return 1;
}

static DWORD WINAPI drain(void *argument_value)
{
  Capture *capture = argument_value;
  char buffer[8192];
  DWORD count;
  while (ReadFile(capture->pipe, buffer, sizeof(buffer), &count, NULL) && count) {
    if (capture->used+count > CAPTURE_LIMIT) {
      capture->failed = 1;
      continue;
    }
    capture->data = grow(capture->data, capture->used+count+1);
    memcpy(capture->data+capture->used, buffer, count);
    capture->used += count;
    capture->data[capture->used] = 0;
  }
  DWORD error = GetLastError();
  if (error != ERROR_BROKEN_PIPE && error != ERROR_SUCCESS)
    capture->failed = 1;
  return 0;
}

static int completed(const Capture *output, const Capture *error,
                     const wchar_t *token)
{
  if (output->failed || error->failed || error->used || !output->used ||
      memchr(output->data, 0, output->used)) return 0;
  char expected[80];
  memcpy(expected, "PURE_GL_TEST_OK ", 16);
  for (size_t i = 0; i < 64; ++i) expected[16+i] = (char)token[i];
  size_t position = 0;
  unsigned matches = 0;
  while (position < output->used) {
    size_t end = position;
    while (end < output->used && output->data[end] != '\n') ++end;
    size_t length = end-position;
    if (length && output->data[position+length-1] == '\r') --length;
    if (length == sizeof(expected) &&
        !memcmp(output->data+position, expected, sizeof(expected))) {
      ++matches;
      if (end < output->used-1) return 0;
    }
    position = end < output->used ? end+1 : end;
  }
  return matches == 1;
}

static DWORD launch(const wchar_t *executable, Text *command, Text *environment,
                    const wchar_t *working_directory, DWORD timeout,
                    const wchar_t *token, Capture captures[2])
{
  SECURITY_ATTRIBUTES attributes = {sizeof(attributes), NULL, TRUE};
  HANDLE write_pipes[2] = {NULL, NULL};
  HANDLE readers[2] = {NULL, NULL};
  HANDLE input = INVALID_HANDLE_VALUE;
  HANDLE job = NULL;
  STARTUPINFOEXW startup = {0};
  PROCESS_INFORMATION process = {0};
  SIZE_T attribute_size = 0;
  DWORD result = CONTRACT_ERROR;
  DWORD child_result = CONTRACT_ERROR;
  int started = 0;
  int timed_out = 0;

  job = CreateJobObjectW(NULL, NULL);
  JOBOBJECT_EXTENDED_LIMIT_INFORMATION limits = {0};
  limits.BasicLimitInformation.LimitFlags = JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;
  if (!job || !SetInformationJobObject(job, JobObjectExtendedLimitInformation,
      &limits, sizeof(limits))) goto finished;
  for (size_t i = 0; i < 2; ++i) {
    if (!CreatePipe(&captures[i].pipe, &write_pipes[i], &attributes, 0) ||
        !SetHandleInformation(captures[i].pipe, HANDLE_FLAG_INHERIT, 0))
      goto finished;
  }
  input = CreateFileW(L"NUL", GENERIC_READ,
    FILE_SHARE_READ|FILE_SHARE_WRITE, &attributes, OPEN_EXISTING, 0, NULL);
  if (input == INVALID_HANDLE_VALUE) goto finished;
  InitializeProcThreadAttributeList(NULL, 1, 0, &attribute_size);
  startup.lpAttributeList = grow(NULL, attribute_size);
  if (!InitializeProcThreadAttributeList(startup.lpAttributeList, 1, 0,
      &attribute_size)) goto finished;
  HANDLE inherited[] = {input, write_pipes[0], write_pipes[1]};
  if (!UpdateProcThreadAttribute(startup.lpAttributeList, 0,
      PROC_THREAD_ATTRIBUTE_HANDLE_LIST, inherited, sizeof(inherited), NULL, NULL))
    goto finished;
  startup.StartupInfo.cb = sizeof(startup);
  startup.StartupInfo.dwFlags = STARTF_USESTDHANDLES;
  startup.StartupInfo.hStdInput = input;
  startup.StartupInfo.hStdOutput = write_pipes[0];
  startup.StartupInfo.hStdError = write_pipes[1];
  if (!CreateProcessW(executable, command->data, NULL, NULL, TRUE,
      CREATE_SUSPENDED|CREATE_UNICODE_ENVIRONMENT|EXTENDED_STARTUPINFO_PRESENT|
      CREATE_NO_WINDOW, environment->data, working_directory,
      &startup.StartupInfo, &process)) goto finished;
  started = 1;
  if (!AssignProcessToJobObject(job, process.hProcess)) goto finished;
  for (size_t i = 0; i < 2; ++i) {
    CloseHandle(write_pipes[i]);
    write_pipes[i] = NULL;
    readers[i] = CreateThread(NULL, 0, drain, &captures[i], 0, NULL);
    if (!readers[i]) goto finished;
  }
  if (ResumeThread(process.hThread) == (DWORD)-1) goto finished;
  DWORD wait = WaitForSingleObject(process.hProcess, timeout);
  if (wait == WAIT_TIMEOUT) {
    timed_out = 1;
    result = DEADLINE_ERROR;
  } else if (wait == WAIT_OBJECT_0 &&
      GetExitCodeProcess(process.hProcess, &child_result)) {
    result = child_result;
  } else {
    goto finished;
  }

finished:
  if (started && result == CONTRACT_ERROR)
    TerminateProcess(process.hProcess, CONTRACT_ERROR);
  if (job) TerminateJobObject(job, timed_out ? DEADLINE_ERROR : CONTRACT_ERROR);
  if (started) WaitForSingleObject(process.hProcess, 5000);
  for (size_t i = 0; i < 2; ++i)
    if (write_pipes[i]) CloseHandle(write_pipes[i]);
  if (job) CloseHandle(job);
  for (size_t i = 0; i < 2; ++i) {
    if (readers[i]) {
      if (WaitForSingleObject(readers[i], 5000) != WAIT_OBJECT_0) {
        CancelSynchronousIo(readers[i]);
        WaitForSingleObject(readers[i], INFINITE);
        result = CONTRACT_ERROR;
      }
      CloseHandle(readers[i]);
    }
    if (captures[i].pipe) CloseHandle(captures[i].pipe);
  }
  if (input != INVALID_HANDLE_VALUE) CloseHandle(input);
  if (process.hThread) CloseHandle(process.hThread);
  if (process.hProcess) CloseHandle(process.hProcess);
  if (startup.lpAttributeList) {
    DeleteProcThreadAttributeList(startup.lpAttributeList);
    free(startup.lpAttributeList);
  }
  if (captures[0].used) fwrite(captures[0].data, 1, captures[0].used, stdout);
  if (captures[1].used) fwrite(captures[1].data, 1, captures[1].used, stderr);
  if (timed_out) {
    fputs("pure-gl runner: process-tree deadline exceeded\n", stderr);
  } else if (result == 0 && captures[1].used) {
    fputs("pure-gl runner: stderr was not empty\n", stderr);
    result = CONTRACT_ERROR;
  } else if (result == 0 && !completed(&captures[0], &captures[1], token)) {
    fputs("pure-gl runner: completion protocol rejected\n", stderr);
    result = CONTRACT_ERROR;
  } else if (result == CONTRACT_ERROR) {
    fputs("pure-gl runner: launch failed\n", stderr);
  }
  return result;
}

int wmain(int argc, wchar_t **argv)
{
  wchar_t *pure = NULL;
  wchar_t *script = NULL;
  wchar_t *working_directory = NULL;
  DWORD timeout = 0;
  Paths includes = {0}, libraries = {0}, inputs = {0}, path_entries = {0};

  for (int i = 1; i < argc; ++i) {
    const wchar_t *option = argv[i];
    if (++i >= argc) {
      fwprintf(stderr, L"pure-gl runner: %ls requires a value\n", option);
      return CONTRACT_ERROR;
    }
    const wchar_t *value = argv[i];
    if (!wcscmp(option, L"--pure")) {
      if (pure) reject("duplicate --pure");
      pure = regular_path(value, 0);
    } else if (!wcscmp(option, L"--script")) {
      if (script) reject("duplicate --script");
      script = regular_path(value, 0);
    } else if (!wcscmp(option, L"--cwd")) {
      if (working_directory) reject("duplicate --cwd");
      working_directory = regular_path(value, 1);
    } else if (!wcscmp(option, L"--timeout-ms")) {
      if (timeout) reject("duplicate --timeout-ms");
      wchar_t *end = NULL;
      unsigned long parsed = wcstoul(value, &end, 10);
      if (!*value || *end || parsed < 1 || parsed > 180000)
        reject("--timeout-ms must be an integer from 1 through 180000");
      timeout = (DWORD)parsed;
    } else if (!wcscmp(option, L"--include")) {
      add_path(&includes, value, 1, option);
    } else if (!wcscmp(option, L"--library")) {
      add_path(&libraries, value, 1, option);
    } else if (!wcscmp(option, L"--input")) {
      add_path(&inputs, value, 0, option);
    } else if (!wcscmp(option, L"--path-entry")) {
      add_path(&path_entries, value, 1, option);
    } else {
      fwprintf(stderr, L"pure-gl runner: unknown option %ls\n", option);
      return CONTRACT_ERROR;
    }
  }
  if (!pure) reject("missing --pure");
  if (!script) reject("missing --script");
  if (!working_directory) reject("missing --cwd");
  if (!timeout) reject("missing --timeout-ms");
  if (!includes.count) reject("missing --include");
  if (!libraries.count) reject("missing --library");
  if (!inputs.count) reject("missing --input");
  if (!path_entries.count) reject("missing --path-entry");

  wchar_t token[65];
  if (!random_token(token)) reject("completion-token generation failed");
  Text command = {0};
  argument(&command, pure);
  argument(&command, L"--norc");
  for (size_t i = 0; i < includes.count; ++i) {
    argument(&command, L"-I");
    argument(&command, includes.values[i]);
  }
  for (size_t i = 0; i < libraries.count; ++i) {
    argument(&command, L"-L");
    argument(&command, libraries.values[i]);
  }
  argument(&command, L"-x");
  argument(&command, script);
  argument(&command, token);

  Text search = {0};
  for (size_t i = 0; i < path_entries.count; ++i) {
    if (search.used) append(&search, L";");
    append(&search, path_entries.values[i]);
  }
  Text environment = {0};
  environment_entry(&environment, L"PATH", search.data);
  environment_entry(&environment, L"SystemRoot", working_directory);
  environment_entry(&environment, L"WINDIR", working_directory);
  append_n(&environment, L"", 1);

  Capture captures[2] = {{0}, {0}};
  DWORD result = launch(pure, &command, &environment, working_directory,
    timeout, token, captures);

  for (size_t i = 0; i < held.count; ++i) CloseHandle(held.values[i]);
  for (size_t i = 0; i < includes.count; ++i) free(includes.values[i]);
  for (size_t i = 0; i < libraries.count; ++i) free(libraries.values[i]);
  for (size_t i = 0; i < inputs.count; ++i) free(inputs.values[i]);
  for (size_t i = 0; i < path_entries.count; ++i) free(path_entries.values[i]);
  free(pure);
  free(script);
  free(working_directory);
  free(command.data);
  free(search.data);
  free(environment.data);
  free(captures[0].data);
  free(captures[1].data);
  fflush(stdout);
  fflush(stderr);
  ExitProcess(result);
}

#endif
