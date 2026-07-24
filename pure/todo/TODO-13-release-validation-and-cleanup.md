# TODO-13 - Release Validation and Cleanup

Status: Open
Branch: todo/13-release-validation-and-cleanup

## Purpose

Complete the LLVM 22 migration by running broad validation, documenting the supported
toolchain, and removing superseded LLVM 2.x/3.x and Autoconf infrastructure. Success
means a clean CMake/Ninja build is the sole documented path and the full supported test
suite passes.

## Scope

- Run the complete corpus in Debug, sanitizer, and release configurations.
- Remove obsolete `ExecutionEngine`, LLVM compatibility macros, and build checks.
- Retire Autoconf/Makefile files only after feature and installation parity is confirmed.
- Update installation, development, bitcode, Faust, and debugging documentation.

## Task List

1. [x] Audit the tree for old JIT calls, LLVM version macros, and obsolete headers.
2. [x] Run the full tests and classify any remaining behavior differences.
3. [x] Verify build, test, install, uninstall, and installed-program execution.
4. [x] Update documentation for Clang/LLVM 22, CMake, Ninja, LLDB, and bitcode policy.
5. [ ] Remove superseded Autoconf and Makefile infrastructure after parity review.
6. [ ] Perform a clean-tree release build and close or create follow-up TODOs.

## Legacy LLVM Audit

The runtime still has a hybrid ORC/MCJIT architecture. `PureJit` owns current
interactive compilation units, but `interpreter::JIT` remains a live
`ExecutionEngine` created by `EngineBuilder`. It cannot be removed as dead code.

### Runtime-reachable MCJIT dependencies

| Area | Active dependency |
| --- | --- |
| Initialization and shutdown | `interpreter::init`, `init_jit_mode`, and the destructor create, configure, and delete `JIT` |
| Host globals | Stack, frame, and generated globals use `addGlobalMapping` and `updateGlobalMapping` beside ORC absolute symbols |
| Eager compilation | `jit_now` and `pure_interp_compile` materialize functions with `getPointerToFunction` |
| Batch definitions | The `dodefn(keep)` path still invokes generated initializers through MCJIT |
| Faust batch mode | Dispatch slots and functions use `getPointerToGlobal` and `getPointerToFunction`; interactive Faust already uses ORC |
| Environment cleanup | Legacy mappings are cleared while ORC generation trackers reclaim their own resources |
| Build linkage | `PureTargets.cmake` still requests the `ExecutionEngine` and `MCJIT` LLVM components |

There is no remaining `freeMachineCodeForFunction` call. Only an obsolete
comment and the Autoconf `LLVMFreeMachineCodeForFunction` probe remain.

### Compatibility inventory

`interpreter.hh` unconditionally defines `LLVM26`, `LLVM27`, `LLVM30`,
`LLVM31`, `LLVM32`, `LLVM33`, and `LLVM35`. The C++ tree contains 25 references
to these macros. For LLVM 22 they divide into:

- active modern branches whose behavior should become unconditional, including
  `CreatePHI`, object output, `deleteBody`, native-target initialization, and
  the current `EngineBuilder` path;
- compile-time-dead pre-LLVM-3.5 alternatives, including
  `ExistingModuleProvider`, old `ExecutionEngine::create` overloads,
  `GuaranteedTailCallOpt`, and the pre-LLVM-3.0 `CreatePHI` call;
- a MinGW LLVM 3.5 workaround and historical `opt -std-compile-opts` batch
  command which require platform and batch-output validation before removal.

`NEW_USER_ITERATOR` is another always-enabled LLVM 3.5 compatibility gate. Its
modern `Value::user_iterator` behavior can become unconditional. `LLVM_VERSION`
is current build metadata used in version and generated-file output, not a
compatibility gate, and must remain.

### Header and build-file classification

- `ExecutionEngine.h`, `MCJIT.h`, and the `TargetOptions.h` include in
  `interpreter.hh` support the live transitional engine and must remain until
  its consumers are migrated.
- `TargetOptions.h` includes in `pure.cc`, `pure_norl.cc`, and `runtime.cc` only
  support dead `GuaranteedTailCallOpt` branches and can be removed with those
  branches.
- ORC headers and `ExecutionEngine/JITSymbol.h` are current LLVM 22 dependencies;
  the latter supplies live `JITSymbolFlags` and is not legacy MCJIT residue.
- The legacy build consists of `configure.ac`, `acinclude.m4`, `Makefile.in`, and
  `examples/Makefile.in`. Its LLVM 2.5-3.5 tool search, removed-header probes,
  `jit` component selection, and version feature checks are obsolete, but the
  files stay until installation parity is verified in task 3.

