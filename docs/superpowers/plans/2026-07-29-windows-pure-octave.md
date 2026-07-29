# Windows pure-octave Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use
> superpowers:subagent-driven-development (recommended) or
> superpowers:executing-plans to implement this plan task-by-task. Steps use
> checkbox (`- [ ]`) syntax for tracking.

**Goal:** Preserve the full in-process `pure-octave` API on portable Windows
with one exactly supported Octave distribution and an optional managed runtime.

**Architecture:** A C-only `octave_embed.dll` selects and validates an explicit
Octave root, restricts Windows DLL lookup, loads an ABI-specific
`octave_bridge_impl.dll`, and delegates the existing Pure-facing C API. The
implementation embeds one Octave 11.3.0 interpreter and keeps all Octave C++
objects, allocation, and exceptions behind that C boundary.

**Tech Stack:** Pure, C11, C++17, Win32 loader APIs, GNU Octave 11.3.0 x86-64
Windows distribution, Octave `mkoctfile`, CMake 3.25+, Ninja, CTest, PowerShell
5.1, GnuPG signature verification, LLVM PE inspection.

## Global Constraints

- The candidate is the official standard-index Windows x86-64 GNU Octave
  11.3.0 distribution.
- Candidate archive:
  `https://ftpmirror.gnu.org/octave/windows/octave-11.3.0-w64.7z`.
- Candidate signature:
  `https://ftpmirror.gnu.org/octave/windows/octave-11.3.0-w64.7z.sig`.
- Required upstream signing key ID: `B05F05B75D36644B`. Accept the archive
  only when GnuPG reports a valid detached signature whose primary-key
  fingerprint ends in this published ID; record the complete fingerprint
  reported by GnuPG before freezing the artifact.
- If the 7z extraction probe fails, use the official
  `octave-11.3.0-w64.zip` plus its matching signature; do not introduce an
  unrelated extractor into the end-user dependency closure.
- Do not permanently install the candidate before the compilation and initial
  ABI gates pass.
- The authorized permanent development root is
  `C:\Tools\GNU Octave\11.3.0`; installation is side-by-side.
- Support exactly one pinned Octave version, distribution identity,
  architecture, and C++ ABI at a time.
- Preserve `octave_eval`, `octave_get`, `octave_set`, `octave_call`,
  `octave_func`, `octave_valuep`, converters, and `pure_call`.
- Never find Octave or any dependency implicitly through host `PATH`.
- Never modify or remove an unsupported external Octave installation.
- The managed runtime installs only when
  `PURE_OCTAVE_INSTALL_RUNTIME=ON`, below `tools/octave`.
- No C++ object, allocator ownership, standard-library type, or exception may
  cross the loader/implementation or Pure/Octave C ABI.
- Stop and record evidence if the official GCC runtime cannot safely coexist
  with the portable Clang/libc++ Pure runtime.
- Use `C:\tmp\Relocated Pure Gplot Final Bundle 20260729` as the verified
  portable Pure base for local staging.
- Commit after every independently verified task.

---

## File Map

- `pure-octave/CMakeLists.txt`: build targets, options, and CTest registration.
- `pure-octave/cmake/AcquireWindowsOctave.cmake`: official download, signature
  verification, controlled extraction, and root validation.
- `pure-octave/cmake/OctaveToolchain.cmake`: locate `mkoctfile`, compiler,
  include, library, binary, module, and data paths inside one explicit root.
- `pure-octave/cmake/RunEmbedProbe.cmake`: sanitized public-API embedding probe.
- `pure-octave/probes/embed_probe.cc`: documented Octave embedding API probe.
- `pure-octave/octave_loader.c`: stable Pure-facing loader and root resolver.
- `pure-octave/octave_bridge_api.h`: shared C ABI and implementation function
  table.
- `pure-octave/embed.cc`: Octave 11.3 implementation, conversions, callback,
  recovery, and lifecycle.
- `pure-octave/embed.h`: implementation declarations using the shared C ABI.
- `pure-octave/octave.pure`: initialization diagnostics and existing Pure API.
- `pure-octave/tests/*.pure`: basic, conversions, callbacks, errors, lifecycle,
  and missing/incompatible runtime contracts.
