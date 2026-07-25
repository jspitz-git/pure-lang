# TODO-33 - Windows pure-audio Package

Status: Open
Branch: todo/33-windows-pure-audio

## Purpose

Build, validate, and package `pure-audio` and its supported codec/resampling
components for Windows.

## Scope

- Use CLANG64 PortAudio, libsndfile, libsamplerate, and FFTW where required.
- Cover device enumeration, playback, capture, file I/O, and resampling.
- Treat hardware-dependent tests as a separate validation tier.

## Task List

1. [ ] Inventory and build every supported native component.
2. [ ] Resolve audio backend, codec, and transitive DLL dependencies.
3. [ ] Add deterministic no-hardware and file-processing smoke tests.
4. [ ] Run documented playback/capture checks on a Windows host.
5. [ ] Stage and validate the advertised package contents.

## Guardrails

- Automated tests must not hang when no audio device is present.
- Do not advertise a codec or backend that was not built and tested.

## Validation Plan

- Import all modules and process a bundled audio fixture without physical hardware.
- Run bounded playback and capture tests and inspect every staged PE dependency.

## Progress Log

- 2026-07-25: Created as an optional multimedia Windows package candidate.
