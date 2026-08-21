#include "ProcessSession.h"

#include <algorithm>
#include <cwchar>
#include <utility>

namespace {

class UniqueHandle {
public:
  UniqueHandle() = default;
  explicit UniqueHandle(HANDLE handle) : handle_(handle) {}
  ~UniqueHandle() { reset(); }
  UniqueHandle(const UniqueHandle&) = delete;
  UniqueHandle& operator=(const UniqueHandle&) = delete;
  UniqueHandle(UniqueHandle&& other) noexcept : handle_(other.release()) {}
  UniqueHandle& operator=(UniqueHandle&& other) noexcept {
    if (this != &other) reset(other.release());
    return *this;
  }
  HANDLE get() const { return handle_; }
  explicit operator bool() const {
    return handle_ != nullptr && handle_ != INVALID_HANDLE_VALUE;
  }
  HANDLE release() {
    HANDLE result = handle_;
    handle_ = nullptr;
    return result;
  }
  void reset(HANDLE handle = nullptr) {
    if (*this) CloseHandle(handle_);
    handle_ = handle;
  }
private:
  HANDLE handle_ = nullptr;
};

std::wstring QuoteArgument(const std::wstring& value) {
  if (value.find_first_of(L" \t\"") == std::wstring::npos) return value;
  std::wstring quoted = L"\"";
  for (wchar_t character : value) {
    if (character == L'"') quoted += L'\\';
    quoted += character;
  }
  return quoted + L"\"";
}

std::wstring BuildCommandLine(const purepad::ProcessLaunch& launch) {
  std::wstring command_line = QuoteArgument(launch.application);
  for (const auto& argument : launch.arguments) {
    command_line += L' ';
    command_line += QuoteArgument(argument);
  }
  return command_line;
}

std::vector<wchar_t> BuildChildEnvironment(const std::wstring& prompt) {
  LPWCH source = GetEnvironmentStringsW();
  std::vector<wchar_t> result;
  if (source) {
    for (const wchar_t* entry = source; *entry != L'\0';) {
      const size_t length = std::wcslen(entry);
      const wchar_t* equals = std::wcschr(entry, L'=');
      const bool is_pure_ps = equals && (equals - entry) == 7 &&
                              _wcsnicmp(entry, L"PURE_PS", 7) == 0;
      if (!is_pure_ps) result.insert(result.end(), entry, entry + length + 1);
      entry += length + 1;
    }
    FreeEnvironmentStringsW(source);
  }
  const std::wstring replacement = L"PURE_PS=" + prompt;
  result.insert(result.end(), replacement.begin(), replacement.end());
  result.push_back(L'\0');
  result.push_back(L'\0');
  return result;
}

} // namespace

namespace purepad {

HANDLE ProcessApi::CreateWorkerThread(LPTHREAD_START_ROUTINE entry,
                                      void* context, DWORD* id) {
  return CreateThread(nullptr, 0, entry, context, 0, id);
}

BOOL ProcessApi::CancelWorkerIo(HANDLE thread) {
  return CancelSynchronousIo(thread);
}

class ProcessSession::Impl {
public:
  enum class State { Idle, Starting, Running, Stopping };
  mutable SRWLOCK state_lock = SRWLOCK_INIT;
  State state = State::Idle;
  ProcessApi default_api;
  ProcessApi* api;
  ProcessCallbacks callbacks;
  PROCESS_INFORMATION process{};
  UniqueHandle stdin_read, stdin_write, stdout_read, stdout_write;
  UniqueHandle stop_event, input_event, reader_thread, writer_thread;
  CRITICAL_SECTION input_lock;
  std::string pending_input;

  explicit Impl(ProcessApi* process_api)
      : api(process_api ? process_api : &default_api) {
    InitializeCriticalSection(&input_lock);
  }
  ~Impl() {
    Stop();
    DeleteCriticalSection(&input_lock);
  }

  static DWORD WINAPI ReaderEntry(void* context) {
    return static_cast<Impl*>(context)->Reader();
  }
  static DWORD WINAPI WriterEntry(void* context) {
    return static_cast<Impl*>(context)->Writer();
  }

  DWORD Reader() {
    char bytes[4096];
    for (;;) {
      DWORD read = 0;
      const HANDLE pipe = stdout_read.get();
      if (!pipe || !ReadFile(pipe, bytes, sizeof(bytes), &read, nullptr) ||
          read == 0) break;
      if (callbacks.output) callbacks.output(std::string_view(bytes, read));
    }
    return 0;
  }

