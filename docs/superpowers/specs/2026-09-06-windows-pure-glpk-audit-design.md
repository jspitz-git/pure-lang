# TODO-31 Windows pure-glpk Audit Hardening Design

## Goal

Make the closed TODO-31 contract reproducible and enforceable: `pure-glpk`
must build with the MSYS2 CLANG64 toolchain, produce a runtime independent of
MSYS2, reject stale native handles safely, and validate its exact installed
package in local tests and Windows CI.

## Scope

The work is limited to `pure-glpk`, its Windows CI integration, and the
TODO-31 record. It fixes the audited callback lifetime defect and closes the
validation gaps in the existing Windows package. It does not redesign the
public GLPK binding or change supported solver functionality.

## Callback lifetime

`mip_callback` will keep the public callback signature
`glp::mip_cb tree info`. The `tree` pointer remains valid only for the dynamic
extent of that callback, matching GLPK's ownership of `glp_tree`.

The native wrapper will retain the Pure pointer expression used for the
callback. After the callback returns, it will set that expression's pointer
payload to `NULL` before freeing the `tree_obj` wrapper. A callback may retain
the Pure value, but subsequent `glp::ios_*` calls will then fail ordinary
pointer validation without dereferencing freed storage. This preserves the
existing API while eliminating the use-after-free.

A real MIP callback regression will verify:

- callback invocation;
- propagation of `cb_info`;
- a valid `glp::ios_*` query during the callback;
- safe rejection of a retained `tree` handle after `glp::intopt` returns.

## Build-tree test isolation

CMake will resolve all required executables and runtime inputs explicitly.
Test runners will receive the Pure runtime directory, the module directory,
and the CLANG64 dependency directory as parameters. On Windows they will set
`PATH` to only those directories plus Windows system directories and clear
`PURELIB`; they will not append an ambient developer `PATH`.

The runners will execute from a neutral directory and reject both nonzero
exit status and unexpected stderr. Contract tests will cover missing required
arguments and prove that an ambient MSYS2 path is not needed.

## PE dependency contract

The PE verifier will parse `llvm-readobj --coff-imports` output and compare
case-insensitive, sorted import names against exact AMD64 import sets for:

- `glpk.dll`;
- `libglpk-40.dll`;
- `libcolamd.dll`;
- `libamd.dll`;
- `libsuitesparseconfig.dll`;
- `libomp.dll`;
- `libgmp-10.dll`;
- `zlib1.dll`.

The allowed sets include the observed Windows system and UCRT API-set DLLs.
Any missing or additional import fails. This turns the claimed dependency
closure into an exact, version-sensitive contract rather than a partial
allowlist plus blacklist.

## Install contract

CTest will install only the `pure-glpk` components into an isolated copy of a
known portable Pure prefix. The verifier will:

- require the exact package-owned file manifest;
- reject unexpected files within the package-owned module, documentation,
  examples, tests, and GLPK runtime namespace;
- compare SHA-256 hashes for every installed package artifact against its
  build or source input;
- prove that reused `libgmp-10.dll` and `zlib1.dll` are byte-identical to the
  selected CLANG64 runtime files;
- launch staged `pure.exe` from `C:\Windows` with `PURELIB` empty and a
  sanitized `PATH`;
- run the solver and callback regressions;
- run the exact PE import verifier over the staged binaries.

Contract-level negative tests will mutate representative inputs and prove
that the verifier rejects extra files, altered hashes, and unexpected PE
imports rather than merely exercising the success path.

## Source distribution

The legacy `make dist` manifest will include `CMakeLists.txt`, `WINDOWS.md`,
all CMake scripts, and test programs needed by the documented Windows flow.
A contract test will inspect the generated source archive or staging tree and
confirm that it can be configured without relying on files outside the
archive.

## Windows CI

The non-Linux release workflow will include `pure-glpk` and TODO-31 in its
path filters, install the CLANG64 GLPK package, and run one package contract
job after the portable Pure SDK is available. The job will configure and
build with four workers, execute the exact PE target, run all tests carrying
the `glpk` label, install into a fresh stage, and invoke the installed-package
verification.

## Documentation

`WINDOWS.md` will document the explicit tool paths, sanitized local test and
install commands, exact runtime ownership, and the source-distribution
contract. TODO-31 will record the audit findings, corrections, and fresh
validation evidence without erasing the original history.

## Verification criteria

The change is complete only when all of the following pass from a clean
build directory:

1. strict Release build with Clang warnings treated as errors;
2. exact Windows PE dependency verification;
3. every CTest carrying the `glpk` label with no ambient MSYS2 `PATH`;
4. isolated installation and exact manifest/hash verification;
5. callback lifetime regression, including a retained stale handle;
6. source-distribution contract test;
7. `git diff --check` and workflow syntax validation.
