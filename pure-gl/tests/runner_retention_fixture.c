#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <stdio.h>
#include <wchar.h>
int wmain(int argc, wchar_t **argv) {
  const wchar_t *script = NULL;
  for (int i = 1; i+1 < argc; ++i)
    if (!wcscmp(argv[i], L"-x")) script = argv[i+1];
  if (!script || argc < 2) return 90;
  FILE *file = _wfopen(script, L"rt");
  wchar_t ready_name[128], release_name[128];
  if (!file || !fgetws(ready_name, 128, file) ||
      !fgetws(release_name, 128, file)) return 91;
  fclose(file);
  ready_name[wcscspn(ready_name,L"\r\n")]=0;
  release_name[wcscspn(release_name,L"\r\n")]=0;
  HANDLE ready=OpenEventW(EVENT_MODIFY_STATE,FALSE,ready_name);
  HANDLE release=OpenEventW(SYNCHRONIZE,FALSE,release_name);
  if (!ready || !release || !SetEvent(ready) ||
      WaitForSingleObject(release,12000)!=WAIT_OBJECT_0) return 92;
  CloseHandle(ready); CloseHandle(release);
  wprintf(L"PURE_GL_TEST_OK %ls\n",argv[argc-1]);
  return 0;
}