- `pure-octave/cmake/RunPureTest.cmake`: sanitized Pure test runner.
- `pure-octave/cmake/VerifyWindowsDependencies.cmake`: PE import closure audit.
- `pure-octave/tools/DetectWindowsOctave.ps1`: machine-readable external-root
  detector for TODO-49.
- `pure-octave/cmake/Install.cmake`: binding, documentation, and optional
  managed runtime installation.
- `pure-octave/cmake/VerifyInstalledPackage.cmake`: staged and relocated
  installed-package verifier.
- `pure-octave/WINDOWS.md`: supported distribution, installation choices,
  diagnostics, size, relocation, and removal.
- `.github/workflows/pure-octave-windows.yml`: cached clean Windows validation.

---

### Task 1: Acquire and prove the Octave 11.3 public embedding toolchain

**Files:**
- Create: `pure-octave/CMakeLists.txt`
- Create: `pure-octave/cmake/AcquireWindowsOctave.cmake`
- Create: `pure-octave/cmake/OctaveToolchain.cmake`
- Create: `pure-octave/cmake/RunEmbedProbe.cmake`
- Create: `pure-octave/probes/embed_probe.cc`
- Modify: `pure/todo/TODO-43-windows-pure-octave.md`

**Interfaces:**
- Consumes: `OCTAVE_ROOT`, `PURE_PREFIX`, `GPG_EXECUTABLE`.
- Produces: validated cache values `OCTAVE_EXECUTABLE`,
  `OCTAVE_MKOCTFILE`, `OCTAVE_RUNTIME_DIR`, `OCTAVE_MODULE_DIR`,
  `OCTAVE_SHARE_DIR`, `OCTAVE_VERSION=11.3.0`, and CTest
  `pure-octave-embed-probe`.

- [ ] **Step 1: Write the rejected-root contract**

  Add a configure-time validator which requires all paths to remain below the
  normalized `OCTAVE_ROOT` and requires:

  ```cmake
  set(required_outputs
    OCTAVE_EXECUTABLE OCTAVE_MKOCTFILE OCTAVE_RUNTIME_DIR
    OCTAVE_MODULE_DIR OCTAVE_SHARE_DIR)
  ```

  Register a script test that passes a fake root containing only an executable
  named `octave-cli.exe`.

- [ ] **Step 2: Run the rejected-root contract**

  Run:

  ```powershell
  cmake -S pure-octave -B "C:\tmp\Pure Octave Build 20260729" `
    -G Ninja -DBUILD_TESTING=ON `
    -DPURE_PREFIX="C:\tmp\Relocated Pure Gplot Final Bundle 20260729" `
    -DOCTAVE_ROOT="C:\tmp\Pure Octave Fake Root"
  ```

  Expected: configuration fails with a precise list of missing `mkoctfile`,
  headers, import libraries, runtime, module, and share paths.

- [ ] **Step 3: Implement signed acquisition**

  `AcquireWindowsOctave.cmake` must:

  ```cmake
  set(octave_version "11.3.0")
  set(archive_name "octave-11.3.0-w64.7z")
  set(archive_url
    "https://ftpmirror.gnu.org/octave/windows/${archive_name}")
  set(signature_url "${archive_url}.sig")
  set(signing_key "B05F05B75D36644B")
  ```

  Download both files below `${WORK_ROOT}/downloads`. Import the required key
  only into `${WORK_ROOT}/gnupg`. Require GnuPG status output containing
  `VALIDSIG`; require the reported primary-key fingerprint to end in
  `B05F05B75D36644B`; record the complete primary-key fingerprint. Then verify
  the detached signature, extract into `${WORK_ROOT}/octave-11.3.0`, and reject
  any extraction path outside `WORK_ROOT`. If `cmake -E tar xf` cannot read the
  signed 7z archive, repeat this exact flow with the official ZIP artifact and
  record that choice in the TODO before continuing.

- [ ] **Step 4: Add the documented public-API probe**

  `embed_probe.cc` must use only:

  ```cpp
  #include <octave/oct.h>
  #include <octave/octave.h>
  #include <octave/interpreter.h>

  octave::interpreter interpreter;
  int status = interpreter.execute();
  octave_value_list in;
  in(0) = 10;
  in(1) = 15;
  octave_value_list out = interpreter.feval("gcd", in, 1);
  ```

  It prints `PURE_OCTAVE_EMBED_PROBE_OK:5` only after a zero initialization
  status and the expected result.

- [ ] **Step 5: Build and run the probe in a sanitized environment**

  `RunEmbedProbe.cmake` must set `PATH` only to the controlled Octave runtime
  and Windows, unset `OCTAVE_HOME`, `OCTAVE_PATH`, and `OCTAVE_EXEC_PATH`, and
  invoke the candidate's own `mkoctfile --link-stand-alone`.

  Run:

  ```powershell
  ctest --test-dir "C:\tmp\Pure Octave Build 20260729" `
    -R pure-octave-embed-probe --output-on-failure
  ```

  Expected: one passing public-API embedding probe.

