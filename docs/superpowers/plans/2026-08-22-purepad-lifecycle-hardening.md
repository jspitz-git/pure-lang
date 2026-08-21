# PurePad Lifecycle Hardening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make PurePad process startup, interruption, restart, and shutdown race-free and reproducibly tested on Windows.

**Architecture:** Move Win32 child-process, pipe, event, and worker-thread ownership from the MFC `CPipe` adapter into a small `ProcessSession` class with an explicit state machine and RAII handles. Test that class against a real helper process, then keep `CPipe` responsible only for CString conversion, buffers, and MFC notifications.

**Tech Stack:** C++17, Win32, MFC, CMake 3.25+, Visual Studio 2022 x64, CTest, GitHub Actions PowerShell.

**Spec:** `docs/superpowers/specs/2026-08-22-purepad-lifecycle-hardening-design.md`

## Global Constraints

- Preserve the stdin/stdout and `PURE_SIGINT-<pid>` / `PURE_SIGTERM-<pid>` protocols.
- Do not rewrite the MFC UI or change the Pure language protocol.
- No production or test path may call `TerminateThread`.
- A failed start returns failure synchronously after releasing every acquired resource.
- Blocking Win32 calls must not run while the lifecycle state lock is held.
- Keep Visual Studio 2022 x64 and shared MFC as the supported build.
- TODO-49 owns `.pure` association registration and VC/MFC redistributable installation.
- Use four build workers on this machine.
- Run Tasks 1–4 commands from `C:\pure-lang\purepad`; run repository-wide
  Git commands from `C:\pure-lang`.

---

### Task 1: Establish the real-process lifecycle test boundary

**Files:**
- Create: `purepad/ProcessSession.h`
- Create: `purepad/ProcessSession.cpp`
- Create: `purepad/tests/process_child.cpp`
- Create: `purepad/tests/process_session_tests.cpp`
- Modify: `purepad/CMakeLists.txt`

**Interfaces:**
- Produces `purepad::ProcessLaunch`, `purepad::ProcessResult`, `purepad::ProcessCallbacks`, `purepad::ProcessApi`, and `purepad::ProcessSession`.
- The child accepts `--echo`, `--wait-for-break`, and `--wait-for-stop` and prints literal readiness/completion markers to stdout.
- Later tasks extend this same interface; do not add a second lifecycle abstraction.

- [ ] **Step 1: Write the first failing lifecycle test**

Create `tests/process_session_tests.cpp` with a tiny assertion runner and this first behavior:

```cpp
#include "ProcessSession.h"
#include <chrono>
#include <iostream>
#include <mutex>
#include <string>
#include <vector>

using namespace std::chrono_literals;

static int failures = 0;
#define CHECK(condition) do { if (!(condition)) { \
  std::cerr << __FILE__ << ':' << __LINE__ << ": " #condition "\n"; \
  ++failures; } } while (false)

int wmain(int argc, wchar_t** argv) {
  CHECK(argc == 2);
  std::mutex output_mutex;
  std::string output;
  purepad::ProcessSession session;
  purepad::ProcessCallbacks callbacks;
  callbacks.output = [&](std::string_view bytes) {
    std::lock_guard<std::mutex> lock(output_mutex);
    output.append(bytes);
  };
  purepad::ProcessLaunch launch;
  launch.application = argv[1];
  launch.arguments = {L"--echo"};
  auto started = session.Start(launch, std::move(callbacks));
  CHECK(started.ok());
  CHECK(session.Write("hello\n"));
  CHECK(session.WaitForExit(5s));
  session.Stop();
  CHECK(!session.IsRunning());
  {
    std::lock_guard<std::mutex> lock(output_mutex);
    CHECK(output == "READY\r\nhello\r\nDONE\r\n");
  }
  return failures == 0 ? 0 : 1;
}
```

The production mutation this catches is failure to connect the real child
stdio or failure to join the process and workers.

- [ ] **Step 2: Register the RED test and verify failure**

Add targets and one CTest to `CMakeLists.txt`, before creating
`ProcessSession.h` or `ProcessSession.cpp`:

