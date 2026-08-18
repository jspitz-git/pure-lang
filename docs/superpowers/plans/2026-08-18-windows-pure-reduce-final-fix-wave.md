# Windows PureReduce Final Fix Wave Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Resolve every merge-blocking final review finding for TODO-47, prove each behavior with RED/GREEN evidence, and replace the historical package evidence with a clean Windows run and independently verified artifact from the final implementation SHA.

**Architecture:** Keep the official REDUCE checkout exactly pinned and immutable. Apply the new raw-cons operation only in the existing checksum-covered private source materialization, trust cached upstream outputs only through exact content manifests, and generate rolling MSYS2 provenance from the packages and static inputs actually used by the build. Extend the Pure lifecycle and package contracts without weakening existing verifiers.

**Tech Stack:** CMake 3.25 script mode/CTest, C++17, Pure, PowerShell, MSYS2 CLANG64, GitHub Actions.

## Global Constraints

- Upstream REDUCE commit remains exactly `7efba90661139ae9c73c99fddd55f3fb2fabf69a` with tracked-tree SHA-256 `134a68fdb10403d3a4c69051eb4e133803ff2659784f2d38ac4d94c7ee9f86d8`.
- Never patch or modify the verified REDUCE checkout; corrections apply only to the private `checkout-index` materialization and are checksum/preimage/postimage covered.
- Preserve the in-process `PROC_*` API, sanitized-runtime package contract, and separate optional `PureReduce` component.
- Rolling MSYS2 package versions must be recorded truthfully, not frozen to stale documentation values; missing or inconsistent provenance blocks packaging.
- Preserve the pre-existing untracked `build/` directory byte-for-byte: do not build in it, clean it, stage it, or delete it.
- Do not create a pull request.
- Commit and push implementation before the clean Windows run; commit evidence-only TODO/report changes only after independent artifact verification.

---

### Task 1: Restore the registered recipe fixture and clean patch bytes

**Files:**
- Modify: `pure-reduce/tests/utf8-image-patch-contract.cmake`
- Modify: `.gitattributes`

**Interfaces:**
- Consumes: `_pure_reduce_run_upstream_build_ensure` complete-cache contract.
- Produces: a fixture with valid runtime directories/manifests and a patch-path whitespace policy that accepts syntax-required unified-diff context markers while retaining exact patch bytes and SHA-256 values.

- [x] Record the current direct recipe-contract RED failure `current upstream recipe marker forced regeneration` and the current `git diff --check` whitespace failures.
- [x] Add deterministic `reduce.resources` and `reduce.fonts` fixture files and generate their manifests before asserting current-recipe reuse.
- [x] Scope `blank-at-eol`/`blank-at-eof` exceptions to `pure-reduce/patches/*.patch`, retaining all patch bytes, registry hashes, and target pre/postimage assertions unchanged.
- [x] Run the direct patch contract and `git diff --check 3b462f73..HEAD`; require exit 0 and no output from the diff check.

### Task 2: Preserve first-operation capture and feed semantics

**Files:**
- Create: `pure-reduce/tests/first-capture.pure`
- Create: `pure-reduce/tests/first-feed.pure`
- Modify: `pure-reduce/CMakeLists.txt`
- Modify: `pure-reduce/reduce.pure`

**Interfaces:**
- Consumes: `reduce::get_started`, `PROC_capture_output`, and `PROC_feed_input`.
- Produces: independent Pure processes proving that capture or feed may be the first REDUCE operation and that callbacks are installed only after `cslstart`.

- [x] Add `first-capture.pure`: assert state 0, call `reduce::capture 1`, emit through Lisp, and assert the output buffer contains a fixed marker.
- [x] Add `first-feed.pure`: assert state 0, call `reduce::feed "(list 7 8 9)"`, evaluate `read`, and assert `[7,8,9]`.
- [x] Register both scripts as reduce-labeled tests and run each against the current bridge/module copy to capture expected RED output.
- [x] Gate public `capture` and `feed` through `get_started`, preserving bridge callback calls after startup.
- [x] Re-run both tests and existing smoke/lifecycle tests; require all four to pass.

### Task 3: Remove the public save-slot collision