  DWORD Writer() {
    HANDLE events[] = {stop_event.get(), input_event.get()};
    for (;;) {
      const DWORD wait = WaitForMultipleObjects(2, events, FALSE, INFINITE);
      if (wait == WAIT_OBJECT_0 || wait != WAIT_OBJECT_0 + 1) return 0;
      std::string input;
      EnterCriticalSection(&input_lock);
      input.swap(pending_input);
      ResetEvent(input_event.get());
      LeaveCriticalSection(&input_lock);
      if (input.empty()) continue;
      const HANDLE pipe = stdin_write.get();
      DWORD written = 0;
      if (!pipe || !WriteFile(pipe, input.data(), static_cast<DWORD>(input.size()),
                              &written, nullptr) || written != input.size()) {
        return 0;
      }
    }
  }

  bool SetState(State expected, State desired) {
    AcquireSRWLockExclusive(&state_lock);
    const bool changed = state == expected;
    if (changed) state = desired;
    ReleaseSRWLockExclusive(&state_lock);
    return changed;
  }

  ProcessResult Start(const ProcessLaunch& launch, ProcessCallbacks new_callbacks) {
    Stop();
    if (launch.application.empty())
      return {ProcessError::InvalidLaunch, ERROR_INVALID_PARAMETER};
    SetState(State::Idle, State::Starting);
    callbacks = std::move(new_callbacks);

    SECURITY_ATTRIBUTES inheritable{};
    inheritable.nLength = sizeof(inheritable);
    inheritable.bInheritHandle = TRUE;
    HANDLE child_stdin_read = nullptr;
    HANDLE parent_stdin_write = nullptr;
    HANDLE parent_stdout_read = nullptr;
    HANDLE child_stdout_write = nullptr;
    if (!CreatePipe(&child_stdin_read, &parent_stdin_write, &inheritable, 0) ||
        !SetHandleInformation(parent_stdin_write, HANDLE_FLAG_INHERIT, 0) ||
        !CreatePipe(&parent_stdout_read, &child_stdout_write, &inheritable, 0) ||
        !SetHandleInformation(parent_stdout_read, HANDLE_FLAG_INHERIT, 0)) {
      const DWORD error = GetLastError();
      if (child_stdin_read) CloseHandle(child_stdin_read);
      if (parent_stdin_write) CloseHandle(parent_stdin_write);
      if (parent_stdout_read) CloseHandle(parent_stdout_read);
      if (child_stdout_write) CloseHandle(child_stdout_write);
      Stop();
      return {ProcessError::PipeCreation, error};
    }
    stdin_read.reset(child_stdin_read);
    stdin_write.reset(parent_stdin_write);
    stdout_read.reset(parent_stdout_read);
    stdout_write.reset(child_stdout_write);
    stop_event.reset(CreateEventW(nullptr, TRUE, FALSE, nullptr));
    input_event.reset(CreateEventW(nullptr, TRUE, FALSE, nullptr));
    if (!stop_event || !input_event) {
      const DWORD error = GetLastError();
      Stop();
      return {ProcessError::EventCreation, error};
    }

    STARTUPINFOW startup{};
    startup.cb = sizeof(startup);
    startup.dwFlags = STARTF_USESTDHANDLES;
    startup.hStdInput = stdin_read.get();
    startup.hStdOutput = stdout_write.get();
    startup.hStdError = stdout_write.get();
    std::wstring command_line = BuildCommandLine(launch);
    std::vector<wchar_t> environment = BuildChildEnvironment(launch.prompt);
    if (!CreateProcessW(launch.application.c_str(), command_line.data(), nullptr,
                        nullptr, TRUE, CREATE_SUSPENDED | CREATE_NO_WINDOW |
                        CREATE_UNICODE_ENVIRONMENT, environment.data(),
                        launch.working_directory.empty() ? nullptr :
                          launch.working_directory.c_str(),
                        &startup, &process)) {
      const DWORD error = GetLastError();
      Stop();
      return {ProcessError::ProcessCreation, error};
    }
    stdin_read.reset();
    stdout_write.reset();
    DWORD reader_id = 0;
    reader_thread.reset(api->CreateWorkerThread(ReaderEntry, this, &reader_id));
    if (!reader_thread) {
      const DWORD error = GetLastError();
      Stop();
      return {ProcessError::ThreadCreation, error};
    }
    DWORD writer_id = 0;
    writer_thread.reset(api->CreateWorkerThread(WriterEntry, this, &writer_id));
    if (!writer_thread) {
      const DWORD error = GetLastError();
      Stop();
      return {ProcessError::ThreadCreation, error};
    }
    if (ResumeThread(process.hThread) == static_cast<DWORD>(-1)) {
      const DWORD error = GetLastError();
      Stop();
      return {ProcessError::ResumeProcess, error};
    }
    CloseHandle(process.hThread);
    process.hThread = nullptr;
    SetState(State::Starting, State::Running);
    return {};
  }

