
# GNU Makefile to compile the C, Fortran and Faust examples.

# Edit these as needed. CC is the C compiler, FC the Fortran compiler, FAUST
# the Faust compiler, and CLANG is the Clang executable whose LLVM major
# matches the running Pure interpreter.

# NOTE: When using the dragonegg plugin for gcc, make sure to set the variable
# below to the actual pathname of the plugin on your system. Also note that at
# present dragonegg can't be used with -c to generate LLVM bitcode directly
# from source files. Therefore the Makefile selects a different sets of rules
# which create the bitcode from intermediate LLVM assembler (.ll) files
# instead.

# This should work out of the box if you installed dragonegg on ggc's plugin
# path (gcc -print-file-name=plugin).
dragonegg=dragonegg

# Note that dragonegg hasn't been ported to gcc versions >= 4.9 yet, so we
# currently use clang for C compilation by default. If you're still running an
# older version of gcc+dragonegg instead of clang then change the CC lines
# below accordingly.

#CC = llvm-gcc -emit-llvm
#CC = gcc -fplugin=dragonegg -flto
CC = clang -emit-llvm
#FC = llvm-gfortran -emit-llvm
FC = gfortran -fplugin=dragonegg -flto
FAUST = faust
CLANG = clang
FAUSTFLAGS = -double -a pure.c -lang c
FAUST_CLANGFLAGS = -O3 -emit-llvm

# Where the LLVM toolchain (llvm-as et al) is located:
LLVMBIN = $(shell pkg-config pure --variable tool_prefix)

# Prerequisites:

# For the C and Fortran examples, you need to have a version of llvm-gcc or
# gcc+dragonegg with both C and Fortran support installed. (Clang can be used
# instead of llvm-gcc if you have it.) Also, the headers and libraries of the
# GNU Scientific Library (GSL) are needed to compile and run the gslsort.c
# example.

# For the Faust signal processing examples (.dsp programs), you'll need a
# recent Grame Faust compiler (https://faust.grame.fr/) which provides the
# pure.c architecture. Faust emits C and matching Clang compiles that C to
# bitcode; Faust's own LLVM backend is not a supported interchange format.

# If your system lacks any of the above then some of the examples will refuse
# to build. Compilation will proceed anyway, so that you should be able to
# build at least the examples for which you have the required utilities.

# Usage:

# 'make' compiles all the examples.

# 'make asm' can be used to generate the LLVM assembler code for the examples.
# (These are for your own perusal, they aren't needed for running the examples
# in Pure.)

# 'make clean' removes all the generated bitcode and assembler files.

# Examples showing how to use the bitcode interface in Pure 0.44 and later can
# be found in the corresponding *.pure scripts.

c_source   := $(wildcard *.c)
# f_source disabled for now, as neither llvm-gcc and dragonegg is supported
# any longer, so at present we're left without an LLVM-capable Fortran
# compiler that we could use. :(
#f_source   := $(wildcard *.f90)
dsp_source := $(wildcard *.dsp)
bitcode    := $(c_source:.c=.bc) $(f_source:.f90=.bc) $(dsp_source:.dsp=.bc)
assembler  := $(c_source:.c=.ll) $(f_source:.f90=.ll) $(dsp_source:.dsp=.ll)
source     := $(c_source) $(f_source) $(dsp_source)

all: $(bitcode)

asm: $(assembler)

clean:
	-rm -f $(bitcode)
	-rm -f $(assembler)
	-rm -f *.faust.*.c

# Single-stage C and Fortran rules (these don't work with dragonegg).

ifeq (,$(findstring $(dragonegg),$(CC)))
%.bc: %.c
	-$(CC) -c $< -o $@
endif

ifeq (,$(findstring $(dragonegg),$(FC)))
%.bc: %.f90
	-$(FC) -c $< -o $@
endif

%.bc: %.dsp
	-@set -e; cfile="$@.faust.$$$$.c"; \
	  trap 'rm -f "$$cfile"' EXIT HUP INT TERM; \
	  "$(FAUST)" $(FAUSTFLAGS) "$<" -o "$$cfile"; \
	  "$(CLANG)" $(FAUST_CLANGFLAGS) -x c -c "$$cfile" -o "$@"

# fallback rule to generate LLVM bitcode from assembler
%.bc: %.ll
	-$(LLVMBIN)llvm-as $< -o $@

# compile C source to LLVM assembler
%.ll: %.c
	-$(CC) -S $< -o $@

# compile Fortran source to LLVM assembler
%.ll: %.f90
	-$(FC) -S $< -o $@

# compile Faust source to LLVM assembler
%.ll: %.dsp
	-@set -e; cfile="$@.faust.$$$$.c"; \
	  trap 'rm -f "$$cfile"' EXIT HUP INT TERM; \
	  "$(FAUST)" $(FAUSTFLAGS) "$<" -o "$$cfile"; \
	  "$(CLANG)" $(FAUST_CLANGFLAGS) -x c -S "$$cfile" -o "$@"
