# Task 7 report — complete verified source distribution

Date: 2026-09-09. Workspace: `C:/pure-lang/.worktrees/todo33-audit`.
Branch: `codex/todo33-audit`. Base: `547f47be9429c2c06df80698df18be6a25819949`.
Status: both Important review findings fixed with actual RED/GREEN evidence;
fresh full verification and self-review complete; independent re-review pending.
No merge/push or TODO closure is part of this task.

Current result: **92 regular source files / 92 SHA values / 238,112 bytes**,
archive SHA256 `ead0d8c9eebd18c2b3916d752bdc96df0ed8165c0011f615bf72d562d5151d42`.
Task7: **34 rejected/neutralized scenarios, 1 pristine archive, 7 controls**.
Fresh public distcheck **1/1 PASS, 1420.30 s**; pristine extracted mandatory
suite **10/10 PASS, 1162.55 s**. Four-worker build/PE, both installs, public
Task4 token and initial/final full source-tree scans passed.

Initial implementation checkpoint `fddb0c2b35b55cef7b2c36ee7b540813bb016fd7`
(superseded by the fix-round evidence below): **92 regular source files / 92 SHA values**, archive **234,815
bytes**, SHA256 `c3171dd88a4bc0aab3c4e995ad9226d6ca63cece3769bbdd1ff2d1cab930bf92`.
Task7: **30 rejected/neutralized mutations, 1 pristine archive, 6 controls**.
Fresh public distcheck **1/1 PASS, 1256.87 s**; extracted mandatory suite
**10/10 PASS, 1161.94 s**; both installs, public Task4-token/PE verification and
then-implemented leak scans PASS. Review correctly found that the source tree
was scanned only before configure, not again after all release phases. This is
a nested 1/1 + 10/10 result, not a claim
that one outer CTest invocation ran 11/11 tests.

## Review fix round 1 — hardlinks and final source-tree scan

The parent approved normalization with GNU tar's advertised
`--hard-dereference` capability, rather than a fixed version pin. The producer
now verifies GNU version identity and the exact help-option boundary before
reserving temporary outputs, then uses this option for both create and append.
This follows hardlinks only, not symlinks; all existing reparse checks remain.

The actual public `make dist` hardlink RED used two declared names, README and
WINDOWS.md, with equal bytes in an independently copied source control. Native
GetFileInformationByHandle proved the mutation had the same volume/file index
and exactly two links. The ordinary-file control was accepted; the hardlinked
archive failed the independent verifier with `Archive contains nonregular
entry`. All 92 source SHA values remained unchanged. Control archive SHA256:
`74fc95146da50294d057232abbe3b863eaef17a0d4da57d61ada9b0aac767f17`;
hardlinked archive SHA256:
`5b6be74356e7e99cb18eaa9203dd4219e889039a4bb6381ea16fa7fc9f958faf`.
Evidence under `C:/pure-lang/task7-final-4/pure-audio-contract-root/`:
`run-6e1bd65d1f9ba97c52f3a59cf35e8f06`.

A separate tool-boundary double advertised GNU tar 1.35 but omitted the required
option from help. Before the fix it reached archive creation and wrote its
unexpected-invocation marker; the capability regression failed specifically
because preflight had not rejected it. Evidence: `run-de0a76afccfdc7e979ac94bd91608d1b`.
The double is not used to produce or certify archive payloads. Focused GREEN
`run-ff3baa4a536fc52b041d65d6e30bc70c` proved capability rejection before writes,
both topology archives accepted as 92 regular members/92 exact SHA values,
identical archive SHA, all 92 source bytes unchanged and native link identity
retained. This checkpoint had 32 negatives and 8 valid checks.

The final-scan RED creates a new file or junction during real CMake configure,
after the initial scan. The binary fixture has a mixed-case/backslash checkout
path at offset 10,485,750 (ten bytes before the 10 MiB/chunk boundary), beyond
9 MiB and preceded by NUL bytes. The second fixture is a verified real junction
to an owned outside sentinel. Test-only extracted-driver copies select four
actual core CTests, but retain real configure, four-worker build and PE target,
both component installs and public installed verifier/token execution. This
approved optimization has no production switch or bypass; pristine still runs
all ten mandatory tests.

