# Task 4 — Hermetic Native Runner and Owned Cleanup

Base: `6026c924b8248225d0cef88838ebd12b76de572e`.
Workspace: `C:\pure-lang\.worktrees\todo33-audit`, branch
`codex/todo33-audit`. Verification date: 2026-09-08, Europe/Prague.

The original evidence below describes commit
`3d1d09c5b43d6e87aacad9b6a19854cf99b4a5f2`. Fix round 1, recorded at the end,
supersedes its direct-subdirectory cleanup scope limitation and final counts.

The Task 4 brief, approved design/plan, preceding reports, and progress rulings
were read before implementation. Superpowers TDD, systematic debugging, and
verification-before-completion governed the behavioral RED checks, root-cause
investigations, and final verification. No subagents, merge, or push were used.

## Implementation and consumer interface

`run_pure_test.exe` owns the Windows launch and scratch-directory lifecycle:

```text
run_pure_test.exe --create-leaf
run_pure_test.exe --pure <absolute-exe> --script <absolute-script>
  --token auto --timeout <milliseconds> --cwd <owned-leaf>
  [--path-entry <directory>] [--include <directory>]
  [--module-dir <directory>] [--allow-stderr <exact-complete-line>]
run_pure_test.exe --cleanup --cwd <owned-leaf>
```

`--token auto` requests a native BCrypt-generated 128-bit nonce. Caller-chosen
tokens are rejected. The token is appended as the final Pure script argument;
each executable fixture prints `last argv` after its checks and resource close.
Success requires exit zero, exactly one occurrence of the token, the token as
the complete final stdout line, successful complete capture, no surviving
descendant, and no unlisted stderr line. The runner preserves nonzero child
exit status exactly (`37` is tested), uses `124` for child timeout, `1` for
completion/diagnostic failures, and `2` for rejected inputs/ownership.

The explicit UTF-16 environment contains only `PATH`, `SystemRoot`, `TEMP`,
`TMP`, and `WINDIR`. PATH consists of the executable directory, explicit
canonical runtime directories, and Windows directories obtained from native
APIs. TEMP/TMP point into the owned leaf. All three inherited Pure path
variables are absent. No shell participates in launching Pure.

Canonical drive paths reject traversal, alternate filesystem aliases, reparse
components, wrong file types, ambiguous trailing characters, and relative
inputs. Directory handles have actual read access and deny write/delete
sharing; attribute-only handles did not enforce the required sharing lock.
Explicit interface/module directories also validate and retain their immediate
`.pure`/`.dll` inputs. File and directory identity locks last through child
termination and pipe draining.

The child starts suspended and detached, receives only three explicit standard
handles, and enters a kill-on-close Job Object before running. Two native
threads drain stdout/stderr concurrently, each retaining at most 1 MiB while
continuing to drain excess bytes. Overflow fails validation. Timeout terminates
the job; the owner waits for the primary process, zero active job processes,
and both readers before releasing handles. Exceptional owner termination also
closes the job and terminates its descendants.

The fixed scratch root is `pure-audio-contract-root` next to the runner. It
requires an exact regular root sentinel. Each `run-<128-bit-nonce>` leaf has an
exact regular, single-link sentinel bound to that leaf name. Launch and cleanup
take an exclusive sentinel handle. Cleanup first validates and retains every
tree object's identity, then deletes those objects through Windows file
handles in child-before-parent order. It never recursively deletes a caller
chosen root or follows a discovered reparse point.

`RunPureTest.cmake` exposes `pure_audio_create_leaf`,
`pure_audio_cleanup_leaf`, and `pure_audio_run_fixture`. Task 6 can include it
with `PURE_AUDIO_RUNNER_HELPERS_ONLY=ON`, supply the explicit runner/Pure/source/
module/runtime inputs, and reuse the same operations. `RunHardwareTest.cmake`
sets the fixture and timeout, then calls the same helper. The per-invocation
`PURE_AUDIO_STDERR_ALLOWLIST` contains exact complete lines only; current real
mandatory fixtures need no stderr allowances. The contract tests an exact
backend notice and rejects a near match with extra diagnostic text.

Playback now waits up to 500 ten-millisecond polls for 256 callback-consumed
frames before closing. Its output explicitly describes callback consumption.
Capture reports one requested/received channel and the actual received frame
count. The hardware helper is loaded by a no-hardware contract case, but no
physical playback/capture was performed.

