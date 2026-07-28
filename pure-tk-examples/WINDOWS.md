# Windows support

The `pure-tk-examples` applications are not included in the portable Windows
bundle. `pure-tk` and `pure-gtk` provide Tcl/Tk and GTK 2, but these examples
also depend on legacy Tcl extensions which have no compatible MSYS2 CLANG64
package.

## Inventory

All three top-level applications are interactive and currently deferred. None
has an automated mode which can run independently of its GUI dependencies.
The 56 application source and data files are grouped as follows:

- `graphedit` (10 files): the Pure application, Gnocl UI script and icon;
  sample graph files; graph algorithm example; README, license, and Makefile.
  Runtime imports are `tk`, `gnocl`, `dict`, `set`, and `system`, plus the
  Gnocl and GnoclCanvas Tcl packages.
- `pong` (5 files): the Pure application, Gnocl UI script, icon, README, and
  Makefile. Runtime imports are `tk`, `gnocl`, `system`, and `math`, plus the
  Gnocl and GnoclCanvas Tcl packages.
- `scale` (41 files): the main application, five local Pure modules, Gnocl/VTK
  UI script, Octave script, interval-name data, 25 Scala scale files,
  documentation, icon, license, and Makefile. Runtime imports add Pure Octave,
  Octave, Gnocl, and the `vtk` and `vtkinteraction` Tcl packages.

Each directory is an indivisible payload because the programs open their
adjacent scripts and data by relative path.

## Support matrix

| Application | Windows status | Additional runtime dependencies |
| --- | --- | --- |
| `graphedit` | Deferred | Gnocl, GnoclCanvas, GTK 2 |
| `pong` | Deferred | Gnocl, GnoclCanvas, GTK 2 |
| `scale` | Deferred | Gnocl, VTK Tcl bindings, Pure Octave, Octave |

`graphedit` and `pong` both execute `package require Gnocl` and
`package require GnoclCanvas`. The canvas extension is essential to their
user interfaces, so installing GTK 2 alone is insufficient.

`scale` executes `package require vtk` and `package require vtkinteraction`,
and its `mds.pure` module imports `octave`. The current staged runtime does not
expose these historical Tcl packages; installing the available MSYS2 VTK 9
package alone would not make them available.

## Verification

Run the dependency probe against a staged `pure-tk` package:

```powershell
cmake `
  -DSTAGE_PREFIX=C:/path/to/pure-tk-stage `
  -DSOURCE_DIR=C:/path/to/pure-tk-examples `
  -P C:/path/to/pure-tk-examples/cmake/VerifyWindowsSupport.cmake
```

The probe starts the staged Tcl/Tk interpreter through `pure-tk` and performs
bounded `package require` calls. It succeeds only while all four required Tcl
packages are unavailable, matching the deferred support classification.

## Future enablement

Reconsider packaging after all of the following are available as x86-64
CLANG64-compatible components:

1. Gnocl and GnoclCanvas built against the bundled Tcl 8.6 and GTK 2 stack.
2. A closed PE dependency set for both Tcl extensions, including their data
   files and license texts.
3. For `scale`, compatible VTK Tcl bindings and a packaged Pure Octave stack.
4. Bounded startup, interaction, callback, and shutdown tests for each
   application.

When those conditions are met, preserve each application directory as a unit.
The programs read their `.tcl`, image, graph, scale, and parameter files
relative to the current directory.

