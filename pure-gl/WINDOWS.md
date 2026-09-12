# Windows build and runtime notes

The audited package is pure-gl 0.9 for native AMD64 Windows. It builds one
`pure-gl.dll` from the GL, GLU, GLUT, ARB, EXT, NV, and ATI C wrappers, using
C11, `-Wall -Wextra -Werror`, CLANG64 FreeGLUT, and Windows OpenGL/GLU import
libraries. MSYS2 supplies build tools; automated Pure execution uses only the
declared portable runtime and Windows system directories.

## Prerequisites and path constraints

The 2026-09-12 audit uses the following installed versions. These are measured
versions, not a promise that arbitrary newer rolling packages satisfy the
pinned import and payload policies.

| Input | Audited version | Explicit location in the commands below |
| --- | --- | --- |
| Canonical portable Pure SDK/runtime | Pure 0.68, 40 files and 9 directories, before installing any extension | `C:/pure-lang/pure/build/windows-clang64-prefix` |
| Clang and LLVM tools | 22.1.8; MSYS2 package revision 22.1.8-2 | `C:/msys64/clang64/bin` |
| CMake / CTest | 4.4.0; project minimum 3.25 | `C:/msys64/clang64/bin` |
| Native GNU Make | 4.4.1, package 4.4.1-5 | `C:/msys64/clang64/bin/mingw32-make.exe` |
| pkgconf | 3.0.4, package `1~3.0.4-1` | `C:/msys64/clang64/bin/pkgconf.exe` |
| FreeGLUT | 3.8.0, package `mingw-w64-clang-x86_64-freeglut` 3.8.0-1 | `C:/msys64/clang64` |
| Ninja (CI generator) | 1.13.2, package 1.13.2-1 | `C:/msys64/clang64/bin/ninja.exe` |
| Repository workflow checks | CLANG64 Python 3.14.6 and PyYAML 6.0.3 | `C:/msys64/clang64/bin/python.exe` |
| Windows system libraries and PowerShell | Native AMD64 Windows installation | `C:/Windows/System32` |

Install the CLANG64 development dependencies and a separately built canonical
Pure SDK before configuring. CI includes `mingw-w64-clang-x86_64-freeglut`,
`mingw-w64-clang-x86_64-make`, and `mingw-w64-clang-x86_64-python-yaml` in its
MSYS2 prerequisite list. A graphics driver capable of creating a hidden
FreeGLUT OpenGL context is required for the mandatory rendering checks.

Use absolute, normalized, canonical paths with no reparse components. The
source and build directories must be disjoint: neither may equal or contain
the other. Both copying release contracts reject overlapping layouts before
creating an audit leaf. Keep the build root short (CI enforces at most 32
characters) because nested Windows release fixtures add long suffixes. The
source path contains spaces; preserve sibling `.github` in repository source
copies so the workflow contract remains registered.

The immutable Pure SDK prefix must be ASCII and contain no spaces for the
public native Make/pkgconf path. Native Windows command parsing splits the
POSIX backslash-escaped include/library flags produced for a spaced SDK
prefix. This constraint does not prohibit spaces in source or tool paths.
Keep the final stage separate from the source, build, SDK, CLANG64, and system
roots; installation rejects equal, ancestor, or descendant protected roots.

The final audit stage deliberately contains spaces and non-ASCII text, such
as `gl package café`. Pure 0.68 derives its default library path from its
executable prefix as UTF-8, but its prelude checks/loading use narrow Windows
CRT `stat`/`fopen`. On the audited ACP 1250 host a physical Unicode executable
prefix therefore loses the prelude, producing missing-operator diagnostics
even with Pure exit status zero. An independent executable/script 2x2 probe
and wide/ACP/UTF-8 native path probe isolated this boundary.

