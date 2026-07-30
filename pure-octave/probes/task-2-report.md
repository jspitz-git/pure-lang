# TODO-51 Task 2 Report: System-volume AppContainer fallback

Date: 2026-07-30

## Corrected outcome

This report supersedes the first Task 2 implementation. Reviewer findings
showed that its generic `FileNameInfo` plus reopen/identity construction was
not proven safe. That implementation, its manual identity code, and its
self-fulfilling volume/reparse mutations have been removed.

The accepted fallback is deliberately narrower. Octave still calls
`GetFinalPathNameByHandleW(FILE_NAME_NORMALIZED)` first and enters the helper
only when that call returns zero with `ERROR_ACCESS_DENIED`. The helper accepts
only an absolute path whose drive:

- is the exact root returned by `GetVolumePathNameW`;
- is `DRIVE_FIXED`;
- equals the drive returned by `GetSystemWindowsDirectoryW`.

It then queries `GetFileInformationByHandleEx(FileNormalizedNameInfo)` on the
already-open handle, validates a bounded absolute volume-relative name, and
returns `\\?\<system-drive><normalized-relative>`. It does not support other
local volumes, mapped drives, UNC paths, SUBST aliases, or mounted-folder
offsets. Failure of any check returns no candidate and preserves the original
`ERROR_ACCESS_DENIED` report at the Octave call site.

This result is a snapshot of the kernel-normalized name at query time. Windows
namespace entries can change after any canonicalization call; the helper does
not claim that the returned path will remain bound to the same object in the
future. Removing the old reopen step avoids pretending that a later namespace
observation can make that general race disappear.

## Root-cause diagnostics

The exact MinGW headers expose `FileNormalizedNameInfo` only under
`NTDDI_VERSION >= 0x0A000007`. Its `FILE_INFO_BY_HANDLE_CLASS` ABI value is 24,
not the value 48 used by the different `FILE_INFORMATION_CLASS` enum. A
high-target typedef assertion verifies the symbolic value; the lower-target
numeric alias exists only in the opposite version guard.

On the same ordinary and zero-capability AppContainer handle,
`FileNormalizedNameInfo` returned the same exact normalized volume-relative
path with error zero. In the AppContainer, both normalized/opened
`GetFinalPathNameByHandleW` calls still returned zero and error 5.

Other mapping APIs were characterized rather than assumed:

- ordinary `GetVolumeNameForVolumeMountPointW` returned the volume GUID;
- the zero-capability AppContainer returned error 5 for that API;
- `GetSystemWindowsDirectoryW` returned exact `C:\WINDOWS`, error zero, in
  both ordinary and AppContainer processes.

## Single-source equivalence

The standalone probe includes
`windows_system_volume_canonicalization.h` directly. The upstream patch adds
the same bytes as
`liboctave/system/windows-system-volume-canonicalization.h`; `file-ops.cc`
contains only the normal-first branch, error propagation, and helper call.

After applying the patch to a disposable official tree, both helper files had
this SHA-256:

```text
7C7A46B7202F9A7E6F89CD7D53C28F0F48AFFB495E18FCE34E525AC5DA0D0D44
```

The comparison reported `SHARED_HELPER_BYTE_IDENTICAL=True`.

## Behavior matrix

The bounded harness builds the same probe source with either MSVC or the exact
Octave MinGW G++ compiler. Both variants execute the shared helper itself.

- ordinary file: normal-first result, exact `\\?\C:\...` path;
- zero-capability AppContainer: raw normalized call error 5, helper exact path;
- real same-volume junction: helper returns the exact underlying normalized
  path;
- junction plus a real hardlink: helper returns the exact underlying hardlink
  path reported by `FileNormalizedNameInfo`;
- real SUBST alias, when available: rejected because its input drive differs
  from the system drive;
- malformed relative-path forms are rejected by the shared validator;
- the bounded name query saturates at the exact maximum allocation and fails
  closed on API errors.

Every run removes the AppContainer profile, SUBST mapping, and disposable
stage. No installed Octave or production Pure file is modified.

## Upstream and build evidence

The official Octave 11.3 archive provenance remains:

```text
SHA-256: 2B80F3149B2DE6D1F4F2FCB4FE6515A17EB363B52111BF57B90F37BF6F5E12E1
VALIDSIG: DBD9C84E39FE1AAE99F04446B05F05B75D36644B
```

The regenerated patch is whitespace-clean and applies to that source:

```text
Checking patch liboctave/system/file-ops.cc...
Checking patch liboctave/system/windows-system-volume-canonicalization.h...
```

The exact `x86_64-w64-mingw32-g++.exe (GCC) 15.2.0` accepted the patched
`file-ops.cc` under `-std=gnu++17 -Wall -Wextra -Werror`, high-NTDDI symbolic
enum checks, and the Octave Windows build macros:

```text
PATCHED_FILE_OPS_HIGH_NTDDI_COMPILE_EXIT=0
PATCHED_FILE_OPS_OBJECT_BYTES=406193
```

The same compiler also built the focused probe as C++ with `-municode` and
ran the complete ordinary, zero-capability AppContainer, SUBST, junction, and
hardlink matrix. This is behavioral execution of the exact upstream helper,
not merely a compile-only approximation.

Full `liboctave` rebuild and installed-runtime integration remain Task 3 work
in the official MXE environment. Task 2 does not modify the installed runtime.
