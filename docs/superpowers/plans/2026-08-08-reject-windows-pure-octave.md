# Reject Windows pure-octave Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove every repository code change made for TODO-43 and TODO-51, restore the pre-investigation `pure-octave` tree, and retain both TODOs and their supporting documents as clearly rejected historical records.

**Architecture:** Use commit `d90bcea60d7a5820172635c5bc2003c6a2bd078b` as the authoritative path-scoped baseline for `pure-octave/`. Restore that tree mechanically, then make only explicit Markdown disposition changes. Preserve Git history and all unrelated package work.

**Tech Stack:** Git, PowerShell 7.6.4, Markdown, ripgrep.

## Global Constraints

- Restore `pure-octave/` exactly from `d90bcea60d7a5820172635c5bc2003c6a2bd078b`.
- Treat the unstaged `pure-octave/probes/task-3-report.md` append as TODO-51 evidence and remove it with the restored tree.
- Do not modify `C:\Tools\GNU Octave`, `C:\tmp`, or any other machine-local installation or evidence tree.
- Do not rewrite Git history, reset the branch, or modify unrelated package code.
- Preserve TODO-43 and TODO-51 history; set both to `Status: Rejected on 2026-08-08`.
- Preserve related specs and plans as historical records with a prominent rejection notice.
- Preserve the baseline's seven `blank-at-eol` findings in `embed.cc` and one
  `blank-at-eof` finding in `embed.h`; use a scoped Git whitespace check that
  disables only those two classes for the exact `pure-octave/` restoration.
- Stage explicit paths only and verify every cached diff before committing.

---

### Task 1: Restore the pre-TODO-43 pure-octave source tree

**Files:**
- Restore: `pure-octave/**`
- Preserve outside repository: `C:\Tools\GNU Octave/**`, `C:\tmp/**`

**Interfaces:**
- Consumes: baseline tree `d90bcea60d7a5820172635c5bc2003c6a2bd078b:pure-octave`.
- Produces: a working and indexed `pure-octave/` tree byte-identical to that baseline.

- [ ] **Step 1: Capture the pre-removal inventory and prove the restoration gate is RED**

Run:

```powershell
git status --short
git diff --name-status d90bcea60d7a5820172635c5bc2003c6a2bd078b -- pure-octave
git diff --quiet d90bcea60d7a5820172635c5bc2003c6a2bd078b -- pure-octave
if ($LASTEXITCODE -ne 1) { throw "Expected pure-octave to differ from the restoration baseline." }
```

Expected: the only pre-existing working-tree change is
`pure-octave/probes/task-3-report.md`; the baseline comparison lists the
TODO-43/TODO-51 additions and three modified legacy files; the quiet comparison
returns `1`.

- [ ] **Step 2: Verify the exact restoration target before changing files**

Run:

