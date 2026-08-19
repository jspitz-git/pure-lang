# Windows pure-bonjour Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build, test, and package the existing `pure-bonjour` API on 64-bit Windows using Microsoft's native DNS-SD API and no Apple runtime.

**Architecture:** Keep `bonjour.pure` as the public contract and add a separate `bonjour_windows.c` backend exporting the same five native operations and two finalizers. Focused private helpers own UTF conversion, DNS-SD names, synchronized registration/browser state, cancellation, and result snapshots; CMake selects this Windows backend and installs it only through the optional `PureBonjour` component.

**Tech Stack:** C11, CMake 3.25+, Ninja, MSYS2/CLANG64 Clang, Pure 0.68+, Win32 synchronization, Windows DNS-SD (`windns.h`, `dnsapi.dll`), Winsock, CTest, PowerShell, `llvm-readobj`, GitHub Actions.

**Spec:** `docs/superpowers/specs/2026-08-18-windows-pure-bonjour-design.md`

## Global Constraints

- Target only 64-bit Windows in the CLANG64 Pure distribution.
- Require Windows 10 or later and compile with `_WIN32_WINNT=0x0A00`.
- Preserve the public `bonjour.pure` API and native exports: `bonjour_publish`, `bonjour_unpublish`, `bonjour_check`, `bonjour_browse`, `bonjour_close`, `bonjour_avail`, and `bonjour_get`.
- Keep the existing `pure-bonjour/bonjour.c` as the non-Windows `dns_sd` implementation; do not mix Microsoft callback handling into it.
- Link the Windows module only to `libpure.dll` and Windows system libraries, including `dnsapi.dll` and `ws2_32.dll`.
- Do not download, copy, import, install, or package Apple Bonjour headers, libraries, services, executables, or DLLs.
- Install only through the optional CMake component `PureBonjour`; a default install must not include it.
- All registration, browse, resolve, deregistration, cancellation, and test waits must be bounded.
- Tests may publish only a unique temporary local-link service and must remove it on success and failure.
- No installed file may retain a source, build, or stage prefix.

## File Structure

- Create `pure-bonjour/bonjour_windows.h`: private Windows backend types, constants, and helper declarations shared only with native tests.
- Create `pure-bonjour/bonjour_windows.c`: Microsoft DNS-SD implementation and the seven native exports consumed by `bonjour.pure`.
- Create `pure-bonjour/CMakeLists.txt`: Windows module target, strict build settings, tests, optional component, and verifier entry points.
- Create `pure-bonjour/tests/unit.c`: deterministic tests for strings, names, result ownership, error mapping, and state transitions.
- Create `pure-bonjour/tests/lifecycle.c`: injected fake DNS-SD operations used to prove callback/cancel/finalizer ordering without multicast.
- Create `pure-bonjour/tests/smoke.pure`: real Pure registration, browse, resolve, and removal scenario.
- Create `pure-bonjour/cmake/RunSmokeTest.cmake`: bounded sanitized Pure test launcher.
- Create `pure-bonjour/cmake/Install.cmake`: exact optional-component payload and generated ownership inventory.
- Create `pure-bonjour/cmake/VerifyWindowsDependencies.cmake`: recursive PE import policy for the build-tree module.
- Create `pure-bonjour/cmake/VerifyInstalledPackage.cmake`: exact file/hash/relocation/runtime verifier.
- Create `pure-bonjour/tests/install-component.cmake`: prove default-install exclusion and component-only inclusion/removal.
- Create `pure-bonjour/tests/ci-contract.cmake`: lock down the clean-runner workflow contract before editing YAML.
- Create `pure-bonjour/WINDOWS.md`: operating-system, runtime, firewall, diagnostics, and license boundary.
- Modify `pure-bonjour/README`: document supported Windows behavior and generated version/date.
- Modify `.github/workflows/non-linux-release-validation.yml`: add a clean Windows `PureBonjour` build/test/package job.
- Modify `pure/todo/TODO-45-windows-pure-bonjour.md`: record each validated milestone and final ship-or-defer decision.

---

### Task 1: Lock the Windows build and private helper contract

**Files:**
- Create: `pure-bonjour/CMakeLists.txt`
- Create: `pure-bonjour/bonjour_windows.h`
- Create: `pure-bonjour/bonjour_windows.c`
- Create: `pure-bonjour/tests/unit.c`
- Modify: `pure/todo/TODO-45-windows-pure-bonjour.md`

