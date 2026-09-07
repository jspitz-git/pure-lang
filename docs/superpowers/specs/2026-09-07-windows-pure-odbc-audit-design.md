# TODO-32 Windows pure-odbc Audit Hardening Design

Date: 2026-09-07

## Objective

Reopen and harden TODO-32 so the native Windows `pure-odbc` package is
memory-safe on the audited ODBC paths and every portability, package, and CI
claim is enforced by an executable contract. The Windows package continues to
use the native 64-bit Microsoft ODBC Driver Manager and must not bundle
unixODBC, `odbc32.dll`, or any database driver.

## Compatibility

The public Pure API remains source-compatible. ODBC integer results that fit
the existing 32-bit Pure `int` representation keep that representation. Values
outside that range are returned as a 64-bit Pure integer instead of being
silently narrowed. Existing symbol names, tuple shapes, error constructors,
and optional Access Text Driver behavior remain unchanged unless a prior result
was produced by undefined behavior or an ignored ODBC error.

## Native ODBC Safety

Introduce a narrow internal ODBC dispatch table used by production code and
the native fault-injection tests. The production table points at the real
Windows ODBC entry points. Tests substitute only the calls needed to exercise
failure, truncation, large-value, and cleanup behavior while running the same
production implementations.

Correct the audited native defects:

- Preserve the actual `SQLGetData` return value and accept only explicitly
  supported success statuses before reading output storage.
- Split numeric and textual `SQLGetInfo` handling. Retry truncated textual
  values using validated, overflow-safe dynamic storage.
- Use `SQLLEN`, `SQLULEN`, and `SQLUSMALLINT` end-to-end, with checked
  conversions at Pure and ODBC boundaries.
- Use single cleanup paths for partially initialized connections, failed
  executions, bound arguments, statement cursors, and result metadata.
- Transfer result-set metadata ownership unconditionally across
  update-count/result-set transitions.
- Replace count-then-fill driver and data-source enumeration with dynamically
  growing single-pass collection that handles truncation and registry changes.
- Preserve `SQL_SUCCESS_WITH_INFO` diagnostics and check every column-binding
  result before reading bound storage.

Allocation arithmetic must be overflow-checked. Tests must be able to observe
resource acquisition and release counts without relying on process teardown.

## Test Architecture

Add a native fault-injection harness around the dispatch table. Each audited C
defect receives a regression that fails against the pre-fix behavior and
passes after the correction. Coverage includes:

- `SQL_ERROR`, `SQL_NO_DATA`, and `SQL_SUCCESS_WITH_INFO` for all `SQLGetData`
  conversion branches;
- long `SQLGetInfo` strings and invalid reported lengths;
- connection and execution failures after each acquired resource;
- failed parameter and result-column binding;
- binary, string, integer, bigint, floating-point, and SQL NULL parameters;
- the `update count -> result set` and `result set -> update count` sequences;
- parameter-number limits, large row counts, allocation failures, and
  diagnostic truncation.

The always-required Pure smoke test covers manager allocation, driver/data
source enumeration, and the expected DSN-free `IM002` diagnostic. The Access
Text Driver CSV scenario becomes a distinct CTest. It reports CTest `SKIP`
when and only when the exact 64-bit `Microsoft Access Text Driver (*.txt,
*.csv)` is unavailable; the runner must not relabel a skip as a pass.

All Pure runners receive explicit existing file paths, run from a neutral or
owned directory, replace rather than extend `PATH`, unset `PURELIB`, reject
unexpected stderr, and preserve useful stdout/diagnostics.

## Cleanup Safety

Destructive contract helpers share a root-safety implementation. The source
identity is derived from the helper location. The build identity is validated
against its regular `CMakeCache.txt`, case-insensitively on Windows. Builds
inside the source tree and any path with symlink, junction, or other reparse
components are rejected.

Contract roots and fixed test leaves are derived internally. Recursive reset
is permitted only for a validated leaf bearing the exact ownership sentinel;
new leaves receive the sentinel after validation. Non-destructive probes cover
source descendants, case-only aliases, reparse aliases, and damaged sentinels.

The legacy `make clean` guard accepts only the expected module suffix and
explicit generated artifacts. An isolated negative contract proves missing or
malformed Pure metadata cannot broaden deletion.