```cmake
include(CTest)
if(BUILD_TESTING)
  add_executable(purepad-process-child tests/process_child.cpp)
  add_executable(purepad-process-session-tests
    tests/process_session_tests.cpp ProcessSession.cpp)
  target_compile_features(purepad-process-child PRIVATE cxx_std_17)
  target_compile_features(purepad-process-session-tests PRIVATE cxx_std_17)
  target_include_directories(purepad-process-session-tests PRIVATE
    "${CMAKE_CURRENT_SOURCE_DIR}")
  add_test(NAME purepad-process-session
    COMMAND purepad-process-session-tests
      "$<TARGET_FILE:purepad-process-child>")
endif()
```

Run:

```powershell
cmake --preset vs2022-x64
cmake --build --preset vs2022-x64-debug --parallel 4
```

Expected: build fails because `ProcessSession.h` is absent. This is the RED
proof for the new boundary, not an infrastructure error to bypass.

- [ ] **Step 3: Add the exact public lifecycle interface**

Create `ProcessSession.h` with this public surface and a private PIMPL:

```cpp
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
  None, InvalidLaunch, PipeCreation, EventCreation, ProcessCreation,
  ThreadCreation, ResumeProcess
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
```

- [ ] **Step 4: Implement the minimal real echo lifecycle**

Implement `process_child.cpp` so `--echo` prints `READY\r\n`, echoes one line,
prints `DONE\r\n`, and exits. Implement `ProcessSession.cpp` with:

- a move-only `UniqueHandle` which closes every non-null/non-invalid handle;
- inheritable child stdin/stdout endpoints and non-inheritable parent endpoints;
- `CreateProcessW` with `CREATE_SUSPENDED | CREATE_NO_WINDOW` and the exact
  application path in `lpApplicationName`;
- one reader and one writer worker created through `ProcessApi`;
- a manual-reset stop event and an input-available event;
- a copied Unicode child environment block in which only the child's `PURE_PS`
  value is replaced, passed with `CREATE_UNICODE_ENVIRONMENT`;
- `ResumeThread` only after all required handles and workers exist;
- `Stop()` which signals stop, closes stdin, calls `CancelSynchronousIo` for
  blocked workers, closes the remaining parent pipe endpoints, waits for the
  child, uses `TerminateProcess` only after one second, joins workers, and
  returns to `Idle`.

Use these exact state and implementation declarations inside `Impl`:

```cpp
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
```

Never call a wait, `CreateProcessW`, callback, or pipe I/O while `state_lock` is
held.

- [ ] **Step 5: Verify GREEN and repeatability**

Run:

```powershell
cmake --build --preset vs2022-x64-debug --parallel 4
ctest --test-dir build/vs2022-x64 -C Debug -R purepad-process-session --repeat until-fail:100 --output-on-failure
```

Expected: 100/100 iterations pass and Task Manager/process enumeration shows no
remaining `purepad-process-child.exe`.

- [ ] **Step 6: Commit the lifecycle boundary**

```powershell
git add purepad/ProcessSession.h purepad/ProcessSession.cpp purepad/tests/process_child.cpp purepad/tests/process_session_tests.cpp purepad/CMakeLists.txt
git commit -m "Add tested PurePad process session"
```

### Task 2: Cover races, failure cleanup, events, and Windows quoting

**Files:**
- Modify: `purepad/ProcessSession.cpp`
- Modify: `purepad/tests/process_child.cpp`
- Modify: `purepad/tests/process_session_tests.cpp`

**Interfaces:**
- Consumes the Task 1 `ProcessSession` API without changing its public names.
- Produces a deterministic `FailingProcessApi` test double which fails only the
  selected worker-thread creation ordinal.

- [ ] **Step 1: Add RED table-driven lifecycle cases**

Extend the test runner with literal cases for:

```cpp
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
```

Add separate named test functions which assert observable behavior:

- `nonexistent_executable_fails_synchronously`: `Start` returns
  `ProcessError::InvalidLaunch` or `ProcessCreation`, session is idle.
- `invalid_working_directory_fails_synchronously`: literal invalid directory,
  `ProcessCreation`, session idle.
- `each_worker_creation_failure_cleans_everything`: run with `fail_at` 1 and 2,
  require `ThreadCreation`, error `ERROR_NOT_ENOUGH_MEMORY`, session idle, then
  start a normal generation successfully with the same object.
- `immediate_break_and_stop_are_idempotent`: child `--wait-for-break`, call
  `Break` immediately, observe `BREAK`, call `Break` and `Stop` twice more.
