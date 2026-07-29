#define WIN32_LEAN_AND_MEAN
#include <windows.h>

#include <stdio.h>
#include <string.h>
#include <wchar.h>

#define PATH_CAPACITY 32768

typedef int (*octave_init_fn)(int, char **);
typedef void (*octave_fini_fn)(void);
typedef int (*octave_eval_fn)(const char *);
typedef const char *(*octave_last_error_fn)(void);

static int
utf8_to_wide(const char *source, wchar_t *destination)
{
  return MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, source, -1,
                             destination, PATH_CAPACITY) > 0;
}

int
main(int argc, char **argv)
{
  wchar_t loader_path[PATH_CAPACITY];
  wchar_t octave_root[PATH_CAPACITY];
  wchar_t expected_runtime[PATH_CAPACITY];
  wchar_t loaded_runtime[PATH_CAPACITY];
  wchar_t marker_path[PATH_CAPACITY];
  HMODULE loader;
  HMODULE runtime;
  octave_init_fn octave_init;
  octave_fini_fn octave_fini;
  octave_eval_fn octave_eval;
  octave_last_error_fn octave_last_error;
  char *octave_argv[] =
    { "octave", "--quiet", "--no-history", "--no-init-file" };
  int status;
  DWORD marker_length;
  DWORD loaded_length;
  wchar_t *separator;

  if (argc != 4 ||
      !utf8_to_wide(argv[1], loader_path) ||
      !utf8_to_wide(argv[2], octave_root) ||
      !utf8_to_wide(argv[3], expected_runtime))
    {
      fprintf(stderr,
              "usage: absolute_preload LOADER OCTAVE_ROOT EXPECTED_RUNTIME\n");
      return 2;
    }

  for (separator = expected_runtime; *separator; ++separator)
    if (*separator == L'/')
      *separator = L'\\';

  if (!SetEnvironmentVariableW(L"PURE_OCTAVE_ROOT", octave_root))
    {
      fprintf(stderr, "could not set PURE_OCTAVE_ROOT: %lu\n",
              GetLastError());
      return 3;
    }

  loader =
    LoadLibraryExW(loader_path, NULL,
                   LOAD_LIBRARY_SEARCH_DLL_LOAD_DIR |
                   LOAD_LIBRARY_SEARCH_SYSTEM32);
  if (!loader)
    {
      fprintf(stderr, "could not load stable loader: %lu\n", GetLastError());
      return 4;
    }

  octave_init = (octave_init_fn) GetProcAddress(loader, "octave_init");
  octave_fini = (octave_fini_fn) GetProcAddress(loader, "octave_fini");
  octave_eval = (octave_eval_fn) GetProcAddress(loader, "octave_eval");
  octave_last_error =
    (octave_last_error_fn) GetProcAddress(loader, "octave_last_error");
  if (!octave_init || !octave_fini || !octave_eval || !octave_last_error)
    {
      fprintf(stderr, "stable loader export set is incomplete\n");
      return 5;
    }

  status = octave_init(4, octave_argv);
  marker_length =
    GetEnvironmentVariableW(L"PURE_OCTAVE_POISON_MARKER", marker_path,
                            PATH_CAPACITY);
  if (marker_length > 0 && marker_length < PATH_CAPACITY &&
      GetFileAttributesW(marker_path) != INVALID_FILE_ATTRIBUTES)
    {
      fprintf(stderr, "POISON_DLLMAIN_OR_EXPORT_EXECUTED\n");
      return 6;
    }
  if (status != 0)
    {
      fprintf(stderr, "octave_init failed: %s\n", octave_last_error());
      return 7;
    }
  if (octave_eval("2 + 2;") != 0)
    {
      fprintf(stderr, "octave_eval failed: %s\n", octave_last_error());
      return 8;
    }

  runtime = GetModuleHandleW(L"liboctinterp-15.dll");
  loaded_length =
    runtime ? GetModuleFileNameW(runtime, loaded_runtime, PATH_CAPACITY) : 0;
  if (!runtime || loaded_length == 0 || loaded_length >= PATH_CAPACITY ||
      _wcsicmp(loaded_runtime, expected_runtime) != 0)
    {
      fwprintf(stderr, L"unexpected liboctinterp provenance: '%ls'\n",
               loaded_length ? loaded_runtime : L"<not loaded>");
      return 9;
    }

  octave_fini();
  printf("PURE_OCTAVE_ABSOLUTE_PRELOAD_OK\n");
  return 0;
}