The top-level Make clean targets validate one exact suffix from `.dll`, `.so`,
or `.dylib` before any recipe. They enumerate the ten object/module outputs
across the five module directories and use nonrecursive `rm -f`. Package-level
cleanup no longer delegates to the broad legacy subdirectory clean recipes.

## Test-first RED evidence

All relative paths below are relative to the workspace named above. Before
writing the runner implementation, `run_pure_test.c` contained only the native
adversarial child behind `PURE_AUDIO_RUNNER_FIXTURE`:

```powershell
New-Item -ItemType Directory -Force C:/pure-lang/task4-normal | Out-Null
C:/msys64/clang64/bin/clang.exe -std=c11 -Wall -Wextra -Werror -DPURE_AUDIO_RUNNER_FIXTURE pure-audio/tests/run_pure_test.c -o C:/pure-lang/task4-normal/run_pure_fixture.exe
C:/msys64/clang64/bin/cmake.exe -DLEGACY=ON -DRUNNER=legacy -DFIXTURE=C:/pure-lang/task4-normal/run_pure_fixture.exe -DPURE_EXECUTABLE=C:/pure-lang/pure/build/windows-clang64-prefix/bin/pure.exe -DPURE_SOURCE_DIR=C:/pure-lang/.worktrees/todo33-audit/pure-audio -DMODULE_DIR=C:/pure-lang/task4-normal -P pure-audio/tests/runner_contract.cmake
C:/msys64/clang64/bin/cmake.exe -DLEGACY=ON -DFIXTURE=C:/pure-lang/task4-normal/run_pure_fixture.exe -DPURE_SOURCE_DIR=C:/pure-lang/.worktrees/todo33-audit/pure-audio -DMODULE_DIR=C:/pure-lang/task4-normal -P pure-audio/tests/cleanup_contract.cmake
```

The unchanged legacy launcher accepted **6/6 invalid completions**: parser
diagnostic with exit zero, exception diagnostic, wrong token, forged token,
duplicate token, and non-final token. The cleanup RED independently reported
`cleanup removed a leaf without an ownership sentinel`. Its sacrificial target
was an explicitly created scratch leaf, not user data.

Before changing Make cleanup, this behavioral command ran the actual Makefile
inside an owned scratch leaf containing both outputs and unrelated neighbors:

```powershell
C:/msys64/clang64/bin/cmake.exe -DRUNNER=C:/pure-lang/task4-normal/run_pure_test.exe -DFIXTURE=C:/pure-lang/task4-normal/run_pure_fixture.exe -DMODULE_DIR=C:/pure-lang/task4-normal -DPURE_SOURCE_DIR=C:/pure-lang/.worktrees/todo33-audit/pure-audio -DMAKE_EXECUTABLE=C:/msys64/clang64/bin/mingw32-make.exe -DSH_EXECUTABLE=C:/msys64/usr/bin/sh.exe -P pure-audio/tests/cleanup_contract.cmake
```

RED: `Make clean violated exact owned outputs: 0`; the command exited zero but
`rm -Rf *.o *.dll*` removed unrelated `.dll.keep` and `.o` files, including a
subdirectory neighbor. This was a behavior failure, not an expected-string
assertion on the Makefile.

Self-review added a separate directory-lock regression before its correction:

```powershell
C:/msys64/clang64/bin/clang.exe -std=c11 -Wall -Wextra -Werror -DPURE_AUDIO_RUNNER_FIXTURE pure-audio/tests/run_pure_test.c -o C:/pure-lang/task4-normal/run_pure_fixture.exe
C:/msys64/clang64/bin/cmake.exe -DRUNNER=C:/pure-lang/task4-normal/run_pure_test.exe -DFIXTURE=C:/pure-lang/task4-normal/run_pure_fixture.exe -DPURE_EXECUTABLE=C:/pure-lang/pure/build/windows-clang64-prefix/bin/pure.exe -DPURE_SOURCE_DIR=C:/pure-lang/.worktrees/todo33-audit/pure-audio -DMODULE_DIR=C:/pure-lang/task4-normal '-DRUNTIME_DIRS=C:/pure-lang/pure/build/windows-clang64-prefix/bin;C:/msys64/clang64/bin' -P pure-audio/tests/runner_contract.cmake
```

RED: `directory-lock: expected 0, got 69`, followed by one contract failure.
Denying write sharing on an attribute-only handle was insufficient. Changing
the directory lock to actual `GENERIC_READ` access made the attempted second
write handle fail and the same contract pass. This directly covers in-place
directory mutation access, in addition to reparse-path rejection.

