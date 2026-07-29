#define WIN32_LEAN_AND_MEAN
#define _WIN32_WINNT 0x0602
#include <windows.h>

#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "octave_bridge_api.h"

#define PURE_OCTAVE_ERROR_CAPACITY 4096
#define PURE_OCTAVE_PATH_CAPACITY 32768

typedef int (*impl_init_fn)(int, char **);
typedef void (*impl_fini_fn)(void);
typedef int (*impl_eval_fn)(const char *);
typedef const char *(*impl_last_error_fn)(void);
typedef const char *(*impl_abi_fn)(void);
typedef pure_expr *(*impl_get_fn)(const char *);
typedef pure_expr *(*impl_set_fn)(const char *, pure_expr *);
typedef pure_expr *(*impl_call_fn)(pure_expr *, int, pure_expr *);
typedef pure_expr *(*impl_func_fn)(pure_expr *);
typedef int (*impl_valuep_fn)(pure_expr *);
typedef void (*impl_free_fn)(void *);
typedef int (*impl_converters_fn)(int);

struct impl_functions
{
  impl_init_fn init;
  impl_fini_fn fini;
  impl_eval_fn eval;
  impl_last_error_fn last_error;
  impl_abi_fn abi;
  impl_get_fn get;
  impl_set_fn set;
  impl_call_fn call;
  impl_func_fn func;
  impl_valuep_fn valuep;
  impl_free_fn free_value;
  impl_converters_fn converters;
};

static struct impl_functions implementation;
static HMODULE implementation_module;
static HMODULE octave_runtime_module;
static DLL_DIRECTORY_COOKIE runtime_cookie;
static DLL_DIRECTORY_COOKIE module_cookie;
static char loader_error[PURE_OCTAVE_ERROR_CAPACITY];

extern IMAGE_DOS_HEADER __ImageBase;

static void
set_error(const char *format, ...)
{
  va_list args;
  va_start(args, format);
  _vsnprintf_s(loader_error, sizeof(loader_error), _TRUNCATE, format, args);
  va_end(args);
}

static void
copy_error(const char *message)
{
  _snprintf_s(loader_error, sizeof(loader_error), _TRUNCATE, "%s",
              message ? message : "unknown Octave bridge error");
}

static void
set_windows_error(const char *operation)
{
  DWORD code = GetLastError();
  wchar_t wide_message[1024];
  char utf8_message[2048];
  DWORD length = FormatMessageW(FORMAT_MESSAGE_FROM_SYSTEM |
                                  FORMAT_MESSAGE_IGNORE_INSERTS,
                                NULL, code, 0, wide_message,
                                (DWORD) (sizeof(wide_message) /
                                         sizeof(wide_message[0])),
                                NULL);
  if (length == 0 ||
      WideCharToMultiByte(CP_UTF8, 0, wide_message, (int) length,
                          utf8_message, sizeof(utf8_message) - 1,
                          NULL, NULL) <= 0)
    {
      set_error("%s failed with Windows error %lu", operation,
                (unsigned long) code);
      return;
    }

  {
    int utf8_length = WideCharToMultiByte(CP_UTF8, 0, wide_message,
                                          (int) length, utf8_message,
                                          sizeof(utf8_message) - 1,
                                          NULL, NULL);
    while (utf8_length > 0 &&
           (utf8_message[utf8_length - 1] == '\r' ||
            utf8_message[utf8_length - 1] == '\n' ||
            utf8_message[utf8_length - 1] == ' '))
      --utf8_length;
    utf8_message[utf8_length] = '\0';
  }
  set_error("%s failed with Windows error %lu: %s", operation,
            (unsigned long) code, utf8_message);
}

static int
append_path(wchar_t *destination, size_t capacity, const wchar_t *suffix)
{
  size_t length = wcslen(destination);
  size_t suffix_length = wcslen(suffix);
  int needs_separator =
    length > 0 && destination[length - 1] != L'\\' &&
    destination[length - 1] != L'/';

  if (length + (size_t) needs_separator + suffix_length + 1 > capacity)
    {
      set_error("Octave path is too long");
      return 0;
    }
  if (needs_separator)
    destination[length++] = L'\\';
  memcpy(destination + length, suffix,
         (suffix_length + 1) * sizeof(wchar_t));
  return 1;
}

