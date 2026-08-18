# Windows pure-fastcgi Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build, test, and package the existing `pure-fastcgi` API on 64-bit Windows with a verified `fcgi2` 2.4.7 implementation statically linked into `fastcgi.dll`.

**Architecture:** CMake verifies and extracts one local, exactly hashed upstream archive, compiles the required `fcgi2` Windows sources into a private static target, and links that target into the Pure module. A non-installed Win32 harness exchanges real FastCGI records with a one-request Pure worker over a uniquely named pipe, while package scripts enforce the optional component, provenance, PE closure, relocation, and ownership contracts.

**Tech Stack:** CMake 3.25+, Ninja, C11, LLVM/Clang CLANG64, Pure 0.68+, `FastCGI-Archives/fcgi2` 2.4.7, Win32 named pipes and process APIs, GMP, MPFR, CTest, PowerShell, `llvm-readobj`.

## Global Constraints

- Target only 64-bit Windows in the CLANG64 Pure distribution.
- Pin `fcgi2` release `2.4.7`, commit `47f2c03b7771f0ef61d887734ef91e6fa747f837`.
- Accept only `https://github.com/FastCGI-Archives/fcgi2/archive/refs/tags/2.4.7.tar.gz`, size `263969`, SHA-256 `e41ddc3a473b555bdc0cbd80703dcb1f4610c1a7700d3b9d3d0c14a416e1074b`.
- Network acquisition is an explicit command; configure and rebuild never download.
- Statically link the required `fcgi2` code into `fastcgi.dll`; never install or load `libfcgi*.dll`.
- Preserve the public names and behavior in `pure-fastcgi/fastcgi.pure`.
- Automated protocol tests use a unique Windows named pipe, never a TCP listener or full web server.
- Every blocking process and pipe operation has a bounded timeout and process-scoped cleanup.
- Install only through the optional `PureFastCGI` component, excluded from the default install.
- Keep web-server-specific installation and configuration outside the component.
- Use test-driven development: each production change follows a test that was observed to fail for the intended reason.
- Preserve the unrelated untracked `build/` tree and all unrelated user changes.

## File Structure

- Create `pure-fastcgi/CMakeLists.txt`: top-level targets, feature checks, CTest registration, and inclusion of focused modules.
- Create `pure-fastcgi/cmake/Fcgi2Dependency.cmake`: immutable dependency constants, local archive verification/extraction, and private static target.
- Create `pure-fastcgi/cmake/FetchFcgi2.cmake`: explicit network-only fetch entry point with expected size and hash.
- Create `pure-fastcgi/cmake/Install.cmake`: optional-component payload, provenance, inventory, and manifest generation.
- Create `pure-fastcgi/cmake/RunProtocolTest.cmake`: launch wrapper that supplies a sanitized runtime and stable diagnostics.
- Create `pure-fastcgi/cmake/VerifyWindowsDependencies.cmake`: recursive PE import allowlist and static-FastCGI assertion.
- Create `pure-fastcgi/cmake/VerifyInstalledPackage.cmake`: exact inventory, relocation, prefix-leak, and installed runtime checks.
- Create `pure-fastcgi/tests/source-contract.cmake`: archive/hash/extraction mutation tests.
- Create `pure-fastcgi/tests/protocol_harness.c`: Win32 named-pipe process owner and FastCGI record client.
- Create `pure-fastcgi/tests/protocol_worker.pure`: one-request worker using only the public Pure API.
- Create `pure-fastcgi/tests/protocol_codec_test.c`: unit tests for record and name/value encoding and decoding.
- Create `pure-fastcgi/tests/protocol_failures.cmake`: truncated-request, timeout, and cleanup assertions.
- Create `pure-fastcgi/tests/install-component.cmake`: optional-selection and exact payload checks.
- Create `pure-fastcgi/tests/relocation-ownership.cmake`: relocated run, overlay, and removal preservation checks.
- Create `pure-fastcgi/THIRD_PARTY.md`: upstream identity, archive hash, licence, static-link, and patch provenance.
- Create `pure-fastcgi/WINDOWS.md`: reproducible fetch/build/test/stage commands and deployment boundary.
- Modify `pure-fastcgi/fastcgi.pure`: remove the MinGW-only dynamic `lib:fcgi` preload because FastCGI is embedded.
- Modify `pure-fastcgi/fastcgi.c`: use the exact upstream types on Windows and export only bridge entry points.
- Modify `pure-fastcgi/README`: document supported Windows component and point to `WINDOWS.md`.
- Modify `.github/workflows/non-linux-release-validation.yml`: add `pure-fastcgi/**` triggers and the clean CLANG64 package job.
- Modify `pure/todo/TODO-46-windows-pure-fastcgi.md`: record source, measurements, validation, and final ship/defer decision.

---

### Task 1: Immutable fcgi2 source contract

**Files:**
- Create: `pure-fastcgi/cmake/Fcgi2Dependency.cmake`
- Create: `pure-fastcgi/cmake/FetchFcgi2.cmake`
- Create: `pure-fastcgi/tests/source-contract.cmake`
- Create: `pure-fastcgi/CMakeLists.txt`

