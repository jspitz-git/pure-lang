#define WIN32_LEAN_AND_MEAN
#include <windows.h>

static void
write_poison_marker(const char *source)
{
  wchar_t marker[MAX_PATH];
  DWORD marker_length =
    GetEnvironmentVariableW(L"PURE_OCTAVE_POISON_MARKER", marker, MAX_PATH);
  if (marker_length > 0 && marker_length < MAX_PATH)
    {
      HANDLE file =
        CreateFileW(marker, GENERIC_WRITE, FILE_SHARE_READ, NULL,
                    CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL);
      if (file != INVALID_HANDLE_VALUE)
        {
          DWORD written;
          WriteFile(file, source, (DWORD) lstrlenA(source), &written, NULL);
          CloseHandle(file);
        }
    }
}

__declspec(dllexport) void
pure_octave_poison_export(void)
{
  write_poison_marker("POISON_EXPORT_EXECUTED");
}

BOOL WINAPI
DllMain(HINSTANCE instance, DWORD reason, LPVOID reserved)
{
  (void) instance;
  (void) reserved;
  if (reason == DLL_PROCESS_ATTACH)
    write_poison_marker("POISON_DLLMAIN_EXECUTED");
  return TRUE;
}