static int
parent_directory(wchar_t *path)
{
  wchar_t *separator = wcsrchr(path, L'\\');
  wchar_t *slash = wcsrchr(path, L'/');
  if (slash && (!separator || slash > separator))
    separator = slash;
  if (!separator)
    {
      set_error("Could not determine the Pure installation prefix");
      return 0;
    }
  *separator = L'\0';
  return 1;
}

static int
module_prefix(wchar_t *prefix, size_t capacity)
{
  DWORD length = GetModuleFileNameW((HMODULE) &__ImageBase, prefix,
                                    (DWORD) capacity);
  if (length == 0 || length >= capacity)
    {
      set_windows_error("GetModuleFileNameW");
      return 0;
    }
  return parent_directory(prefix) && parent_directory(prefix) &&
         parent_directory(prefix);
}

static int
directory_exists(const wchar_t *path)
{
  DWORD attributes = GetFileAttributesW(path);
  return attributes != INVALID_FILE_ATTRIBUTES &&
         (attributes & FILE_ATTRIBUTE_DIRECTORY) != 0;
}

static int
read_utf8_file(const wchar_t *path, char *buffer, size_t capacity,
               int missing_is_ok)
{
  DWORD open_error;
  HANDLE file = CreateFileW(path, GENERIC_READ, FILE_SHARE_READ, NULL,
                            OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, NULL);
  DWORD bytes_read;
  DWORD size;
  if (file == INVALID_HANDLE_VALUE)
    {
      open_error = GetLastError();
      if (missing_is_ok &&
          (open_error == ERROR_FILE_NOT_FOUND ||
           open_error == ERROR_PATH_NOT_FOUND))
        return 0;
      SetLastError(open_error);
      set_windows_error("CreateFileW");
      return -1;
    }

  size = GetFileSize(file, NULL);
  if (size == INVALID_FILE_SIZE || size + 1 > capacity)
    {
      CloseHandle(file);
      set_error("Octave configuration file is too large");
      return -1;
    }
  if (!ReadFile(file, buffer, size, &bytes_read, NULL) ||
      bytes_read != size)
    {
      CloseHandle(file);
      set_windows_error("ReadFile");
      return -1;
    }
  CloseHandle(file);
  buffer[size] = '\0';
  return 1;
}

static char *
trim_utf8(char *text)
{
  char *begin = text;
  char *end;
  if (strlen(begin) >= 3 &&
      (unsigned char) begin[0] == 0xef &&
      (unsigned char) begin[1] == 0xbb &&
      (unsigned char) begin[2] == 0xbf)
    begin += 3;
  while (*begin == ' ' || *begin == '\t' ||
         *begin == '\r' || *begin == '\n')
    ++begin;
  end = begin + strlen(begin);
  while (end > begin &&
         (end[-1] == ' ' || end[-1] == '\t' ||
          end[-1] == '\r' || end[-1] == '\n'))
    --end;
  *end = '\0';
  return begin;
}

static int
utf8_to_wide(const char *source, wchar_t *destination, size_t capacity)
{
  int length = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, source, -1,
                                   destination, (int) capacity);
  if (length <= 0)
    {
      set_windows_error("MultiByteToWideChar");
      return 0;
    }
  return 1;
}

static int
select_root(wchar_t *root, size_t capacity, wchar_t *prefix)
{
  DWORD environment_length =
    GetEnvironmentVariableW(L"PURE_OCTAVE_ROOT", root, (DWORD) capacity);
  if (environment_length > 0)
    {
      if (environment_length >= capacity)
        {
          set_error("PURE_OCTAVE_ROOT is too long");
          return 0;
        }
      return 1;
    }
  if (GetLastError() != ERROR_ENVVAR_NOT_FOUND)
    {
      set_windows_error("GetEnvironmentVariableW(PURE_OCTAVE_ROOT)");
      return 0;
    }

  {
    wchar_t config_path[PURE_OCTAVE_PATH_CAPACITY];
    char config_utf8[PURE_OCTAVE_PATH_CAPACITY];
    int config_result;
    memcpy(config_path, prefix, (wcslen(prefix) + 1) * sizeof(wchar_t));
    if (!append_path(config_path, PURE_OCTAVE_PATH_CAPACITY,
                     L"etc\\pure\\octave-root.conf"))
      return 0;
    config_result = read_utf8_file(config_path, config_utf8,
                                   sizeof(config_utf8), 1);
    if (config_result < 0)
      return 0;
    if (config_result > 0)
      {
        char *configured_root = trim_utf8(config_utf8);
        if (*configured_root == '\0')
          {
            set_error("etc/pure/octave-root.conf is empty");
            return 0;
          }
        return utf8_to_wide(configured_root, root, capacity);
      }
  }

  memcpy(root, prefix, (wcslen(prefix) + 1) * sizeof(wchar_t));
  return append_path(root, capacity, L"tools\\octave");
}