**Interfaces:**
- Consumes: cache path `PURE_FASTCGI_FCGI2_ARCHIVE` supplied by the caller.
- Produces: `pure_fastcgi_prepare_fcgi2(ARCHIVE absolute_archive OUT_SOURCE_DIR output_variable)`; immutable variables `PURE_FASTCGI_FCGI2_VERSION`, `PURE_FASTCGI_FCGI2_COMMIT`, `PURE_FASTCGI_FCGI2_ARCHIVE_SHA256`, and `PURE_FASTCGI_FCGI2_ARCHIVE_SIZE`.

- [ ] **Step 1: Write the failing source-contract test**

Create a test that includes `Fcgi2Dependency.cmake`, verifies the public constants, prepares the valid archive, copies and mutates one byte, and invokes a child CMake process that must reject the mutated copy:

```cmake
include("${SOURCE_DIR}/cmake/Fcgi2Dependency.cmake")
if(NOT PURE_FASTCGI_FCGI2_COMMIT STREQUAL
    "47f2c03b7771f0ef61d887734ef91e6fa747f837")
  message(FATAL_ERROR "unexpected fcgi2 commit")
endif()
pure_fastcgi_prepare_fcgi2(
  ARCHIVE "${FCGI2_ARCHIVE}"
  OUT_SOURCE_DIR extracted)
foreach(required IN ITEMS include/fcgi_stdio.h libfcgi/fcgi_stdio.c
    libfcgi/fcgiapp.c libfcgi/os_win32.c LICENSE)
  if(NOT EXISTS "${extracted}/${required}")
    message(FATAL_ERROR "missing extracted fcgi2 input: ${required}")
  endif()
endforeach()
file(READ "${FCGI2_ARCHIVE}" bytes HEX)
string(SUBSTRING "${bytes}" 2 -1 tail)
file(WRITE "${TEST_ROOT}/mutated.tar.gz" "00${tail}")
execute_process(
  COMMAND "${CMAKE_COMMAND}"
    -DSOURCE_DIR=${SOURCE_DIR}
    -DARCHIVE=${TEST_ROOT}/mutated.tar.gz
    -P "${SOURCE_DIR}/tests/verify-one-archive.cmake"
  RESULT_VARIABLE result ERROR_VARIABLE error)
if(result EQUAL 0 OR NOT error MATCHES "fcgi2 archive (size|SHA-256) mismatch")
  message(FATAL_ERROR "mutated fcgi2 archive was not rejected: ${error}")
endif()
```

Also create `pure-fastcgi/tests/verify-one-archive.cmake` as the child entry point that calls `pure_fastcgi_prepare_fcgi2`.

- [ ] **Step 2: Run the test and verify the missing contract fails**

Run:

```powershell
& C:/msys64/clang64/bin/cmake.exe `
  -DSOURCE_DIR=C:/pure-lang/pure-fastcgi `
  -DFCGI2_ARCHIVE=C:/pure-lang/tmp/fcgi2-2.4.7.tar.gz `
  '-DTEST_ROOT=C:/pure-lang/tmp/pure-fastcgi source contract' `
  -P C:/pure-lang/pure-fastcgi/tests/source-contract.cmake
```

Expected: failure because `Fcgi2Dependency.cmake` and `pure_fastcgi_prepare_fcgi2` do not exist.

- [ ] **Step 3: Implement verification, extraction, and explicit fetch**

Define the immutable contract and an argument-parsed function:

```cmake
set(PURE_FASTCGI_FCGI2_VERSION "2.4.7")
set(PURE_FASTCGI_FCGI2_COMMIT
  "47f2c03b7771f0ef61d887734ef91e6fa747f837")
set(PURE_FASTCGI_FCGI2_URL
  "https://github.com/FastCGI-Archives/fcgi2/archive/refs/tags/2.4.7.tar.gz")
set(PURE_FASTCGI_FCGI2_ARCHIVE_SIZE "263969")
set(PURE_FASTCGI_FCGI2_ARCHIVE_SHA256
  "e41ddc3a473b555bdc0cbd80703dcb1f4610c1a7700d3b9d3d0c14a416e1074b")

function(pure_fastcgi_prepare_fcgi2)
  cmake_parse_arguments(PARSE_ARGV 0 arg "" "ARCHIVE;OUT_SOURCE_DIR" "")
  if(NOT IS_ABSOLUTE "${arg_ARCHIVE}" OR NOT EXISTS "${arg_ARCHIVE}")
    message(FATAL_ERROR "PURE_FASTCGI_FCGI2_ARCHIVE must name an existing absolute file")
  endif()
  file(SIZE "${arg_ARCHIVE}" actual_size)
  file(SHA256 "${arg_ARCHIVE}" actual_sha256)
  if(NOT actual_size EQUAL PURE_FASTCGI_FCGI2_ARCHIVE_SIZE)
    message(FATAL_ERROR "fcgi2 archive size mismatch")
  endif()
  if(NOT actual_sha256 STREQUAL PURE_FASTCGI_FCGI2_ARCHIVE_SHA256)
    message(FATAL_ERROR "fcgi2 archive SHA-256 mismatch")
  endif()
  set(root "${CMAKE_CURRENT_BINARY_DIR}/_deps/fcgi2-2.4.7")
  file(REMOVE_RECURSE "${root}")
  file(MAKE_DIRECTORY "${root}")
  file(ARCHIVE_EXTRACT INPUT "${arg_ARCHIVE}" DESTINATION "${root}")
  set(source "${root}/fcgi2-2.4.7")
  set(${arg_OUT_SOURCE_DIR} "${source}" PARENT_SCOPE)
endfunction()
```