The supervisor launches that same stage's `pure.exe` through its OS-provided
ASCII Windows 8.3 spelling. It verifies the physical canonical path, every
component and volume/file identity, and retains handles for both spellings
through execution. All scripts, interfaces, DLLs, inventory, hashes, and PE
checks still use the physical stage. The stage volume must already supply a
valid ASCII 8.3 alias; absent, non-ASCII, external, or wrong-identity aliases
fail closed. The gate does not enable 8.3 names, copy to an ASCII execution
stage, or select another Pure runtime. `café` is representable on the tested
ACP 1250 and expected hosted ACP 1252; arbitrary Unicode Pure argument paths
are not claimed to work.

## Strict configure and release commands

Run this PowerShell example from the checkout, selecting fresh paths. The
function stops immediately on a failed native command. The strict cache pins
the exact tools; do not replace the hashes with unchecked current hashes to
make an upgraded tool pass.

```powershell
$ErrorActionPreference = 'Stop'
$glCheckout = (Get-Location).Path.Replace('\', '/')
$glSource = 'C:/pure-lang/gl source/pure-gl'
$glBuild = 'C:/pure-lang/gl8'
$glSdk = 'C:/pure-lang/glp'
$glStage = 'C:/pure-lang/gl package café'
$glTools = 'C:/msys64/clang64/bin'
$glCmake = "$glTools/cmake.exe"
function Invoke-GLNative([string]$Exe, [string[]]$Arguments) {
  & $Exe @Arguments
  if ($LASTEXITCODE -ne 0) { throw "GL command failed ($LASTEXITCODE): $Exe" }
}
foreach ($glPath in @('C:/pure-lang/gl source', $glBuild, $glSdk, $glStage)) {
  if (Test-Path -LiteralPath $glPath) { throw "Fresh path already exists: $glPath" }
}
if ($glBuild.Length -gt 32) { throw 'Use a build root at most 32 characters long' }
$env:PATH = "$glTools;C:/Windows/System32;C:/Windows"
$env:PKG_CONFIG_PATH = ''
$env:PKG_CONFIG_LIBDIR = "$glSdk/lib/pkgconfig;C:/msys64/clang64/lib/pkgconfig"
$env:PURE_INCLUDE = ''
$env:PURE_LIBRARY = ''
Remove-Item Env:PKG_CONFIG_SYSROOT_DIR -ErrorAction SilentlyContinue
Remove-Item Env:PURELIB -ErrorAction SilentlyContinue
Invoke-GLNative $glCmake @('-E', 'copy_directory', "$glCheckout/pure-gl", $glSource)
Invoke-GLNative $glCmake @('-E', 'copy_directory', "$glCheckout/.github", 'C:/pure-lang/gl source/.github')
Invoke-GLNative $glCmake @('-E', 'copy_directory', 'C:/pure-lang/pure/build/windows-clang64-prefix', $glSdk)
Invoke-GLNative $glCmake @(
  '-S', $glSource, '-B', $glBuild, '-G', 'Ninja',
  '-DCMAKE_BUILD_TYPE=Release', '-DBUILD_TESTING=ON', '-DPURE_GL_STRICT_AUDIT=ON',
  "-DCMAKE_MAKE_PROGRAM=$glTools/ninja.exe",
  "-DCMAKE_C_COMPILER=$glTools/clang.exe",
  '-DCMAKE_C_COMPILER_TARGET=x86_64-w64-windows-gnu',
  "-DPURE_EXECUTABLE=$glSdk/bin/pure.exe", "-DPURE_GL_PURE_PREFIX=$glSdk",
  '-DPURE_GL_CLANG64_PREFIX=C:/msys64/clang64',
  '-DPURE_GL_WINDOWS_SYSTEM_DIRECTORY=C:/Windows/System32',
  "-DPKG_CONFIG_EXECUTABLE=$glTools/pkgconf.exe",
  "-DGNU_MAKE_EXECUTABLE=$glTools/mingw32-make.exe",
  "-DLLVM_READOBJ_EXECUTABLE=$glTools/llvm-readobj.exe",
  '-DLLVM_READOBJ_SHA256=040c4cb0740d2a9d9f7b488bc676c0406eb12c7b349acba1797c2f58865087cb',
  "-DLLVM_STRINGS_EXECUTABLE=$glTools/llvm-strings.exe",
  '-DLLVM_STRINGS_SHA256=8d04b5a905fc4d42ee21ae075ced38f5d9a937dbbc03aa571f409002f1bbd411'
)
Invoke-GLNative $glCmake @('--build', $glBuild, '--parallel', '4')
Invoke-GLNative $glCmake @('--build', $glBuild, '--target', 'verify-windows-dependencies', '--parallel', '4')

$env:PATH = 'C:/Windows/System32;C:/Windows'
Remove-Item Env:PURELIB -ErrorAction SilentlyContinue
Invoke-GLNative "$glTools/ctest.exe" @('--test-dir', $glBuild, '-L', 'gl', '--output-on-failure', '--no-tests=error')
Invoke-GLNative "$glTools/mingw32-make.exe" @('--no-print-directory', '-C', $glSource, 'distcheck',
  "CMAKE=$glCmake", "PKG_CONFIG=$glTools/pkgconf.exe", "DIST_AUDIT_BUILD=$glBuild")
Invoke-GLNative $glCmake @('-E', 'copy_directory', $glSdk, $glStage)
Invoke-GLNative $glCmake @('--install', $glBuild, '--prefix', $glStage, '--component', 'runtime')
Invoke-GLNative $glCmake @('--install', $glBuild, '--prefix', $glStage, '--component', 'documentation')
Invoke-GLNative $glCmake @("-DGL_INSTALL_CONTEXT=$glBuild/pure-gl-install-context.cmake",
  "-DSTAGE_PREFIX=$glStage", '-P', "$glSource/cmake/VerifyInstalledPackage.cmake")
```