**Interfaces:**
- Consumes: staged `pure>=0.68` through `PkgConfig::PURE`; Windows `MultiByteToWideChar`, `WideCharToMultiByte`, and DNS error constants.
- Produces: `wchar_t *bonjour_utf8_to_wide(const char *)`, `char *bonjour_wide_to_utf8(const wchar_t *)`, `wchar_t *bonjour_make_type_fqdn(const char *)`, `wchar_t *bonjour_make_instance_fqdn(const char *, const char *)`, `int bonjour_split_instance_fqdn(const wchar_t *, char **, char **, char **)`, and `int bonjour_status_error(DWORD)`.

- [ ] **Step 1: Write the failing helper tests**

Create `tests/unit.c` with table-driven assertions for ASCII and non-ASCII round trips, `_puretodo45._tcp` becoming `_puretodo45._tcp.local`, `Probe ą._puretodo45._tcp.local` splitting into `Probe ą`, `_puretodo45._tcp`, and `local`, rejection of malformed types, and negative nonzero error mapping:

```c
static void test_names(void) {
  wchar_t *fqdn = bonjour_make_instance_fqdn("Probe \xC4\x85",
                                             "_puretodo45._tcp");
  char *name = NULL, *type = NULL, *domain = NULL;
  assert(fqdn != NULL);
  assert(bonjour_split_instance_fqdn(fqdn, &name, &type, &domain) == 0);
  assert(strcmp(name, "Probe \xC4\x85") == 0);
  assert(strcmp(type, "_puretodo45._tcp") == 0);
  assert(strcmp(domain, "local") == 0);
  free(fqdn); free(name); free(type); free(domain);
  assert(bonjour_make_type_fqdn("http.tcp") == NULL);
  assert(bonjour_status_error(ERROR_ACCESS_DENIED) < 0);
  assert(bonjour_status_error(ERROR_SUCCESS) == 0);
}
```

- [ ] **Step 2: Run the test to verify the build fails**

Run:

```powershell
C:\msys64\clang64\bin\clang.exe -std=c11 -Wall -Wextra -Werror -D_WIN32_WINNT=0x0A00 -Ipure-bonjour pure-bonjour/tests/unit.c pure-bonjour/bonjour_windows.c -ldnsapi -lws2_32 -o build/pure-bonjour-unit.exe
```

Expected: FAIL because the header/source and helper functions are not yet defined.

- [ ] **Step 3: Add the minimal CMake target and helper declarations**

Create a Windows-only project and private header. The source must be testable without exporting helpers from `bonjour.dll`:

```cmake
cmake_minimum_required(VERSION 3.25)
project(pure_bonjour VERSION 0.2 LANGUAGES C)
if(NOT WIN32)
  message(FATAL_ERROR "pure-bonjour Windows backend requires Windows")
endif()
if(NOT CMAKE_SIZEOF_VOID_P EQUAL 8)
  message(FATAL_ERROR "PureBonjour supports only 64-bit Windows")
endif()
find_package(PkgConfig REQUIRED)
pkg_check_modules(PURE REQUIRED IMPORTED_TARGET "pure>=0.68")
add_library(pure-bonjour MODULE bonjour_windows.c)
set_target_properties(pure-bonjour PROPERTIES OUTPUT_NAME bonjour PREFIX ""
  WINDOWS_EXPORT_ALL_SYMBOLS ON)
target_compile_features(pure-bonjour PRIVATE c_std_11)
target_compile_definitions(pure-bonjour PRIVATE _WIN32_WINNT=0x0A00)
target_compile_options(pure-bonjour PRIVATE -Wall -Wextra -Werror)
target_link_libraries(pure-bonjour PRIVATE PkgConfig::PURE dnsapi ws2_32)
```

Declare owned-string return values and `0`/negative status semantics explicitly in `bonjour_windows.h`.

- [ ] **Step 4: Implement and pass the deterministic helper tests**

Use `MB_ERR_INVALID_CHARS` and `WC_ERR_INVALID_CHARS`; allocate from exact size probes; require service types matching `_<label>._tcp` or `_<label>._udp`; reject labels longer than 63 bytes and constructed names longer than 255 bytes. Map `DWORD` status without signed overflow:

```c
int bonjour_status_error(DWORD status) {
  if (status == ERROR_SUCCESS) return 0;
  if (status > (DWORD)INT_MAX) return -INT_MAX;
  return -(int)status;
}
```

Run the compile command from Step 2 and then:

```powershell
build\pure-bonjour-unit.exe
```

Expected: exit 0 and `pure-bonjour unit tests passed`.

- [ ] **Step 5: Configure the real module and inspect its initial imports/exports**

Run:

```powershell
C:\msys64\clang64\bin\cmake.exe -S pure-bonjour -B build/pure-bonjour -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_C_COMPILER=C:/msys64/clang64/bin/clang.exe -DPKG_CONFIG_EXECUTABLE=C:/msys64/clang64/bin/pkg-config.exe
C:\msys64\clang64\bin\cmake.exe --build build/pure-bonjour --verbose
C:\msys64\clang64\bin\llvm-readobj.exe --file-headers --coff-imports --coff-exports build/pure-bonjour/bonjour.dll
```

