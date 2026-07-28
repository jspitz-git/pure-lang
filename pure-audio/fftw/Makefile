
include ../Makefile.common

LIBS = -lfftw3

.PHONY: all clean realclean

all: fftw$(DLL)

clean:
	@test -n "$(DLL)" || { echo "refusing to clean: Pure DLL suffix is empty" >&2; exit 1; }
	rm -Rf *.o *$(DLL)*

realclean:
	@test -n "$(DLL)" || { echo "refusing to clean: Pure DLL suffix is empty" >&2; exit 1; }
	rm -Rf *.o *$(DLL)*

fftw$(DLL): fftw.c
	$(CC) $(shared) $(dllname) -o $@ $(MOD_CFLAGS) $< $(MOD_LDFLAGS)
