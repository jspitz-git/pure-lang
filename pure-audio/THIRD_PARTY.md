# Third-party runtime components

The Windows package redistributes unmodified MSYS2 CLANG64 runtime DLLs.
Their upstream projects and licenses are:

| Component | License | Project |
| --- | --- | --- |
| PortAudio | MIT-style | https://www.portaudio.com/ |
| FFTW | GPL-2.0-or-later | https://www.fftw.org/ |
| libsamplerate | BSD-2-Clause | https://libsndfile.github.io/libsamplerate/ |
| libsndfile | LGPL-2.1-or-later | https://libsndfile.github.io/libsndfile/ |
| FLAC | BSD-3-Clause and GPL-2.0-or-later | https://xiph.org/flac/ |
| libogg | BSD-3-Clause | https://xiph.org/ogg/ |
| libvorbis | BSD-3-Clause | https://xiph.org/vorbis/ |
| Opus | BSD-3-Clause | https://opus-codec.org/ |
| mpg123 | LGPL-2.1-only | https://www.mpg123.de/ |
| LAME | LGPL-2.0-or-later | https://lame.sourceforge.io/ |
| winpthreads | MIT and BSD-style | https://www.mingw-w64.org/ |
| LLVM libc++ | Apache-2.0 WITH LLVM-exception | https://libcxx.llvm.org/ |

License texts shipped by the installed MSYS2 packages are copied into the
`licenses` subdirectory. FFTW, Vorbis, and LAME do not provide separate
license files in the installed CLANG64 packages; the table above records the
applicable terms and upstream source. The bundle-level license inventory must
