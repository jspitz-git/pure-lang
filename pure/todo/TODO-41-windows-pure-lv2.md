# TODO-41 - Windows pure-lv2 Package

Status: Open
Branch: todo/41-windows-pure-lv2

## Purpose

Build, validate, and package `pure-lv2` after the required Windows Lilv/LV2
infrastructure is available.

## Scope

- Build the Pure-side module and generic LV2 plugin bridge with the
  distribution toolchain.
- Preserve the Unix `pure2lv2` script and add a native Windows command
  launcher which does not require an MSYS2 shell.
- Cover batch-compiled and source-loaded plugin generation, discovery,
  instantiation, ports, processing, errors, and cleanup.
- Package the generator and examples; keep generated test plugins as
  validation fixtures rather than installed third-party content.

## Task List

1. [x] Add the CLANG64 CMake build and Windows source compatibility.
2. [ ] Add the native Windows generator and correct Windows bundle/path
   handling for both compilation modes.
3. [ ] Generate batch and source fixtures, load them through staged
   `pure-lilv`, and audit their exports, imports, processing, and lifecycle.
4. [ ] Stage the module, bridge sources, generator, examples, documentation,
   and license; validate the relocated package outside MSYS2.

## Guardrails

- Do not claim compatibility with arbitrary plugins from a single test plugin.
- Keep real-time callbacks free of avoidable blocking or allocation regressions.
- Keep the compiler/toolchain an optional developer component; generated
  plugins must not require it at run time.
- Do not make plugin discovery depend on a machine-wide `LV2_PATH`.

## Validation Plan

- Generate one batch-compiled and one source-loaded gain plugin in controlled
  bundle roots.
- Discover both through `lilv::world_at`, instantiate them, process a fixed
  buffer, verify output, and unload.
- Inspect the `lv2` module and generated plugin PE files, including the
  required LV2 and Dynamic Manifest exports.
- Relocate the installed tree and repeat generation and host tests with
  `PURELIB` and `LV2_PATH` unset and `PATH` restricted to the bundle and
  Windows.

## Design Decision

The Windows generator will be a `pure2lv2.cmd` launcher backed by a PowerShell
script. It will resolve Pure, the installed bridge sources, headers, import
library, and an optional sibling `tools/bin/clang.exe` relative to its own
prefix. An explicit `PURE2LV2_CC` override remains available for developer
builds. MSYS2 is permitted as the build-time provider of Clang and LV2 headers,
but neither the generator process nor a generated plugin may depend on an
MSYS2 shell. Batch-generated plugins are the distribution default; source mode
is retained for development and receives Windows-aware path handling.

## Progress Log

- 2026-07-25: Created as a follow-up to the Windows `pure-lilv` package.
- 2026-07-29: Completed TODO-40 first, providing a staged, relocatable Lilv
  0.26.4 host with Dynamic Manifest support and deterministic `world_at`
  discovery.
- 2026-07-29: Selected a native `.cmd`/PowerShell generator so Windows users
  can build Pure LV2 bundles without invoking Bash. The compiler remains an
  optional developer dependency; produced plugins are runtime-only artifacts.
- 2026-07-29: Added the CLANG64 CMake build, a compile-only check of the
  generic plugin bridge, a sanitized module load test, and a PE32+ dependency
  audit. Replaced both Unix-only `alloca.h` includes on Windows; the clean
  build and all focused checks passed without compiler warnings.
- 2026-07-29: Added the native `pure2lv2.cmd`/PowerShell generator. Direct
  launcher help and both batch/source generation passed with a sanitized
  Windows `PATH`, explicit developer toolchain, and output bundles below a
  path containing spaces. Batch compilation uses relative temporary outputs
  to avoid Pure's unquoted internal `opt | llc` pipeline.
