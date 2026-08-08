# Reject Windows pure-octave Design

Status: Approved
Date: 2026-08-08
Affected TODOs: `pure/todo/TODO-43-windows-pure-octave.md`, `pure/todo/TODO-51-windows-strict-write-confinement.md`
Restoration baseline: `d90bcea60d7a5820172635c5bc2003c6a2bd078b`

## Goal

Remove all repository code created for the Windows `pure-octave` investigation
and its strict-write-confinement follow-up, while retaining the pre-existing
portable `pure-octave` sources and an explicit historical record that both
TODOs were rejected.

## Scope

- Restore the complete `pure-octave/` tree to its exact state at the restoration
  baseline. This restores the original `embed.cc`, `embed.h`, and `octave.pure`
  and removes all files added later for TODO-43 or TODO-51.
- Preserve `pure/todo/TODO-43-windows-pure-octave.md` and
  `pure/todo/TODO-51-windows-strict-write-confinement.md`, set both statuses to
  `Rejected on 2026-08-08`, leave their historical progress logs intact, and
  append a concise rejection decision.
- Preserve the related files under `docs/superpowers/specs/` and
  `docs/superpowers/plans/` as historical evidence. Add a prominent status note
  stating that the work was rejected and must not be resumed without a new
  approved TODO.
- Remove any repository workflow or integration code introduced solely for
  TODO-43 or TODO-51 if the baseline comparison identifies such a path.

## Exclusions

- Do not modify pre-existing `pure-octave` code from the restoration baseline.
- Do not delete the machine-local Octave installation under `C:\Tools`.
- Do not delete temporary or preserved evidence below `C:\tmp`; these paths are
  outside the repository and may be cleaned separately only by explicit user
  request.
- Do not rewrite or erase Git history. The removal is represented by new,
  auditable commits on the current branch.
- Do not change code or TODOs for unrelated Windows packages.

## Implementation

1. Record the current path inventory and exact baseline comparison.
2. Restore `pure-octave/` from the restoration baseline as a single scoped tree
   operation, preserving no later TODO-43/TODO-51 repository code.
3. Mark TODO-43 and TODO-51 rejected and append the decision rationale.
4. Mark their design and implementation-plan documents historical and rejected.
5. Search the repository for live build, workflow, packaging, or test references
   to the removed Windows implementation and remove only references introduced
   by TODO-43/TODO-51.

## Safety and Error Handling

- Refuse to proceed if a changed `pure-octave/` path cannot be classified
  against the restoration baseline.
- Treat the currently modified `pure-octave/probes/task-3-report.md` as part of
  TODO-51 and remove it with the restored tree; do not overwrite unrelated
  working-tree changes.
- Review the complete diff before staging. Stage explicit paths only.
- Do not use history-rewriting commands or broad destructive filesystem
  commands.

## Verification

- `git diff --exit-code d90bcea60d7a5820172635c5bc2003c6a2bd078b -- pure-octave`
  must report no difference.
- `git diff --check` must pass.
- Both TODO files must contain `Status: Rejected on 2026-08-08` and an explicit
  rejection entry.
- Every related spec and plan must carry the historical/rejected notice.
- A repository search must find no live code, build, CI, packaging, or test
  reference to the removed Windows `pure-octave` implementation outside the
  deliberately retained historical documents and rejected TODOs.
- The staged diff must contain only the approved restoration, TODO disposition,
  and historical-document status changes.

## Acceptance

The change is accepted when the repository contains only the pre-TODO-43
`pure-octave` implementation, TODO-43 and TODO-51 are visibly rejected, the
historical documents cannot be mistaken for active plans, and all scoped
verification gates pass.
