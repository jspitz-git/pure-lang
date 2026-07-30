# TODO-51 Task 1 Report: Octave AppContainer Canonicalization RED

Date: 2026-07-30

## Outcome

The standalone probe in
`pure-octave/probes/windows_canonicalize_appcontainer.c` reduces the GNU
Octave 11.3.0 failure to one public Windows API call.  For the same existing
staged file, an ordinary process returns a normalized path.  A
zero-capability AppContainer process successfully opens, reads, and enumerates
the file, but `GetFinalPathNameByHandleW` returns zero with
`ERROR_ACCESS_DENIED`.  This is a precise RED reproducer, not a runtime fix.

`FILE_NAME_OPENED` does not avoid the failure.  The public
`GetFileInformationByHandleEx(FileNameInfo)` API does work in the packaged
process and returns the same nonempty, volume-relative handle path as the
ordinary process.

## Source provenance

The inputs were kept outside the repository:

- Archive: `C:\tmp\octave-11.3.0-source-task51\octave-11.3.0.tar.xz`
- Detached signature:
  `C:\tmp\octave-11.3.0-source-task51\octave-11.3.0.tar.xz.sig`
- Extracted source:
  `C:\tmp\octave-11.3.0-source-task51\src\octave-11.3.0`
- Official URLs:
  `https://ftp.gnu.org/gnu/octave/octave-11.3.0.tar.xz` and its `.sig`
- Verification keyring:
  `https://ftp.gnu.org/gnu/gnu-keyring.gpg`, downloaded only into the
  disposable build directory and removed after verification

Fresh `Get-FileHash -Algorithm SHA256` output:

```text
2B80F3149B2DE6D1F4F2FCB4FE6515A17EB363B52111BF57B90F37BF6F5E12E1
```

Fresh detached-signature replay used:

```powershell
$verifyRoot = "C:/pure-lang/.task1-signature-<unique-id>"
if (Test-Path -LiteralPath $verifyRoot) { throw "verification root exists" }
New-Item -ItemType Directory -Path $verifyRoot | Out-Null
gpgv.exe --status-fd 1 `
  --keyring "$verifyRoot/gnu-keyring.gpg" `
  C:/tmp/octave-11.3.0-source-task51/octave-11.3.0.tar.xz.sig `
  C:/tmp/octave-11.3.0-source-task51/octave-11.3.0.tar.xz