- [ ] **Step 6: Record provenance and commit**

  Record the chosen archive format, signature fingerprint, extracted root,
  toolchain paths, version output, and probe result in TODO-43.

  ```powershell
  git add pure-octave pure/todo/TODO-43-windows-pure-octave.md
  git commit -m "Validate the Windows Octave 11.3 toolchain"
  ```

---

### Task 2: Add the stable loader and basic Octave 11.3 implementation

**Files:**
- Create: `pure-octave/octave_loader.c`
- Create: `pure-octave/octave_bridge_api.h`
- Create: `pure-octave/cmake/RunPureTest.cmake`
- Create: `pure-octave/tests/basic.pure`
- Modify: `pure-octave/embed.cc`
- Modify: `pure-octave/embed.h`
- Modify: `pure-octave/octave.pure`
- Modify: `pure-octave/CMakeLists.txt`
- Modify: `pure/todo/TODO-43-windows-pure-octave.md`

**Interfaces:**
- Produces stable exports:

  ```c
  int octave_init(int argc, char **argv);
  void octave_fini(void);
  int octave_eval(const char *command);
  const char *octave_last_error(void);
  ```

- The implementation exports:

  ```c
  int pure_octave_impl_init(int argc, char **argv);
  void pure_octave_impl_fini(void);
  int pure_octave_impl_eval(const char *command);
  const char *pure_octave_impl_last_error(void);
  const char *pure_octave_impl_abi(void);
  ```

- [ ] **Step 1: Write the failing basic Pure test**

  `tests/basic.pure` must:

  ```pure
  using octave, system;
  octave_eval "assert (gcd (10, 15) == 5);" == 0 || exit 10;
  octave_eval "assert (2 + 2 == 4);" == 0 || exit 11;
  puts "PURE_OCTAVE_BASIC_OK";
  ```

- [ ] **Step 2: Verify the original Windows module cannot satisfy it**

  Build the existing `embed.cc` against Octave 11.3.0 and run the focused test.
  Expected: compile or load failure caused by obsolete Octave APIs and static
  runtime discovery assumptions. Preserve the first actionable diagnostics in
  TODO-43.

- [ ] **Step 3: Implement the loader**

  `octave_loader.c` must:

  - resolve `PURE_OCTAVE_ROOT`, then the installer config at
    `etc/pure/octave-root.conf`, then the DLL-relative `tools/octave`;
  - validate the root's fingerprint file before loading;
  - call `SetDefaultDllDirectories(LOAD_LIBRARY_SEARCH_SYSTEM32 |
    LOAD_LIBRARY_SEARCH_USER_DIRS)`;
  - add only controlled runtime directories with `AddDllDirectory`;
  - load `lib/pure/octave_bridge_impl.dll` with
    `LoadLibraryExW(..., LOAD_LIBRARY_SEARCH_DLL_LOAD_DIR |
    LOAD_LIBRARY_SEARCH_USER_DIRS)`;
  - require `pure_octave_impl_abi()` to equal
    `pure-octave/11.3.0/windows-x86_64/v1`;
  - resolve every function-table entry before publishing the table;
  - keep UTF-8 diagnostics in a loader-owned buffer;
  - never search host `PATH`.

