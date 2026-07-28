# Windows build and runtime notes

The supported Windows build uses MSYS2 CLANG64 only as a build environment.
It downloads the official liblo 0.36 source archive, verifies SHA-256
`c08d14832e8dcf8f06840405824a4f9611a0cb3daed0198946326c740941c8b6`,
and builds a shared `liblo.dll` with native Winsock and threading support.

The Pure wrapper is built as `lo.dll`. The portable package bundles
`liblo.dll`; Windows networking and system DLLs are never copied.

All automated OSC traffic is restricted to IPv4 loopback. Tests use bounded
timeouts and must stop and free server threads before exiting.