Expected: PE32+ x86-64; the build is warning-free; imports contain `libpure.dll`, `DNSAPI.dll`, `WS2_32.dll`, UCRT/system DLLs only; all seven native functions are exported after later tasks fill them in.

- [ ] **Step 6: Record and commit the build/helper milestone**

Add the exact commands, tool versions, and current import list to the TODO progress log, then run:

```powershell
git add pure-bonjour/CMakeLists.txt pure-bonjour/bonjour_windows.h pure-bonjour/bonjour_windows.c pure-bonjour/tests/unit.c pure/todo/TODO-45-windows-pure-bonjour.md
git commit -m "Add Windows pure-bonjour build helpers"
```

---

### Task 2: Implement registration with bounded completion and cleanup

**Files:**
- Modify: `pure-bonjour/bonjour_windows.h`
- Modify: `pure-bonjour/bonjour_windows.c`
- Create: `pure-bonjour/tests/lifecycle.c`
- Modify: `pure-bonjour/CMakeLists.txt`
- Modify: `pure/todo/TODO-45-windows-pure-bonjour.md`

**Interfaces:**
- Consumes: Task 1 string/name/error helpers; `DnsServiceConstructInstance`, `DnsServiceRegister`, `DnsServiceDeRegister`, `DnsServiceRegisterCancel`, and `DnsServiceFreeInstance`.
- Produces: opaque `bonjour_service_t`; `bonjour_service_t *bonjour_publish(const char *, const char *, int)`; `pure_expr *bonjour_check(bonjour_service_t *)`; `void bonjour_unpublish(bonjour_service_t *)`; private injected `bonjour_dns_api_t` function table and test-only `bonjour_service_t *bonjour_publish_with_api(const char *, const char *, int, const bonjour_dns_api_t *, DWORD)`.

- [ ] **Step 1: Write failing fake-API registration lifecycle tests**

The fake table records calls and explicitly fires completion callbacks. Cover synchronous rejection, asynchronous success, timeout, pending cancellation, deregistration after success, repeated null cleanup, and callback completion during cancellation:

```c
static void test_pending_registration_is_cancelled_before_free(void) {
  fake_dns_t fake = fake_dns_pending_registration();
  bonjour_service_t *service = bonjour_publish_with_api(
      "Probe", "_puretodo45._tcp", 43210, &fake.api, 25);
  assert(service != NULL);
  bonjour_unpublish(service);
  assert(fake.register_calls == 1);
  assert(fake.cancel_calls == 1);
  assert(fake.deregister_calls == 0);
  assert(fake.free_instance_calls == 1);
  assert(fake.callback_after_free == 0);
}
```

- [ ] **Step 2: Register and run the lifecycle test to verify RED**

Add a `pure-bonjour-lifecycle` executable compiled with `PURE_BONJOUR_TESTING=1`, link it to a backend object library plus `PkgConfig::PURE`, `dnsapi`, and `ws2_32`, and register CTest label `bonjour;lifecycle` with timeout 10 seconds.

Run:

```powershell
C:\msys64\clang64\bin\cmake.exe --build build/pure-bonjour --target pure-bonjour-lifecycle
C:\msys64\clang64\bin\ctest.exe --test-dir build/pure-bonjour -R "^pure-bonjour-lifecycle$" --output-on-failure
```

Expected: FAIL because registration state and injected entry points do not exist.

- [ ] **Step 3: Implement the registration state machine**

Use one lock, one manual-reset completion event, explicit state, and an in-callback counter:

```c
typedef enum {
  BONJOUR_REG_PENDING,
  BONJOUR_REG_REGISTERED,
  BONJOUR_REG_FAILED,
  BONJOUR_REG_STOPPING,
  BONJOUR_REG_STOPPED
} bonjour_reg_state_t;

struct bonjour_service_t {
  SRWLOCK lock;
  CONDITION_VARIABLE callbacks_done;
  HANDLE completion;
  DNS_SERVICE_CANCEL cancel;
  PDNS_SERVICE_INSTANCE instance;
  bonjour_reg_state_t state;
  DWORD status;
  unsigned callbacks;
  char *name;
  char *type;
  uint16_t port;
  const bonjour_dns_api_t *api;
  DWORD wait_ms;
};
```

Initialize all callback-visible fields before `DnsServiceRegister`. The callback increments/decrements `callbacks` under the lock, copies the effective instance name when available, stores only the first terminal outcome, sets the completion event, and wakes shutdown waiters.

- [ ] **Step 4: Implement bounded `check` and shutdown ordering**

