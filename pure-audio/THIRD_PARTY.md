# Audio runtime licensing inventory

Task 6 owns the eleven new audio/codec DLLs listed below. The portable Pure
prefix is a separately owned baseline: it is never overwritten, and its full
29-PE combined closure is checked. Two baseline DLLs newly required/reused by
audio (`libc++.dll` and `libwinpthread-1.dll`) are also mapped here. This is an
inventory of all thirteen audio-relevant DLLs, not a certification of the
pre-existing portable Pure package's licensing or source-offer obligations.
The audited baseline contained no third-party license materials; its owner
must resolve that separate, pre-existing packaging issue before distribution.

| DLL (in bin/) | Project/package version | License | Bundled full text (in licenses/) |
| --- | --- | --- | --- |
| libportaudio.dll | PortAudio 19.7.0-5 | MIT | PortAudio.txt |
| libfftw3-3.dll | FFTW 3.3.11-1 | GPL-2.0-or-later | FFTW-COPYING.txt, FFTW-COPYRIGHT.txt |
| libsamplerate-0.dll | libsamplerate 0.2.2-1 | BSD-2-Clause | libsamplerate.txt |
| libsndfile-1.dll | libsndfile 1.2.2-1 | LGPL-2.1-or-later | libsndfile.txt |
| libogg-0.dll | libogg 1.3.6-1 | BSD-3-Clause | libogg.txt |
| libvorbis-0.dll, libvorbisenc-2.dll | Vorbis 1.3.7-2 | BSD-3-Clause | Vorbis-COPYING.txt |
| libFLAC.dll | FLAC 1.5.0-1 | BSD-3-Clause (library) | FLAC-Xiph.txt |
| libopus-0.dll | Opus 1.6.1-1 | BSD-3-Clause | Opus.txt |
| libmpg123-0.dll | mpg123 1.33.5-1 | LGPL-2.1-only (library) | mpg123.txt |
| libmp3lame-0.dll | LAME 3.100-3 | LGPL-2.0-or-later | LAME-COPYING.txt |
| libwinpthread-1.dll (reused) | winpthreads 14.0.0.r220.gd999af622-1 | MIT AND BSD-3-Clause | winpthreads.txt |
| libc++.dll (reused) | LLVM libc++ 22.1.8-1 | Apache-2.0 WITH LLVM-exception | libcxx.txt |

`licenses/origins.tsv` records the canonical upstream URL, exact local package
payload or immutable release member, retrieval date (2026-09-09 UTC), and
SHA-256 of each of the thirteen byte-exact texts. The installer verifies these
hashes at configure/build/install time and maps every binary to installed
license destinations. PortAudio's MSYS2 version is `1~19.7.0-5` (upstream
19.7.0). Five pure-audio modules, six interfaces and package documentation are
pure-audio 0.6, covered by the accompanying BSD-3-Clause `COPYING`.

Nine texts came from installed CLANG64 package payloads. The user explicitly
authorized obtaining the missing FFTW/Vorbis/LAME texts from official upstream
releases after the local-only preflight blocked. No third-party mirror was
used and no redirect was followed:

- FFTW: [official 3.3.11 release](https://fftw.org/fftw-3.3.11.tar.gz),
  archive SHA-256 `5630c24cdeb33b131612f7eb4b1a9934234754f9f388ff8617458d0be6f239a1`;
  its MD5 `40ec8d0447d03b8f01f8c90aa77bd16f` matches the official `.md5sum`.
  `COPYING` and `COPYRIGHT` are extracted without modification.
- Vorbis: the [official Xiph v1.3.7 tag](https://gitlab.xiph.org/api/v4/projects/xiph%2Fvorbis/repository/tags/v1.3.7)
  (tag object `0c55fa38933fd4bdb7db7c298b27e7bf2f2c5e98`) resolves to
  `0657aee69dec8508a0011f47f3b69d7538e9d262`; `COPYING` comes from that
  immutable commit. The tag's signature was not independently verified.
- LAME: [official SVN release tag at revision 6403](https://sourceforge.net/p/lame/svn/6403/tree/tags/RELEASE__3_100/lame/)
  identifies release 3.100; `configure.in` at that revision confirms
  `AC_INIT([lame],[3.100],...)`. `COPYING` is fetched at the same fixed revision.

These texts describe upstream terms, not a legal conclusion that bundling
license texts alone satisfies all distribution obligations. Corresponding
source, notices and any applicable offers remain the distributor's responsibility.