`FetchFcgi2.cmake` must require absolute `OUTPUT`, refuse to overwrite a mismatching existing file, download to `OUTPUT.part` with `EXPECTED_HASH`, verify size, and rename only after success. Configure must never include this script automatically.

- [ ] **Step 4: Register and run the passing contract test**

In `CMakeLists.txt`, require Windows, CMake 3.25, C, the absolute archive cache variable, and register `pure-fastcgi-source-contract` with label `fastcgi;source;contract` and timeout 30 seconds. Re-run the command from Step 2 and then:

```powershell
& C:/msys64/clang64/bin/ctest.exe --test-dir 'C:/pure-lang/build/pure-fastcgi' `
  -R pure-fastcgi-source-contract --output-on-failure
```

Expected: PASS; direct configure without `PURE_FASTCGI_FCGI2_ARCHIVE` fails without network access.

- [ ] **Step 5: Commit the source contract**

```powershell
git add pure-fastcgi/CMakeLists.txt pure-fastcgi/cmake/Fcgi2Dependency.cmake pure-fastcgi/cmake/FetchFcgi2.cmake pure-fastcgi/tests/source-contract.cmake pure-fastcgi/tests/verify-one-archive.cmake
git commit -m "Pin the pure-fastcgi upstream source"
```

### Task 2: Private static fcgi2 target and Pure module

**Files:**
- Modify: `pure-fastcgi/cmake/Fcgi2Dependency.cmake`
- Modify: `pure-fastcgi/CMakeLists.txt`
- Modify: `pure-fastcgi/fastcgi.pure:13-17`
- Modify: `pure-fastcgi/fastcgi.c`
- Create: `pure-fastcgi/cmake/VerifyWindowsDependencies.cmake`

**Interfaces:**
- Consumes: verified source directory from `pure_fastcgi_prepare_fcgi2` and pkg-config targets `PkgConfig::PURE`, `PkgConfig::GMP`, `PkgConfig::MPFR`.
- Produces: private `fcgi2-static`, module target `pure-fastcgi` with output name `fastcgi`, and target `verify-windows-dependencies`.

- [ ] **Step 1: Write a failing static-closure verifier**

Implement the test script first. It runs `llvm-readobj --coff-imports` on the module, lowercases imported names, and rejects any name matching `(^|/)lib?fcgi.*\.dll$`. It also runs `llvm-nm --defined-only` and requires `FCGI_Accept`, `FCGI_Finish`, `fastcgi_defs`, and `fastcgi_to_file`:

```cmake
execute_process(COMMAND "${LLVM_READOBJ}" --coff-imports "${MODULE}"
  RESULT_VARIABLE read_result OUTPUT_VARIABLE imports ERROR_VARIABLE read_error)
if(NOT read_result EQUAL 0)
  message(FATAL_ERROR "llvm-readobj failed: ${read_error}")
endif()
string(TOLOWER "${imports}" imports_lower)
if(imports_lower MATCHES "lib?fcgi[^\r\n]*\\.dll")
  message(FATAL_ERROR "dynamic FastCGI dependency is forbidden")
endif()
```

- [ ] **Step 2: Run the verifier and observe the missing module failure**

Run the configured verifier target.

```powershell
& C:/msys64/clang64/bin/cmake.exe --build 'C:/pure-lang/build/pure-fastcgi' `
  --target verify-windows-dependencies
```

Expected: failure because neither the static target nor `fastcgi.dll` exists.

- [ ] **Step 3: Add the static library and module targets**

Extend `pure_fastcgi_prepare_fcgi2` or add `pure_fastcgi_add_fcgi2_target(SOURCE_DIR <dir>)` with these exact source inputs:

```cmake
add_library(fcgi2-static STATIC
  "${source}/libfcgi/fcgi_stdio.c"
  "${source}/libfcgi/fcgiapp.c"
  "${source}/libfcgi/os_win32.c")
target_include_directories(fcgi2-static PUBLIC "${source}/include")
target_compile_definitions(fcgi2-static PRIVATE DLLAPI=)
target_compile_features(fcgi2-static PRIVATE c_std_11)
target_link_libraries(fcgi2-static PUBLIC ws2_32)
```

Keep the project C-only; the C++ convenience wrapper `fcgio.cpp` is outside
the `fcgi_stdio` bridge contract and must not be compiled. Build the module as:

```cmake
add_library(pure-fastcgi MODULE fastcgi.c fastcgi_extra.c)
set_target_properties(pure-fastcgi PROPERTIES
  OUTPUT_NAME fastcgi PREFIX "" WINDOWS_EXPORT_ALL_SYMBOLS ON)
target_compile_features(pure-fastcgi PRIVATE c_std_11)
target_compile_definitions(pure-fastcgi PRIVATE NO_FCGI_DEFINES)
target_link_libraries(pure-fastcgi PRIVATE fcgi2-static
  PkgConfig::PURE PkgConfig::GMP PkgConfig::MPFR)
```

Do not define `NO_FCGI_DEFINES` globally if it prevents `fastcgi.c` from receiving the `FCGI_FILE` stdio mappings; apply it only where the existing source already requests it. Remove the MinGW block that says `using "lib:fcgi";` from `fastcgi.pure`. Keep `using "lib:fastcgi";` unchanged.

- [ ] **Step 4: Build and verify the static closure**

```powershell
& C:/msys64/clang64/bin/cmake.exe --build 'C:/pure-lang/build/pure-fastcgi'
& C:/msys64/clang64/bin/cmake.exe --build 'C:/pure-lang/build/pure-fastcgi' `
  --target verify-windows-dependencies
```

Expected: both commands succeed; `fastcgi.dll` exports the bridge and required upstream API, and imports no FastCGI DLL.

- [ ] **Step 5: Commit the static module**

```powershell
git add pure-fastcgi/CMakeLists.txt pure-fastcgi/cmake/Fcgi2Dependency.cmake pure-fastcgi/cmake/VerifyWindowsDependencies.cmake pure-fastcgi/fastcgi.c pure-fastcgi/fastcgi.pure
git commit -m "Build pure-fastcgi with embedded fcgi2"
```

### Task 3: FastCGI codec and named-pipe success path

**Files:**
- Create: `pure-fastcgi/tests/protocol_harness.c`
- Create: `pure-fastcgi/tests/protocol_codec_test.c`
- Create: `pure-fastcgi/tests/protocol_worker.pure`
- Create: `pure-fastcgi/cmake/RunProtocolTest.cmake`
- Modify: `pure-fastcgi/CMakeLists.txt`

**Interfaces:**
- Consumes: built `fastcgi.dll`, source `fastcgi.pure`, installed `pure.exe`, and Pure runtime directory.
- Produces: executable `pure-fastcgi-protocol-harness`; codec functions `fcgi_write_record`, `fcgi_write_name_value`, `fcgi_read_record`; CTest `pure-fastcgi-protocol-smoke`.

- [ ] **Step 1: Write failing codec tests**

The codec test includes the harness implementation with `PURE_FASTCGI_CODEC_TEST` and asserts exact bytes for an eight-byte header, one-byte and four-byte name/value lengths, padding to an eight-byte boundary, and rejection of wrong version or request id:

```c
static void test_begin_request_header(void) {
  unsigned char out[16] = {0};
  size_t used = fcgi_encode_record(out, sizeof out, 1, FCGI_BEGIN_REQUEST,
                                   7, "\0\1\0\0\0\0\0\0", 8);
  const unsigned char expected[16] = {
    1, FCGI_BEGIN_REQUEST, 0, 7, 0, 8, 0, 0,
    0, 1, 0, 0, 0, 0, 0, 0};
  assert(used == sizeof expected);
  assert(memcmp(out, expected, sizeof expected) == 0);
}
```

- [ ] **Step 2: Compile the codec test and verify undefined functions fail**

```powershell
& C:/msys64/clang64/bin/cmake.exe --build 'C:/pure-lang/build/pure-fastcgi' `
  --target pure-fastcgi-protocol-codec-test
```

Expected: compile or link failure because the codec functions are not defined.

- [ ] **Step 3: Implement the minimal bounded codec**

Use fixed-width integers and explicit big-endian conversion. Reject content lengths above 65535, output buffer overflow, non-v1 records, unexpected request ids, and truncated content or padding. All read/write helpers accept a deadline in monotonic milliseconds and return a typed enum:

```c
enum fcgi_io_result { FCGI_IO_OK, FCGI_IO_TIMEOUT, FCGI_IO_EOF,
                      FCGI_IO_PROTOCOL, FCGI_IO_SYSTEM };
size_t fcgi_encode_record(unsigned char *out, size_t capacity,
  uint8_t version, uint8_t type, uint16_t request_id,
  const void *content, uint16_t content_len);
enum fcgi_io_result fcgi_write_record(HANDLE pipe, uint8_t type,
  uint16_t request_id, const void *content, uint16_t content_len,
  uint64_t deadline_ms);
enum fcgi_io_result fcgi_read_record(HANDLE pipe, struct fcgi_record *record,
  uint64_t deadline_ms);
```

- [ ] **Step 4: Run codec tests and observe PASS**

```powershell
& C:/msys64/clang64/bin/ctest.exe --test-dir 'C:/pure-lang/build/pure-fastcgi' `
  -R pure-fastcgi-protocol-codec --output-on-failure
```

Expected: PASS.

- [ ] **Step 5: Write the one-request Pure worker and failing integration test**

The worker must use only public module operations and emit deterministic markers:

```pure
using fastcgi;
using namespace fastcgi;