`bonjour_check` waits at most the configured 10-second production limit; timeout becomes `bonjour_status_error(ERROR_TIMEOUT)`. `bonjour_unpublish` marks STOPPING under the lock, releases it, calls cancel or deregister, then waits on the condition variable until `callbacks == 0` before freeing the instance and context. It is a no-op for null.

Run:

```powershell
C:\msys64\clang64\bin\cmake.exe --build build/pure-bonjour --target pure-bonjour pure-bonjour-lifecycle
C:\msys64\clang64\bin\ctest.exe --test-dir build/pure-bonjour -R "^pure-bonjour-lifecycle$" --repeat until-fail:10 --output-on-failure
```

Expected: 10/10 lifecycle repetitions pass with no warning or hang.

- [ ] **Step 5: Record and commit registration evidence**

Record the covered state transitions and repeated-test duration in TODO-45, then:

```powershell
git add pure-bonjour/bonjour_windows.h pure-bonjour/bonjour_windows.c pure-bonjour/tests/lifecycle.c pure-bonjour/CMakeLists.txt pure/todo/TODO-45-windows-pure-bonjour.md
git commit -m "Implement bounded Windows Bonjour registration"
```

---

### Task 3: Implement browse, resolve, snapshots, and cancellation

**Files:**
- Modify: `pure-bonjour/bonjour_windows.h`
- Modify: `pure-bonjour/bonjour_windows.c`
- Modify: `pure-bonjour/tests/unit.c`
- Modify: `pure-bonjour/tests/lifecycle.c`
- Modify: `pure-bonjour/CMakeLists.txt`
- Modify: `pure/todo/TODO-45-windows-pure-bonjour.md`

**Interfaces:**
- Consumes: Task 1 helpers and Task 2 callback-quiescence rules; `DnsServiceBrowse`, `DnsServiceBrowseCancel`, `DnsServiceResolve`, `DnsServiceResolveCancel`, `DnsRecordListFree`, and `DnsServiceFreeInstance`.
- Produces: opaque `bonjour_browser_t`; `bonjour_browser_t *bonjour_browse(const char *)`; `int bonjour_avail(bonjour_browser_t *)`; `pure_expr *bonjour_get(bonjour_browser_t *)`; `void bonjour_close(bonjour_browser_t *)`; private `bonjour_result_t`/`bonjour_result_set_t` and `bonjour_results_put`, `bonjour_results_remove`, and `bonjour_results_clear` helpers keyed by `(fqdn, interface_index)`.

- [ ] **Step 1: Add failing result-set and discovery lifecycle tests**

Extend `unit.c` with add/update/remove tests proving stable keying and deep copies. Extend `lifecycle.c` with browse callback -> resolve callback -> snapshot, removal, immediate browse rejection, pending resolver cancellation, browser close during callbacks, and no-result cancellation:

```c
static void test_resolve_updates_existing_key(void) {
  bonjour_result_set_t set = {0};
  assert(bonjour_results_put(&set, L"Probe._puretodo45._tcp.local", 7,
      "Probe", "_puretodo45._tcp", "local", "127.0.0.1", 41000) == 1);
  assert(bonjour_results_put(&set, L"Probe._puretodo45._tcp.local", 7,
      "Probe", "_puretodo45._tcp", "local", "::1", 41000) == 1);
  assert(set.count == 1);
  assert(strcmp(set.head->address, "::1") == 0);
  bonjour_results_clear(&set);
}
```

- [ ] **Step 2: Run focused tests to verify RED**

Run:

```powershell
C:\msys64\clang64\bin\cmake.exe --build build/pure-bonjour --target pure-bonjour-unit pure-bonjour-lifecycle
C:\msys64\clang64\bin\ctest.exe --test-dir build/pure-bonjour -R "^pure-bonjour-(unit|lifecycle)$" --output-on-failure
```

Expected: FAIL on undefined result-set and browse/resolve functions.

- [ ] **Step 3: Implement owned result records and Pure snapshots**

Define a private linked result with owned UTF-8 strings and a key consisting of owned FQDN plus `DWORD interface_index`. `put` returns `1` for an observable add/change, `0` for identical data, and `-1` on allocation failure without altering the old value. `remove` returns `1` only when a record existed. `bonjour_get` constructs a new Pure list while holding the lock, resets `avail` only after successful construction, and never exposes internal storage.

- [ ] **Step 4: Implement browse-to-resolve flow**

The browser owns its `DNS_SERVICE_CANCEL`, a linked list of resolver contexts, lock, condition variable, status, availability flag, closing flag, and callback count. Parse PTR owner/target records from the browse callback, free every returned DNS record list exactly once, and start one resolver per `(fqdn, interface)` not already pending. Resolver callbacks copy IPv4 through `InetNtopA(AF_INET, ...)` and IPv6 through `InetNtopA(AF_INET6, ...)`, apply `ntohs` only if the Windows structure supplies network byte order (confirm from the SDK declaration/test), update results, detach themselves, and signal close waiters.

