# Windows pure-faust Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Package `faust2.pure` as the Windows `pure-faust` runtime and provide a separate, reproducible Faust 2.70.3 developer toolchain that generates Clang 22 bitcode without MSYS2.

**Architecture:** The runtime package is script-only and delegates loading, ABI checks, DSP execution, and cleanup to the Pure core completed by TODO-11. CMake components keep the runtime payload separate from the Faust compiler, `pure.c`, and a Windows-native `faust2pure.ps1` helper; staged-layout tests exercise each component with a sanitized environment.

**Tech Stack:** CMake 3.25+, CTest, Pure, PowerShell 5.1+, Faust 2.70.3, Clang/LLVM 22, GitHub Actions Windows runners.

## Global Constraints

- Execute on an integration base containing `windows-bundle` commit `38210b213` or a descendant; before Task 1, `git merge-base --is-ancestor 38210b213 HEAD` must succeed. The current planning branch does not yet satisfy this, so do not implement until its two documentation commits are transferred to an approved descendant of that integration base.
- Install `faust2.pure`; do not build or install `faust.cc`, `faust.pure`, `pure.cpp`, or `faust.dll` on Windows.
- Preserve the portable legacy sources and non-Windows behavior.
- Pin the developer compiler to Faust 2.70.3 and compile generated C with the distribution's Clang 22.
- Keep Faust, `pure.c`, Clang, and LLVM command-line tools out of the default runtime component.
- Do not require MSYS2, a host `PATH`, or a global `PURELIB` at package runtime.
- Use distribution-relative discovery and support paths containing spaces.
- Publish generated bitcode atomically; failure must preserve an existing destination.
- Record the upstream URL, SHA-256, installed-file inventory, provenance, and licenses for every developer payload.
- If the official Faust 2.70.3 Windows artifact cannot be acceptably redistributed, stop for a packaging decision instead of changing versions.

---

## File Map

- Create `pure-faust/CMakeLists.txt`: define runtime/developer components, focused tests, and install entry point.
- Create `pure-faust/cmake/Install.cmake`: declare exact files in the `Runtime` and `FaustDeveloper` components.
- Create `pure-faust/cmake/RunFaust2Pure.cmake`: shared process driver for Faust, Clang, verifier, and atomic publication.
- Create `pure-faust/cmake/RunRuntimeSmoke.cmake`: run the staged runtime smoke with sanitized environment.
- Create `pure-faust/cmake/VerifyInstalledPackage.cmake`: assert component boundaries, forbidden files, path cleanliness, and installed behavior.
- Create `pure-faust/tools/faust2pure.ps1`: user-facing Windows-native developer helper.
- Create `pure-faust/tests/reference.dsp`: deterministic two-input/one-output DSP source.
- Create `pure-faust/tests/runtime-smoke.pure`: load the fixture through `faust2`, check channels/output, and clean up.
- Create `pure-faust/tests/helper-failures.cmake`: verify missing-tool diagnostics and destination preservation.
- Create `pure-faust/WINDOWS.md`: document component selection and distribution-relative usage.
- Create `pure-faust/THIRD_PARTY.md`: record Faust artifact provenance and license mapping.
- Modify `.github/workflows/non-linux-release-validation.yml`: build, stage, audit, and test both component selections.
- Modify `pure/todo/TODO-44-windows-pure-faust.md`: resolve decisions, track exact validation, and close only after clean-VM success.

### Task 1: Establish the Windows package and runtime-only boundary

**Files:**
- Create: `pure-faust/CMakeLists.txt`
- Create: `pure-faust/cmake/Install.cmake`
- Create: `pure-faust/cmake/VerifyInstalledPackage.cmake`
- Test: CTest `pure-faust-runtime-layout`

**Interfaces:**
- Consumes: installed Pure prefix from `pkg-config pure`; integration-base `pure.exe` with TODO-11 Faust loading.
- Produces: CMake install components `Runtime` and `FaustDeveloper`; cache variables `PURE_FAUST_CORE_FIXTURE`, `PURE_FAUST_FAUST_ROOT`, `PURE_FAUST_CLANG`, and `PURE_FAUST_OPT`.

- [ ] **Step 1: Write the failing runtime-layout test**

Add `pure-faust-runtime-layout` to configure and install only `Runtime` into `${binary_dir}/stage runtime`, then call `VerifyInstalledPackage.cmake` with `EXPECT_DEVELOPER=OFF`. The verifier must require `lib/pure/faust2.pure`, `share/doc/pure-faust/COPYING`, `COPYING.LESSER`, and `WINDOWS.md`; it must fail if it finds `faust.dll`, `faust.pure`, `pure.cpp`, `faust.exe`, `clang.exe`, `opt.exe`, or `msys-2.0.dll`.