All strict executable inputs must name regular files. pkg-config lookup is
restricted to the explicit SDK and CLANG64 metadata, and the returned Pure and
FreeGLUT prefixes/include/library paths must match those authorities. The
default fixed destinations are `PURE_LIBRARY_INSTALL_DIR=lib/pure`,
`PURE_DOCUMENTATION_INSTALL_DIR=share/doc/pure-gl`, and
`PURE_EXAMPLES_INSTALL_DIR=share/doc/pure-gl/examples`; other layouts fail.
Changing sealed source, documentation, baseline, tool, or license inputs
requires a fresh configured build.

On the local audit host both Ninja 1.11.1 and 1.13.2 stalled on `.ninja_lock`
before compilation. Local evidence therefore uses `-G 'MinGW Makefiles'`,
`-DCMAKE_MAKE_PROGRAM=C:/msys64/clang64/bin/mingw32-make.exe`, and the recorded
host compiler-probe overrides `-DCMAKE_C_COMPILER_WORKS=1` and
`-DCMAKE_C_ABI_COMPILED=1`. The real module and helpers still compile with four
workers and warnings as errors. The top-level CI configure uses Ninja and
normal compiler probing;
the local fallback is not evidence of a hosted Ninja run. Locally the
registered CLANG64 Python 3.14.6 uses PyYAML from native Python 3.14.5's
installed site-packages via `PYTHONPATH`; CI installs CLANG64 `python-yaml`.
The native install guard needs Windows named-pipe access, including in a
sandbox; its authentication must not be bypassed.

## Runtime, tests, and CI

The supervisor constructs a fresh child environment containing only `PATH`,
`SystemRoot`, and `WINDIR`; `PURELIB` and inherited MSYS2 search paths are
absent. Build-tree PATH consists of SDK `bin`, module directory, the selected
FreeGLUT copy in `pure-gl-runtime`, and `C:/Windows/System32`. Installed PATH
consists of stage `bin`, stage `lib/pure`, and System32. Tests run from
`C:/Windows`, outside source and build trees. Retained no-follow handles bind
the inputs, and a Job Object bounds the complete child tree. Success requires
exit zero, empty stderr, and one terminal `PURE_GL_TEST_OK <random-token>`
completion line. The supervisor has a 90-second functional deadline, the
adapter adds a five-second outer margin, and each functional CTest has a
100-second limit.

