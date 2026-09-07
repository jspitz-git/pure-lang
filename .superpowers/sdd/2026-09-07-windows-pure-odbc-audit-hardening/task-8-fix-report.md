# Task 8 consolidated fix report

Date: 2026-09-08

## Confirmed root causes

1. `odbc_info` had a second, unsafe SQLGetInfo implementation. It accepted
   truncation as success and passed a fixed, uninitialized 1024-byte array to
   `pure_cstring_dup`, bypassing the audited dynamic loader used by
   `odbc_getinfo`.
2. The text SQLGetData loop treated every `SQL_SUCCESS_WITH_INFO` as
   truncation. A complete short result was therefore appended repeatedly, an
   invalid negative indicator was converted into chunk arithmetic, and a
   driver returning repeated warnings could grow the buffer without a bound.
   The former later-`SQL_NO_DATA` assertion did not actually require a
   truncating first call, so it did not test the claimed continuation path.
3. When only one output reader thread was created, cleanup terminated the
   child and immediately closed that thread and its pipe. The thread could
   still be executing `ReadFile` against the closed handle and stack-owned
   capture state.

## RED evidence

The new public-path SQLGetInfo test executed `odbc_info` with a 2048-byte
value against the unchanged implementation. ASan stopped at the actual defect:

```text
ERROR: AddressSanitizer: stack-buffer-overflow
WRITE of size 1 in fake_SQLGetInfo
... fake_SQLGetInfo -> odbc_info -> run_public_info_case
info [160, 1184) ... Memory access at offset 1184 overflows this variable
```

The text SQLGetData regressions then reported the expected behavioral RED:

```text
FAIL: short text warning returns a complete value
FAIL: text SQLGetData value is exact
FAIL: text SQLGetData warning continuation is bounded
```

The negative-indicator and repeated-warning cases also exceeded their call
bounds. The dedicated truncation-then-`SQL_NO_DATA` fixture uses
`SQL_NO_TOTAL` and a full initialized chunk, replacing the prior short-warning
case that could not reach a legitimate continuation after the fix.

The runner contract was authored to require a controlled failure of the second
`CreateThread`, a non-terminating child, a ten-second outer timeout, and an
event trace proving termination/close/wait/handle ordering. The test-only seam
and trace do not exist in non-`PURE_ODBC_TEST_SEAM` builds; without the cleanup
change the first reader is not waited before its handle and pipe are closed.

## Implementation

- Added one allocation-only `odbc_load_info_text` routine shared by
  `odbc_info` and `odbc_getinfo`. It validates negative lengths,
  `SQL_NO_TOTAL`, retry results and retry lengths, adds its own terminator, and
  distinguishes ODBC failure from allocation failure. `odbc_info` preserves
  its legacy empty-string fallback for ODBC failures, but aborts cleanly on
  allocation failure after releasing every already-created Pure value.
- The text SQLGetData branch now accepts a short known-length warning as a
  complete value in one call, rejects unsupported negative indicators, writes
  a terminator only at a validated in-buffer offset, and permits at most 16
  consecutive truncation warnings (17 calls including the rejected warning).
  A real full-chunk continuation followed by `SQL_NO_DATA` retains exactly the
  initialized bytes.
- The test launcher creates the readers before releasing the parent's pipe
  write ends. On any partial failure it terminates the child, closes both write
  ends, waits for the child and every reader that was actually created, and
  only then closes thread/read handles and returns. The controlled thread
  failure, cleanup event marker, and hanging fake child compile only into the
  existing test-support seam/fixtures and do not alter the module ABI or
  installed package.

## GREEN evidence

ASan fault harness after the final test wording/fidelity correction:

```text
1/1 Test #5: pure-odbc-fault ... Passed 23.55 sec
100% tests passed out of 1
```

The direct harness included all new long/negative/`SQL_NO_TOTAL`/retry/
unterminated/allocation public-info cases and all new short/negative/
continuation/repeated-warning text-data cases, ending:

```text
SUMMARY: 0 failure(s), 0 net allocation(s)
```

Runner contract with the second thread creation forced to fail while the child
was intentionally non-terminating:

```text
pure-odbc-runner-contract ... Passed 77.07 sec
-- pure-odbc runner and root-safety contracts passed
```

Exact cleanup trace:

```text
terminate-process close-write-ends wait-process wait-stdout-thread
close-stdout-thread close-stdout-read close-stderr-read
```

Relevant strict Release verification:

```text
strict task7 build: 9 build steps completed, including odbc.dll and both runners
pure-odbc-manager-smoke ... Passed 6.17 sec
pure-odbc-access-text-smoke ... Passed 4.53 sec
pure-odbc-cleanup-contract ... Passed 6.12 sec
git diff --check: no errors
```

## Files changed

- `pure-odbc/odbc.c`
- `pure-odbc/tests/odbc_fault_harness.c`
- `pure-odbc/tests/run_pure_test.c`
- `pure-odbc/tests/runner_contract.cmake`

## Residual risks

- Windows ASan still reports that LeakSanitizer itself is unsupported. The
  harness therefore retains explicit Pure teardown and native allocation
  accounting; the final result is zero net tracked allocations.
- The 16-warning text continuation budget is deliberately fail-closed. A
  nonconforming driver that requires more than 16 consecutive truncating
  chunks for one value returns an ODBC error instead of growing indefinitely.
- No network, credentials, DSN, external database server, package installation,
  or third-party driver was used. The locally installed optional Access Text
  Driver was exercised by its existing smoke test.