Both RED integrations completed all seven real phases and 4/4 core tests,
then incorrectly wrote EXTRACTED_SOURCE_OK. The contract failed with
`Final extracted-source gate accepted post-configure mutations: leak;junction`.
Evidence: `run-ea323821f39444d83b45c88a298e9102/postflight-leak` and
`postflight-junction`. Step seconds were respectively 7/4/4/10/11/9/22 and
7/3/3/11/10/10/23. Both source-root locks released, the junction was unlinked
non-recursively, and outside sentinel bytes stayed unchanged. The production
driver now re-enumerates and scans the entire source tree immediately after the
public installed verifier, before final build/stage scans and success output.
Focused GREEN completed with rc=0 in
`run-d94c6f01203f4d6d07e642f49df69c46`, reporting
`SOURCE_DIST_POSTFLIGHT_OK negatives=2 real_core_tests=4 real_phases=7 late_binary=1 junction=1 released_roots=2`.
The intended final failures were respectively `Checkout leak detected` and
`Leak scan refuses reparse entry`, both at the new source scan after the
installed-verifier phase. Neither case wrote a success artifact. All prior
archive/mutation controls also passed: **34 negative scenarios / 8 valid
checks**, archive SHA256
`ead0d8c9eebd18c2b3916d752bdc96df0ed8165c0011f615bf72d562d5151d42`.
Fresh strict parent `C:/pure-lang/task7-fix1-final` configured successfully
(tool wall 6.72 s, CMake configure 6.2 s), then all 23 four-worker build steps
passed in 3.90 s. Completed fresh full public distcheck results follow.

Its retained archive evidence root is
`C:/pure-lang/task7-fix1-final/pure-audio-contract-root/run-64455f9ebb87bc9beccaa4f7b3914c6f`.
Pristine/repeat/poisoned archives are each 238,112 bytes with the focused SHA256
above. The distinct topology fixture intentionally makes WINDOWS.md equal to
README; its ordinary-file and hardlinked archives are both 237,345 bytes,
SHA256 `9655f4c95382a28ceb7afea9a3955bd3f9d9d1068d0292a93a5580fee2c4f1fa`.
Those fixture bytes are not represented as the pristine release payload.

Fresh full public `make distcheck` then passed **1/1 in 1420.30 s** (CTest wall
1420.31 s, measured public-command wall 1420.5254267 s). It independently
repeated all **34 negatives / 8 valid checks**, including both real postflight
pipelines, before running the untouched pristine ten-test gate. The pristine
extracted build is `C:/pure-lang/task7-fix1-final/d-2CKv0BG6Dm9koxaGiL9joA`.
Its **10/10** mandatory tests passed in **1162.55 s**: install 801.22 s, guard
342.01 s, configure contract 96.30 s and runtime verifier 113.64 s. Step seconds
were configure 7 / four-worker build 4 / four-worker PE 4 / tests 1162 /
runtime install 11 / documentation install 9 / public verifier 23. Both native
builds completed all 23 steps; a separate final outer four-worker PE target
also passed (29 PEs, tool wall 4.29 s).

Public verification proved `PURE_AUDIO_DONE_5a6609c408b1d91b7461c7ac2a8e21e4`
and **61 artifacts = 22 runtime + 39 documentation**, delta 61, PE29,
27 full license payloads, 22 third-party DLLs and 7 project-owned PEs. Stage
101 files and inventory74 records preserve the same baseline-owned boundary;
the inherited install controls still prove deltas61/60/0. System DLLs are
loader-resolved, not staged files. Inherited contracts freshly confirmed
393 negatives / 72 controls / 6 pristine, with two explicit unavailable actual
file-symlink skips excluded. Native harness2391 checks (quarantine allocation
delta3), public Pure bounds24 checks, guard3 concurrent installers,
zero outside writes and12 precommit rollback/retry cases all passed.

The pristine driver output now proves **two complete 92-file source scans**,
before configure and after the installed verifier, followed by all73 generated
build/cache files and101 stage files. The isolator scans all17 final raw
log/preset files, proves184 held handles over2 roots with denied-read probes,
then reports successful release. All8 stderr captures are byte-empty. After
release, all92 original source hashes were independently rechecked against the
archive snapshot, and the final working-tree diff check passed. Current tool
versions were queried again and match those listed below. Only the scoped
report was edited during the full run; no archived source bytes changed.
Post-run checks also confirmed exact tracked/snapshot membership92, both
PowerShell helpers' full-file parser success, three unchanged identical
pristine/repeat/poisoned archives and two unchanged identical topology archives.

## Approved scope and rulings

- Standalone unbuilt `make dist` must remain available; no built Task 4 runner
  prerequisite. The parent rejected that initial proposal. The archive producer
  instead uses exact literal relative inputs, existing GNU tar/gzip, a unique
  temporary archive, deterministic metadata/root and no-overwrite publication,
  without a recursive staging tree. The contract uses Task 4 owned leaves.