`ctest -L gl` runs all ten repository tests: load-all-modules, hidden-render,
runtime-verifier, configure, runner, source-dist, cleanup, install,
install-guard, and workflow contracts. All carry `gl`; additional labels are
`load`, `render`, `contract`, `pe`, `release`, `install`, and `workflow` as
appropriate. The load test covers all seven interfaces. Hidden rendering
creates and hides a 32 by 32 RGBA FreeGLUT window, checks nonempty OpenGL
vendor/renderer/version strings, checks the pixel against `[64,128,191,255]`
with a tolerance of two per channel, checks errors, and
destroys the window before authenticated completion. The separate
`pure-gl-render-contract` build target exercises script-semantic mutations;
it is not an extra registered CTest.

Visible desktop validation remains opt-in and is never registered as a CTest:

```powershell
Invoke-GLNative $glCmake @('--build', $glBuild, '--target', 'check-gl-interactive', '--parallel', '4')
```

It shows a 320 by 240 RGB triangle for one second, processes the display event,
checks OpenGL errors, destroys the window, and terminates through the same
supervisor. The 2026-09-12 follow-up did not rerun this visible target; the
2026-07-28 desktop observation remains historical evidence.

`.github/workflows/non-linux-release-validation.yml` makes the strict gate
mandatory in the existing Windows 2025 job. Both push and pull-request filters
include `pure-gl/**`, TODO-35, the approved design, and its plan. Six
unconditional PowerShell steps snapshot Pure immediately after its portable
installation, configure a separate short Release/Ninja tree, build and inspect
PE with four workers, run every `gl` CTest, run public `distcheck` independently,
and install/verify both components in `${{ runner.temp }}/gl package café`.
The SDK copy is `${{ runner.temp }}/glp`, the build is `${{ runner.temp }}/gl8`,
and the source is `${{ runner.temp }}/pure gl source/pure-gl`. Every native
failure stops its step. The workflow semantic validator and independent
mutation suite check commands, environments, ordering, failure guards and
artifacts. An `always()` upload preserves GL logs and the build for 14 days.
Local verification does not establish hosted 8.3 availability, graphics
support, or the combined job's fit within its unchanged 120-minute timeout.

## Exact package and dependency inventory

The sealed build inventory is `pure-gl-install-inventory.tsv`; each row binds
component, destination, canonical source, SHA-256, project, version, source
URL, license identity, and installed notice mapping. The generated
`pure-gl-install-context.cmake` is the public verifier input. Keep it and its
matching source/build/helpers available when auditing a stage; a loose list
of caller-selected payload paths is not a substitute for that authority.

| Component | Exact added files |
| --- | --- |
| runtime (9) | `lib/pure/pure-gl.dll`; `lib/pure/{GL,GL_ARB,GL_EXT,GL_NV,GL_ATI,GLU,GLUT}.pure`; `bin/libfreeglut.dll` |
| documentation (17) | Under `share/doc/pure-gl`: `README`, `COPYING`, `WINDOWS.md`, `THIRD_PARTY.md`; `examples/{simple_glut_example.pure,teapot.pure,texture.pure,Imlib2.pure,fractal.jpg}`; `examples/flexi-line/{vector_math.pure,glamour.pure,flexi-line.pure,flexi-line-auto.pure}`; `tests/{load,hidden-render,interactive}.pure`; `licenses/FreeGLUT.txt` |

