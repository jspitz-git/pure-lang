# TODO-47 - Windows pure-reduce Package

Status: Closed
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

- TODO-49 must consume `PureReduce` only as a separate optional installer
  component or downloadable artifact; it must not enter the default frontend
  installation.

## Packaging Decision

Ship PureReduce as the separately selected CMake component `PureReduce` and as
the CI artifact `windows-pure-reduce.zip`. The component is excluded from the
default install. Its current 81-file closure contains the Pure module, embedded
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
This proves deterministic packaging for that historical local payload; the
separately built clean-runner payload and digest are recorded below.

### Verified clean-runner evidence

The required Windows PureReduce job passed from implementation commit
`7c0b064c56d0f8186ef86903917a03b3e5ba0b43` on 2026-08-18:

- workflow run: [32080639311](https://github.com/jspitz-git/pure-lang/actions/runs/32080639311);
- Windows job: [95542811896](https://github.com/jspitz-git/pure-lang/actions/runs/32080639311/job/95542811896), `success` in 2,548 seconds;
- artifact: `windows-pure-reduce`, ID `9305888161`, [immutable artifact API URL](https://api.github.com/repos/jspitz-git/pure-lang/actions/artifacts/9305888161/zip);
- exact REDUCE fetch: 392,134,513 bytes;
- canonical source: 1,228,233,321 bytes;
- upstream build tree: 1,446,291,042 bytes;
- upstream build: 1,715 seconds with one worker;
- selected CSL closure: 106 objects, 2 resources and 48 fonts;
- installed package: 81 files and 15,135,198 bytes;
- authoritative 81-entry inventory: 21,077 bytes, SHA-256
  `117baf6dc6253e2249f18d00a183167b4c093409f4b54c74b4f20620d11e1945`;
- embedded 80-entry ownership inventory: 20,822 bytes, SHA-256
  `a89ef6e7b70086dd674c6b801f98b147b30fc45f5d1fcda5481659c6709ae058`;
- deterministic inner ZIP: 9,344,138 bytes, SHA-256
  `7227839b2f1d98be16bc6bafe292a25393daad4af3bdb487c80f6455f07e954a`;
- uploaded artifact wrapper: 9,333,027 bytes, SHA-256 / upload digest
  `23ea055b92e4cfefe5e3d0b9591e00569f18ce5df977e053767df6f4aba08a7d`;
- complete `reduce`-label suite: 23/23 tests in 373.52 seconds;
- installed component verifier: 81 files, success.

The workflow's aggregate conclusion is `failure` because both unrelated
Windows pure-faust matrix jobs failed. The required `Windows PureReduce
package` job itself and each of its 12 build, test, verification and upload
steps succeeded; the aggregate result is not described as green.

The downloaded artifact wrapper matched the GitHub upload digest, and its sole
inner ZIP matched the workflow transcript. The inner ZIP was extracted afresh
under
`C:\Users\jiris\AppData\Local\Temp\PR artifact 32080639311 short 8e5d\package with spaces`.
With `PATH` limited to that module directory, a matching temporary Pure runtime
directory, and Windows system directories (`MSYS2` absent), the installed smoke
and lifecycle drivers both exited 0. The independent structural installed
verifier then accepted the unchanged 81-file package and exact manifest.

## Progress Log

- 2026-07-25: Created as a large optional Windows package investigation.
- 2026-08-17: Completed the exact-pin local Windows implementation and chose
  the separate optional `PureReduce` component/artifact model. Added build,
  package, relocation, lifecycle, inventory and licensing evidence.
- 2026-08-18: The clean Windows PureReduce job passed all 23 tests, installed
  verification and artifact upload. Independently downloaded and hash-checked
  the artifact, extracted it into a new path containing spaces, and passed its
  smoke, lifecycle and installed-package verification without MSYS2 on
  `PATH`. Closed TODO-47 with the separate-component decision unchanged.