- Alternate `distcheck`, `diffs` and `deb` package entry points must also lose
  unsafe separate extraction/deletion. Preserve practical non-Windows workflows;
  missing legacy inputs must cause explicit actionable failure.
- Actual file symlink creation is unavailable on this host: correctly marshaled
  CreateSymbolicLink returns FALSE with Win32 1314. Do not enable Developer Mode
  or elevate the OS. Use verified real junction endpoints/ancestors and a
  non-production attribute-injection seam; never count failed setup as coverage.
- The parent authorized correcting the two existing Task 5 CreateSymbolicLink
  declarations and explicit skip accounting. All other Tasks 1–6 interfaces are
  consumed, not duplicated. No Task 8/9 work, subagents, merge or push.
- The parent approved two narrow POSIX compatibility corrections: preserve
  DEBUILD_FLAGS with its quoted arguments and compare canonical owned-leaf
  parents literally, not using an interpolated regular expression. Available
  Make/CMake behavioral checks are required; native POSIX execution remains
  explicitly unverified on this Windows host.
- Self-review found inherited GNU archive options unsafe. The parent approved
  clearing TAR_OPTIONS and GZIP explicitly for each producer tar/gzip process,
  a real public Make poison test checking all source SHA values and exact archive
  SHA, then focused verification and a new fresh final-4 after final-3 finishes.

## RED evidence collected before implementation

The actual legacy `make dist` ran in a disposable native-owned source clone.
Its extracted archive contained **33 files vs 86 independently declared inputs**,
missing **53** CMake, test, guide, inventory and license inputs. Initial quick
chat tallies of 34/87 were corrected from the retained snapshot, not reused.
Evidence: `C:/pure-lang/task6-fix3-final/pure-audio-contract-root/run-ae58dc9aec03d0fdb121bd837292704a`.

The first symlink fixture attempt was invalid: the old Task 5 P/Invoke declared
a four-byte BOOL for the one-byte BOOLEAN return and falsely signaled success.
Those two setup attempts are excluded from RED/GREEN counts. A correctly
marshaled native probe proved Win32 1314 and absence of the supposed link.

The corrected mutation matrix verified every actual junction's reparse
attribute before calling the old Makefile. All **7** cases were accepted:
source endpoint junction, source ancestor junction, checkout root junction,
archive endpoint junction, existing archive, output ancestor junction and
caller-controlled dist path. Existing archive bytes were overwritten and the
caller-dist case removed only its deliberately created sentinel inside the
owned test leaf, never workspace/user data. Evidence:
`C:/pure-lang/task6-fix3-final/pure-audio-contract-root/run-a30ee38fdc6b7a7f395292ce43cead73`.
The new producer rejected all seven with all seven outside sentinels unchanged:
`C:/pure-lang/task6-fix3-final/pure-audio-contract-root/run-75830dd1aae14ab2c534fefd2053030e`.

An independent source inventory audit found `licenses/.gitattributes` omitted
from the first new archive. The actual archive contract failed specifically
for that missing file before the producer list was corrected:
`C:/pure-lang/task6-fix3-final/pure-audio-contract-root/run-a45867ea6d8d826db65a61343c2847f4`.

The dedicated test-only attribute seam loads only actual validation function
ASTs, without adding a production helpers-only/override switch. Its injected
regular-file reparse attribute first failed to reach the real validation and
then passed after the attribute-read boundary was connected. Current focused
marker: `SOURCE_DIST_ATTRIBUTE_OK negatives=1 controls=1 injected_file_reparse=1`.
This is explicitly injected attribute coverage, not a claim of a real symlink.

## Authorized Task 5 correction

Both declarations now use `[return: MarshalAs(UnmanagedType.I1)]`, require an
actual existing ReparsePoint after successful creation, and explicitly skip
only Win32 1314. Other creation failures remain fatal. Focused CTest rerun:
**2/2 PASS in 107.85 s** (configure 89.46 s, runtime verifier 107.85 s).
Exact markers: **configure negative=119 positive=4 skipped_symlink=1**;
**runtime verifier negative=41 positive=3 pe_count=29 skipped_symlink=1**.
Earlier 120/42 negative totals included those unavailable cases and must not be
represented as demonstrated real symlink coverage. Production Task 5 behavior
was not changed by this correction.

## Archive implementation and additional regressions

