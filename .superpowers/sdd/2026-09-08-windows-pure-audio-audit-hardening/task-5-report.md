# Task 5 report — Strict toolchain and exact Windows PE closure

Date: 2026-09-09 (Europe/Prague). Base: `57ee5aca`.
Workspace: `C:/pure-lang/.worktrees/todo33-audit`.
Branch: `codex/todo33-audit`.

Revision note: the original implementation and verification evidence below is
retained as history. The final section records review fix round 1 against
`b82a221456c5e8709c3cecb34afa0418bce44d48`, including its revised counts and
required standalone inspection-tool pin.

## Scope and implementation

The four planned files implement an opt-in strict configuration, exact PE
verification, and independent configure/PE mutation contracts. The normal
pkg-config and Threads configuration remains available with strict mode off;
the exact PE target and the two new audit contracts are registered only with
`PURE_AUDIO_STRICT_WINDOWS_AUDIT=ON`. No native audio/FFI behavior changed.

Strict configuration requires 28 explicit input declarations in addition to
the opt-in flag: compiler, Ninja, pkgconf, llvm-readobj, CLANG64/Pure prefixes,
authoritative System32 directory, Pure executable/include/header/import/runtime,
PortAudio/FFTW/samplerate/sndfile headers and import libraries, pthread header
and import library, GMP/MPFR headers, Windows SDK header, Make, shell, and the
complete runtime-source list. Tools/headers/import libraries have exact origins
relative to the declared prefixes. Every path is normalized and must exist as
the expected regular file/directory without a reparse endpoint or ancestor.

The Windows authority comes from the registered Windows installation, compared
to the explicit System32 input. The native Windows PowerShell executable below
that authority checks all reparse attributes. Strict configuration sanitizes
tool/probe environment variables, validates Clang 22 and the exact
`x86_64-w64-windows-gnu` target, Pure 0.68, LLVM 22, AMD64 import archive members,
and every declared runtime's AMD64 PE32+ headers. Import libraries must contain
actual short import members, not merely AMD64 object files.

The five module targets use absolute declared import libraries and includes.
A cache SHA-256 pin records all configured tool/header/library/path inputs and
the runtime-source hashes; reconfiguration rejects a changed pin. The
generated `windows-runtime-sources.txt` has 24 newline-terminated records:
`exact-name|canonical-source|SHA-256`. It includes Pure's executable and 23
runtime DLLs. Names, complete membership, origins, duplicate declarations,
record structure, and frozen hashes are checked on every PE verification.

The PE parser processes all `llvm-readobj --file-headers --coff-imports`
records with balanced sections, exactly one file/format/architecture/address
record, complete required header fields with valid values, and exactly one
name plus both RVAs per import block. It rejects delay imports (including
nonzero delay directories), unknown/truncated records, duplicate fields/imports,
malformed names, and case-insensitive MSYS/libgcc/libstdc++ names. Exact import
sets are checked against a frozen policy, never learned from the file being
verified.

Traversal starts with the five modules plus `pure.exe` and `libpure.dll`.
Every non-system import resolves through the declared mapping. The source
mode reads only those configured paths. Supplying `STAGE_PREFIX` switches
resolution entirely to `bin/<runtime>` and `lib/pure/<module>` below that
stage, requires source/stage SHA-256 equality, and rejects additional or
duplicate PEs anywhere in the stage. PE signatures are checked even on files
without .dll/.exe extensions. Directories are checked before descent so
junctions cannot become traversal routes.

The OS loader resolves each allowed system import using
`LoadLibraryExW(..., LOAD_LIBRARY_SEARCH_SYSTEM32)`. The returned module path
must remain under the authoritative System32 directory, with non-reparse
ancestors and AMD64 PE32+ bytes. All 14 UCRT contracts must resolve specifically
to that directory's `ucrtbase.dll`; this includes the private CRT contract.

## Test-first RED evidence

The independent fixtures were written before the production rewrite. Both
initial commands ran against the actual original build/modules and original
verifier:

