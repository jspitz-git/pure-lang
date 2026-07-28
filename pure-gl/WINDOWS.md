# Windows build and runtime notes

The supported Windows build uses 64-bit MSYS2 CLANG64 FreeGLUT and the native
Windows OpenGL/GLU libraries. MSYS2 is a build environment only; the resulting
Pure module runs from a native Windows prefix.

The package builds one `pure-gl.dll` module from the GL, GLU, GLUT, ARB, EXT,
NV, and ATI wrapper sources and installs their seven matching Pure interfaces.
`libfreeglut.dll` is bundled. `opengl32.dll`, `glu32.dll`, `gdi32.dll`, and
`winmm.dll` are Windows system components and must never be bundled.

Automated rendering tests use a hidden FreeGLUT window, verify rendered pixels,
destroy the window, and terminate without user interaction. They have both
CTest and inner process timeouts.

Visible desktop validation is deliberately opt-in and never registered as a
CTest. From a configured build tree run:

    cmake --build build/windows-clang64-gl --target check-gl-interactive

The target shows a 320 by 240 RGB triangle for one second, verifies that all
OpenGL calls succeeded, closes the window, and terminates automatically.