- `immediate_restart_has_isolated_generations`: 100 start/stop generations,
  each output contains its literal generation argument exactly once.
- `windows_arguments_round_trip`: pass literals `space value`, `quote\"value`,
  `C:\\trailing\\`, and empty string; child serializes one length-prefixed value
  per line and the parent compares exact literals.
- `prompt_environment_is_child_local`: helper prints `PURE_PS`; require the
  launch prompt in the child and the original parent value after exit.

The production mutations caught are the original lock leak, incomplete startup
cleanup, generation handle reuse, missing event creation before resume, and the
old simplistic quote escaping.

- [ ] **Step 2: Run RED against the Task 1 implementation**

```powershell
cmake --build --preset vs2022-x64-debug --parallel 4
ctest --test-dir build/vs2022-x64 -C Debug -R purepad-process-session --output-on-failure
```

Expected: the new break/restart/quoting/failure cases fail while the original
echo case remains green.

- [ ] **Step 3: Implement one state transition at a time**

Implement and rerun the focused executable after each item:

1. A lock guard around state reads/writes with explicit unlock before blocking.
2. Named auto-reset events created from the suspended child PID before resume.
3. A private `QuoteWindowsArgument(std::wstring_view)` implementing the
   `CommandLineToArgvW` rules: quote empty/whitespace arguments, double each run
   of backslashes before a quote, and double trailing backslashes before the
   closing quote.
4. One cleanup routine used by every partial-start error and by `Stop`.
5. Generation-local handles moved out under the state lock before cleanup so a
   later `Start` cannot observe or reuse them.

Return the first exact failing operation's `ProcessError` and `GetLastError()`.
Do not convert a failed start into a later asynchronous exit notification.

- [ ] **Step 4: Verify GREEN under repetition**

```powershell
ctest --test-dir build/vs2022-x64 -C Debug -R purepad-process-session --repeat until-fail:100 --output-on-failure
```

Expected: all cases pass in all 100 iterations with no child remaining.

- [ ] **Step 5: Commit race and failure coverage**

```powershell
git add purepad/ProcessSession.cpp purepad/tests/process_child.cpp purepad/tests/process_session_tests.cpp
git commit -m "Harden PurePad process lifecycle races"
```

### Task 3: Replace the legacy `CPipe` lifecycle with the tested session

**Files:**
- Modify: `purepad/Pipe.h`
- Modify: `purepad/Pipe.cpp`
- Modify: `purepad/CMakeLists.txt`
- Test: `purepad/tests/process_session_tests.cpp`

**Interfaces:**
- Consumes `ProcessSession` from Tasks 1–2.
- Preserves every public `CPipe` method used by `CEvalView`.

- [ ] **Step 1: Add a RED adapter test for sibling launch semantics**

Add a case which launches a helper copied to a directory containing spaces,
sets the process `PATH` to `C:\Windows\System32;C:\Windows`, passes a script
basename while using its parent as `working_directory`, and requires the helper
to report the expected absolute working directory and argument. Run it before
changing `CPipe`; it fails because the adapter has not yet moved to
`ProcessSession` and the new launch builder is absent.

- [ ] **Step 2: Reduce `Pipe.h` to the adapter state**

Keep its public methods unchanged and replace `ThreadInfo` plus all raw handles
with:

```cpp
#include "ProcessSession.h"

private:
  BOOL Run2(LPCTSTR application, LPCTSTR arguments,
            LPCTSTR name, LPCTSTR display_name);
  purepad::ProcessSession m_session;
  CBuffer m_bufInput;
  CBuffer m_bufOutput;
```

- [ ] **Step 3: Rewrite `Pipe.cpp` as a thin adapter**

- `Run` and `Debug` still select `-i -q` and `-i -q -g`.
- `Run2` derives working directory and basename exactly once, builds a
  `ProcessLaunch`, and supplies the prompt without mutating parent `PURE_PS`.
- The output callback converts UTF-8 to `CString`, appends to `m_bufInput`, and
  posts `WM_USER_INPUT` only when the buffer transitioned from empty.
