#define WIN32_LEAN_AND_MEAN
#include <windows.h>

#include <fcntl.h>
#include <io.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <wchar.h>
#include <wctype.h>

struct capture_reader {
  HANDLE input;
  HANDLE output;
  volatile LONG saw_data;
  DWORD error;
};

static int fail(const wchar_t *message, const wchar_t *path) {
  if (path != NULL)
    fwprintf(stderr, L"run_pure_test: %ls: %ls\n", message, path);
  else
    fwprintf(stderr, L"run_pure_test: %ls\n", message);
  return 1;
}

static wchar_t *full_path(const wchar_t *path) {
  DWORD size = GetFullPathNameW(path, 0, NULL, NULL);
  wchar_t *result;
  if (size == 0) return NULL;
  result = (wchar_t *)calloc((size_t)size, sizeof(*result));
  if (result == NULL || GetFullPathNameW(path, size, result, NULL) == 0) {
    free(result);
    return NULL;
  }
  while (wcslen(result) > 3 &&
         (result[wcslen(result) - 1] == L'\\' ||
          result[wcslen(result) - 1] == L'/'))
    result[wcslen(result) - 1] = L'\0';
  return result;
}

static int path_has_reparse_component(const wchar_t *path) {
  wchar_t *probe = full_path(path);
  wchar_t *root_end;
  wchar_t *cursor;
  int result = 0;
  if (probe == NULL) return -1;
  root_end = probe + 3;
  if (wcsncmp(probe, L"\\\\", 2) == 0) {
    root_end = wcschr(probe + 2, L'\\');
    if (root_end != NULL) root_end = wcschr(root_end + 1, L'\\');
    if (root_end == NULL) {
      free(probe);
      return -1;
    }
    ++root_end;
  }
  for (cursor = root_end; ; ++cursor) {
    wchar_t saved;
    DWORD attributes;
    if (*cursor != L'\\' && *cursor != L'/' && *cursor != L'\0') continue;
    saved = *cursor;
    *cursor = L'\0';
    attributes = GetFileAttributesW(probe);
    *cursor = saved;
    if (attributes == INVALID_FILE_ATTRIBUTES) {
      result = -1;
      break;
    }
    if ((attributes & FILE_ATTRIBUTE_REPARSE_POINT) != 0) {
      result = 1;
      break;
    }
    if (saved == L'\0') break;
  }
  free(probe);
  return result;
}

static int validate_path(const wchar_t *path, int directory,
                         int reject_reparse, const wchar_t *label,
                         wchar_t **normalized) {
  DWORD attributes;
  wchar_t *absolute = full_path(path);
  int reparse;
  if (absolute == NULL) return fail(L"cannot normalize path", path);
  attributes = GetFileAttributesW(absolute);
  if (attributes == INVALID_FILE_ATTRIBUTES ||
      (!!(attributes & FILE_ATTRIBUTE_DIRECTORY)) != !!directory) {
    free(absolute);
    return fail(directory ? L"expected an existing directory"
                          : L"expected an existing regular file", path);
  }
  if (reject_reparse) {
    reparse = path_has_reparse_component(absolute);
    if (reparse != 0) {
      free(absolute);
      return fail(reparse > 0 ? L"reparse path is forbidden"
                              : L"cannot inspect path for reparse points",
                  label);
    }
  }
  *normalized = absolute;
  return 0;
}

static wchar_t *parent_path(const wchar_t *path) {
  wchar_t *copy = _wcsdup(path);
  wchar_t *slash;
  if (copy == NULL) return NULL;
  slash = wcsrchr(copy, L'\\');
  if (slash == NULL) slash = wcsrchr(copy, L'/');
  if (slash == NULL || slash == copy) {
    free(copy);
    return NULL;
  }
  *slash = L'\0';
  return copy;
}

static const wchar_t *base_name(const wchar_t *path) {
  const wchar_t *backslash = wcsrchr(path, L'\\');
  const wchar_t *slash = wcsrchr(path, L'/');
  const wchar_t *base = backslash != NULL ? backslash + 1 : path;
  if (slash != NULL && slash + 1 > base) base = slash + 1;
  return base;
}

static char *sentinel_path_text(const wchar_t *path) {
  wchar_t *folded = _wcsdup(path);
  int count;
  char *utf8;
  wchar_t *cursor;
  if (folded == NULL) return NULL;
  for (cursor = folded; *cursor != L'\0'; ++cursor) {
    if (*cursor == L'\\') *cursor = L'/';
    *cursor = towlower(*cursor);
  }
  count = WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, folded, -1,
                              NULL, 0, NULL, NULL);
  if (count == 0) {
    free(folded);
    return NULL;
  }
  utf8 = (char *)malloc((size_t)count);
  if (utf8 == NULL ||
      WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, folded, -1,
                          utf8, count, NULL, NULL) == 0) {
    free(folded);
    free(utf8);
    return NULL;
  }
  free(folded);
  return utf8;
}