These are historical test-first commands against the production state at each
point, not claims that the final expanded matrix ran unchanged against the base.

## GREEN evidence

Configure/build environment and exact fresh build configuration:

```powershell
$env:MSYSTEM_PREFIX='C:/msys64/clang64'
$env:PKG_CONFIG_PATH='C:/pure-lang/pure/build/windows-clang64-prefix/lib/pkgconfig;C:/msys64/clang64/lib/pkgconfig'
$env:PATH='C:/pure-lang/pure/build/windows-clang64-prefix/bin;C:/msys64/clang64/bin;C:/Windows/System32;C:/Windows'
C:/msys64/clang64/bin/cmake.exe -S pure-audio -B C:/pure-lang/task4-green -G Ninja -DCMAKE_BUILD_TYPE=Debug -DBUILD_TESTING=ON -DCMAKE_C_COMPILER=C:/msys64/clang64/bin/clang.exe -DCMAKE_MAKE_PROGRAM=C:/msys64/clang64/bin/ninja.exe
C:/msys64/clang64/bin/cmake.exe --build C:/pure-lang/task4-green --parallel 4
```

Configure and all 18 initial build steps passed. The final four-worker rebuild
after the sharing-lock correction also passed with no compiler diagnostics.

The poison directory contains failing `prelude.pure`, `system.pure`, and
`audio.pure` fixtures and an invalid `audio.dll`. The runner contract additionally
creates its own poison directory and fills all four inherited path variables.

```powershell
$env:PATH='C:/pure-lang/task4-poison'
$env:PURELIB='C:/pure-lang/task4-poison'
$env:PURE_INCLUDE='C:/pure-lang/task4-poison'
$env:PURE_LIBRARY='C:/pure-lang/task4-poison'
C:/msys64/clang64/bin/ctest.exe --test-dir C:/pure-lang/task4-green -L audio --output-on-failure
```

Final full suite: **6/6 passed**, 52.97 seconds.

| Test | Seconds | Evidence |
| --- | ---: | --- |
| fault-bounds | 8.08 | 2,391 native checks; intentional quarantine allocation delta 3 |
| load | 6.07 | Generated final token |
| processing | 7.99 | Generated final token |
| public-bounds | 8.67 | 24 bounds checks, then resource cleanup and generated token |
| runner-contract | 17.65 | 23 rejected cases, 7 accepted cases, one descendant-termination check |
| cleanup-contract | 4.49 | 13 rejected cleanup cases, 2 valid leaves; Make 4 rejected suffixes and 2 valid targets |

After replacing the test's empty-directory removal with a nonrecursive removal,
the final concurrent contract verification ran under the same poisoned parent:

```powershell
C:/msys64/clang64/bin/ctest.exe --test-dir C:/pure-lang/task4-green -R 'pure-audio-(runner|cleanup)-contract' --parallel 2 -V
```

**2/2 passed**, 17.64 seconds (runner 17.63; cleanup 4.81). Exact summaries:

```text
RUNNER_CONTRACT_OK negative=23 positive=7 descendant_checks=1
CLEANUP_CONTRACT_OK negative=13 positive=2 unique_leaves=2
MAKE_CLEAN_CONTRACT_OK negative=4 positive=2
```

This is **40 rejected mutation cases and 11 valid cases**, plus the independent
descendant check. Runner negatives cover parser/exception diagnostics, wrong/
forged/duplicate/non-final completion, exit propagation, filled-pipe timeout,
inherited handles, exact/near notice rejection, real Pure parser/exception
failures, six reparse input classes, traversal, relative PATH, and fixed tokens.
Runner positives cover native/Pure pristine cases, environment removal,
directory write exclusion, exact notice allowance, hardware-helper loading,
and paths with spaces. Cleanup negatives cover empty/volume/root/outside/
noncanonical targets; missing, wrong, borrowed, and directory sentinels;
reparse descendant/leaf/ancestor targets; and a concurrently locked leaf.

```powershell
C:/msys64/clang64/bin/clang.exe --analyze -Xanalyzer -analyzer-output=text -std=c11 pure-audio/tests/run_pure_test.c
git diff --check
```

Both passed. Clang's analyzer emitted no diagnostics. Git emitted only the
repository's LF-to-CRLF working-copy notices, with no whitespace errors.
Tools: Clang 22.1.8, target `x86_64-w64-windows-gnu`; CMake 4.4.0;
Ninja 1.13.2; configured Pure 0.68.