- [ ] **Step 5: Implement close without reentrant-lock hazards**

Under the lock set `closing = true` and snapshot cancel handles. Release the lock before calling `DnsServiceBrowseCancel` and each `DnsServiceResolveCancel`. Reacquire it and wait until both `callbacks == 0` and the resolver list is empty; use a production deadline and retain state rather than freeing callback-visible memory if the invariant cannot be proven. Make null close a no-op.

Run:

```powershell
C:\msys64\clang64\bin\cmake.exe --build build/pure-bonjour
C:\msys64\clang64\bin\ctest.exe --test-dir build/pure-bonjour -R "^pure-bonjour-(unit|lifecycle)$" --repeat until-fail:10 --output-on-failure
```

Expected: unit and lifecycle tests pass in all ten repetitions.

- [ ] **Step 6: Audit exports and commit discovery**

Run `llvm-readobj --coff-exports build/pure-bonjour/bonjour.dll` and require the exact seven public bridge functions. Record result counts and timing in TODO-45, then:

```powershell
git add pure-bonjour/bonjour_windows.h pure-bonjour/bonjour_windows.c pure-bonjour/tests/unit.c pure-bonjour/tests/lifecycle.c pure-bonjour/CMakeLists.txt pure/todo/TODO-45-windows-pure-bonjour.md
git commit -m "Add Windows Bonjour discovery lifecycle"
```

---

### Task 4: Add the bounded real Pure registration/discovery test

**Files:**
- Create: `pure-bonjour/tests/smoke.pure`
- Create: `pure-bonjour/cmake/RunSmokeTest.cmake`
- Modify: `pure-bonjour/CMakeLists.txt`
- Modify: `pure-bonjour/bonjour_windows.c`
- Modify: `pure-bonjour/tests/lifecycle.c`
- Modify: `pure/todo/TODO-45-windows-pure-bonjour.md`

**Interfaces:**
- Consumes: the seven public bridge exports and unchanged `bonjour.pure` wrapper.
- Produces: CTest `pure-bonjour-loopback` with labels `bonjour;dnssd;integration`, marker `PURE_BONJOUR_LOOPBACK_OK`, and at most 30 seconds wall time.

- [ ] **Step 1: Write the failing Pure smoke scenario**

Use a name containing process/time-derived uniqueness supplied by the runner and a reserved test type `_puretodo45._tcp`. The Pure script must browse first, publish a dynamic test port passed by the runner, call `check`, poll `avail`/`get` with short sleeps, match name/type/domain/port and loopback/local address, release the service, observe removal, release the browser, and print only the success marker after cleanup.

```pure
using bonjour;
using namespace bonjour;

find_service name port xs =
  any (\(n,t,d,a,p) -> n==name && t=="_puretodo45._tcp" &&
                         d=="local" && p==port && #a>0) xs;
```

- [ ] **Step 2: Add the runner and verify the test fails**

`RunSmokeTest.cmake` must require absolute existing `PURE_EXECUTABLE`, module, wrapper, and script paths; create a unique working directory; set `PURELIB` to a temporary directory containing only `bonjour.pure` and `bonjour.dll`; remove MSYS2 directories from `PATH`; run with `execute_process(TIMEOUT 25)`; require exact marker and zero exit; and remove the temporary directory.

Register the test only when `PURE_PREFIX/bin/pure.exe` exists. Run:

```powershell
C:\msys64\clang64\bin\cmake.exe --build build/pure-bonjour
C:\msys64\clang64\bin\ctest.exe --test-dir build/pure-bonjour -R "^pure-bonjour-loopback$" --output-on-failure -V
```

Expected: FAIL until the real backend handles all Windows callback record shapes correctly.

- [ ] **Step 3: Make the smallest backend corrections exposed by the real test**

Correct only observed API-contract issues. Add a fake lifecycle regression before each correction, such as record-list ownership, callback status ordering, effective registration name, interface matching, address byte order, or removal-key parsing. Do not add sleeps or broaden timeouts to hide a race.

- [ ] **Step 4: Prove bounded repeatability and cleanup**

Run:

```powershell
C:\msys64\clang64\bin\ctest.exe --test-dir build/pure-bonjour -R "^pure-bonjour-loopback$" --repeat until-fail:5 --output-on-failure
C:\msys64\clang64\bin\ctest.exe --test-dir build/pure-bonjour -R "^pure-bonjour-(unit|lifecycle|loopback)$" --output-on-failure
```

Expected: five integration repetitions pass, followed by all three tests passing; no process or service persists after each run.