## PE and Runtime Contract

The Windows dependency verifier must:

- require existing regular tool and PE file inputs;
- parse and validate `llvm-readobj` output, including AMD64 architecture;
- compare normalized import sets exactly, not merely reject selected names;
- reject malformed, duplicate, missing, unexpected, or unknown records;
- recursively resolve every non-system import in the staged prefix;
- prove `ODBC32.dll` resolves to the native 64-bit Windows System32 component;
- reject any staged or recursively resolved unixODBC or bundled ODBC manager;
- verify the module, `libpure.dll`, `libgmp-10.dll`, and all other staged PE
  files participating in the closure.

The exact import sets are intentionally version-sensitive. A toolchain or SDK
update that changes them must fail until the package is re-audited.

## Install Contract

The install contract starts from a clean copy of the portable Pure prefix and
snapshots every relative file and SHA-256 hash. It installs the `runtime` and
`documentation` components separately, verifies the generated component
manifests, and proves that the complete post-install delta contains exactly
these ten owned files:

1. `lib/pure/odbc.dll`
2. `lib/pure/odbc.pure`
3. `share/doc/pure-odbc/README`
4. `share/doc/pure-odbc/COPYING`
5. `share/doc/pure-odbc/COPYING.LESSER`
6. `share/doc/pure-odbc/WINDOWS.md`
7. `share/doc/pure-odbc/examples/menagerie.pure`
8. `share/doc/pure-odbc/tests/smoke.pure`
9. `share/doc/pure-odbc/tests/data/people.csv`
10. `share/doc/pure-odbc/tests/data/Schema.ini`

Every pre-existing prefix file must remain present and byte-identical. Every
owned file must match its source or built artifact. The pre-existing GMP DLL
is reused byte-for-byte. No ODBC manager or driver is installed. Negative
mutations cover missing, extra, altered, and overwritten files outside former
name-based glob namespaces.

Installed verification runs staged `pure.exe` with `PURELIB` absent and
`PATH` limited to staged `bin` plus Windows system directories. It executes
the mandatory manager/diagnostic test and the exact staged PE verifier.

## Source Distribution

`make dist` must include all files needed for the supported Windows build,
tests, documentation, installation, and verification. An executable contract
creates the real archive, extracts it beneath a path containing spaces, deletes
the checkout-side driver, rejects symlinked required assets, and configures,
builds, tests, installs, and verifies using only extracted sources. Archive
contents and hashes are compared against the declared distribution inputs.

## Toolchain and CI

Strict audit mode accepts only the explicit Windows CLANG64 toolchain used by
the bundle: Clang 22, x86-64 Windows target, explicit `pkgconf`, `llvm-readobj`,
Ninja, MSYS `make`, staged Pure SDK, GMP runtime, Windows headers, and the
native ODBC import library. Normal upstream/non-Windows builds remain usable;
the strict restriction is enabled by the Windows audit configuration.

The Windows workflow must include `pure-odbc/**` and TODO-32 in both push and
pull-request filters. After the portable Pure SDK is staged, it configures a
strict Release build, builds with exactly four workers, runs the exact PE
target and all `odbc` tests, stages both install components into a fresh prefix,
and runs installed verification under the sanitized environment. Workflow YAML
is structurally validated with a real YAML parser rather than a source-text
grep test.

## Documentation and Closure

`WINDOWS.md` must say that the package relies on, but does not contain, the
native Windows ODBC Driver Manager. It records exact configure, build, test,
install, and verification commands, prerequisites, driver boundaries, skip
semantics, runtime sanitization, package ownership, and known limitations.

TODO-32 is reopened while implementation is in progress. Its historical log
is preserved and corrected by dated audit entries rather than rewritten. It is
closed with `Status: Closed on YYYY-MM-DD` only after all task reviews, a final
whole-branch review, a clean four-worker build, the full test suite, exact PE
and install checks, source-distribution validation, YAML validation, and
`git diff --check` pass.

## Out of Scope and Residual Boundaries

- No database driver is bundled, installed, or generally certified.
- No credentials, user/system DSNs, network database, or external server are
  required by mandatory tests.
- Supporting callback exceptions or redesigning the public Pure ODBC API is
  outside this audit.
- The exact Access Text Driver test remains optional and Windows-specific.
