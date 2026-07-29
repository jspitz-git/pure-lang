# pure-gplot on Windows

`pure-gplot` keeps its Pure API (`open`, `puts`, and `close`) and uses a small
native `gplot.dll` bridge on Windows. The bridge launches one exact executable
with `CreateProcessW`; it does not invoke `cmd.exe` and it does not search
`PATH`.

## Optional gnuplot component

The supported managed dependency is the official x86-64 Windows Clang build
of gnuplot 6.0.4 (`gp604-win64-clang.exe`). Its required SHA-256 is:

```
2c31e3fc91b21c450f4b015f1cd1f2f84f7a8cfc63afc037f9ba5efb47cc0c23
```

`cmake/AcquireWindowsGnuplot.cmake` downloads the pinned SourceForge artifact,
checks that hash, installs it below a caller-controlled work directory, and
verifies `gnuplot 6.0 patchlevel 4`.

The optional distribution is installed below `tools/gnuplot`. Its upstream
license tree is retained there and copied to
`share/doc/pure-gplot/licenses/gnuplot`. The upstream installer's own
`unins000.exe` and `unins000.dat` are not packaged because the enclosing Pure
installer owns component removal.

Configure packaging with:

```powershell
cmake -S pure-gplot -B "C:\tmp\Pure Gplot Build" -G Ninja `
  -DPURE_PREFIX="C:\path\to\portable-pure" `
  -DGNUPLOT_ROOT="C:\path\to\controlled-gnuplot" `
  -DPURE_GPLOT_INSTALL_GNUPLOT=ON
cmake --build "C:\tmp\Pure Gplot Build"
cmake --install "C:\tmp\Pure Gplot Build" --prefix "C:\path\to\stage"
```

Leave `PURE_GPLOT_INSTALL_GNUPLOT=OFF` to install the binding and its
documentation without the managed gnuplot tree. At runtime, `GPLOT_EXE` can override the executable with an exact
path. Without that override, the bridge derives
`tools/gnuplot/bin/gnuplot.exe` from its installed DLL location. A missing
optional component causes `open` to return a null pointer; there is no fallback
to a host installation.

## Tests

Normal Windows tests cover command input and deterministic PNG rendering. Set
`PURE_GPLOT_INTERACTIVE_TESTS=ON` only on an interactive desktop to add the
short-lived `windows` terminal smoke test.
## Installed-package verification

The verifier compares the portable runtime DLLs with the source bundle, so
both paths are required:

```powershell
cmake -DSTAGE_PREFIX="C:\path\to\pure-stage" `
  -DSOURCE_RUNTIME_DIR="C:\path\to\source-bundle\bin" `
  -P pure-gplot\cmake\VerifyInstalledPackage.cmake
```

It renders through the bundle-relative executable and tests the absent-component
case in a disposable miniature prefix; it never renames or edits the supplied
stage.