```

The replay downloads the official keyring only after the absence precheck,
uses `gpgv` with that exact keyring (and therefore never the default GnuPG
home), and in `finally` removes only the canonical, strict-descendant
verification root and verifies its absence.  If `gpg` is substituted for
`gpgv`, it must use `--homedir` pointing at a separately prechecked disposable
directory plus `--no-options`; it must never use `%APPDATA%\gnupg`.

It exited zero and emitted:

```text
GOODSIG B05F05B75D36644B John W. Eaton <jwe@gnu.org>
VALIDSIG DBD9C84E39FE1AAE99F04446B05F05B75D36644B 2026-06-02 ...
```

The `VALIDSIG` primary fingerprint exactly matches the already trusted
fingerprint `DBD9C84E39FE1AAE99F04446B05F05B75D36644B`.

## Official Windows package and build provenance

The tested installed tree is `C:\Tools\GNU Octave\11.3.0`.  Its
`README.html` identifies Octave 11.3.0, its packaging-tree `HG-ID` is
`8837c9048e1a`, and `etc\os-release` identifies the distribution environment
as MSYS2.  `pure-octave.fingerprint` records the official signing fingerprint
`DBD9C84E39FE1AAE99F04446B05F05B75D36644B` and package hash
`959C23237F0852C29E131C5034B378FF4168B84325EFE1C92A50070A8BB89607`.
The extracted, signature-verified Octave source has `HG-ID 4e62258d6e20`.

The installed interpreter's `__octave_config_info__()` reports:

```text
version=11.3.0
release_date=2026-06-01
hg_id=4e62258d6e20
canonical_host_type=x86_64-w64-mingw32
windows=1
CC=x86_64-w64-mingw32-gcc
CXX=x86_64-w64-mingw32-g++
GCC_VERSION=15.2.0
GXX_VERSION=15.2.0
CFLAGS=-g -O2
CXXFLAGS=-g -O2
DEFS=-DHAVE_CONFIG_H
```

The configured options include the exact target/build pair
`--host=x86_64-w64-mingw32 --build=x86_64-pc-linux-gnu`, the MXE prefix
`/scratch/build/mxe-octave-w64/usr/x86_64-w64-mingw32`,
`--enable-relocate-all`, `--with-blas=-lblas -lxerbla`, `--enable-64`,
`--with-x=no`, and `--enable-cross-tools`.  The installed runtime includes
`libstdc++-6.dll`, `libgcc_s_seh-1.dll`, and `liboctave-13.dll`; this is the
MinGW GCC/libstdc++ Octave runtime.

The source file `oct-conf-post-private.in.h` contains:

```c
#if defined (__WIN32__) && ! defined (__CYGWIN__)
#  define OCTAVE_USE_WINDOWS_API 1
#endif
```

Thus this native MinGW target selects the Windows implementation discussed
below.  MSVC is used only to build the small standalone Win32 probe with
strict warnings; it is not the compiler or C++ runtime provenance of the
tested Octave package.

## Exact Octave branch

`oct-conf-post-private.in.h` defines `OCTAVE_USE_WINDOWS_API` for
`__WIN32__ && ! __CYGWIN__`.  In `liboctave/system/file-ops.cc`,
`octave::sys::canonicalize_file_name` then takes the Windows branch:

1. Convert the UTF-8 input to UTF-16.
2. Open it with `CreateFileW`, `GENERIC_READ`, `FILE_SHARE_READ`,
   `OPEN_EXISTING`, and `FILE_FLAG_BACKUP_SEMANTICS`.
3. Call `GetFinalPathNameByHandleW(..., FILE_NAME_NORMALIZED)`.
4. Reject only `len >= 32767`.
5. Construct the result from the buffer and returned length.

The non-Windows branch calls
`octave_canonicalize_file_name_wrapper`, which delegates to gnulib
`canonicalize_file_name`; it is not the implementation used by the native
Windows build.  The wrapper and Windows source are listed respectively in
`liboctave/wrappers/module.mk` and `liboctave/system/module.mk`.

The bug is the omitted `len == 0` branch.  On the packaged failure, Octave
constructs an empty string from a zero-length buffer while leaving `msg`
empty.  The interpreter wrapper consequently reports an empty result with
status zero and no message.

## Reproducer

Build from an x64 Visual Studio Developer Command Prompt:

```text
cl /nologo /W4 /WX /TC /Fo:<temp>\probe.obj /Fe:<temp>\probe.exe ^
  pure-octave\probes\windows_canonicalize_appcontainer.c ^
  /link userenv.lib advapi32.lib
```

The source header and its usage output document both modes:

```text
probe.exe --probe TARGET OUTPUT
probe.exe --appcontainer UNIQUE_PROFILE STAGE WORK PROBE TARGET
```

The committed reproducible harness is:

```powershell
pwsh -NoProfile -File `
  pure-octave/probes/run_windows_canonicalize_appcontainer.ps1 `
  -ScratchRoot C:\pure-lang