## Debugging notes, self-review, and limits

- The sandbox prevented MSYS signal-pipe creation and stalled Ninja's compiler
  probe. Read-only process inspection identified the exact Task 4 CMake/Ninja
  pair; only those two processes were stopped. Approved unsandboxed local
  configure/build and Make-contract runs then passed. The failed sandbox runs
  are not GREEN evidence.
- Early pristine-run debugging found a leading command-line space (an empty
  CRT argv[0]), absent `using system` in the minimal Pure fixture, and a hidden
  `conhost.exe` created by `CREATE_NO_WINDOW`. Correct CRT quoting, the explicit
  import, and detached process creation resolved those observed causes.
- An initial sentinel restoration used text writing, which changed LF to
  CRLF. The contract now restores by exact binary copy. Production validation
  continues to require exact bytes.
- Self-review checked the complete native implementation, argument quoting,
  environment termination, token boundaries, stream limits, job admission and
  draining, sentinel sharing, retained path identities, deletion ordering,
  fixture completion positions, Make scope, and CMake registration. No
  temporary production mutation or debugging instrumentation remains.
- Hardware playback/capture was not exercised, and this task makes no ASan
  claim for the new launcher. The mandatory native harness retains its prior
  Task 3 resource/quarantine behavior. Callback consumption does not prove
  physical playback.
- The native runner accepts canonical drive paths (not UNC paths), caps paths
  at 4,095 wide characters, input handles at 8,192, and captures at 1 MiB per
  stream. Invalid/oversized inputs fail closed. Explicit input validation does
  not replace the exact runtime/source manifests planned for Tasks 5–7.
- Original scope followed the Task 4 file list: top-level package cleanup was
  hardened, while direct invocation of the four legacy subdirectory Make clean
  recipes was outside that initial change. Fix round 1 below closes this gap.
  The Windows-only runner contracts are registered only
  on Windows; other platforms retain module builds and the native fault test.
- Existing untracked workspace `build/` was preserved. Task 4 scratch evidence
  is outside the worktree under `C:/pure-lang/task4-normal`, `task4-green`, and
  `task4-poison`. No PE, install, archive, license, CI, or TODO-closure work was
  included.

## Fix round 1 — review corrections

Verification date: 2026-09-09, Europe/Prague. The approved review follow-up
expanded scope to all four direct subdirectory Make cleanup entry points and
required preservation of a drive-root executable's absolute parent. Receiving
code review, TDD, systematic debugging, and verification-before-completion were
used to reproduce the findings before correcting them.

### Changes and behavioral RED

- `fftw`, `samplerate`, `sndfile`, and `realtime` now enumerate their exact
  object/module names with nonrecursive `rm -f --`. `realclean` depends on
  `clean`; only samplerate/sndfile additionally remove their named generated
  interface. Every direct clean/realclean accepts only the literal suffixes
  `.dll`, `.so`, or `.dylib`, before any cleanup recipe executes.
- The same literal comparison also replaces the top-level word/filter guard.
  Review-driven boundary testing found that the previous guard accepted a real
  leading/trailing whitespace value. Make command-line assignments trim
  leading spaces, so whitespace cases use environment override (`-e`) to
  preserve the actual hostile value. Empty values use explicit `DLL=` because
  an empty Windows environment assignment removes the variable and can expose
  pkg-config's valid default. These are test-setup corrections, not product
  failures or passing evidence.
