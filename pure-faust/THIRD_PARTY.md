# Third-party developer component

## Faust 2.85.9

The optional `FaustDeveloper` component redistributes two files selected from
the official Faust 2.85.9 Windows release: `bin/faust.exe` and
`share/faust/pure.c`. No other file from the 4,258-file installed tree is
selected.

- Release tag: `2.85.9`
- Windows asset: `Faust-2.85.9-win64.exe`
- URL: <https://github.com/grame-cncm/faust/releases/download/2.85.9/Faust-2.85.9-win64.exe>
- Size: `109591809` bytes
- SHA-256: `d0994eb444ab4b1e75e3ed7c31897da24013db0672e2c6be8f2ab09b73d16977`
- Installed `bin/faust.exe` SHA-256:
  `66327ceb3ed7170859a010767488028f333247ed80f9d4b38a08113073644a2a`
- Installed CRLF `share/faust/pure.c` SHA-256:
  `c41948c5fad4c5e6f458559f862b228215b29577f7bb168848aac0e835688b63`

The installed compiler reports `FAUST Version 2.85.9`. Its `pure.c` is byte-for-
byte identical to `architecture/pure.c` from the official source archive after
normalizing CRLF to LF.

- Source asset: `faust-2.85.9.tar.gz`
- URL: <https://github.com/grame-cncm/faust/releases/download/2.85.9/faust-2.85.9.tar.gz>
- Size: `79259467` bytes
- Locally computed SHA-256:
  `0cd00968f81357b78df64c25aad12ec94bd4b75bd489ca0449fe7f7b1ad0efe1`
- Source `COPYING.txt` SHA-256:
  `92a42adab3110694eb7731691f57f229fcaba31570d1727eb7be3f197307378c`
- License: GNU Lesser General Public License, version 2.1 or later
- Installed license copy: `share/doc/pure-faust/licenses/Faust-COPYING.txt`

## Relocatable Clang/LLVM 22 compile-only closure

The component includes a deliberately bounded compiler closure from the MSYS2
CLANG64 prefix. MSYS2 is build provenance only; the installed product neither
requires nor ships the MSYS2 runtime or package-manager state.

- Supplying packages: `mingw-w64-clang-x86_64-clang 22.1.8-2`,
  `clang-libs 22.1.8-2`, `llvm 22.1.8-2`, `llvm-libs 22.1.8-2`,
  `libffi 3.7.1-1`, `libiconv 1.19-1`, `libxml2 2.15.3-1`,
  `zlib 1.3.2-2`, `zstd 1.5.7-2`, and MinGW-w64 `headers`/`crt`
  `14.0.0.r220.gd999af622-1`
- Executables: `clang.exe`, `opt.exe`
- Transitive non-system DLLs: `libLLVM-22.dll`, `libclang-cpp.dll`,
  `libc++.dll`, `libffi-8.dll`, `zlib1.dll`, `libzstd.dll`,
  `libxml2-16.dll`, and `libiconv-2.dll`
- Clang resource headers: `lib/clang/22/include`, 300 files, 15,554,443
  bytes; sorted SHA-256 inventory
  `3e14c739b60d15a7c0f255734b13859e142d990a8e2fc8cf12eb74196e87cff3`
- MinGW include root reported by `clang -E -x c -v NUL`: `include`. Only
  the 2,056 files (95,930,515 bytes) owned by the pinned MinGW-w64 `headers`
  and `crt` package manifests are selected; 10,801 unrelated-package headers sharing that
  physical root are excluded. The sorted inventory SHA-256 is recorded in
  `CompilerClosure.cmake` as
  `6beada17367e62412d6244d98721a4fc015ae4c0db4d897dd17487e7489b44cd`.
- LLVM/Clang license: Apache-2.0 WITH LLVM-exception, installed as
  `licenses/LLVM-Apache-2.0-WITH-LLVM-exception.txt`, SHA-256
  `8d85c1057d742e597985c7d4e6320b015a9139385cff4cbae06ffc0ebe89afee`
- MinGW-w64 license evidence: installed as
  `licenses/MinGW-w64-COPYING.txt`. It aggregates the pinned header package's
  `COPYING`, project, runtime, and DDK notices; SHA-256
  `841dcac31b495c708d68622d0ace296acf9f9783375220ad02f6d61a59ca9ae5`

`CompilerClosure.cmake` records and validates the SHA-256 of every executable
and DLL and the sorted per-file inventories of both header roots. It is the
authoritative exact allowlist. Shells, package-manager databases, link-only
libraries, and `msys-2.0.dll` are forbidden.

## Fixed FaustDeveloper files

- `bin/faust.exe`
- `cmake/CompilerClosure.cmake`
- `cmake/RunFaust2Pure.cmake`
- `share/doc/pure-faust/THIRD_PARTY.md`
- `share/doc/pure-faust/licenses/Faust-COPYING.txt`
- `share/doc/pure-faust/licenses/LLVM-Apache-2.0-WITH-LLVM-exception.txt`
- `share/doc/pure-faust/licenses/MinGW-w64-COPYING.txt`
- `share/pure-faust/pure.c`
- `tools/faust2pure.ps1`

The compiler-closure files declared above are appended to these fixed files.
