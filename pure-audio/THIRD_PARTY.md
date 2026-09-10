# Staged package licensing inventory

Task 6 owns eleven new audio/codec DLLs and five audio modules. The portable
Pure prefix remains a separately owned, byte-identical baseline, never
overwritten by this installer. After review the user authorized official
upstream license retrieval for the complete staged dependency inventory,
including its nine previously unmapped baseline dependency DLLs. The full
29-PE closure consists of 22 third-party DLLs listed below and seven
project-owned PEs (five audio modules, pure.exe, libpure.dll). This coverage
does not transfer ownership of the baseline binaries to Task 6.

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
| libgmp-10.dll (baseline) | GMP 6.3.0-2 | LGPL-3.0-or-later OR GPL-2.0-or-later | GMP-COPYINGv2.txt, GMP-COPYINGv3.txt, GMP-COPYING-LESSERv3.txt |
| libiconv-2.dll (baseline) | libiconv 1.19-1 | LGPL-2.1-or-later (library) | libiconv-COPYING-LIB.txt |
| libmpfr-6.dll (baseline) | MPFR 4.2.2-3 | LGPL-3.0-or-later | MPFR-COPYING.txt, MPFR-COPYING-LESSER.txt |
| libpcre-1.dll, libpcreposix-0.dll (baseline) | PCRE 8.45-2 | BSD-3-Clause | PCRE-LICENCE.txt |
| libreadline8.dll (baseline) | Readline 8.3.003-1 | GPL-3.0-or-later | Readline-COPYING.txt |
| libtermcap-0.dll (baseline) | Termcap 1.3.1-7 | GPL-2.0-or-later | Termcap-COPYING.txt |
| libzstd.dll (baseline) | Zstd 1.5.7-2 | BSD-3-Clause | Zstd-LICENSE.txt |
| zlib1.dll (baseline) | Zlib 1.3.2-2 | Zlib | Zlib-LICENSE.txt |

`licenses/origins.tsv` records the canonical upstream URL, exact local package
payload or immutable release member, retrieval date (2026-09-09 UTC), and
SHA-256 of each of the 27 byte-exact license/notice payloads (24 third-party
texts plus three Pure project texts). The installer verifies these
hashes at configure/build/install time and maps every binary to installed
license destinations. PortAudio's MSYS2 version is `1~19.7.0-5` (upstream
19.7.0). Five pure-audio modules, six interfaces and package documentation are
pure-audio 0.6, covered by the accompanying BSD-3-Clause `COPYING`.
The Pure 0.68 executable is GPL-3.0-or-later; its runtime and standard library
are LGPL-3.0-or-later. `Pure-COPYING.txt` and `Pure-COPYING-LESSER.txt` contain
their full terms; `Pure-README.txt` retains the project's interpreter/runtime
distinction and additional GPLv2-only linking permission. The aggregate Pure
package mapping includes all three texts for both PEs, not a relicensing of
the LGPL runtime as GPL. The five audio modules map to the own-package COPYING.

Windows system imports are not redistributed in the stage. Task 5 accepts
only its explicit system/API-set policy from the registered Windows System32
authority; those host-owned files are not counted among the 29 staged PEs or
the 22 third-party DLLs. This is PE/DLL license-text coverage, not an audit of
every source file or statically incorporated component in the Pure baseline.

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

The additional baseline release payloads come directly from the GNU project
release host (GMP, libiconv, Readline, Termcap), mpfr.org (MPFR), the PCRE
author's Exim archive (PCRE 8.45), and immutable commits in the official
facebook/zstd and madler/zlib repositories. Archive hashes and member names
are in origins.tsv. Zstd v1.5.7 and Zlib v1.3.2 annotated tags were resolved
through their official GitHub APIs; signatures were not independently verified.
Readline's exact installed 8.3.003 level is base 8.3 plus the three official
patches below; their patchlevel changes are 0 to 1 to 2 to 3 and none changes
COPYING:

- [readline83-001](https://ftp.gnu.org/gnu/readline/readline-8.3-patches/readline83-001): SHA-256 `21f0a03106dbe697337cd25c70eb0edbaa2bdb6d595b45f83285cdd35bac84de`.
- [readline83-002](https://ftp.gnu.org/gnu/readline/readline-8.3-patches/readline83-002): SHA-256 `e27364396ba9f6debf7cbaaf1a669e2b2854241ae07f7eca74ca8a8ba0c97472`.
- [readline83-003](https://ftp.gnu.org/gnu/readline/readline-8.3-patches/readline83-003): SHA-256 `72dee13601ce38f6746eb15239999a7c56f8e1ff5eb1ec8153a1f213e4acdb29`.

These texts describe upstream terms, not a legal conclusion that bundling
license texts alone satisfies all distribution obligations. Corresponding
source, notices and any applicable offers remain the distributor's responsibility.