- The production PATH builder and native fixture share `executable_parent`.
  It retains the root separator for `C:\pure.exe` and `z:\pure.exe`, producing
  `C:\` and `z:\`, never the drive-relative `C:` or `z:`. A nested path with
  spaces verifies ordinary parent extraction. No drive-root fixture placement
  is required, and no new production runner option was introduced.

The following commands were run with `PATH`, `PURELIB`, `PURE_INCLUDE`, and
`PURE_LIBRARY` set to `C:/pure-lang/task4-poison`:

```powershell
C:/msys64/clang64/bin/ctest.exe --test-dir C:/pure-lang/task4-green -R pure-audio-cleanup-contract -V
C:/msys64/clang64/bin/ctest.exe --test-dir C:/pure-lang/task4-green -R pure-audio-runner-contract --output-on-failure
```

Actual test-first failures, before the corresponding behavior correction:

| Regression | Observed RED |
| --- | --- |
| Original direct cleanup recipes | 64 failures in the then-current 24 valid / 48 hostile matrix; all 24 valid cases lost unrelated neighbors and 40 hostile cases were accepted or mutated files; 1/1 CTest failed, 16.00 seconds total |
| Original top-level word/filter suffix guard, with a preserved environment value | `Make clean accepted unsafe suffix ' .dll'`; 1/1 failed, 5.61 seconds total |
| Original executable-parent truncation, extracted unchanged into the shared helper | 2 of 3 executable-parent boundary checks failed (both drive roots); 1/1 failed, 0.14 seconds total |

The direct matrix was subsequently expanded to eight hostile values per
directory/target, including both whitespace boundaries. The early command-line
leading-space attempt was not valid RED because Make had normalized its input.
An initial fixture build also exposed `_WIN32_WINNT` header ordering; its
definition was moved ahead of the shared standard header before obtaining the
behavioral root-parent RED. That compile failure is not counted as TDD evidence.

### Fresh final GREEN

The four-step runner/fixture rebuild passed with this environment and command:

```powershell
$env:MSYSTEM_PREFIX='C:/msys64/clang64'
$env:PKG_CONFIG_PATH='C:/pure-lang/pure/build/windows-clang64-prefix/lib/pkgconfig;C:/msys64/clang64/lib/pkgconfig'
$env:PATH='C:/pure-lang/pure/build/windows-clang64-prefix/bin;C:/msys64/clang64/bin;C:/Windows/System32;C:/Windows'
C:/msys64/clang64/bin/cmake.exe --build C:/pure-lang/task4-green --parallel 4
$env:PATH='C:/pure-lang/task4-poison'
$env:PURELIB='C:/pure-lang/task4-poison'
$env:PURE_INCLUDE='C:/pure-lang/task4-poison'
$env:PURE_LIBRARY='C:/pure-lang/task4-poison'
C:/msys64/clang64/bin/ctest.exe --test-dir C:/pure-lang/task4-green -L audio --output-on-failure
```

The first full verification was 5/6 because the test's empty environment value
was removed on Windows and pkg-config supplied a valid suffix. After correcting
the fixture to pass explicit `DLL=`, focused cleanup passed 1/1 (9.80 seconds
total), followed by the fresh full run above: **6/6 passed, 67.53 seconds**.

| Test | Seconds | Evidence |
| --- | ---: | --- |
| fault-bounds | 8.70 | 2,391 native checks; quarantine allocation delta 3 |
| load | 7.37 | Generated final token |
| processing | 10.08 | Generated final token |
| public-bounds | 10.98 | 24 checks and generated final token |
| runner-contract | 20.50 | 23 rejected / 7 valid cases; one descendant check; three parent-boundary checks |
| cleanup-contract | 9.89 | 13 rejected / 2 valid native cleanup cases; top-level Make 6 rejected / 2 valid; direct Make 64 rejected / 24 valid |

Exact summaries from the final `Testing/Temporary/LastTest.log`:

```text
EXECUTABLE_PARENT_BOUNDARIES_OK checks=3
RUNNER_CONTRACT_OK negative=23 positive=7 descendant_checks=1
CLEANUP_CONTRACT_OK negative=13 positive=2 unique_leaves=2
MAKE_CLEAN_CONTRACT_OK negative=6 positive=2
DIRECT_MAKE_CLEAN_CONTRACT_OK negative=64 positive=24
```

Totals: **106 rejected mutation cases and 35 valid cases**, plus **three
executable-parent boundary checks and one descendant-termination check**.
Direct Make coverage is all four directories times both targets times three
allowed suffixes (24), and all four times both targets times eight hostile
suffixes (64). Valid cleanup removes owned outputs while preserving unrelated
matching files and directories; rejected suffixes must leave output canaries
and unrelated matching files/directories intact. Interface retention/removal is
checked separately for clean/realclean.

The fresh Clang static-analyzer command shown earlier passed without diagnostics;
`git diff --check` passed (only LF-to-CRLF notices). Self-review examined the
complete nine-file fix diff: five Makefiles, the native runner source, both
contract scripts, and this report. It checked every enumerated output against
its local build recipe, all eight direct entry points, suffix-value transport,
negative canary preservation, generated-interface behavior, and the shared
helper's canonical-path precondition. No broad recursive cleanup glob or
temporary production mutation remains in these five Make cleanup targets.

The pre-existing untracked worktree `build/` is preserved. This round did not
rerun parallel contracts, hardware, or launcher ASan and makes no new claims
about those checks. The original platform/path/stream limits remain. No
subagents, merge, push, or TODO closure was performed.