- [ ] **Step 4: Port interpreter initialization and evaluation**

  Replace obsolete emulation of `octave_main`, direct private symbol-table
  manipulation, and external signal-mask symbols with Octave 11.3 public
  interpreter operations:

  ```cpp
  static std::unique_ptr<octave::interpreter> interpreter;
  interpreter = std::make_unique<octave::interpreter>();
  int status = interpreter->execute();
  octave_value_list out =
    interpreter->eval_string(command, false, parse_status, 0);
  ```

  Catch `octave::exit_exception`, `octave::execution_exception`,
  `std::exception`, and an unknown exception inside every implementation
  export. Convert them to result codes and `pure_octave_impl_last_error()`.

- [ ] **Step 5: Make Pure initialization diagnostic**

  Change the internal `octave_init` declaration in `octave.pure` to return an
  integer. Initialize with `["octave", "--quiet", "--no-history",
  "--no-init-file"]`. If initialization is nonzero, throw a Pure exception
  containing `octave_last_error`.

- [ ] **Step 6: Run basic, loader, and PE tests**

  Run:

  ```powershell
  ctest --test-dir "C:\tmp\Pure Octave Build 20260729" `
    -R "pure-octave-(basic|loader|dependencies)" --output-on-failure
  ```

  Expected: basic evaluation passes; the loader has no Octave imports; the
  implementation resolves its Octave imports only from the explicit root.

- [ ] **Step 7: Record and commit**

  ```powershell
  git add pure-octave pure/todo/TODO-43-windows-pure-octave.md
  git commit -m "Port the pure-octave bridge to Octave 11.3"
  ```

---

### Task 3: Restore the complete data-conversion contract

**Files:**
- Create: `pure-octave/tests/conversions.pure`
- Create: `pure-octave/tests/function-values.pure`
- Modify: `pure-octave/embed.cc`
- Modify: `pure-octave/octave_bridge_api.h`
- Modify: `pure-octave/CMakeLists.txt`
- Modify: `pure/todo/TODO-43-windows-pure-octave.md`

**Interfaces:**
- Restores stable exports for `octave_get`, `octave_set`, `octave_call`,
  `octave_func`, `octave_valuep`, `octave_free`, and `octave_converters`.
- Ownership rule: returned `pure_expr *` belongs to Pure; wrapped
  `octave_value` objects are allocated and deleted inside
  `octave_bridge_impl.dll`.

- [ ] **Step 1: Write the conversion test**

  Cover exact values:

  ```pure
  using math;
  octave_call "plus" 1 (2.5,3.5) == 6.0;
  octave_call "double" 1 {1,2;3,4} == {1.0,2.0;3.0,4.0};
  octave_call "conj" 1 {1.0+:2.0,3.0+:-4.0}
    == {1.0+:-2.0,3.0+:4.0};
  octave_call "toupper" 1 "Pure" == "PURE";
  ```

  Also round-trip a 2×3 real matrix, a complex matrix, a 2×2 cell array, a
  three-dimensional numeric array, a scalar struct, and a two-element struct
  array. Print `PURE_OCTAVE_CONVERSIONS_OK`.

- [ ] **Step 2: Run it and capture the first unsupported Octave 11.3 API**

  Expected: failure until the value API, string API, integer/logical type
  predicates, dimension vectors, and function-handle access are ported.

- [ ] **Step 3: Port native conversions**

  Keep the existing copy semantics. Use Octave 11.3 public value predicates and
  accessors. All temporary Octave values use RAII within the implementation;
  all Pure expressions use the existing `pure_new`, `pure_freenew`, matrix,
  tuple, and sentry conventions.

- [ ] **Step 4: Restore customizable converters**

  Preserve `__pure2oct__`, `__oct2pure__`, `cell`, `struct`, and
  `struct_array`. The C++ layer invokes Pure converter hooks only through the
  Pure C runtime, and catches every Pure exception before returning to Octave.

- [ ] **Step 5: Test function values**

  `function-values.pure` must create `octave_func "eig"` and an anonymous
  function equivalent to `x+y`, assert `octave_valuep`, invoke each, allow the
  values to become unreachable, call `pure_gc`, and then make one further
  Octave call. Print `PURE_OCTAVE_FUNCTION_VALUES_OK`.

- [ ] **Step 6: Run conversion tests and commit**

  ```powershell
  ctest --test-dir "C:\tmp\Pure Octave Build 20260729" `
    -R "pure-octave-(conversions|function-values)" --output-on-failure
  git add pure-octave pure/todo/TODO-43-windows-pure-octave.md
  git commit -m "Restore pure-octave data conversions on Windows"
  ```

