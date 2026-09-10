
include ../Makefile.common

LIBS = -lfftw3

.PHONY: all clean realclean

all: fftw$(DLL)

# Direct cleanup has the same exact suffix/ownership contract as the package.
ifneq ($(filter clean realclean,$(MAKECMDGOALS)),)
ifneq ($(DLL),.dll)
ifneq ($(DLL),.so)
ifneq ($(DLL),.dylib)
$(error refusing to clean: invalid Pure DLL suffix)
endif
endif
endif
endif

clean:
	rm -f -- fftw.o fftw$(DLL)

realclean: clean

fftw$(DLL): fftw.c
	$(CC) $(shared) $(dllname) -o $@ $(MOD_CFLAGS) $< $(MOD_LDFLAGS)