- [ ] **Step 2: Run the test to verify it fails**

Run:

```powershell
cmake -S pure-faust -B build/pure-faust -G Ninja -DCMAKE_PREFIX_PATH=C:/pure -DPURE_FAUST_CORE_FIXTURE=C:/pure/test/faust/reference.bc
ctest --test-dir build/pure-faust -R pure-faust-runtime-layout --output-on-failure
```

Expected: configure or test fails because the CMake package/install rules do not exist.

- [ ] **Step 3: Implement the minimal script-only package**

In `CMakeLists.txt`, require CMake 3.25, locate Pure only inside its reported prefix, enable CTest, and include `cmake/Install.cmake`. In `Install.cmake`, use explicit `install(FILES ...)` calls with `COMPONENT Runtime`; never use a source-tree glob. In the verifier, normalize the stage path, enumerate the exact expected files, recursively scan only that normalized stage, and reject the forbidden basenames case-insensitively.

- [ ] **Step 4: Run the focused test and inspect the manifest**

Run:

```powershell
cmake --build build/pure-faust
ctest --test-dir build/pure-faust -R pure-faust-runtime-layout --output-on-failure
cmake --install build/pure-faust --prefix "C:/tmp/pure faust runtime" --component Runtime
```

Expected: PASS; the stage contains `faust2.pure` and documentation but none of the forbidden developer or legacy files.

- [ ] **Step 5: Commit the runtime boundary**

```powershell
git add pure-faust/CMakeLists.txt pure-faust/cmake/Install.cmake pure-faust/cmake/VerifyInstalledPackage.cmake
git commit -m "Package the Windows faust2 runtime"
```

### Task 2: Build and exercise the deterministic runtime fixture

**Files:**
- Create: `pure-faust/tests/reference.dsp`
- Create: `pure-faust/tests/runtime-smoke.pure`
- Create: `pure-faust/cmake/RunRuntimeSmoke.cmake`
- Modify: `pure-faust/CMakeLists.txt`
- Modify: `pure-faust/cmake/Install.cmake`
- Modify: `pure-faust/cmake/VerifyInstalledPackage.cmake`

**Interfaces:**
- Consumes: `PURE_FAUST_CORE_FIXTURE` bitcode generated by Faust 2.70.3 + `pure.c` + Clang 22 on the same Windows target.
- Produces: installed `share/doc/pure-faust/tests/reference.bc`; CTest `pure-faust-runtime-smoke`; Pure script exit status 0 only after exact DSP assertions and `faust_exit`.

- [ ] **Step 1: Write the DSP source and failing Pure smoke**

Use the same fixture contract as TODO-11:

```faust
declare name "Pure ORC reference";
process = _,_ : +;
```

The Pure test must import `faust2`, initialize `reference.bc` at 48000 Hz,
assert two inputs and one output from `faust_info`, feed rows
`{1.0, -0.5, 0.25, 0.0}` and `{2.0, 1.0, -0.25, 4.0}`, assert output
`{3.0, 0.5, 0.0, 4.0}`, call `faust_exit`, and print
`pure-faust runtime smoke: PASS`.

- [ ] **Step 2: Run the smoke to verify it fails**

Run:

```powershell
ctest --test-dir build/pure-faust -R pure-faust-runtime-smoke --output-on-failure
```

Expected: FAIL because the staged fixture and driver are absent.

- [ ] **Step 3: Add fixture staging and the sanitized driver**

Require `PURE_FAUST_CORE_FIXTURE` to exist and install it as `gain.bc` in the runtime test payload. `RunRuntimeSmoke.cmake` must set `PATH` to `<stage>/bin;C:/Windows/System32;C:/Windows`, clear `PURELIB`, create a fresh working directory whose name contains spaces, and run:

```text
<stage>/bin/pure.exe --norc -I <stage>/lib/pure -L <fixture-dir> -x <runtime-smoke.pure>
```

Capture stdout/stderr, use a 90-second timeout, require exit code 0 and the PASS marker, then remove the working directory.

- [ ] **Step 4: Run runtime-only validation**

Run:

```powershell
ctest --test-dir build/pure-faust -R "pure-faust-(runtime-layout|runtime-smoke)" --output-on-failure
```

Expected: two tests pass with a sanitized `PATH`; no Faust or LLVM executable is invoked.

- [ ] **Step 5: Commit the deterministic runtime smoke**

