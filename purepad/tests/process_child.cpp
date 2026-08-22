#include <fcntl.h>
#include <iostream>
#include <io.h>
#include <string>
#include <string_view>
#include <vector>
#include <windows.h>

namespace {

class ScopedHandle {
public:
  explicit ScopedHandle(HANDLE handle) : handle_(handle) {}
  ~ScopedHandle() {
    if (handle_) CloseHandle(handle_);
  }
  ScopedHandle(const ScopedHandle&) = delete;
  ScopedHandle& operator=(const ScopedHandle&) = delete;
  HANDLE get() const { return handle_; }
  explicit operator bool() const { return handle_ != nullptr; }

private:
  HANDLE handle_;
};

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

void PrintLaunchReportValue(std::string_view name, std::wstring_view value) {
  const std::string utf8 = Utf8(value);
  std::cout << name << ':' << utf8.size() << ':' << utf8 << "\r\n";
}

bool PrintLaunchReport(int argc, wchar_t** argv) {
  const DWORD required = GetCurrentDirectoryW(0, nullptr);
  if (required == 0) return false;
  std::vector<wchar_t> directory(required);
  const DWORD copied = GetCurrentDirectoryW(required, directory.data());
  if (copied == 0 || copied >= required) return false;

  PrintLaunchReportValue("cwd", std::wstring_view(directory.data(), copied));
  for (int index = 2; index + 1 < argc; ++index)
    PrintLaunchReportValue("arg", argv[index]);
  PrintLaunchReportValue("script", argv[argc - 1]);
  std::cout << std::flush;
  return true;
}

std::wstring ExecutablePath() {
  std::vector<wchar_t> path(260);
  for (;;) {
    const DWORD copied = GetModuleFileNameW(
      nullptr, path.data(), static_cast<DWORD>(path.size()));
    if (copied == 0) return {};
    if (copied < path.size()) return std::wstring(path.data(), copied);
    path.resize(path.size() * 2);
  }
}

bool SpawnInheritedStdoutDescendant(std::wstring_view release_event_name,
                                    std::wstring_view write_event_name,
                                    std::wstring_view start_event_name,
                                    std::wstring_view ready_event_name,
                                    std::wstring_view next_event_name) {
  const std::wstring executable = ExecutablePath();
  if (executable.empty()) return false;

  HANDLE stdout_handle = GetStdHandle(STD_OUTPUT_HANDLE);
  HANDLE stderr_handle = GetStdHandle(STD_ERROR_HANDLE);
  if (!SetHandleInformation(stdout_handle, HANDLE_FLAG_INHERIT,
                            HANDLE_FLAG_INHERIT) ||
      !SetHandleInformation(stderr_handle, HANDLE_FLAG_INHERIT,
                            HANDLE_FLAG_INHERIT)) {
    return false;
  }

  std::wstring command_line = L"\"" + executable +
    L"\" --write-inherited-stdout \"" +
    std::wstring(release_event_name) + L"\" \"" +
    std::wstring(start_event_name) + L"\" \"" +
    std::wstring(ready_event_name) + L"\" \"" +
    std::wstring(next_event_name) + L"\"";
  STARTUPINFOW startup{};
  startup.cb = sizeof(startup);
  startup.dwFlags = STARTF_USESTDHANDLES;
  startup.hStdInput = GetStdHandle(STD_INPUT_HANDLE);
  startup.hStdOutput = stdout_handle;
  startup.hStdError = stderr_handle;
  PROCESS_INFORMATION descendant{};
  if (!CreateProcessW(executable.c_str(), command_line.data(), nullptr,
                      nullptr, TRUE, CREATE_NO_WINDOW, nullptr, nullptr,
                      &startup, &descendant)) {
    return false;
  }

  std::cout << "DESCENDANT:" << descendant.dwProcessId << "\r\n"
            << std::flush;
  CloseHandle(descendant.hThread);
  CloseHandle(descendant.hProcess);

  HANDLE write_event = OpenEventW(SYNCHRONIZE, FALSE,
                                  std::wstring(write_event_name).c_str());
  if (!write_event) return false;
  const DWORD write_wait = WaitForSingleObject(write_event, INFINITE);
  CloseHandle(write_event);
  if (write_wait != WAIT_OBJECT_0) return false;
  std::cout << "PARENT-FINAL\r\n" << std::flush;
  return true;
}

bool WriteInheritedStdout(std::wstring_view release_event_name,
                          std::wstring_view start_event_name,
                          std::wstring_view ready_event_name,
                          std::wstring_view next_event_name) {
  ScopedHandle release(OpenEventW(
    SYNCHRONIZE, FALSE, std::wstring(release_event_name).c_str()));
  ScopedHandle start(OpenEventW(
    SYNCHRONIZE, FALSE, std::wstring(start_event_name).c_str()));
  ScopedHandle ready(OpenEventW(
    EVENT_MODIFY_STATE, FALSE, std::wstring(ready_event_name).c_str()));
  ScopedHandle next(OpenEventW(
    SYNCHRONIZE, FALSE, std::wstring(next_event_name).c_str()));
  if (!release || !start || !ready || !next) return false;

  HANDLE startup_events[] = {release.get(), start.get()};
  const DWORD startup_wait =
    WaitForMultipleObjects(2, startup_events, FALSE, INFINITE);
  if (startup_wait == WAIT_OBJECT_0) return true;
  if (startup_wait != WAIT_OBJECT_0 + 1) return false;

  const std::string chunk(1024, 'D');
  for (;;) {
    DWORD written = 0;
    if (!WriteFile(GetStdHandle(STD_OUTPUT_HANDLE), chunk.data(),
                   static_cast<DWORD>(chunk.size()), &written, nullptr)) {
      const DWORD error = GetLastError();
      return error == ERROR_BROKEN_PIPE || error == ERROR_NO_DATA;
    }
    if (written != chunk.size()) return false;
    if (!SetEvent(ready.get())) return false;

    HANDLE writer_events[] = {release.get(), next.get()};
    const DWORD writer_wait =
      WaitForMultipleObjects(2, writer_events, FALSE, INFINITE);
    if (writer_wait == WAIT_OBJECT_0) return true;
    if (writer_wait != WAIT_OBJECT_0 + 1) return false;
  }
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
  if (mode == L"--launch-report" && argc >= 3)
    return PrintLaunchReport(argc, argv) ? 0 : 7;
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
  if (mode == L"--spawn-inherited-stdout" && argc == 7)
    return SpawnInheritedStdoutDescendant(
      argv[2], argv[3], argv[4], argv[5], argv[6]) ? 0 : 8;
  if (mode == L"--write-inherited-stdout" && argc == 6)
    return WriteInheritedStdout(argv[2], argv[3], argv[4], argv[5]) ? 0 : 9;
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
