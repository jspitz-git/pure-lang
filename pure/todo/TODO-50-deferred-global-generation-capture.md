# TODO-50 - Deferred Global Generation Capture

Status: Open
Branch: todo/50-deferred-global-generation-capture

## Purpose

Preserve the function generation captured by a retained global closure even
when its native address is materialized only after later redefinitions. An
uncalled `let f = foo` must continue to denote the generation of `foo` that was
current at binding time, rather than silently rebinding to the newest generation
on its first invocation.

## Scope

- Reproduce and fix the extended `test052.pure` failure under LLVM 22.
- Resolve deferred global closures by their stored implementation key instead
  of unconditionally selecting the current implementation for the symbol tag.
- Preserve ORC resource ownership until every closure referring to a generation
  has been released.
- Keep direct calls to the current global definition and deliberate
  redefinition behavior unchanged.
- Do not include unrelated portable-runtime or Windows packaging changes.

## Task List

1. [x] Add a focused reproducer for deferred capture before first invocation.
   - Confirm `f1`, `f2`, and `f3` retain three distinct generations.
   - Cover out-of-order release of newer closures before invoking the oldest.
2. [ ] Implement generation lookup and materialization by closure key.
   - Reject or diagnose a missing retained generation instead of falling back
     silently to the current definition.
3. [ ] Verify generation reference counting and ORC tracker collection.
   - Exercise both never-materialized and already-materialized closures.
   - Confirm superseded generations are reclaimed after their final reference.
4. [ ] Run focused, complete, and sanitizer regression tests and close the TODO.

## Guardrails

- Do not force eager JIT compilation of every captured global merely to pin its
  generation.
- Do not leak obsolete ORC resource trackers or retain stale generations
  indefinitely.
- Preserve closure ABI fields and the public embedding ABI.
- Keep behavior identical across Windows and the supported Unix configurations.
- Do not weaken or rewrite the existing `test052.pure` expectations.

## Validation Plan

- From `build/windows-clang64-release`, run
  `./run-tests -v ../../test/test052.pure` for the native Windows LLVM 22 build.
- Run `pure-jit-lifetime-stress`, `pure-jit-eager`, and related closure tests.
- Add a focused assertion for collection after out-of-order closure release.
- Run the complete Release regression corpus on Windows and Linux.
- Run the focused lifetime tests under ASan/UBSan before closure.

## Open Questions

- Should a missing generation key be a hard internal error or a reported Pure
  runtime exception? Decide before changing the resolution failure path.
- What is the narrowest observable hook for proving that the final obsolete
  tracker was collected without exposing ORC internals as public API?

## Progress Log

- 2026-07-25: Diagnosed the extended `test052.pure` failure.
  - Windows LLVM 22 validation commit `830d00cf` passed 22/22 tests before the
    extended three-generation case entered the history.
  - Commit `64d0cc0c` added the case without executing it; merge `73b3d587`
    later introduced it into the main line.
  - The failure was reproduced on parent revision `c889330a`: `f1` and `f2`
    returned the third generation because `resolve_global_closure` selected
    `current_generation(closure->tag)` at first invocation.
  - No implementation change has been made yet.
- 2026-07-25: Added the focused `pure-jit-deferred-generation` test.
  - The no-prelude test retains three uncalled closures, invokes them only after
    the third redefinition, and releases newer closures before reusing the first.
  - Validation:
    - Windows CLANG64 Release configure and build passed.
    - The focused test produced six third-generation results instead of the
      expected per-generation sequence, reproducing the defect in 0.13 seconds.