```powershell
$baseline = 'd90bcea60d7a5820172635c5bc2003c6a2bd078b'
git cat-file -e "$baseline`:pure-octave/embed.cc"
git cat-file -e "$baseline`:pure-octave/embed.h"
git cat-file -e "$baseline`:pure-octave/octave.pure"
git ls-tree -r --name-only $baseline -- pure-octave
```

Expected: all three legacy files exist and the listing is the complete baseline
inventory. Save the listing in the task report; do not write it into the
repository.

- [ ] **Step 3: Restore only the approved source tree**

Run:

```powershell
git restore --source=d90bcea60d7a5820172635c5bc2003c6a2bd078b --worktree -- pure-octave
```

Expected: added TODO-43/TODO-51 files are removed, and the three legacy source
files contain their baseline versions. No path outside `pure-octave/` changes.

- [ ] **Step 4: Prove the restoration gate is GREEN**

Run:

```powershell
git diff --exit-code d90bcea60d7a5820172635c5bc2003c6a2bd078b -- pure-octave
git status --short
```

Expected: the baseline comparison exits `0`. Git status shows the intended
tracked deletions and legacy-file restorations. The design and implementation
plan remain committed, and no unrelated working-tree path is present.

- [ ] **Step 5: Stage and review only the restored source tree**

Run:

```powershell
git add -- pure-octave
git -c core.whitespace=-blank-at-eol,-blank-at-eof diff --cached --check -- pure-octave
git diff --cached --name-status
git diff --cached --stat
```

Expected: the cached diff contains only `pure-octave/**`, with added Windows
files deleted and `embed.cc`, `embed.h`, and `octave.pure` restored. The scoped
whitespace check exits `0`; the exception covers only the baseline's seven
`blank-at-eol` and one `blank-at-eof` findings.

- [ ] **Step 6: Commit the source removal**

Run:

```powershell
git commit -m "Remove Windows pure-octave implementation"
```

Expected: one commit containing only the approved `pure-octave/` restoration.

---

### Task 2: Reject both TODOs and retire their historical plans

**Files:**
- Modify: `pure/todo/TODO-43-windows-pure-octave.md`
- Modify: `pure/todo/TODO-51-windows-strict-write-confinement.md`
- Modify: `docs/superpowers/specs/2026-07-29-windows-pure-octave-design.md`
- Modify: `docs/superpowers/plans/2026-07-29-windows-pure-octave.md`
- Modify: `docs/superpowers/specs/2026-07-31-todo51-pure-rsvg-supplement-design.md`
- Modify: `docs/superpowers/plans/2026-07-31-todo51-pure-rsvg-supplement.md`
- Modify: `docs/superpowers/specs/2026-08-01-todo51-gnuplot-loader-domain-design.md`
- Modify: `docs/superpowers/plans/2026-08-01-todo51-gnuplot-loader-domain.md`
- Modify: `docs/superpowers/specs/2026-08-01-todo51-windows-api-set-repin-design.md`
- Modify: `docs/superpowers/plans/2026-08-01-todo51-windows-api-set-repin.md`
- Modify: `docs/superpowers/specs/2026-08-03-todo51-v15-assembler-diagnostics-design.md`
- Modify: `docs/superpowers/plans/2026-08-03-todo51-v15-assembler-diagnostics.md`
- Modify: `docs/superpowers/specs/2026-08-03-todo51-v16-gnuplot-platform-plugin-design.md`
- Modify: `docs/superpowers/plans/2026-08-03-todo51-v16-gnuplot-platform-plugin.md`
- Modify: `docs/superpowers/specs/2026-08-08-todo51-v17-process-owner-design.md`
- Modify: `docs/superpowers/plans/2026-08-08-todo51-v17-verified-process-owner.md`

**Interfaces:**
- Consumes: the approved rejection design and the completed source restoration.
- Produces: two rejected TODO records and fourteen unmistakably historical supporting documents.

- [ ] **Step 1: Add the exact TODO disposition**

In both TODO files, replace the status line with:

```markdown
Status: Rejected on 2026-08-08
```

Append this entry to each `## Progress Log` without rewriting earlier evidence:

```markdown
- 2026-08-08: Rejected by product decision.
  - The Windows `pure-octave` implementation and its strict-write-confinement
    follow-up were removed from the repository.
  - Historical investigation evidence remains in Git and in the rejected
    design and plan documents; resumption requires a new approved TODO.
```

- [ ] **Step 2: Add the exact historical notice to every supporting document**

Immediately after the first Markdown heading in each of the fourteen listed
specs and plans, insert:

```markdown
> **Rejected on 2026-08-08.** Historical record only. Do not implement or
> resume this work without a new approved TODO.
```

Do not otherwise rewrite their historical contents.

- [ ] **Step 3: Verify disposition cardinality and formatting**

Run:

```powershell
rg -n "^Status: Rejected on 2026-08-08$" pure/todo/TODO-43-windows-pure-octave.md pure/todo/TODO-51-windows-strict-write-confinement.md
$historicalDocs = @(
  'docs/superpowers/specs/2026-07-29-windows-pure-octave-design.md',
  'docs/superpowers/plans/2026-07-29-windows-pure-octave.md',
  'docs/superpowers/specs/2026-07-31-todo51-pure-rsvg-supplement-design.md',
  'docs/superpowers/plans/2026-07-31-todo51-pure-rsvg-supplement.md',
  'docs/superpowers/specs/2026-08-01-todo51-gnuplot-loader-domain-design.md',
  'docs/superpowers/plans/2026-08-01-todo51-gnuplot-loader-domain.md',
  'docs/superpowers/specs/2026-08-01-todo51-windows-api-set-repin-design.md',
  'docs/superpowers/plans/2026-08-01-todo51-windows-api-set-repin.md',
  'docs/superpowers/specs/2026-08-03-todo51-v15-assembler-diagnostics-design.md',
  'docs/superpowers/plans/2026-08-03-todo51-v15-assembler-diagnostics.md',
  'docs/superpowers/specs/2026-08-03-todo51-v16-gnuplot-platform-plugin-design.md',
  'docs/superpowers/plans/2026-08-03-todo51-v16-gnuplot-platform-plugin.md',
  'docs/superpowers/specs/2026-08-08-todo51-v17-process-owner-design.md',
  'docs/superpowers/plans/2026-08-08-todo51-v17-verified-process-owner.md'
)
foreach ($document in $historicalDocs) {
  if (@(Select-String -LiteralPath $document -Pattern '^> \*\*Rejected on 2026-08-08\.\*\* Historical record only\. Do not implement or$').Count -ne 1) {
    throw "Historical notice mismatch: $document"
  }
}
git diff --check
```

Expected: two TODO status matches, exactly fourteen historical-document matches
from this task, and no whitespace errors.

- [ ] **Step 4: Stage and review only the disposition documents**

Run:

```powershell
git add -- `
  pure/todo/TODO-43-windows-pure-octave.md `
  pure/todo/TODO-51-windows-strict-write-confinement.md `
  docs/superpowers/specs/2026-07-29-windows-pure-octave-design.md `
  docs/superpowers/plans/2026-07-29-windows-pure-octave.md `
  docs/superpowers/specs/2026-07-31-todo51-pure-rsvg-supplement-design.md `
  docs/superpowers/plans/2026-07-31-todo51-pure-rsvg-supplement.md `
  docs/superpowers/specs/2026-08-01-todo51-gnuplot-loader-domain-design.md `
  docs/superpowers/plans/2026-08-01-todo51-gnuplot-loader-domain.md `
  docs/superpowers/specs/2026-08-01-todo51-windows-api-set-repin-design.md `
  docs/superpowers/plans/2026-08-01-todo51-windows-api-set-repin.md `
  docs/superpowers/specs/2026-08-03-todo51-v15-assembler-diagnostics-design.md `
  docs/superpowers/plans/2026-08-03-todo51-v15-assembler-diagnostics.md `
  docs/superpowers/specs/2026-08-03-todo51-v16-gnuplot-platform-plugin-design.md `
  docs/superpowers/plans/2026-08-03-todo51-v16-gnuplot-platform-plugin.md `
  docs/superpowers/specs/2026-08-08-todo51-v17-process-owner-design.md `
  docs/superpowers/plans/2026-08-08-todo51-v17-verified-process-owner.md
git diff --cached --check
git diff --cached --name-status
git diff --cached --stat
```

Expected: only the two TODOs and fourteen historical documents are staged. No
source, workflow, installer, implementation-plan, or unrelated TODO path is
present.

- [ ] **Step 5: Commit the rejected disposition**

Run:

```powershell
git commit -m "Reject Windows pure-octave TODOs"
```

Expected: one documentation-only commit.

---

### Task 3: Audit the complete removal

**Files:**
- Read: complete repository tree
- Modify only if found: a live non-Markdown reference introduced solely by TODO-43 or TODO-51

**Interfaces:**
- Consumes: Tasks 1 and 2 commits.
- Produces: fresh evidence that no active repository implementation remains.

- [ ] **Step 1: Prove the restored source tree remains exact**

Run:

```powershell
git diff --exit-code d90bcea60d7a5820172635c5bc2003c6a2bd078b HEAD -- pure-octave
```

Expected: exit `0` and no output.

- [ ] **Step 2: Search for live implementation references**

Run:

```powershell
rg -n --hidden --glob '!.git/**' --glob '!*.md' --glob '!docs/superpowers/**' `
  "TODO-43|TODO-51|windows-pure-octave|stage_task3_runtime|invoke_task3_process_owner|PURE_OCTAVE_ABI" .
```

Expected: no matches. If a match exists, classify it against the baseline. Remove
it only when it was introduced solely for TODO-43/TODO-51, then repeat Tasks 3
Steps 1 and 2.

- [ ] **Step 3: Verify TODO and historical-document state**

Run:

```powershell
$todos = @(
  'pure/todo/TODO-43-windows-pure-octave.md',
  'pure/todo/TODO-51-windows-strict-write-confinement.md'
)
foreach ($todo in $todos) {
  if (@(Select-String -LiteralPath $todo -Pattern '^Status: Rejected on 2026-08-08$').Count -ne 1) {
    throw "Rejected status mismatch: $todo"
  }
}
$historicalDocs = @(
  'docs/superpowers/specs/2026-07-29-windows-pure-octave-design.md',
  'docs/superpowers/plans/2026-07-29-windows-pure-octave.md',
  'docs/superpowers/specs/2026-07-31-todo51-pure-rsvg-supplement-design.md',
  'docs/superpowers/plans/2026-07-31-todo51-pure-rsvg-supplement.md',
  'docs/superpowers/specs/2026-08-01-todo51-gnuplot-loader-domain-design.md',
  'docs/superpowers/plans/2026-08-01-todo51-gnuplot-loader-domain.md',
  'docs/superpowers/specs/2026-08-01-todo51-windows-api-set-repin-design.md',
  'docs/superpowers/plans/2026-08-01-todo51-windows-api-set-repin.md',
  'docs/superpowers/specs/2026-08-03-todo51-v15-assembler-diagnostics-design.md',
  'docs/superpowers/plans/2026-08-03-todo51-v15-assembler-diagnostics.md',
  'docs/superpowers/specs/2026-08-03-todo51-v16-gnuplot-platform-plugin-design.md',
  'docs/superpowers/plans/2026-08-03-todo51-v16-gnuplot-platform-plugin.md',
  'docs/superpowers/specs/2026-08-08-todo51-v17-process-owner-design.md',
  'docs/superpowers/plans/2026-08-08-todo51-v17-verified-process-owner.md'
)
foreach ($document in $historicalDocs) {
  if (@(Select-String -LiteralPath $document -Pattern '^> \*\*Rejected on 2026-08-08\.\*\* Historical record only\. Do not implement or$').Count -ne 1) {
    throw "Historical notice mismatch: $document"
  }
}
```

Expected: both TODO checks pass and the supporting-document count is `14`.

- [ ] **Step 4: Run final repository gates**

Run:

```powershell
git diff --check HEAD^
git -c core.whitespace=-blank-at-eol,-blank-at-eof diff --check 7a2be4d075df671a3c334bc8ec898cabb9a498f3 HEAD -- pure-octave
git status --short
git log -4 --oneline
```

Expected: no new documentation whitespace errors; the scoped source check
passes while preserving the eight baseline findings; no unstaged or staged
changes; the latest commits include the rejected disposition, source removal,
and the documented baseline-whitespace decision.

- [ ] **Step 5: Review requirements line by line**

Confirm from fresh command output:

```text
[ ] pure-octave equals the pre-TODO-43 baseline
[ ] TODO-43 is rejected
[ ] TODO-51 is rejected
[ ] fourteen related specs/plans are historical and rejected
[ ] no live non-Markdown implementation reference remains
[ ] C:\Tools and C:\tmp were not modified
[ ] Git history was preserved
[ ] worktree and index are clean
```

Expected: all eight items are supported by recorded evidence before reporting
completion.