static int
validate_root(const wchar_t *root)
{
  wchar_t fingerprint_path[PURE_OCTAVE_PATH_CAPACITY];
  char fingerprint_text[256];
  char *fingerprint;

  if (!directory_exists(root))
    {
      set_error("The selected Octave root does not exist");
      return 0;
    }
  memcpy(fingerprint_path, root, (wcslen(root) + 1) * sizeof(wchar_t));
  if (!append_path(fingerprint_path, PURE_OCTAVE_PATH_CAPACITY,
                   L"" PURE_OCTAVE_FINGERPRINT_FILE))
    return 0;
  if (read_utf8_file(fingerprint_path, fingerprint_text,
                     sizeof(fingerprint_text), 0) <= 0)
    return 0;
  fingerprint = trim_utf8(fingerprint_text);
  if (strcmp(fingerprint, PURE_OCTAVE_SIGNING_FINGERPRINT) != 0)
    {
      set_error("The selected Octave root has an unsupported fingerprint");
      return 0;
    }
  return 1;
}

static FARPROC
require_symbol(HMODULE module, const char *name)
{
  FARPROC symbol = GetProcAddress(module, name);
  if (!symbol)
    set_windows_error(name);
  return symbol;
}

static int
load_implementation(void)
{
  wchar_t prefix[PURE_OCTAVE_PATH_CAPACITY];
  wchar_t root[PURE_OCTAVE_PATH_CAPACITY];
  wchar_t runtime_path[PURE_OCTAVE_PATH_CAPACITY];
  wchar_t octave_module_path[PURE_OCTAVE_PATH_CAPACITY];
  wchar_t octave_home[PURE_OCTAVE_PATH_CAPACITY];
  wchar_t implementation_path[PURE_OCTAVE_PATH_CAPACITY];
  wchar_t octave_runtime_dll[PURE_OCTAVE_PATH_CAPACITY];
  struct impl_functions candidate;
  wchar_t loaded_runtime_dll[PURE_OCTAVE_PATH_CAPACITY];
  wchar_t normalized_runtime_dll[PURE_OCTAVE_PATH_CAPACITY];
  const char *abi;

  if (implementation_module)
    return 1;
  loader_error[0] = '\0';

  if (!module_prefix(prefix, PURE_OCTAVE_PATH_CAPACITY) ||
      !select_root(root, PURE_OCTAVE_PATH_CAPACITY, prefix) ||
      !validate_root(root))
    return 0;

  if (!SetDefaultDllDirectories(LOAD_LIBRARY_SEARCH_SYSTEM32 |
                                LOAD_LIBRARY_SEARCH_USER_DIRS))
    {
      set_windows_error("SetDefaultDllDirectories");
      return 0;
    }

  memcpy(runtime_path, root, (wcslen(root) + 1) * sizeof(wchar_t));
  memcpy(octave_module_path, root, (wcslen(root) + 1) * sizeof(wchar_t));
  memcpy(octave_home, root, (wcslen(root) + 1) * sizeof(wchar_t));
  if (!append_path(runtime_path, PURE_OCTAVE_PATH_CAPACITY,
                   L"mingw64\\bin") ||
      !append_path(octave_module_path, PURE_OCTAVE_PATH_CAPACITY,
                   L"mingw64\\lib\\octave\\11.3.0") ||
      !append_path(octave_home, PURE_OCTAVE_PATH_CAPACITY, L"mingw64"))
    return 0;
  if (!directory_exists(runtime_path) ||
      !directory_exists(octave_module_path))
    {
      set_error("The selected Octave root is missing controlled runtime directories");
      return 0;
    }

  runtime_cookie = AddDllDirectory(runtime_path);
  module_cookie = AddDllDirectory(octave_module_path);
  if (!runtime_cookie || !module_cookie)
    {
      set_windows_error("AddDllDirectory");
      return 0;
    }
  if (_wputenv_s(L"OCTAVE_HOME", octave_home) != 0 ||
      _wputenv_s(L"OCTAVE_EXEC_HOME", octave_home) != 0)
    {
      set_error("Could not publish the controlled Octave root to the UCRT environment");
      return 0;
    }

  memcpy(octave_runtime_dll, runtime_path,
         (wcslen(runtime_path) + 1) * sizeof(wchar_t));
  if (!append_path(octave_runtime_dll, PURE_OCTAVE_PATH_CAPACITY,
                   L"liboctinterp-15.dll"))
    return 0;
  {
    DWORD normalized_length =
      GetFullPathNameW(octave_runtime_dll, PURE_OCTAVE_PATH_CAPACITY,
                       normalized_runtime_dll, NULL);
    if (normalized_length == 0 ||
        normalized_length >= PURE_OCTAVE_PATH_CAPACITY)
      {
        set_windows_error("GetFullPathNameW(liboctinterp-15.dll)");
        return 0;
      }
    memcpy(octave_runtime_dll, normalized_runtime_dll,
           (normalized_length + 1) * sizeof(wchar_t));
  }
  octave_runtime_module =
    LoadLibraryExW(octave_runtime_dll, NULL,
                   LOAD_LIBRARY_SEARCH_DLL_LOAD_DIR |
                   LOAD_LIBRARY_SEARCH_USER_DIRS |
                   LOAD_LIBRARY_SEARCH_SYSTEM32);
  if (!octave_runtime_module)
    {
      set_windows_error("LoadLibraryExW(liboctinterp-15.dll)");
      return 0;
    }
  {
    DWORD loaded_length =
      GetModuleFileNameW(octave_runtime_module, loaded_runtime_dll,
                         PURE_OCTAVE_PATH_CAPACITY);
    if (loaded_length == 0 ||
        loaded_length >= PURE_OCTAVE_PATH_CAPACITY ||
        _wcsicmp(loaded_runtime_dll, octave_runtime_dll) != 0)
      {
        set_error("liboctinterp-15.dll was not loaded from the explicit Octave root");
        return 0;

      }
  }
  memcpy(implementation_path, prefix,
         (wcslen(prefix) + 1) * sizeof(wchar_t));
  if (!append_path(implementation_path, PURE_OCTAVE_PATH_CAPACITY,
                   L"lib\\pure\\octave_bridge_impl.dll"))
    return 0;
  implementation_module =
    LoadLibraryExW(implementation_path, NULL,
                   LOAD_LIBRARY_SEARCH_DLL_LOAD_DIR |
                   LOAD_LIBRARY_SEARCH_USER_DIRS);
  if (!implementation_module)
    {
      set_windows_error("LoadLibraryExW(octave_bridge_impl.dll)");
      return 0;
    }

  memset(&candidate, 0, sizeof(candidate));
  candidate.init = (impl_init_fn)
    require_symbol(implementation_module, "pure_octave_impl_init");
  candidate.fini = (impl_fini_fn)
    require_symbol(implementation_module, "pure_octave_impl_fini");
  candidate.eval = (impl_eval_fn)
    require_symbol(implementation_module, "pure_octave_impl_eval");
  candidate.last_error = (impl_last_error_fn)
    require_symbol(implementation_module, "pure_octave_impl_last_error");
  candidate.abi = (impl_abi_fn)
    require_symbol(implementation_module, "pure_octave_impl_abi");
  candidate.get = (impl_get_fn)
    require_symbol(implementation_module, "pure_octave_impl_get");
  candidate.set = (impl_set_fn)
    require_symbol(implementation_module, "pure_octave_impl_set");
  candidate.call = (impl_call_fn)
    require_symbol(implementation_module, "pure_octave_impl_call");
  candidate.func = (impl_func_fn)
    require_symbol(implementation_module, "pure_octave_impl_func");
  candidate.valuep = (impl_valuep_fn)
    require_symbol(implementation_module, "pure_octave_impl_valuep");
  candidate.free_value = (impl_free_fn)
    require_symbol(implementation_module, "pure_octave_impl_free");
  candidate.converters = (impl_converters_fn)
    require_symbol(implementation_module, "pure_octave_impl_converters");
  if (!candidate.init || !candidate.fini || !candidate.eval ||
      !candidate.last_error || !candidate.abi)
    {
      FreeLibrary(implementation_module);
      implementation_module = NULL;
      return 0;
    }
  if (!candidate.get || !candidate.set || !candidate.call ||
      !candidate.func || !candidate.valuep || !candidate.free_value ||
      !candidate.converters)
    {
      FreeLibrary(implementation_module);
      implementation_module = NULL;
      return 0;
    }
  abi = candidate.abi();
  if (!abi || strcmp(abi, PURE_OCTAVE_BRIDGE_ABI) != 0)
    {
      set_error("octave_bridge_impl.dll has an incompatible ABI");
      FreeLibrary(implementation_module);
      implementation_module = NULL;
      return 0;
    }

  implementation = candidate;
  return 1;
}

