#include <fcntl.h>
#include <iostream>
#include <io.h>
#include <string>
#include <windows.h>

int wmain(int argc, wchar_t** argv) {
  _setmode(_fileno(stdout), _O_BINARY);
  if (argc != 2) {
    return 2;
  }
  const std::wstring mode(argv[1]);
  std::cout << "READY\r\n" << std::flush;
  if (mode == L"--echo") {
    std::string line;
    if (!std::getline(std::cin, line)) {
      return 3;
    }
    std::cout << line << "\r\nDONE\r\n" << std::flush;
    return 0;
  }
  const bool breaking = mode == L"--wait-for-break";
  if (!breaking && mode != L"--wait-for-stop") {
    return 2;
  }
  const std::wstring event_name =
    std::wstring(breaking ? L"PURE_SIGINT-" : L"PURE_SIGTERM-") +
    std::to_wstring(GetCurrentProcessId());
  HANDLE event = OpenEventW(SYNCHRONIZE, FALSE, event_name.c_str());
  if (!event) {
    return 4;
  }
  const DWORD wait = WaitForSingleObject(event, INFINITE);
  CloseHandle(event);
  if (wait != WAIT_OBJECT_0) {
    return 5;
  }
  std::cout << (breaking ? "BREAK\r\n" : "STOP\r\n") << std::flush;
  return 0;
}
