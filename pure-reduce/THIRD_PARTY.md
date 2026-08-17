# PureReduce third-party provenance

The PureReduce component embeds the CSL implementation of REDUCE and links
its native dependencies statically. Its audited PE closure contains no
redistributable runtime DLL at this pin; the exact imported Windows/UCRT set
is matched against the explicit allowlist in `AuditWindowsDependencies.cmake`.
Any future non-system DLL must resolve uniquely and have a reviewed mapping in
`RuntimeDllMappings.cmake` with exact origin, version, and vendored license.

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
`git -c core.autocrlf=false checkout-index`. It applies only these three
checksum-covered patches:

- `0001-csl-winsupport-define-nil.patch`, SHA-256
  `2d88d6d4a842ccb4574b60b0bd7e3af91896cea76708551a6e54489792e91d08`.
- `0002-csl-windows-utf8-image-open.patch`, SHA-256
  `ad89f9581eefaaf4191b65af1b769a18883e865ee2740e4e6f053d1c5615d0e9`.
- `0003-configure-quote-source-paths.patch`, SHA-256
  `ec94278f24718963e68aeac737a168c704c81cc72f48af903c4675770f3518df`.
  This also passes libffi's supported `--disable-symvers` option because native
  Windows lld does not accept the ELF `--version-script` linker option.

The installed metrics JSON contains every patched path and exact preimage and
postimage SHA-256.

## Statically linked runtime families

The component installs the following exact checked-in notices under
`share/doc/pure-reduce/licenses`. These families contribute code to
`reduce.dll`; their `.a`, `.lib`, object files, tools, and source trees are not
installed.

| Family and origin | Role | Installed notice and SHA-256 |
| --- | --- | --- |
| REDUCE CSL at the commit above | Algebra runtime and image loader | `REDUCE-LICENSE.txt`, `4f1ff282be9cc134055cd7095e54104115e0d308da5bd9ccbb4de4dd7b8d01f3`; `CSL-COPYING.txt` is verified from the pinned source |
| REDUCE-vendored crlibm | Correctly rounded math | `CRLIBM-COPYING.txt` and `CRLIBM-COPYING.LIB.txt`, verified from the pinned source |
| REDUCE-vendored libffi | Foreign-call support | `LIBFFI-LICENSE.txt`, verified from the pinned source |
| `mingw-w64-clang-x86_64-zlib 1.3.2-2` | Compressed runtime data | `ZLIB-LICENSE.txt`, `e32ff4e00d9d94930537635291da39e7e612703334bf6fde8c7f1686fe8a45a2` |
| `mingw-w64-clang-x86_64-ncurses 6.6-4` | CSL terminal support | `NCURSES-LICENSE.txt`, `708999f95527e1ffa670c6fce288c6c600cb477dd04afcc1171422b3dd4ee226` |
| `mingw-w64-clang-x86_64-winpthreads 14.0.0.r220.gd999af622-1` | Static POSIX threads implementation | `WINPTHREADS-COPYING.txt`, `63263614cdd29f2f93cba85e992f041b31f9fc7b4033692f31269489a8a1b177` |
| `mingw-w64-clang-x86_64-libc++ 22.1.8-1` | C++ standard library (`-lstdc++` maps to libc++ in CLANG64) | `LIBCXX-LICENSE.txt`, `539dd7aed86e8a4f12cbdd0e6c50c189c7d74847e4fecc64ce2c6ee3a01da38b` |
| `mingw-w64-clang-x86_64-libunwind 22.1.8-1` | Static unwind runtime | `LIBUNWIND-LICENSE.txt`, `b5efebcaca80879234098e52d1725e6d9eb8fb96a19fce625d39184b705f7b6d` |
| `mingw-w64-clang-x86_64-compiler-rt 22.1.8-2` | Compiler builtins selected by `-static-libgcc` | `COMPILER-RT-LICENSE.txt`, `1a8f1058753f1ba890de984e48f0242a3a5c29a6a8f2ed9fd813f36985387e8d` |
| `mingw-w64-clang-x86_64-crt 14.0.0.r262.g5ea8e9fac-1` | Native Windows CRT startup/support | `MINGW-W64-CRT-COPYING.txt`, `99a69660981156c21336fdb5661f89341b013c94e4bf9e1c7467b4745718397f`; `MINGW-W64-RUNTIME-COPYING.txt`, `1db8da07b436c68833c0673ffee3d9fcb2526047f3820b81661865dfedc79a1f` |

## Bundled fonts and data

`reduce.resources` contains the two manifest-verified REDUCE-owned AWK helpers.
The runtime font allowlist contains only font binaries, font index files, and
their notices; upstream `reduce.fonts/src/*.asm.gz` development sources are
verified against the upstream manifest but not installed. The installed
`PureReduceInventory.tsv` describes every remaining payload file with origin,
purpose, size, SHA-256, and applicable notice. The external build-tree
`PureReduceExpected.sha256` hashes that installed inventory as well, avoiding
self-hash recursion while keeping the installed inventory machine-readable.
