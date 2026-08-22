#include "ProcessSession.h"
#include "ProcessSessionInternal.h"
#include "Pipe.h"

#include <atomic>
#include <chrono>
#include <iostream>
#include <memory>
#include <mutex>
#include <optional>
#include <string>
#include <string_view>
#include <thread>
#include <vector>
#include <windows.h>

using namespace std::chrono_literals;

namespace {

int failures = 0;
#define CHECK(condition) do { if (!(condition)) { \
  std::cerr << __FUNCTION__ << ':' << __LINE__ << ": " #condition "\n"; \
  ++failures; } } while (false)

class Output {
public:
  purepad::ProcessCallbacks Callbacks() {
    purepad::ProcessCallbacks callbacks;
    callbacks.output = [this](std::string_view bytes) {
      std::lock_guard<std::mutex> lock(mutex_);
      bytes_.append(bytes);
    };
    return callbacks;
  }

  std::string Get() const {
    std::lock_guard<std::mutex> lock(mutex_);
    return bytes_;
  }

  bool WaitFor(std::string_view text,
               std::chrono::milliseconds timeout = 5s) const {
    const auto deadline = std::chrono::steady_clock::now() + timeout;
    do {
      if (Get().find(text) != std::string::npos) return true;
      Sleep(1);
    } while (std::chrono::steady_clock::now() < deadline);
    return Get().find(text) != std::string::npos;
  }

private:
  mutable std::mutex mutex_;
  std::string bytes_;
};

purepad::ProcessLaunch Launch(const wchar_t* child,
                              std::vector<std::wstring> arguments) {
  purepad::ProcessLaunch launch;
  launch.application = child;
  launch.arguments = std::move(arguments);
  return launch;
}

std::string Utf8(std::wstring_view value) {
  if (value.empty()) return {};
  const int size = WideCharToMultiByte(
    CP_UTF8, 0, value.data(), static_cast<int>(value.size()), nullptr, 0,
    nullptr, nullptr);
  CHECK(size > 0);
  if (size <= 0) return {};
  std::string result(static_cast<size_t>(size), '\0');
  CHECK(WideCharToMultiByte(
          CP_UTF8, 0, value.data(), static_cast<int>(value.size()),
          result.data(), size, nullptr, nullptr) == size);
  return result;
}

size_t Count(std::string_view text, std::string_view needle) {
  size_t result = 0;
  for (size_t at = 0; (at = text.find(needle, at)) != std::string_view::npos;
       at += needle.size()) {
    ++result;
  }
  return result;
}

std::string LaunchReportRecord(std::string_view name,
                               std::wstring_view value) {
  const std::string utf8 = Utf8(value);
  return std::string(name) + ':' + std::to_string(utf8.size()) + ':' + utf8 +
         "\r\n";
}

class ScopedEnvironmentVariable {
public:
  ScopedEnvironmentVariable(const wchar_t* name, const wchar_t* value)
      : name_(name) {
    const DWORD required = GetEnvironmentVariableW(name, nullptr, 0);
    if (required != 0) {
      std::wstring original(required, L'\0');
      const DWORD copied =
        GetEnvironmentVariableW(name, original.data(), required);
      if (copied != 0 && copied < required) {
        original.resize(copied);
        original_ = std::move(original);
      }
    }
    changed_ = SetEnvironmentVariableW(name, value) != FALSE;
  }

  ~ScopedEnvironmentVariable() {
    if (!changed_) return;
    SetEnvironmentVariableW(name_.c_str(),
                            original_ ? original_->c_str() : nullptr);
  }

  bool changed() const { return changed_; }

private:
  std::wstring name_;
  std::optional<std::wstring> original_;
  bool changed_ = false;
};

class ScopedDirectory {
public:
  explicit ScopedDirectory(std::wstring path) : path_(std::move(path)) {}
  ~ScopedDirectory() {
    DeleteFileW((path_ + L"\\script-name.pure").c_str());
    DeleteFileW((path_ + L"\\sibling helper.exe").c_str());
    RemoveDirectoryW(path_.c_str());
  }

private:
  std::wstring path_;
};

struct FailingProcessApi final : purepad::ProcessApi {
  int fail_at = 0;
  int calls = 0;
  HANDLE CreateWorkerThread(LPTHREAD_START_ROUTINE entry,
                            void* context, DWORD* id) override {
    if (++calls == fail_at) {
      SetLastError(ERROR_NOT_ENOUGH_MEMORY);
      return nullptr;
    }
    return ProcessApi::CreateWorkerThread(entry, context, id);
  }
};

struct FailingEnvironmentApi final : purepad::ProcessApi {
  bool fail = true;
  LPWCH GetEnvironmentStrings() override {
    if (fail) {
      SetLastError(ERROR_NOT_ENOUGH_MEMORY);
      return nullptr;
    }
    return ProcessApi::GetEnvironmentStrings();
  }
};

struct RecordingWaitApi final : purepad::ProcessApi {
  std::vector<DWORD> timeouts;
  DWORD WaitForProcess(HANDLE, DWORD timeout) override {
    timeouts.push_back(timeout);
    return WAIT_FAILED;
  }
};

class BlockingWaitApi final : public purepad::ProcessApi {
public:
  BlockingWaitApi()
      : entered(CreateEventW(nullptr, TRUE, FALSE, nullptr)),
        release(CreateEventW(nullptr, TRUE, FALSE, nullptr)) {}
  ~BlockingWaitApi() override {
    CloseHandle(entered);
    CloseHandle(release);
  }
  DWORD WaitForProcess(HANDLE process, DWORD timeout) override {
    SetEvent(entered);
    WaitForSingleObject(release, INFINITE);
    return ProcessApi::WaitForProcess(process, timeout);
  }
  HANDLE entered;
  HANDLE release;
};