---

### Task 4: Prove callbacks, error recovery, and lifecycle safety

**Files:**
- Create: `pure-octave/tests/callbacks.pure`
- Create: `pure-octave/tests/errors.pure`
- Create: `pure-octave/tests/lifecycle.pure`
- Modify: `pure-octave/embed.cc`
- Modify: `pure-octave/octave.pure`
- Modify: `pure-octave/CMakeLists.txt`
- Modify: `pure/todo/TODO-43-windows-pure-octave.md`

**Interfaces:**
- `pure_call(NAME, ARG, ...)` remains installed in the embedded interpreter.
- Every callback converts all inputs and outputs before returning across the
  Octave C++ frame.

- [ ] **Step 1: Write the callback contract**

  `callbacks.pure` defines:

  ```pure
  twice x = 2*x;
  pair x = x,x+1;
  callback_error _ = throw "callback failure";
  ```

  It asserts `pure_call('twice',21)` returns 42, two-output
  `[a,b]=pure_call('pair',9)` returns 9 and 10, and a callback over a complex
  matrix round-trips exactly.

- [ ] **Step 2: Run callback tests before installing the builtin**

  Expected: Octave reports `pure_call` as undefined or the old private
  symbol-table installation fails against Octave 11.3.

- [ ] **Step 3: Install `pure_call` through the current interpreter**

  Keep `DEFUN_DLD` conversion logic inside the implementation. Install the
  resulting built-in function through the current interpreter's supported
  function-registration API. Convert a Pure exception to an Octave execution
  error without allowing it to unwind through Octave C++.

- [ ] **Step 4: Add error and recovery tests**

  `errors.pure` performs, in one process:

  1. invalid Octave syntax;
  2. a valid `2+2` call;
  3. `pure_call('callback_error',1)`;
  4. a valid matrix call;
  5. a missing Octave function;
  6. a valid `gcd` call.

  Each failure must return a stable error and each following success must pass.
  Print `PURE_OCTAVE_ERRORS_OK`.

- [ ] **Step 5: Add lifecycle stress**

  `lifecycle.pure` runs 100 scalar, matrix, and callback cycles, releases
  temporary function values, and exits normally. CTest runs it in 20 fresh
  Pure processes with a 60-second timeout per process. No process may crash,
  hang, or write outside its controlled work directory.

- [ ] **Step 6: Run the candidate acceptance gate**

  Run the complete suite plus PE audit with MSYS2 absent from `PATH`. Expected:
  all tests pass and repeated shutdown is clean.

  If the official runtime fails this gate because of C++ runtime coexistence,
  stop before permanent installation and append the exact crash, import, or
  exception evidence to TODO-43. Create a follow-up plan for a Clang/libc++
  Octave build only after user approval.

- [ ] **Step 7: Permanently install the accepted candidate**

  Only after Step 6 passes, copy the signature-verified distribution to:

  ```text
  C:\Tools\GNU Octave\11.3.0
  ```

  Re-run the complete suite with
  `PURE_OCTAVE_ROOT=C:\Tools\GNU Octave\11.3.0`. Record the permanent root and
  validation result.

- [ ] **Step 8: Commit**

  ```powershell
  git add pure-octave pure/todo/TODO-43-windows-pure-octave.md
  git commit -m "Validate pure-octave callbacks and lifecycle"
  ```

