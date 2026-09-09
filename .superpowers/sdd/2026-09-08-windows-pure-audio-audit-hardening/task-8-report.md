# TODO-33 Task 8 — Windows CI and audited documentation

Date: 2026-09-09, Europe/Prague. Base: `e82bc32ca4d7be726e4d1c175d2c3634cc291895`.
Status: Task 8 fix round 1 fresh verification GREEN (see final section).
TODO stays **Open**, pending independent re-review and Task 9 whole-branch verification.
No merge, push, subagents, hardware exercise or changes under existing `build/`.

## Scope and approved sequencing

The three workflow/validator files, WINDOWS.md, README, TODO-33 and this report
are the seven intended commit paths. No Task 1–7 production interface changed.
The ignored progress ledger remains local coordination, not force-added.

The parent approved a bounded fail-closed PowerShell-command parser over the
PyYAML BaseLoader structure, and this exact sequence after portable Pure:

1. Fresh short strict Release configure with 32 explicit `-D` inputs, including
   24 named runtime source rows; pinned CLANG64 compiler/tools and Pure prefix.
2. One normal build, then one distinct PE target, each `--parallel 4`.
3. `ctest -L "^audio$" -LE "^hardware$" -E "^pure-audio-source-dist-contract$"
   --output-on-failure --no-tests=error --parallel 4`: all other ten tests.
4. Fresh baseline copy, runtime then documentation install, public Task 6
   context+stage verifier (which invokes Task 4 smoke and Task 5 PE verification).
5. Public `make distcheck`, executing exactly the deferred eleventh contract,
   with another real extracted configure/build/PE/ten-test/install/verifier run.

Both steps 3 and 5 are mandatory. No extra exclusion, positive selection,
`--rerun-failed`, missing gate, helper-only/seal substitute or worker override
is accepted. This avoids an unnecessary duplicate outer source audit without
removing any audio test. Hardware is absent from mandatory registration.