if accept >= 0 then
  body = fget stdin;
  fprintf stdout "Status: 201 Created\r\nContent-Type: text/plain\r\n\r\nmethod=%s;query=%s;body=%s\n"
    (getenv "REQUEST_METHOD", getenv "QUERY_STRING", body);
  fprintf stderr "pure-fastcgi-stderr-marker\n";
  set_exit_status 23;
  finish;
  finish;
endif;
```

Register the smoke test through `RunProtocolTest.cmake`, passing absolute paths and a 20-second CTest timeout. Run it before implementing Win32 process ownership; expected failure is “named-pipe launcher not implemented”.

- [ ] **Step 6: Implement the success-path launcher**

The harness must:

- create `\\.\pipe\FastCGI\pure-fastcgi-<pid>-<counter>` with `CreateNamedPipeW`;
- build a quoted UTF-16 command line for `pure.exe -L <module-dir> <worker.pure>`;
- pass only the named-pipe server handle as inheritable stdin and use `STARTUPINFOEXW` plus `PROC_THREAD_ATTRIBUTE_HANDLE_LIST`;
- make stdout/stderr invalid in the child so upstream detects FastCGI listener mode;
- connect the client endpoint with `CreateFileW`;
- send request id 1 with role `FCGI_RESPONDER`, `REQUEST_METHOD=POST`, `QUERY_STRING=value%20with%20spaces`, `CONTENT_LENGTH=12`, and body `hello=world!`;
- send empty terminators for `PARAMS` and `STDIN`;
- accumulate `STDOUT` and `STDERR` with explicit size ceilings of 64 KiB each;
- require one `END_REQUEST` with application status 23 and protocol status `FCGI_REQUEST_COMPLETE`;
- require normal worker exit and close every owned handle on all exits.

`RunProtocolTest.cmake` sets `PATH` to the module/Pure runtime plus Windows system directories, unsets `PURELIB`, runs the harness, and requires the marker `pure-fastcgi protocol smoke passed`.

- [ ] **Step 7: Run the success-path test**

```powershell
& C:/msys64/clang64/bin/ctest.exe --test-dir 'C:/pure-lang/build/pure-fastcgi' `
  -R 'pure-fastcgi-protocol-(codec|smoke)' --output-on-failure
```

Expected: 2/2 tests pass and no TCP listener is created.

- [ ] **Step 8: Commit the protocol success path**

```powershell
git add pure-fastcgi/CMakeLists.txt pure-fastcgi/cmake/RunProtocolTest.cmake pure-fastcgi/tests/protocol_harness.c pure-fastcgi/tests/protocol_codec_test.c pure-fastcgi/tests/protocol_worker.pure
git commit -m "Test pure-fastcgi over a Windows named pipe"
```

### Task 4: Protocol failures and lifecycle cleanup

**Files:**
- Modify: `pure-fastcgi/tests/protocol_harness.c`
- Create: `pure-fastcgi/tests/protocol_failures.cmake`
- Create: `pure-fastcgi/tests/protocol_worker_hang.pure`
- Modify: `pure-fastcgi/CMakeLists.txt`

**Interfaces:**
- Consumes: harness option `--scenario <success|truncated|timeout>` and `--cleanup-report <absolute-path>`.
- Produces: deterministic cleanup report fields `child_pid`, `child_exited`, `pipe_closed`, `owned_handles_closed`; CTest `pure-fastcgi-protocol-failures`.

- [ ] **Step 1: Write failing failure-path tests**

Run the harness twice from CMake. The truncated case sends a partial `PARAMS` record and closes the client. The timeout case runs a worker that accepts but never finishes. Require nonzero harness status, the stable category, elapsed time below 10 seconds, and a cleanup report proving the owned child exited and pipe closed:

```cmake
function(expect_failure scenario expected)
  execute_process(COMMAND "${HARNESS}" --scenario "${scenario}"
      --cleanup-report "${TEST_ROOT}/${scenario}.txt"
    RESULT_VARIABLE result OUTPUT_VARIABLE out ERROR_VARIABLE err
    TIMEOUT 12)
  if(result EQUAL 0 OR NOT "${out}\n${err}" MATCHES "${expected}")
    message(FATAL_ERROR "${scenario} did not fail as ${expected}")
  endif()
  file(READ "${TEST_ROOT}/${scenario}.txt" cleanup)
  foreach(marker IN ITEMS "child_exited=1" "pipe_closed=1"
      "owned_handles_closed=1")
    if(NOT cleanup MATCHES "${marker}")
      message(FATAL_ERROR "${scenario} cleanup missing ${marker}")
    endif()
  endforeach()
endfunction()
expect_failure(truncated "protocol error while reading PARAMS")
expect_failure(timeout "deadline expired while waiting for END_REQUEST")
```

- [ ] **Step 2: Run and verify scenarios are not implemented**

Run `ctest -R pure-fastcgi-protocol-failures --output-on-failure`.

Expected: FAIL because the harness accepts only the success path and writes no cleanup report.

- [ ] **Step 3: Implement process-scoped failure cleanup**