```powershell
$env:MSYSTEM_PREFIX='C:/msys64/clang64'
$env:PKG_CONFIG_PATH='C:/pure-lang/pure/build/windows-clang64-prefix/lib/pkgconfig;C:/msys64/clang64/lib/pkgconfig'
$env:PATH='C:/pure-lang/pure/build/windows-clang64-prefix/bin;C:/msys64/clang64/bin;C:/Windows/System32;C:/Windows'
C:/msys64/clang64/bin/cmake.exe -DRED_ONLY=ON -DSOURCE_DIR=C:/pure-lang/.worktrees/todo33-audit/pure-audio -DCLANG64_PREFIX=C:/msys64/clang64 -DPURE_PREFIX=C:/pure-lang/pure/build/windows-clang64-prefix -DRUNNER=C:/pure-lang/task4-green/run_pure_test.exe -P pure-audio/tests/configure_contract.cmake
C:/msys64/clang64/bin/cmake.exe -DRED_ONLY=ON -DSOURCE_DIR=C:/pure-lang/.worktrees/todo33-audit/pure-audio -DMODULE_DIR=C:/pure-lang/task4-green -DCLANG64_PREFIX=C:/msys64/clang64 -DPURE_PREFIX=C:/pure-lang/pure/build/windows-clang64-prefix -DRUNNER=C:/pure-lang/task4-green/run_pure_test.exe -P pure-audio/tests/runtime_verifier_contract.cmake
```

Actual RED: missing-header configure exited **zero**, followed by
`RED: strict configure accepted undeclared Pure header`. The original PE
verifier also exited **zero** after the independently staged
`libvorbis-0.dll` was removed, followed by
`RED: verifier accepted missing staged transitive libvorbis-0.dll`.

The first sandbox configure attempt timed out in Ninja's compiler probe and
is not RED evidence. The local process-access retry above reproduced both
behavioral failures without that infrastructure error.

Additional tests found and corrected three header-field failures:

```powershell
C:/msys64/clang64/bin/ctest.exe --test-dir C:/pure-lang/task5-green -R pure-audio-runtime_verifier-contract --output-on-failure
```

Before the field correction the contract failed after 84.45 seconds with
`parser-missing-header-field;parser-unknown-header-field;parser-invalid-header-value`.
After the correction the same matrix passed (77.68 seconds, then-current
26 rejected cases and two pristine cases).

A later, independent extra PE with the extension `.payload` reproduced the
extension-only enumeration gap:

```powershell
C:/msys64/clang64/bin/cmake.exe '-DCASE_FILTER=pristine|extra-staged-renamed-pe' -DSOURCE_DIR=C:/pure-lang/.worktrees/todo33-audit/pure-audio -DMODULE_DIR=C:/pure-lang/task5-green -DCLANG64_PREFIX=C:/msys64/clang64 -DPURE_PREFIX=C:/pure-lang/pure/build/windows-clang64-prefix -DRUNNER=C:/pure-lang/task5-green/run_pure_test.exe -P pure-audio/tests/runtime_verifier_contract.cmake
```

RED named `extra-staged-renamed-pe`; after checking file signatures, the
same command passed with **one rejected mutation and two pristine cases**.

Self-review then independently compiled and archived an ordinary AMD64 C
object. Direct invocation of the real `audio_import_library` helper through
`C:/pure-lang/task5-plain-archive-red.cmake` reached
`RED: plain AMD64 static archive passed import-library validation`. The
strict-configure case also failed to produce the required early audit
rejection (it reached later compiler identification). The corrected gate
requires archive magic and an AMD64 short-import member:

```powershell
C:/msys64/clang64/bin/cmake.exe '-DCASE_FILTER=non-import|pristine' -DSOURCE_DIR=C:/pure-lang/.worktrees/todo33-audit/pure-audio -DCLANG64_PREFIX=C:/msys64/clang64 -DPURE_PREFIX=C:/pure-lang/pure/build/windows-clang64-prefix -DRUNNER=C:/pure-lang/task5-final/run_pure_test.exe -P pure-audio/tests/configure_contract.cmake
```

That focused GREEN reported **one rejected mutation and one pristine case**.

The compiler version/target fixtures and I386 archive use an owned copy of
the relevant toolchain files. Native `CreateSymbolicLinkW` with the
unprivileged-creation flag supplies real symbolic links; directory junctions
are tested separately. No actual installed compiler, header, library, or
runtime is modified.

## Fresh build and verification commands

An independent input fixture generated the complete explicit cache file:

```powershell
C:/msys64/clang64/bin/cmake.exe -DWRITE_PRESET_ONLY=ON -DPRESET_OUTPUT=C:/pure-lang/task5-inputs.cmake -DSOURCE_DIR=C:/pure-lang/.worktrees/todo33-audit/pure-audio -DCLANG64_PREFIX=C:/msys64/clang64 -DPURE_PREFIX=C:/pure-lang/pure/build/windows-clang64-prefix -DRUNNER=C:/pure-lang/task4-green/run_pure_test.exe -P pure-audio/tests/configure_contract.cmake
C:/msys64/clang64/bin/cmake.exe -S pure-audio -B C:/pure-lang/task5-final -G Ninja -C C:/pure-lang/task5-inputs.cmake
C:/msys64/clang64/bin/cmake.exe --build C:/pure-lang/task5-final --parallel 4
C:/msys64/clang64/bin/cmake.exe --build C:/pure-lang/task5-final --target verify-windows-dependencies --parallel 4
```

The never-before-used `task5-final` Release build configured successfully,
built all **18/18** steps without compiler diagnostics, and its PE target
reported **PE_CLOSURE_OK count=29**. Both targets were rerun with exactly four
workers after the final self-review correction; regeneration and PE
verification passed and no native rebuild was required.

```powershell
$env:PATH='C:/pure-lang/task4-poison'
$env:PURELIB='C:/pure-lang/task4-poison'
$env:PURE_INCLUDE='C:/pure-lang/task4-poison'
$env:PURE_LIBRARY='C:/pure-lang/task4-poison'
$env:MSYSTEM_PREFIX='C:/pure-lang/task4-poison'
$env:PKG_CONFIG_PATH='C:/pure-lang/task4-poison'
C:/msys64/clang64/bin/ctest.exe --test-dir C:/pure-lang/task5-final -L audio --output-on-failure
C:/msys64/clang64/bin/ctest.exe --test-dir C:/pure-lang/task5-final -L audio --parallel 2 --output-on-failure
```

The first fresh sequential run passed **8/8**, 185.22 seconds, with the
then-current configure matrix at 73 rejections. The final two-worker result
and exact final counts are recorded below after completion.

The final complete two-worker run passed **8/8**, **112.57 seconds** wall time
(223.86 seconds summed test time), after all production changes:

| Test | Seconds | Final evidence |
| --- | ---: | --- |
| configure-contract | 45.34 | 74 rejected mutations, two pristine configurations |
| runner-contract | 25.33 | 23 rejected / seven pristine; three parent boundaries; one descendant check |
| cleanup-contract | 10.51 | 13 rejected / two valid owned leaves; Make 6 rejected / two valid; direct Make 64 rejected / 24 valid |
| public-bounds | 12.06 | 24 public checks and generated final token |
| runtime_verifier-contract | 102.06 | 36 rejected mutations, two pristine manifests, 29 PEs |
| processing | 11.59 | Generated final token |
| fault-bounds | 9.25 | 2,391 checks; intentional quarantine allocation delta three |
| load | 7.72 | Generated final token |

Exact Task 5 summaries from the final `Testing/Temporary/LastTest.log`:

```text
CONFIGURE_CONTRACT_OK negative=74 positive=2
RUNTIME_VERIFIER_CONTRACT_OK negative=36 positive=2 pe_count=29
```

Task 5 adds **110 rejected mutation cases and four pristine cases**. The full
suite combines these with Task 4's 106 rejected / 35 valid cases, for **216
rejected and 39 valid contract cases**, plus the three parent-boundary checks
and one descendant-termination check. The exact configure and PE commands
above also passed with the real tools, independently of the mutation transport.

The configure matrix covers every missing explicit input, ten representative
tool/header/import/runtime inputs as missing/directory/wrong-origin cases,
malformed/duplicate/incomplete/unknown runtime declarations, compiler version
and target, I386 and non-import AMD64 archives, wrong-machine runtime, actual
symbolic-link/junction paths, conflicting compiler flags/target/toolchain,
changed immutable pin, hostile inherited discovery variables, and normal
upstream discovery. The runtime matrix covers complete parser records and
headers, all specified forbidden import classes, missing/unknown/duplicate
imports, delay imports, missing transitive stage files with host copies present,
extra and renamed PEs, duplicate origins/declarations, malformed/missing/altered
source manifests, libpure transitive imports, foreign System32, staged symlink/
junction inputs, and altered staged hashes. Each case changes independent
fixture data; no expected import table is imported from production.