The literal producer list and independent test list currently contain 92 files.
Archive names are rooted at `pure-audio-0.6/`, sorted (with the executable Debian
rules entry appended last), uid/gid 0, mtime epoch 0, regular mode 0644 except
`debian/rules` 0755. GNU gzip `-n -9` removes original name/time metadata.
Two uniquely CREATE_NEW-reserved files hold raw tar and compressed output;
only their exact filenames are removed. Same-directory no-overwrite rename
publishes the final archive. No staging-directory recursive deletion occurs.
The legacy README date/version token substitution is intentionally not applied:
all 92 archive payloads must retain their independently snapshotted source
bytes. The separate Task8 documentation rewrite is not implemented here.

Actual default `make dist` first failed to find gzip because the defined
default `DIST_TAR=tar` was incorrectly treated as a relative filename. The
producer now resolves a bare tool name before canonical validation. The next
actual archive metadata test then found `debian/rules` archived as 0644. It is
now deterministically appended as 0755; the resulting 90-file checkpoint was
GREEN at `run-46073bf0f395f418b1e517454be555a5` under the Task 6 fixture root.

Independent gzip/tar parsing checks headers, regular entry types, exact
membership, duplicates and every SHA before CMake extraction. Real extra,
omitted-harness and changed-C-source archives all fail for their respective
content defects. A repeated real public archive is byte-identical even with
undeclared extra source files present; they cannot enter the literal manifest.

The streaming checkout scanner uses 64KiB raw FileStream chunks and persistent
KMP state, with ASCII case/slash folding and both UTF-8 and UTF-16LE patterns.
It neither treats NUL as EOF nor has a read-size limit. Four independent binary
fixtures cover mixed case/backslashes, a chunk boundary, a reference beyond
10 MiB and UTF-16LE beyond 10 MiB, with one clean binary control. A mechanically
mutated scanner limited to 9 MiB was actually run and failed specifically with
`Scanner accepted late binary checkout leak`; the unlimited implementation
passes the same cases. Evidence script: `C:/pure-lang/task7-scanner-mutation.ps1`;
fixture root `C:/pure-lang/task7-final-1/pure-audio-contract-root/run-f63dbfe2ebec8d368f822e4fb8088cab`.

Public `make distcheck` uncovered an additional integration RED: inherited
GNU Make command-variable MAKEFLAGS supplied a valid audit-build directory to
the intentionally invalid nested distcheck fixture, recursively launching it.
The exact test process ancestry was inspected, its one process tree stopped,
and test-side MAKEFLAGS/MFLAGS/MAKEOVERRIDES cleared; the invalid probe now also
explicitly passes an empty DIST_AUDIT_BUILD. No unrelated process was stopped.
This failed attempt is not counted as extracted-source GREEN.

Self-review then tested ambient `TAR_OPTIONS=--remove-files` using the actual
public Make target in a newly Task4-owned disposable clone. The legacy-to-this-
fix producer removed **92/92** copied source inputs, then failed rc=2 because
its publication helper had also been removed. No original/extracted source,
user file or unrelated process was affected. This is genuine RED evidence,
not merely a source-text inference: `C:/pure-lang/task7-tar-options-red.cmake`,
`C:/pure-lang/task7-final-3/pure-audio-contract-root/run-6140a92bb6e41051acfb8c5677972973/tar-options.log`.
After final-3 released its handles, the new checked-in public-target test first
failed with `Ambient archive options removed a declared source: CMakeLists.txt`
in owned leaf `run-0a7c7d1042db98d600c68298b1f23e08` under the final-3 fixture root.
The test's SOURCE_DIR was itself an explicitly disposable owned copy; an
earlier command using the read-only worktree SOURCE_DIR was blocked by the
execution safety reviewer before execution, and was not counted as test evidence.

Every producer tool invocation (tar version/create/append and gzip) now uses
the declared CMake executable's `-E env --unset=TAR_OPTIONS --unset=GZIP`.
Focused GREEN in `run-3720d9232085119001a6fa154f892b70` reported
`SOURCE_DIST_ENVIRONMENT_OK negatives=1 source_hashes_unchanged=92 exact_archive_hash=1`.
Archive SHA256 was `c3171dd88a4bc0aab3c4e995ad9226d6ca63cece3769bbdd1ff2d1cab930bf92`.
The poison fixture sets both variables but counts as one hostile-environment
scenario. A separate GZIP-only characterization had no effect with this gzip
version, and is not counted as another demonstrated RED/GREEN mutation. Its
initial source-set probe mistakenly included the newly created archive; the
corrected source-only probe passed and that invalid diagnostic is excluded.

