# MinGW glob and fnmatch compatibility

These sources are derived from the GNU C Library implementations of
`glob(3)` and `fnmatch(3)`, with the historical MinGW portability changes
provided by the Pure project maintainer. The original files retain their
Free Software Foundation copyright notices and LGPL-2.0-or-later terms.

Pure builds these files only for native Windows targets. The CMake integration
defines the ANSI C and MinGW feature macros that the standalone Makefile used
to supply. Local changes keep path counts and allocation sizes in `size_t`
so that the implementation preserves the x86_64 `glob_t` ABI.
