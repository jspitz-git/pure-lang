# TODO-51 Task 2 Report: AppContainer Canonicalization Fallback

Date: 2026-07-30

## Outcome

The standalone Windows probe now implements and verifies a narrowly scoped
fallback for the Octave 11.3 Windows canonicalization failure.  The existing
`GetFinalPathNameByHandleW(FILE_NAME_NORMALIZED)` call remains the first
choice.  Only `ERROR_ACCESS_DENIED` enters the fallback.  A normal process
returns the unchanged normalized result; a zero-capability AppContainer
returns the same exact `\\?\C:\...` target through the fallback.

The fallback fails closed unless all of these conditions hold:

- the input is an absolute local drive path, not UNC or a remote/mapped drive;
- `GetVolumePathNameW` identifies that same drive root without a
  mounted-folder offset;
- `FileNameInfo` from the already opened handle is nonempty, structurally
  valid, and exactly equals the input path after its drive prefix;
- a reconstructed extended DOS path can be opened without following its final
  component as a reparse point;
- the reconstructed handle has the same volume serial and file identity as the
  original handle.

Exact kernel-name comparison rejects path-changing reparse components, SUBST
offsets, mounted-folder offsets, UNC, and mapped-drive ambiguity.  Re-opening
and comparing identity makes namespace changes fail closed.  The committed
harness also creates a real directory junction and proves that its target is
rejected, rather than relying only on a synthetic reparse mutation.

## TDD evidence

The candidate expectation was committed to the harness before implementation.
The fresh RED retained a successful `/W4 /WX` build and ordinary controls,
then failed exactly with:

```text
AppContainer probe exit code 10; expected 0
```

The expanded RED then failed because the ordinary output had no
`CANDIDATE_SOURCE=NORMALIZED` record.  No fallback implementation existed at
either point.

The final fresh harness command was:

```powershell
pwsh -NoProfile -File \
  pure-octave/probes/run_windows_canonicalize_appcontainer.ps1 \
  -ScratchRoot C:\pure-lang
```

It exited zero and asserted:

- MSVC `/W4 /WX` build: exit 0;
- ordinary normalized and candidate paths: exact and unchanged;
- forced safe fallback: exit 0 and exact target;
- volume-identity mutation: exit 25, original error 5, empty result;
- reparse-status mutation: exit 25, original error 5, empty result;
- malformed handle-path mutation: exit 25, original error 5, empty result;
- real junction path: exit 25, original error 5, empty result;
- exact maximum `FileNameInfo` allocation: seven attempts, final capacity
  65,538 bytes, then `ERROR_BUFFER_OVERFLOW` (111);
- zero-capability AppContainer token: exact package SID, zero capabilities;
- AppContainer raw normalized API: `0 / ERROR_ACCESS_DENIED`;
- AppContainer candidate: `FALLBACK / error 0`, exact canonical target;
- profile cleanup: HRESULT zero;
- disposable stage after cleanup: absent.

The probe investigation also established why two superficially attractive
guards are not usable in the package:

- `QueryDosDeviceW` is denied after the local root and drive-type checks;
- opening or querying attributes for ancestors above the explicitly granted
  stage is denied.

Neither guard is required for safety because the accepted kernel-name and
reopened-identity checks cover their ambiguity cases without depending on
ancestor ACLs.

## Task 1 Minor closures

`query_file_name_info` now saturates its growth at the exact maximum instead
of stopping below it.  A deterministic API-injection mode proves that exact
maximum is attempted once before returning overflow.

The signature replay in `task-1-report.md` now creates its root with a real
`[guid]::NewGuid().ToString("N")` value.  Its first state-changing
`New-Item` is inside `try`, so the snippet is literally copy-paste safe and
its existing `finally` owns cleanup.

## Upstream patch

`patches/octave-11.3.0-appcontainer-canonicalization.patch` changes only
`liboctave/system/file-ops.cc`.  It also closes the independent false-success
bug: a zero result now captures `GetLastError()`, returns an empty result,
and reports the matching `std::system_category` message when the safe
fallback is unavailable.

Fresh provenance and applicability evidence:

```text
archive SHA-256:
2B80F3149B2DE6D1F4F2FCB4FE6515A17EB363B52111BF57B90F37BF6F5E12E1

trusted VALIDSIG fingerprint:
DBD9C84E39FE1AAE99F04446B05F05B75D36644B

git apply --check --verbose:
Checking patch liboctave/system/file-ops.cc...

disposable apply:
Applied patch liboctave/system/file-ops.cc cleanly.
```

The upstream code uses `BY_HANDLE_FILE_INFORMATION`, not
`FILE_ID_INFO`.  The latter is not exposed by the exact Octave MinGW target
headers at their configured Windows API level.  The accepted structure
provides a volume serial plus a 64-bit file index and therefore retains the
required cross-volume and same-object gates without raising the supported
Windows API baseline.

## Actual MinGW build feasibility

The exact official compiler was used:

```text
x86_64-w64-mingw32-g++.exe (GCC) 15.2.0
```

A disposable copy of the verified source was patched, and the actual patched
`liboctave/system/file-ops.cc` was compiled with the installed Octave public
headers, the verified source private wrapper headers, the Windows filesystem
macros, and the `OCTAVE_DLL` build export macro:

```text
PATCHED_FILE_OPS_COMPILE_EXIT=0
PATCHED_FILE_OPS_OBJECT_BYTES=469285
```

The compile used `-std=gnu++17 -Wall -Wextra -Werror`; it therefore proves
that the patched component is accepted by the exact MinGW C++ ABI and header
set.

An out-of-tree full configure probe was also attempted.  It recognized the
exact pair `--host=x86_64-w64-mingw32 --build=x86_64-pc-linux-gnu`, compiled
C and C++ conftests with GCC/G++ 15.2.0, and found the official package's GNU
Make 4.4.1.  The first run exposed libtool splitting the installed linker path
at the space in `C:\Tools\GNU Octave`; a disposable no-space toolchain
junction plus `COMPILER_PATH` removed that failure.  A later configure run
did not reach `config.status` in this Git-for-Windows host and ended while
running a later OpenMP conftest, so this task does not claim a complete local
Octave build.

The practical build recommendation is to apply the patch in the official MXE
Octave Windows build environment, where the package's configured dependency
graph and no-space build prefix already exist.  The successful strict object
compile is the narrow local acceptance gate; a full rebuilt `liboctave` and
AppContainer integration belong to Task 3.

## Containment

No installed Octave or production Pure file was modified.  All patch,
configure, and object artifacts were placed under
`C:\tmp\octave-task51-task2-build`.  The AppContainer profile and harness
stage were removed and verified absent after every run.  The disposable build
root is removed after the final evidence is recorded.
