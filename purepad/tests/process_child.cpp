#include <fcntl.h>
#include <iostream>
#include <io.h>
#include <string>
#include <string_view>
#include <vector>
#include <windows.h>

namespace {

std::string Utf8(std::wstring_view value) {
  if (value.empty()) return {};
  const int size = WideCharToMultiByte(CP_UTF8, 0, value.data(),
                                       static_cast<int>(value.size()), nullptr,
                                       0, nullptr, nullptr);
  if (size <= 0) return {};
  std::string result(static_cast<size_t>(size), '\0');
  WideCharToMultiByte(CP_UTF8, 0, value.data(),
                      static_cast<int>(value.size()), result.data(), size,
                      nullptr, nullptr);
  return result;
}

void PrintValue(std::wstring_view value) {
  const std::string utf8 = Utf8(value);
  std::cout << utf8.size() << ':' << utf8 << "\r\n";
}

} // namespace

int wmain(int argc, wchar_t** argv) {
  _setmode(_fileno(stdout), _O_BINARY);
  if (argc < 2) return 2;

  const std::wstring mode(argv[1]);
  if (mode == L"--arguments") {
    for (int index = 2; index < argc; ++index) PrintValue(argv[index]);
    std::cout << std::flush;
    return 0;
  }
  if (mode == L"--generation" && argc == 3) {
    std::cout << "GEN:" << Utf8(argv[2]) << "\r\n" << std::flush;
    return 0;
  }
  if (mode == L"--print-pure-ps" && argc == 2) {
    const DWORD required = GetEnvironmentVariableW(L"PURE_PS", nullptr, 0);
    if (required == 0) {
      PrintValue({});
    } else {
      std::vector<wchar_t> value(required);
      const DWORD copied =
        GetEnvironmentVariableW(L"PURE_PS", value.data(), required);
      if (copied == 0 || copied >= required) return 6;
      PrintValue(std::wstring_view(value.data(), copied));
    }
    std::cout << std::flush;
    return 0;
  }
  if (argc != 2) return 2;

  std::cout << "READY\r\n" << std::flush;
  if (mode == L"--echo") {
    std::string line;
    if (!std::getline(std::cin, line)) return 3;
    std::cout << line << "\r\nDONE\r\n" << std::flush;
    return 0;
  }
  const bool breaking = mode == L"--wait-for-break";
  if (!breaking && mode != L"--wait-for-stop") return 2;
  const std::wstring event_name =
    std::wstring(breaking ? L"PURE_SIGINT-" : L"PURE_SIGTERM-") +
    std::to_wstring(GetCurrentProcessId());
  HANDLE event = OpenEventW(SYNCHRONIZE, FALSE, event_name.c_str());
  if (!event) return 4;
  const DWORD wait = WaitForSingleObject(event, INFINITE);
  CloseHandle(event);
  if (wait != WAIT_OBJECT_0) return 5;
  std::cout << (breaking ? "BREAK\r\n" : "STOP\r\n") << std::flush;
  return 0;
}
