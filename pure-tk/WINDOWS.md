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

A second bounded smoke test withdraws the root window, creates and invokes a
button backed by a real Pure callback, processes a scheduled Tk event, destroys
the root window, and verifies that the interpreter shuts down. No test window
requires user interaction.

The wrapper is built as `tk.dll`. Its PE closure reuses the bundle's
`libpure.dll` and `zlib1.dll`, while networking, environment, GUI,
common-control, UCRT, and other Windows system DLLs are never copied. The
module and all three bundled DLLs must remain free of MSYS, GCC, and C++
runtime imports.

The optional `gnocl.pure` interface is not installed by this core package. It
requires a separate Gnocl Tcl extension plus the GTK/XML stack and is evaluated
with the examples after the Windows `pure-gtk` investigation.
## Build, test, and stage

From an MSYS2 CLANG64 shell, point `PKG_CONFIG_PATH` at the staged Pure SDK
and run:

```sh
cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_C_COMPILER=clang -DBUILD_TESTING=ON
cmake --build build
cmake --build build --target verify-windows-dependencies
ctest --test-dir build --output-on-failure
```

Copy the portable Pure runtime to a fresh prefix before installing pure-tk,
then verify that complete stage:

```sh
cmake --install build --prefix "C:/tmp/Pure Tk Stage"
cmake -DSTAGE_PREFIX="C:/tmp/Pure Tk Stage" \
  -DSOURCE_PREFIX=C:/path/to/pure-runtime \
  -DLLVM_READOBJ=/clang64/bin/llvm-readobj.exe \
  -P cmake/VerifyInstalledPackage.cmake
```

The installed verifier checks both GUI tests, the Tcl/Tk discovery paths,
reused DLL hashes, required script/data files, and the staged PE closure.