```powershell
git add pure-faust/tests pure-faust/cmake/RunRuntimeSmoke.cmake pure-faust/CMakeLists.txt pure-faust/cmake/Install.cmake pure-faust/cmake/VerifyInstalledPackage.cmake
git commit -m "Test the Windows faust2 runtime"
```

### Task 3: Add the Windows-native Faust developer helper

**Files:**
- Create: `pure-faust/tools/faust2pure.ps1`
- Create: `pure-faust/cmake/RunFaust2Pure.cmake`
- Create: `pure-faust/tests/helper-failures.cmake`
- Modify: `pure-faust/CMakeLists.txt`

**Interfaces:**
- Consumes: `-InputPath <string>`, optional `-OutputPath <string>`, and distribution layout containing `faust.exe`, `pure.c`, `clang.exe`, and `opt.exe`.
- Produces: verified LLVM bitcode at `OutputPath`; prints the absolute output path; returns 0 on success and nonzero with stage-specific diagnostics on failure.

- [ ] **Step 1: Write failing helper tests**

Cover four cases in `helper-failures.cmake`: missing Faust reports `Faust developer component is not installed`; missing `pure.c` names that file; a fake verifier failure leaves a sentinel destination byte-for-byte unchanged; and paths containing spaces reach the fake tools with argument boundaries preserved.

- [ ] **Step 2: Run the tests to verify they fail**

Run:

```powershell
ctest --test-dir build/pure-faust -R pure-faust-helper --output-on-failure
```

Expected: FAIL because `faust2pure.ps1` and the process driver are absent.

- [ ] **Step 3: Implement the helper and shared driver**

The PowerShell entry point resolves its own directory, derives the distribution prefix, validates all four tools, and calls `RunFaust2Pure.cmake`. The CMake driver creates a unique work directory, executes these exact stages, and stops on the first nonzero status:

```text
faust.exe -lang c -a <pure.c> <input.dsp> -o <temp>/reference.c
clang.exe -emit-llvm -O3 -c <temp>/reference.c -o <temp>/reference.bc
opt.exe -passes=verify -disable-output <temp>/reference.bc
cmake -E copy_if_different <temp>/reference.bc <output>.new
cmake -E rename <output>.new <output>
```

Use `try/finally` in PowerShell to remove temporary output on every exit. Refuse identical input/output paths and directories used as output files. Report `faust`, `clang`, `verify`, or `publish` as the failing stage.

- [ ] **Step 4: Run helper unit tests**

Run:

```powershell
ctest --test-dir build/pure-faust -R pure-faust-helper --output-on-failure
```

Expected: all failure-safety and quoting tests pass.

- [ ] **Step 5: Commit the helper**

```powershell
git add pure-faust/tools/faust2pure.ps1 pure-faust/cmake/RunFaust2Pure.cmake pure-faust/tests/helper-failures.cmake pure-faust/CMakeLists.txt
git commit -m "Add the Windows Faust bitcode helper"
```

### Task 4: Define and validate the optional Faust 2.70.3 component

**Files:**
- Create: `pure-faust/cmake/FaustToolchain.cmake`
- Create: `pure-faust/licenses/Faust-COPYING.txt`
- Create: `pure-faust/THIRD_PARTY.md`
- Modify: `pure-faust/cmake/Install.cmake`
- Modify: `pure-faust/cmake/VerifyInstalledPackage.cmake`
- Modify: `pure-faust/CMakeLists.txt`

**Interfaces:**
- Consumes: extracted official asset `Faust-2.70.3-win64.exe` from `https://github.com/grame-cncm/faust/releases/download/2.70.3/Faust-2.70.3-win64.exe`, supplied as `PURE_FAUST_FAUST_ROOT`; Clang/opt 22 paths supplied explicitly by the parent distribution build.
- Produces: `FaustDeveloper` payload, a provenance record containing the locally computed SHA-256 and exact installed-file allowlist, and CTest `pure-faust-developer-smoke`.

- [ ] **Step 1: Capture artifact identity and inventory before packaging**

Download the official 106,920,705-byte asset to a temporary directory and
compute `Get-FileHash -Algorithm SHA256`. Install it into an empty temporary
prefix with `Start-Process -Wait -PassThru -ArgumentList '/S',
'/D=<absolute-temp-prefix>'`; require exit code 0 and refuse a nonempty prefix.
Run the installed `faust.exe -version`, save a sorted relative-file inventory,
and compare its license files against the upstream 2.70.3 source release. Do
not commit the installer or installed payload, and remove only the verified
temporary prefix after the inventory is recorded.

