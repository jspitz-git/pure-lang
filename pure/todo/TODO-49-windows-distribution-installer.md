# TODO-49 - Windows Distribution Installer

Status: Open
Branch: todo/49-windows-distribution-installer

## Purpose

Create a polished 64-bit Windows installer for the portable Pure runtime, PurePad,
documentation, examples, and every package independently approved for Windows.

## Scope

- Build an explicit staging manifest before producing the installer.
- Use selectable components for optional package groups and developer tools.
- Support shortcuts, `.pure` association, upgrades, silent installation, and uninstall.
- Test the installed product without MSYS2 or unrelated development tools.

## Task List

1. [ ] Define the versioned staging manifest, component groups, and installation layout.
2. [ ] Create a reproducible Inno Setup build with per-user and administrative modes.
3. [ ] Add PurePad, documentation, examples, licenses, and approved package manifests.
4. [ ] Implement optional file association, shortcuts, and user `PATH` integration.
5. [ ] Add clean-VM install, smoke, upgrade, silent-install, and uninstall validation.
6. [ ] Produce checksums, signing hooks, release notes, and the final distributable.

## Guardrails

- The installer must never copy files from an undeclared glob or the host MSYS2 tree.
- Default operation must not require global `PURELIB` or modify machine `PATH`.
- Every bundled binary and library must have recorded provenance and license material.
- A package may enter the installer only after its own Windows TODO passes.

## Validation Plan

- Build and install on a clean GitHub Actions Windows VM into a path containing spaces.
- Sanitize `PATH`, run `pure --version`, execute a program, and launch PurePad.
- Import and smoke-test every selected package component.
- Exercise silent install, upgrade, repair-equivalent reinstall, and uninstall.
- Reject missing DLLs, `msys-2.0.dll`, and embedded build/MSYS2 paths.

## Open Questions

- Which packages belong in the default selection versus optional feature groups.
- Whether code signing is available for initial releases.

## Progress Log

- 2026-07-25: Created as the final integration step for the Windows distribution.
