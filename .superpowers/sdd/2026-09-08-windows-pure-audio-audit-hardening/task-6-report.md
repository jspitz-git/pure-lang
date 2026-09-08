# Task 6 report — Blocked local-license preflight

Date: 2026-09-09 (Europe/Prague).
Workspace: `C:/pure-lang/.worktrees/todo33-audit`.
Branch: `codex/todo33-audit`. Implementation base: `ec67ed023ec3799313f56eb783e6cb7f9bb0a382`.

## Status and required decision

**Task 6 is blocked before implementation.** The required exact local license
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