`git diff --check` passed after the final code changes (only Git's ordinary
LF-to-CRLF notices). No whitespace error or compiler diagnostic was reported.

Tools: **Clang 22.1.8** targeting **x86_64-w64-windows-gnu**,
**llvm-readobj 22.1.8**, **CMake 4.4.0**, **Ninja 1.13.2**,
**pkgconf 3.0.4**, **Pure 0.68** compiled with LLVM 22.1.8.
Dependency versions observed with pkgconf: PortAudio **19**, FFTW **3.3.11**,
libsamplerate **0.2.2**, libsndfile **1.2.2**.
Authoritative `ucrtbase.dll` file version:
**10.0.26100.8875 (WinBuild.160101.0800)**.

## Exact PE imports and origins

There are **29 non-system PEs**: five module DLLs, the Pure executable, and
23 runtime DLLs. Origin abbreviations below are exact directory prefixes,
with the row's filename appended:

- B = `C:/pure-lang/task5-final/`
- P = `C:/pure-lang/pure/build/windows-clang64-prefix/bin/`
- C = `C:/msys64/clang64/bin/`

Every item in the CRT column expands to
`api-ms-win-crt-<item>-l1-1-0.dll`. The CRT and Other columns together are
the **complete** import set, lowercased only for case-insensitive comparison.
These rows were freshly collected from the actual PEs with llvm-readobj;
they were not obtained by asking the verifier for its expected values.

| PE | Origin | CRT contracts | Other imports |
| --- | --- | --- | --- |
| audio.dll | B | heap,private,runtime,stdio,string | kernel32.dll,libportaudio.dll,libpure.dll,libwinpthread-1.dll |
| fftw.dll | B | math,private,runtime,stdio,string | kernel32.dll,libfftw3-3.dll |
| srcprocess.dll | B | private,runtime,stdio,string | kernel32.dll,libpure.dll,libsamplerate-0.dll |
| sfinfo.dll | B | heap,private,runtime,stdio,string | kernel32.dll,libpure.dll,libsndfile-1.dll |
| realtime.dll | B | private,runtime,stdio,string | kernel32.dll,libpure.dll,libwinpthread-1.dll |
| pure.exe | P | convert,environment,filesystem,heap,locale,math,private,runtime,stdio,string | kernel32.dll,libc++.dll,libpure.dll,libreadline8.dll |
| libpure.dll | P | convert,environment,filesystem,heap,locale,math,private,process,runtime,stdio,string,time,utility | advapi32.dll,kernel32.dll,libc++.dll,libgmp-10.dll,libiconv-2.dll,libmpfr-6.dll,libpcreposix-0.dll,libwinpthread-1.dll,libzstd.dll,ntdll.dll,ole32.dll,shell32.dll,zlib1.dll |
| libc++.dll | P | convert,environment,filesystem,heap,locale,math,multibyte,private,runtime,stdio,string,time,utility | kernel32.dll |
| libgmp-10.dll | P | convert,environment,filesystem,heap,locale,private,runtime,stdio,string,time,utility | kernel32.dll |
| libiconv-2.dll | P | convert,heap,locale,private,runtime,stdio,string,utility | kernel32.dll |
| libmpfr-6.dll | P | convert,filesystem,heap,locale,private,runtime,stdio,string,utility | kernel32.dll,libgmp-10.dll |
| libpcre-1.dll | P | heap,private,runtime,stdio,string,utility | kernel32.dll |
| libpcreposix-0.dll | P | convert,heap,locale,private,runtime,stdio,string,utility | kernel32.dll,libpcre-1.dll |
| libreadline8.dll | P | convert,environment,filesystem,heap,locale,math,private,runtime,stdio,string,utility | kernel32.dll,libtermcap-0.dll,user32.dll |
| libtermcap-0.dll | P | convert,environment,filesystem,heap,locale,private,runtime,stdio,string,time | kernel32.dll |
| libwinpthread-1.dll | P | convert,heap,private,runtime,stdio,string,utility | kernel32.dll |
| libzstd.dll | P | convert,filesystem,heap,locale,private,runtime,stdio,string,time,utility | kernel32.dll |
| zlib1.dll | P | convert,heap,locale,private,runtime,stdio,string,utility | kernel32.dll |
| libportaudio.dll | C | convert,filesystem,heap,locale,private,runtime,stdio,string,utility | advapi32.dll,kernel32.dll,libc++.dll,ole32.dll,setupapi.dll,user32.dll,winmm.dll |
| libfftw3-3.dll | C | convert,filesystem,heap,locale,math,private,runtime,stdio,string,utility | kernel32.dll |
| libsamplerate-0.dll | C | environment,heap,private,runtime,stdio,string,time,utility | kernel32.dll |
| libsndfile-1.dll | C | convert,environment,filesystem,heap,locale,math,private,runtime,stdio,string,time,utility | kernel32.dll,libflac.dll,libmp3lame-0.dll,libmpg123-0.dll,libogg-0.dll,libopus-0.dll,libvorbis-0.dll,libvorbisenc-2.dll |
| libogg-0.dll | C | heap,private,runtime,stdio,string,utility | kernel32.dll |
| libvorbisenc-2.dll | C | environment,heap,private,runtime,stdio,string,time,utility | kernel32.dll,libvorbis-0.dll |
| libFLAC.dll | C | convert,filesystem,heap,locale,math,private,runtime,stdio,string,time,utility | kernel32.dll,libogg-0.dll,libwinpthread-1.dll |
| libopus-0.dll | C | convert,filesystem,heap,locale,math,private,runtime,stdio,string,utility | kernel32.dll |
| libmpg123-0.dll | C | convert,environment,filesystem,heap,locale,math,private,runtime,stdio,string,utility | kernel32.dll,shlwapi.dll |
| libmp3lame-0.dll | C | convert,environment,filesystem,heap,locale,math,private,runtime,stdio,string,time,utility | kernel32.dll |
| libvorbis-0.dll | C | environment,heap,math,private,runtime,stdio,string,time,utility | kernel32.dll,libogg-0.dll |

