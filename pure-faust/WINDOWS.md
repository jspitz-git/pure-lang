# pure-faust on Windows

The default `Runtime` component installs `faust2.pure`, its licenses and
documentation, and a compatible prebuilt test module. DSP loading is delegated
to the Pure core, including its Faust bitcode loader, ABI checks, DSP lifecycle,
and cleanup.

The runtime deliberately excludes the legacy native bridge (`faust.cc`,
`faust.dll`, `faust.pure`, and `pure.cpp`) and developer tools such as Faust,
Clang, and LLVM. Those developer tools belong to the optional `FaustDeveloper`
component.

## Install the components

Install the runtime into an existing Pure prefix. Paths may contain spaces:

```powershell
$prefix = Join-Path $env:ProgramFiles 'Pure'
cmake --install build/pure-faust --prefix $prefix --component Runtime
```

Install the optional compiler component into the same prefix only on systems
which build DSP source:

```powershell
cmake --install build/pure-faust --prefix $prefix --component FaustDeveloper
```

The second command does not implicitly install `Runtime`; a complete developer
installation runs both commands.

## Load prebuilt bitcode

With `Runtime` installed in the Pure prefix, a Pure program imports `faust2`
and passes an absolute, extensionless module path to `faust_init`:

```pure
using faust2;
dsp = faust_init "<absolute-module-path-without-.bc>" 48000;
/* use faust_info and faust_compute, then release the instance */
faust_exit dsp;
```

The placeholder names an absolute path and the corresponding file has the
`.bc` suffix. Prebuilt bitcode must target the same Windows x86-64 ABI and LLVM
22 bitcode contract as the Pure runtime. Loading prebuilt bitcode does not
require Faust, Clang, LLVM tools, MSYS2, or a global `PURELIB` setting.

## Build bitcode with FaustDeveloper

The supported helper syntax is:

```powershell
$prefix = Join-Path $env:ProgramFiles 'Pure'
powershell.exe -NoProfile -ExecutionPolicy Bypass -File `
  (Join-Path $prefix 'tools\faust2pure.ps1') `
  -InputPath "<DSP source path>\example.dsp" `
  -OutputPath "<bitcode output path>\example.bc"
```

`-OutputPath` is optional; when omitted, the helper writes a `.bc` file beside
the input. The helper discovers every packaged tool relative to its own
installation, supports input, output, and installation paths containing
spaces, verifies the generated bitcode, and replaces the destination only
after every stage succeeds.

`FaustDeveloper` is a pinned compile-only compatibility set: Faust 2.85.9 and
the reviewed Clang/LLVM 22 closure. It includes only the compiler executables,
DLLs, resource headers, and MinGW headers required to generate and verify the
supported bitcode. It contains no MSYS2 shell, package manager, or
`msys-2.0.dll`, and it does not require an installed MSYS2 environment or host
compiler entries on `PATH`.
