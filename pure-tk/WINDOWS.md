# Windows build and runtime notes

The supported Windows build uses the native MSYS2 CLANG64 Tcl/Tk 8.6 stack.
The build consumes the `mingw-w64-clang-x86_64-tcl` and
`mingw-w64-clang-x86_64-tk` packages through `tcl.pc`; it does not use the
MSYS runtime or an external ActiveTcl installation.

The portable runtime consists of `tcl86.dll`, `tk86.dll`, `zlib1.dll`, and
the complete core `lib/tcl8.6` and `lib/tk8.6` script trees. The script trees
contain `init.tcl`, encodings, timezone data, messages, and themed-widget
support required by Tcl and Tk initialization.

Tcl discovers these libraries relative to the staged `bin/pure.exe`. The
automated test copies the runtime to a path containing spaces, clears
`TCL_LIBRARY`, `TK_LIBRARY`, `TCLLIBPATH`, and `PURELIB`, restricts `PATH` to
the staged runtime and Windows system directories, and verifies the reported
Tcl/Tk library paths and encoding data.

The wrapper is built as `tk.dll`. Its PE closure reuses the bundle's
`libpure.dll`; Tcl adds `zlib1.dll`, while networking, environment, GUI,
common-control, UCRT, and other Windows system DLLs are never copied. The
module and all three bundled DLLs must remain free of MSYS, GCC, and C++
runtime imports.
