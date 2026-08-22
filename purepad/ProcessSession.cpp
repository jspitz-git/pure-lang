#include "ProcessSession.h"

#include <algorithm>
#include <atomic>
#include <condition_variable>
#include <cwchar>
#include <mutex>
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

class SharedStateLock {
public:
  explicit SharedStateLock(SRWLOCK& lock) : lock_(&lock) {
    AcquireSRWLockShared(lock_);
  }
  ~SharedStateLock() { unlock(); }
  SharedStateLock(const SharedStateLock&) = delete;
  SharedStateLock& operator=(const SharedStateLock&) = delete;
  void unlock() {
    if (lock_) {
      ReleaseSRWLockShared(lock_);
      lock_ = nullptr;
    }
  }
private:
  SRWLOCK* lock_;
};

class ExclusiveStateLock {
public:
  explicit ExclusiveStateLock(SRWLOCK& lock) : lock_(&lock) {
    AcquireSRWLockExclusive(lock_);
  }
  ~ExclusiveStateLock() { unlock(); }
  ExclusiveStateLock(const ExclusiveStateLock&) = delete;
  ExclusiveStateLock& operator=(const ExclusiveStateLock&) = delete;
  void unlock() {
    if (lock_) {
      ReleaseSRWLockExclusive(lock_);
      lock_ = nullptr;
    }
  }
private:
  SRWLOCK* lock_;
};

std::wstring QuoteWindowsArgument(std::wstring_view value) {
  if (!value.empty() && value.find_first_of(L" \t\n\v\"") ==
                          std::wstring_view::npos) {
    return std::wstring(value);
  }

  std::wstring result(1, L'"');
  size_t backslashes = 0;
  for (const wchar_t character : value) {
    if (character == L'\\') {
      ++backslashes;
      continue;
    }
    if (character == L'"') {
      result.append(backslashes * 2 + 1, L'\\');
      result.push_back(character);
    } else {
      result.append(backslashes, L'\\');
      result.push_back(character);
    }
    backslashes = 0;
  }
  result.append(backslashes * 2, L'\\');
  result.push_back(L'"');
  return result;
}

std::wstring BuildCommandLine(const purepad::ProcessLaunch& launch) {
  std::wstring command_line = QuoteWindowsArgument(launch.application);
  for (const auto& argument : launch.arguments) {
    command_line += L' ';
    command_line += QuoteWindowsArgument(argument);
  }
  return command_line;
}