- [ ] **Step 5: Record network boundary and commit integration**

Record whether the SDK/API allowed local-only scope, the exact fallback local-link scope if not, test durations, dynamic port method, and firewall behavior in TODO-45. Then:

```powershell
git add pure-bonjour/tests/smoke.pure pure-bonjour/cmake/RunSmokeTest.cmake pure-bonjour/CMakeLists.txt pure-bonjour/bonjour_windows.c pure-bonjour/tests/lifecycle.c pure/todo/TODO-45-windows-pure-bonjour.md
git commit -m "Test Windows Bonjour registration and discovery"
```

---

### Task 5: Add exact optional-component installation and dependency audit

**Files:**
- Create: `pure-bonjour/cmake/Install.cmake`
- Create: `pure-bonjour/cmake/VerifyWindowsDependencies.cmake`
- Create: `pure-bonjour/tests/install-component.cmake`
- Modify: `pure-bonjour/CMakeLists.txt`
- Modify: `pure-bonjour/README`
- Modify: `pure/todo/TODO-45-windows-pure-bonjour.md`

**Interfaces:**
- Consumes: built `bonjour.dll`, `bonjour.pure`, README template, `COPYING`, `COPYING.LESSER`, and `examples/bonjour_examp.pure`.
- Produces: optional component `PureBonjour`, `PureBonjourInventory.tsv`, `PureBonjourExpected.sha256`, CTest `pure-bonjour-install-component`, and target `verify-windows-dependencies`.

- [ ] **Step 1: Write failing install-component assertions**

The test first installs without `--component` into a fresh prefix and requires no PureBonjour-owned path. It then installs `--component PureBonjour` and requires exactly:

```text
lib/pure/bonjour.dll
lib/pure/bonjour.pure
share/doc/pure-bonjour/README
share/doc/pure-bonjour/WINDOWS.md
share/doc/pure-bonjour/COPYING
share/doc/pure-bonjour/COPYING.LESSER
share/doc/pure-bonjour/examples/bonjour_examp.pure
share/doc/pure-bonjour/PureBonjourInventory.tsv
```

Run the test and expect failure because install rules and inventory do not exist.

- [ ] **Step 2: Implement prefix-safe optional installation**

Reject absolute or parent-traversing install destinations. Generate README version `0.2` and current date without changing the source template. Generate the inventory from exact relative destination, purpose, origin, version, SHA-256, and size fields. Install all eight paths with `COMPONENT PureBonjour EXCLUDE_FROM_ALL`; the inventory is generated after the module exists and is itself included in an external expected-hash oracle.

- [ ] **Step 3: Add a recursive PE import policy**

Parse `llvm-readobj --coff-imports` records strictly. Resolve `libpure.dll` from `PURE_PREFIX/bin`; classify `DNSAPI.dll`, `WS2_32.dll`, KernelBase/Kernel32, UCRT/API-set DLLs, and other documented Windows DLLs as system; reject malformed records, missing imports, ambiguous case-folded duplicates, paths outside declared roots, `dnssd.dll`, Apple executables/services, and any MSYS2 runtime dependency.

Run:

```powershell
C:\msys64\clang64\bin\cmake.exe --build build/pure-bonjour --target verify-windows-dependencies
C:\msys64\clang64\bin\ctest.exe --test-dir build/pure-bonjour -R "^pure-bonjour-install-component$" --output-on-failure
```

Expected: dependency audit passes and the component contains exactly eight files while the default install contains none of them.

- [ ] **Step 4: Add mutation checks for the audit**

In script-mode tests feed one valid synthetic import listing plus malformed header, unknown DLL, `dnssd.dll`, and ambiguous import cases to the same parser entry point. Require each invalid case to fail with its stable category token. Run those tests before accepting the real-module audit.

- [ ] **Step 5: Record manifest/import evidence and commit packaging**

Record installed paths, sizes, hashes, and recursive dependency count in TODO-45, then:

```powershell
git add pure-bonjour/cmake/Install.cmake pure-bonjour/cmake/VerifyWindowsDependencies.cmake pure-bonjour/tests/install-component.cmake pure-bonjour/CMakeLists.txt pure-bonjour/README pure/todo/TODO-45-windows-pure-bonjour.md
git commit -m "Package optional PureBonjour component"
```

---

### Task 6: Verify installed and relocated runtime ownership

**Files:**
- Create: `pure-bonjour/cmake/VerifyInstalledPackage.cmake`
- Create: `pure-bonjour/tests/package-mutations.cmake`
- Create: `pure-bonjour/tests/relocation-ownership.cmake`
- Modify: `pure-bonjour/CMakeLists.txt`
- Modify: `pure/todo/TODO-45-windows-pure-bonjour.md`