The complete system-import set has **23 names**: the 14 CRT names
`convert,environment,filesystem,heap,locale,math,multibyte,private,process,runtime,stdio,string,time,utility`
and `advapi32.dll,kernel32.dll,ntdll.dll,ole32.dll,setupapi.dll,shell32.dll,shlwapi.dll,user32.dll,winmm.dll`.
The OS resolved the former to `C:/Windows/System32/ucrtbase.dll` and each
latter name to its same-name regular AMD64 System32 DLL. Thus the 23 names
resolve to ten distinct authoritative system files.

## Consumer interface, self-review, and boundaries

Tasks 6–8 can call the standalone verifier with these complete explicit
arguments, optionally adding `-DSTAGE_PREFIX=<installed-prefix>`:

```powershell
C:/msys64/clang64/bin/cmake.exe -DLLVM_READOBJ=C:/msys64/clang64/bin/llvm-readobj.exe -DPURE_AUDIO_LLVM_READOBJ_SHA256=040c4cb0740d2a9d9f7b488bc676c0406eb12c7b349acba1797c2f58865087cb -DAUDIO_MODULE_DIR=C:/pure-lang/task5-fix1 -DPURE_AUDIO_CLANG64_PREFIX=C:/msys64/clang64 -DPURE_AUDIO_PURE_PREFIX=C:/pure-lang/pure/build/windows-clang64-prefix -DPURE_AUDIO_WINDOWS_SYSTEM_DIRECTORY=C:/Windows/System32 -DPURE_AUDIO_RUNTIME_MANIFEST=C:/pure-lang/task5-fix1/windows-runtime-sources.txt -P pure-audio/cmake/VerifyWindowsDependencies.cmake
```

The inspection-tool hash above is the value recorded in the fresh configured
build's `PURE_AUDIO_LLVM_READOBJ_SHA256` internal cache entry. Consumers must
pass that configured pin unchanged, not accept a newly computed replacement
hash at verification time.

The source manifest stays attached to the configured build. Staged mode
does not permit an omitted staged file to resolve from that manifest's host
source: the sources establish byte identity, while all resolution comes from
the stage. Module hashes compare against the built module outputs because
those outputs do not yet exist at configure time.

