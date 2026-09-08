
include ../Makefile.common

LIBS = -lpthread

all: realtime$(DLL)

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
	rm -f -- realtime.o realtime$(DLL)

realclean: clean

realtime$(DLL): realtime.c
	$(CC) $(shared) $(dllname) -o $@ $(MOD_CFLAGS) $< $(MOD_LDFLAGS)
