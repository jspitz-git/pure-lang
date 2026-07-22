# Docs Agent Guide

This file defines the required structure for new TODO documents in `docs/`.
Preserve older TODO files as history, but use this convention for new work and
for substantial rewrites of active TODOs.

## New TODO Structure

New TODO files should use this shape:

```markdown
# TODO-NN - Short Title

Status: Open
Branch: todo/NN-short-kebab-title

## Purpose

One or two short paragraphs describing the problem, why it matters, and what
success should look like.

## Scope

- What is in scope.
- What is explicitly out of scope.
- Known constraints, risks, or compatibility promises.

## Task List

1. [ ] First coherent milestone.
   - Optional notes or acceptance details.
2. [ ] Second coherent milestone.
3. [ ] Validation and closure.

## Guardrails

- Rules that should not be broken while doing the work.
- Performance, stability, compatibility, corpus, or API constraints.

## Validation Plan

- Narrow targeted checks to run after each small step.
- Broader checks to run after related batches.
- Final closure checks, including `Pkg.test()` when relevant.

## Open Questions

- Questions that genuinely affect the implementation direction.
- Remove or resolve this section when it is no longer useful.

## Progress Log

- YYYY-MM-DD: What changed.
  - Validation:
    - `exact command` passed/failed with relevant counts or caveats.
```

## Required Conventions

- Use `TODO-NN-short-kebab-title.md` for new numbered TODO files.
- Keep the title human-readable: `# TODO-NN - Short Title`.
- Put `Status: Open`, `Status: Paused`, or `Status: Closed on YYYY-MM-DD`
  directly below the title.
- Put `Branch: todo/NN-short-kebab-title` directly below the status line. Keep
  it as a historical record after integration or closure.
- Use checkbox task lists for the main milestones. Mark items complete only when
  the code/docs and validation for that milestone are done.
- Keep task items coherent rather than microscopic. Sub-bullets may describe
  details, but the main checklist should show the shape of the work.
- Record exact validation commands and outcomes in the progress log.
- Keep historical command output concise. Summarize important counts, timings,
  warnings, failures, and caveats instead of pasting huge logs.
- Preserve old TODO history. Do not rewrite old progress logs just to match the
  new format unless the TODO is active and the rewrite clarifies current work.
- Commit after each completed, coherent TODO update.

## TODO Branch Workflow

- Every new numbered TODO must use its own local Git branch. Create the branch
  from the current local `master` before the first TODO-specific commit.
- Name the branch `todo/NN-short-kebab-title`, matching the TODO number and
  filename. For example, `docs/TODO-101-basis-audit.md` uses
  `todo/101-basis-audit`.
- Start only from a clean working tree. Before creating or switching branches,
  run `git status --short --branch` and preserve unrelated user changes.
- Keep the initial TODO document, implementation, tests, progress-log updates,
  and closure commit on the TODO branch. Do not develop a numbered TODO directly
  on `master`.
- Use one numbered TODO per branch. If work is split into a follow-up TODO,
  create a new branch for that follow-up from its intended integration base.
- A paused TODO keeps its branch. Record the branch tip, current blocker, last
  validation, and next safe action in the TODO before switching away.
- Integrate only after the TODO checklist and closure requirements are complete
  and the user has approved local integration. Prefer a history-preserving
  fast-forward:

  ```text
  git switch master
  git merge --ff-only todo/NN-short-kebab-title
  ```

- If `master` moved and `--ff-only` is not possible, reconcile the divergence on
  the TODO branch, rerun affected validation, and request approval for the final
  integration shape. Do not force-move or rewrite `master` to make integration
  pass.
- After successful integration, keep or delete the TODO branch according to the
  user's retention preference. Branch deletion must not be treated as TODO
  completion; the closed TODO document and integrated commits are the durable
  record.

## Closing A TODO

Before marking a TODO closed:

- All main checklist items should be checked or explicitly moved to a new TODO.
- The final validation commands should be listed in the progress log.
- Any remaining caveats should be documented under `Open Questions`, a closing
  note, or a follow-up TODO.
- The status line should be changed to `Status: Closed on YYYY-MM-DD`.