Add one cleanup block used by every exit. It closes the client endpoint, cancels pipe I/O with `CancelIoEx`, closes the server endpoint, waits up to two seconds for the owned process, calls `TerminateProcess(child, 124)` only if that wait expires, waits again, and then closes thread, process, job, attribute-list, and event resources. Put the child in a kill-on-close job object so harness termination cannot orphan it. Never enumerate or kill processes by name.

- [ ] **Step 4: Run all protocol tests**

```powershell
& C:/msys64/clang64/bin/ctest.exe --test-dir 'C:/pure-lang/build/pure-fastcgi' `
  -L fastcgi --output-on-failure
```

Expected: source, codec, success, and failure tests all pass; the timeout scenario completes within 12 seconds.

- [ ] **Step 5: Commit lifecycle handling**

```powershell
git add pure-fastcgi/CMakeLists.txt pure-fastcgi/tests/protocol_harness.c pure-fastcgi/tests/protocol_failures.cmake pure-fastcgi/tests/protocol_worker_hang.pure
git commit -m "Bound pure-fastcgi failure cleanup"
```

### Task 5: Optional component, provenance, and exact package verifier

**Files:**
- Create: `pure-fastcgi/cmake/Install.cmake`
- Create: `pure-fastcgi/cmake/VerifyInstalledPackage.cmake`
- Create: `pure-fastcgi/tests/install-component.cmake`
- Create: `pure-fastcgi/THIRD_PARTY.md`
- Modify: `pure-fastcgi/CMakeLists.txt`

**Interfaces:**
- Consumes: module, Pure source, README, `THIRD_PARTY.md`, upstream `LICENSE`, verified source constants, and `llvm-readobj`.
- Produces: optional `PureFastCGI` component, build oracles `PureFastCGIExpected.sha256` and `PureFastCGIInventory.tsv`, installed `share/doc/pure-fastcgi/PureFastCGIInventory.tsv`.

- [ ] **Step 1: Write the failing component-selection test**

The test installs the default selection into one empty prefix and requires no files, installs `--component PureFastCGI` into another, checks the required paths, rejects any `libfcgi*.dll`, and validates every manifest hash:

```cmake
execute_process(COMMAND "${CMAKE_COMMAND}" --install "${BUILD_DIR}"
  --prefix "${DEFAULT_STAGE}" RESULT_VARIABLE default_result)
file(GLOB_RECURSE default_files LIST_DIRECTORIES false "${DEFAULT_STAGE}/*")
if(default_files)
  message(FATAL_ERROR "PureFastCGI leaked into default install")
endif()
execute_process(COMMAND "${CMAKE_COMMAND}" --install "${BUILD_DIR}"
  --prefix "${STAGE}" --component PureFastCGI RESULT_VARIABLE install_result)
foreach(required IN ITEMS lib/pure/fastcgi.dll lib/pure/fastcgi.pure
    share/doc/pure-fastcgi/README share/doc/pure-fastcgi/THIRD_PARTY.md
    share/doc/pure-fastcgi/LICENSE.fcgi2
    share/doc/pure-fastcgi/PureFastCGIInventory.tsv)
  if(NOT EXISTS "${STAGE}/${required}")
    message(FATAL_ERROR "missing PureFastCGI payload: ${required}")
  endif()
endforeach()
file(GLOB_RECURSE forbidden "${STAGE}/*fcgi*.dll")
list(FILTER forbidden EXCLUDE REGEX "/fastcgi\\.dll$")
if(forbidden)
  message(FATAL_ERROR "separate FastCGI DLL installed: ${forbidden}")
endif()
```

- [ ] **Step 2: Run and verify the missing install contract fails**

Run `ctest -R pure-fastcgi-install-component --output-on-failure`.

Expected: FAIL because component install rules and inventory do not exist.

- [ ] **Step 3: Implement authoritative package generation**

Generate rows in ordinal relative-path order with six tab-separated fields:

```text
relative_path<TAB>purpose<TAB>origin<TAB>version_or_commit<TAB>sha256<TAB>size
```

Install `fastcgi.dll`, `fastcgi.pure`, `README`, `THIRD_PARTY.md`, the verbatim upstream licence as `LICENSE.fcgi2`, and the generated inventory. Generate the authoritative SHA manifest before tests. Use `install(... COMPONENT PureFastCGI EXCLUDE_FROM_ALL)` for every payload. `THIRD_PARTY.md` records URL, release, full commit, archive size/hash, embedded source files, static linkage, licence obligations, and an empty patch set until a checksum-covered patch is actually added.

- [ ] **Step 4: Implement recursive PE and inventory verification**

The verifier must:

- compare the exact staged relative-file set to `PureFastCGIExpected.sha256`;
- reject malformed, duplicate, case-colliding, absolute, or parent-traversing inventory paths;
- check all installed sizes and SHA-256 values;
- parse `llvm-readobj --coff-imports` recursively;
- require component-owned imports to resolve within the stage and declared
  Pure/GMP/MPFR/compiler-runtime imports to resolve beneath an explicit,
  separately supplied `PURE_RUNTIME_ROOT`;
- reject any imported or installed `libfcgi*.dll` other than the module name `fastcgi.dll`;
- reject source, build, and stage prefixes in installed text and binary strings;
- run the protocol smoke with sanitized `PATH` when `RUN_RUNTIME_TESTS=ON`.

- [ ] **Step 5: Run component and mutation checks**

Add mutations for a changed module byte, undeclared file, deleted licence, forged inventory hash, case-colliding path, and synthetic `libfcgi.dll`. Each must fail with its stable category. Run:

```powershell
& C:/msys64/clang64/bin/ctest.exe --test-dir 'C:/pure-lang/build/pure-fastcgi' `
  -R 'pure-fastcgi-(install|package)' --output-on-failure
```

