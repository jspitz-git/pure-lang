# TODO-47 - Windows pure-reduce Package

Status: Open
Branch: todo/47-windows-pure-reduce

## Purpose

Determine a reproducible Windows build and packaging model for the large
`pure-reduce` integration.

## Scope

- Inventory the bundled Reduce/CSL sources, generated artifacts, tools, and licenses.
- Separate bridge requirements from the full computer-algebra runtime.
- Assess size, build time, relocatability, and maintenance cost.

## Task List

1. [x] Reproduce the complete dependency and generation pipeline on Windows.
2. [x] Build the bridge and required Reduce runtime components.
3. [x] Make runtime data and executable lookup relocatable.
4. [x] Add symbolic-algebra and lifecycle smoke tests.
5. [x] Decide whether to ship as a separate installer component or artifact.

## Guardrails

- Do not include an incomplete generated runtime.
- Preserve all upstream license and source-offer obligations.

## Validation Plan

- Run representative algebra, simplification, and error cases outside MSYS2.
- Measure installed size and test installation, upgrade, and removal separately.

## Open Questions

- Clean-runner evidence from the new GitHub Actions job is still pending.
- TODO-49 must consume `PureReduce` only as a separate optional installer
  component or downloadable artifact; it must not enter the default frontend
  installation.

## Packaging Decision

Ship PureReduce as the separately selected CMake component `PureReduce` and as
the CI artifact `windows-pure-reduce.zip`. The component is excluded from the
default install. Its current 80-file closure contains the Pure module, embedded
CSL runtime and image, runtime data, tests, inventory, metrics, patches and
license notices; it contains no full REDUCE frontend, `reduce.exe`, source
tree, development archive, MSYS2 tool, or non-system runtime DLL.

This is the installation contract for TODO-49. Upgrade and removal must use
the component's exact installed inventory as the ownership boundary and must
not delete unrelated files under the shared Pure prefix.

## Evidence

### Verified local Windows evidence

The local CLANG64 build and package verifier passed on 2026-08-17. These
measurements describe that successful local run, not a clean GitHub-hosted
runner:

| Measurement | Value |
| --- | ---: |
| exact REDUCE commit | `7efba90661139ae9c73c99fddd55f3fb2fabf69a` |
| exact REDUCE tree | `5573613a2f86efea75695fbe65a73317383884c1` |
| tracked-tree SHA-256 | `134a68fdb10403d3a4c69051eb4e133803ff2659784f2d38ac4d94c7ee9f86d8` |
| local partial-clone Git data | 402,235,138 bytes |
| canonical private source | 1,228,241,276 bytes |
| upstream build tree | 1,529,606,144 bytes |
| upstream build elapsed time | 2,477 seconds |
| upstream build workers | 1 |
| selected CSL closure | 106 objects |
| staged package | 15,155,926 bytes |
| staged package files | 80 |
| local ZIP | 9,349,478 bytes |
| local inner ZIP SHA-256 | `340cdc5ec7aa84ed4c22a8513355b0eaa7b9ab799efbb499522108472e2020df` |

The complete local `reduce`-label suite passed 19/19 tests. It covers the
exact source/patch/build contract, bridge ABI and lifecycle, symbolic algebra,
expected errors, UTF-8 relocation, recursive PE imports, optional component
selection, exact installed inventory, mutations, overlay/removal ownership and
relocation. The installed verifier accepts the exact unchanged layout and
reports 80 files.

The local ZIP writer consumed the verified file set in ordinal relative-path
order, assigned every ZIP entry the fixed timestamp
`2000-01-01T00:00:00+00:00`, and did not modify staged payload metadata. Two
independent archive creations produced the same byte count and SHA-256 above.
This proves deterministic packaging for the measured local payload; Task 8
must still record the separately built clean-runner payload and digest.

### Pending clean-runner evidence

The `windows-pure-reduce` job in
`.github/workflows/non-linux-release-validation.yml` performs a fresh exact-pin
fetch into a path with spaces, builds Pure and the complete headless CSL
closure with MSYS2 CLANG64, runs `ctest -L reduce`, installs and verifies only
`PureReduce`, creates `windows-pure-reduce.zip`, prints its inner SHA-256 and
uploads it with `actions/upload-artifact@v4`.

Until Task 8 records a successful clean run, the following values and links
remain deliberately unset:

- clean-runner fetch/source/build/stage/archive byte measurements;
- clean-runner elapsed time and confirmed runner worker count;
- clean-runner inner ZIP SHA-256;
- `actions/upload-artifact` artifact digest;
- workflow run and artifact URLs.

No URL, digest, or successful clean-runner claim is inferred from local
evidence. Status remains **Open** until Task 8 captures those results.

## Progress Log

- 2026-07-25: Created as a large optional Windows package investigation.
- 2026-08-17: Completed the exact-pin local Windows implementation and chose
  the separate optional `PureReduce` component/artifact model. Added build,
  package, relocation, lifecycle, inventory and licensing evidence. Clean
  GitHub-hosted runner evidence remains pending Task 8.