static int validate_work_directory(const wchar_t *work,
                                   const wchar_t *source) {
  wchar_t *neutral = full_path(L"C:/Windows");
  wchar_t *contract = NULL;
  wchar_t *binary = NULL;
  wchar_t *sentinel = NULL;
  char *source_text = NULL;
  char *binary_text = NULL;
  char *expected = NULL;
  char actual[8192];
  const wchar_t *leaf;
  HANDLE file = INVALID_HANDLE_VALUE;
  DWORD size;
  DWORD read_size;
  int result = 1;

  if (neutral != NULL && _wcsicmp(work, neutral) == 0) {
    free(neutral);
    return 0;
  }
  free(neutral);

  leaf = base_name(work);
  if (_wcsicmp(leaf, L"runner") != 0 &&
      _wcsicmp(leaf, L"cleanup") != 0 &&
      _wcsicmp(leaf, L"access") != 0)
    return fail(L"WORK_DIRECTORY is not a fixed contract leaf", work);
  contract = parent_path(work);
  if (contract == NULL ||
      _wcsicmp(base_name(contract), L"pure-odbc-contract") != 0) {
    fail(L"WORK_DIRECTORY is outside pure-odbc-contract", work);
    goto done;
  }
  binary = parent_path(contract);
  if (binary == NULL) {
    fail(L"cannot derive build directory from WORK_DIRECTORY", work);
    goto done;
  }
  sentinel = (wchar_t *)malloc(
      (wcslen(work) + wcslen(L"\\.pure-odbc-contract-owner") + 1) *
      sizeof(*sentinel));
  if (sentinel == NULL) goto done;
  wcscpy(sentinel, work);
  wcscat(sentinel, L"\\.pure-odbc-contract-owner");
  {
    wchar_t *validated = NULL;
    if (validate_path(sentinel, 0, 1, L"WORK_DIRECTORY ownership sentinel",
                      &validated) != 0)
      goto done;
    free(validated);
  }

  source_text = sentinel_path_text(source);
  binary_text = sentinel_path_text(binary);
  if (source_text == NULL || binary_text == NULL) goto done;
  size = (DWORD)(strlen(source_text) + strlen(binary_text) + 128);
  expected = (char *)malloc((size_t)size);
  if (expected == NULL) goto done;
  _snprintf(expected, size,
            "pure-odbc-contract-v1\r\nleaf=%ls\r\nsource=%s\r\nbinary=%s\r\n",
            leaf, source_text, binary_text);
  expected[size - 1] = '\0';

  file = CreateFileW(sentinel, GENERIC_READ, FILE_SHARE_READ, NULL,
                     OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, NULL);
  if (file == INVALID_HANDLE_VALUE) {
    fail(L"cannot read WORK_DIRECTORY ownership sentinel", sentinel);
    goto done;
  }
  size = GetFileSize(file, NULL);
  if (size == INVALID_FILE_SIZE || size >= sizeof(actual) ||
      !ReadFile(file, actual, size, &read_size, NULL) || read_size != size) {
    fail(L"invalid WORK_DIRECTORY ownership sentinel", sentinel);
    goto done;
  }
  actual[size] = '\0';
  if (strcmp(actual, expected) != 0) {
    fail(L"WORK_DIRECTORY ownership sentinel does not match", sentinel);
    goto done;
  }
  result = 0;

done:
  if (file != INVALID_HANDLE_VALUE) CloseHandle(file);
  free(contract);
  free(binary);
  free(sentinel);
  free(source_text);
  free(binary_text);
  free(expected);
  return result;
}

static int append_quoted(wchar_t **cursor, size_t *remaining,
                         const wchar_t *argument) {
  size_t needed = 3;
  const wchar_t *scan;
  size_t backslashes = 0;
  for (scan = argument; *scan != L'\0'; ++scan) {
    if (*scan == L'\\') {
      ++backslashes;
    } else {
      needed += backslashes + (*scan == L'"' ? backslashes + 2 : 1);
      backslashes = 0;
    }
  }
  needed += backslashes * 2;
  if (needed > *remaining) return 1;
  *(*cursor)++ = L'"';
  backslashes = 0;
  for (scan = argument; *scan != L'\0'; ++scan) {
    if (*scan == L'\\') {
      ++backslashes;
      continue;
    }
    while (backslashes-- > 0) *(*cursor)++ = L'\\';
    backslashes = 0;
    if (*scan == L'"') {
      *(*cursor)++ = L'\\';
      *(*cursor)++ = L'"';
    } else {
      *(*cursor)++ = *scan;
    }
  }
  while (backslashes-- > 0) {
    *(*cursor)++ = L'\\';
    *(*cursor)++ = L'\\';
  }
  *(*cursor)++ = L'"';
  *(*cursor)++ = L' ';
  **cursor = L'\0';
  *remaining -= needed;
  return 0;
}