Self-review examined the entire four-file diff, every strict cache input,
normal/strict configuration separation, archive member architecture and
identity, exact runtime membership and source hashing, full parser record
consumption and field completeness, recursive dependency visitation, complete
stage enumeration, source/stage hash equality, authoritative API-set
resolution, and the mutation producer's independence. It confirmed the
contracts use real files/PE records and exact owned leaves, preserve neighboring
files, and never alter installed inputs. No temporary production mutant remains.

The existing native harness retains Task 3's intentional backend quarantine;
its allocation delta of three is not a Task 5 leak. Hardware playback/capture,
ASan, install component manifests/licenses, source archives, CI, and TODO closure
were not rerun or implemented here. Their existing task boundaries remain.
The legacy install metadata now receives the frozen strict MSYSTEM prefix;
the planned exact installation/license rewrite still belongs to Task 6.

The PE/import policy and copied test-tool dependency names are deliberately
version-sensitive. An updated toolchain, runtime payload, or Windows API-set
mapping requires a new audit. Paths are validated for each invocation; this
CMake verifier does not retain native file-identity locks across its whole
inspection and assumes the declared source trees remain stable during the
read-only run. The native runner's separate handle/cleanup protections remain.

Successful contract leaves are removed through the Task 4 ownership runner;
failed leaves are retained as diagnostic evidence outside the worktree under
the explicitly created `task5-green`/`task5-final` build roots. Existing
untracked worktree `build/` is preserved. No subagents, merge, push, unrelated
source changes, or TODO closure were performed.

## Review fix round 1 — build environment, all configurations, tool identity

All three Important findings were reproduced and addressed within the same
four scoped implementation/test files. The fix keeps non-strict configuration
unchanged and introduces no wrapper that substitutes for the validated Clang
executable.

### Additional RED evidence

The first flag regression run accepted these seven mutations with configure
exit zero: `CMAKE_C_FLAGS_RELEASE`, `CMAKE_C_FLAGS_RELWITHDEBINFO`,
`CMAKE_MODULE_LINKER_FLAGS_RELEASE`, `CMAKE_SHARED_LINKER_FLAGS_DEBUG`,
`CMAKE_EXE_LINKER_FLAGS_MINSIZEREL`, `CMAKE_SYSROOT_COMPILE`, and
`CMAKE_C_COMPILER_LAUNCHER_RELEASE`. The C flags inject an absolute `-include`
header; the linker flags inject an undeclared `-L` directory. Evidence remains
at `C:/pure-lang/task5-final/pure-audio-contract-root/run-8b363fa603cc05caec83dd01c6ad09b0`.

The initial poisoned build fixture used the same directory for CPATH and
C_INCLUDE_PATH. Clang deduplicated it as a system directory, so it did not
reproduce the reported shadow-header failure. That was a fixture defect,
not valid RED evidence. Giving every environment variable a distinct path
produced the required real build failure:

```powershell
C:/msys64/clang64/bin/cmake.exe '-DCASE_FILTER=pristine-explicit|build-ambient' -DSOURCE_DIR=C:/pure-lang/.worktrees/todo33-audit/pure-audio -DCLANG64_PREFIX=C:/msys64/clang64 -DPURE_PREFIX=C:/pure-lang/pure/build/windows-clang64-prefix -DRUNNER=C:/pure-lang/task5-final/run_pure_test.exe -P pure-audio/tests/configure_contract.cmake
```

The pristine configure passed; the actual `cmake --build ... --parallel 4`
failed. Ninja's absolute Clang command included the declared Pure include
directory, but CPATH selected the independent
`build-poison/CPATH/pure/runtime.h`, emitting
`error: AUDIO_UNDECLARED_BUILD_HEADER` from audio, samplerate and sndfile.
The command exited 1 with `Configure contract failures: build-ambient`.
The preserved leaf is
`C:/pure-lang/task5-final/pure-audio-contract-root/run-9758a0b31b3fd7e5869d575a2f08ca20`.

Before the public-verifier fix, running `runtime_verifier_contract.cmake`
with `-DCASE_FILTER=tool-foreign-origin` accepted the sidecar-record reader
executable as `LLVM_READOBJ`. The contract exited 1 with
`Runtime verifier accepted mutations: tool-foreign-origin`; evidence remains
under `C:/pure-lang/task5-final/pure-audio-contract-root/run-1350cd0f62c0344cf3ed6cbc1a942b4d`.
The final origin test uses a copied genuine llvm-readobj executable and its
correct hash, so rejection specifically proves the canonical origin check.