PURE_OCTAVE_LOADER_API int
octave_init(int argc, char **argv)
{
  int result;
  if (!load_implementation())
    {
      if (loader_error[0] == '\0')
        set_error("Octave implementation loading failed without a diagnostic");
      return -100;
    }
  result = implementation.init(argc, argv);
  if (result != 0)
    copy_error(implementation.last_error());
  else
    loader_error[0] = '\0';
  return result;
}

PURE_OCTAVE_LOADER_API void
octave_fini(void)
{
  if (!implementation_module)
    return;
  implementation.fini();
  copy_error(implementation.last_error());
}

PURE_OCTAVE_LOADER_API int
octave_eval(const char *command)
{
  int result;
  if (!load_implementation())
    {
      if (loader_error[0] == '\0')
        set_error("Octave implementation loading failed without a diagnostic");
      return -100;
    }
  result = implementation.eval(command);
  if (result != 0)
    copy_error(implementation.last_error());
  else
    loader_error[0] = '\0';
  return result;
}

PURE_OCTAVE_LOADER_API pure_expr *
octave_get(const char *id)
{
  pure_expr *result;
  const char *error;
  if (!load_implementation())
    return NULL;
  result = implementation.get(id);
  error = implementation.last_error();
  if (error && *error)
    copy_error(error);
  else
    loader_error[0] = '\0';
  return result;
}

