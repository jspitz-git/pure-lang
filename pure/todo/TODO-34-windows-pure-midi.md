# TODO-34 - Windows pure-midi Package

Status: Open
Branch: todo/34-windows-pure-midi

## Purpose

Build, validate, and package `pure-midi` with PortMidi on Windows.

## Scope

- Build the native module and bundle the compatible PortMidi runtime.
- Cover device enumeration, message conversion, timing, and cleanup.
- Separate deterministic tests from tests requiring MIDI hardware.

## Task List

1. [ ] Build the module against the staged runtime and PortMidi.
2. [ ] Audit Windows device and timing behavior.
3. [ ] Add deterministic encoding and no-device smoke tests.
4. [ ] Run documented loopback or hardware validation.
5. [ ] Stage and inspect the complete package.

## Guardrails

- Absence of MIDI hardware must not crash or hang the test suite.
- Device handles must be closed on every exit path.

## Validation Plan

- Exercise enumeration and MIDI message conversion with bounded timeouts.
- Run a loopback test when a suitable virtual or physical device is available.

## Progress Log

- 2026-07-25: Created as an optional multimedia Windows package candidate.
