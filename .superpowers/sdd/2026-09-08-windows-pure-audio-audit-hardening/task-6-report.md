# Task 6 report — Exact installation and licensed audio inventory

Date: 2026-09-09 (Europe/Prague).
Workspace: `C:/pure-lang/.worktrees/todo33-audit`.
Branch: `codex/todo33-audit`. Implementation base: `ec67ed023ec3799313f56eb783e6cb7f9bb0a382`.

Current fix-round status: all four reviewer findings addressed and self-reviewed.
Final combined suite **10/10 PASS in 961.42 seconds**. Task 6 contracts contain
**106 negative mutations, 18 positive controls and 6 complete pristine runs**;
one additional retained production-helper pristine install passed afterward.
Current package: **61 owned artifacts (22 runtime / 39 documentation), delta 61,
29 staged PEs, 27 bundled license/notice payloads**. Detailed current evidence
and limitations are in the Fix round 1 section below.

Checkpoint 93e1a5bf status: implemented, self-reviewed and verified after the user-authorized
official license retrieval. Final suite: **9/9 passed**, including **82 negative
install mutations, 3 complete pristine verifications and 4 positive controls**.
The earlier blocking checkpoint is retained below as historical evidence.

## Historical checkpoint be7afa96: local-license preflight

**At checkpoint be7afa96, Task 6 was blocked before implementation.** The required exact local license
texts for FFTW, Vorbis and LAME are absent from their installed CLANG64 package
payloads and cached package archives. No corresponding authoritative project
license file was found in the existing repository. In particular, Vorbis's
installed headers refer explicitly to a `COPYING` file that is not present.

The approved design, Task 6 brief and progress ruling require stopping when
these exact local texts cannot be sourced. They forbid network downloads,
paraphrases, fabricated license files and treating upstream links as a
replacement. Therefore no install behavior, inventory, test implementation or
license payload was changed. The old installer is not certified by this
preflight and must not be presented as a complete licensed distribution.

To resume, provide authoritative local license payloads corresponding to
FFTW 3.3.11, libvorbis 1.3.7 and LAME 3.100 in an approved repository or
installed-package location. Any alternative runtime scope or license-version
selection needs an explicit ruling; it was not inferred during this task.

## Read-only evidence

The applicable approved plan and design, all progress rulings, the complete
Task 6 brief, and existing install/verifier/third-party files were read.
`git worktree list` confirmed the existing isolated worktree and base commit.
The only initial worktree status entry was the preserved untracked `build/`.
The repository's only AGENTS guide concerns TODO documents, which were not
modified.

Installed package database `desc` and `files` records were read directly under
`C:/msys64/var/lib/pacman/local/`. This avoided the sandbox failure of the
read-only `pacman -Ql` attempt (`couldn't create signal pipe, Win32 error 5`);
that infrastructure error is not licensing evidence.

| Installed package | Version | Affected bundled DLLs | License-named archive entries |
| --- | --- | --- | --- |
| mingw-w64-clang-x86_64-fftw | 3.3.11-1 | libfftw3-3.dll | 0 / 71 entries |
| mingw-w64-clang-x86_64-libvorbis | 1.3.7-2 | libvorbis-0.dll, libvorbisenc-2.dll | 0 / 168 entries |
| mingw-w64-clang-x86_64-lame | 3.100-3 | libmp3lame-0.dll | 0 / 36 entries |

The installed manifests contain headers, binaries, libraries and documentation,
but no COPYING/LICENSE/LICENCE payload. Their matching local cached archives
were independently listed with native CMake's archive reader:

```powershell
foreach ($auditPackageName in @('fftw-3.3.11-1','libvorbis-1.3.7-2','lame-3.100-3')) {
  $auditArchive='C:/msys64/var/cache/pacman/pkg/mingw-w64-clang-x86_64-' + $auditPackageName + '-any.pkg.tar.zst'
  $auditArchivePaths=& C:/msys64/clang64/bin/cmake.exe -E tar tf $auditArchive
  if ($LASTEXITCODE -ne 0) { throw ('Cannot inspect local package archive ' + $auditArchive) }
  $auditLicensePaths=@($auditArchivePaths | Select-String -Pattern '(?i)(copying|licen[sc]e)')
  'PACKAGE_LICENSE_AUDIT package=' + $auditPackageName + ' archive_entries=' + $auditArchivePaths.Count + ' license_named_entries=' + $auditLicensePaths.Count
}
$auditMissingLicenses=@('C:/msys64/clang64/share/licenses/fftw/COPYING','C:/msys64/clang64/share/licenses/libvorbis/COPYING','C:/msys64/clang64/share/licenses/lame/COPYING') | Where-Object { -not (Test-Path -LiteralPath $_ -PathType Leaf) }
if ($auditMissingLicenses) { 'LICENSE_PREFLIGHT_BLOCKED missing=' + $auditMissingLicenses.Count; $auditMissingLicenses; exit 1 }
```

Observed exit **1**, with all three archive counts above followed by
`LICENSE_PREFLIGHT_BLOCKED missing=3` and the three absent paths. This is a
real missing-artifact preflight failure, not a completed production mutation
contract and not a GREEN installation result.

The filename search was supplemented by content and repository checks:

- All installed `share/doc/libvorbis-1.3.7`, `share/doc/lame/html` and Vorbis
  include files were searched for licensing and redistribution terms. Vorbis
  headers identify a BSD-style license in absent `COPYING`; no full BSD terms
  occur in the installed Vorbis docs/headers. RFC copying conditions apply to
  that RFC and are not substituted for the library license.
- All three installed `share/info/fftw3.info*.gz` files were decompressed
  read-only in memory with .NET GZipStream. The `License and Copyright` node
  gives FFTW's copyright and GPL-2.0-or-later notice, explicitly refers to a
  copy of the GPL that should accompany the program and links to GNU. It does
  not contain the full GPL. The BSD terms in `include/fftw3.h` explicitly apply
  only to the header file, not the runtime DLL.
