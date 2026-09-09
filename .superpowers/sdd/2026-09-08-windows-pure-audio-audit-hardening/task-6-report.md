# Task 6 report — Exact installation and licensed audio inventory

Date: 2026-09-09 (Europe/Prague).
Workspace: `C:/pure-lang/.worktrees/todo33-audit`.
Branch: `codex/todo33-audit`. Implementation base: `ec67ed023ec3799313f56eb783e6cb7f9bb0a382`.

Current status: implemented, self-reviewed and verified after the user-authorized
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

## Resumption authorization and ownership boundary

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
This boundary is explicit in the installed THIRD_PARTY.md.

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
libc++ SHA-256 `7344daed05388589e9bd691edd1d30c568c374da4b8b6a12e1502185948c03cd4`;
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

## Self-review and residual concerns

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