---

### Task 5: Implement exact external detection and managed fallback

**Files:**
- Create: `pure-octave/tools/DetectWindowsOctave.ps1`
- Create: `pure-octave/tests/detection.Tests.ps1`
- Create: `pure-octave/cmake/WriteOctaveFingerprint.cmake`
- Create: `pure-octave/cmake/RunLoaderSelectionTest.cmake`
- Create: `pure-octave/tests/selection.pure`
- Modify: `pure-octave/octave_loader.c`
- Modify: `pure-octave/CMakeLists.txt`
- Modify: `pure/todo/TODO-43-windows-pure-octave.md`

**Interfaces:**
- Detector parameters are `-CandidateRoots`, `-SupportedManifest`, and the
  test-only `-ProbeExecutable`. Production calls omit `-ProbeExecutable` and
  execute the candidate's own `octave-cli.exe`.
- Detector JSON schema:

  ```json
  {
    "status": "compatible-external",
    "root": "C:\\Tools\\GNU Octave\\11.3.0",
    "version": "11.3.0",
    "architecture": "x86_64",
    "abi": "pure-octave/11.3.0/windows-x86_64/v1",
    "reason": ""
  }
  ```

- `status` is exactly one of `compatible-external`,
  `unsupported-external`, `not-installed`, or `invalid`.

- [ ] **Step 1: Write Pester-free detector tests**

  The PowerShell test script creates fake roots for missing executable, wrong
  version, wrong architecture, missing fingerprint, mismatched fingerprint,
  and compatible metadata. Its fixture probe is passed explicitly through
  `-ProbeExecutable`; it never makes metadata alone sufficient for
  compatibility. It calls the detector, parses JSON with `ConvertFrom-Json`,
  and asserts every field and exit code.