## Alternate package entry points and supported boundaries

Windows `make distcheck DIST_AUDIT_BUILD=<strict-built-directory>` invokes the
registered source-dist contract, not a second extraction/deletion recipe.
Standalone `make dist` requires no configured/built Pure helpers. Source-only
Make goals no longer include compiler/pkg-config discovery in Makefile.common.
Windows `diffs` and `deb` fail before writes with actionable POSIX toolchain
guidance. Missing strict audit build and caller-changed release basenames also
fail before writes. Six direct target cases retain outside/xxx/yyy sentinels.

The POSIX branch preserves `diffs` with pure-gen and required development headers,
`distcheck` via extracted make/build/install, and `deb` with debuild plus an
explicit authoritative original tarball. It never downloads that tarball.
These use a fixed `.pure-audio-source-workflows` root, atomic mktemp unique
leaves, exact nonce/path sentinels, complete non-symlink/regular preflight and
enumerated file deletion plus empty-directory rmdir. Successful Debian artifacts
remain in their explicitly reported unique owned leaf. No POSIX host is
available in this Windows audit, so those execution branches are not claimed
as native POSIX GREEN; their compatibility is subject to the upstream POSIX gate.

The existing regex parent check was actually evaluated against a valid owned
root named `literal[owner]+` and rejected its valid child (RED). The replacement
normalizes root/leaf and compares the parent with literal STREQUAL, then checks
only the fixed leaf-name grammar. The production helper passes that valid root
and rejects a foreign parent and invalid leaf name. A real public GNU Make
invocation transports `DEBUILD_FLAGS=-us -uc "--build-option=two words"` through
the exported environment into the actual production parser; its oracle requires
exactly three arguments with the last embedded space intact. Mutating the
production parser to return no flags failed specifically with
`DEBUILD_FLAGS were lost or split incorrectly`. These two negatives and two
controls do not invoke or certify native POSIX debuild. Evidence scripts:
`C:/pure-lang/task7-posix-red.cmake`, `C:/pure-lang/task7-flags-red.cmake`.
Focused GREEN evidence:
`C:/pure-lang/task7-final-2/pure-audio-contract-root/run-a05737e1c8b80ec9ca001e78010c48b0`;
92-file archive SHA256 `0c5f88ebdf9da70daed0809087c8b67631d53acbf5ecdb7c34b948872c5a8db5`.

As in the approved Task 6 boundary, these path checks and unique ownership do
not claim isolation from an actively malicious same-principal process capable
of replacing files between checks. Existing source/archive/output reparse
endpoints and ancestors are rejected; concurrent final archive publication
cannot overwrite an existing entry. Crash/power-loss may leave only the unique
temporary files/owned contract evidence, which are not broadly auto-deleted.

## Extracted-source verification

Fresh build: `C:/pure-lang/task7-final-1`; strict configure and 23 build steps
passed with `--parallel 4`. Public entrypoint:

```
C:/msys64/clang64/bin/mingw32-make.exe SHELL=C:/msys64/usr/bin/sh.exe DIST_CMAKE=C:/msys64/clang64/bin/cmake.exe DIST_AUDIT_BUILD=C:/pure-lang/task7-final-1 distcheck
```

The extracted source path and producer checkout both contain spaces. A
test-only process holds read-exclusive handles on every independently declared
input in the real checkout and producer clone, proves ERROR_SHARING_VIOLATION
on fresh read attempts, then keeps those handles for the entire extracted
driver. The child generates strict inputs solely from explicit external
CLANG64/Pure prefixes, compiles its own runner/guard from archived C sources,
and invokes exactly two explicit four-worker build commands. Inner CTest
excludes only the recursively self-referential source-dist contract; all ten
mandatory Task 1–6 tests remain enabled. Per-step stdout/stderr are captured as
raw files and scanned; generated build/cache and final stage are scanned too.
Handles are released in finally and subsequent checkout reads must succeed.

The first real isolated full run failed correctly after **9/10** mandatory
tests (867.61 s; install contract 822.33 s). The remaining guard fixture creates
an additional private `guard-build/install-audits/<64-hex>` under its native
leaf; its actual atomic temporary path was **292 characters**, causing Win32
error 3 before the observation gate. That run's archive/hash/mutation checks
passed, but its end-to-end outcome is RED, not a pristine release claim.
Evidence: `C:/pure-lang/task7-final-1/pure-audio-contract-root/run-517941531e3f9e71ff53c01dae4e482f`;
failed public distcheck time 910.75 s; archive SHA256
`3cebcf17f3f3361dbf0363e2ed1741df2fc55971fe9c97b751bcdccea6764032`.