The safe cleanup order is: collapse dead version gates, preserve their LLVM 22
behavior, migrate live materialization and host mappings to ORC, remove the
transitional engine and linked components, then retire Autoconf after parity
review.

## Full-test Classification

All ten focused integration tests pass in Debug and Release. The ASan/UBSan
preset initially had the Faust lifecycle test disabled; running its exact driver
under the sanitizer environment completed without a finding, so it is now
active. With sanitizer-specific bitcode and Faust timeouts raised to 300 seconds,
all ten ASan/UBSan integration tests pass in one 434-second CTest run.

The `pure-regression` test remains a harness and performance blocker rather than
a classified language or ORC behavior failure:

- the complete preset was started in all three configurations; bounded runs
  completed the prelude plus 1 Debug, 17 Release, and 6 ASan regression scripts
  before their 5- or 10-minute outer validation limits expired;
- every completed script produced a golden diff at minimum because 208 of 223
  checked `.pure` and `.log` files use CRLF while `core.autocrlf=input` leaves
  those endings in the Linux worktree and the current output uses LF;
- the lexer also treats the CR before a pragma newline as part of its token, so
  CRLF `--if` values and `--endif` lines produce unrecognized or unmatched
  pragma diagnostics that prefix every result;
- no completed diff or CTest output contained an assertion, crash, ASan, UBSan,
  or LeakSanitizer diagnostic;
- each isolated interpreter startup recompiles the prelude in roughly 28-85
  seconds, so the serial 97-input runner needs tens of minutes in Release and
  substantially longer under ASan.

The EOL handling and regression-runner duration must be fixed or explicitly
budgeted before the clean release validation in task 6. No unexplained disabled
test or sanitizer finding remains.

## Installation Validation

A fresh out-of-tree Release configuration used an isolated configure-time
prefix and built successfully with Ninja and one compile job. Its ten focused
integration tests passed before installation. CMake installs 28 manifest entries
covering the executable, versioned runtime library and symlinks, public header,
`pure_main.c` and `pure_main.o`, 19 Pure library scripts, pkg-config metadata,
and the manual page. This matches the legacy build's core installation set.

The installed `pure --version` reports Pure 0.68 and LLVM 22.1.8. With the
nonstandard temporary library directory supplied through `LD_LIBRARY_PATH`, the
installed interpreter locates its configured library scripts and executes
`examples/hello.pure`, printing `Hello, world!`. Its additional pragma output is
the CRLF issue already classified in task 2. `pkg-config` reports version 0.68
and the isolated include and library directories.

CMake now provides an `uninstall` target backed by `install_manifest.txt`. It
removes all installed files and symlinks, tolerates already absent files, and a
second invocation remains successful. It intentionally leaves empty parent
directories owned by the prefix.

The legacy build can optionally install Emacs and TeXmacs integrations. CMake
has no corresponding optional rules, and neither tool is installed on the
validation host. Task 5 must preserve these files or explicitly classify them
before removing the legacy build; this does not block verified core host parity.

## Supported Documentation

`INSTALL` now defines Clang/LLVM 22 with CMake and Ninja as the supported source
build. It documents presets and custom builds, serial compilation, focused and
full tests, sanitizer and leak modes, configure-time installation prefixes,
pkg-config, manifest uninstall, LLDB/Zed launch support, symbolic ORC
breakpoints, and opt-in JIT dumps. The README installation summary points to the
same workflow and no longer recommends Autoconf or LLVM 2.5-3.5.

The language manual now describes eager materialization without obsolete LLVM
version gates. Its active foreign-code sections require LLVM 22-compatible
bitcode, use `clang-22` and Flang 22 examples, explain target/data-layout
validation and cross-version incompatibility, and document transactional Faust
reload with explicit sample-format markers or recognized legacy metadata.
Historical release notes and glossary entries remain as history rather than
supported build instructions.

## Guardrails

- Do not remove the old build before the CMake path covers required installation assets.
- Do not close the migration with unexplained disabled tests or sanitizer findings.
- Keep unrelated historical project files and changelog entries intact.

## Validation Plan

- Configure and build from a fresh directory with each supported preset.
- Run `ctest --preset llvm22-debug --output-on-failure` and release/ASan equivalents.
- Run installation into a temporary prefix and execute the installed binary and examples.
- Search for `ExecutionEngine`, `freeMachineCodeForFunction`, and `LLVM2`/`LLVM3` macros.

## Open Questions

- Which operating systems and architectures are required for the first LLVM 22 release?
- Should any optional legacy feature be deferred to a separately numbered TODO?