static wchar_t *build_command(const wchar_t *pure, const wchar_t *source,
                              const wchar_t *module, const wchar_t *script) {
  const wchar_t *arguments[] = {
    pure, L"--norc", L"-I", source, L"-L", module, L"-x", script
  };
  size_t capacity = 64;
  size_t remaining;
  wchar_t *command;
  wchar_t *cursor;
  size_t index;
  for (index = 0; index < sizeof(arguments) / sizeof(arguments[0]); ++index)
    capacity += wcslen(arguments[index]) * 2 + 4;
  command = (wchar_t *)calloc(capacity, sizeof(*command));
  if (command == NULL) return NULL;
  cursor = command;
  remaining = capacity;
  for (index = 0; index < sizeof(arguments) / sizeof(arguments[0]); ++index) {
    if (append_quoted(&cursor, &remaining, arguments[index]) != 0) {
      free(command);
      return NULL;
    }
  }
  if (cursor > command) cursor[-1] = L'\0';
  return command;
}

static DWORD WINAPI capture_thread(void *opaque) {
  struct capture_reader *reader = (struct capture_reader *)opaque;
  char buffer[4096];
  DWORD count;
  for (;;) {
    if (!ReadFile(reader->input, buffer, sizeof(buffer), &count, NULL)) {
      DWORD error = GetLastError();
      if (error != ERROR_BROKEN_PIPE) reader->error = error;
      break;
    }
    if (count == 0) break;
    InterlockedExchange(&reader->saw_data, 1);
    {
      DWORD offset = 0;
      while (offset < count) {
        DWORD written;
        if (!WriteFile(reader->output, buffer + offset, count - offset,
                       &written, NULL)) {
          reader->error = GetLastError();
          return 1;
        }
        offset += written;
      }
    }
  }
  return reader->error == 0 ? 0 : 1;
}

static int fake_child(int argc, wchar_t **argv, const wchar_t *name) {
  wchar_t cwd[32768];
  wchar_t *path;
  wchar_t *purelib;
  int index;
  if (_wcsicmp(name, L"fake-stderr.exe") == 0) {
    fwprintf(stderr, L"ZERO_EXIT_STDERR_SENTINEL\n");
    return 0;
  }
  if (_wcsicmp(name, L"fake-exit37.exe") == 0) {
    wprintf(L"EXIT_STDOUT_SENTINEL\n");
    return 37;
  }
  if (_wcsicmp(name, L"fake-exit77.exe") == 0) {
    wprintf(L"SKIP_STDOUT_SENTINEL\n");
    return 77;
  }
  if (_wcsicmp(name, L"fake-success.exe") != 0) return -1;
  GetCurrentDirectoryW((DWORD)(sizeof(cwd) / sizeof(cwd[0])), cwd);
  path = _wgetenv(L"PATH");
  purelib = _wgetenv(L"PURELIB");
  wprintf(L"RUNNER_STDOUT_SENTINEL\n");
  wprintf(L"EFFECTIVE_CWD=%ls\n", cwd);
  wprintf(L"EFFECTIVE_PATH=%ls\n", path != NULL ? path : L"UNSET");
  wprintf(L"EFFECTIVE_PURELIB=%ls\n", purelib != NULL ? L"SET" : L"UNSET");
  for (index = 1; index < argc; ++index)
    wprintf(L"EFFECTIVE_ARG_%d=%ls\n", index, argv[index]);
  return 0;
}