class BlockingSignalApi final : public purepad::ProcessApi {
public:
  BlockingSignalApi()
      : entered(CreateEventW(nullptr, TRUE, FALSE, nullptr)),
        release(CreateEventW(nullptr, TRUE, FALSE, nullptr)) {}
  ~BlockingSignalApi() override {
    CloseHandle(entered);
    CloseHandle(release);
  }
  BOOL SignalEvent(HANDLE event) override {
    if (!blocked.exchange(true)) {
      SetEvent(entered);
      WaitForSingleObject(release, INFINITE);
    }
    return ProcessApi::SignalEvent(event);
  }
  std::atomic<bool> blocked = false;
  HANDLE entered;
  HANDLE release;
};

class ResumeGateApi final : public purepad::ProcessApi {
public:
  ResumeGateApi()
      : resumed(CreateEventW(nullptr, TRUE, FALSE, nullptr)),
        release(CreateEventW(nullptr, TRUE, FALSE, nullptr)) {}
  ~ResumeGateApi() override {
    CloseHandle(resumed);
    CloseHandle(release);
  }
  DWORD ResumeProcessThread(HANDLE thread) override {
    const DWORD result = ProcessApi::ResumeProcessThread(thread);
    SetEvent(resumed);
    WaitForSingleObject(release, INFINITE);
    return result;
  }
  HANDLE resumed;
  HANDLE release;
};

class ReaderShutdownApi final : public purepad::ProcessApi {
public:
  ReaderShutdownApi()
      : reader_shutdown_requested(
          CreateEventW(nullptr, TRUE, FALSE, nullptr)) {}
  ~ReaderShutdownApi() override { CloseHandle(reader_shutdown_requested); }
  BOOL SignalEvent(HANDLE event) override {
    const int call = ++signal_calls;
    const BOOL result = ProcessApi::SignalEvent(event);
    // Cleanup signals writer stop, parent terminate, then reader stop.
    if (call == 3) SetEvent(reader_shutdown_requested);
    return result;
  }
  BOOL CancelWorkerIo(HANDLE thread) override {
    const int call = ++cancel_calls;
    const BOOL result = ProcessApi::CancelWorkerIo(thread);
    // The pre-fix reader cancellation was the second worker cancellation.
    // Observing it positions the RED run without adding a production hook.
    if (call == 2) SetEvent(reader_shutdown_requested);
    return result;
  }
  std::atomic<int> signal_calls = 0;
  std::atomic<int> cancel_calls = 0;
  HANDLE reader_shutdown_requested;
};

class ReaderStopWindowApi final : public purepad::ProcessApi {
public:
  ReaderStopWindowApi()
      : reader_checked_stop(CreateEventW(nullptr, TRUE, FALSE, nullptr)),
        release_reader(CreateEventW(nullptr, TRUE, FALSE, nullptr)),
        reader_stop_signaled(CreateEventW(nullptr, TRUE, FALSE, nullptr)) {}
  ~ReaderStopWindowApi() override {
    CloseHandle(reader_checked_stop);
    CloseHandle(release_reader);
    CloseHandle(reader_stop_signaled);
  }
  void Arm() { armed.store(true, std::memory_order_release); }
  void ReaderStopCheckCompleted() override {
    if (armed.load(std::memory_order_acquire) && !paused.exchange(true)) {
      SetEvent(reader_checked_stop);
      WaitForSingleObject(release_reader, INFINITE);
    }
  }
  BOOL SignalEvent(HANDLE event) override {
    const int call = ++signal_calls;
    const BOOL result = ProcessApi::SignalEvent(event);
    // Cleanup signals writer stop, parent terminate, then reader stop.
    if (call == 3) SetEvent(reader_stop_signaled);
    return result;
  }
  std::atomic<bool> armed = false;
  std::atomic<bool> paused = false;
  std::atomic<int> signal_calls = 0;
  HANDLE reader_checked_stop;
  HANDLE release_reader;
  HANDLE reader_stop_signaled;
};

void echo_round_trip(const wchar_t* child) {
  Output output;
  purepad::ProcessSession session;
  const auto started = session.Start(
    Launch(child, {L"--echo"}), output.Callbacks());
  CHECK(started.ok());
  if (!started.ok()) return;
  CHECK(session.Write("hello\n"));
  CHECK(session.WaitForExit(5s));
  session.Stop();
  CHECK(!session.IsRunning());
  CHECK(output.Get() == "READY\r\nhello\r\nDONE\r\n");
}