- `Write` converts the input `CString` to UTF-8 and calls `m_session.Write`.
- `Break`, `Kill`, and `IsRunning` delegate directly.
- Delete `CompileRun`, `Reader`, `Writer`, `MakeEvents`, `QuoteArg`,
  `KillThreads`, `KillChild`, `Clean`, every raw thread/pipe handle, and every
  `TerminateThread` call.
- A failed `Start` displays a synchronous message containing the executable and
  `FormatMessageW` text for `win32_error`, then returns `FALSE`.

- [ ] **Step 4: Build the real MFC adapter and run lifecycle tests**

```powershell
cmake --build --preset vs2022-x64-debug --parallel 4
ctest --test-dir build/vs2022-x64 -C Debug --output-on-failure
```

Expected: MFC target builds without warnings and all lifecycle tests pass.

- [ ] **Step 5: Commit the adapter migration**

```powershell
git add purepad/Pipe.h purepad/Pipe.cpp purepad/CMakeLists.txt purepad/tests/process_session_tests.cpp
git commit -m "Use safe process sessions in PurePad"
```

### Task 4: Move association and deployment ownership to the installer boundary

**Files:**
- Modify: `purepad/qpad.cpp`
- Modify: `purepad/CMakeLists.txt`
- Create: `purepad/WINDOWS.md`
- Create: `purepad/cmake/VerifyInstalledPurePad.cmake`
- Create: `purepad/tests/install_contract.cmake`

**Interfaces:**
- Produces CMake install component `PurePad` containing `bin/purepad.exe` and
  `share/doc/purepad/WINDOWS.md`.
- TODO-49 consumes that component and owns `.pure` registry association and the
  VC/MFC redistributable.

- [ ] **Step 1: Add a RED installed-component behavior test**

Create `tests/install_contract.cmake` to install only `PurePad` into a unique
temporary prefix, fail unless `bin/purepad.exe` and the documentation exist,
and run `VerifyInstalledPurePad.cmake`. Register it as
`purepad-install-contract`. Run CTest and observe failure because no install
rules or verifier exist.

- [ ] **Step 2: Remove startup association mutation**

Delete only this startup call from `CQpadApp::InitInstance`:

```cpp
RegisterShellFileTypes(TRUE);
```

Keep `EnableShellOpen`, command-line file opening, drag/drop, and DDE behavior.

- [ ] **Step 3: Add the component and executable verifier**

Add:

```cmake
install(TARGETS purepad RUNTIME DESTINATION bin COMPONENT PurePad)
install(FILES WINDOWS.md DESTINATION share/doc/purepad COMPONENT PurePad)
```

`VerifyInstalledPurePad.cmake` must use `file(GET_RUNTIME_DEPENDENCIES)` and
require the staged executable to declare the expected Microsoft runtime names
without copying them from the Visual Studio tree. It must reject `msys-2.0.dll`,
embedded source/build prefixes supplied by the caller, and absence of
`longPathAware` in the manifest extracted with CMake's `CMAKE_MT` Windows SDK
tool. The install-contract test passes the executable, source/build prefixes,
and `CMAKE_MT` path to the verifier and installs the active configuration with
`cmake --install ... --config $<CONFIG> --component PurePad`. The verifier
reports the dependency names which TODO-49 must satisfy.

- [ ] **Step 4: Document the exact deployment contract**

`WINDOWS.md` must contain executable-relative `pure.exe`, AppData and
`PUREPAD_USER_DATA`, CMake configure/build/test/install commands, installer-owned
optional `.pure` association, and the exact Microsoft VC/MFC runtime DLL list.
It must not claim that copying DLLs from Visual Studio is supported.

- [ ] **Step 5: Verify GREEN**

```powershell
cmake --build --preset vs2022-x64-release --parallel 4
ctest --test-dir build/vs2022-x64 -C Release -R "purepad-(install-contract|process-session)" --output-on-failure
```

Expected: both tests pass; launching PurePad no longer changes association
ownership.

- [ ] **Step 6: Commit the packaging boundary**

```powershell
git add purepad/qpad.cpp purepad/CMakeLists.txt purepad/WINDOWS.md purepad/cmake/VerifyInstalledPurePad.cmake purepad/tests/install_contract.cmake
git commit -m "Define PurePad installer ownership"
```

### Task 5: Add Windows CI regression coverage

**Files:**
- Modify: `.github/workflows/non-linux-release-validation.yml`

