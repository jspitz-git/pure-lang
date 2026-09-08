# Task 5 report — Strict toolchain and exact Windows PE closure

Date: 2026-09-09 (Europe/Prague). Base: `57ee5aca`.
Workspace: `C:/pure-lang/.worktrees/todo33-audit`.
Branch: `codex/todo33-audit`.

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
C:/msys64/clang64/bin/cmake.exe -DLLVM_READOBJ=C:/msys64/clang64/bin/llvm-readobj.exe -DAUDIO_MODULE_DIR=C:/pure-lang/task5-final -DPURE_AUDIO_CLANG64_PREFIX=C:/msys64/clang64 -DPURE_AUDIO_PURE_PREFIX=C:/pure-lang/pure/build/windows-clang64-prefix -DPURE_AUDIO_WINDOWS_SYSTEM_DIRECTORY=C:/Windows/System32 -DPURE_AUDIO_RUNTIME_MANIFEST=C:/pure-lang/task5-final/windows-runtime-sources.txt -P pure-audio/cmake/VerifyWindowsDependencies.cmake
```

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