- `C:/msys64/clang64/bin/lame.exe --license` prints the copyright and
  LGPL-2.0-or-later notice, then directs the reader to the missing GNU Library
  GPL text. Installed HTML similarly links to LGPL; it does not supply it.
- `git ls-files '*COPYING*' '*LICENSE*' '*LICENCE*'` inventoried repository
  license files. `git grep -n -i -e 'Xiph.org' -e 'Vorbis' -- '*COPYING*'
  '*LICENSE*' '*LICENCE*'` found no matching repository license text. An
  additional filename scan across the local MSYS2 tree found no FFTW/Vorbis/
  LAME license payload in another installed prefix. Generic GPL/LGPL texts
  belonging to other projects were not relabelled as these projects' exact
  authoritative license files.

## Available local license sources

The following nine exact local payloads exist and were SHA-256 hashed. They
were not copied into the repository because the mandatory preflight is
blocked. These identify seven other audio dependency projects plus the two
reused winpthreads/libc++ runtime projects; this is not a claim that the full
portable Pure baseline license inventory has already been completed.

| Local origin under C:/msys64/clang64/ | SHA-256 |
| --- | --- |
| share/doc/portaudio/LICENSE.txt | ec52a1952d701f94e5135719a47376da4ee0b4a0201f1cafb49f61db6480ac3d |
| share/licenses/libsamplerate/COPYING | 2c1f76ce2effdddb425018405d5690c0b1ab4e6976e35296b0a6db65c5e1a55d |
| share/licenses/libsndfile/COPYING | ad01ea5cd2755f6048383c8d54c88459cd6fcb17757c5c8892f8c5ea060f6140 |
| share/licenses/libogg/COPYING | d2ab5758336489da61c12cc5bb757da5339c4ae9001f9bb0562b4370249af814 |
| share/licenses/flac/COPYING.Xiph | 7866ee98760fc1f0156b4fe6bf530257e02be487ab3fd94e2b63799dd32d6b2c |
| share/licenses/opus/COPYING | 01e1167d54a096d123cf6dfbbeb19587278845c6481d2d66d545669846079551 |
| share/licenses/mpg123/COPYING | c22482728a634a8dfdb4ff72a96d4c1ed64cd8f3e79335c401751ac591609366 |
| share/licenses/winpthreads/COPYING | 63263614cdd29f2f93cba85e992f041b31f9fc7b4033692f31269489a8a1b177 |
| share/licenses/libc++/LICENSE | 539dd7aed86e8a4f12cbdd0e6c50c189c7d74847e4fecc64ce2c6ee3a01da38b |

## Counts, self-review and preserved state

- License preflight: **9 local texts available; 3 required project texts
  missing, affecting 4 DLLs**. No license payload was created or copied.
- Installation artifact/component/delta counts: **not established**; no
  installation was attempted and no component manifest was produced.
- Task 6 staged PE verification: **not run**. Task 5's earlier 29-PE result
  is not reused as evidence of a Task 6 installed artifact.
- Behavioral install mutation/pristine counts: **0 / 0, not implemented**.
  The licensing preflight itself failed once as intended on actual absent
  artifacts. No GREEN claim is made.
- Changed files: only this report. No production code, tests, THIRD_PARTY.md,
  licenses, TODO or later-task files were changed. `build/` remains preserved.

Self-review compared the blocking result with the explicit approved ruling,
checked that the package archives and embedded-document alternatives had been
examined, and distinguished available notices/links from full exact license
payloads. No network access, fabricated text, legal reinterpretation,
subagents, merge, push or broad cleanup was used. Task 6 remains incomplete
pending authoritative local license material and a new implementation turn.

## Checkpoint 93e1a5bf: resumption authorization and ownership boundary

On 2026-09-09 the user explicitly authorized downloading the missing exact
upstream license texts. This supersedes only the earlier no-download ruling;
it does not authorize mirrors, paraphrases, fabricated terms, or later-task
work. The historical preflight above remains evidence, not the current status.

The parent clarified that Task 6 owns eleven new audio/codec DLLs and maps the
two reused audio-relevant baseline DLLs, libc++ and winpthreads. The existing
portable Pure tree remains baseline-owned. Its forty regular files are
frozen at configuration, compared byte-for-byte at installation/verification,
and included in the full 29-PE check; its license inventory is not duplicated
or silently certified. The baseline lacks its own third-party license
materials, a residual baseline-package issue for its owner before distribution.
This was the boundary in checkpoint 93e1a5bf's THIRD_PARTY.md. The review-round
authorization below supersedes its license-inventory limit and resolves the
nine-DLL omission; binary ownership remains unchanged.

## Official upstream retrieval evidence

All requests used the native Windows curl with `--fail --silent --show-error
--max-redirs 0 --proto '=https'`; no `--location` and no mirror redirect was
followed. Each response had HTTP 200 and the exact requested effective URL.
Retrieval date: 2026-09-09 UTC. Byte-exact payloads are committed with a local
`.gitattributes` `* -text` rule, preventing Git line-ending conversion.
The upstream texts contain intentional original trailing whitespace; the
license-only `*.txt -whitespace` rule keeps it verbatim rather than altering
the verified payloads. Code and metadata retain normal whitespace checks.