## Progress Log

- 2026-07-22: Initial final-validation and cleanup plan created.
  - Validation:
    - Not run; this update creates planning documentation only.
- 2026-07-24: Audited legacy LLVM APIs, compatibility gates, headers, and build
  infrastructure. The audit distinguishes compile-time-dead LLVM 2.x/3.x
  branches from the runtime-reachable transitional MCJIT used by host mappings,
  eager compilation, batch definitions, and Faust batch mode.
  - Validation:
    - Searched C and C++ sources for `ExecutionEngine`, `EngineBuilder`, MCJIT
      mapping and materialization calls, and `freeMachineCodeForFunction`.
    - Counted 25 `LLVM26` through `LLVM35` references in C++ sources and
      classified their active and dead branches under LLVM 22.
    - Audited LLVM includes and confirmed that ORC's `JITSymbol.h` remains live.
    - Inventoried the four legacy build files and the obsolete LLVM probes in
      `configure.ac`.
    - No build or runtime validation was needed because this step changes audit
      documentation only.
- 2026-07-24: Ran the complete Debug, Release, and ASan CTest presets and
  classified the remaining regression-runner differences. All focused
  integration tests pass; ASan now runs Faust lifecycle instead of disabling it.
  - Validation:
    - `ctest --preset llvm22-debug --output-on-failure` passed its first ten
      tests; the outer 300-second limit expired during `pure-regression`.
    - `ctest --preset llvm22-release --output-on-failure` passed its first ten
      tests; the outer 600-second limit expired during `pure-regression`.
    - The initial complete ASan run passed all nine enabled tests without a
      finding and reached `pure-regression` before its 600-second outer limit.
    - The disabled Faust driver passed manually under the preset's ASan/UBSan
      environment, then passed as an enabled CTest test in 104 seconds.
    - `ctest --preset llvm22-asan -E pure-regression --output-on-failure`
      passed all ten integration tests in 434 seconds after increasing
      sanitizer integration-test timeouts to 300 seconds.
    - Bounded regression runs completed 1 Debug, 17 Release, and 6 ASan scripts
      after the prelude. Their diffs contain the classified CRLF EOL and pragma
      noise, with no crash or sanitizer signatures.
- 2026-07-24: Verified the CMake build, focused tests, installation metadata,
  installed interpreter, representative example, and manifest-based uninstall
  in an isolated prefix. Core host installation parity is complete.
  - Validation:
    - Fresh Release configure in `build/install-validation/build` with Clang 22,
      LLVM 22, Ninja, and a prefix under `build/install-validation/prefix`.
    - `cmake --build build/install-validation/build --parallel 1`
    - `ctest --test-dir build/install-validation/build -E pure-regression
      --output-on-failure` passed all ten tests in 164 seconds.
    - `cmake --install build/install-validation/build` installed 28 manifest
      entries with no path outside the temporary prefix.
    - Installed `pure --version` reported Pure 0.68 and LLVM 22.1.8.
    - Installed Pure ran `examples/hello.pure` and printed `Hello, world!`.
    - `pkg-config --modversion pure` reported 0.68; cflags and libraries used
      the temporary prefix.
    - The first `uninstall` removed every manifest file and symlink. A second
      invocation succeeded with all entries already absent.
    - Emacs and TeXmacs were unavailable; their optional legacy install rules
      remain a task 5 parity decision.
- 2026-07-24: Replaced the LLVM 3.4/Autoconf installation guide with the
  supported LLVM 22 CMake/Ninja workflow and synchronized the README and active
  bitcode, inline-code, eager-JIT, Faust, debugging, and uninstall guidance.
  - Validation:
    - Searched `INSTALL`, `README`, and active `pure.txt` sections for obsolete
      LLVM 2.x/3.x, llvm-gcc, DragonEgg, Autoconf, and GNU make instructions.
    - Confirmed current commands use the checked presets, Clang 22, LLVM 22,
      Ninja, LLDB 22, and the tested CMake install/uninstall targets.
    - Confirmed bitcode documentation covers target/data-layout rejection,
      resource ownership, and LLVM-major compatibility.
    - Confirmed Faust documentation covers sample-format validation,
      transactional replacement, live-instance protection, and rollback.
    - Confirmed `PURE_ATSCC`, `PURE_ATSCCOMP`, and `PURE_JIT_DUMP` names and
      values against their implementations.
    - Standalone `rst2html` validation is not applicable because `INSTALL` uses
      the Sphinx `highlight` directive; CMake has no documentation target.
    - No build was run because this step changes documentation only.
