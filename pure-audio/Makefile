
# Package name and version number:
dist = pure-audio-$(version)
version = 0.6

# check Makefile.common for compiler flags and platform-specific settings
ifeq ($(strip $(filter-out dist distcheck diffs deb,$(MAKECMDGOALS))),)
ifneq ($(strip $(MAKECMDGOALS)),)
# Source/package targets do not need a configured compiler or Pure pkg-config.
else
include Makefile.common
endif
else
include Makefile.common
endif

LIBS = -lportaudio -lpthread

# Comment this out to *not* install the realtime module.
realtime = realtime

override DISTFILES = COPYING CMakeLists.txt Makefile Makefile.common README WINDOWS.md THIRD_PARTY.md \
audio.c audio.pure audio_test_api.h portaudio.pure \
cmake/Install.cmake cmake/RunHardwareTest.cmake cmake/RunPureTest.cmake \
cmake/VerifyInstalledPackage.cmake cmake/VerifyWindowsDependencies.cmake cmake/install_guard.c \
cmake/CreateSourceArchive.cmake cmake/SourceArchiveTools.ps1 \
cmake/SourceWorkflow.cmake \
debian/changelog debian/compat debian/control debian/copyright debian/docs \
debian/rules debian/source/format debian/watch examples/audio_examp.pure examples/audio_test.pd \
fftw/Makefile fftw/fftw.c fftw/fftw.pure \
samplerate/Makefile samplerate/srcprocess.c samplerate/srcprocess.h \
samplerate/src.pure samplerate/samplerate.pure \
sndfile/Makefile sndfile/sfinfo.c sndfile/sfinfo.h sndfile/sf.pure \
sndfile/sndfile.pure \
realtime/Makefile realtime/realtime.c realtime/realtime.pure \
tests/audio_fault_harness.c tests/bounds.pure tests/cleanup_contract.cmake \
tests/configure_contract.cmake tests/hardware-capture.pure tests/hardware-playback.pure \
tests/hardware.pure tests/install_contract.cmake tests/install_guard_contract.ps1 \
tests/load.pure tests/run_pure_test.c tests/runner_contract.cmake \
tests/runtime_verifier_contract.cmake tests/smoke.pure tests/source_dist_contract.cmake \
tests/source_dist_tools.ps1 \
tests/source_dist_extracted.cmake \
licenses/.gitattributes licenses/FFTW-COPYING.txt licenses/FFTW-COPYRIGHT.txt licenses/FLAC-Xiph.txt \
licenses/GMP-COPYING-LESSERv3.txt licenses/GMP-COPYINGv2.txt licenses/GMP-COPYINGv3.txt \
licenses/LAME-COPYING.txt licenses/MPFR-COPYING-LESSER.txt licenses/MPFR-COPYING.txt \
licenses/Opus.txt licenses/PCRE-LICENCE.txt licenses/PortAudio.txt \
licenses/Pure-COPYING-LESSER.txt licenses/Pure-COPYING.txt licenses/Pure-README.txt \
licenses/Readline-COPYING.txt licenses/Termcap-COPYING.txt licenses/Vorbis-COPYING.txt \
licenses/Zlib-LICENSE.txt licenses/Zstd-LICENSE.txt licenses/libcxx.txt \
licenses/libiconv-COPYING-LIB.txt licenses/libogg.txt licenses/libsamplerate.txt \
licenses/libsndfile.txt licenses/mpg123.txt licenses/origins.tsv licenses/winpthreads.txt
SEDFILES = README
DIST_CMAKE ?= cmake
DIST_TAR ?= tar
DIST_OUTPUT_DIRECTORY ?= $(CURDIR)
# Preserve quoting inside legacy Debian flags without interpolating them into
# another shell command line. SourceWorkflow parses this exported value once.
export DEBUILD_FLAGS

subdirs = fftw samplerate sndfile $(realtime)

# Makefile to build the PortAudio wrapper and the libsamplerate and libsndfile
# support libraries.

.PHONY: all clean realclean subdirs generate install uninstall dist distcheck

all: audio$(DLL) portaudio.pure subdirs

subdirs:
	for dir in $(subdirs); do $(MAKE) -C $$dir all; done

# Validate before expanding the suffix into a shell recipe. Only these exact
# platform suffixes are supported; patterns and path fragments are never names.
ifneq ($(filter clean realclean,$(MAKECMDGOALS)),)
ifneq ($(DLL),.dll)
ifneq ($(DLL),.so)
ifneq ($(DLL),.dylib)
$(error refusing to clean: invalid Pure DLL suffix)
endif
endif
endif
endif

