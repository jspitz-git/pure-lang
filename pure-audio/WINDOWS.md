# Windows build and runtime notes

The supported Windows build uses the 64-bit MSYS2 CLANG64 development files
for PortAudio, libsndfile, libsamplerate, and FFTW. The resulting Pure modules
run from a native Windows prefix; MSYS2 is a build environment only.

The advertised module set is:

- `audio.dll`, `audio.pure`, and `portaudio.pure` for PortAudio;
- `fftw.dll` and `fftw.pure`;
- `srcprocess.dll` and `samplerate.pure`;
- `sfinfo.dll` and `sndfile.pure`;
- `realtime.dll` and `realtime.pure`.

The Windows `realtime` module uses the winpthreads scheduling API. Normal
`SCHED_OTHER` operation is tested automatically. FIFO/RR priority elevation
is not promised because Windows permissions and winpthreads behavior vary.

Automated tests must not open physical playback or capture streams. They cover
module loading, device enumeration, deterministic transforms, resampling, and
audio-file I/O. Playback and capture are a separate bounded manual tier and
may be reported only for the exact host devices on which they were exercised.

## Runtime closure

The package adds eleven non-system runtime DLLs: PortAudio, FFTW,
libsamplerate, libsndfile, Ogg, Vorbis/VorbisEnc, FLAC, Opus, mpg123, and
LAME. The existing bundle copies of `libc++.dll` and
`libwinpthread-1.dll` are reused after hash verification.

PortAudio imports the native Windows multimedia, COM, and device-setup APIs.
This build does not claim ASIO support. The Ogg, Vorbis, FLAC, Opus, mpg123,
and LAME DLLs are transitive parts of the audited libsndfile build, but their
presence is not a claim that every corresponding file format was tested. The
automated package test covers deterministic WAV input and output.

## Optional hardware validation

After a normal CMake build, the following targets exercise the selected host
devices with a hard 15-second process limit:

```sh
cmake --build <build-dir> --target check-audio-playback
cmake --build <build-dir> --target check-audio-capture
```

Playback writes one 256-frame block of silence. Capture reads 128 frames into
process memory and neither saves nor prints sample data. These targets are
never part of the default CTest suite. Record the exact host device and sample
rate before claiming hardware validation.
