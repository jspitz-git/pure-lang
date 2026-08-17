# PureReduce third-party provenance

The PureReduce component embeds the CSL implementation of REDUCE and links
its native dependencies statically. Its audited PE closure contains no
redistributable runtime DLL at this pin; Windows and UCRT DLLs are supplied by
Windows and are matched against the explicit allowlist in
`AuditWindowsDependencies.cmake`.

## REDUCE / CSL source identity

- Official repository: <https://github.com/reduce-algebra/reduce-algebra.git>
- Commit: `7efba90661139ae9c73c99fddd55f3fb2fabf69a`
- Git tree object: `5573613a2f86efea75695fbe65a73317383884c1`
- Verified tracked-tree SHA-256:
  `134a68fdb10403d3a4c69051eb4e133803ff2659784f2d38ac4d94c7ee9f86d8`
- Role: CSL supplies the in-process algebra engine, `reduce.img`, runtime
  resources, and fonts used by `reduce.dll` and `reduce.pure`.
- License: `licenses/REDUCE-LICENSE.txt`, copied byte-for-byte from `LICENSE`
  at the pinned commit. The installed SHA-256 inventory also covers the more
  detailed CSL and embedded-library notices listed below.

The tracked-tree digest is generated without reading working-tree bytes. The
pathname-sorted output of `git ls-files -s` (mode, object ID, stage, and path)
is hashed as one byte stream with SHA-256. `pure_reduce_verify_source` repeats
this operation and rejects a dirty tree or any other commit.

Retrieve the exact source without relying on a moving branch:

```console
git clone --filter=blob:none https://github.com/reduce-algebra/reduce-algebra.git
git -C reduce-algebra fetch origin 7efba90661139ae9c73c99fddd55f3fb2fabf69a
git -C reduce-algebra checkout --detach 7efba90661139ae9c73c99fddd55f3fb2fabf69a
```

The private build materializes canonical Git blobs with
`git -c core.autocrlf=false checkout-index`. It applies only these two
checksum-covered patches:

- `0001-csl-winsupport-define-nil.patch`, SHA-256
  `2d88d6d4a842ccb4574b60b0bd7e3af91896cea76708551a6e54489792e91d08`.
- `0002-csl-windows-utf8-image-open.patch`, SHA-256
  `ad89f9581eefaaf4191b65af1b769a18883e865ee2740e4e6f053d1c5615d0e9`.

The installed metrics JSON contains every patched path and exact preimage and
postimage SHA-256.

## Statically linked runtime families

The component installs the following exact notices under
`share/doc/pure-reduce/licenses`. These families contribute code to
`reduce.dll`; their `.a`, `.lib`, object files, tools, and source trees are not
installed.

| Family and origin | Role | Installed license notice |
| --- | --- | --- |
| REDUCE CSL at the commit above | Algebra runtime and image loader | `REDUCE-LICENSE.txt`, `CSL-COPYING.txt` |
| REDUCE-vendored crlibm | Correctly rounded math | `CRLIBM-COPYING.txt`, `CRLIBM-COPYING.LIB.txt` |
| REDUCE-vendored libffi | Foreign-call support | `LIBFFI-LICENSE.txt` |
| `mingw-w64-clang-x86_64-zlib 1.3.2-2` | Compressed runtime data | `ZLIB-LICENSE.txt` |
| `mingw-w64-clang-x86_64-ncurses 6.6-4` | CSL terminal support | `NCURSES-LICENSE.txt` |
| `mingw-w64-clang-x86_64-winpthreads 14.0.0.r220.gd999af622-1` | Static POSIX threads implementation | `WINPTHREADS-COPYING.txt` |
| `mingw-w64-clang-x86_64-libc++ 22.1.8-1` | C++ standard library (`-lstdc++` maps to libc++ in CLANG64) | `LIBCXX-LICENSE.txt` |
| `mingw-w64-clang-x86_64-libunwind 22.1.8-1` | Static unwind runtime | `LIBUNWIND-LICENSE.txt` |
| `mingw-w64-clang-x86_64-compiler-rt 22.1.8-2` | Compiler builtins selected by `-static-libgcc` | `COMPILER-RT-LICENSE.txt` |
| `mingw-w64-clang-x86_64-crt 14.0.0.r262.g5ea8e9fac-1` | Native Windows CRT startup/support | `MINGW-W64-CRT-COPYING.txt`, `MINGW-W64-RUNTIME-COPYING.txt` |

## Bundled fonts and data

`reduce.resources` contains REDUCE-owned AWK helpers and is covered by the
REDUCE notice. `reduce.fonts` retains the upstream-provided DejaVu,
BaKoMa/Computer Modern, CMPS, and CM Unicode notices and README files beside
the fonts. `CM-UNICODE-LICENSE.txt` is additionally installed in the central
license directory. Every individual resource and font is recorded with its
origin, purpose, size, SHA-256, and applicable notice in
`PureReduceInventory.tsv` in the build directory.