| Release/provenance | Download or evidence SHA-256 |
| --- | --- |
| FFTW official `https://fftw.org/fftw-3.3.11.tar.gz` | 5630c24cdeb33b131612f7eb4b1a9934234754f9f388ff8617458d0be6f239a1 |
| FFTW official `.tar.gz.md5sum` | b9fea4bb6a08743fb0352f59bb6de1f5811a72f8a671c5b788df375592e8b4cd |
| FFTW archive member `fftw-3.3.11/COPYING` | 231f7edcc7352d7734a96eef0b8030f77982678c516876fcb81e25b32d68564c |
| FFTW archive member `fftw-3.3.11/COPYRIGHT` | 8a74b35d541d93fdf58a22a3d3baa48ae3edbf6d715edfeb6457c21968ae43ac |
| Xiph official API `https://gitlab.xiph.org/api/v4/projects/xiph%2Fvorbis/repository/tags/v1.3.7` | f5cd8e40fae3cc3e00b233b5212c94ff411478e0bda0cded5e83fba4100ed9bb |
| Vorbis `https://gitlab.xiph.org/xiph/vorbis/-/raw/0657aee69dec8508a0011f47f3b69d7538e9d262/COPYING` | ec1815db59fcd302846df949d7424876cb2e2dc5ed1606c5fb0b36787b1cf43a |
| LAME `https://svn.code.sf.net/p/lame/svn/!svn/bc/6403/tags/RELEASE__3_100/lame/COPYING` | bfe4a52dc4645385f356a8e83cc54216a293e3b6f1cb4f79f5fc0277abf937fd |
| LAME same immutable revision `configure.in` | 08f61593248e9a4c7ff88881082b93d6ec1f8f1a773b6cd340e03b466cc7b32f |

FFTW's official release page identifies 3.3.11; archive MD5
`40ec8d0447d03b8f01f8c90aa77bd16f` matches its official checksum. Vorbis's
official tag object `0c55fa38933fd4bdb7db7c298b27e7bf2f2c5e98` resolves to
commit `0657aee69dec8508a0011f47f3b69d7538e9d262`, dated 2020-07-04, with
the 1.3.7 release description. The tag signature was not independently
cryptographically verified. LAME's official SVN listing identifies r6403
(`tag 3.100 release`, 2017-10-14); the retrieved `configure.in`, line 21,
contains `AC_INIT([lame],[3.100],...)`.

The nine local sources and hashes listed in the historical audit were copied
without modification. Along with the four downloaded release members this
gives thirteen full payloads for twelve projects and thirteen DLL mappings.
`pure-audio/licenses/origins.tsv` is the machine-readable complete origin,
package-version, canonical URL, license-ID, mapping, date and SHA-256 record.
The local package IDs/versions and the two reused DLL identities were read
from the installed MSYS2 package database and Task 5 frozen runtime sources.

## Implementation and initial behavioral RED/GREEN

The initial independent fixture copied the real portable Pure prefix, placed
a non-identical `lib/pure/audio.pure` baseline file, snapshotted the full tree,
then ran the actual old runtime install. It returned success and/or changed
the prefix, causing the expected test exit 1:

```
RED: install accepted a non-identical collision or partially wrote the prefix
C:/pure-lang/task5-fix1/pure-audio-contract-root/run-719e8905058557e57dcfd25d0e338550
```

The same `-DRED_ONLY=ON` invocation against the fresh `task6-green` build
returned exit 0 after implementation: collision rejection occurred before
any prefix file changed. Native strict configure succeeded; the first
`cmake --build C:/pure-lang/task6-green --parallel 4` completed 19/19 steps.

The new artifact policy covers all configured sources, destinations, hashes,
components, project/version/source URLs, license identifiers and mappings.
Non-module source bytes freeze at configure; the five built module hashes
seal on the first successful build. Later build/install/verify cannot refresh
an existing seal. Runtime and documentation install separately, preflight
all destinations before any prefix write, skip byte-identical baseline files,
and keep per-prefix audit records outside the distributed tree. The verifier
requires the exact sorted baseline plus declared component deltas, rechecks
all source bytes, calls Task 5 for the staged PE closure, and uses Task 4's
native runner for the installed smoke. No parallel launcher or PE parser was
introduced.

Self-review found two additional behavioral regressions, both tested before
their fixes. A fixture-owned junction redirected the executable CMake context;
its harmless marker ran before the original rejection (RED exit 1, evidence
`task6-green/pure-audio-contract-root/run-8036cd6bbe5a14ecf6a785717c21d78f`).
The verifier now validates the context and all ancestors with Task 5 helpers
using registry-derived Windows authority before including it. The same
`-DCONTEXT_RED_ONLY=ON` test then passed without creating the marker. A real
non-strict configure with `-DPURE_DOCUMENTATION_INSTALL_DIR=share/doc/audio docs`
also exposed an unnecessarily narrowed relative-path rule (RED exit 1);
restoring upstream's relative-path semantics made that same configure GREEN.
The fixed layout restriction remains exclusive to strict audit mode.

The first complete matrix returned `negatives=81 pristine=3` before adding
the context test; its complete evidence remains at
`C:/pure-lang/task6-green/pure-audio-contract-root/run-d2f8de786c036fbcaaef81c834a0a65a`.
The final matrix includes the context regression and normal-path control.

## Final verification commands and expected inventory

All native configure/build/test commands were run with the explicitly
authorized native process permission needed for Windows signal pipes.
Toolchain: Clang/LLVM **22.1.8**, Pure **0.68**, CMake **4.4.0**, Ninja
**1.13.2**, pkgconf **3.0.4**. Task 5's readobj pin remains
`040c4cb0740d2a9d9f7b488bc676c0406eb12c7b349acba1797c2f58865087cb`.

