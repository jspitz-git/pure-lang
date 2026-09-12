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

OpenGL, GLU, GDI, User32, and WinMM are Windows system components. Their DLLs
must not be copied into the portable distribution.

The traditional callback-based examples also use the separately packaged
`pure-ffi` module. `texture.pure` and `Imlib2.pure` additionally require an
Imlib2 runtime, which is not part of the Windows bundle.
