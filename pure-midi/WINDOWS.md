# Windows build and runtime notes

The supported Windows build uses the 64-bit MSYS2 CLANG64 PortMidi package.
The resulting modules run from a native Windows prefix; MSYS2 is a build
environment only.

The package contains two native modules:

- `pmlib.dll`, `portmidi.pure`, and `midi.pure` provide the realtime
  PortMidi/PortTime interface;
- `midifile.dll` and `midifile.pure` provide deterministic Standard MIDI File
  reading and writing.

Automated tests enumerate devices but never open physical MIDI ports. Hardware
or virtual-loopback tests are a separate bounded validation tier. Any reported
hardware result applies only to the exact Windows host and devices tested.