**Interfaces:**
- Consumes: Task 5 component, external expected-hash oracle, inventory, recursive import parser, Pure executable/runtime, and smoke script.
- Produces: CTests `pure-bonjour-package-verifier`, `pure-bonjour-package-mutations`, and `pure-bonjour-relocation-ownership`; a verifier callable by CI with `-DSTAGE_PREFIX`, `-DSOURCE_PREFIX`, `-DBUILD_PREFIX`, and `-DPURE_PREFIX`.

- [ ] **Step 1: Write failing package mutation cases**

Stage a valid component, prove the verifier accepts it, then independently copy and mutate cases: changed module, deleted license, undeclared file, forged inventory hash, duplicate/case-colliding inventory path, absolute/parent-traversing inventory path, malformed row, source/build/stage prefix embedded as ASCII, and UTF-16LE prefix leakage. Require rejection tokens such as `PACKAGE_HASH`, `PACKAGE_SET`, `PACKAGE_INVENTORY`, and `PACKAGE_PREFIX`.

- [ ] **Step 2: Implement exact installed-package verification**

Canonicalize the stage, reject reparse points, parse the external oracle and installed inventory independently, reject duplicate normalized paths, compare exact file sets/sizes/SHA-256, scan every file for source/build/stage prefixes in ASCII and UTF-16LE, recursively audit PE imports, and run installed `bonjour.pure`/`bonjour.dll` through the smoke runner with sanitized environment.

- [ ] **Step 3: Verify relocation**

Install into a prefix containing spaces and Unicode, verify it, copy the complete staged Pure runtime plus component to a second unrelated prefix, verify again, run the smoke test there, overlay the same component, and prove unrelated sentinel files remain byte-identical.

- [ ] **Step 4: Verify exact removal ownership**

Remove only paths declared in the trusted external oracle, remove now-empty PureBonjour-specific directories, and require unrelated shared-prefix files and directories to remain. Never trust the installed inventory as authority for deletion. Repeat against an installed forged inventory and prove the external oracle still bounds removal.

Run:

```powershell
C:\msys64\clang64\bin\ctest.exe --test-dir build/pure-bonjour -R "^pure-bonjour-(package-verifier|package-mutations|relocation-ownership)$" --output-on-failure
```

Expected: all valid stage/relocation/overlay/removal paths pass and every mutation is rejected by its expected category.

- [ ] **Step 5: Record and commit package verification**

Record exact file count, total bytes, inventory SHA-256, relocation paths, mutation count, and dependency closure in TODO-45, then:

```powershell
git add pure-bonjour/cmake/VerifyInstalledPackage.cmake pure-bonjour/tests/package-mutations.cmake pure-bonjour/tests/relocation-ownership.cmake pure-bonjour/CMakeLists.txt pure/todo/TODO-45-windows-pure-bonjour.md
git commit -m "Verify PureBonjour package ownership"
```

---

### Task 7: Document the backend and add clean-runner CI

**Files:**
- Create: `pure-bonjour/WINDOWS.md`
- Create: `pure-bonjour/tests/ci-contract.cmake`
- Modify: `pure-bonjour/README`
- Modify: `pure-bonjour/CMakeLists.txt`
- Modify: `.github/workflows/non-linux-release-validation.yml`
- Modify: `pure/todo/TODO-45-windows-pure-bonjour.md`

**Interfaces:**
- Consumes: all build/test/install/verifier commands from Tasks 1-6.
- Produces: CTest `pure-bonjour-ci-contract`; GitHub job `windows-pure-bonjour`; artifact `windows-pure-bonjour`; user-facing Windows installation and diagnostics contract.

- [ ] **Step 1: Write the failing CI contract test**

Require workflow triggers for `pure-bonjour/**`, TODO-45, the design/plan, and the workflow itself. Require job name `Windows PureBonjour package`, runner `windows-2025`, CLANG64 prerequisite installation, configure/build from a checkout path containing spaces, `ctest -L bonjour`, component-only install, installed verifier with sanitized runtime, deterministic ZIP creation twice, equal SHA-256, and `actions/upload-artifact@v4` name `windows-pure-bonjour`.

Run the contract test and expect failure because the job is missing.

- [ ] **Step 2: Write Windows documentation**

`WINDOWS.md` must state Windows 10+ x86-64, CLANG64 build commands, `PureBonjour` component installation, installed file list, Microsoft `dnsapi.dll` backend, no Apple Bonjour requirement, local-link multicast/firewall implications, API/no-result/cancellation diagnostics, relocation/removal behavior, test commands, and license/source references. Update README's Installation and Usage sections and link `WINDOWS.md`; remove the obsolete claim that Windows requires a separately installed Bonjour service.

- [ ] **Step 3: Add the clean CI job**