- [ ] **Step 2: Write failing developer-layout assertions**

With `EXPECT_DEVELOPER=ON`, require the allowlisted `faust.exe`, `pure.c`, helper, Faust license, and provenance document; require `faust -version` to report `2.70.3`; require `clang --version` and `opt --version` to report major version 22. Fail on every extracted file not present in the explicit allowlist.

- [ ] **Step 3: Run the developer test to verify it fails**

Run:

```powershell
ctest --test-dir build/pure-faust -R pure-faust-developer --output-on-failure
```

Expected: FAIL because the developer component is not installed yet.

- [ ] **Step 4: Install the explicit developer payload and provenance**

Put the verified URL, byte size, computed SHA-256, release tag, license mapping, and relative allowlist in `FaustToolchain.cmake` and `THIRD_PARTY.md`. Install only allowlisted Faust files plus `pure.c` and `faust2pure.ps1` under `COMPONENT FaustDeveloper`. Reference distribution-owned Clang/opt paths; do not copy undeclared LLVM or MSYS2 trees.

- [ ] **Step 5: Rebuild the fixture and run it**

Configure with the temporary Faust root and explicit LLVM 22 tools, install
both components to `C:/tmp/pure faust full`, invoke installed
`faust2pure.ps1` on `reference.dsp`, verify the emitted `reference.bc`, then
execute `runtime-smoke.pure` against that new file.

Expected: the build and smoke pass; the output path contains spaces; the existing runtime fixture remains unchanged.

- [ ] **Step 6: Commit the developer component**

```powershell
git add pure-faust/cmake/FaustToolchain.cmake pure-faust/cmake/Install.cmake pure-faust/cmake/VerifyInstalledPackage.cmake pure-faust/licenses/Faust-COPYING.txt pure-faust/THIRD_PARTY.md pure-faust/CMakeLists.txt
git commit -m "Package the optional Faust developer tools"
```

### Task 5: Document, automate, and close TODO-44

**Files:**
- Create: `pure-faust/WINDOWS.md`
- Modify: `.github/workflows/non-linux-release-validation.yml`
- Modify: `pure/todo/TODO-44-windows-pure-faust.md`

**Interfaces:**
- Consumes: `Runtime` and `FaustDeveloper` CMake components and all focused CTests.
- Produces: clean-runner validation for both selections and a closed TODO containing exact commands/results.

- [ ] **Step 1: Add the failing workflow/static audit first**

Add a Windows job section that configures from a checkout path containing spaces, builds the package, stages runtime-only and full layouts separately, sanitizes `PATH`, and runs the corresponding CTest labels. Add repository assertions that no Windows install rule selects `faust.cc`, `faust.pure`, `pure.cpp`, or `faust.dll`.

- [ ] **Step 2: Run the local equivalents**

Run:

```powershell
cmake --build build/pure-faust
ctest --test-dir build/pure-faust --output-on-failure
cmake --install build/pure-faust --prefix "C:/tmp/pure faust runtime" --component Runtime
cmake --install build/pure-faust --prefix "C:/tmp/pure faust full" --component Runtime
cmake --install build/pure-faust --prefix "C:/tmp/pure faust full" --component FaustDeveloper
git diff --check
```

Expected: all tests pass; runtime-only has no developer/legacy payload; full stage rebuilds and runs the fixture; `git diff --check` is clean.

- [ ] **Step 3: Write Windows usage and resolved decisions**

Document runtime-only loading, optional component installation, exact `faust2pure.ps1` syntax, the Faust 2.70.3/Clang 22 compatibility promise, spaces-in-path support, and the absence of MSYS2. Rewrite TODO-44 task 2 to say the legacy bridge is deliberately excluded, resolve the compiler question as optional, and append exact validation counts and caveats.

- [ ] **Step 4: Verify on a clean Windows runner**

Run the workflow job for both component configurations. Record the workflow run URL, commit, CTest count, elapsed time, artifact hash, and any bounded caveat in the progress log. Do not mark the TODO closed if either clean-runner configuration is skipped or fails.

- [ ] **Step 5: Close and commit**

Set `Status: Closed on 2026-08-15` only after every checklist item and clean-runner gate passes, then run `git diff --check` and review `git diff --stat windows-bundle...HEAD` for TODO-44-only scope.

```powershell
git add .github/workflows/non-linux-release-validation.yml pure-faust/WINDOWS.md pure/todo/TODO-44-windows-pure-faust.md
git commit -m "Validate and close Windows pure-faust"
```
