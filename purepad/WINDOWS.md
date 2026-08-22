# PurePad on Windows

PurePad is built and shipped as a 64-bit Visual Studio 2022 shared-MFC
application.  It starts the Pure interpreter from `pure.exe` beside
`purepad.exe`; a deployment must therefore place both programs in the same
`bin` directory.

## User data

By default PurePad stores its profile, history, and settings under
`%APPDATA%\Pure\PurePad`.  Set `PUREPAD_USER_DATA` to an existing or writable
directory to place that data elsewhere.  The environment variable is the
per-user override; it does not change the executable-relative lookup of
`pure.exe`.

## Build and install

From this directory, use the reproducible Visual Studio 2022 x64 commands:

```powershell
cmake --preset vs2022-x64
cmake --build --preset vs2022-x64-release --parallel 4
ctest --test-dir build/vs2022-x64 -C Release --output-on-failure
cmake --install build/vs2022-x64 --config Release --component PurePad --prefix C:\PurePad-stage
```

The `PurePad` component installs `bin\purepad.exe` and this document.  It is
the handoff artifact consumed by TODO-49's installer work.

## Installer ownership

PurePad itself does not register or update a file association when it starts.
TODO-49's installer may offer an optional `.pure` association and owns its
installation, upgrade, and removal in both per-user and administrative modes.
PurePad continues to open files supplied on its command line or through DDE;
drag and drop remains available.

TODO-49 must also install the matching Microsoft Visual C++ Redistributable
for the target architecture.  Its required shared runtime DLLs are:

- `mfc140u.dll`
- `MSVCP140.dll`
- `VCRUNTIME140.dll`
- `VCRUNTIME140_1.dll`

Do not copy these DLLs from a Visual Studio installation.  The installer must
use the matching Microsoft Visual C++ Redistributable instead.  The installed
`purepad.exe` is independent of MSYS2; using MSYS2 to run the build commands
does not make MSYS2 a deployment dependency.