Use the staged Pure SDK produced or downloaded by the workflow's established pattern. Configure with absolute `PURE_PREFIX`, build all targets, run `ctest -L bonjour --output-on-failure`, install only `PureBonjour` into a path containing spaces, remove `PURELIB` and all MSYS2 paths for runtime verification, invoke `VerifyInstalledPackage.cmake`, archive the exact stage twice in ordinal path order with stable timestamps, compare hashes, and upload one ZIP plus a concise hash/size summary.

- [ ] **Step 4: Run local contract and documentation checks**

Run:

```powershell
C:\msys64\clang64\bin\ctest.exe --test-dir build/pure-bonjour -R "^pure-bonjour-ci-contract$" --output-on-failure
rg -n "@version@|\|today\||Apple Bonjour.*required|TBD|FIXME" pure-bonjour/README pure-bonjour/WINDOWS.md
```

Expected: CI contract passes; source README contains only intentional template markers consumed by CMake; generated/staged README contains none; Windows docs contain no unresolved marker or external Apple requirement.

- [ ] **Step 5: Commit documentation and CI**

```powershell
git add pure-bonjour/WINDOWS.md pure-bonjour/tests/ci-contract.cmake pure-bonjour/README pure-bonjour/CMakeLists.txt .github/workflows/non-linux-release-validation.yml pure/todo/TODO-45-windows-pure-bonjour.md
git commit -m "Validate PureBonjour on clean Windows"
```

---

### Task 8: Run final validation and close TODO-45

**Files:**
- Modify: `pure/todo/TODO-45-windows-pure-bonjour.md`

**Interfaces:**
- Consumes: complete source, test, package, documentation, and CI contracts.
- Produces: closed TODO with exact local and clean-runner evidence plus final ship-or-defer decision.

- [ ] **Step 1: Start from a clean build directory and run the complete local suite**

Use a fresh directory, not `build/pure-bonjour`:

```powershell
C:\msys64\clang64\bin\cmake.exe -S pure-bonjour -B build/pure-bonjour-final -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_C_COMPILER=C:/msys64/clang64/bin/clang.exe -DPKG_CONFIG_EXECUTABLE=C:/msys64/clang64/bin/pkg-config.exe -DPURE_PREFIX=C:/pure-lang/pure/build/windows-clang64-prefix
C:\msys64\clang64\bin\cmake.exe --build build/pure-bonjour-final --verbose
C:\msys64\clang64\bin\ctest.exe --test-dir build/pure-bonjour-final -L bonjour --output-on-failure
C:\msys64\clang64\bin\cmake.exe --build build/pure-bonjour-final --target verify-windows-dependencies
```

Expected: warning-free build; every Bonjour-labeled test passes; recursive imports remain within policy.

- [ ] **Step 2: Stage and independently verify the final component**

```powershell
C:\msys64\clang64\bin\cmake.exe --install build/pure-bonjour-final --prefix "C:/pure-lang/build/PureBonjour final stage" --component PureBonjour
C:\msys64\clang64\bin\cmake.exe -DSTAGE_PREFIX="C:/pure-lang/build/PureBonjour final stage" -DSOURCE_PREFIX=C:/pure-lang/pure-bonjour -DBUILD_PREFIX=C:/pure-lang/build/pure-bonjour-final -DPURE_PREFIX=C:/pure-lang/pure/build/windows-clang64-prefix -P pure-bonjour/cmake/VerifyInstalledPackage.cmake
```

Expected: exact manifest/hash/import/prefix checks and sanitized installed smoke pass.

- [ ] **Step 3: Obtain and independently inspect the clean-runner artifact**

After the GitHub job succeeds, download the uploaded ZIP into a fresh path containing spaces and Unicode. Reject unsafe ZIP entries, extract, compare exact eight-file inventory and hashes, recursively inspect every PE file, and run the installed smoke with no MSYS2 directory on `PATH`. Record workflow/job/artifact URLs, archive size/SHA-256, inventory hash, test count/duration, and recursive PE count.

- [ ] **Step 4: Close the TODO only if every shipping condition passed**

Change all four checklist items to `[x]`, set `Status: Closed on 2026-08-18`, resolve the Open Questions section to the Microsoft Windows DNS-SD decision, add the installed manifest and runtime dependency summary, and append the exact final commands/outcomes. If any shipping condition failed, leave the TODO open or paused and record the reproducible blocker; do not mark partial success as shipped.

- [ ] **Step 5: Commit the final evidence**

```powershell
git add pure/todo/TODO-45-windows-pure-bonjour.md
git commit -m "Record final PureBonjour Windows evidence"
git status --short --branch
```

Expected: branch contains coherent milestone commits, TODO-45 is closed only on full success, and only pre-existing unrelated untracked build artifacts remain.
