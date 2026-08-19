# PureBonjour on Windows

PureBonjour supports x86-64 Windows 10 and later in the MSYS2 CLANG64 Pure
distribution. The public `bonjour.pure` API is unchanged: applications use
`publish`, `check`, `browse`, `avail`, and `get`, and garbage collection closes
the associated native registration or browser object.

## Native backend and network scope

The Windows module calls Microsoft's DNS Service Discovery API in the system
`dnsapi.dll` and links the Windows socket API in `ws2_32.dll`. Installing
Apple's Bonjour for Windows is unnecessary. The component neither consumes nor
ships an Apple header, SDK, service, executable, import library, or DLL.

DNS-SD publication and discovery use the `.local` multicast link. Records do
not leave the local link, but local firewall rules, disabled multicast, network
isolation, or organization policy can prevent registration or discovery. The
bounded integration test temporarily publishes one unique record and removes
it on every completed path; it does not contact a public service.

## Build and install

Install the CLANG64 C compiler, LLVM tools, CMake, Ninja, pkgconf, and the
dependencies needed to build Pure. First build and install Pure into a complete
staging prefix. Then run these commands from the repository root in PowerShell,
replacing the Pure prefix with its absolute path:

```powershell
$savedPath = $env:Path
try {
  $env:Path = "C:/msys64/clang64/bin;C:/msys64/usr/bin;$savedPath"
  $env:PKG_CONFIG_PATH = 'C:/path with spaces/Pure/lib/pkgconfig'
  C:/msys64/clang64/bin/cmake.exe -S pure-bonjour `
    -B 'build/PureBonjour release' -G Ninja `
    -DCMAKE_BUILD_TYPE=Release `
    -DCMAKE_MAKE_PROGRAM=C:/msys64/clang64/bin/ninja.exe `
    -DCMAKE_C_COMPILER=C:/msys64/clang64/bin/clang.exe `
    -DPKG_CONFIG_EXECUTABLE=C:/msys64/clang64/bin/pkgconf.exe `
    '-DPURE_PREFIX=C:/path with spaces/Pure'
  C:/msys64/clang64/bin/cmake.exe --build 'build/PureBonjour release'
} finally {
  # Do not carry the build toolchain into tests or installed verification.
  $env:Path = $savedPath
}
C:/msys64/clang64/bin/cmake.exe --install 'build/PureBonjour release' `
  --prefix 'C:/path with spaces/PureBonjour stage' `
  --component PureBonjour
```

`PureBonjour` is optional and excluded from a default install. A component-only
install owns exactly these eight paths beneath its prefix:

```text
lib/pure/bonjour.dll
lib/pure/bonjour.pure
share/doc/pure-bonjour/COPYING
share/doc/pure-bonjour/COPYING.LESSER
share/doc/pure-bonjour/PureBonjourInventory.tsv
share/doc/pure-bonjour/README
share/doc/pure-bonjour/WINDOWS.md
share/doc/pure-bonjour/examples/bonjour_examp.pure
```

It installs no test executable, SDK header, import or static library, external
service, or dependency DLL. `PureBonjourInventory.tsv` describes the seven
payload files. The build-owned `PureBonjourExpected.sha256`, which is not
installed, authenticates all eight paths and is the only removal authority.

## Tests and installed verification

Run the complete labeled suite and the build-tree dependency audit with:

```powershell
C:/msys64/clang64/bin/ctest.exe `
  --test-dir 'build/PureBonjour release' `
  -L bonjour --output-on-failure --no-tests=error
C:/msys64/clang64/bin/cmake.exe --build 'build/PureBonjour release' `
  --target verify-windows-dependencies
```

The `finally` block above restores the caller's original `PATH` before any
runtime command. To verify a component-only stage independently, unset
`PURELIB`, replace `PATH` with the staged Pure runtime plus Windows system
directories only, and call the installed-package verifier by absolute path. It
requires absolute source, build, stage, and complete Pure prefixes:

```powershell
Remove-Item Env:PURELIB -ErrorAction SilentlyContinue
$env:Path = 'C:/path with spaces/Pure/bin;' +
  "$env:SystemRoot/System32/WindowsPowerShell/v1.0;" +
  "$env:SystemRoot/System32;$env:SystemRoot"
C:/msys64/clang64/bin/cmake.exe `
  '-DSTAGE_PREFIX=C:/path with spaces/PureBonjour stage' `
  '-DSOURCE_PREFIX=C:/checkout/pure-bonjour' `
  '-DBUILD_PREFIX=C:/checkout/build/PureBonjour release' `
  '-DPURE_PREFIX=C:/path with spaces/Pure' `
  -P C:/checkout/pure-bonjour/cmake/VerifyInstalledPackage.cmake
```

The verifier checks the exact ownership set, byte sizes and hashes, prefix
leaks, the recursive PE dependency closure, the seven native exports, and a
real installed publish/browse/resolve/removal smoke test. The validated closure
is 11 PE files and 126 import edges; only the staged Pure runtime and allowlisted
Windows system libraries are accepted.

## Diagnostics

- A null result from `publish` or `browse`, or a negative value from `check`,
  `avail`, or `get`, means input validation or a Microsoft DNS-SD API operation
  failed. Check Windows version, firewall event logs, multicast policy, and the
  adapter's network profile.
- A successful browse with no entries is not an API failure. It means no
  matching service was resolved during that bounded observation window, which
  may be normal or may indicate local-link filtering.
- Cancellation is normal during garbage collection and test cleanup. A bounded
  cancellation or callback-quiescence failure is reported to standard error;
  the backend retains callback-visible state instead of freeing it unsafely.
- Microsoft's registration and resolve cancellation APIs provide no documented
  callback-drain barrier. Consequently cleanup releases callback-owned result
  instances and registration payloads, but conservatively retains small
  lock/event/API callback contexts and resolver/browser tombstones until process
  exit. Retention is proportional to accepted registrations and resolve
  queries, and therefore is intentionally not bounded across process lifetime;
  it prevents late callbacks from dereferencing freed memory. Applications that
  repeatedly create and destroy registrations or browsers should reuse them
  where practical.
- The smoke test has explicit port-probe, Pure child, and outer time budgets. A
  timeout points to local API, firewall, or multicast behavior rather than an
  absent third-party daemon.

## Relocation and removal

The package verifier accepts a copied installation only after checking it at
the relocated prefix and repeating the sanitized smoke test. Pure 0.68 passes
script paths through the active narrow Windows code page, so Unicode relocation
uses scoped ASCII directory-junction aliases to the already audited stage and
runtime. Each alias target is verified before use and every alias is explicitly
removed afterward; aliases are never packaged.

Removal parses only the external build oracle, completes a no-follow safety
preflight, revalidates every parent immediately before deleting each exact
owned file, and removes only empty PureBonjour-specific directories. It does
not trust the installed inventory and preserves unrelated files in a shared
Pure prefix.

## Source and license boundary

The Windows implementation is maintained in `bonjour_windows.c`; the original
`bonjour.c` remains the non-Windows `dns_sd` backend. The language declarations
are in `bonjour.pure`, and the bounded real scenario is in `tests/smoke.pure`.
See `README` for API documentation and `COPYING` plus `COPYING.LESSER` for the
GNU GPL/LGPL notices that accompany the source and installed component.

Microsoft's DNS-SD functions and `dnsapi.dll` are Windows system interfaces.
No Apple binary license applies to the component because no Apple binary or
source is copied, linked, installed, or redistributed.
