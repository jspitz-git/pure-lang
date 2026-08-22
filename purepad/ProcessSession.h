#pragma once
#include <chrono>
#include <functional>
#include <memory>
#include <string>
#include <string_view>
#include <vector>
#include <windows.h>

namespace purepad {
struct ProcessLaunch {
  std::wstring application;
  std::vector<std::wstring> arguments;
  std::wstring working_directory;
  std::wstring prompt;
};
enum class ProcessError {
  None, InvalidLaunch, PipeCreation, EnvironmentCreation, EventCreation,
  ProcessCreation, ThreadCreation, ResumeProcess
};
struct ProcessResult {
  ProcessError error = ProcessError::None;
  DWORD win32_error = ERROR_SUCCESS;
  bool ok() const { return error == ProcessError::None; }
};
struct ProcessCallbacks {
  std::function<void(std::string_view)> output;
  std::function<void()> exited;
};
class ProcessApi {
public:
  virtual ~ProcessApi() = default;
  virtual HANDLE CreateWorkerThread(LPTHREAD_START_ROUTINE entry,
                                    void* context, DWORD* id);
  virtual BOOL CancelWorkerIo(HANDLE thread);
  virtual LPWCH GetEnvironmentStrings();
  virtual BOOL FreeEnvironmentStrings(LPWCH environment);
  virtual DWORD ResumeProcessThread(HANDLE thread);
  virtual DWORD WaitForProcess(HANDLE process, DWORD timeout);
};
class ProcessSession {
public:
  explicit ProcessSession(ProcessApi* api = nullptr);
  ~ProcessSession();
  ProcessSession(const ProcessSession&) = delete;
  ProcessSession& operator=(const ProcessSession&) = delete;
  ProcessResult Start(const ProcessLaunch&, ProcessCallbacks);
  bool Write(std::string_view bytes);
  void Break();
  void Stop();
  bool IsRunning() const;
  bool WaitForExit(std::chrono::milliseconds timeout);
private:
  class Impl;
  std::unique_ptr<Impl> impl_;
};
}
