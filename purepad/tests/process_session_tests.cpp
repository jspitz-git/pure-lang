#include "ProcessSession.h"

#include <atomic>
#include <chrono>
#include <iostream>
#include <memory>
#include <mutex>
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

size_t Count(std::string_view text, std::string_view needle) {
  size_t result = 0;
  for (size_t at = 0; (at = text.find(needle, at)) != std::string_view::npos;
       at += needle.size()) {
    ++result;
  }
  return result;
}

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
  echo_round_trip(child);
  output_callback_can_stop_session(child);
  exited_callback_can_restart_session(child);
  output_callback_can_destroy_session(child);
  nonexistent_executable_fails_synchronously();
  invalid_working_directory_fails_synchronously(child);
  each_worker_creation_failure_cleans_everything(child);
  environment_acquisition_failure_is_synchronous(child);
  exit_notification_only_follows_successful_start(child);
  immediate_break_and_stop_are_idempotent(child);
  immediate_stop_signals_terminate_event(child);
  immediate_restart_has_isolated_generations(child);
  windows_arguments_round_trip(child);
  prompt_environment_is_child_local(child);
  negative_wait_timeout_is_nonblocking(child);
  finite_wait_timeout_never_uses_infinite(child);
  concurrent_stop_cancels_start(child);
  concurrent_write_and_stop_are_serialized(child);
  concurrent_wait_for_exit_and_stop_keep_duplicate_alive(child);
  return failures == 0 ? 0 : 1;
}
