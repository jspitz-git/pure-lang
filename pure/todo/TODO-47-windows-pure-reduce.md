# TODO-47 - Windows pure-reduce Package

Status: Closed on 2026-08-18
Branch: todo/47-windows-pure-reduce

## Purpose

Determine a reproducible Windows build and packaging model for the large
`pure-reduce` integration.

## Scope

- Inventory the bundled Reduce/CSL sources, generated artifacts, tools, and licenses.
- Separate bridge requirements from the full computer-algebra runtime.
- Assess size, build time, relocatability, and maintenance cost.

## Task List

1. [x] Reproduce the complete dependency and generation pipeline on Windows.
2. [x] Build the bridge and required Reduce runtime components.
3. [x] Make runtime data and executable lookup relocatable.
4. [x] Add symbolic-algebra and lifecycle smoke tests.
5. [x] Decide whether to ship as a separate installer component or artifact.

## Guardrails

- Do not include an incomplete generated runtime.
- Preserve all upstream license and source-offer obligations.

## Validation Plan

- Run representative algebra, simplification, and error cases outside MSYS2.
- Measure installed size and test installation, upgrade, and removal separately.

## Open Questions

- TODO-49 must consume `PureReduce` only as a separate optional installer
  component or downloadable artifact; it must not enter the default frontend
  installation.

## Packaging Decision

Ship PureReduce as the separately selected CMake component `PureReduce` and as
the CI artifact `windows-pure-reduce.zip`. The component is excluded from the
default install. The closure verified at implementation commit
`649b08c485b0d8f26d1c26ec4ac4923394f68374` contains 85 files: the Pure module,
embedded CSL runtime and image, runtime data, tests, inventory, metrics, patches
and license notices. It contains no full REDUCE frontend, `reduce.exe`, source
tree, development archive, MSYS2 tool, or non-system runtime DLL.

This is the installation contract for TODO-49. Upgrade and removal must use
the component's exact installed inventory as the ownership boundary and must
not delete unrelated files under the shared Pure prefix.

## Evidence

### Verified local Windows evidence

The local CLANG64 build and package verifier passed on 2026-08-17. These
measurements describe that successful local run, not a clean GitHub-hosted
runner:

| Measurement | Value |
| --- | ---: |
| exact REDUCE commit | `7efba90661139ae9c73c99fddd55f3fb2fabf69a` |
| exact REDUCE tree | `5573613a2f86efea75695fbe65a73317383884c1` |
| tracked-tree SHA-256 | `134a68fdb10403d3a4c69051eb4e133803ff2659784f2d38ac4d94c7ee9f86d8` |
| local partial-clone Git data | 402,235,138 bytes |
| canonical private source | 1,228,241,276 bytes |
| upstream build tree | 1,529,606,144 bytes |
| upstream build elapsed time | 2,477 seconds |
| upstream build workers | 1 |
| selected CSL closure | 106 objects |
| staged package | 15,155,926 bytes |
| staged package files | 80 |
| local ZIP | 9,349,478 bytes |
| local inner ZIP SHA-256 | `340cdc5ec7aa84ed4c22a8513355b0eaa7b9ab799efbb499522108472e2020df` |

The complete local `reduce`-label suite passed 19/19 tests. It covers the
exact source/patch/build contract, bridge ABI and lifecycle, symbolic algebra,
expected errors, UTF-8 relocation, recursive PE imports, optional component
selection, exact installed inventory, mutations, overlay/removal ownership and
relocation. The installed verifier accepts the exact unchanged layout and
reports 80 files.

The local ZIP writer consumed the verified file set in ordinal relative-path
order, assigned every ZIP entry the fixed timestamp
`2000-01-01T00:00:00+00:00`, and did not modify staged payload metadata. Two
independent archive creations produced the same byte count and SHA-256 above.
This proves deterministic packaging for that historical local payload; the
separately built clean-runner payload and digest are recorded below.

### Final review-fix clean-runner evidence

The final required Windows PureReduce job passed from implementation commit
`649b08c485b0d8f26d1c26ec4ac4923394f68374` on 2026-08-18:

- workflow run: [32105355247](https://github.com/jspitz-git/pure-lang/actions/runs/32105355247);
- Windows job: [95613544742](https://github.com/jspitz-git/pure-lang/actions/runs/32105355247/job/95613544742), `success` in 2,739 seconds;
- artifact: `windows-pure-reduce`, ID `9314029105`, [artifact page](https://github.com/jspitz-git/pure-lang/actions/runs/32105355247/artifacts/9314029105); its [retention-limited API download endpoint](https://api.github.com/repos/jspitz-git/pure-lang/actions/artifacts/9314029105/zip) expires at `2026-11-16T06:04:00Z`;
- exact REDUCE fetch: 392,136,537 bytes;
- canonical private source: 1,228,238,768 bytes;
- upstream build tree: 1,446,306,878 bytes;
- upstream build: 1,735 seconds with one worker;
- selected CSL closure: 106 objects, 2 resources and 48 fonts;
- installed package: 85 files and 15,159,477 bytes;
- authoritative 85-entry inventory: 22,030 bytes, SHA-256
  `a9b62c0f2ef11e487c049c5b6532bd98f1b7d24e8187ca4ac467530dd69d0ac8`;
- authoritative 85-entry SHA manifest: 9,079 bytes, SHA-256
  `a34f51eea1f2b4f8b8daa362e824ce7c2492758094b23211755ee9d18b3a1ae9`;
- embedded 84-entry ownership inventory: 21,775 bytes, SHA-256
  `8066c0071c7340b3a6641bca712fb06dd240a365d9f754f1c7a60fd7266de6ab`;
- installed package metrics: 4,796 bytes, SHA-256
  `351de5d5aee08efc9c451ae73a56e66324eb7ceea3c0dd53c705a2a81661d575`;
- deterministic inner ZIP: 9,353,306 bytes, SHA-256
  `6e4d91d00fea3672bf01f35c5cd83a5c243cb241432e45a38beef31ddbbb8213`;
- uploaded artifact wrapper: 9,341,760 bytes, SHA-256 / upload digest
  `306c09fb9e0c177d55a5ca04bd778efe1536d5b229f595407a29cdec89e51331`;
- complete `reduce`-label suite: 29/29 tests in 466.05 seconds;
- installed component verifier: 85 files, success.

The installed metrics truthfully record the runner's rolling CLANG64 inputs:
zlib `1.3.2-2`, ncurses `6.6-4`, winpthreads
`14.0.0.r283.ga7cb47123-1`, libc++ `22.1.8-1`, libunwind `22.1.8-1`,
compiler-rt `22.1.8-2`, and CRT `14.0.0.r283.ga7cb47123-1`. The CRT input is
the shared-link startup object `lib/dllcrt2.o`. The workflow independently
compared every recorded version, input owner/hash and notice owner/hash to the
live rolling runner before creating the ZIP.

The artifact wrapper and sole inner ZIP were downloaded and hash-checked
independently. Before extraction, all 85 ZIP entries were verified as safe,
case-unique, ordinally sorted and timestamped `2000-01-01T00:00:00+00:00`.
The package was then extracted afresh under
`C:\Users\jiris\AppData\Local\Temp\PureReduce final artifact run 32105355247 649b08c4 with spaces\fresh extracted package with spaces`.
Every embedded inventory hash/size and the exact 85-file set matched a newly
constructed external manifest. With `PATH` limited by the repository driver to
the downloaded module, a matching Pure runtime and Windows system directories,
smoke, lifecycle, first-capture, first-feed and initialization-failure all
exited 0. The registered Unicode relocation contract also exited 0 with the
downloaded `reduce.dll` and `reduce.img` under `relocated 日本語 no aliases`.
The unchanged downloaded package then passed the structural verifier against
the independently reconstructed oracles, and a post-runtime check found 85
files with zero hash mismatches.

The aggregate workflow conclusion is `failure` only because the two unrelated
Windows pure-faust matrix jobs failed. The required `Windows PureReduce
package` job itself and all 13 setup, build, test, provenance, packaging and
upload steps succeeded.

### Historical pre-fix clean-runner evidence

The required Windows PureReduce job passed from implementation commit
`7c0b064c56d0f8186ef86903917a03b3e5ba0b43` on 2026-08-18:

- workflow run: [32080639311](https://github.com/jspitz-git/pure-lang/actions/runs/32080639311);
- Windows job: [95542811896](https://github.com/jspitz-git/pure-lang/actions/runs/32080639311/job/95542811896), `success` in 2,548 seconds;
- artifact: `windows-pure-reduce`, ID `9305888161`, [retention-limited artifact API URL](https://api.github.com/repos/jspitz-git/pure-lang/actions/artifacts/9305888161/zip), expiring at `2026-11-15T23:29:25Z`;
- exact REDUCE fetch: 392,134,513 bytes;
- canonical source: 1,228,233,321 bytes;
- upstream build tree: 1,446,291,042 bytes;
- upstream build: 1,715 seconds with one worker;
- selected CSL closure: 106 objects, 2 resources and 48 fonts;
- installed package: 81 files and 15,135,198 bytes;
- authoritative 81-entry inventory: 21,077 bytes, SHA-256
  `117baf6dc6253e2249f18d00a183167b4c093409f4b54c74b4f20620d11e1945`;
- embedded 80-entry ownership inventory: 20,822 bytes, SHA-256
  `a89ef6e7b70086dd674c6b801f98b147b30fc45f5d1fcda5481659c6709ae058`;
- deterministic inner ZIP: 9,344,138 bytes, SHA-256
  `7227839b2f1d98be16bc6bafe292a25393daad4af3bdb487c80f6455f07e954a`;
- uploaded artifact wrapper: 9,333,027 bytes, SHA-256 / upload digest
  `23ea055b92e4cfefe5e3d0b9591e00569f18ce5df977e053767df6f4aba08a7d`;
- complete `reduce`-label suite: 23/23 tests in 373.52 seconds;
- installed component verifier: 81 files, success.

The workflow's aggregate conclusion is `failure` because both unrelated
Windows pure-faust matrix jobs failed. The required `Windows PureReduce
package` job itself and each of its 12 build, test, verification and upload
steps succeeded; the aggregate result is not described as green.

The downloaded artifact wrapper matched the GitHub upload digest, and its sole
inner ZIP matched the workflow transcript. The inner ZIP was extracted afresh
under
`C:\Users\jiris\AppData\Local\Temp\PR artifact 32080639311 short 8e5d\package with spaces`.
With `PATH` limited to that module directory, a matching temporary Pure runtime
directory, and Windows system directories (`MSYS2` absent), the installed smoke
and lifecycle drivers both exited 0. The independent structural installed
verifier then accepted the unchanged 81-file package and exact manifest.

## Progress Log

- 2026-07-25: Created as a large optional Windows package investigation.
- 2026-08-17: Completed the exact-pin local Windows implementation and chose
  the separate optional `PureReduce` component/artifact model. Added build,
  package, relocation, lifecycle, inventory and licensing evidence.
- 2026-08-18: The clean Windows PureReduce job passed all 23 tests, installed
  verification and artifact upload. Independently downloaded and hash-checked
  the artifact, extracted it into a new path containing spaces, and passed its
  smoke, lifecycle and installed-package verification without MSYS2 on
  `PATH`. Closed TODO-47 with the separate-component decision unchanged.
- 2026-08-18: Closed all final-review gaps on implementation SHA
  `649b08c485b0d8f26d1c26ec4ac4923394f68374`. The replacement clean Windows
  job passed 29/29 tests, fail-closed rolling provenance, the 85-file installed
  verifier, deterministic ZIP creation and upload. Independently downloaded
  and verified both archive layers, reconstructed the 85/84-entry inventories,
  and passed installed smoke, lifecycle, first-operation capture/feed,
  initialization-failure and registered Unicode relocation checks.
  - Validation:
    - `gh api repos/jspitz-git/pure-lang/actions/jobs/95613544742` returned
      `completed/success` for exact SHA `649b08c485b0d8f26d1c26ec4ac4923394f68374`.
    - `gh run view 32105355247 --repo jspitz-git/pure-lang --job 95613544742 --log`
      reported 29/29 tests, the 85-file verifier, both archive digests and all
      successful provenance/package/upload gates.
    - `gh api repos/jspitz-git/pure-lang/actions/artifacts/9314029105` matched the
      independently downloaded wrapper size/digest and reported the retention
      expiry above.
    - These exact commands downloaded and checked both archive layers, required
      one safe inner member and 85 safe deterministic payload entries, and
      extracted into the fresh root:

      ```powershell
      $root = 'C:/Users/jiris/AppData/Local/Temp/PureReduce final artifact run 32105355247 649b08c4 with spaces'
      $outer = "$root/github artifact wrapper.zip"
      $inner = "$root/windows-pure-reduce.zip"
      $stage = "$root/fresh extracted package with spaces"
      $token = (& gh auth token | Out-String).Trim()
      Invoke-WebRequest -Uri 'https://api.github.com/repos/jspitz-git/pure-lang/actions/artifacts/9314029105/zip' -OutFile $outer -Headers @{Authorization="Bearer $token";Accept='application/vnd.github+json';'X-GitHub-Api-Version'='2022-11-28'}
      $outerItem = Get-Item -LiteralPath $outer
      $outerSha = (Get-FileHash -LiteralPath $outer -Algorithm SHA256).Hash.ToLowerInvariant()
      if ($outerItem.Length -ne 9341760 -or $outerSha -cne '306c09fb9e0c177d55a5ca04bd778efe1536d5b229f595407a29cdec89e51331') { throw 'outer wrapper mismatch' }
      Add-Type -AssemblyName System.IO.Compression
      Add-Type -AssemblyName System.IO.Compression.FileSystem
      $wrapper = [IO.Compression.ZipFile]::OpenRead($outer)
      try { $entries = @($wrapper.Entries); if ($entries.Count -ne 1 -or $entries[0].FullName -cne 'windows-pure-reduce.zip') { throw 'unexpected wrapper entries' }; $source = $entries[0].Open(); $destination = [IO.File]::Open($inner,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None); try { $source.CopyTo($destination) } finally { $destination.Dispose(); $source.Dispose() } } finally { $wrapper.Dispose() }
      $innerItem = Get-Item -LiteralPath $inner
      $innerSha = (Get-FileHash -LiteralPath $inner -Algorithm SHA256).Hash.ToLowerInvariant()
      if ($innerItem.Length -ne 9353306 -or $innerSha -cne '6e4d91d00fea3672bf01f35c5cd83a5c243cb241432e45a38beef31ddbbb8213') { throw 'inner ZIP mismatch' }
      $archive = [IO.Compression.ZipFile]::OpenRead($inner)
      try { $entries = @($archive.Entries); if ($entries.Count -ne 85) { throw 'entry-count mismatch' }; [string[]]$names = @($entries | ForEach-Object { $_.FullName }); [string[]]$sorted = @($names); [Array]::Sort($sorted,[StringComparer]::Ordinal); $folded = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase); for ($i=0; $i -lt $names.Count; $i++) { if ($names[$i] -cne $sorted[$i]) { throw 'non-ordinal ZIP' } }; foreach ($entry in $entries) { $name=$entry.FullName; if ([string]::IsNullOrWhiteSpace($entry.Name) -or [IO.Path]::IsPathRooted($name) -or $name.Contains('\') -or ($name.Split('/') | Where-Object { $_ -in @('','.','..') }) -or -not $folded.Add($name)) { throw "unsafe ZIP entry: $name" }; $stamp=$entry.LastWriteTime; if ($stamp.Year -ne 2000 -or $stamp.Month -ne 1 -or $stamp.Day -ne 1 -or $stamp.Hour -ne 0 -or $stamp.Minute -ne 0 -or $stamp.Second -ne 0) { throw "non-deterministic timestamp: $name" } } } finally { $archive.Dispose() }
      [IO.Compression.ZipFile]::ExtractToDirectory($inner,$stage)
      ```

    - These exact commands reconstructed the oracles and passed the structural
      verifier:

      ```powershell
      & C:/msys64/clang64/bin/cmake.exe "-DSTAGE_PREFIX=C:/Users/jiris/AppData/Local/Temp/PureReduce final artifact run 32105355247 649b08c4 with spaces/fresh extracted package with spaces" "-DORACLE_DIR=C:/Users/jiris/AppData/Local/Temp/PureReduce final artifact run 32105355247 649b08c4 with spaces/independently reconstructed oracles with spaces" -P 'C:/Users/jiris/AppData/Local/Temp/PR artifact 32080639311 short 8e5d/construct-independent-oracles.cmake'
      & C:/msys64/clang64/bin/cmake.exe "-DBUILD_DIR=C:/Users/jiris/AppData/Local/Temp/PureReduce final artifact run 32105355247 649b08c4 with spaces/independently reconstructed oracles with spaces" "-DSTAGE_PREFIX=C:/Users/jiris/AppData/Local/Temp/PureReduce final artifact run 32105355247 649b08c4 with spaces/fresh extracted package with spaces" "-DAUTHORITATIVE_MANIFEST=C:/Users/jiris/AppData/Local/Temp/PureReduce final artifact run 32105355247 649b08c4 with spaces/independently reconstructed oracles with spaces/PureReduceExpected.sha256" "-DPURE_EXECUTABLE=C:/pure-lang/pure/build/windows-clang64-prefix/bin/pure.exe" -DLLVM_READOBJ=C:/msys64/clang64/bin/llvm-readobj.exe "-DSOURCE_PREFIX=C:/pure-lang/.worktrees/todo-47-windows-pure-reduce/pure-reduce;D:/a/pure-lang/pure-lang/source with spaces/pure-reduce" "-DORIGINAL_BUILD_PREFIX=D:/a/pure-lang/pure-lang/source with spaces/build/windows PureReduce release" "-DORIGINAL_STAGE_PREFIX=D:/a/pure-lang/pure-lang/source with spaces/build/windows PureReduce release/staged PureReduce package" -DVERIFY_ONLY=ON -DRUN_RUNTIME_TESTS=OFF -P C:/pure-lang/.worktrees/todo-47-windows-pure-reduce/pure-reduce/cmake/VerifyInstalledPackage.cmake
      ```

    - This exact loop passed the four installed runtime tests; the following
      literal invocation also passed `initialization-failure`:

      ```powershell
      $stage = 'C:/Users/jiris/AppData/Local/Temp/PureReduce final artifact run 32105355247 649b08c4 with spaces/fresh extracted package with spaces'
      foreach ($test in @('smoke','lifecycle','first-capture','first-feed')) { & C:/msys64/clang64/bin/cmake.exe -DPURE_EXECUTABLE=C:/pure-lang/pure/build/windows-clang64-prefix/bin/pure.exe -DPURE_LIBRARY_DIR=C:/pure-lang/pure/build/windows-clang64-prefix/lib/pure "-DPURE_SOURCE_DIR=$stage/lib/pure" "-DMODULE_DIR=$stage/lib/pure" "-DTEST_SCRIPT=$stage/share/doc/pure-reduce/tests/$test.pure" "-DEXPECTED_MARKER=pure-reduce $test passed" -P C:/pure-lang/.worktrees/todo-47-windows-pure-reduce/pure-reduce/cmake/RunPureReduceTest.cmake }
      & C:/msys64/clang64/bin/cmake.exe -DPURE_EXECUTABLE=C:/pure-lang/pure/build/windows-clang64-prefix/bin/pure.exe -DPURE_LIBRARY_DIR=C:/pure-lang/pure/build/windows-clang64-prefix/lib/pure "-DPURE_SOURCE_DIR=$stage/lib/pure" "-DMODULE_DIR=$stage/lib/pure" "-DTEST_SCRIPT=$stage/share/doc/pure-reduce/tests/initialization-failure.pure" "-DEXPECTED_MARKER=pure-reduce initialization-failure passed" -P C:/pure-lang/.worktrees/todo-47-windows-pure-reduce/pure-reduce/cmake/RunPureReduceTest.cmake
      ```

    - This exact post-runtime command proved that the package stayed unchanged:

      ```powershell
      $manifest = "$root/independently reconstructed oracles with spaces/PureReduceExpected.sha256"
      $mismatches = @()
      foreach ($line in Get-Content -LiteralPath $manifest) { if ($line -notmatch '^([0-9a-f]{64})  (.+)$') { throw "malformed manifest row: $line" }; $expected=$Matches[1]; $relative=$Matches[2]; $actual=(Get-FileHash -LiteralPath (Join-Path $stage $relative) -Algorithm SHA256).Hash.ToLowerInvariant(); if ($actual -cne $expected) { $mismatches += $relative } }
      $fileCount = @(Get-ChildItem -LiteralPath $stage -Recurse -File -Force).Count
      if ($mismatches.Count -ne 0 -or $fileCount -ne 85) { throw 'post-runtime package changed' }
      ```

    - The registered Unicode relocation passed with this exact invocation:

      ```powershell
      $scratch = "$root/registered unicode relocation scratch"
      & C:/msys64/clang64/bin/cmake.exe -DCMAKE_COMMAND=C:/msys64/clang64/bin/cmake.exe "-DREDUCE_DLL=$stage/lib/pure/reduce.dll" "-DREDUCE_IMAGE=$stage/lib/pure/reduce.img" "-DPURE_MODULE=$stage/lib/pure/reduce.pure" -DPURE_EXECUTABLE=C:/pure-lang/pure/build/windows-clang64-prefix/bin/pure.exe -DPURE_LIBRARY_DIR=C:/pure-lang/pure/build/windows-clang64-prefix/lib/pure "-DPURE_SOURCE_DIR=$stage/lib/pure" -DTEST_DRIVER=C:/pure-lang/.worktrees/todo-47-windows-pure-reduce/pure-reduce/cmake/RunPureReduceTest.cmake "-DTEST_SCRIPT=$stage/share/doc/pure-reduce/tests/unicode-relocation.pure" "-DSTAGE_ROOT=$scratch" "-DEXPECTED_MARKER=pure-reduce unicode-relocation passed" -P C:/pure-lang/.worktrees/todo-47-windows-pure-reduce/pure-reduce/cmake/RunPureReduceUnicodeTest.cmake
      ```