The parent approved a Task7-only short sibling build layout. The archive/source
and evidence stay in the Task4 native-owned leaf. The extracted build is now
an atomically CreateDirectoryW-reserved `d-<22-char CSPRNG base64url>` leaf under
the strict MODULE_DIR, with a byte-exact owner sentinel and separate ticket.
All existing ancestors are canonical and non-reparse. A 202-character downstream
fixture budget is checked before any reservation. Too-long roots fail with
actionable shorter-build-directory guidance. Cleanup validates root, name,
ticket, sentinel and every entry before any delete, then removes only enumerated
files and empty directories; it never calls a recursive delete API. Three
negative cases (MAX_PATH budget, wrong sentinel, actual junction) plus one valid
cleanup control passed, including unchanged outside/owned payload bytes.
Successful release build/evidence leaves are deliberately retained for review.
The legacy 260-character limit (including NUL) and the separate long-path
application opt-in are documented by [Microsoft](https://learn.microsoft.com/en-us/windows/win32/fileio/maximum-file-path-limitation).
No Windows policy, registry setting, privilege or application manifest was
changed; the Task7 layout stays within the existing Task6 API boundary.

The final isolated driver also copies its complete raw outer stdout/stderr and
generated strict preset into the scanned log set after both stream copies have
finished. This complements scans after every configure/build/test/install step
and scans of all generated build/cache/stage files.

Local versions actually queried: Clang/LLVM 22.1.8, CMake 4.4.0, Ninja 1.13.2,
GNU Make 4.4.1, GNU tar 1.35, GNU gzip 1.14, pkgconf 3.0.4, Pure 0.68.
The deterministic-archive claim is for identical input bytes and these tools;
it does not claim that differently normalized source checkout bytes produce
the same archive across operating systems.

Focused MAX_PATH GREEN used the same previously extracted source with the
short reserved build `C:/pure-lang/task7-final-1/d-sSfcX0Ms6-UoA-1J0t36dg`:
strict configure, 23-step four-worker build, then
`ctest --test-dir <short-build> -R ^pure-audio-install-guard-contract$ --output-on-failure --parallel 4`.
The actual guard contract passed **1/1, 350.36 s** (wall 350.37 s), reporting
28 negatives, 20 controls and 2 pristine cases, including live counterfeit,
late collisions, reserved races, metadata rollback and both manifest hardlinks.
The fixture binaries have build-specific hashes; no byte-identical PE claim
is inferred from using identical source and toolchain.

The first complete GREEN strict parent was `C:/pure-lang/task7-final-2`.
Configure 6.6 s and all 23 four-worker build steps passed. Its focused Task7
run passed at `pure-audio-contract-root/run-c9fc70e63f755cebadc4aa0f7410f5d9`,
with archive SHA256 `46e6275f018ffa34722a29f61fe3530165119511d629b9e3c55738ce9803b115`.
The subsequent public distcheck passed **1/1 in 1253.46 s** (wall 1253.47 s),
with **10/10** mandatory extracted-source tests passing in **1162.07 s**.
Full evidence is retained under
`C:/pure-lang/task7-final-2/pure-audio-contract-root/run-21a8958aef85813cc682c7f9396d183e`
and extracted build `C:/pure-lang/task7-final-2/d-s8FPIZ57NJWHindnGGAPRw`.
This successful checkpoint predates the final narrow POSIX compatibility
corrections above; it is not substituted for the current fresh run.

The next strict parent `C:/pure-lang/task7-final-3` configured in 6.3 s and
completed all 23 four-worker build steps. Its public distcheck passed **1/1 in
1254.85 s** (CTest wall 1254.86 s), with **10/10** mandatory tests passing in
**1163.06 s** (install 801.13 s, guard 343.16 s). Both installs, public Task4-token
verification, PE29 and all final scanners passed. Evidence:
`C:/pure-lang/task7-final-3/pure-audio-contract-root/run-36fcd749c9954b26199f3254fccb464a`;
extracted build `C:/pure-lang/task7-final-3/d-cE3Hz726NIbyOIV74Cprew`.
This checkpoint predates the ambient archive-options fix and is not substituted
for the final current run.

Initial implementation strict parent `C:/pure-lang/task7-final-4` configured in 6.39 s.
The 23-step four-worker parent build passed. Its current archive/source evidence
is retained at
`C:/pure-lang/task7-final-4/pure-audio-contract-root/run-2ba66f5fd23bc35aa7d3f18b441e7ccb`,
with extracted build `C:/pure-lang/task7-final-4/d-CEARra8EsL1U8EZFdYfZdQ`.
The fresh public distcheck passed **1/1 in 1256.87 s** (CTest wall 1256.88 s,
measured public-command wall 1257.07 s). The exact same current source archive
passed **10/10** extracted mandatory tests in **1161.94 s**. Per-step driver
times were configure 6 s, four-worker build 3 s, four-worker PE target 4 s,
tests 1162 s, runtime install 10 s, documentation install 9 s and public verifier
23 s. Native build completed all 23 steps. A separate final outer PE target
with `--parallel 4` also passed (29 PEs).

The public verifier proved `PURE_AUDIO_DONE_730cd911d37c5a99f60c66a2cc93fced` and
`INSTALL_PACKAGE_OK artifacts=61 runtime=22 documentation=39 delta=61 pe=29 license_payloads=27 third_party_dlls=22 project_owned_pe=7`.
The resulting stage has **101 files = 40 baseline + 61 added artifacts**;
the sealed inventory has 74 records (61 owned + 13 baseline PE records).
System DLLs are resolved by the Windows loader, not counted as staged or
third-party package files. Task6's standard/identical-preseed/full-preseed
delta controls remained **61/60/0**; no Task6 inventory/interface was changed.

The native harness passed **2,391 checks** (expected quarantined allocation
delta 3) and public Pure bounds passed **24 checks**. Fresh inherited contract
markers: Task4 106 negatives/35 controls; configure 119/4 with one explicit
file-symlink skip; runtime verifier 41/3 with one explicit file-symlink skip;
install 99 negatives/10 controls/4 pristine; guard 28 negatives/20 controls/2
pristine. Thus inherited contracts contribute 393 negatives, 72 controls and
6 pristine cases, with two unavailable file-symlink cases excluded. Guard
reported three concurrent installers, zero outside writes, 12 precommit
rollback cases and 12 successful retries. Install and guard timings were
**801.62 s** and **340.85 s**, respectively; configure/verifier contracts were
96.50 s and 113.96 s.

Initial-checkpoint scans covered all 92 extracted source files before configure,
73 build/cache/generated
files, 101 stage files and the complete final set of 17 raw log/preset files.
There is no size limit or NUL truncation. Isolation reported 184 retained
read-exclusive handles over two checkout roots, denied-read probes before the
child and successful released-read probes afterward. All eight stderr capture
files were empty. The original 92 source hashes were rechecked against the
snapshot after release, and pristine/repeat/poisoned archives all retained the
same exact SHA256 above.

Fix-round reproduction commands, executed from the worktree root in native
PowerShell (the already-declared outer preset is not consumed by the extracted
child, which writes its own explicit-input preset):

```powershell
$cmake = 'C:/msys64/clang64/bin/cmake.exe'
$outer = 'C:/pure-lang/task7-fix1-final'
& $cmake -S pure-audio -B $outer -G Ninja -C C:/pure-lang/task6-fix1-preset.cmake
& $cmake --build $outer --parallel 4
& C:/msys64/clang64/bin/mingw32-make.exe -C pure-audio SHELL=C:/msys64/usr/bin/sh.exe DIST_CMAKE=C:/msys64/clang64/bin/cmake.exe "DIST_AUDIT_BUILD=$outer" distcheck
```

The final contract's generated strict preset, exact subprocess command list,
separate raw stdout/stderr, extracted CTest LastTest.log and public installed
verifier result are retained with its evidence. Native commands ran with the
existing task execution permission required for MSYS signal pipes, not elevated
Windows privileges or a changed Developer Mode policy.

Fix-round focused and fresh full Task7 counts (setup failures and historical
probes excluded):

| Contract | Rejected/neutralized mutations | Valid/pristine controls |
| --- | ---: | ---: |
| Real producer source/output/junction/no-overwrite/caller path matrix | 7 | 0 |
| Direct diffs/deb/distcheck unsupported-input and caller-path targets | 6 | 0 |
| Actual archive endpoint/ancestor junctions | 2 | 0 |
| Actual extra/omitted/changed-hash archives | 3 | 0 |
| Missing declared source input, no final publication | 1 | 0 |
| Binary mixed-case/chunk/late/UTF-16LE scanner | 4 | 1 |
| Non-production file-reparse attribute seam | 1 | 1 |
| Short-build MAX_PATH/ownership/reparse cleanup | 3 | 1 |
| Literal canonical parent / quoted DEBUILD_FLAGS compatibility | 2 | 2 |
| Inherited TAR_OPTIONS/GZIP public archive/source-byte safety | 1 | 0 |
| GNU tar missing hard-dereference capability, before writes | 1 | 0 |
| Real public hardlink topology / ordinary-file control | 1 | 1 |
| Post-configure late binary and junction, seven real phases each | 2 | 0 |
| Exact 92-file/92-SHA pristine archive and deterministic repeat | 0 | 2 |
| **Total** | **34** | **8** |

The eight valid checks comprise one pristine archive and seven controls
(repeat determinism, scanner clean binary, attribute pristine file and owned
build cleanup, literal parent, quoted DEBUILD_FLAGS and independent-file
hardlink-topology control). The end-to-end run
consumes that pristine archive rather than
counting it again as a second independent package. Outside-byte checks total
16 cases: seven producer paths, six direct targets, one build cleanup and two
post-configure integrations.

## Self-review and handoff boundary

The following 11-file scope describes the initial implementation commit; the
review fix round touches only four existing module files and this report.
Before launching its fresh full run, the fix-round diff was reviewed for both
tar create/append coverage, fail-before-reservation capability behavior,
independent native hardlink identity/member/hash oracles, source-byte retention,
final-scan ordering and absence of a production test-selection bypass. Both
actual integration failures retain seven real successful release phases, then
require the intended scanner error and absence of a success artifact; they
also verify outside bytes and source-handle teardown. No Task 1–6 interface or
public production test selection was changed. `git diff --check` passed before
and after the fresh full run. Fix-round scope is exactly
`cmake/CreateSourceArchive.cmake`, `tests/source_dist_contract.cmake`,
`tests/source_dist_extracted.cmake`, `tests/source_dist_tools.ps1` and this report.
The final staged-scope check passed with exactly these five files, and the full
staged diff check passed; no `build/` or ignored progress file is included.
Self-review is not independent re-review approval.

The independent snapshot was also compared with `git ls-files pure-audio`:
all 86 previously tracked files are present, with exactly the six new Task7
helpers/tests added, yielding 92. No required tracked module input is omitted
and no build, generated binary, task report or audit log enters the source
archive. The report itself is deliberately outside the archive's source list.

Reviewed the literal producer/test lists, regular-file/hash validation before
extraction, no-overwrite publication, all alternate cleanup entry points,
short-build ownership/teardown, raw-stream leak scanning and checkout-handle
lifetime. Reviewed the CMake registration in its existing strict Windows branch;
normal configuration and production Tasks1–6 interfaces are unchanged. The
only cross-task edits are the two specifically authorized Task5 fixture fixes.
Self-review is not independent approval; the parent will arrange that review.
Both shipped PowerShell helpers also passed an explicit full-file parser check;
their Windows PowerShell runtime branches are exercised by the actual contract.
The final working-tree and complete staged `git diff --check` passed. Staged
scope was exactly the 11 declared files, with neither `build/` nor the ignored
progress ledger included. TDD and systematic debugging were used for the
actual archive, mutation, MAX_PATH, compatibility and ambient-options failures;
completion claims follow fresh executed evidence, not inferred source behavior.

Scoped changed files (11, including this report): Makefile and CMakeLists;
three producer/workflow helpers (`CreateSourceArchive.cmake`,
`SourceArchiveTools.ps1`, `SourceWorkflow.cmake`); three source contract helpers
(`source_dist_contract.cmake`, `source_dist_extracted.cmake`,
`source_dist_tools.ps1`); the two Task5 contract files; and this Task7 report.
The progress ledger remains an ignored local coordination artifact. Existing
untracked `build/` is preserved and will not be staged. No merge or push is
part of this task.

Retained evidence is intentionally not auto-deleted. Native POSIX execution,
physical audio hardware and unavailable real file-symlink privilege are not
certified. The short extracted build requires a MODULE_DIR of at most 32
characters under the current 202-character downstream fixture budget; a longer
root fails before reservation with an actionable diagnostic. No claim is made
of hostile same-principal race isolation, source-byte normalization across
operating systems, crash cleanup or power-loss atomicity.
The archive producer requires GNU tar and gzip in the same validated tool
directory (the tested MSYS `/usr/bin` layout). Alternate POSIX tool-prefix
layouts and native POSIX package workflows remain subject to their own gate;
no portability claim for BSD tar is made.