- [ ] **Step 2: Run detector tests red**

  Run:

  ```powershell
  powershell -NoProfile -ExecutionPolicy Bypass `
    -File pure-octave\tests\detection.Tests.ps1
  ```

  Expected: failure because the detector does not exist.

- [ ] **Step 3: Implement deterministic detection**

  Search only explicit candidate roots supplied by TODO-49 and documented
  registry/uninstall entries belonging to GNU Octave. Do not inspect `PATH`.
  Execute the candidate's exact `octave-cli.exe --version`, audit PE
  architecture, and compare the installed fingerprint with the supported
  manifest.

- [ ] **Step 4: Write the loader-selection matrix**

  `RunLoaderSelectionTest.cmake` creates isolated miniature prefixes and checks:

  - explicit `PURE_OCTAVE_ROOT` overrides config and managed root;
  - compatible installer config overrides managed root;
  - managed root is used when no config exists;
  - invalid explicit root fails rather than falling through;
  - missing roots never find a host Octave from `PATH`.

- [ ] **Step 5: Run detector and loader-selection tests**

  Expected: all JSON statuses and precedence cases pass with paths containing
  spaces.

- [ ] **Step 6: Record TODO-49 contract and commit**

  ```powershell
  git add pure-octave pure/todo/TODO-43-windows-pure-octave.md
  git commit -m "Add Windows Octave detection and managed fallback"
  ```

---

### Task 6: Package, relocate, and validate the optional component

**Files:**
- Create: `pure-octave/cmake/Install.cmake`
- Create: `pure-octave/cmake/VerifyInstalledPackage.cmake`
- Create: `pure-octave/WINDOWS.md`
- Create: `.github/workflows/pure-octave-windows.yml`
- Modify: `pure-octave/CMakeLists.txt`
- Modify: `pure-octave/README`
- Modify: `pure/todo/TODO-43-windows-pure-octave.md`

**Interfaces:**
- Consumes: `PURE_OCTAVE_INSTALL_RUNTIME=ON|OFF`, exact `OCTAVE_ROOT`, and a
  portable Pure base prefix.
- Produces: `lib/pure/octave_embed.dll`,
  `lib/pure/octave_bridge_impl.dll`, `lib/pure/octave.pure`,
  `lib/pure/gnuplot.pure`, documentation, detector, fingerprints, tests, and
  optionally `tools/octave`.

- [ ] **Step 1: Write the installed-package verifier first**

  Require the binding inventory, licenses, detector, tests, and fingerprints.
  With the runtime enabled, require the complete controlled Octave closure.
  Compare reused Pure runtime hashes with the base prefix.

  The verifier must run basic, conversion, callback, error, and lifecycle
  tests with `PURELIB` unset, `PURE_OCTAVE_ROOT` unset, and `PATH` restricted
  to the stage plus Windows.

- [ ] **Step 2: Run verifier before install rules**

  Expected: failure at the first missing installed binding file.

- [ ] **Step 3: Add optional install rules**

  Always install the loader, implementation, Pure modules, examples, tests,
  documentation, detector, and pure-octave licenses. When
  `PURE_OCTAVE_INSTALL_RUNTIME=ON`, copy only from the signature-validated,
  build-tree snapshot of `OCTAVE_ROOT` to `tools/octave`, preserving Octave
  license and provenance files. The OFF configuration must contain no Octave
  runtime tree.

- [ ] **Step 4: Stage and verify**

  Copy `C:\tmp\Relocated Pure Gplot Final Bundle 20260729` to
  `C:\tmp\Pure Octave Stage 20260729`, install with the managed runtime ON, and
  run:

  ```powershell
  cmake -DSTAGE_PREFIX="C:\tmp\Pure Octave Stage 20260729" `
    -DSOURCE_RUNTIME_DIR="C:\tmp\Relocated Pure Gplot Final Bundle 20260729\bin" `
    -P pure-octave\cmake\VerifyInstalledPackage.cmake
  ```

- [ ] **Step 5: Relocate and verify**

  Copy the full stage to
  `C:\tmp\Relocated Pure Octave Bundle 20260729`, rerun the verifier, then
  verify an OFF installation contains no `tools/octave`.

- [ ] **Step 6: Add clean Windows GitHub validation**

  The workflow uses `windows-latest`, caches only the signature-verified Octave
  archive by exact version and fingerprint, builds the module, runs the
  noninteractive suite, stages the managed component, relocates it, and runs
  the installed verifier. Make the workflow manually dispatchable and weekly;
  do not run GUI plotting tests.

- [ ] **Step 7: Document size and close TODO-43**

  Record the exact managed runtime file count and byte size, external and
  managed behaviors, permanent development installation, GitHub result, and
  relocation evidence. Change the status to `Closed on` followed by the actual
  ISO calendar date on which all of these validation gates finish.

- [ ] **Step 8: Commit**

  ```powershell
  git add .github/workflows/pure-octave-windows.yml `
    pure-octave pure/todo/TODO-43-windows-pure-octave.md
  git commit -m "Package pure-octave as an optional Windows component"
  ```

---

### Task 7: Review and integrate into windows-bundle

**Files:**
- No source changes expected.

**Interfaces:**
- Consumes: closed and verified `todo/43-windows-pure-octave`.
- Produces: pushed `windows-bundle` containing a history-preserving merge.

- [ ] **Step 1: Request focused code review**

  Review the complete branch against the design and this plan. Fix every
  Critical and Important finding, then rerun affected tests.

- [ ] **Step 2: Run fresh feature-branch verification**

  Run the complete CTest suite, detector tests, installed verifier against the
  relocated prefix, PE audit, `git diff --check`, and `git status --short`.
  Expected: all pass and the worktree is clean.

- [ ] **Step 3: Merge locally**

  Fetch `origin/windows-bundle`, confirm local and remote base alignment,
  switch to `windows-bundle`, and merge
  `todo/43-windows-pure-octave` with a history-preserving merge commit.

- [ ] **Step 4: Verify merged result**

  Repeat the complete suite and installed verifier on the merge commit. Stop
  without pushing on any failure.

- [ ] **Step 5: Push and confirm**

  Push `windows-bundle`, fetch it, require local `HEAD` to equal
  `origin/windows-bundle`, and delete the merged local TODO branch.