owned_outputs = audio.o audio$(DLL) \
fftw/fftw.o fftw/fftw$(DLL) \
samplerate/srcprocess.o samplerate/srcprocess$(DLL) \
sndfile/sfinfo.o sndfile/sfinfo$(DLL) \
realtime/realtime.o realtime/realtime$(DLL)

clean:
	rm -f -- $(owned_outputs)

realclean: clean
	rm -f -- portaudio.pure samplerate/samplerate.pure sndfile/sndfile.pure

audio$(DLL): audio.c
	$(CC) $(shared) $(dllname) -o $@ $(MOD_CFLAGS) $< $(MOD_LDFLAGS)

# Type 'make generate' to force a rebuild of the wrappers. This requires
# pure-gen and that you have required header files in the $(includedir)
# directory.

includedir = /usr/include

generate:
	rm -f portaudio.pure
	$(MAKE) portaudio.pure
	$(MAKE) -C samplerate generate
	$(MAKE) -C sndfile generate

portaudio.pure:
ifeq ($(DLL),.dll)
	echo 'using "lib:libportaudio-2.dll";' > $@
	pure-gen -C -ansi -N -m Pa -p Pa -s '$(includedir)/portaudio.h;' $(includedir)/portaudio.h -laudio -o $@
	mv $@ $@.tmp
	tr -d '\r' < $@.tmp > $@
	rm -f $@.tmp
else
	pure-gen -m Pa -p Pa -s '$(includedir)/portaudio.h;' -x '^(linux|unix)$$' $(includedir)/portaudio.h -laudio -o $@
endif

# Type 'make diffs' to generate the wrappers for this platform and compare
# them against the distributed sources.

diffs:
	"$(DIST_CMAKE)" "-DMODE=diffs" $(source_workflow_args) -P "$(CURDIR)/cmake/SourceWorkflow.cmake"

install:
	test -d "$(DESTDIR)$(libdir)/pure" || mkdir -p "$(DESTDIR)$(libdir)/pure"
	cp audio.pure portaudio.pure audio$(DLL) fftw/fftw.pure fftw/fftw$(DLL) samplerate/samplerate.pure samplerate/srcprocess$(DLL) sndfile/sndfile.pure sndfile/sfinfo$(DLL) "$(DESTDIR)$(libdir)/pure"
ifneq ($(strip $(realtime)),)
	cp realtime/realtime.pure realtime/realtime$(DLL) "$(DESTDIR)$(libdir)/pure"
endif

uninstall:
	rm -f "$(DESTDIR)$(libdir)/pure/audio.pure" "$(DESTDIR)$(libdir)/pure/portaudio.pure" "$(DESTDIR)$(libdir)/pure/fftw.pure" "$(DESTDIR)$(libdir)/pure/samplerate.pure" "$(DESTDIR)$(libdir)/pure/sndfile.pure" "$(DESTDIR)$(libdir)/pure/audio$(DLL)" "$(DESTDIR)$(libdir)/pure/fftw$(DLL)" "$(DESTDIR)$(libdir)/pure/srcprocess$(DLL)" "$(DESTDIR)$(libdir)/pure/sfinfo$(DLL)"
ifneq ($(strip $(realtime)),)
	rm -f "$(DESTDIR)$(libdir)/pure/realtime.pure" "$(DESTDIR)$(libdir)/pure/realtime$(DLL)"
endif

date = $(shell date "+%B %-d, %Y")
datesubst = sed -e "s?@version@?$(version)?g" -e "s?|today|?$(date)?g" < $(1) > $(2)

dist:
	"$(DIST_CMAKE)" "-DDIST_SOURCE_ROOT=$(CURDIR)" "-DDIST_OUTPUT_DIRECTORY=$(DIST_OUTPUT_DIRECTORY)" "-DDIST_ARCHIVE_BASENAME=$(dist)" "-DDIST_FILES=$(DISTFILES)" "-DDIST_TAR=$(DIST_TAR)" -P "$(CURDIR)/cmake/CreateSourceArchive.cmake"

source_workflow_args = "-DDIST_SOURCE_ROOT=$(CURDIR)" "-DDIST_ARCHIVE_BASENAME=$(dist)" "-DDIST_FILES=$(DISTFILES)" "-DDIST_TAR=$(DIST_TAR)" "-DDIST_MAKE=$(MAKE)" "-DDIST_AUDIT_BUILD=$(DIST_AUDIT_BUILD)" "-DDIST_DEBIAN_ORIG=$(DIST_DEBIAN_ORIG)"

distcheck:
	"$(DIST_CMAKE)" "-DMODE=distcheck" $(source_workflow_args) -P "$(CURDIR)/cmake/SourceWorkflow.cmake"

deb:
	"$(DIST_CMAKE)" "-DMODE=deb" $(source_workflow_args) -P "$(CURDIR)/cmake/SourceWorkflow.cmake"