Expected: the valid component passes and all mutations are rejected.

- [ ] **Step 6: Commit packaging and provenance**

```powershell
git add pure-fastcgi/CMakeLists.txt pure-fastcgi/cmake/Install.cmake pure-fastcgi/cmake/VerifyInstalledPackage.cmake pure-fastcgi/tests/install-component.cmake pure-fastcgi/THIRD_PARTY.md
git commit -m "Package PureFastCGI as an optional component"
```

### Task 6: Relocation, overlay, and removal ownership

**Files:**
- Create: `pure-fastcgi/tests/relocation-ownership.cmake`
- Modify: `pure-fastcgi/cmake/VerifyInstalledPackage.cmake`
- Modify: `pure-fastcgi/CMakeLists.txt`

**Interfaces:**
- Consumes: exact authoritative manifests and the installed verifier from Task 5.
- Produces: CTest `pure-fastcgi-relocation-ownership` and removal mode `REMOVE_OWNED=ON` in the verifier.

- [ ] **Step 1: Write the failing relocation and ownership test**

The test creates a stage with spaces, installs the component, adds two unrelated sentinels, hashes all files, copies the stage to `relocated 日本語 PureFastCGI`, runs the protocol smoke there, overlays the component in the original stage, removes only inventory-owned files, and requires both sentinels unchanged:

```cmake
file(WRITE "${stage}/unrelated-sentinel.txt" "keep\n")
file(WRITE "${stage}/lib/pure/unrelated-module.pure" "keep-module\n")
file(SHA256 "${stage}/unrelated-sentinel.txt" sentinel_before)
file(COPY "${stage}/" DESTINATION "${relocated}")
execute_process(COMMAND "${CMAKE_COMMAND}"
  -DBUILD_DIR=${BUILD_DIR} -DSTAGE_PREFIX=${relocated}
  -DRUN_RUNTIME_TESTS=ON -P "${VERIFY_SCRIPT}"
  RESULT_VARIABLE relocated_result)
if(NOT relocated_result EQUAL 0)
  message(FATAL_ERROR "relocated PureFastCGI verification failed")
endif()
```

- [ ] **Step 2: Run and observe removal/relocation support fail**

Run `ctest -R pure-fastcgi-relocation-ownership --output-on-failure`.

Expected: FAIL because removal mode and relocated runtime invocation are absent.

- [ ] **Step 3: Implement exact removal and relocated runtime setup**

Removal reads only the trusted external ownership inventory, validates every path remains below the stage, removes owned files with `file(REMOVE)`, and removes an owned directory only when empty. It must never recursively remove `lib`, `lib/pure`, `share`, or `share/doc`. The relocated runtime uses only relocated module/doc paths, the matching Pure prefix, and Windows system directories.

- [ ] **Step 4: Run the complete local suite**

```powershell
& C:/msys64/clang64/bin/ctest.exe --test-dir 'C:/pure-lang/build/pure-fastcgi' `
  -L fastcgi --output-on-failure
& C:/msys64/clang64/bin/cmake.exe --build 'C:/pure-lang/build/pure-fastcgi' `
  --target verify-windows-dependencies
git diff --check
```

Expected: all FastCGI tests pass, dependency verification passes, and diff check is clean.

- [ ] **Step 5: Commit relocation and ownership**

```powershell
git add pure-fastcgi/CMakeLists.txt pure-fastcgi/cmake/VerifyInstalledPackage.cmake pure-fastcgi/tests/relocation-ownership.cmake
git commit -m "Verify PureFastCGI relocation and ownership"
```

### Task 7: Reproducible documentation and clean Windows CI

**Files:**
- Create: `pure-fastcgi/WINDOWS.md`
- Modify: `pure-fastcgi/README`
- Modify: `.github/workflows/non-linux-release-validation.yml`
- Modify: `pure/todo/TODO-46-windows-pure-fastcgi.md`

**Interfaces:**
- Consumes: exact fetch/build/test/install commands and generated package metrics.
- Produces: job `windows-pure-fastcgi`, artifact `windows-pure-fastcgi.zip`, stable `PureFastCGI` handoff contract for TODO-49, and the final ship/defer record.

- [ ] **Step 1: Add a failing static CI contract test**

Create `pure-fastcgi/tests/ci-contract.cmake` that reads the workflow and requires the path trigger, job name, exact URL/hash/commit, explicit fetch step, CLANG64 configure/build, `ctest -L fastcgi`, component-only install, installed verifier, deterministic archive, and artifact upload. Register it before editing the workflow.

