# Third-party runtime component

The Windows package redistributes the unmodified MSYS2 CLANG64
`libportmidi.dll` runtime from [PortMidi](https://github.com/PortMidi/portmidi).
PortMidi is distributed under an MIT-style license. The complete upstream text,
including the non-binding requests, is checked in as `licenses/PortMidi.txt`.
It was copied byte-for-byte from the locally installed MSYS2 package
`mingw-w64-clang-x86_64-portmidi 1~2.0.8-1`, not downloaded during installation.
The authoritative project source is
[v2.0.8/license.txt](https://github.com/PortMidi/portmidi/blob/v2.0.8/license.txt).

`licenses/origins.tsv` binds the runtime filename, installed package version,
source URL, MIT license, local license payload, and both SHA-256 hashes. The
license SHA-256 is
`8d187c40c782da0e24489c4c4bf7590635e072dc0b70b0afda7b0652d290c1ea`;
the runtime SHA-256 is
`99454395751bfad786db9c457b93db62f31f7d68dc2bebb2281f33289d43cb49`.
The package's pkg-config metadata reports 2.0.7; the installed package version
and pinned payloads are authoritative for this audit. Strict installation
checks these identities together and never consults `MSYSTEM_PREFIX` for license
content. The portable Pure baseline and its redistribution notices remain the
responsibility of the portable Pure package; this inventory covers the added
pure-midi artifacts and PortMidi runtime.