```powershell
C:/msys64/clang64/bin/cmake.exe -S pure-audio -B C:/pure-lang/task6-green -G Ninja -C C:/pure-lang/task5-inputs.cmake
C:/msys64/clang64/bin/cmake.exe --build C:/pure-lang/task6-green --parallel 4
C:/msys64/clang64/bin/cmake.exe --build C:/pure-lang/task6-green --target verify-windows-dependencies --parallel 4
C:/msys64/clang64/bin/ctest.exe --test-dir C:/pure-lang/task6-green -L audio --parallel 2 --output-on-failure
C:/msys64/clang64/bin/cmake.exe -DKEEP_EVIDENCE=ON -DSOURCE_DIR=C:/pure-lang/.worktrees/todo33-audit/pure-audio -DMODULE_DIR=C:/pure-lang/task6-green -DCLANG64_PREFIX=C:/msys64/clang64 -DPURE_PREFIX=C:/pure-lang/pure/build/windows-clang64-prefix -DRUNNER=C:/pure-lang/task6-green/run_pure_test.exe -P pure-audio/tests/install_contract.cmake
```

`task5-inputs.cmake` is the existing Task 5 explicit-input preset, reproducible
with its `configure_contract.cmake` entry point using
`-DWRITE_PRESET_ONLY=ON -DPRESET_OUTPUT=<preset-path>` and the same SOURCE_DIR,
CLANG64_PREFIX, PURE_PREFIX and RUNNER arguments above. The
standalone installed verifier now uses its trusted generated build context:

```powershell
C:/msys64/clang64/bin/cmake.exe --install C:/pure-lang/task6-green --prefix <copied-portable-Pure-stage> --component runtime
C:/msys64/clang64/bin/cmake.exe --install C:/pure-lang/task6-green --prefix <copied-portable-Pure-stage> --component documentation
C:/msys64/clang64/bin/cmake.exe -DAUDIO_INSTALL_CONTEXT=C:/pure-lang/task6-green/windows-install-context.cmake -DSTAGE_PREFIX=<copied-portable-Pure-stage> -P pure-audio/cmake/VerifyInstalledPackage.cmake
```

| Exact package category | Count |
| --- | ---: |
| Built modules / Pure interfaces / new runtime DLLs | 5 / 6 / 11 |
| Runtime component artifacts | 22 |
| Docs / examples / installed tests / license texts / provenance record | 4 / 2 / 5 / 13 / 1 |
| Documentation component artifacts | 25 |
| Total owned artifact records / separately mapped reused baseline records | 47 / 2 |
| Standard delta / identical-preseed delta | 47 / 46 |
| Standard runtime delta / identical-preseed runtime delta | 22 / 21 |
| Documentation delta, either order | 25 |
| Portable Pure baseline regular files | 40 |
| Standard fixture tree with one unrelated baseline marker | 41 baseline + 47 delta = 88 |
| Reverse-order fixture with one identical preseeded interface | 41 baseline + 46 delta = 87 |
| Staged PE closure in every complete pristine run | 29 |
| License payloads / projects / mapped DLLs / DLL-to-text edges | 13 / 12 / 13 / 14 |

An independent PowerShell hash check of all origin rows returned
`LICENSE_PAYLOAD_OK texts=13 dlls=13 edges=14`. Both reused runtime binaries
are also byte-identical to the corresponding installed CLANG64 versions:
libc++ SHA-256 `7344daed05388589e9bd691ed1d30c568c374da4b8b6a12e1502185948c03cd4`;
winpthreads SHA-256 `9740bf073286435729b7f2c45ee3116e6eba18a19a367947101be4e854ced9cf`.

The independent matrix declares its own artifact paths and tree snapshots;
it never derives expected component ownership from the producer. It compares
the actual CMake component manifests and separately mutates the preserved
per-stage hashed manifests. Source/build/license mutations operate on private
copies, each first passing an unchanged-byte seal control, so a wrong fixture
cannot masquerade as a source-hash rejection. Missing staged audio.pure and
libportaudio.dll fail both the verifier and a direct Task 4 installed runner
call while inherited checkout/Pure/CLANG64 paths are deliberately poisoned.

| Negative mutation group | Count |
| --- | ---: |
| File/module/late-license/directory/ancestor collisions, no partial writes | 5 |
| Reparse root/ancestor/endpoint | 3 |
| Redirected executable context, rejected before execution | 1 |
| Every individual owned artifact missing | 47 |
| Altered module, runtime, license, unrelated baseline and Pure prelude | 5 |
| Extra nested file / wrong staged PE origin | 2 |
| Missing manifest / missing, duplicate or cross-component row, both components | 8 |
| Missing, duplicate, cross-component or mismapped frozen inventory records | 4 |
| Changed configured source / built module / license source | 3 |
| Host rescue: missing interface/DLL through verifier and direct native runner | 4 |
| Total negative mutations | 82 |

Complete pristine scenarios are standard runtime-then-documentation,
post-mutation restored standard, and documentation-then-runtime with identical
preseed under a path containing spaces. There are also four additional
positive controls: three unchanged-byte private source seals and non-strict
configuration with a spaced relative documentation path.

## Checkpoint 93e1a5bf: self-review and residual concerns

The implementation follows the approved Task 6 checklist and the revised
download/ownership rulings. TDD established three behavioral RED/GREEN cycles;
systematic debugging separated a diagnostic line-wrap mismatch in the test
harness from real product failures. Verification-before-completion governs
the final build, full suite, exact counts and Git checks. No subagent was
spawned under the explicit no-subagents instruction; the parent will obtain
the separate review after this self-reviewed commit. The branch/worktree are
kept as requested, without merge/push or removal of the pre-existing `build/`.

The configured build context, its frozen records and per-stage audit session
are trusted build-owned state, not a portable standalone certificate. The
installer assumes no concurrent writer to the stage; it preflights collisions
but is not a rollback transaction for disk failures or concurrent mutation.
No hardware test, legal compliance conclusion, baseline licensing cleanup,
source-archive/CI work or later-task documentation rewrite is claimed.
Residual distribution issue: the separate portable Pure baseline lacks its
own license materials, and applicable source/offer obligations remain the
distributor's responsibility. Task 6's audio license inventory does not erase
either obligation.

