# TODO-34 - Windows pure-midi Package

Status: Closed
Branch: todo/34-windows-pure-midi

## Purpose

Build, validate, and package `pure-midi` with PortMidi on Windows.

## Scope

- Build the native module and bundle the compatible PortMidi runtime.
- Cover device enumeration, message conversion, timing, and cleanup.
- Separate deterministic tests from tests requiring MIDI hardware.

## Task List

1. [x] Build the module against the staged runtime and PortMidi.
2. [x] Audit Windows device and timing behavior.
3. [x] Add deterministic encoding and no-device smoke tests.
4. [x] Run documented loopback or hardware validation.
5. [x] Stage and inspect the complete package.

## Guardrails

- Absence of MIDI hardware must not crash or hang the test suite.
- Device handles must be closed on every exit path.

## Validation Plan

- Exercise enumeration and MIDI message conversion with bounded timeouts.
- Run a loopback test when a suitable virtual or physical device is available.

## Progress Log

- 2026-07-25: Created as an optional multimedia Windows package candidate.
- 2026-07-28: Installed CLANG64 PortMidi 2.0.8 (pkg-config version 2.0.7)
  and built `pmlib.dll` and `midifile.dll` as strict-warning x86-64 PE
  modules. Hardened both legacy clean targets. Commit: `2ec07fc2`.
- 2026-07-28: Audited the runtime closure: one `libportmidi.dll`, native
  WinMM device/timing backend, UCRT, and no MSYS/GNU runtime. Added bounded
  enumeration, PortTime, restart, and cleanup checks. Commit: `4191585e`.
- 2026-07-28: Added deterministic MIDI word/byte conversion, invalid-port,
  and Standard MIDI File round-trip tests. The bundled fixture has two tracks
  and 1632 events; both hardware-free CTests pass. Commit: `ed635d3f`.
- 2026-07-28: The 15-second-bounded output test passed twice on `MMSystem`
  device 0, `Microsoft MIDI Mapper`, with explicit Note Off and stream close.
  The host exposed two outputs and no inputs, so no loopback result is
  claimed. Commit: `2c051294`.
- 2026-07-28: Installed and verified a 16-file package delta: two modules,
  three Pure interfaces, PortMidi runtime, four package documents, one
  third-party license, two examples, and three test scripts. Both installed
  hardware-free tests pass with empty `PURELIB` and a sanitized staged-only
  runtime `PATH`.
- 2026-07-28: The complete portable prefix audit passes with 13 DLLs,
  12 resolved non-system dependency paths, and 56 staged files.