bool BuildChildEnvironment(purepad::ProcessApi& api,
                           const std::wstring& prompt,
                           std::vector<wchar_t>& result,
                           DWORD& error) {
  LPWCH source = api.GetEnvironmentStrings();
  if (!source) {
    error = GetLastError();
    return false;
  }
  for (const wchar_t* entry = source; *entry != L'\0';) {
    const size_t length = std::wcslen(entry);
    const wchar_t* equals = std::wcschr(entry, L'=');
    const bool is_pure_ps = equals && (equals - entry) == 7 &&
                            _wcsnicmp(entry, L"PURE_PS", 7) == 0;
    if (!is_pure_ps) result.insert(result.end(), entry, entry + length + 1);
    entry += length + 1;
  }
  api.FreeEnvironmentStrings(source);
  const std::wstring replacement = L"PURE_PS=" + prompt;
  result.insert(result.end(), replacement.begin(), replacement.end());
  result.push_back(L'\0');
  result.push_back(L'\0');
  return true;
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

BOOL ProcessApi::SignalEvent(HANDLE event) {
  return SetEvent(event);
}

LPWCH ProcessApi::GetEnvironmentStrings() {
  return GetEnvironmentStringsW();
}

BOOL ProcessApi::FreeEnvironmentStrings(LPWCH environment) {
  return FreeEnvironmentStringsW(environment);
}

DWORD ProcessApi::ResumeProcessThread(HANDLE thread) {
  return ResumeThread(thread);
}

DWORD ProcessApi::WaitForProcess(HANDLE process, DWORD timeout) {
  return WaitForSingleObject(process, timeout);
}

class ProcessSession::Impl {
public:
  enum class State { Idle, Starting, Running, Stopping };

  struct Generation {
    using WorkerContext = std::shared_ptr<Generation>;

    explicit Generation(ProcessCallbacks new_callbacks)
        : callbacks(std::move(new_callbacks)) {
      InitializeCriticalSection(&input_lock);
    }
    ~Generation() { DeleteCriticalSection(&input_lock); }

    Generation(const Generation&) = delete;
    Generation& operator=(const Generation&) = delete;

    static DWORD WINAPI ReaderEntry(void* context) {
      std::unique_ptr<WorkerContext> owner(
        static_cast<WorkerContext*>(context));
      return (*owner)->Reader();
    }
    static DWORD WINAPI WriterEntry(void* context) {
      std::unique_ptr<WorkerContext> owner(
        static_cast<WorkerContext*>(context));
      return (*owner)->Writer();
    }

    DWORD Reader() {
      char bytes[4096];
      for (;;) {
        if (reader_stop_requested.load(std::memory_order_acquire)) break;
        DWORD read = 0;
        if (!ReadFile(stdout_read.get(), bytes, sizeof(bytes), &read, nullptr) ||
            read == 0) {
          break;
        }
        auto output = callbacks.output;
        if (output) output(std::string_view(bytes, read));
      }
      if (WaitForStartup()) {
        auto exited = callbacks.exited;
        if (exited) exited();
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
        LeaveCriticalSection(&input_lock);
        if (input.empty()) continue;
        DWORD written = 0;
        if (!WriteFile(stdin_write.get(), input.data(),
                       static_cast<DWORD>(input.size()), &written, nullptr) ||
            written != input.size()) {
          return 0;
        }
      }
    }

    void MarkStartupDone(bool succeeded) {
      std::lock_guard<std::mutex> lock(completion_mutex);
      startup_succeeded = succeeded;
      startup_done = true;
      completion_changed.notify_all();
    }

    bool WaitForStartup() {
      std::unique_lock<std::mutex> lock(completion_mutex);
      completion_changed.wait(lock, [&] { return startup_done; });
      return startup_succeeded;
    }

    void MarkCleanupDone() {
      std::lock_guard<std::mutex> lock(completion_mutex);
      cleanup_done = true;
      completion_changed.notify_all();
    }

    void WaitForCleanup() {
      std::unique_lock<std::mutex> lock(completion_mutex);
      completion_changed.wait(lock, [&] { return cleanup_done; });
    }

    ProcessCallbacks callbacks;
    UniqueHandle stdin_read, stdin_write, stdout_read, stdout_write;
    UniqueHandle stop_event, input_event, break_event, terminate_event;
    UniqueHandle process_handle, process_thread, reader_thread, writer_thread;
    DWORD process_id = 0;
    DWORD reader_id = 0;
    DWORD writer_id = 0;
    bool resumed = false;
    CRITICAL_SECTION input_lock;
    std::string pending_input;
    std::atomic<bool> accepting_requests = true;
    std::atomic<bool> reader_stop_requested = false;
    std::mutex access_mutex;
    std::mutex completion_mutex;
    std::condition_variable completion_changed;
    bool startup_done = false;
    bool startup_succeeded = false;
    bool cleanup_done = false;
  };

  mutable SRWLOCK state_lock = SRWLOCK_INIT;
  State state = State::Idle;
  ProcessApi default_api;
  ProcessApi* api;
  std::shared_ptr<Generation> active;

  explicit Impl(ProcessApi* process_api)
      : api(process_api ? process_api : &default_api) {}
  ~Impl() { Stop(); }

  bool IsCurrentAndStarting(const std::shared_ptr<Generation>& generation) {
    SharedStateLock lock(state_lock);
    return active == generation && state == State::Starting;
  }

  void FinishCleanup(const std::shared_ptr<Generation>& generation) {
    {
      ExclusiveStateLock lock(state_lock);
      if (active == generation) {
        active.reset();
        state = State::Idle;
      }
    }
    generation->MarkCleanupDone();
  }

  void Cleanup(const std::shared_ptr<Generation>& generation) {
    const bool on_reader =
      generation->reader_id != 0 &&
      generation->reader_id == GetCurrentThreadId();
    if (on_reader)
      generation->reader_stop_requested.store(true, std::memory_order_release);
    std::unique_lock<std::mutex> access_lock(generation->access_mutex);
    if (generation->stop_event) api->SignalEvent(generation->stop_event.get());
    if (generation->terminate_event)
      api->SignalEvent(generation->terminate_event.get());

    if (generation->writer_thread)
      api->CancelWorkerIo(generation->writer_thread.get());
    access_lock.unlock();
    if (generation->writer_thread)
      WaitForSingleObject(generation->writer_thread.get(), INFINITE);
    generation->writer_thread.reset();
    generation->stdin_write.reset();

    if (generation->process_handle) {
      if (!generation->resumed) {
        TerminateProcess(generation->process_handle.get(), 1);
        WaitForSingleObject(generation->process_handle.get(), INFINITE);
      } else if (WaitForSingleObject(generation->process_handle.get(), 1000) ==
                 WAIT_TIMEOUT) {
        TerminateProcess(generation->process_handle.get(), 1);
        WaitForSingleObject(generation->process_handle.get(), INFINITE);
      }
    }

    if (generation->reader_thread && !on_reader)
      WaitForSingleObject(generation->reader_thread.get(), INFINITE);
    generation->reader_thread.reset();
    generation->stdout_read.reset();

    generation->stdin_read.reset();
    generation->stdout_write.reset();
    generation->stop_event.reset();
    generation->input_event.reset();
    generation->break_event.reset();
    generation->terminate_event.reset();
    generation->process_thread.reset();
    generation->process_handle.reset();
    EnterCriticalSection(&generation->input_lock);
    generation->pending_input.clear();
    LeaveCriticalSection(&generation->input_lock);
    generation->callbacks = {};
  }

  ProcessResult AbortStart(const std::shared_ptr<Generation>& generation,
                           ProcessError error, DWORD win32_error) {
    bool clean_here = false;
    {
      ExclusiveStateLock lock(state_lock);
      if (active == generation && state == State::Starting) {
        state = State::Stopping;
        generation->accepting_requests.store(false, std::memory_order_release);
        clean_here = true;
      }
    }
    generation->MarkStartupDone(false);
    if (clean_here) {
      Cleanup(generation);
      FinishCleanup(generation);
    } else {
      generation->WaitForCleanup();
    }
    return {error, win32_error};
  }

  ProcessResult CancelledStart(
      const std::shared_ptr<Generation>& generation, ProcessError stage) {
    return AbortStart(generation, stage, ERROR_OPERATION_ABORTED);
  }

  ProcessResult Start(const ProcessLaunch& launch,
                      ProcessCallbacks new_callbacks) {
    Stop();
    if (launch.application.empty())
      return {ProcessError::InvalidLaunch, ERROR_INVALID_PARAMETER};

    auto generation =
      std::make_shared<Generation>(std::move(new_callbacks));
    {
      ExclusiveStateLock lock(state_lock);
      if (state != State::Idle) {
        return {ProcessError::InvalidLaunch, ERROR_OPERATION_ABORTED};
      }
      state = State::Starting;
      active = generation;
    }

    SECURITY_ATTRIBUTES inheritable{};
    inheritable.nLength = sizeof(inheritable);
    inheritable.bInheritHandle = TRUE;
    HANDLE child_stdin = nullptr;
    HANDLE parent_stdin = nullptr;
    if (!CreatePipe(&child_stdin, &parent_stdin, &inheritable, 0)) {
      return AbortStart(generation, ProcessError::PipeCreation, GetLastError());
    }
    generation->stdin_read.reset(child_stdin);
    generation->stdin_write.reset(parent_stdin);
    if (!SetHandleInformation(generation->stdin_write.get(),
                              HANDLE_FLAG_INHERIT, 0)) {
      return AbortStart(generation, ProcessError::PipeCreation, GetLastError());
    }
    HANDLE child_stdout = nullptr;
    HANDLE parent_stdout = nullptr;
    if (!CreatePipe(&parent_stdout, &child_stdout, &inheritable, 0)) {
      return AbortStart(generation, ProcessError::PipeCreation, GetLastError());
    }
    generation->stdout_read.reset(parent_stdout);
    generation->stdout_write.reset(child_stdout);
    if (!SetHandleInformation(generation->stdout_read.get(),
                              HANDLE_FLAG_INHERIT, 0)) {
      return AbortStart(generation, ProcessError::PipeCreation, GetLastError());
    }
    if (!IsCurrentAndStarting(generation))
      return CancelledStart(generation, ProcessError::PipeCreation);

    generation->stop_event.reset(CreateEventW(nullptr, TRUE, FALSE, nullptr));
    if (!generation->stop_event) {
      return AbortStart(generation, ProcessError::EventCreation, GetLastError());
    }
    generation->input_event.reset(CreateEventW(nullptr, FALSE, FALSE, nullptr));
    if (!generation->input_event) {
      return AbortStart(generation, ProcessError::EventCreation, GetLastError());
    }

    std::vector<wchar_t> environment;
    DWORD environment_error = ERROR_SUCCESS;
    if (!BuildChildEnvironment(*api, launch.prompt, environment,
                               environment_error)) {
      return AbortStart(generation, ProcessError::EnvironmentCreation,
                        environment_error);
    }

    STARTUPINFOW startup{};
    startup.cb = sizeof(startup);
    startup.dwFlags = STARTF_USESTDHANDLES;
    startup.hStdInput = generation->stdin_read.get();
    startup.hStdOutput = generation->stdout_write.get();
    startup.hStdError = generation->stdout_write.get();
    std::wstring command_line = BuildCommandLine(launch);
    PROCESS_INFORMATION process{};
    if (!CreateProcessW(launch.application.c_str(), command_line.data(), nullptr,
                        nullptr, TRUE, CREATE_SUSPENDED | CREATE_NO_WINDOW |
                        CREATE_UNICODE_ENVIRONMENT, environment.data(),
                        launch.working_directory.empty() ? nullptr :
                          launch.working_directory.c_str(),
                        &startup, &process)) {
      return AbortStart(generation, ProcessError::ProcessCreation,
                        GetLastError());
    }
    generation->process_handle.reset(process.hProcess);
    generation->process_thread.reset(process.hThread);
    generation->process_id = process.dwProcessId;
    generation->stdin_read.reset();
    generation->stdout_write.reset();
    if (!IsCurrentAndStarting(generation))
      return CancelledStart(generation, ProcessError::ProcessCreation);

    const std::wstring break_name =
      L"PURE_SIGINT-" + std::to_wstring(generation->process_id);
    generation->break_event.reset(
      CreateEventW(nullptr, FALSE, FALSE, break_name.c_str()));
    if (!generation->break_event) {
      return AbortStart(generation, ProcessError::EventCreation, GetLastError());
    }
    const std::wstring terminate_name =
      L"PURE_SIGTERM-" + std::to_wstring(generation->process_id);
    generation->terminate_event.reset(
      CreateEventW(nullptr, FALSE, FALSE, terminate_name.c_str()));
    if (!generation->terminate_event) {
      return AbortStart(generation, ProcessError::EventCreation, GetLastError());
    }
    if (!IsCurrentAndStarting(generation))
      return CancelledStart(generation, ProcessError::EventCreation);

    auto reader_context =
      std::make_unique<Generation::WorkerContext>(generation);
    generation->reader_thread.reset(api->CreateWorkerThread(
      Generation::ReaderEntry, reader_context.get(), &generation->reader_id));
    if (!generation->reader_thread) {
      return AbortStart(generation, ProcessError::ThreadCreation, GetLastError());
    }
    reader_context.release();
    if (!IsCurrentAndStarting(generation))
      return CancelledStart(generation, ProcessError::ThreadCreation);
    auto writer_context =
      std::make_unique<Generation::WorkerContext>(generation);
    generation->writer_thread.reset(api->CreateWorkerThread(
      Generation::WriterEntry, writer_context.get(), &generation->writer_id));
    if (!generation->writer_thread) {
      return AbortStart(generation, ProcessError::ThreadCreation, GetLastError());
    }
    writer_context.release();
    if (!IsCurrentAndStarting(generation))
      return CancelledStart(generation, ProcessError::ThreadCreation);

    if (api->ResumeProcessThread(generation->process_thread.get()) ==
        static_cast<DWORD>(-1)) {
      return AbortStart(generation, ProcessError::ResumeProcess, GetLastError());
    }
    generation->resumed = true;
    generation->process_thread.reset();

    bool running = false;
    {
      ExclusiveStateLock lock(state_lock);
      if (active == generation && state == State::Starting) {
        state = State::Running;
        running = true;
      }
    }
    generation->MarkStartupDone(running);
    if (!running) {
      generation->WaitForCleanup();
      return {ProcessError::ResumeProcess, ERROR_OPERATION_ABORTED};
    }
    return {};
  }

  bool Write(std::string_view bytes) {
    if (bytes.empty()) return false;
    std::shared_ptr<Generation> generation;
    {
      SharedStateLock lock(state_lock);
      if (state != State::Running || !active) return false;
      generation = active;
    }
    std::lock_guard<std::mutex> access_lock(generation->access_mutex);
    if (!generation->accepting_requests.load(std::memory_order_acquire) ||
        !generation->input_event) {
      return false;
    }
    EnterCriticalSection(&generation->input_lock);
    generation->pending_input.append(bytes.data(), bytes.size());
    const bool signaled =
      api->SignalEvent(generation->input_event.get()) != FALSE;
    LeaveCriticalSection(&generation->input_lock);
    return signaled;
  }

  void Break() {
    std::shared_ptr<Generation> generation;
    {
      SharedStateLock lock(state_lock);
      if (state != State::Running || !active) return;
      generation = active;
    }
    std::lock_guard<std::mutex> access_lock(generation->access_mutex);
    if (generation->accepting_requests.load(std::memory_order_acquire) &&
        generation->break_event) {
      api->SignalEvent(generation->break_event.get());
    }
  }

  void Stop() {
    std::shared_ptr<Generation> generation;
    bool wait_for_startup = false;
    bool wait_for_cleanup = false;
    {
      ExclusiveStateLock lock(state_lock);
      if (state == State::Idle) return;
      generation = active;
      if (!generation) {
        state = State::Idle;
        return;
      }
      if (state == State::Starting) {
        state = State::Stopping;
        generation->accepting_requests.store(false, std::memory_order_release);
        wait_for_startup = true;
      } else if (state == State::Running) {
        state = State::Stopping;
        generation->accepting_requests.store(false, std::memory_order_release);
      } else {
        wait_for_cleanup = true;
      }
    }
    if (wait_for_cleanup) {
      if (generation->reader_id != 0 &&
          generation->reader_id == GetCurrentThreadId()) {
        return;
      }
      generation->WaitForCleanup();
      return;
    }
    if (wait_for_startup) generation->WaitForStartup();
    Cleanup(generation);
    FinishCleanup(generation);
  }

  bool IsRunning() const {
    SharedStateLock lock(state_lock);
    return state == State::Running;
  }

  bool WaitForExit(std::chrono::milliseconds timeout) {
    std::shared_ptr<Generation> generation;
    {
      SharedStateLock lock(state_lock);
      if (state != State::Running || !active) return false;
      generation = active;
    }
    UniqueHandle process;
    {
      std::lock_guard<std::mutex> access_lock(generation->access_mutex);
      if (!generation->accepting_requests.load(std::memory_order_acquire) ||
          !generation->process_handle) {
        return false;
      }
      HANDLE duplicate = nullptr;
      if (!DuplicateHandle(GetCurrentProcess(), generation->process_handle.get(),
                           GetCurrentProcess(), &duplicate, 0, FALSE,
                           DUPLICATE_SAME_ACCESS)) {
        return false;
      }
      process.reset(duplicate);
    }

    int64_t remaining = std::max<int64_t>(0, timeout.count());
    constexpr DWORD max_finite_wait = MAXDWORD - 1;
    for (;;) {
      const DWORD chunk = static_cast<DWORD>(std::min<int64_t>(
        remaining, static_cast<int64_t>(max_finite_wait)));
      const DWORD result = api->WaitForProcess(process.get(), chunk);
      if (result == WAIT_OBJECT_0) return true;
      if (result != WAIT_TIMEOUT || remaining <= chunk) return false;
      remaining -= chunk;
    }
  }
};

ProcessSession::ProcessSession(ProcessApi* api)
    : impl_(std::make_unique<Impl>(api)) {}
ProcessSession::~ProcessSession() = default;
ProcessResult ProcessSession::Start(const ProcessLaunch& launch,
                                    ProcessCallbacks callbacks) {
  return impl_->Start(launch, std::move(callbacks));
}
bool ProcessSession::Write(std::string_view bytes) {
  return impl_->Write(bytes);
}
void ProcessSession::Break() { impl_->Break(); }
void ProcessSession::Stop() { impl_->Stop(); }
bool ProcessSession::IsRunning() const { return impl_->IsRunning(); }
bool ProcessSession::WaitForExit(std::chrono::milliseconds timeout) {
  return impl_->WaitForExit(timeout);
}

} // namespace purepad