CI has 30 required prerequisite packages, explicit step PATH replacement and
empty PURELIB/PURE_INCLUDE/PURE_LIBRARY. The five steps reuse one environment
mapping via YAML anchors/aliases. GitHub documents this syntax in its
[official workflow reuse reference](https://docs.github.com/en/actions/reference/workflows-and-actions/reusing-workflow-configurations).
Required push/PR path inputs include audio, TODO-33, both helpers and workflow;
push branches include master, todo/** and codex/**. Existing ODBC checks remain.

The parser compares native argument vectors, not source substrings: it
normalizes supported quotes, continuations, comments and logging, requires an
immediate LASTEXITCODE throw after each native command, and rejects unknown
statements. Configure/runtime rows are parsed for duplicates and exact origins.
It is deliberately not a general PowerShell interpreter or security proof for
arbitrary additional jobs/scripts. Audited syntax extensions require review.
The selected job must remain Windows-2025 with no job-level defaults override.

## Structural TDD evidence

All commands ran from the worktree with `PYTHONDONTWRITEBYTECODE=1`, using
`C:/Python314/python.exe`. Tests author their own expected input/command data;
they never import policy constants from the production validator. New mutation
files use atomically unique NamedTemporaryFile names and exact-file cleanup.
The inherited three ODBC worker tests retain their pre-existing behavior.

| Checkpoint | Exact result |
| --- | --- |
| Original ODBC tests + pristine validator | 3/3 PASS, 0.160 s; pristine PASS |
| Durable audio RED, before validator implementation | 316 negatives; 304 wrongly accepted, 12 rejected by inherited checks; 3 methods, 304 failures, 41.438 s |
| Validator-first, before real workflow changes | Authored control + all 316 negatives PASS; real old workflow rejected: `push audio trigger inputs are missing`; one failure, 41.468 s |
| Workflow GREEN | 6 methods PASS, 316 audio + 3 ODBC negatives, two pristine controls; 41.452 s |
| Self-review RED | 320 audio negatives; wrong runner and job-default directory wrongly accepted; 4 methods, two failures, 50.740 s |
| Self-review GREEN | 7/7 methods PASS, 320 audio negatives +3 ODBC, 2 pristine +2 formatting controls; 44.468 s |
| Semantic-invocation RED | Four selected real mutations wrongly accepted (comments-only, tests-only, validator-only and wrong workflow); original unittest method has four failures, 0.550 s |
| Expanded GREEN | 7/7 methods PASS, 324 audio negatives +3 ODBC, 2 pristine +2 formatting controls; 44.722 s; actual pristine CLI PASS |
| Fresh final structural GREEN | Same full 7/7 methods/327 negatives/2 pristine/2 formatting controls PASS, 45.503 s; actual pristine CLI PASS |

Durable logs: `C:/pure-lang/task8-yaml-red.log`,
`task8-validator-first.log`, `task8-yaml-green-1.log`,
`task8-yaml-self-review-red.log`, `task8-yaml-green-2.log`,
`task8-semantic-self-review-red.log`, `task8-semantic-unittest-red.log`,
`task8-yaml-green-3.log`, and `task8-yaml-final.log`.
The final matrix adds well-formed duplicate normal/PE command+guard pairs,
plus positive runtime-row-order and multiline/comment formatting controls.
There are 324 audio negatives + 3 preserved ODBC negatives, two pristine and
two formatting controls (seven unittest methods). The selected semantic RED
driver displayed actual unittest failures but did not propagate its result to
the wrapper process (wrapper rc0); its failure count, not that exit status,
is the evidence. The final full script propagates failure normally. The neutral
case marker no longer prints a fixed pristine count when one method is selected.

An earlier developmental 288-case run had 278 failures and a misleading
unconditional `...OK` print. The print was corrected to neutral
`AUDIO_WORKFLOW_CASES`; unittest exit/results are authoritative. That superseded
run is not added to the durable final mutation count.

## Fresh execution method and current evidence

The actual five new workflow `run` strings were loaded from the real YAML with
BaseLoader, not copied from the test-side candidate. They execute unchanged
with concrete local substitutions for job/environment values:

```
AUDIO_SOURCE=C:/pure-lang/.worktrees/todo33-audit/pure-audio
AUDIO_BUILD=C:/pure-lang/task8-final/pa8
AUDIO_STAGE=C:/pure-lang/task8-final/pa8/package
AUDIO_PREFIX=C:/pure-lang/pure/build/windows-clang64-prefix
CMAKE_EXE=C:/msys64/clang64/bin/cmake.exe
CTEST_EXE=C:/msys64/clang64/bin/ctest.exe
LOG_DIR=C:/pure-lang/task8-final/logs
PATH=<AUDIO_PREFIX>/bin;C:/msys64/clang64/bin;C:/msys64/usr/bin;C:/Windows/System32;C:/Windows
PURELIB= PURE_INCLUDE= PURE_LIBRARY=
```

The root was absent, its ancestors checked non-reparse, and its directory and
log child freshly created. No existing audit root was cleaned/reused. Commands
ran with the workflow's `pure` working directory. Native MSYS helper execution
needed the tool sandbox override for signal pipes; no OS elevation was used.

| Fresh Task 8 phase | Result |
| --- | --- |
| PowerShell AST parse | All five real workflow blocks + all five guide blocks parse; zero errors |
| Strict configure | PASS; 6.3362263 s wall |
| Normal build, four workers | PASS; 23/23 Ninja actions, including 74-record seal |
| PE target, four workers | PASS; exact 29 AMD64 PE 32+ PEs, authoritative loader-resolved UCRT |
| Combined two-command build step | 7.410164 s wall |
| CTest inventory | Exactly ten selected tests, every one audio/no-hardware; source contract alone deferred |
| Outer mandatory CTest | 10/10 PASS; 1172.57 s CTest /1172.8369366 s wall; install 814.34 s, guard 339.77 s |
| Outer component install/public verifier | PASS; runtime 22 + documentation 39, exact 61 delta, PE 29/license 27; 43.8473429 s wall |
| Public source distribution + extracted closure | 1/1 PASS 1418.81 s (CTest wall 1418.82/public wall 1419.0552919); pristine extracted 10/10 PASS 1163.64 s |

The selected ten are fault-bounds, load, processing, public-bounds,
runner-contract, cleanup-contract, install-guard-contract, configure-contract,
runtime_verifier-contract and install-contract, each with `pure-audio-` prefix.
Registration includes explicit timeouts; the guard test is serial even when
CTest is launched with four workers.

Outer detailed output is preserved in
`C:/pure-lang/task8-final/logs/ctest-outer-detailed.log` before the subsequent
source CTest overwrites its own LastTest.log. It records 393 rejected scenarios,
72 controls and 6 pristine packages: Task 4 negatives 106/controls 35; configure 119/4;
runtime verifier 41/3; install 99/10/pristine 4; guard 28/20/pristine 2. Guard evidence
includes three concurrent installers, outside_writes=0, teardown 2, twelve
pre-commit rollback cases and twelve successful retries. Native 2391 checks
report quarantine allocation delta 3; public bounds 24 passed. Actual file
symlink setups returned 1314 and are separately skipped once in each Task 5
contract, not added to the negative count.

Outer public token: `PURE_AUDIO_DONE_548d0d88c32acdcbebf61effc2af6c36`.
Its stage has 101 files; an independent post-verifier SHA comparison confirmed
all 40 baseline files unchanged. Both component manifests are preserved under
`C:/pure-lang/task8-final/pa8/install-audits/cc18ad275746151481216d16509a21722dc9194744e44276e721d5d47b07d214`.
Runtime batch commit reports 22 artifacts/2 manifests/63 reservations;
documentation 39/2/41. The public verification guard reports retained identity,
no batch commit and successful teardown. Log: `installed-pure-audio.log`.

The documentation was separately executed, not only parsed: the exact first
PowerShell block, substituting only its three example paths, configured a
fresh `C:/pure-lang/task8-docs/pa8` in 6.8315212 s. The exact standalone unbuilt
dist block, substituting only output directory `C:/pure-lang/task8-docs/release`,
passed in 2.2476135 s. It created 92 regular source members, 242909 bytes, with SHA-256
`41254b9a93328917b58928ed8727a7778dd9a7f8f01afdafdcd19c05321248f5`.
This documentation control does not stand in for the final extracted audit.
Its two logs are `C:/pure-lang/task8-docs/configure.log` and `dist.log`.
All 32 explicit cache input values were compared against the actual workflow
configuration and were identical (source/build locations are not `-D` inputs).
An independent Python tarfile/hashlib read confirmed 92 unique regular members,
all 92 hashes equal to live source bytes, uid/gid 0 and mtime 0 on every member.

Fresh source evidence root:
`C:/pure-lang/task8-final/pa8/pure-audio-contract-root/run-4c08e47eb5ee2d7bf64260362c239a93`.
Its pristine short build is `C:/pure-lang/task8-final/pa8/d--OOQiCqCQTuRtHtoo04MgQ`.
Pristine producer, repeat and poisoned-environment archive SHA-256 values all
match the independent guide archive above. Both topology-control and real
hardlinked-input archives have identical SHA-256
`56273c2159b7dfc48a245b784bcc9612f94e84648c180178b91ea6672d10619b`;
their intentionally changed input bytes are not the pristine source snapshot.
The two postflight mutation copies each ran seven actual release phases and
four actual core tests (the approved test-only integration selection), then
failed specifically at final source scan: late `post-configure-leak.bin` or
new reparse entry. Their production source driver is unchanged, and the
pristine extracted gate still executes all ten tests.

The completed source contract reports **34 rejected scenarios, one pristine
archive and seven controls**. Pristine extracted configure/build/PE/tests/
runtime install/documentation install/public verifier took respectively
7/4/4/1163/11/9/23 whole seconds in its per-phase log. Normal build has 23 Ninja
actions; both normal and PE commands use four workers. Extracted CTest's
precise timings include configure-contract 96.67 s, runtime-verifier 114.31 s,
install 802.05 s and guard 342.46 s. All 10 tests passed in1163.64 s.

Extracted contracts repeat the same 393 negatives/72 controls/6 pristine as
the outer suite; these are repeated executions, not newly invented unique
scenarios. The two explicit privilege 1314 symlink skips also recur. Native
2391/public 24 checks pass. The two postflight mutation runs each add 4 actual
core-test executions while retaining all seven real phases.

Extracted public token: `PURE_AUDIO_DONE_2c7e5c32f2dc32bcd818830ce6111897`.
Its package again has 61 artifacts, runtime 22/documentation 39, delta 61,
PE 29/license 27/third-party DLL22/project PE 7. Final complete scans report92
source files (both initial and post-phase scans), 73 build files, 101 staged
files and 17 raw log files. All eight pristine stderr captures are byte-empty.
`SOURCE_DIST_ISOLATION_OK held=184 roots=2 denied_read=1` and
`SOURCE_DIST_ISOLATION_RELEASED_OK` prove the original/producer source roots
were unavailable during the pristine child and released afterward.

After completion, all 92 original source SHA-256 values were independently
rechecked against expected-source-sha256.tsv, every input remained non-reparse,
and all matched. The final archive is 242909 bytes, 92 files/92 hashes, SHA
`41254b9a93328917b58928ed8727a7778dd9a7f8f01afdafdcd19c05321248f5`.
Final AST parsing again passed all five workflow and five guide blocks.
`git diff --check` passed; its only messages were the existing Git autocrlf
conversion advisories, not whitespace errors.

Final source stdout/summary is preserved in
`C:/pure-lang/task8-final/pa8/Testing/Temporary/LastTest.log` and public wrapper
log `C:/pure-lang/task8-final/logs/distcheck-pure-audio.log`. The detailed child
record is under the short build's `Testing/Temporary/LastTest.log`; raw phase
logs are under the source evidence root's `logs/`. No original archive input
changed after the fresh source snapshot. Owned evidence trees are retained.

## Documentation and ownership accuracy

WINDOWS.md now contains standalone prerequisites and every explicit configure
input/runtime row, both build commands, nonempty ten-test selection, both
component installs, context-based public verifier, public distcheck and unbuilt
dist commands. It documents five DLLs/six interfaces; interleaved and
NonInterleaved boundaries; canonical frame-aligned queue; numeric sample
formats/UInt8 silence; raw-only three-byte Int24; size/shape/64-bit ABI guards;
callback consumption versus actual audibility; and close-failure quarantine.

The guide and README explicitly separate native Windows from legacy POSIX
Make/import generation. The guide's paths are portable examples, never the
checkout path that the archive leak scan is required to reject.

The package numbers remain 61 owned artifacts (runtime 22/documentation 39),
40 byte-identical baseline files, combined 101, 29 staged PEs (22 third-party
DLLs +7 project-owned), and 27 full license/notice payloads (24 third-party +3
Pure texts), plus the package's own COPYING. The 11 new audio DLLs and reused
baseline libc++/winpthreads are distinguished from the baseline's other 9
third-party DLLs. Baseline binary ownership does not transfer. System imports
are not redistributed or counted in those staged totals. Full text/provenance
coverage is not a claim about every statically incorporated/source component
or fulfillment of all distribution obligations.

## Versions and limitations

Local validation: Windows native x64; PowerShell 7.6.5; Python 3.14.5;
PyYAML 6.0.3; CMake 4.4.0; Clang/LLVM 22.1.8; Ninja 1.13.2; pkgconf 3.0.4;
GNU Make 4.4.1; GNU tar 1.35; gzip 1.14; Pure 0.68.
The local CLANG64 Python lacks PyYAML, so the available Python 3.14 interpreter
performed structural checks. CI explicitly installs its declared CLANG64
python-yaml package. No package installation was needed locally. Dependency
versions and pinned license provenance remain in THIRD_PARTY.md/origins.tsv.

No claim is made that the complete GitHub-hosted workflow ran remotely or
that its unrelated Pure/ODBC/other-package jobs were freshly rerun here. The
five actual audio step scripts were exercised locally; the pre-existing 120-min
job budget was not changed, and aggregate hosted-job duration remains unmeasured.

Hardware was not exercised. Current optional fixtures are one channel at the
selected device default rate (256 silent playback frames, 128 capture frames
in memory only, 15-second process limit). July's two-channel 44100-Hz history is
preserved without being relabeled as current fixture evidence. ASIO, FIFO/RR
elevation and every transitive codec format are not advertised. No new TSan
or ASan run is claimed for Task 8; prior tasks carry their own ASan evidence.
Native POSIX execution remains unverified. Two real file-symlink tests lack
privilege 1314 and must be reported as explicit skips, not passes.

Task 6's threat boundary is preserved: cooperating authenticated installers,
retained path identities, pre-existing hardlink rejection and owned-byte
rollback on controlled pre-commit failures. Malicious same-principal live
hardlinks/direct writes and process-crash/power-loss atomicity are excluded.

## Self-review and handoff

Self-review is complete against the Task 8 brief and approved plan/ruling:
all five actual audio scripts were run unchanged; exact 32/24 inputs and 30
prerequisites validated; distinct four-worker normal/PE commands and complete
10+deferred1 selection checked; both components/public context verifier reused;
trigger/environment/failure propagation and real semantic invocations covered
by independent mutations; guide commands executed/parsed and 32 cache values
compared; archive hashes/closure/isolation and ownership/licensing claims
checked against fresh output; July history preserved and TODO still Open.
The implementation-handoff structural suite was 7/7 PASS 45.503 s. Subsequent
independent review found two gaps; the fix-round evidence below supersedes that
handoff assessment. The limitations above are not silently certified.

Using TDD/systematic debugging produced the documented REDs before fixes;
verification-before-completion required the fresh native/archive/YAML evidence.
Per the parent's explicit no-subagent/no-integration instruction, independent
review is delegated back to the parent after this scoped commit, not represented
as already completed. The branch/worktree and pre-existing `build/` are kept.
The static guide typo `DIST_ARCHIVE` was caught against the real Make interface
before execution and corrected to `DIST_OUTPUT_DIRECTORY`; it is not counted
as a behavioral RED test. No Task 9 completion or TODO closure is claimed.

## Task 8 fix round 1 — execution context and quote semantics

Base: `a442d5fed78465bd0bbed9ee8658f199a45f68be`, 2026-09-09.
Independent review found that the semantic-validation step's shell and working
directory were not checked, and that POSIX shlex erased PowerShell's distinction
between expanding double quotes and literal single quotes. Both findings were
reproduced before production changes. The parent approved a bounded context
resolver and strict quote-aware lexer, without changing the five audio run bodies.

The actual semantic step now explicitly declares `shell: pwsh` and
`working-directory: pure`. The validator computes effective values in
workflow -> job -> step order, including Windows' default pwsh shell, and
requires the audited pwsh/pure pair. Declared defaults themselves must also
be safe: a masked custom shell still affects shared prerequisite steps.
Custom templates, alternate shells/directories and conditional/failure-ignoring
job or semantic steps are rejected. Safe workflow/job inheritance controls pass.
This follows GitHub's documented [run-default precedence](https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax#defaultsrun).

The new lexer retains each token's bare/single/double-quoted form before
normalization. Single-quoted environment references never satisfy expanding
arguments. Unsupported escapes, concatenation, subexpressions, variable forms,
smart quotes and quoted operators/logging syntax fail closed. Native argument
vectors still enforce exact tools/inputs/ordering, not textual grep. Literal
single-quoted CTest regex anchors remain valid. Microsoft documents the
[literal versus expanding quote behavior](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_quoting_rules?view=powershell-7.5).
A real native Python invocation under PowerShell independently observed
`["C:/task8-quote-control", "$env:AUDIO_PREFIX"]` for double/single quoting.
Backticks must immediately precede newline; spaces/tabs after the backtick are
not normalized into fictitious continuations. This parser deliberately does not
claim to interpret arbitrary PowerShell.

TDD evidence (all logs retained under `C:/pure-lang/`):

- `task8-fix1-red.log`: four focused methods, exit 1, 35 failures in 7.109 s:
  six accepted unsafe execution contexts, 28 accepted quote mutations and one
  wrongly rejected safe job-default inheritance control. Of the initial 50
  negative cases, 34 exposed missing checks and 16 were already rejected.
- `task8-fix1-focused-green.log`: 4/4 PASS, 19 context +31 expansion negative
  cases, three positive controls, 7.039 s.
- Self-review added nine literal audio-log argument cases and two invalid
  backtick-space/tab cases. `task8-fix1-continuation-red.log`: exit 1, exactly
  two failures in 5.639 s; the other 40 expansion cases were rejected.
- `task8-fix1-focused-final.log`: 4/4 PASS, 19+42 negatives and three controls,
  8.446 s. A uniqueness audit then identified two already-covered job conditions;
  these redundant rows were removed from the new context group, not counted twice.
- Final `task8-fix1-final-green-2.log`: **11/11 PASS, 50.790 s**, exit 0;
  **324 original audio +17 new context +42 expansion +3 ODBC =386 distinct
  negative scenarios**, two pristine variants and five positive controls.
  All 383 audio documents and labels were separately checked unique.
  Actual pristine validator CLI also passed. Exact commands:
  `C:/Python314/python.exe .github/scripts/test_validate_non_linux_release_workflow.py -v`
  and `C:/Python314/python.exe .github/scripts/validate_non_linux_release_workflow.py .github/workflows/non-linux-release-validation.yml`.

Fresh proportionate native verification used `C:/pure-lang/task8-fix1/pa8`,
with the exact first two actual workflow run strings, unchanged, from `pure/`.
Only the local concrete env paths replace hosted expressions, as in the original
Task 8 run; the declared baseline remains
`C:/pure-lang/pure/build/windows-clang64-prefix`. The absent short evidence root
and non-reparse ancestors were checked before creation. Strict configure passed
**6.2621647 s**; normal build **23/23** and PE target **29 AMD64 PE32+** both
passed with `--parallel 4` (**7.4748183 s combined**). Build seal: 74 records,
runtime 22/documentation 39/baseline 13. Logs are in
`C:/pure-lang/task8-fix1/logs/{configure,build,pe}-pure-audio.log`.
The exact no-hardware CTest inventory is still ten nonempty tests with only
source-dist deferred. `command-parser.log` confirms all five audio scripts,
the semantic script and five guide PowerShell blocks parse: **6+5, zero errors**.
The four real core tests also freshly passed **4/4, 10.47 s** (`core-tests.log`):
`C:/msys64/clang64/bin/ctest.exe --test-dir C:/pure-lang/task8-fix1/pa8 -L '^audio$' -LE '^hardware$' -R '^pure-audio-(fault-bounds|load|processing|public-bounds)$' --output-on-failure --no-tests=error --parallel 4`.
This focused diagnostic selection does not replace or alter CI's ten-test gate.

All five actual audio step objects were compared structurally against the base
commit and are unchanged. All 92 source hashes still match the original Task 8
snapshot, and its retained 242909-byte archive still hashes to
`41254b9a93328917b58928ed8727a7778dd9a7f8f01afdafdcd19c05321248f5`.
Consequently, per the parent's explicit proportional-verification ruling, the
slow outer 10/10, component/public verifier, public distcheck 1/1 and extracted
10/10 results above are **unchanged historical regression evidence, not reruns
of this fix round**. No new install or dist mutation/pristine counts are claimed.
The 61-artifact/27-license/29-PE package and source 34-negative/1-pristine/7-control
counts remain those of that identified original closure.

Versions freshly observed: PowerShell 7.6.5, Python 3.14.5/PyYAML 6.0.3,
CMake 4.4.0, Clang/LLVM 22.1.8, Ninja 1.13.2, pkgconf 3.0.4 and Pure 0.68.
The CLANG64-Python/PyYAML and hosted-workflow limitations above remain unchanged.
Self-review checked inheritance and overrides, operator and expansion semantics,
failure propagation, mutation uniqueness, unchanged audio source/interfaces and
historical/fresh evidence separation. Both reported findings are addressed;
independent parent re-review remains required. Five scoped tracked files are
changed: validator, tests, workflow metadata, TODO-33 and this report. The local
ignored progress ledger is not staged. `build/`, branch and worktree are retained;
no merge, push, Task 9 completion or TODO closure is performed.