### Fixes and self-review

- Both `CMAKE_C_COMPILER_LAUNCHER` and `CMAKE_C_LINKER_LAUNCHER` are generated
  as the canonical declared `<CLANG64>/bin/cmake.exe -E env ... --`, followed
  by the original absolute validated `clang.exe` command. Every actual build
  invocation clears compiler/header/library discovery and Clang option
  overrides and sets PATH to the frozen Pure/CLANG64/System32 directories.
  The launcher path, launcher arguments, and CMake executable SHA-256 are
  included in the immutable configured-input pin. Clang's implicit default
  config files are disabled by fixed `--no-default-config` flags during
  probes, compilation, linking, version/target and resource-directory queries.
- The flag gate enumerates all defined C/configuration and EXE/SHARED/MODULE/
  STATIC link-flag variables. Generic and all four standard configurations
  must equal fixed defaults; unknown configurations and `_INIT` variants are
  rejected. All launcher/sysroot suffixes, compiler argument/external-toolchain
  overrides, standard include/library overrides, rule overrides and project
  hooks are rejected or fixed. Selected configuration and every fixed flag
  are part of the pin. A new successful reconfigure regression initially
  exposed CMake's generated standard-library cache value; that exact library
  list is now fixed and pinned, and the reconfigure passes.
- Standalone verification now validates llvm-readobj's canonical exact
  CLANG64 origin, non-reparse path, configured SHA-256 and LLVM major 22 before
  inspecting any PE. The parser mutation seam is a function override in an
  explicitly included, test-owned driver. The production `-P` entry point
  cannot enable helpers-only mode, and no CLI variable selects recorded
  records. Real standalone pristine/stage/hash/origin cases invoke the real
  inspection tool. Tests cover wrong origin, wrong/missing pin, altered tool
  bytes after pinning, wrong LLVM major and attempted CLI helper bypass.

Self-review read the complete fix diff, checked the actual generated Ninja
compile and link commands, fixed-default reconfiguration, configuration
coverage, real-vs-recorded test routing, configured pin propagation and the
unchanged exact import policy. Source stability/TOCTOU remains the documented
boundary above: native file locks across every compiler/verifier subprocess
are not introduced by this CMake-only task. No production fixture, source
mutation, broadened task scope, merge, push or subagent remains.

### Final fresh GREEN evidence

All commands ran from the stated worktree with the native process-access
approval needed for Ninja/Windows child-process execution. The build root was
fresh, `C:/pure-lang/task5-fix1`; the independent preset was regenerated by
the contract producer in the original Task 5 run and contains only explicit
input declarations, Release and BUILD_TESTING.

```powershell
C:/msys64/clang64/bin/cmake.exe -S pure-audio -B C:/pure-lang/task5-fix1 -G Ninja -C C:/pure-lang/task5-inputs.cmake

$env:CPATH='C:/pure-lang/task5-final/pure-audio-contract-root/run-9758a0b31b3fd7e5869d575a2f08ca20/build-poison/CPATH'
foreach ($auditPoisonVariable in @('C_INCLUDE_PATH','CPLUS_INCLUDE_PATH','OBJC_INCLUDE_PATH','LIBRARY_PATH','COMPILER_PATH','GCC_EXEC_PREFIX','INCLUDE','LIB','LIBPATH','CL','_CL_','LINK','_LINK_','CCC_ADD_ARGS','SDKROOT','DEVELOPER_DIR','CLANG_CONFIG_FILE_SYSTEM_DIR','CLANG_CONFIG_FILE_USER_DIR')) { [Environment]::SetEnvironmentVariable($auditPoisonVariable, 'C:/pure-lang/task4-poison/' + $auditPoisonVariable, 'Process') }
$env:CCC_OVERRIDE_OPTIONS='+--audio-audit-invalid-ambient-option'
$env:PATH='C:/pure-lang/task4-poison'
C:/msys64/clang64/bin/cmake.exe --build C:/pure-lang/task5-fix1 --parallel 4 --verbose
```

