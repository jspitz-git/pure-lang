# Windows build and runtime notes

The supported Windows build uses MSYS2 CLANG64 only as a build environment.
It downloads the official liblo 0.36 source archive, verifies SHA-256
`c08d14832e8dcf8f06840405824a4f9611a0cb3daed0198946326c740941c8b6`,
and builds a shared `liblo.dll` with native Winsock and threading support.

The Pure wrapper is built as `lo.dll`. Its only package-specific runtime
delta is `liblo.dll`. It reuses the bundle's `libpure.dll` and
`libgmp-10.dll`; Windows networking, IP Helper, UCRT, and other system DLLs
are never copied. Neither binary imports an MSYS, GCC, or C++ runtime.

All automated OSC traffic is restricted to IPv4 loopback. Tests use bounded
timeouts and must stop and free server threads before exiting.
