
include ../Makefile.common

LIBS = -lpthread

all: realtime$(DLL)

clean:
	@test -n "$(DLL)" || { echo "refusing to clean: Pure DLL suffix is empty" >&2; exit 1; }
	rm -Rf *.o *$(DLL)*

realclean:
	@test -n "$(DLL)" || { echo "refusing to clean: Pure DLL suffix is empty" >&2; exit 1; }
	rm -Rf *.o *$(DLL)*

realtime$(DLL): realtime.c
	$(CC) $(shared) $(dllname) -o $@ $(MOD_CFLAGS) $< $(MOD_LDFLAGS)