  bool Write(std::string_view bytes) {
    AcquireSRWLockShared(&state_lock);
    const bool running = state == State::Running;
    ReleaseSRWLockShared(&state_lock);
    if (!running || bytes.empty()) return false;
    EnterCriticalSection(&input_lock);
    pending_input.append(bytes.data(), bytes.size());
    SetEvent(input_event.get());
    LeaveCriticalSection(&input_lock);
    return true;
  }

  void Stop() {
    AcquireSRWLockExclusive(&state_lock);
    if (state == State::Idle) {
      ReleaseSRWLockExclusive(&state_lock);
      return;
    }
    state = State::Stopping;
    ReleaseSRWLockExclusive(&state_lock);
    if (stop_event) SetEvent(stop_event.get());
    stdin_write.reset();
    if (reader_thread) api->CancelWorkerIo(reader_thread.get());
    if (writer_thread) api->CancelWorkerIo(writer_thread.get());
    stdout_read.reset();
    if (process.hProcess) {
      if (WaitForSingleObject(process.hProcess, 1000) == WAIT_TIMEOUT) {
        TerminateProcess(process.hProcess, 1);
        WaitForSingleObject(process.hProcess, INFINITE);
      }
    }
    if (reader_thread) WaitForSingleObject(reader_thread.get(), INFINITE);
    if (writer_thread) WaitForSingleObject(writer_thread.get(), INFINITE);
    reader_thread.reset();
    writer_thread.reset();
    stdin_read.reset();
    stdin_write.reset();
    stdout_read.reset();
    stdout_write.reset();
    stop_event.reset();
    input_event.reset();
    if (process.hThread) CloseHandle(process.hThread);
    if (process.hProcess) CloseHandle(process.hProcess);
    process = {};
    EnterCriticalSection(&input_lock);
    pending_input.clear();
    LeaveCriticalSection(&input_lock);
    callbacks = {};
    AcquireSRWLockExclusive(&state_lock);
    state = State::Idle;
    ReleaseSRWLockExclusive(&state_lock);
  }

  bool IsRunning() const {
    AcquireSRWLockShared(&state_lock);
    const bool running = state == State::Running;
    ReleaseSRWLockShared(&state_lock);
    return running;
  }

  bool WaitForExit(std::chrono::milliseconds timeout) {
    HANDLE process_handle = nullptr;
    AcquireSRWLockShared(&state_lock);
    if (process.hProcess) {
      DuplicateHandle(GetCurrentProcess(), process.hProcess, GetCurrentProcess(),
                      &process_handle, 0, FALSE, DUPLICATE_SAME_ACCESS);
    }
    ReleaseSRWLockShared(&state_lock);
    if (!process_handle) return false;
    const DWORD count = static_cast<DWORD>(
      std::min<int64_t>(timeout.count(), static_cast<int64_t>(MAXDWORD)));
    const bool exited =
      WaitForSingleObject(process_handle, count) == WAIT_OBJECT_0;
    CloseHandle(process_handle);
    return exited;
  }
};

ProcessSession::ProcessSession(ProcessApi* api) : impl_(std::make_unique<Impl>(api)) {}
ProcessSession::~ProcessSession() = default;
ProcessResult ProcessSession::Start(const ProcessLaunch& launch, ProcessCallbacks callbacks) {
  return impl_->Start(launch, std::move(callbacks));
}
bool ProcessSession::Write(std::string_view bytes) { return impl_->Write(bytes); }
void ProcessSession::Break() {}
void ProcessSession::Stop() { impl_->Stop(); }
bool ProcessSession::IsRunning() const { return impl_->IsRunning(); }
bool ProcessSession::WaitForExit(std::chrono::milliseconds timeout) {
  return impl_->WaitForExit(timeout);
}

} // namespace purepad