void reader_stop_is_latched_after_normal_loop_check(const wchar_t* child) {
  const std::wstring release_name =
    L"Local\\PurePadReaderStopWindow-" +
    std::to_wstring(GetCurrentProcessId()) + L"-" +
    std::to_wstring(GetTickCount64());
  const std::wstring write_name = release_name + L"-write";
  const std::wstring start_name = release_name + L"-start";
  const std::wstring ready_name = release_name + L"-ready";
  const std::wstring next_name = release_name + L"-next";
  HANDLE release = CreateEventW(nullptr, TRUE, FALSE, release_name.c_str());
  HANDLE write_final = CreateEventW(nullptr, TRUE, FALSE, write_name.c_str());
  HANDLE start_writing =
    CreateEventW(nullptr, TRUE, FALSE, start_name.c_str());
  HANDLE chunk_ready =
    CreateEventW(nullptr, FALSE, FALSE, ready_name.c_str());
  HANDLE next_chunk =
    CreateEventW(nullptr, FALSE, FALSE, next_name.c_str());
  HANDLE stop_completed = CreateEventW(nullptr, TRUE, FALSE, nullptr);
  HANDLE descendant_reported = CreateEventW(nullptr, TRUE, FALSE, nullptr);
  HANDLE parent_final_blocked = CreateEventW(nullptr, TRUE, FALSE, nullptr);
  HANDLE release_parent_final = CreateEventW(nullptr, TRUE, FALSE, nullptr);
  ReaderStopWindowApi api;
  CHECK(release != nullptr);
  CHECK(write_final != nullptr);
  CHECK(start_writing != nullptr);
  CHECK(chunk_ready != nullptr);
  CHECK(next_chunk != nullptr);
  CHECK(stop_completed != nullptr);
  CHECK(descendant_reported != nullptr);
  CHECK(parent_final_blocked != nullptr);
  CHECK(release_parent_final != nullptr);
  CHECK(api.reader_checked_stop != nullptr);
  CHECK(api.release_reader != nullptr);
  CHECK(api.reader_stop_signaled != nullptr);
  if (!release || !write_final || !start_writing || !chunk_ready ||
      !next_chunk || !stop_completed || !descendant_reported ||
      !parent_final_blocked || !release_parent_final ||
      !api.reader_checked_stop || !api.release_reader ||
      !api.reader_stop_signaled) {
    if (release) CloseHandle(release);
    if (write_final) CloseHandle(write_final);
    if (start_writing) CloseHandle(start_writing);
    if (chunk_ready) CloseHandle(chunk_ready);
    if (next_chunk) CloseHandle(next_chunk);
    if (stop_completed) CloseHandle(stop_completed);
    if (descendant_reported) CloseHandle(descendant_reported);
    if (parent_final_blocked) CloseHandle(parent_final_blocked);
    if (release_parent_final) CloseHandle(release_parent_final);
    return;
  }

  std::mutex output_mutex;
  std::string output;
  std::atomic<bool> blocked_on_parent_final = false;
  purepad::ProcessCallbacks callbacks;
  callbacks.output = [&](std::string_view bytes) {
    bool have_descendant_record = false;
    bool have_parent_final = false;
    {
      std::lock_guard<std::mutex> lock(output_mutex);
      output.append(bytes);
      const size_t descendant_at = output.find("DESCENDANT:");
      have_descendant_record = descendant_at != std::string::npos &&
        output.find("\r\n", descendant_at) != std::string::npos;
      have_parent_final =
        output.find("PARENT-FINAL\r\n") != std::string::npos;
    }
    if (have_descendant_record) SetEvent(descendant_reported);
    if (have_parent_final && !blocked_on_parent_final.exchange(true)) {
      SetEvent(parent_final_blocked);
      WaitForSingleObject(release_parent_final, INFINITE);
    }
  };
  purepad::ProcessSession session(&api);
  const auto started = session.Start(
    Launch(child, {L"--spawn-inherited-stdout", release_name, write_name,
                   start_name, ready_name, next_name}),
    std::move(callbacks));
  CHECK(started.ok());
  if (!started.ok()) {
    SetEvent(release);
    SetEvent(release_parent_final);
    CloseHandle(release_parent_final);
    CloseHandle(parent_final_blocked);
    CloseHandle(descendant_reported);
    CloseHandle(stop_completed);
    CloseHandle(next_chunk);
    CloseHandle(chunk_ready);
    CloseHandle(start_writing);
    CloseHandle(write_final);
    CloseHandle(release);
    return;
  }

  CHECK(WaitForSingleObject(descendant_reported, 5'000) == WAIT_OBJECT_0);
  std::string before_parent_exit;
  {
    std::lock_guard<std::mutex> lock(output_mutex);
    before_parent_exit = output;
  }
  const size_t pid_begin = before_parent_exit.find("DESCENDANT:");
  const size_t pid_end = pid_begin == std::string::npos
    ? std::string::npos : before_parent_exit.find("\r\n", pid_begin);
  DWORD descendant_pid = 0;
  if (pid_begin != std::string::npos && pid_end != std::string::npos) {
    descendant_pid = static_cast<DWORD>(std::stoul(before_parent_exit.substr(
      pid_begin + std::string_view("DESCENDANT:").size(),
      pid_end - pid_begin - std::string_view("DESCENDANT:").size())));
  }
  CHECK(descendant_pid != 0);
  HANDLE descendant = descendant_pid == 0 ? nullptr :
    OpenProcess(SYNCHRONIZE | PROCESS_QUERY_LIMITED_INFORMATION |
                  PROCESS_TERMINATE,
                FALSE, descendant_pid);
  CHECK(descendant != nullptr);

  SetEvent(write_final);
  CHECK(session.WaitForExit(5s));
  CHECK(WaitForSingleObject(parent_final_blocked, 5'000) == WAIT_OBJECT_0);
  if (descendant)
    CHECK(WaitForSingleObject(descendant, 0) == WAIT_TIMEOUT);

  api.Arm();
  SetEvent(release_parent_final);
  const bool reader_paused_after_clear_stop =
    WaitForSingleObject(api.reader_checked_stop, 5'000) == WAIT_OBJECT_0;
  CHECK(reader_paused_after_clear_stop);
  std::thread stopper([&] {
    session.Stop();
    SetEvent(stop_completed);
  });
  const bool reader_stop_was_signaled =
    WaitForSingleObject(api.reader_stop_signaled, 5'000) == WAIT_OBJECT_0;
  CHECK(reader_stop_was_signaled);
  SetEvent(api.release_reader);
  // Event handshakes position the race.  This generous outer wait only turns
  // a future-byte ReadFile mutant into a bounded test failure.
  const bool stopped_with_empty_inherited_pipe =
    WaitForSingleObject(stop_completed, 10'000) == WAIT_OBJECT_0;
  SetEvent(release);
  SetEvent(api.release_reader);
  SetEvent(release_parent_final);
  CHECK(WaitForSingleObject(stop_completed, 5'000) == WAIT_OBJECT_0);
  stopper.join();

  CHECK(stopped_with_empty_inherited_pipe);
  CHECK(!session.IsRunning());
  {
    std::lock_guard<std::mutex> lock(output_mutex);
    CHECK(output.find("PARENT-FINAL\r\n") != std::string::npos);
  }
  if (descendant) {
    CHECK(WaitForSingleObject(descendant, 5'000) == WAIT_OBJECT_0);
    DWORD exit_code = STILL_ACTIVE;
    CHECK(GetExitCodeProcess(descendant, &exit_code));
    CHECK(exit_code != STILL_ACTIVE);
    if (exit_code == STILL_ACTIVE) {
      TerminateProcess(descendant, 11);
      WaitForSingleObject(descendant, 5'000);
    }
    CloseHandle(descendant);
  }
  CloseHandle(release_parent_final);
  CloseHandle(parent_final_blocked);
  CloseHandle(descendant_reported);
  CloseHandle(stop_completed);
  CloseHandle(next_chunk);
  CloseHandle(chunk_ready);
  CloseHandle(start_writing);
  CloseHandle(write_final);
  CloseHandle(release);
}

void inherited_stdout_descendant_does_not_block_stop(const wchar_t* child) {
  const std::wstring release_name =
    L"Local\\PurePadInheritedStdout-" +
    std::to_wstring(GetCurrentProcessId()) + L"-" +
    std::to_wstring(GetTickCount64());
  const std::wstring write_name = release_name + L"-write";
  const std::wstring start_name = release_name + L"-start";
  const std::wstring ready_name = release_name + L"-ready";
  const std::wstring next_name = release_name + L"-next";
  HANDLE release = CreateEventW(nullptr, TRUE, FALSE, release_name.c_str());
  HANDLE write_final = CreateEventW(nullptr, TRUE, FALSE, write_name.c_str());
  HANDLE start_writing =
    CreateEventW(nullptr, TRUE, FALSE, start_name.c_str());
  HANDLE chunk_ready =
    CreateEventW(nullptr, FALSE, FALSE, ready_name.c_str());
  HANDLE next_chunk =
    CreateEventW(nullptr, FALSE, FALSE, next_name.c_str());
  HANDLE reader_blocked = CreateEventW(nullptr, TRUE, FALSE, nullptr);
  HANDLE release_reader = CreateEventW(nullptr, TRUE, FALSE, nullptr);
  HANDLE stop_completed = CreateEventW(nullptr, TRUE, FALSE, nullptr);
  CHECK(release != nullptr);
  CHECK(write_final != nullptr);
  CHECK(start_writing != nullptr);
  CHECK(chunk_ready != nullptr);
  CHECK(next_chunk != nullptr);
  CHECK(reader_blocked != nullptr);
  CHECK(release_reader != nullptr);
  CHECK(stop_completed != nullptr);
  if (!release || !write_final || !start_writing || !chunk_ready ||
      !next_chunk || !reader_blocked || !release_reader || !stop_completed) {
    if (release) CloseHandle(release);
    if (write_final) CloseHandle(write_final);
    if (start_writing) CloseHandle(start_writing);
    if (chunk_ready) CloseHandle(chunk_ready);
    if (next_chunk) CloseHandle(next_chunk);
    if (reader_blocked) CloseHandle(reader_blocked);
    if (release_reader) CloseHandle(release_reader);
    if (stop_completed) CloseHandle(stop_completed);
    return;
  }

  std::mutex output_mutex;
  std::string output;
  std::atomic<bool> blocked = false;
  std::atomic<bool> refill_after_callback = false;
  purepad::ProcessCallbacks callbacks;
  callbacks.output = [&](std::string_view bytes) {
    bool have_descendant_record = false;
    {
      std::lock_guard<std::mutex> lock(output_mutex);
      output.append(bytes);
      have_descendant_record = output.find("\r\n") != std::string::npos;
    }
    if (have_descendant_record && !blocked.exchange(true)) {
      SetEvent(reader_blocked);
      WaitForSingleObject(release_reader, INFINITE);
      return;
    }
    if (refill_after_callback.load(std::memory_order_acquire)) {
      // Do not return until the descendant has queued the next chunk.  Thus
      // the pre-fix unbounded drain cannot escape through a transient empty
      // pipe; only the explicit release below ends that stream.
      SetEvent(next_chunk);
      HANDLE refill_events[] = {release, chunk_ready};
      WaitForMultipleObjects(2, refill_events, FALSE, INFINITE);
    }
  };
  ReaderShutdownApi api;
  purepad::ProcessSession session(&api);
  const auto started = session.Start(
    Launch(child, {L"--spawn-inherited-stdout", release_name, write_name,
                   start_name, ready_name, next_name}),
    std::move(callbacks));
  CHECK(started.ok());
  if (!started.ok()) {
    SetEvent(release);
    CloseHandle(release_reader);
    CloseHandle(reader_blocked);
    CloseHandle(next_chunk);
    CloseHandle(chunk_ready);
    CloseHandle(start_writing);
    CloseHandle(write_final);
    CloseHandle(stop_completed);
    CloseHandle(release);
    return;
  }
  CHECK(WaitForSingleObject(reader_blocked, 5'000) == WAIT_OBJECT_0);
  SetEvent(write_final);
  CHECK(session.WaitForExit(5s));

  std::string before_stop;
  {
    std::lock_guard<std::mutex> lock(output_mutex);
    before_stop = output;
  }
  const size_t pid_begin = before_stop.find("DESCENDANT:");
  const size_t pid_end = pid_begin == std::string::npos
    ? std::string::npos : before_stop.find("\r\n", pid_begin);
  DWORD descendant_pid = 0;
  if (pid_begin != std::string::npos && pid_end != std::string::npos) {
    descendant_pid = static_cast<DWORD>(std::stoul(before_stop.substr(
      pid_begin + std::string_view("DESCENDANT:").size(),
      pid_end - pid_begin - std::string_view("DESCENDANT:").size())));
  }
  CHECK(descendant_pid != 0);
  HANDLE descendant = descendant_pid == 0 ? nullptr :
    OpenProcess(SYNCHRONIZE | PROCESS_QUERY_LIMITED_INFORMATION |
                  PROCESS_TERMINATE,
                FALSE, descendant_pid);
  CHECK(descendant != nullptr);

  std::thread stopper([&] {
    session.Stop();
    SetEvent(stop_completed);
  });
  const bool reader_shutdown_observed =
    WaitForSingleObject(api.reader_shutdown_requested, 5'000) == WAIT_OBJECT_0;
  CHECK(reader_shutdown_observed);
  SetEvent(start_writing);
  const bool first_chunk_ready =
    WaitForSingleObject(chunk_ready, 5'000) == WAIT_OBJECT_0;
  CHECK(first_chunk_ready);
  refill_after_callback.store(true, std::memory_order_release);
  SetEvent(release_reader);
  // This generous outer bound detects a hang; event handshakes position the
  // race and make no correctness assertion about scheduler timing.
  const bool stopped_while_descendant_held_stdout =
    WaitForSingleObject(stop_completed, 10'000) == WAIT_OBJECT_0;
  SetEvent(release);
  CHECK(WaitForSingleObject(stop_completed, 5'000) == WAIT_OBJECT_0);
  stopper.join();

  CHECK(stopped_while_descendant_held_stdout);
  CHECK(api.cancel_calls.load() == 1);
  {
    std::lock_guard<std::mutex> lock(output_mutex);
    CHECK(output.find("PARENT-FINAL\r\n") != std::string::npos);
  }
  CHECK(!session.IsRunning());
  if (descendant) {
    CHECK(WaitForSingleObject(descendant, 5'000) == WAIT_OBJECT_0);
    DWORD exit_code = STILL_ACTIVE;
    CHECK(GetExitCodeProcess(descendant, &exit_code));
    CHECK(exit_code != STILL_ACTIVE);
    if (exit_code == STILL_ACTIVE) {
      TerminateProcess(descendant, 11);
      WaitForSingleObject(descendant, 5'000);
    }
    CloseHandle(descendant);
  }
  CloseHandle(stop_completed);
  CloseHandle(release_reader);
  CloseHandle(reader_blocked);
  CloseHandle(next_chunk);
  CloseHandle(chunk_ready);
  CloseHandle(start_writing);
  CloseHandle(write_final);
  CloseHandle(release);
}

void output_callback_can_stop_session(const wchar_t* child) {
  purepad::ProcessSession session;
  std::atomic<bool> armed = false;
  std::atomic<bool> triggered = false;
  HANDLE completed = CreateEventW(nullptr, TRUE, FALSE, nullptr);
  std::string output;
  purepad::ProcessCallbacks callbacks;
  callbacks.output = [&](std::string_view bytes) {
    output.append(bytes);
    if (output.find("DONE\r\n") != std::string::npos &&
        !triggered.exchange(true)) {
      while (!armed.load(std::memory_order_acquire)) SwitchToThread();
      session.Stop();
      SetEvent(completed);
    }
  };
  const auto started = session.Start(
    Launch(child, {L"--echo"}), std::move(callbacks));
  CHECK(started.ok());
  if (started.ok()) {
    CHECK(session.Write("callback-stop\n"));
    armed.store(true, std::memory_order_release);
    CHECK(WaitForSingleObject(completed, 5'000) == WAIT_OBJECT_0);
    CHECK(!session.IsRunning());
  }
  CloseHandle(completed);
}

void exited_callback_can_restart_session(const wchar_t* child) {
  purepad::ProcessSession session;
  Output restarted_output;
  std::atomic<bool> armed = false;
  HANDLE completed = CreateEventW(nullptr, TRUE, FALSE, nullptr);
  purepad::ProcessResult restarted;
  purepad::ProcessCallbacks callbacks;
  callbacks.exited = [&] {
    while (!armed.load(std::memory_order_acquire)) SwitchToThread();
    restarted = session.Start(
      Launch(child, {L"--generation", L"callback-restart"}),
      restarted_output.Callbacks());
    SetEvent(completed);
  };
  const auto started = session.Start(
    Launch(child, {L"--echo"}), std::move(callbacks));
  CHECK(started.ok());
  if (started.ok()) {
    CHECK(session.Write("callback-restart\n"));
    armed.store(true, std::memory_order_release);
    CHECK(WaitForSingleObject(completed, 5'000) == WAIT_OBJECT_0);
    CHECK(restarted.ok());
    if (restarted.ok()) {
      CHECK(session.WaitForExit(5s));
      session.Stop();
      CHECK(restarted_output.Get() == "GEN:callback-restart\r\n");
    }
  }
  CloseHandle(completed);
}

void output_callback_can_destroy_session(const wchar_t* child) {
  auto session = std::make_unique<purepad::ProcessSession>();
  std::atomic<bool> armed = false;
  std::atomic<bool> triggered = false;
  HANDLE completed = CreateEventW(nullptr, TRUE, FALSE, nullptr);
  std::string output;
  purepad::ProcessCallbacks callbacks;
  callbacks.output = [&](std::string_view bytes) {
    output.append(bytes);
    if (output.find("DONE\r\n") != std::string::npos &&
        !triggered.exchange(true)) {
      while (!armed.load(std::memory_order_acquire)) SwitchToThread();
      session.reset();
      SetEvent(completed);
    }
  };
  const auto started = session->Start(
    Launch(child, {L"--echo"}), std::move(callbacks));
  CHECK(started.ok());
  if (started.ok()) {
    CHECK(session->Write("callback-destroy\n"));
    armed.store(true, std::memory_order_release);
    CHECK(WaitForSingleObject(completed, 5'000) == WAIT_OBJECT_0);
    CHECK(!session);
  }
  CloseHandle(completed);
}

void nonexistent_executable_fails_synchronously() {
  purepad::ProcessSession session;
  const auto result = session.Start(
    Launch(L"C:\\purepad-lifecycle-tests\\missing-child.exe", {L"--echo"}),
    {});
  CHECK(result.error == purepad::ProcessError::InvalidLaunch ||
        result.error == purepad::ProcessError::ProcessCreation);
  CHECK(!session.IsRunning());
}

void invalid_working_directory_fails_synchronously(const wchar_t* child) {
  purepad::ProcessSession session;
  auto launch = Launch(child, {L"--echo"});
  launch.working_directory = L"C:\\purepad-lifecycle-tests\\missing-directory";
  const auto result = session.Start(launch, {});
  CHECK(result.error == purepad::ProcessError::ProcessCreation);
  CHECK(!session.IsRunning());
}

void sibling_launch_uses_absolute_application_and_script_parent(
    const wchar_t* child) {
  const auto rooted_backslash = purepad::detail::BuildPipeLaunch(
    L"C:\\pure.exe", {}, L"\\script.pure", L"");
  CHECK(rooted_backslash.working_directory == L"\\");
  CHECK(rooted_backslash.arguments ==
        std::vector<std::wstring>{L"script.pure"});
  const auto rooted_slash = purepad::detail::BuildPipeLaunch(
    L"C:\\pure.exe", {}, L"/script.pure", L"");
  CHECK(rooted_slash.working_directory == L"/");
  CHECK(rooted_slash.arguments ==
        std::vector<std::wstring>{L"script.pure"});
  const auto extended_drive_root = purepad::detail::BuildPipeLaunch(
    L"C:\\pure.exe", {}, L"\\\\?\\C:\\script.pure", L"");
  CHECK(extended_drive_root.working_directory == L"\\\\?\\C:\\");
  CHECK(extended_drive_root.arguments ==
        std::vector<std::wstring>{L"script.pure"});

  wchar_t temporary_root[MAX_PATH]{};
  CHECK(GetTempPathW(MAX_PATH, temporary_root) != 0);
  const std::wstring working_directory =
    std::wstring(temporary_root) + L"PurePad sibling launch " +
    std::to_wstring(GetCurrentProcessId());
  CHECK(CreateDirectoryW(working_directory.c_str(), nullptr) ||
        GetLastError() == ERROR_ALREADY_EXISTS);
  ScopedDirectory cleanup(working_directory);

  const std::wstring helper = working_directory + L"\\sibling helper.exe";
  CHECK(CopyFileW(child, helper.c_str(), FALSE));
  const std::wstring script = working_directory + L"\\script-name.pure";
  HANDLE script_file = CreateFileW(script.c_str(), GENERIC_WRITE, 0, nullptr,
                                   CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL,
                                   nullptr);
  CHECK(script_file != INVALID_HANDLE_VALUE);
  if (script_file != INVALID_HANDLE_VALUE) CloseHandle(script_file);

  ScopedEnvironmentVariable path(
    L"PATH", L"C:\\Windows\\System32;C:\\Windows");
  CHECK(path.changed());
  Output output;
  purepad::ProcessSession session;
  auto launch = purepad::detail::BuildPipeLaunch(
    helper, {L"--launch-report", L"fixed sibling argument"}, script,
    L"test prompt");
  CHECK(launch.application == helper);
  CHECK(launch.working_directory == working_directory);
  CHECK((launch.arguments == std::vector<std::wstring>{
    L"--launch-report", L"fixed sibling argument", L"script-name.pure"}));
  const auto result = session.Start(launch, output.Callbacks());
  CHECK(result.ok());
  if (!result.ok()) return;
  CHECK(session.WaitForExit(5s));
  session.Stop();
  CHECK(output.Get() ==
        LaunchReportRecord("cwd", working_directory) +
          LaunchReportRecord("arg", L"fixed sibling argument") +
          LaunchReportRecord("script", L"script-name.pure"));
}

void adapter_output_preserves_split_utf8_and_notification_coalescing() {
  purepad::detail::Utf8Decoder decoder;
  CBuffer buffer;
  std::string first(4095, 'x');
  first.push_back(static_cast<char>(0xe2));
  CHECK(purepad::detail::AppendDecodedOutput(buffer, decoder, first));
  CHECK(buffer.GetLength() == 4095);
  CHECK(!purepad::detail::AppendDecodedOutput(
    buffer, decoder, std::string_view("\x82\xac", 2)));
  const CString actual = buffer.Read();
  CHECK(actual.GetLength() == 4096);
  if (actual.GetLength() == 4096)
    CHECK(actual[4095] == static_cast<TCHAR>(0x20ac));
}

void adapter_output_replaces_nul_for_ui_consumers() {
  purepad::detail::Utf8Decoder decoder;
  CBuffer buffer;
  CHECK(purepad::detail::AppendDecodedOutput(
    buffer, decoder, std::string_view("A\0B", 3)));
  const CString actual = buffer.Read();
  CHECK(actual.GetLength() == 3);
  if (actual.GetLength() == 3) {
    CHECK(actual[0] == _T('A'));
    CHECK(actual[1] == static_cast<TCHAR>(0xfffd));
    CHECK(actual[2] == _T('B'));
  }
  const CString nul_terminated_consumer(actual.GetString());
  CHECK(nul_terminated_consumer.GetLength() == 3);
  CHECK(nul_terminated_consumer == actual);
}

void adapter_decoder_state_is_generation_local_and_flushable() {
  purepad::detail::Utf8Decoder stopped_generation;
  CBuffer stopped_output;
  CHECK(!purepad::detail::AppendDecodedOutput(
    stopped_output, stopped_generation, std::string_view("\xe2", 1)));
  CHECK(purepad::detail::FlushDecodedOutput(
    stopped_output, stopped_generation));
  CHECK(stopped_output.GetLength() == 1);
  CBuffer reused_output;
  CHECK(purepad::detail::AppendDecodedOutput(
    reused_output, stopped_generation, "after"));
  CHECK(reused_output.Read() == _T("after"));

  purepad::detail::Utf8Decoder new_generation;
  CBuffer new_output;
  CHECK(purepad::detail::AppendDecodedOutput(
    new_output, new_generation, "next"));
  CHECK(new_output.Read() == _T("next"));
}

void each_worker_creation_failure_cleans_everything(const wchar_t* child) {
  for (int fail_at : {1, 2}) {
    FailingProcessApi api;
    api.fail_at = fail_at;
    purepad::ProcessSession session(&api);
    const auto failed = session.Start(Launch(child, {L"--echo"}), {});
    CHECK(failed.error == purepad::ProcessError::ThreadCreation);
    CHECK(failed.win32_error == ERROR_NOT_ENOUGH_MEMORY);
    CHECK(!session.IsRunning());

    api.fail_at = 0;
    api.calls = 0;
    Output output;
    const auto restarted = session.Start(
      Launch(child, {L"--echo"}), output.Callbacks());
    CHECK(restarted.ok());
    if (restarted.ok()) {
      CHECK(session.Write("again\n"));
      CHECK(session.WaitForExit(5s));
      session.Stop();
      CHECK(output.Get() == "READY\r\nagain\r\nDONE\r\n");
    }
  }
}

void environment_acquisition_failure_is_synchronous(const wchar_t* child) {
  FailingEnvironmentApi api;
  purepad::ProcessSession session(&api);
  const auto failed = session.Start(Launch(child, {L"--echo"}), {});
  CHECK(failed.error == purepad::ProcessError::EnvironmentCreation);
  CHECK(failed.win32_error == ERROR_NOT_ENOUGH_MEMORY);
  CHECK(!session.IsRunning());

  api.fail = false;
  Output output;
  const auto restarted = session.Start(
    Launch(child, {L"--echo"}), output.Callbacks());
  CHECK(restarted.ok());
  if (restarted.ok()) {
    CHECK(session.Write("environment\n"));
    CHECK(session.WaitForExit(5s));
    session.Stop();
    CHECK(output.Get() == "READY\r\nenvironment\r\nDONE\r\n");
  }
}

void exit_notification_only_follows_successful_start(const wchar_t* child) {
  std::atomic<int> successful_exits = 0;
  Output output;
  auto callbacks = output.Callbacks();
  callbacks.exited = [&] { successful_exits.fetch_add(1); };
  purepad::ProcessSession session;
  const auto started = session.Start(
    Launch(child, {L"--generation", L"notification"}),
    std::move(callbacks));
  CHECK(started.ok());
  if (started.ok()) {
    CHECK(session.WaitForExit(5s));
    session.Stop();
    CHECK(successful_exits.load() == 1);
  }

  std::atomic<int> failed_exits = 0;
  FailingProcessApi api;
  api.fail_at = 1;
  purepad::ProcessSession failed_session(&api);
  purepad::ProcessCallbacks failed_callbacks;
  failed_callbacks.exited = [&] { failed_exits.fetch_add(1); };
  const auto failed = failed_session.Start(
    Launch(child, {L"--generation", L"failed"}),
    std::move(failed_callbacks));
  CHECK(!failed.ok());
  CHECK(failed_exits.load() == 0);
}

void immediate_break_and_stop_are_idempotent(const wchar_t* child) {
  Output output;
  purepad::ProcessSession session;
  const auto result = session.Start(
    Launch(child, {L"--wait-for-break"}), output.Callbacks());
  CHECK(result.ok());
  if (!result.ok()) return;
  session.Break();
  CHECK(session.WaitForExit(5s));
  CHECK(output.WaitFor("BREAK\r\n"));
  session.Break();
  session.Stop();
  session.Break();
  session.Stop();
  CHECK(!session.IsRunning());
}

void immediate_stop_signals_terminate_event(const wchar_t* child) {
  Output output;
  purepad::ProcessSession session;
  const auto result = session.Start(
    Launch(child, {L"--wait-for-stop"}), output.Callbacks());
  CHECK(result.ok());
  if (!result.ok()) return;
  session.Stop();
  CHECK(output.Get() == "READY\r\nSTOP\r\n");
  session.Stop();
  CHECK(!session.IsRunning());
}

void immediate_restart_has_isolated_generations(const wchar_t* child) {
  purepad::ProcessSession session;
  for (int generation = 0; generation != 100; ++generation) {
    Output output;
    const std::wstring marker = L"generation-" + std::to_wstring(generation);
    const auto result = session.Start(
      Launch(child, {L"--generation", marker}), output.Callbacks());
    CHECK(result.ok());
    if (!result.ok()) return;
    CHECK(session.WaitForExit(5s));
    session.Stop();
    const std::string expected =
      "GEN:generation-" + std::to_string(generation) + "\r\n";
    CHECK(output.Get() == expected);
    CHECK(Count(output.Get(), expected) == 1);
  }
}

void windows_arguments_round_trip(const wchar_t* child) {
  Output output;
  purepad::ProcessSession session;
  const auto result = session.Start(
    Launch(child, {L"--arguments", L"space value", L"quote\"value",
                   L"C:\\trailing\\", L"", L"one\\\"quote",
                   L"C:\\trailing path\\"}),
    output.Callbacks());
  CHECK(result.ok());
  if (!result.ok()) return;
  CHECK(session.WaitForExit(5s));
  session.Stop();
  CHECK(output.Get() ==
        "11:space value\r\n11:quote\"value\r\n12:C:\\trailing\\\r\n"
        "0:\r\n10:one\\\"quote\r\n17:C:\\trailing path\\\r\n");
}

void prompt_environment_is_child_local(const wchar_t* child) {
  const wchar_t parent_value[] = L"parent prompt";
  CHECK(SetEnvironmentVariableW(L"PURE_PS", parent_value));
  Output output;
  purepad::ProcessSession session;
  auto launch = Launch(child, {L"--print-pure-ps"});
  launch.prompt = L"child prompt";
  const auto result = session.Start(launch, output.Callbacks());
  CHECK(result.ok());
  if (result.ok()) {
    CHECK(session.WaitForExit(5s));
    session.Stop();
    CHECK(output.Get() == "12:child prompt\r\n");
  }
  wchar_t actual[64]{};
  CHECK(GetEnvironmentVariableW(L"PURE_PS", actual, 64) == 13);
  CHECK(std::wstring(actual) == parent_value);
  CHECK(SetEnvironmentVariableW(L"PURE_PS", nullptr));
}

void child_environment_is_sorted_replaced_and_double_terminated() {
  const std::vector<std::wstring> inherited = {
    L"zulu=9",
    L"=D:=D:\\work",
    L"Path=C:\\bin",
    L"pUrE_pS=stale",
    L"alpha=1",
    L"=C:=C:\\root",
    L"Beta=2",
    L"PURE_ps=duplicate",
  };
  const std::vector<wchar_t> actual =
    purepad::detail::BuildChildEnvironmentBlock(inherited, L"new prompt");
  const wchar_t expected[] =
    L"=C:=C:\\root\0"
    L"=D:=D:\\work\0"
    L"alpha=1\0"
    L"Beta=2\0"
    L"Path=C:\\bin\0"
    L"PURE_PS=new prompt\0"
    L"zulu=9\0";
  CHECK(actual == std::vector<wchar_t>(
    expected, expected + sizeof(expected) / sizeof(expected[0])));
}

void negative_wait_timeout_is_nonblocking(const wchar_t* child) {
  RecordingWaitApi api;
  purepad::ProcessSession session(&api);
  const auto result = session.Start(Launch(child, {L"--wait-for-stop"}), {});
  CHECK(result.ok());
  if (!result.ok()) return;
  CHECK(!session.WaitForExit(-1ms));
  CHECK(api.timeouts.size() == 1);
  if (api.timeouts.size() == 1) CHECK(api.timeouts.front() == 0);
  session.Stop();
}

void finite_wait_timeout_never_uses_infinite(const wchar_t* child) {
  RecordingWaitApi api;
  purepad::ProcessSession session(&api);
  const auto result = session.Start(Launch(child, {L"--wait-for-stop"}), {});
  CHECK(result.ok());
  if (!result.ok()) return;
  const auto timeout = std::chrono::milliseconds(
    static_cast<int64_t>(MAXDWORD) + 100);
  CHECK(!session.WaitForExit(timeout));
  CHECK(api.timeouts.size() == 1);
  if (api.timeouts.size() == 1) {
    CHECK(api.timeouts.front() == MAXDWORD - 1);
  }
  session.Stop();
}

void concurrent_stop_cancels_start(const wchar_t* child) {
  ResumeGateApi api;
  purepad::ProcessSession session(&api);
  purepad::ProcessResult started;
  std::atomic<int> exits = 0;
  purepad::ProcessCallbacks callbacks;
  callbacks.exited = [&] { exits.fetch_add(1); };
  std::thread starter([&] {
    started = session.Start(Launch(child, {L"--wait-for-stop"}),
                            std::move(callbacks));
  });
  CHECK(WaitForSingleObject(api.resumed, 5'000) == WAIT_OBJECT_0);
  std::atomic<bool> stop_returned = false;
  std::thread stopper([&] {
    session.Stop();
    stop_returned.store(true, std::memory_order_release);
  });
  Sleep(20);
  CHECK(!stop_returned.load(std::memory_order_acquire));
  SetEvent(api.release);
  starter.join();
  stopper.join();
  CHECK(!started.ok());
  CHECK(!session.IsRunning());
  CHECK(exits.load() == 0);
}

void concurrent_write_and_stop_are_serialized(const wchar_t* child) {
  BlockingSignalApi api;
  purepad::ProcessSession session(&api);
  const auto result = session.Start(
    Launch(child, {L"--wait-for-stop"}), {});
  CHECK(result.ok());
  if (!result.ok()) return;

  bool wrote = false;
  std::thread writer([&] { wrote = session.Write("input\n"); });
  CHECK(WaitForSingleObject(api.entered, 5'000) == WAIT_OBJECT_0);
  std::atomic<bool> stop_returned = false;
  std::thread stopper([&] {
    session.Stop();
    stop_returned.store(true, std::memory_order_release);
  });
  const auto deadline = std::chrono::steady_clock::now() + 5s;
  while (session.IsRunning() && std::chrono::steady_clock::now() < deadline)
    SwitchToThread();
  CHECK(!session.IsRunning());
  CHECK(!stop_returned.load(std::memory_order_acquire));
  SetEvent(api.release);
  writer.join();
  stopper.join();
  CHECK(wrote);
  CHECK(!session.Write("after stop\n"));
  CHECK(!session.IsRunning());
}

void concurrent_wait_for_exit_and_stop_keep_duplicate_alive(
    const wchar_t* child) {
  BlockingWaitApi api;
  purepad::ProcessSession session(&api);
  const auto result = session.Start(
    Launch(child, {L"--wait-for-stop"}), {});
  CHECK(result.ok());
  if (!result.ok()) return;

  bool exited = false;
  std::thread waiter([&] { exited = session.WaitForExit(5s); });
  CHECK(WaitForSingleObject(api.entered, 5'000) == WAIT_OBJECT_0);
  session.Stop();
  CHECK(!session.IsRunning());
  SetEvent(api.release);
  waiter.join();
  CHECK(exited);
}

} // namespace

int wmain(int argc, wchar_t** argv) {
  CHECK(argc == 2);
  if (argc != 2) return 1;
  const wchar_t* child = argv[1];
  adapter_output_preserves_split_utf8_and_notification_coalescing();
  adapter_output_replaces_nul_for_ui_consumers();
  adapter_decoder_state_is_generation_local_and_flushable();
  echo_round_trip(child);
  reader_stop_is_latched_after_normal_loop_check(child);
  inherited_stdout_descendant_does_not_block_stop(child);
  output_callback_can_stop_session(child);
  exited_callback_can_restart_session(child);
  output_callback_can_destroy_session(child);
  nonexistent_executable_fails_synchronously();
  invalid_working_directory_fails_synchronously(child);
  sibling_launch_uses_absolute_application_and_script_parent(child);
  each_worker_creation_failure_cleans_everything(child);
  environment_acquisition_failure_is_synchronous(child);
  exit_notification_only_follows_successful_start(child);
  immediate_break_and_stop_are_idempotent(child);
  immediate_stop_signals_terminate_event(child);
  immediate_restart_has_isolated_generations(child);
  windows_arguments_round_trip(child);
  prompt_environment_is_child_local(child);
  child_environment_is_sorted_replaced_and_double_terminated();
  negative_wait_timeout_is_nonblocking(child);
  finite_wait_timeout_never_uses_infinite(child);
  concurrent_stop_cancels_start(child);
  concurrent_write_and_stop_are_serialized(child);
  concurrent_wait_for_exit_and_stop_keep_duplicate_alive(child);
  return failures == 0 ? 0 : 1;
}