Configure exited zero. The separate poisoned build process exited zero after
all **18/18 steps**, with no diagnostics. The verbose transcript explicitly
shows `ninja.exe -v -j 4`, nine compile commands and nine link commands using
the generated CMake environment launcher and original absolute Clang path.
This is the same real shadow-header fixture that failed before the fix;
the invalid ambient Clang option would also fail any unprotected driver call.

The following PE invocation used the ordinary shell environment (a separate
process from the intentionally poisoned build):

```powershell
C:/msys64/clang64/bin/cmake.exe --build C:/pure-lang/task5-fix1 --target verify-windows-dependencies --parallel 4
```

It exited zero with `PE_CLOSURE_OK count=29; AMD64 PE32+; UCRT resolved by
Windows loader`. All exact imports match the complete 29-row table above;
the final module origin B is now `C:/pure-lang/task5-fix1/`, while P and C
are unchanged. All 14 CRT contracts again resolved to System32/ucrtbase.dll,
and the other nine allowed system names resolved to their authoritative
same-name System32 DLLs.

The complete suite ran in another process with deliberately poisoned runtime
and discovery variables:

```powershell
foreach ($auditRuntimeVariable in @('PATH','PURELIB','PURE_INCLUDE','PURE_LIBRARY','MSYSTEM_PREFIX','PKG_CONFIG_PATH')) { [Environment]::SetEnvironmentVariable($auditRuntimeVariable, 'C:/pure-lang/task4-poison', 'Process') }
C:/msys64/clang64/bin/ctest.exe --test-dir C:/pure-lang/task5-fix1 -L audio --parallel 2 --output-on-failure
```

Result: **8/8 passed, 0 failed, 149.44 seconds**. Fresh
`C:/pure-lang/task5-fix1/Testing/Temporary/LastTest.log` records:

```text
AUDIO_FAULT_HARNESS_OK 2391 checks quarantine_allocation_delta=3
PURE_AUDIO_BOUNDS_OK 24 checks
CLEANUP_CONTRACT_OK negative=13 positive=2 unique_leaves=2
MAKE_CLEAN_CONTRACT_OK negative=6 positive=2
DIRECT_MAKE_CLEAN_CONTRACT_OK negative=64 positive=24
EXECUTABLE_PARENT_BOUNDARIES_OK checks=3
RUNNER_CONTRACT_OK negative=23 positive=7 descendant_checks=1
CONFIGURE_CONTRACT_OK negative=120 positive=4
RUNTIME_VERIFIER_CONTRACT_OK negative=42 positive=3 pe_count=29
```

The configure contract took 88.94 seconds and includes all 25 generic/config
C/link flag positions, all ten compiler/linker launcher positions, remaining
toolchain and unknown/init variants, the real four-worker poisoned build,
unchanged strict reconfigure, and normal upstream configure. The runtime
contract took 109.02 seconds and includes the six new production-entry-point
identity/bypass negatives. Task 5 now has **162 rejected / 7 valid** cases;
combined with Task 4, the suite has **268 rejected / 42 valid** contract cases,
plus the three parent-boundary checks and one descendant check.

Versions freshly reconfirmed: Clang/LLVM **22.1.8**, exact target
**x86_64-w64-windows-gnu**, CMake **4.4.0**, Ninja **1.13.2**, pkgconf **3.0.4**,
Pure **0.68** (LLVM 22.1.8), PortAudio **19**, FFTW **3.3.11**, libsamplerate
**0.2.2**, libsndfile **1.2.2**, System32 UCRT **10.0.26100.8875**.

The final configured-input pin is
`6bde281f59d40841b7b4d7c9bbfd55a6a4032e64c4c26a56cf5808881a609494`.
The pinned environment-launcher CMake executable SHA-256 is
`86ece838d82e39179f456f615cbd4ff45a14b7373dbf97ebf94797c65715d0bd`.
The configured LLVM inspection-tool SHA-256 is
`040c4cb0740d2a9d9f7b488bc676c0406eb12c7b349acba1797c2f58865087cb`.

Final `git diff --check` passed. Successful owned contract leaves were cleaned;
the earlier RED leaves remain outside the worktree for evidence. The existing
untracked worktree `build/` was neither modified nor removed. No additional
concern remains beyond the already documented source-stability, toolchain
version-sensitivity and later-task boundaries.
