# TODO-16 - Non-Linux Release Validation

Status: Open
Branch: todo/16-non-linux-release-validation

## Purpose

Define and validate the supported non-Linux platform matrix for the LLVM 22 port.
Success means each declared operating-system and architecture combination has a
reproducible CMake/Ninja build, test, install, uninstall, and installed-program result.

## Scope

- Decide whether Windows, macOS, or both are release-supported.
- Record supported architectures, LLVM 22 distributions, generators, and shells.
- Validate platform-specific runtime loading, paths, object/link output, and optional assets.
- Add presets or CI jobs only after the support matrix is explicit.

## Task List

1. [ ] Define required operating systems, architectures, and host toolchains.
2. [ ] Configure and build each supported matrix entry from a clean tree.
3. [ ] Run focused integration and complete regression tests.
4. [ ] Validate batch object/link execution and platform library lookup behavior.
5. [ ] Validate install manifests, pkg-config where applicable, and idempotent uninstall.
6. [ ] Document unsupported combinations and any platform-specific prerequisites.

## Guardrails

- Do not infer Windows or macOS support from the Linux/WSL validation.
- Do not add nominal presets which have not been exercised on their target host.
- Keep platform-specific workarounds narrowly scoped and covered by tests.

## Validation Plan

- Preserve complete configure, build, CTest, install, execution, and uninstall logs for
  every supported matrix entry.
- Confirm no generated or installed path escapes the selected build or prefix.

## Origin

Created from TODO-02's Linux-only compatibility note, TODO-13 retrospective gate 5,
and TODO-13's unresolved release-matrix question.
