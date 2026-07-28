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

## Optional hardware validation

After a normal CMake build, the following target opens the selected output,
sends a low-velocity middle-C Note On, waits 100 ms, sends Note Off, and closes
the stream. The Pure subprocess has a hard 15-second limit:

```sh
cmake --build <build-dir> --target check-midi-output
```

Set `PURE_MIDI_OUT` to a PortMidi device number or interface/name glob before
configuring when the default output is unsuitable. A true loopback validation
also requires an input connected to that output; absence of such an input must
be recorded rather than represented as a passing loopback test.

On the validation host, PortMidi enumerated two `MMSystem` outputs and no
inputs. The bounded test passed on device 0, `Microsoft MIDI Mapper`; device 1
was `Microsoft GS Wavetable Synth`. No loopback result is claimed because the
host exposed no MIDI input.
