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