PURE_OCTAVE_LOADER_API pure_expr *
octave_set(const char *id, pure_expr *value)
{
  pure_expr *result;
  const char *error;
  if (!load_implementation())
    return NULL;
  result = implementation.set(id, value);
  error = implementation.last_error();
  if (error && *error)
    copy_error(error);
  else
    loader_error[0] = '\0';
  return result;
}

PURE_OCTAVE_LOADER_API pure_expr *
octave_call(pure_expr *function, int nargout, pure_expr *arguments)
{
  pure_expr *result;
  const char *error;
  if (!load_implementation())
    return NULL;
  result = implementation.call(function, nargout, arguments);
  error = implementation.last_error();
  if (error && *error)
    copy_error(error);
  else
    loader_error[0] = '\0';
  return result;
}

PURE_OCTAVE_LOADER_API pure_expr *
octave_func(pure_expr *function)
{
  pure_expr *result;
  const char *error;
  if (!load_implementation())
    return NULL;
  result = implementation.func(function);
  error = implementation.last_error();
  if (error && *error)
    copy_error(error);
  else
    loader_error[0] = '\0';
  return result;
}

PURE_OCTAVE_LOADER_API int
octave_valuep(pure_expr *value)
{
  int result;
  const char *error;
  if (!load_implementation())
    return 0;
  result = implementation.valuep(value);
  error = implementation.last_error();
  if (error && *error)
    copy_error(error);
  else
    loader_error[0] = '\0';
  return result;
}

PURE_OCTAVE_LOADER_API void
octave_free(void *value)
{
  const char *error;
  if (!implementation_module || !implementation.free_value)
    {
      set_error("Octave implementation is unavailable during value finalization");
      return;
    }
  implementation.free_value(value);
  error = implementation.last_error();
  if (error && *error)
    copy_error(error);
  else
    loader_error[0] = '\0';
}

PURE_OCTAVE_LOADER_API int
octave_converters(int enable)
{
  int result;
  const char *error;
  if (!load_implementation())
    return 0;
  result = implementation.converters(enable);
  error = implementation.last_error();
  if (error && *error)
    copy_error(error);
  else
    loader_error[0] = '\0';
  return result;
}

PURE_OCTAVE_LOADER_API const char *
octave_last_error(void)
{
  if (implementation_module && implementation.last_error)
    {
      const char *implementation_error = implementation.last_error();
      if (implementation_error && *implementation_error)
        copy_error(implementation_error);
    }
  return loader_error;
}
