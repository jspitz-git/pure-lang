#define WIN32_LEAN_AND_MEAN
#include <windows.h>

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <wchar.h>

typedef struct {
  HANDLE process;
  HANDLE input;
} gplot_process;

static wchar_t *utf8_to_wide(const char *text)
{
  wchar_t *result;
  int count;

  if (!text)
    return NULL;
  count = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, text, -1,
                              NULL, 0);
  if (!count)
    return NULL;
  result = (wchar_t *)malloc((size_t)count * sizeof(wchar_t));
  if (!result)
    return NULL;
  if (!MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, text, -1,
                           result, count)) {
    free(result);
    return NULL;
  }
  return result;
}

static int remove_filename(wchar_t *path)
{
  wchar_t *backslash = wcsrchr(path, L'\\');
  wchar_t *slash = wcsrchr(path, L'/');
  wchar_t *separator =
    backslash && (!slash || backslash > slash) ? backslash : slash;

  if (!separator)
    return 0;
  *separator = L'\0';
  return 1;
}

__declspec(dllexport)
const char *gplot_default_executable(void)
{
  static char utf8_path[32768];
  wchar_t module_path[32768];
  wchar_t managed_path[32768];
  HMODULE module = NULL;
  DWORD length;
  int utf8_length;

  utf8_path[0] = '\0';
  if (!GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS |
                          GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
                          (LPCWSTR)(uintptr_t)&gplot_default_executable,
                          &module))
    return utf8_path;
  length = GetModuleFileNameW(module, module_path,
                              (DWORD)(sizeof(module_path) /
                                      sizeof(module_path[0])));
  if (!length || length >= sizeof(module_path) / sizeof(module_path[0]))
    return utf8_path;

  if (!remove_filename(module_path) ||
      !remove_filename(module_path) ||
      !remove_filename(module_path))
    return utf8_path;
  if (_snwprintf(managed_path,
                 sizeof(managed_path) / sizeof(managed_path[0]),
                 L"%ls\\tools\\gnuplot\\bin\\gnuplot.exe",
                 module_path) < 0)
    return utf8_path;
  managed_path[(sizeof(managed_path) / sizeof(managed_path[0])) - 1] = L'\0';

  utf8_length = WideCharToMultiByte(CP_UTF8, 0, managed_path, -1,
                                    utf8_path, (int)sizeof(utf8_path),
                                    NULL, NULL);
  if (!utf8_length)
    utf8_path[0] = '\0';
  return utf8_path;
}

__declspec(dllexport)
void *gplot_open(const char *executable)
{
  SECURITY_ATTRIBUTES attributes;
  STARTUPINFOW startup;
  PROCESS_INFORMATION process;
  gplot_process *handle = NULL;
  wchar_t *wide_executable = NULL;
  wchar_t *command_line = NULL;
  HANDLE child_input = INVALID_HANDLE_VALUE;
  HANDLE parent_input = INVALID_HANDLE_VALUE;
  size_t command_length;

  wide_executable = utf8_to_wide(executable);
  if (!wide_executable || !wide_executable[0])
    goto fail;
  command_length = wcslen(wide_executable);
  command_line = (wchar_t *)malloc((command_length + 3) * sizeof(wchar_t));
  if (!command_line)
    goto fail;
  command_line[0] = L'"';
  memcpy(command_line + 1, wide_executable,
         command_length * sizeof(wchar_t));
  command_line[command_length + 1] = L'"';
  command_line[command_length + 2] = L'\0';

  memset(&attributes, 0, sizeof(attributes));
  attributes.nLength = sizeof(attributes);
  attributes.bInheritHandle = TRUE;
  if (!CreatePipe(&child_input, &parent_input, &attributes, 0))
    goto fail;
  if (!SetHandleInformation(parent_input, HANDLE_FLAG_INHERIT, 0))
    goto fail;

  memset(&startup, 0, sizeof(startup));
  startup.cb = sizeof(startup);
  startup.dwFlags = STARTF_USESTDHANDLES;
  startup.hStdInput = child_input;
  startup.hStdOutput = GetStdHandle(STD_OUTPUT_HANDLE);
  startup.hStdError = GetStdHandle(STD_ERROR_HANDLE);
  memset(&process, 0, sizeof(process));
  if (!CreateProcessW(wide_executable, command_line, NULL, NULL, TRUE, 0,
                      NULL, NULL, &startup, &process))
    goto fail;

  CloseHandle(child_input);
  child_input = INVALID_HANDLE_VALUE;
  CloseHandle(process.hThread);
  handle = (gplot_process *)malloc(sizeof(*handle));
  if (!handle) {
    CloseHandle(parent_input);
    WaitForSingleObject(process.hProcess, INFINITE);
    CloseHandle(process.hProcess);
    parent_input = INVALID_HANDLE_VALUE;
    goto fail;
  }
  handle->process = process.hProcess;
  handle->input = parent_input;
  free(command_line);
  free(wide_executable);
  return handle;

fail:
  if (child_input != INVALID_HANDLE_VALUE)
    CloseHandle(child_input);
  if (parent_input != INVALID_HANDLE_VALUE)
    CloseHandle(parent_input);
  free(command_line);
  free(wide_executable);
  return NULL;
}

__declspec(dllexport)
int gplot_write(void *opaque, const char *command)
{
  gplot_process *handle = (gplot_process *)opaque;
  const char *cursor = command;
  size_t remaining;

  if (!handle || !command || handle->input == INVALID_HANDLE_VALUE)
    return -1;
  remaining = strlen(command);
  while (remaining) {
    DWORD chunk = remaining > UINT32_MAX ? UINT32_MAX : (DWORD)remaining;
    DWORD written = 0;
    if (!WriteFile(handle->input, cursor, chunk, &written, NULL) || !written)
      return -1;
    cursor += written;
    remaining -= written;
  }
  return 0;
}

__declspec(dllexport)
int gplot_close(void *opaque)
{
  gplot_process *handle = (gplot_process *)opaque;
  DWORD exit_code = (DWORD)-1;
  DWORD wait_result;

  if (!handle)
    return -1;
  if (handle->input != INVALID_HANDLE_VALUE) {
    CloseHandle(handle->input);
    handle->input = INVALID_HANDLE_VALUE;
  }
  wait_result = WaitForSingleObject(handle->process, INFINITE);
  if (wait_result == WAIT_OBJECT_0)
    GetExitCodeProcess(handle->process, &exit_code);
  CloseHandle(handle->process);
  free(handle);
  return wait_result == WAIT_OBJECT_0 ? (int)exit_code : -1;
}