**Files:**
- Create: `pure-reduce/patches/0004-csl-procedural-raw-cons.patch`
- Modify: `pure-reduce/tests/bridge-contract.cpp`
- Modify: `pure-reduce/CMakeLists.txt`
- Modify: `pure-reduce/bridge/reduce_bridge.cpp`
- Modify: `pure-reduce/cmake/ReduceUpstream.cmake`
- Modify: `pure-reduce/tests/utf8-image-patch-contract.cmake`
- Modify: `pure-reduce/cmake/Install.cmake`
- Modify: `pure-reduce/THIRD_PARTY.md`
- Modify: `pure-reduce/WINDOWS.md`

**Interfaces:**
- Consumes: pinned private `csl/cslbase/csl.cpp` and `proc.h`.
- Produces: checksum-covered upstream-private `CSL_LISP::PROC_make_raw_cons()` plus the unchanged bridge export `PROC_make_cons()`.

- [x] Extend the live bridge test to save 42 in public slot 99, construct `(1 . 2)`, then reload and assert 42; run against current implementation and capture RED value 2.
- [x] Add a minimal private-source patch declaring/implementing `PROC_make_raw_cons` directly over the procedural stack without using any `PROC_save` slot.
- [x] Register patch SHA-256 and exact target pre/post hashes, add it to the source stamp, private materialization, metrics, installation, and documentation.
- [x] Replace bridge slot-99 emulation with `CSL_LISP::PROC_make_raw_cons()`.
- [x] Build a fresh bridge against the patched private source and run the live slot probe; require the pair and saved 42 to survive.

### Task 4: Generate fail-closed rolling toolchain provenance

**Files:**
- Create: `pure-reduce/cmake/ToolchainProvenance.cmake`
- Create: `pure-reduce/tests/toolchain-provenance.cmake`
- Modify: `pure-reduce/cmake/ReduceUpstream.cmake`
- Modify: `pure-reduce/cmake/Install.cmake`
- Modify: `pure-reduce/cmake/VerifyInstalledPackage.cmake`
- Modify: `pure-reduce/tests/install-component.cmake`
- Modify: `pure-reduce/CMakeLists.txt`
- Modify: `.github/workflows/non-linux-release-validation.yml`
- Modify: `pure-reduce/THIRD_PARTY.md`
- Modify: `pure-reduce/WINDOWS.md`

**Interfaces:**
- Consumes: `pacman -Q`, `pacman -Qqo`, `clang++ -print-file-name`, static link inputs, and vendored notices.
- Produces: an exact canonical build snapshot plus a deterministic `toolchain_packages` array embedded in installed package metrics, with package version, role, actual static input/hash, owner, and notice names/hashes for zlib, ncurses, winpthreads, libc++, libunwind, compiler-rt, and CRT.

- [x] Add a structural test with one valid literal seven-row fixture plus missing-row, wrong-owner/schema, malformed-hash, and license-mismatch cases; capture RED because the validator is absent.
- [x] Implement strict capture: every resolved static input must be an existing absolute file owned by the expected package, every package query must yield a nonempty exact version, and every package license hash must match the vendored notice.
- [x] Implement strict validation with an exact package/input/license set and no hard-coded package versions.
- [x] Generate and validate provenance at both ends of the upstream build, compare it on every cache ensure, validate it again during install, and embed the canonical records in installed metrics without adding another installed file.
- [x] Log rolling package versions in CI and fail before publish on any absent/inconsistent row.
- [x] Remove stale exact version claims from static documentation and point to generated installed evidence.

### Task 5: Content-validate every cached load-bearing input

**Files:**
- Create: `pure-reduce/tests/upstream-cache-identity.cmake`
- Modify: `pure-reduce/cmake/ReduceUpstream.cmake`
- Modify: `pure-reduce/tests/runtime-artifact-handoff.cmake`
- Modify: `pure-reduce/tests/utf8-image-patch-contract.cmake`
- Modify: `pure-reduce/CMakeLists.txt`

**Interfaces:**
- Consumes: the exact cached image, header, static archives, install licenses, provenance, metrics, probe executable/log, runtime manifests, stamp, and recipe marker.
- Produces: `pure-reduce-upstream-inputs.manifest` plus a last-written `pure-reduce-upstream.complete`, with exact sorted SHA-256/size/path identity validated before cache reuse and direct component install.