```

It canonicalizes source, fixture, scratch, stage, work, probe, and target;
requires every generated path to be a strict descendant of the disposable
stage as appropriate; and rejects reparse points in all path components and
the complete staged tree.  It snapshots the scratch-root ACL before the run
and proves that the launcher changes ACLs only inside the disposable stage.

The harness copies the executable and the existing nonempty
`pure-octave/probes/embed_probe.cc` fixture into one disposable stage.  It ran
`--probe` ordinarily, then launched `--probe` in a zero-capability
AppContainer against that exact same staged target.  The launcher grants the
temporary package SID read/execute on the stage and modify on its work
subdirectory.  It creates the child suspended, opens the child token, proves
`TokenIsAppContainer == 1`, requires the exact expected package SID and zero
capabilities, and only then resumes it.  It distinguishes timeout, failed,
and unexpected waits; every failure path requires `TerminateProcess` to
succeed and a second bounded wait to return `WAIT_OBJECT_0`.

PowerShell `finally` independently attempts profile and stage cleanup, so a
profile cleanup failure cannot skip stage removal.  It removes only the
canonical, strict-descendant `C:\pure-lang\.task1-harness-*` root and verifies
absence.  The harness makes ordinary/AppContainer exit codes and all output
claims below executable assertions, including a successful, nonzero,
in-bounds `FileNameInfo` result.

## Exact RED evidence

MSVC compiled the probe with `/W4 /WX`; exit code was zero.

Ordinary process, exit `0`:

```text
CREATEFILE_HANDLE=1 ERROR=0
GETFINAL_NORMALIZED_LENGTH=87 ERROR=0 NONEMPTY=1
GETFINAL_NORMALIZED_PATH=\\?\C:\pure-lang\.task1-harness-<unique-id>\fixture\embed_probe.cc
GETFINAL_OPENED_LENGTH=87 ERROR=0 NONEMPTY=1
GETFINAL_OPENED_PATH=\\?\C:\pure-lang\.task1-harness-<unique-id>\fixture\embed_probe.cc
FILE_NAME_INFO_OK=1 LENGTH=81 ERROR=0 NONEMPTY=1
FILE_NAME_INFO_PATH=\pure-lang\.task1-harness-<unique-id>\fixture\embed_probe.cc
READFILE=1 ERROR=0 BYTES=1 BYTE=35
ENUMERATION=1 ERROR=0
```

Zero-capability AppContainer process, expected RED exit `10`:

```text
TOKEN_IS_APPCONTAINER=1 TOKEN_SID_MATCH=1 TOKEN_CAPABILITIES=0
CREATEFILE_HANDLE=1 ERROR=0
GETFINAL_NORMALIZED_LENGTH=0 ERROR=5 NONEMPTY=0
GETFINAL_NORMALIZED_PATH=
GETFINAL_OPENED_LENGTH=0 ERROR=5 NONEMPTY=0
GETFINAL_OPENED_PATH=
FILE_NAME_INFO_OK=1 LENGTH=81 ERROR=0 NONEMPTY=1
FILE_NAME_INFO_PATH=\pure-lang\.task1-harness-<unique-id>\fixture\embed_probe.cc
READFILE=1 ERROR=0 BYTES=1 BYTE=35
ENUMERATION=1 ERROR=0
```

Thus the failing operation is specifically
`GetFinalPathNameByHandleW`; error 5 is `ERROR_ACCESS_DENIED`.  Both
`FILE_NAME_NORMALIZED` and `FILE_NAME_OPENED` fail.  The successful open,
one-byte read, enumeration, and `FileNameInfo` query rule out missing file
access or a bad input path.

Cleanup output:

```text
PROFILE_DELETE_HRESULT=0x00000000
PROFILE_CLEANUP_HRESULT=0x00000000
STAGE_EXISTS_AFTER_CLEANUP=False
```

No installed Octave or production Pure file was modified.

## Candidate upstream fix semantics

The mandatory correctness fix is small and independent of any fallback:

1. Capture `GetLastError()` immediately when
   `GetFinalPathNameByHandleW` returns zero.
2. Set `msg` using the existing `file-ops.cc` pattern,
   `std::system_category().default_error_condition(error).message()`.
3. Return the empty result.  Continue to treat `len >= buf_size` as the
   existing buffer error.

That change prevents a false success, but by itself does not make
canonicalization AppContainer-compatible.

For the isolated local stage, the narrow fallback candidate is:

1. Attempt the existing normalized call first.
2. Only for its `ERROR_ACCESS_DENIED`, query the already open handle with
   `GetFileInformationByHandleEx(FileNameInfo)`.
3. Require a nonempty volume-relative result.
4. Obtain the input volume root with `GetVolumePathNameW`, open that root, and
   verify its volume serial equals the target handle's volume serial before
   combining the root with `FileNameInfo`.
5. Fail closed with the original normalized-call error for UNC, mapped-drive,
   cross-volume, buffer, or identity cases that cannot be proven equivalent.

`FileNameInfo` is preferable to a bare `GetFullPathNameW` fallback because it
queries the opened object rather than merely normalizing input text.  It still
needs a reparse semantic guard: the strict Task-1/Task-51 stage audit must
reject reparse points in every staged path component before relying on
volume-root reconstruction.  An upstream patch must retain that guard or add
equivalent symlink/reparse tests; otherwise it could silently weaken
`canonicalize_file_name` semantics.  A retry with `FILE_NAME_OPENED` alone is
not a candidate because this reproducer proves it fails with the same error.

No candidate patch was applied to the installed runtime in Task 1.