## Final observed results and changed files

The final nine-test suite exited **0**, **9/9 passed**, in **559.19 seconds**;
the install contract took **428.04 seconds**. Its final exact marker was:

```
INSTALL_CONTRACT_OK negatives=82 pristine=3 controls=4 artifacts=47 runtime=22 documentation=25 standard_delta=47 identical_delta=46 pe=29 license_payloads=13 mapped_dlls=13
```

`C:/pure-lang/task6-green/Testing/Temporary/LastTest.log` records the final
run, including the matrix marker at line 147. The final successful matrix
cleaned only its native-runner-owned leaf; the earlier full evidence leaf
listed above was intentionally retained. Final strict regeneration/build
after the normal-path correction again exited 0 and confirmed the unchanged
49-record seal. The real `verify-windows-dependencies` target reported
`PE_CLOSURE_OK count=29`.

The same full suite also freshly recorded:

| Existing contract | Negative / positive or checks |
| --- | --- |
| Cleanup / Make clean / direct Make clean | 13/2, 6/2, 64/24 |
| Native runner | 23/7, 3 executable-parent boundaries, 1 descendant check |
| Strict configure, including poisoned actual build and normal upstream configure | 120/4 |
| Runtime PE verifier | 42/3, 29 PE files |
| Fault harness / public bounds | 2391 / 24 checks |

The harness retains its previously documented intentional
`quarantine_allocation_delta=3`. Across the final suite, contract totals are
**350 negative cases and 49 positive/pristine controls** (including Task 6's
three pristine and four additional controls), not counting the separate
harness/bounds/boundary checks.

Exactly **21 files** are in this Task 6 change: this report; CMakeLists.txt;
Install.cmake; VerifyInstalledPackage.cmake; THIRD_PARTY.md;
tests/install_contract.cmake; and the fifteen files in licenses/ (thirteen
verbatim texts, origins.tsv and its local .gitattributes). `git diff --cached
--check` passes with only verbatim upstream text whitespace exempted. No
Task 7/8 files, TODO documents, parent progress file, baseline payload or
pre-existing untracked `build/` were changed. No merge or push was performed.

## Fix round 1 — implementation and verification record

Reviewer findings supersede the limited baseline-license ruling and the
concurrent-writer limitation above. The user authorized official upstream
license retrieval for the complete staged package. Parent explicitly approved
the narrowly scoped `cmake/install_guard.c` and required CMake/test integration:
path-based CMake COPY_FILE cannot retain destination identity against swaps.

Plan: (1) explicitly invoke Task 4 smoke irrespective of helper/include state;
(2) map all 22 third-party staged DLLs, distinguish the seven project-owned PEs
and Windows system imports, and add exact baseline project licenses;
(3) retain a build/session operation lock through guarded CMake manifest emission,
plus a native stage-identity lock and non-delete/non-reparse directory handles
through snapshot, preflight, copies, preserved manifests, PE/smoke and cleanup;
publish files atomically from validated source handles under retained destination
ancestors, with deterministic concurrent-installer/ancestor-swap and teardown
tests; (4) correct/audit report hashes; then full verification and commit.

Smoke-state RED reproduced against the retained pristine stage: a public
`-DPURE_AUDIO_RUNNER_HELPERS_ONLY=ON` returned INSTALL_PACKAGE_OK without any
completion token. Evidence: `task6-green/pure-audio-contract-root/run-cb7341ec59a67f80993be1d02cd5a08b`.
Explicit fixture invocation now passes both public-define and prior-include
controls (`INSTALLED_SMOKE_STATE_OK controls=2`). Further fix-round evidence
and revised counts follow below.

### Additional behavioral RED evidence

The focused missing-license test stopped on the real staged `libgmp-10.dll`
with no `GMP-COPYINGv2.txt`, before adding payloads. Evidence leaf:
`task6-green/pure-audio-contract-root/run-cb0b4718720afccf778b856921a9ba72`.

The initial operation-lock mutation held an exclusive FileShare.None handle
on `install-operation.lock` while invoking actual `cmake --install`. The old
installer ignored it and changed the stage. Evidence leaf:
`task6-green/pure-audio-contract-root/run-54f0590650a22dd760f622e01f9a88bf`.

A test-only CMake macro intercepted the old first COPY_FILE after real
preflight, renamed `stage/lib/pure`, and inserted an owned junction to an
outside sentinel directory. The old installer wrote **11 files outside the
stage** before its post-tree rejection. Evidence leaf:
`task6-green/pure-audio-contract-root/run-fb3ca3954b8b1f231461035e64781a22`.
An earlier fixture-function attempt lost CMake file-command output scope and
never reached the gate; it was corrected to a macro and is not counted as
product RED/GREEN evidence.

Self-review added a global-namespace ownership assertion. A session-local
mutex failed that behavioral test (`global stage identity is not owned`,
Windows error 2, 6.34 seconds) in `C:/pure-lang/task6-global-red`. The final
guard uses a Global namespace mutex, not a per-Windows-session mutex.

### Native guard and ownership rationale

`cmake/install_guard.c` is the explicitly approved scope expansion. A CMake
path check followed by COPY_FILE does not retain the checked directory's
identity. The helper is build-only, hash-sealed in `install-guard.sha256`, and
does not add a distributed PE or duplicate Pure launching/PE parsing.