- [x] Add a fixture that writes a complete cache, corrupts every listed load-bearing file with same-size bytes one at a time, and requires one full recovery rebuild followed by idempotent reuse; capture RED against existence/size validation.
- [x] Implement exact manifest writing and validation: strict 64-hex hashes, byte counts, safe unique relative paths, exact expected set, and exact file content.
- [x] Generate the manifest only after all load-bearing outputs exist and require it in build completeness.
- [x] Update adjacent fixtures to publish a real identity manifest and re-run corruption, runtime handoff, recipe, and revalidation contracts.

### Task 6: Install WINDOWS.md, preserve string ownership, and update exact package contracts

**Files:**
- Modify: `pure-reduce/cmake/Install.cmake`
- Modify: `pure-reduce/cmake/VerifyInstalledPackage.cmake`
- Modify: `pure-reduce/tests/install-component.cmake`
- Modify: `pure-reduce/reduce.pure`
- Modify: `pure-reduce/WINDOWS.md`
- Modify: `pure-reduce/THIRD_PARTY.md`
- Modify: `.github/workflows/non-linux-release-validation.yml`
- Modify: `pure/todo/TODO-47-windows-pure-reduce.md`

**Interfaces:**
- Consumes: dynamically generated install records.
- Produces: an exact 85-file component: old 81 + `WINDOWS.md` + two first-operation tests + patch 0004; rolling provenance is embedded in the existing metrics file, so the embedded inventory has 84 entries.

- [x] Add installed contract assertions for `WINDOWS.md`, the two lifecycle scripts, patch 0004, and embedded toolchain provenance; capture RED against the old 81-file package rules.
- [x] Install `WINDOWS.md` and the new patch/tests, change every current exact count gate to 85 (embedded ownership inventory 84), and keep historical evidence explicitly historical until replaced.
- [x] Preserve the existing consuming `string s::pointer = pure_string s` ownership transfer for `utf8_module`; record direct runtime evidence that an added `free` would double-free rather than treating the review's leak claim as valid.
- [x] Align the THIRD_PARTY metrics statement with the actually installed metrics/inventory.
- [ ] Change TODO status to repository format `Closed on YYYY-MM-DD` and describe artifact ID/digests as immutable while identifying the download URL as expiring.

### Task 7: Fresh local verification and implementation commit

**Files:**
- Modify: `.superpowers/sdd/2026-08-16-windows-pure-reduce/final-fix-wave-report.md`

**Interfaces:**
- Consumes: all implementation changes.
- Produces: a pushed implementation SHA with no evidence values invented from local state.

- [x] Configure and build in a new `%TEMP%` build root, leaving repository `build/` untouched.
- [x] Run all targeted RED/GREEN commands, then fresh `ctest -L reduce --output-on-failure --no-tests=error`, install/verify to a path with spaces, and `git diff --check 3b462f73..HEAD`.
- [ ] Review `git diff --stat`, `git status`, and intended paths; commit implementation only and push `HEAD:refs/heads/todo/47-windows-pure-reduce`.

### Task 8: Final clean-runner and independent artifact evidence

**Files:**
- Modify: `pure/todo/TODO-47-windows-pure-reduce.md`
- Modify: `.superpowers/sdd/2026-08-16-windows-pure-reduce/final-fix-wave-report.md`

**Interfaces:**
- Consumes: final implementation SHA, clean Windows job, uploaded artifact.
- Produces: final evidence-only commit with run/job/artifact URLs, immutable IDs/digests, exact inventories/counts, and sanitized runtime proof.

- [ ] Wait for the push-triggered `Windows PureReduce package` job on the exact implementation SHA and require build, complete reduce suite, installed verifier, deterministic ZIP, and upload to pass.
- [ ] Download the artifact wrapper, independently hash outer and inner ZIPs, extract into a fresh path containing spaces, and reconstruct/verify exact external and embedded inventories.
- [ ] Run smoke, lifecycle, first-capture, first-feed, and installed verifier with a PATH containing only the artifact module, matching Pure runtime, and Windows system directories.
- [ ] Record only observed final values in TODO and the final-fix report, then commit/push the evidence-only changes and report DONE, DONE_WITH_CONCERNS, or BLOCKED.