The audited baseline has 49 entries (40 files, 9 directories). The components
add exactly 26 disjoint files and six directories: `share/doc`,
`share/doc/pure-gl`, and its `examples`, `examples/flexi-line`, `licenses`, and
`tests` descendants. The final tree has **49 + 26 + 6 = 81 entries**, comprising
66 files and 15 directories. Native retained identity/exclusion and absent
destination reservations protect installation; controlled failure rolls back
only transaction-owned output. This is not a whole-tree crash/power-loss
atomicity guarantee. The verifier requires unchanged baseline bytes plus the
exact delta, runs both staged functional tests, repeats PE validation, and
requires an identical final snapshot with no residue. Both components are
required for complete verification.

The exact normal-import closure contains 12 non-system AMD64 binaries and
141 import edges, plus ten terminal AMD64 system binaries: **22 PE files** in
all. The package contributes `pure-gl.dll` and `libfreeglut.dll`; the canonical
Pure baseline supplies `libc++.dll`, `libgmp-10.dll`, `libiconv-2.dll`,
`libmpfr-6.dll`, `libpcre-1.dll`, `libpcreposix-0.dll`, `libpure.dll`,
`libwinpthread-1.dll`, `libzstd.dll`, and `zlib1.dll`. Exact fixtures reject
missing/unexpected imports, ambiguous or shadow origins, reparses, wrong
architecture, unreviewed runtime names, and decorated FreeGLUT loader strings.

System imports resolve only to the actual Windows `System32`: `advapi32.dll`,
`gdi32.dll`, `kernel32.dll`, `ntdll.dll`, `ole32.dll`, `opengl32.dll`,
`shell32.dll`, `ucrtbase.dll`, `user32.dll`, and `winmm.dll`. These are terminal
OS dependencies, not recursively bundled files. `glu32.dll` is also an
OS-provided GLU binding dependency and forbidden payload, although it is not
a normal-import entry in this pinned graph. Never bundle Windows OpenGL,
GLU, GDI, User32, or WinMM DLLs. See [THIRD_PARTY.md](THIRD_PARTY.md) for the
FreeGLUT runtime/notice provenance and pins.

The pinned `llvm-readobj` emits a physical Unicode filename as UTF-8 in its
`File:` line. The PE parser accepts non-ASCII only in that exact canonical
physical `File:` field, with raw bytes preserved; all other records retain
strict ASCII grammar. Invalid UTF-8, a different physical path, or non-ASCII
structural/import records fail. PE inspection does not use an alias path.

## Public source archive and cleanup

The public `make distcheck` command above requires `DIST_AUDIT_BUILD` to name
the matching strict CMake build. It verifies the retained canonical
`CMAKE_HOME_DIRECTORY` before dispatching the source contract. That contract
runs public `make dist` in an owned spaced source copy and validates exactly
**78 regular files and 9 directory entries**, including the CMake build, all
helpers/native helper sources, Windows/provenance documentation, and tests.
It checks archived bytes against the input snapshot (including README's
declared version/date substitution), removes the copied
source, rejects missing/extra/stale-generated/symlink mutations, and performs
an extracted strict build, four-worker generation, exact PE audit, and eight
non-source-dist contracts. The standalone archive registers nine tests;
repository `.github` is not shipped, so its workflow test is not registered.

To create only the public `pure-gl-0.9.tar.gz` archive, use the same explicit
Make/CMake/pkgconf environment and replace `distcheck` with `dist`. Archive
creation alone is not the full release verification. Keep source hashes,
archive SHA-256, inventory, and CTest output with release evidence.

Public `clean`, `realclean`, `generate`, `dist`, and `distcheck`, and inherited
contract cleanup use fixed owned leaves, build/source-bound sentinel checks,
no-follow native ownership, and protected-descendant rejection. Unsafe
suffixes, aliases, reparses, hardlinks, overlapping roots, wrong sentinels,
and inherited override attempts fail before mutation. `clean` preserves
wrappers and unrelated bytes, `realclean` removes the owned generated
wrappers, and `generate` actually rebuilds with four workers, including when
the selected Make executable path contains spaces and an ampersand.
