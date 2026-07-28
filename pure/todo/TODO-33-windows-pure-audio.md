# TODO-33 - Windows pure-audio Package

Status: Closed
Branch: todo/33-windows-pure-audio

## Purpose

Build, validate, and package `pure-audio` and its supported codec/resampling
components for Windows.

## Scope

- Use CLANG64 PortAudio, libsndfile, libsamplerate, and FFTW where required.
- Cover device enumeration, playback, capture, file I/O, and resampling.
- Treat hardware-dependent tests as a separate validation tier.

## Task List

1. [x] Inventory and build every supported native component.
2. [x] Resolve audio backend, codec, and transitive DLL dependencies.
3. [x] Add deterministic no-hardware and file-processing smoke tests.
4. [x] Run documented playback/capture checks on a Windows host.
5. [x] Stage and validate the advertised package contents.

## Guardrails

- Automated tests must not hang when no audio device is present.
- Do not advertise a codec or backend that was not built and tested.

## Validation Plan

- Import all modules and process a bundled audio fixture without physical hardware.
- Run bounded playback and capture tests and inspect every staged PE dependency.

## Progress Log

- 2026-07-25: Created as an optional multimedia Windows package candidate.
- 2026-07-28: Built the five supported native modules (`audio`, `fftw`,
  `srcprocess`, `sfinfo`, and `realtime`) as x86-64 PE DLLs with strict
  warnings enabled. Added guarded clean targets. Commit: `3e7e3b92`.
- 2026-07-28: Audited the complete runtime closure: eleven new PortAudio,
  FFTW, libsamplerate, libsndfile, and codec DLLs; hash-matched the existing
  `libc++.dll` and `libwinpthread-1.dll`; rejected MSYS, libgcc, and
  libstdc++ dependencies. Commit: `6a49cd6d`.
- 2026-07-28: Added deterministic hardware-free tests covering all module
  imports, PortAudio enumeration/restart without streams, FFT round-trip,
  resampling, WAV write/read, and normal scheduling. Both CTest tests pass.
  Commit: `9f3306e7`.
- 2026-07-28: Added 15-second-bounded optional playback and capture checks.
  Playback passed on device 3, `Microsoft Sound Mapper - Output` (MME,
  2 channels, 44100 Hz); capture passed on device 0,
  `Microsoft Sound Mapper - Input` (MME, 2 channels, 44100 Hz). Corrected
  stream close/sentry handling and frame-count reporting. Commit: `ff4f088d`.
- 2026-07-28: Installed and verified a 40-file package delta: five modules,
  six Pure interfaces, eleven new runtime DLLs, four package documents,
  seven third-party license texts, two examples, and five test scripts.
  The installed smoke test passes with an empty `PURELIB` and a sanitized
  staged-only runtime `PATH`; the staged PE closure also passes.
- 2026-07-28: The complete portable prefix audit passes with 23 DLLs,
  19 resolved non-system dependency paths, and 80 staged files. Codec DLLs
  are documented as transitive libsndfile dependencies; only deterministic
  WAV file I/O is advertised as tested.