For each install or verification, it holds an exclusive build-owned operation
file, a machine-global mutex keyed by the stage volume serial/file ID, and
non-share-delete/non-share-write directory handles. Existing stage and session
files are retained read-only. It keeps these handles through the baseline
snapshot, both-component preflight, component writes, preserved and conventional
manifests, Task 5 PE verification, Task 4 token smoke, and native fixture cleanup.
This ownership spans every stage/session access of the current invocation:
`cmake --install` with no component writes both components under one owner;
separate component calls each reacquire ownership and revalidate the preserved
session. The standalone verifier likewise retains ownership until its PE,
smoke and Task 4 fixture cleanup finish. No background lock process is left
running between CLI invocations.
An unguessable local pipe authenticates requests using the actual client PID
and the guard's CMake-child parent PID; public flags or copied environment
strings do not assert ownership.

Copies hash their actual retained source handle, write and flush a CREATE_NEW
temporary under a retained parent, then publish by native **same-directory
rename from that temporary handle and a simple basename**. No path-based
destination lookup or replace-existing operation is used for package files.
The exact temporary handle is deleted on publication failure. Conventional
component manifests are atomically replaced as directory entries, not written
through an existing endpoint. Install.cmake returns before CMake's unguarded
final manifest WRITE; both normal component and all-component entry points use
the same guarded manifest implementation. A kill-on-close job bounds the CMake
child tree to 240 seconds and prevents descendants surviving the retained
identities. The existing Task 4 child process/smoke/cleanup implementation is
still invoked, not reimplemented.

