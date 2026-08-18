# PureFastCGI third-party provenance

PureFastCGI statically embeds the FastCGI application library (`fcgi2`); it
does not install or load a separate FastCGI DLL.

## fcgi2

- Upstream: `FastCGI-Archives/fcgi2`
- Release: `2.4.7`
- Commit: `47f2c03b7771f0ef61d887734ef91e6fa747f837`
- Archive URL: `https://github.com/FastCGI-Archives/fcgi2/archive/refs/tags/2.4.7.tar.gz`
- Archive size: `263969` bytes
- Archive SHA-256: `e41ddc3a473b555bdc0cbd80703dcb1f4610c1a7700d3b9d3d0c14a416e1074b`
- Embedded implementation files: `libfcgi/fcgi_stdio.c`,
  `libfcgi/fcgiapp.c`, and `libfcgi/os_win32.c`
- Embedded headers: `include/fastcgi.h`, `include/fcgiapp.h`,
  `include/fcgi_stdio.h`, `include/fcgios.h`, `include/fcgimisc.h`, and the
  generated `include/fcgi_config.h` copy of `include/fcgi_config_x86.h`
- Linkage: compiled into `fastcgi.dll` as the private static target
  `fcgi2-static`
- Licence: the Open Market FastCGI licence; its existing copyright notices
  must be retained and its notice included verbatim in distributions. The
  package installs that notice as `LICENSE.fcgi2`.

## Patch set

- `patches/fcgi2-2.4.7-clang64-types.patch`
  - Purpose: preserve pointer-width values and Windows socket/handle types in
    the 64-bit clang64 build.
  - SHA-256: `a95286e560aba3733a74929d0057168a605efcdc112beef2eccc31cf55854f7f`

The archive and patch hashes are checked before compilation.
The dependency preparation also verifies and normalizes one whitespace-only
`WSAAccept` source line before applying the checksum-covered patch.
