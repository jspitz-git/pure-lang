# Third-party runtime

The Windows package bundles FreeGLUT 3.8.0 from MSYS2 CLANG64 package
`mingw-w64-clang-x86_64-freeglut` 3.8.0-1. Its upstream source is the
[FreeGLUT 3.8.0 release archive](https://github.com/FreeGLUTProject/freeglut/releases/download/v3.8.0/freeglut-3.8.0.tar.gz).
The inventory records MIT, following the
[MSYS2 package license metadata](https://packages.msys2.org/packages/mingw-w64-clang-x86_64-freeglut).
The complete notice, including its advertising-name restriction, is copied
unchanged to `share/doc/pure-gl/licenses/FreeGLUT.txt`.

The strict inventory binds these two files to the same explicit, canonical
`PURE_GL_CLANG64_PREFIX`. These SHA-256 pins identify the audited payloads:

| Payload | Exact source relative to the CLANG64 prefix | SHA-256 |
| --- | --- | --- |
| FreeGLUT 3.8.0 runtime | `bin/libfreeglut.dll` | `a297e3b3fa824de6eb21285e23a409fbbf0bc573c60dd04c227bbc89d8398519` |
| FreeGLUT notice | `share/licenses/freeglut/COPYING` | `b6593d5ec4c113a274abb85b10e8615895cb0ddb89f7912af5fe5aa8df38a275` |

The DLL installs as `bin/libfreeglut.dll` in the runtime component. The notice
belongs to the documentation component. The inventory records project,
version, upstream source, license, installed notice path and each payload's
source hash; both components are required for the complete package audit.
An identical file selected from another prefix or license directory is not
accepted as the declared source. Updating either payload requires a reviewed
pin update and a fresh configured build.

For the audited `C:/msys64/clang64` prefix, the runtime is 359,936 bytes and the
notice is 1,439 bytes. Strict configuration also requires the header
`include/GL/freeglut.h` and import library `lib/libfreeglut.dll.a` from that
same prefix and cross-checks pkg-config's resolved include/library paths.
Neither development input is a portable package payload. Build-tree tests
load an explicitly staged copy of the pinned DLL from `pure-gl-runtime`;
the CLANG64 `bin` directory is absent from the supervised runtime PATH.

The generated `pure-gl-install-inventory.tsv` binds each source and hash to
its component and destination. The complete stage is the unchanged 49-entry
Pure baseline plus nine runtime files, 17 documentation files, and six new
directories: 81 entries (66 files, 15 directories). It contains exactly one
FreeGLUT notice payload. The installed verifier checks both component seals,
the actual notice bytes, and the same source-origin mapping before running
the staged load/render tests and final no-residue scan. Mutable inventory
files are data; the configured native authority and retained file identities
must agree with them.

OpenGL, GLU, GDI, User32, and WinMM are Windows system components. Their DLLs
must not be copied into the portable distribution.

The pinned normal-import closure is 12 non-system AMD64 binaries, 141 import
edges, and ten terminal AMD64 Windows binaries (22 inspected PE files). The
ten non-system dependencies beyond this package's two DLLs are already owned
by the canonical Pure baseline, not additional pure-gl payloads. Exact import
fixtures, canonical origin checks, and the complete stage inventory reject
unreviewed dependencies and system-DLL copies. The full dependency names,
strict tool hashes, commands, and path limitations are in
[WINDOWS.md](WINDOWS.md).

For a Unicode stage, only Pure's executable launch uses an identity-checked
ASCII 8.3 spelling of that same physical `pure.exe`. FreeGLUT provenance and
PE inspection continue to use the physical stage; non-ASCII PE-reader output
is allowed only in its exact physical UTF-8 `File:` field. A host without a
valid ASCII 8.3 executable alias fails verification. This does not authorize
an alternate runtime source or relax the pinned notice/DLL checks.

The traditional callback-based examples also use the separately packaged
`pure-ffi` module. `texture.pure` and `Imlib2.pure` additionally require an
Imlib2 runtime, which is not part of the Windows bundle.
