# Windows support

The `pure-tk-examples` applications are not included in the portable Windows
bundle. `pure-tk` and `pure-gtk` provide Tcl/Tk and GTK 2, but these examples
also depend on legacy Tcl extensions which have no compatible MSYS2 CLANG64
package.

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
and its `mds.pure` module imports `octave`. The current MSYS2 VTK package does
not provide the historical Tcl packages expected by this application.

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