int wmain(int argc, wchar_t **argv) {
  wchar_t module_name[32768];
  int fake_result;
  wchar_t *pure = NULL;
  wchar_t *source = NULL;
  wchar_t *module = NULL;
  wchar_t *script = NULL;
  wchar_t *work = NULL;
  wchar_t *pure_bin = NULL;
  wchar_t *windows = NULL;
  wchar_t *environment_path = NULL;
  wchar_t *command = NULL;
  SECURITY_ATTRIBUTES security = {sizeof(security), NULL, TRUE};
  HANDLE stdout_read = NULL, stdout_write = NULL;
  HANDLE stderr_read = NULL, stderr_write = NULL;
  HANDLE stdout_thread = NULL, stderr_thread = NULL;
  PROCESS_INFORMATION process = {0};
  STARTUPINFOW startup = {0};
  struct capture_reader stdout_capture = {0};
  struct capture_reader stderr_capture = {0};
  DWORD exit_code = 1;
  int result = 1;

  if (GetModuleFileNameW(NULL, module_name,
                         (DWORD)(sizeof(module_name) / sizeof(module_name[0]))) == 0)
    return fail(L"cannot identify executable", NULL);
  fake_result = fake_child(argc, argv, base_name(module_name));
  if (fake_result >= 0) return fake_result;
  if (argc != 6)
    return fail(L"usage: run_pure_test PURE SOURCE MODULE SCRIPT WORK", NULL);
  startup.cb = sizeof(startup);

  if (validate_path(argv[1], 0, 1, L"PURE_EXECUTABLE", &pure) != 0 ||
      validate_path(argv[2], 1, 1, L"PURE_SOURCE_DIR", &source) != 0 ||
      validate_path(argv[3], 1, 1, L"MODULE_DIR", &module) != 0 ||
      validate_path(argv[4], 0, 1, L"SCRIPT", &script) != 0 ||
      validate_path(argv[5], 1, 1, L"WORK_DIRECTORY", &work) != 0)
    goto done;
  if (validate_work_directory(work, source) != 0) goto done;

  pure_bin = parent_path(pure);
  windows = full_path(L"C:/Windows");
  if (pure_bin == NULL || windows == NULL) {
    fail(L"cannot construct child PATH", NULL);
    goto done;
  }
  environment_path = (wchar_t *)malloc(
      (wcslen(module) + wcslen(pure_bin) + wcslen(windows) * 2 + 32) *
      sizeof(*environment_path));
  if (environment_path == NULL) goto done;
  swprintf(environment_path,
           wcslen(module) + wcslen(pure_bin) + wcslen(windows) * 2 + 32,
           L"%ls;%ls;%ls\\System32;%ls", module, pure_bin, windows, windows);
  if (!SetEnvironmentVariableW(L"PATH", environment_path) ||
      !SetEnvironmentVariableW(L"PURELIB", NULL)) {
    fail(L"cannot set strict child environment", NULL);
    goto done;
  }
  command = build_command(pure, source, module, script);
  if (command == NULL) goto done;

  if (!CreatePipe(&stdout_read, &stdout_write, &security, 0) ||
      !SetHandleInformation(stdout_read, HANDLE_FLAG_INHERIT, 0) ||
      !CreatePipe(&stderr_read, &stderr_write, &security, 0) ||
      !SetHandleInformation(stderr_read, HANDLE_FLAG_INHERIT, 0)) {
    fail(L"cannot create child output pipes", NULL);
    goto done;
  }
  startup.dwFlags = STARTF_USESTDHANDLES;
  startup.hStdInput = GetStdHandle(STD_INPUT_HANDLE);
  startup.hStdOutput = stdout_write;
  startup.hStdError = stderr_write;
  if (!CreateProcessW(pure, command, NULL, NULL, TRUE, CREATE_NO_WINDOW,
                      NULL, work, &startup, &process)) {
    fail(L"cannot start PURE_EXECUTABLE", pure);
    goto done;
  }
  CloseHandle(stdout_write);
  stdout_write = NULL;
  CloseHandle(stderr_write);
  stderr_write = NULL;

  stdout_capture.input = stdout_read;
  stdout_capture.output = GetStdHandle(STD_OUTPUT_HANDLE);
  stderr_capture.input = stderr_read;
  stderr_capture.output = GetStdHandle(STD_ERROR_HANDLE);
  stdout_thread = CreateThread(NULL, 0, capture_thread, &stdout_capture, 0, NULL);
  stderr_thread = CreateThread(NULL, 0, capture_thread, &stderr_capture, 0, NULL);
  if (stdout_thread == NULL || stderr_thread == NULL) {
    TerminateProcess(process.hProcess, 1);
    fail(L"cannot create output capture threads", NULL);
    goto done;
  }
  WaitForSingleObject(process.hProcess, INFINITE);
  WaitForSingleObject(stdout_thread, INFINITE);
  WaitForSingleObject(stderr_thread, INFINITE);
  if (!GetExitCodeProcess(process.hProcess, &exit_code) ||
      stdout_capture.error != 0 || stderr_capture.error != 0) {
    fail(L"cannot collect child result", NULL);
    goto done;
  }
  if (stderr_capture.saw_data) {
    fail(L"pure-odbc test emitted stderr", NULL);
    goto done;
  }
  result = (int)exit_code;

done:
  if (stdout_write != NULL) CloseHandle(stdout_write);
  if (stderr_write != NULL) CloseHandle(stderr_write);
  if (stdout_thread != NULL) CloseHandle(stdout_thread);
  if (stderr_thread != NULL) CloseHandle(stderr_thread);
  if (stdout_read != NULL) CloseHandle(stdout_read);
  if (stderr_read != NULL) CloseHandle(stderr_read);
  if (process.hThread != NULL) CloseHandle(process.hThread);
  if (process.hProcess != NULL) CloseHandle(process.hProcess);
  free(pure);
  free(source);
  free(module);
  free(script);
  free(work);
  free(pure_bin);
  free(windows);
  free(environment_path);
  free(command);
  return result;
}