**Interfaces:**
- Produces job `Windows PurePad lifecycle`; the job itself is the behavioral
  test and must pass on the pushed branch.

- [ ] **Step 1: Add the PurePad job**

Add path triggers for `purepad/**`, TODO-20, the approved spec/plan, and the
workflow. The job uses PowerShell and these commands:

```powershell
$vswhere = "$env:ProgramFiles(x86)\Microsoft Visual Studio\Installer\vswhere.exe"
& $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.ATLMFC
if ($LASTEXITCODE -ne 0) { throw 'Visual Studio MFC component is unavailable' }
$source = Join-Path $env:RUNNER_TEMP 'PurePad source with spaces'
Copy-Item "$env:GITHUB_WORKSPACE\purepad" $source -Recurse
cmake -S $source -B "$source\build" -G 'Visual Studio 17 2022' -A x64
cmake --build "$source\build" --config Release --parallel 4
ctest --test-dir "$source\build" -C Release --output-on-failure
cmake --build "$source\build" --config Debug --parallel 4
ctest --test-dir "$source\build" -C Debug --output-on-failure
```

Capture each CTest output in a log while preserving its exit code, then upload
the logs with `actions/upload-artifact@v4` even on failure.

- [ ] **Step 2: Commit CI coverage**

```powershell
git add .github/workflows/non-linux-release-validation.yml
git commit -m "Validate PurePad lifecycle on Windows"
```

- [ ] **Step 3: Push and verify the real workflow execution**

```powershell
git push
gh run list --workflow non-linux-release-validation.yml --branch windows-bundle --limit 1
gh run watch <run-id> --exit-status
```

Expected: GitHub accepts the YAML, both configurations build and test in the
space-containing source path, and both CTest logs are uploaded. If the branch
name differs, substitute the current branch reported by `git branch --show-current`.

### Task 6: Run final validation and close the audit remediation

**Files:**
- Modify: `pure/todo/TODO-20-modernize-purepad.md`
- Modify if measurements differ: `purepad/WINDOWS.md`

**Interfaces:**
- Consumes all preceding targets and tests.
- Produces the final reproducible TODO-20 audit record.

- [ ] **Step 1: Run fresh Debug and Release validation**

```powershell
Push-Location purepad
cmake --preset vs2022-x64
cmake --build --preset vs2022-x64-release --parallel 4
ctest --test-dir build/vs2022-x64 -C Release --output-on-failure
cmake --build --preset vs2022-x64-debug --parallel 4
ctest --test-dir build/vs2022-x64 -C Debug --output-on-failure
ctest --test-dir build/vs2022-x64 -C Release -R purepad-process-session --repeat until-fail:100 --output-on-failure
Pop-Location
```

Expected: both builds are warning-free, every test passes, and the lifecycle
test passes 100 consecutive repetitions.

- [ ] **Step 2: Run static and process residue gates**

```powershell
rg -n "TerminateThread|RegisterShellFileTypes" purepad -g '*.cpp' -g '*.h'
Get-Process purepad-process-child -ErrorAction SilentlyContinue
git diff --check
```

Expected: the symbol scan and process query produce no output; `git diff
--check` exits zero.

- [ ] **Step 3: Record measured evidence in TODO-20**

Append a 2026-08-22 audit-remediation entry with exact test counts, repetition
count, build configurations, elapsed times, CI job/run result, no-residue gate,
association ownership transfer, and VC/MFC handoff. Preserve
`Status: Closed on 2026-07-26`; state separately that the 2026-08-22 audit
remediation passed rather than rewriting the historical completion date.

- [ ] **Step 4: Verify the complete staged diff**

```powershell
git diff --check
git status --short
git diff --stat 7f707238..HEAD
```

Expected: only PurePad, TODO-20, the approved spec/plan, and the Windows workflow
are changed; repository-level `_deps/` and `build/` remain untracked and are not
staged.

- [ ] **Step 5: Commit closure evidence**

```powershell
git add pure/todo/TODO-20-modernize-purepad.md purepad/WINDOWS.md
git commit -m "Complete audited PurePad hardening"
```

- [ ] **Step 6: Request code review before integration**

Use `superpowers:requesting-code-review` on the complete commit range beginning
after design commit `7f707238`, address findings through RED/GREEN tests, rerun
Task 6, and only then offer the branch-finishing choices.
