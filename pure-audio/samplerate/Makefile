
include ../Makefile.common

LIBS = -lsamplerate

.PHONY: all clean realclean generate

all: srcprocess$(DLL) samplerate.pure

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
	rm -f -- srcprocess.o srcprocess$(DLL)

realclean: clean
	rm -f -- samplerate.pure

srcprocess$(DLL): srcprocess.c
	$(CC) $(shared) $(dllname) -o $@ $(MOD_CFLAGS) $< $(MOD_LDFLAGS)

includedir = /usr/include

generate:
	rm -f samplerate.pure
	make samplerate.pure

samplerate.pure: srcprocess.h src.pure
	pure-gen -C -ansi -s '$(includedir)/samplerate.h;' $(includedir)/samplerate.h -lsrcprocess -o $@
	pure-gen -C -ansi -N -s 'srcprocess.h;' srcprocess.h -o $@
	cat src.pure >> $@
ifeq ($(DLL),.dll)
	mv $@ $@.tmp
	tr -d '\r' < $@.tmp > $@
	rm -f $@.tmp
endif
