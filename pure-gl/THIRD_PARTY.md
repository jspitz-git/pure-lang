# Third-party runtime

The Windows package bundles `libfreeglut.dll` from MSYS2 CLANG64 FreeGLUT.
Its license is installed as `licenses/FreeGLUT.txt`.

OpenGL, GLU, GDI, User32, and WinMM are Windows system components. Their DLLs
must not be copied into the portable distribution.

The traditional callback-based examples also use the separately packaged
`pure-ffi` module. `texture.pure` and `Imlib2.pure` additionally require an
Imlib2 runtime, which is not part of the Windows bundle.