The Win32 absolute rename prototype failed with sharing error 32, and its
RootDirectory variant returned invalid-parameter error 87 on this host. The
documented native same-directory form works while retaining the no-write and
no-delete directory handles, so no protection is temporarily weakened. Primary
API references: [native rename semantics](https://learn.microsoft.com/en-us/windows-hardware/drivers/ddi/ntifs/ns-ntifs-_file_rename_information),
[CreateFile sharing](https://learn.microsoft.com/en-us/windows/win32/api/fileapi/nf-fileapi-createfilew),
and [global kernel namespaces](https://learn.microsoft.com/en-us/windows/win32/termserv/kernel-object-namespaces).

The deterministic guard fixture is compiled with a test-only first-copy gate
absent from the production executable. Its final matrix checks same-build and
cross-build real installers, retained-ancestor rename, reparse-conversion write
access, forged ownership channel, post-preflight endpoint junction collision,
and an externally held operation lock. Positive controls inspect the global
mutex, resume the first installer, reopen locks and rename directories after
teardown, retry after atomic failure, and install all components twice without
changing bytes. The sentinel has **zero outside writes**. Success and failure
teardown are checked separately. The pre-global extended matrix passed in
59.24 seconds; final evidence below supersedes that intermediate run.

### Whole staged PE licensing coverage and provenance

The user explicitly extended download authorization to complete baseline
coverage. No remaining third-party DLL in the 29-PE staged closure is excluded
on the old audio-only ownership rationale. Task 6 still does not overwrite or
claim ownership of the Pure baseline binaries. The full graph is:

| Class | PE count | Licensing coverage |
| --- | --- | --- |
| New Task 6 dependency DLLs | 11 | Bundled full upstream license/notice payloads |
| Baseline third-party DLLs, including reused libc++/winpthreads | 11 | Bundled full upstream license/notice payloads |
| Project-owned Pure executable/runtime | 2 | Pure COPYING, COPYING.LESSER and README notices |
| Project-owned audio modules | 5 | pure-audio COPYING |
| Windows system/API-set imports | Not redistributed | Task 5 explicit registered-System32 authority, outside the 29 staged PEs |

There are **20 third-party DLL projects**, plus Pure and pure-audio. Under
`licenses/` there are **27 byte-exact license/notice payloads**: 24 third-party
texts and three Pure project texts. The separate own-package COPYING remains
installed too. The graph has **26 third-party DLL-to-text edges**, six Pure
PE-to-text edges, and five audio-module-to-COPYING edges: **37 edges for 29 PEs**.
The aggregate Pure package metadata does not relicense libpure as GPL:
THIRD_PARTY distinguishes executable GPLv3-or-later and runtime LGPLv3-or-later,
and preserves the project's additional linking permission in Pure-README.txt.

All downloads below were direct HTTPS 200 responses without redirects on
**2026-09-09 UTC**. No third-party mirror was used. The exact member URL/origin,
installed package version, full payload SHA-256 and mappings are committed in
`licenses/origins.tsv` and checked by the producer and independent contract.

| Official release/archive | SHA-256 |
| --- | --- |
| [GMP 6.3.0](https://ftp.gnu.org/gnu/gmp/gmp-6.3.0.tar.xz) | a3c2b80201b89e68616f4ad30bc66aee4927c3ce50e33929ca819d5c43538898 |
| [libiconv 1.19](https://ftp.gnu.org/gnu/libiconv/libiconv-1.19.tar.gz) | 88dd96a8c0464eca144fc791ae60cd31cd8ee78321e67397e25fc095c4a19aa6 |
| [MPFR 4.2.2](https://www.mpfr.org/mpfr-4.2.2/mpfr-4.2.2.tar.xz) | b67ba0383ef7e8a8563734e2e889ef5ec3c3b898a01d00fa0a6869ad81c6ce01 |
| [PCRE 8.45, author Exim archive](https://ftp.exim.org/pub/pub/pcre/pcre-8.45.tar.bz2) | 4dae6fdcd2bb0bb6c37b5f97c33c2be954da743985369cddac3546e3218bffb8 |
| [Readline 8.3](https://ftp.gnu.org/gnu/readline/readline-8.3.tar.gz) | fe5383204467828cd495ee8d1d3c037a7eba1389c22bc6a041f627976f9061cc |
| [Termcap 1.3.1](https://ftp.gnu.org/gnu/termcap/termcap-1.3.1.tar.gz) | 91a0e22e5387ca4467b5bcb18edf1c51b930262fd466d5fda396dd9d26719100 |
| [Zstd v1.5.7 LICENSE at resolved commit](https://raw.githubusercontent.com/facebook/zstd/f8745da6ff1ad1e7bab384bd1f9d742439278e99/LICENSE) | 7055266497633c9025b777c78eb7235af13922117480ed5c674677adc381c9d8 |
| [Zlib v1.3.2 LICENSE at resolved commit](https://raw.githubusercontent.com/madler/zlib/da607da739fa6047df13e66a2af6b8bec7c2a498/LICENSE) | e32ff4e00d9d94930537635291da39e7e612703334bf6fde8c7f1686fe8a45a2 |

The official Zstd tag `ac66b19e6bd6b83238bf008eecc1298105298532` resolves to
`f8745da6ff1ad1e7bab384bd1f9d742439278e99`; Zlib tag
`216c70c020aa53f0c40920d155f808b6b59c9acb` resolves to
`da607da739fa6047df13e66a2af6b8bec7c2a498`. The official GitHub ref and annotated
tag responses are retained in `C:/pure-lang/task6-baseline-upstream`. PCRE's
8.45 archive configure.ac declares major 8/minor 45; libiconv declares 1.19;
MPFR's VERSION is 4.2.2. GMP's own configure.ac states LGPLv3-or-later OR
GPLv2-or-later; Termcap's termcap.c explicitly states GPLv2-or-later, rather
than relying on a broad package metadata label. Readline 8.3.003 is base 8.3
plus the three official readline83-001/-002/-003 patches; their independent
hashes are in THIRD_PARTY.md and the downloaded patchlevels form 0 to 1 to 2
to 3, with no COPYING edits. Release signatures were not independently verified.

The nine additionally covered baseline DLLs were each SHA-compared with the
installed CLANG64 package binary: **9/9 exact byte matches**. Thus their package
versions (GMP 6.3.0-2, libiconv 1.19-1, MPFR 4.2.2-3, PCRE 8.45-2,
Readline 8.3.003-1, Termcap 1.3.1-7, Zstd 1.5.7-2, Zlib 1.3.2-2) apply to the
actual baseline files, not just filenames. The baseline license-text omission
identified in review is resolved; corresponding-source/offers and a full
source/static-component legal compliance audit are not certified by this
PE/DLL inventory.

### Final verification commands (fresh build)

The independent Task 5 fixture generated `C:/pure-lang/task6-fix1-preset.cmake`
with WRITE_PRESET_ONLY, then:

```powershell
cmake -S pure-audio -B C:/pure-lang/task6-fix1-green -G Ninja -C C:/pure-lang/task6-fix1-preset.cmake
cmake --build C:/pure-lang/task6-fix1-green --parallel 4
cmake --build C:/pure-lang/task6-fix1-green --target verify-windows-dependencies --parallel 4
ctest --test-dir C:/pure-lang/task6-fix1-green -L audio --output-on-failure --parallel 4
```

The real strict build completed **23/23** steps, sealing **74 inventory
records: 22 runtime, 39 documentation, 13 baseline**. This is **61 Task 6-owned
artifacts**, with standard delta 61 and identical-interface preseed delta 60.
Its four-worker PE target reported `PE_CLOSURE_OK count=29; AMD64 PE32+; UCRT
resolved by Windows loader`. The native guard pin in this build is
`f7f599479ccd6d50a46b3f71e4782f59632991e76024ec251aca9de5df6f8e5d`.
The final full-suite and retained-package evidence follows below.

### Additional zero-delta regression from final self-review

A complete, already-identical installed tree is a legitimate baseline. Its
runtime and documentation manifests must both be empty, and a full installed
PE/token verification must report delta 0. A new independent
`-DFULL_PRESEED_ONLY=ON` control copies an actual complete stage into a new
Task 4-owned leaf, invokes both real component installers, checks both empty
conventional manifests and runs the public verifier.

The first behavioral RED at
`task6-fix1-dev4/pure-audio-contract-root/run-8dd057131a6495d6e45f8634d4124e37`
found unquoted CMake argument expansion dropping the empty manifest byte
stream before the native client. After preserving that explicit argument,
the second RED at
`task6-fix1-dev4/pure-audio-contract-root/run-8368f53400af79ed25d52190b981af53`
found an unset empty delta variable interpreted as a literal by an unquoted
STREQUAL comparison on the second component. Explicit empty initialization
and quoted value comparison resolve this without changing native helper
bytes or the sealed artifact inventory.

The same isolated control then returned exit 0:
`FULL_PRESEED_OK pristine=1 delta=0 manifests=2`. It is now included in the
main matrix as its fourth pristine scenario. The preceding full suite passed
10/10 in 980.60 seconds (99 negative install mutations, three pristine
scenarios and ten controls; native guard 7 negative, 8 controls and 2 pristine
scenarios). That run had already started before the zero-delta control was
integrated, so the final combined suite is repeated rather than treating
the earlier run as coverage of the new case.

### Independent final inventory and hash audit

The independent artifact list now contains 22 runtime and 39 documentation
paths. Runtime remains 5 modules + 6 interfaces + 11 new DLLs; documentation
is 4 package documents + 2 examples + 5 installed test files + 27 full
license/notice payloads + 1 origins record. The separately frozen baseline
contains 40 regular files; its 13 inventoried PEs are 11 dependency DLLs and
the two Pure-owned PEs. Standard, single-interface-preseed and complete-preseed
deltas are respectively 61, 60 and 0. No baseline PE is installed by Task 6.

The fixed libc++ binary hash is
`7344daed05388589e9bd691ed1d30c568c374da4b8b6a12e1502185948c03cd4`.
The historical report's extra character was a transcription error, not a
changed binary. A fresh read-only audit hashed all retained upstream downloads,
the exact license assets, both reused runtime binaries, LLVM readobj and the
final native guard, and required every 60–70-character lowercase hex word in
this report, THIRD_PARTY and origins.tsv to be a 64-character hash matching
an actual file. All references matched. Separately, all 27 nine-field origins
records matched the payload's SHA-256. Git's index blob ID for every payload
matched `git hash-object --no-filters`, proving no line-ending conversion.

Observed markers: `LICENSE_PAYLOAD_OK payloads=27 bin_pes=24 edges=32`,
`BASELINE_PACKAGE_BYTES_OK dlls=9`, and
`INDEX_LICENSE_BYTES_OK payloads=27`. The five audio-module COPYING mappings
complete the 37-edge/29-PE graph. These byte checks supplement, rather than
replace, the real installed PE and Pure-token verification.

### Final combined GREEN results

The full final command was
`C:/msys64/clang64/bin/ctest.exe --test-dir C:/pure-lang/task6-fix1-green -L audio --output-on-failure --parallel 4`.
It returned exit 0: **10/10 PASS, 961.42 seconds wall time**. Complete per-test
commands, output, counts and times are retained in
`C:/pure-lang/task6-fix1-green/Testing/Temporary/LastTest.log`.

| Contract | Negative cases | Positive controls | Complete pristine cases |
| --- | ---: | ---: | ---: |
| Final install matrix (857.29 s) | 99 | 10 | 4 |
| Native guard matrix (104.12 s) | 7 | 8 | 2 |
| Task 6 subtotal | 106 | 18 | 6 |

The 99 install negatives are the prior 82 plus deletion of each of the 14
new payloads and three new changed-source cases (guard executable, baseline
license and provenance). Its ten controls are six unchanged-byte private
seals, the non-strict spaced-path configuration, two public helper/include
states that must execute Pure, and the independent whole-package license
graph. Its four pristine scenarios are standard, restored standard,
single-interface-identical reverse component order, and fully identical
zero-delta. Native guard's exact marker is
`INSTALL_GUARD_CONTRACT_OK negatives=7 controls=8 pristine=2 concurrent_installers=3 outside_writes=0 teardown=2`.
The Global namespace check and reparse-write denial run at the actual first-copy
gate, before the first installer is released. Production has no such gate.

Other final contract markers remain cleanup 13/2, Make cleanup 6/2, direct
Make cleanup 64/24, runner 23/7 (plus three executable-parent boundaries and
one descendant check), configure 120/4, and runtime verifier 42/3. The full
suite therefore exercises **374 negative cases and 66 positive/pristine
cases**, excluding separately counted boundary checks. The fault harness
passed 2,391 checks, including its explicitly intentional three-allocation
quarantine; public Pure bounds passed 24 checks. Load and processing each
returned their exact fresh completion token. No hardware test is claimed.

The post-suite retained package was created by the production helper through
real runtime and documentation component installations, followed by the public
installed verifier with `-DPURE_AUDIO_RUNNER_HELPERS_ONLY=ON`. It independently
SHA-compared every baseline file and returned:

```
FINAL_PRISTINE_OK files=101 baseline=40 delta=61 pe=29 licenses=27
PE_CLOSURE_OK count=29; AMD64 PE32+; UCRT resolved by Windows loader
PURE_AUDIO_DONE_bf6685be1b9a81dc116789a403efa4be
INSTALL_PACKAGE_OK artifacts=61 runtime=22 documentation=39 delta=61 pe=29 license_payloads=27 third_party_dlls=22 project_owned_pe=7
INSTALL_GUARD_OK retained_identity=1 atomic_publish=1 teardown=1
```

Retained stage:
`C:/pure-lang/task6-fix1-green/pure-audio-contract-root/run-291cefe6a8888604cb8f2ffeb96e3a97/package`.
Its sibling `final-verification.log` preserves the real verifier output.
Its preserved component manifests are under the same build's `install-audits/`,
keyed by the SHA-256 of the lowercase canonical stage path.
This is **one additional pristine run**, separate from the six in the Task 6
matrix totals. Passing mutation leaves were removed only by Task 4's native
owned cleanup; this final evidence leaf is intentionally retained.

After the matrix and retained install, the same four-worker build command
rechecked all 74 sealed records without refreshing them, and the four-worker
`verify-windows-dependencies` target again returned `PE_CLOSURE_OK count=29`.

### Final self-review, scope and remaining boundaries

Receiving-code-review, TDD, systematic-debugging and verification-before-
completion guided the fixes: reproduce the reported bypass/write, add an
independent oracle, fix the specific cause, rerun the full real contracts and
inspect their exact output. Self-review covered every Task 6 plan item and
all four findings, native handle/job/pipe ownership and failure teardown,
source SHA matching before publication, disjoint manifests including empty
ones, complete staged PE licensing edges and exact upstream/index bytes.

Fix-round changed files: **23**. They are CMakeLists.txt, THIRD_PARTY.md,
cmake/Install.cmake, cmake/VerifyInstalledPackage.cmake, the approved new
cmake/install_guard.c, tests/install_contract.cmake, the new native guard
contract script, licenses/origins.tsv, fourteen new exact license/notice
payloads, and this report. No Task 7/8 implementation, TODO, parent progress
file, portable baseline binary or existing untracked `build/` was changed.
No subagent, merge or push was used. The parent owns independent review after
this self-reviewed commit.

The build context/source/toolchain remains trusted configure-owned input,
not an untrusted portable certificate. The guard provides exclusion and
atomic per-file publication, not rollback of a whole package after disk or
power failure; an interrupted/incomplete tree fails exact verification.
Release signatures were not independently verified. The nine-DLL baseline
license-text omission is resolved, but corresponding-source/offers and a
source/static-component legal compliance audit remain outside this PE/DLL
artifact-completeness task. These are explicit boundaries, not a claim of
complete legal certification or hardware support.
