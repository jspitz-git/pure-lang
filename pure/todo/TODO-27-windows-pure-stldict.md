# TODO-27 - Windows pure-stldict Package

Status: Open
Branch: todo/27-windows-pure-stldict

## Purpose

Build, validate, and package `pure-stldict` with the C++ runtime selected for the
portable Windows distribution.

## Scope

- Build all native components with one compatible CLANG64 C++ toolchain.
- Validate dictionary operations, iteration, ordering, and object lifetime.
- Reuse the distribution's existing C++ runtime DLLs.

## Task List

1. [x] Build the package against the staged Pure runtime.
2. [x] Audit C++ ABI and runtime DLL dependencies.
3. [x] Add focused dictionary and lifetime smoke tests.
4. [ ] Stage and validate the package outside MSYS2.

## Guardrails

- Do not mix incompatible C++ standard libraries in one process.
- Keep object ownership and exception handling valid across the module boundary.

## Validation Plan

- Exercise insertion, lookup, deletion, iteration, copying, and cleanup.
- Inspect PE imports and run with only staged runtime DLLs available.

## Progress Log

- 2026-07-25: Created as a base Windows package candidate.
- 2026-07-28: Added a CMake build for both native modules using C++17 and the
  staged Pure 0.68 runtime.
- 2026-07-28: Removed obsolete GNU-version guards around standard C++11
  `unordered_map::reserve` calls and made intentionally unused pretty-printer
  parameters explicit.
- 2026-07-28: Verified both the legacy Makefile and a clean CMake build with
  CLANG64 Clang 22.1.8 and `-Wall -Wextra -Werror`.
- 2026-07-28: Loaded `hashdict.dll` and `orddict.dll` from `C:\Windows` with
  `PATH` restricted to the clean build, portable Pure runtime, and Windows,
  then constructed both dictionary types.
- 2026-07-28: Confirmed that Clang targets `x86_64-w64-windows-gnu` and both
  native modules are x86-64 PE files exporting their complete C interfaces.
- 2026-07-28: Both modules import exactly `libpure.dll`, `libc++.dll`, and
  Windows/UCRT components; neither imports an MSYS runtime or a second C++
  standard library.
- 2026-07-28: The existing portable `libc++.dll` is x86-64, has only
  Windows/UCRT imports, and is byte-identical to the CLANG64 input with
  SHA-256
  `7344DAED05388589E9BD691ED1D30C568C374DA4B8B6A12E1502185948C03CD4`.
- 2026-07-28: The native code does not use C++ exceptions across the module
  boundary; ordered comparison failures use Pure's `pure_throw` API.
- 2026-07-28: Added a marker-checked CTest covering hash and ordered
  dictionaries, both multidict variants, insertion, lookup, update, deletion,
  copying, clear, membership, missing-key failure handling, reserve, ordering,
  iterator traversal/find/get/put/erase, and cleanup.
- 2026-07-28: The ordering test exposed that specializing `std::less` for a
  pointer key did not provide the required Pure-expression comparator with
  the current libc++. Replaced all `std` specializations with explicit
  hash/equality/order functors in the container types; ordered keys now
  reliably produce `[1,2,3]`.
- 2026-07-28: Verified iterator ownership by returning an iterator over a
  temporary dictionary and reading it after the creator returned, then
  exercised 250 hash and ordered dictionary destruction cycles. The complete
  strict CLANG64 CTest passes.
