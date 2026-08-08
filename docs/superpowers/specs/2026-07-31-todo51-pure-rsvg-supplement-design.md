# TODO-51 Pure SVG Runtime Supplement Design

> **Rejected on 2026-08-08.** Historical record only. Do not implement or
> resume this work without a new approved TODO.

## Context

The hardened Task 3 staging audit reached the complete Pure runtime closure in
production stage v10 and failed closed on
`pure/lib/gdk-pixbuf-2.0/2.10.0/loaders/pixbufloader_svg.dll`.  The module
imports `librsvg-2-2.dll`, which is absent from the accepted relocated Pure
tree.  Read-only closure analysis of the matching MSYS2 clang64 runtime found
that the minimal missing closure is exactly three DLLs:

| File | Bytes | SHA-256 |
| --- | ---: | --- |
| `librsvg-2-2.dll` | 5,882,880 | `9F90DE3779E80F590B542AFDF79C105A403B0C566265D69EACBBF9B524338F89` |
| `libunwind.dll` | 63,488 | `60FA3C200899BC6E4A5876B82E2C656FF72FC53EC55979D99CB7C4EF640A6D96` |
| `libxml2-16.dll` | 1,294,848 | `C6C34A810D86C19C034A1BC96C4C500BDE8FB789DED69B434E67EEE773605852` |

All other direct and transitive non-system dependencies of these DLLs already
exist in the Pure loader directory and are byte-identical to their current
MSYS2 clang64 counterparts.  The approved design is to add this minimal
closure as an independently verified supplement.  The Pure source tree and
permanent Octave installation remain immutable.

## Architecture

The implementation creates one disposable source snapshot at the exact root
`C:\tmp\todo51-task3\pure-rsvg-supplement-v1`.  It contains only
`bin/<the three DLLs>` and repo-produced evidence outside the effective loader
directory.  A repo-owned TSV contract pins each relative path, byte length,
SHA-256, PE machine, direct imports, and the resolved transitive closure.

The staging assembler receives the supplement as a distinct provenance root.
In production mode it accepts only the exact contract and snapshot identity;
callers cannot replace the root, files, hashes, or closure through overrides.
The three DLLs are copied into `stage/pure/bin`, never into Octave's
`stage/mingw64/bin`.  Any destination collision, reparse point, extra or
missing supplement file, changed hash, ABI mismatch, unresolved import, or
Pure/Octave bridge-union ambiguity fails before runtime execution.

The resulting loader domains remain:

- Pure PE files: `stage/pure/bin` plus Windows system resolution;
- Octave PE files: `stage/mingw64/bin` plus Windows system resolution;
- bridge PE files: the explicitly audited union of those two domains;
- Windows API-set imports: authoritative local OS mappings, with every loaded
  verification handle released.

No global `PATH`, installed runtime, source-tree ACL, or permanent file is
modified.

## Evidence and postconditions

Before creating a new real stage, a report-only planning checkpoint will:

1. copy the three files once from `C:\msys64\clang64\bin` into a previously
   absent, regular, non-reparse supplement root;
2. verify the source files and snapshot before and after copying against the
   fixed table above;
3. prove that the closure adds no fourth DLL and that every reused Pure DLL is
   byte-identical to the matching clang64 DLL;
4. derive the new deterministic stage count, byte total, PE count, import
   closure, and manifest SHA from the accepted v5 manifest plus the three
   fixed rows using the repo-owned manifest serialization;
5. commit those exact production postconditions and receive independent
   review before any new stage Apply.

The expected arithmetic before manifest serialization is fixed: the
supplement adds exactly three files and 7,241,216 bytes.  Therefore the new
stage must contain exactly 64,312 files and 3,334,971,045 bytes.  It must
audit exactly 1,539 magic-byte PE files, including the unchanged 219 `.oct`
modules, plus the one separately pinned inert Qt documentation placeholder.
The exact new manifest SHA is generated and reviewed in the report-only
checkpoint; production Apply remains disabled until that value is hard-bound
in the assembler and tests.

## Failure handling and cleanup

Every snapshot and stage target must be absent before its sole creation.  A
failed attempt is preserved as evidence and is never recycled.  No staged
binary is executed during snapshot construction or static audit.  The final
Task 3 cleanup removes all disposable supplement, stage, build, wrapper, and
profile artifacts only after runtime verification has completed and their
exact paths have been revalidated.

## Test design

TDD coverage must first fail on the current missing `librsvg-2-2.dll`, then
prove:

- the exact three-file supplement succeeds and is recorded separately;
- missing, extra, renamed, changed, non-PE, wrong-machine, reparse, or
  caller-substituted supplement content fails closed;
- a destination collision fails even when the filename matches;
- a fourth unresolved transitive dependency fails;
- reused Pure dependencies must match the clang64 source bytes;
- all supplement imports resolve only in the Pure loader domain or through
  authoritative Windows system resolution;
- final count, bytes, manifest SHA, PE cardinality, `.oct` cardinality, and
  inert-placeholder cardinality are exact production postconditions;
- the existing staging regression suite remains green.

After the reviewed static stage succeeds, the existing Task 3 plan resumes
with the strict AppContainer runner, legacy RED/strict GREEN write tests,
direct canonicalization regression, public embed probe, and basic bridge test.