```cmake
file(READ "${WORKFLOW}" workflow)
foreach(required IN ITEMS
    "pure-fastcgi/**" "windows-pure-fastcgi:" "PureFastCGI"
    "e41ddc3a473b555bdc0cbd80703dcb1f4610c1a7700d3b9d3d0c14a416e1074b"
    "ctest.exe --test-dir" "-L fastcgi" "windows-pure-fastcgi.zip")
  string(FIND "${workflow}" "${required}" position)
  if(position EQUAL -1)
    message(FATAL_ERROR "workflow is missing PureFastCGI contract: ${required}")
  endif()
endforeach()
```

- [ ] **Step 2: Run and verify the workflow contract fails**

Run `ctest -R pure-fastcgi-ci-contract --output-on-failure`.

Expected: FAIL because no FastCGI job or trigger exists.

- [ ] **Step 3: Add the clean CLANG64 job**

The job checks out into `source with spaces`, installs only the Pure build prerequisites already used by the workflow, builds and installs the matching Pure runtime, invokes `FetchFcgi2.cmake` explicitly, configures `pure-fastcgi` with the absolute archive path, builds, runs `ctest -L fastcgi`, stages only `PureFastCGI`, verifies with sanitized `PATH`, and records:

- source URL, release, commit, archive size and hash;
- compiler, CMake, Ninja, pkg-config, GMP, and MPFR versions;
- build elapsed seconds and worker count;
- module and stage sizes, staged file count, inventory hash;
- complete recursive PE imports;
- deterministic ZIP size and SHA-256.

Create the ZIP with ordinal forward-slash paths and fixed UTC timestamp `2000-01-01T00:00:00Z`; create it twice and require identical hashes before upload.

- [ ] **Step 4: Document the supported build and deployment boundary**

`WINDOWS.md` contains copyable PowerShell commands for explicit fetch, configure, build, focused tests, component staging, and installed verification. It states that IIS/Apache/nginx setup is not installed or validated and that deployment must provide a compatible FastCGI listener. Update `README` with a Windows section pointing to this document.

- [ ] **Step 5: Run all local static and functional checks**

```powershell
& C:/msys64/clang64/bin/ctest.exe --test-dir 'C:/pure-lang/build/pure-fastcgi' `
  -L fastcgi --output-on-failure
git diff --check
git status --short
```

Expected: all tests pass; only intended files plus the pre-existing untracked `build/` appear.

- [ ] **Step 6: Commit CI and documentation**

```powershell
git add .github/workflows/non-linux-release-validation.yml pure-fastcgi/CMakeLists.txt pure-fastcgi/tests/ci-contract.cmake pure-fastcgi/WINDOWS.md pure-fastcgi/README
git commit -m "Validate PureFastCGI on clean Windows"
```

- [ ] **Step 7: Run and inspect the clean Windows job**

Push the task branch only after normal publication approval. Require the `Windows PureFastCGI package` job itself to complete successfully, even if unrelated matrix jobs fail. Download the artifact, verify both GitHub wrapper and inner deterministic ZIP hashes, safely extract into a fresh path with spaces, reconstruct the file/hash oracle independently, and repeat protocol, relocation, and structural verification without MSYS2 on runtime `PATH`.

- [ ] **Step 8: Record the evidence and final decision**

If every shipping criterion passes, set TODO-46 to closed, check all four task-list entries, record exact workflow/job/artifact links, commit SHA, metrics, inventory/file counts and hashes, and state that TODO-49 may consume only optional component `PureFastCGI`. If a criterion fails, leave the TODO open or mark it deferred with the exact reproducible failure and do not advertise or stage the component.

- [ ] **Step 9: Commit the evidence-only closure**

```powershell
git add pure/todo/TODO-46-windows-pure-fastcgi.md
git commit -m "Record the Windows pure-fastcgi decision"
```

### Task 8: Final verification and review handoff

**Files:**
- Review: all files changed by Tasks 1-7

**Interfaces:**
- Consumes: implementation commits, clean-runner evidence, and downloaded artifact verification.
- Produces: a review-ready branch with no unverified success claims.

- [ ] **Step 1: Run the complete verification from a clean local build directory**

Configure with the exact archive, build, run the full `fastcgi` label, stage the component, and run the installed verifier. Capture command output and ensure every expected test count and package metric matches the TODO evidence.

- [ ] **Step 2: Audit the final diff and history**

```powershell
$base = (git merge-base HEAD master).Trim()
git diff --check "$base..HEAD"
git diff --stat "$base..HEAD"
git log --oneline -10
git status --short
```

Expected: no whitespace errors, focused commits, and only the pre-existing untracked `build/` outside committed scope.

- [ ] **Step 3: Request code review**

Use `superpowers:requesting-code-review`. Resolve every correctness, security, lifecycle, provenance, or packaging finding before claiming completion. Re-run the focused tests after each fix and the full suite after the final fix.

- [ ] **Step 4: Apply completion verification**

Use `superpowers:verification-before-completion` and cite fresh outputs for the local full suite, clean Windows job, artifact hashes, installed verifier, relocation test, and final `git status`. Do not mark TODO-46 closed unless all ship criteria have current evidence.
