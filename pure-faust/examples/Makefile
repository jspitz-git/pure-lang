
# Generic Makefile for Pure-Faust plugins.

# make, make all: make plugins
# make bitcode: make plugins in LLVM bitcode format
# make cpp: make C++ sources
# make svg: make SVG diagrams
# make clean: remove all generated stuff

# Platform-specific defaults, edit this as needed.
#PIC = -fPIC # uncomment for x86-64 compilation
DLL = .so
shared = -shared

CXXFLAGS = -g -O2
FAUST = faust
CLANG = clang
FAUST_C_FLAGS = -lang c -a pure.c -double
FAUST_CLANG_FLAGS = -emit-llvm -O3

# Try to guess the host system type and figure out compilation flags.
host = $(shell ./config.guess)
ifneq "$(findstring -mingw,$(host))" ""
# Windows
DLL = .dll
endif
ifneq "$(findstring -darwin,$(host))" ""
# OSX (untested)
DLL = .dylib
shared = -dynamiclib
endif
ifneq "$(findstring x86_64-,$(host))" ""
# 64 bit, needs -fPIC flag
PIC = -fPIC
endif

dspsrc  := $(wildcard *.dsp)
cppsrc  := $(dspsrc:.dsp=.cpp)
plugins	:= $(dspsrc:.dsp=$(DLL))
bitcode	:= $(dspsrc:.dsp=.bc)
svg 	:= $(dspsrc:.dsp=-svg)
xml 	:= $(dspsrc:.dsp=.dsp.xml)

all: $(plugins)
cpp: $(cppsrc)
svg: $(svg)
xml: $(xml)

# Use this target to generate bitcode modules (this requires faust2).
bitcode: $(bitcode)

clean:
	rm -Rf *~ $(cppsrc) $(plugins) $(bitcode) $(svg) $(xml)
	-rm -f *.faust.*.c

%.cpp: %.dsp
	"$(FAUST)" -a pure.cpp -double $< -o $@

%$(DLL): %.cpp
	$(CXX) $(shared) $(PIC) $(CPPFLAGS) $(CXXFLAGS) $(LDFLAGS) -o $@ $<

# Faust bitcode is always generated through the portable pure.c architecture
# and the Clang selected by CLANG, which must match Pure's LLVM major.
%.bc: %.dsp
	@set -e; cfile="$@.faust.$$$$.c"; \
	  trap 'rm -f "$$cfile"' EXIT HUP INT TERM; \
	  "$(FAUST)" $(FAUST_C_FLAGS) "$<" -o "$$cfile"; \
	  "$(CLANG)" $(FAUST_CLANG_FLAGS) -x c -c "$$cfile" -o "$@"

%-svg: %.dsp
	faust -svg $< -o /dev/null

%.dsp.xml: %.dsp
	faust -xml $< -o /dev/null
