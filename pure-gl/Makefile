
# This needs GNU make. Really.

# Package name and version number:
dist = pure-gl-$(version)
version = 0.9

# compiler flags -- these can be overridden from the command line if needed,
# as well as CPPFLAGS, LDFLAGS and LIBS
CFLAGS = -O3
#CFLAGS = -g -O2

# platform-specific setup

PKG_CONFIG ?= pkg-config
CMAKE ?= cmake
DLL         = $(shell "$(PKG_CONFIG)" pure --variable DLL)
PIC         = $(shell "$(PKG_CONFIG)" pure --variable PIC)
shared      = $(shell "$(PKG_CONFIG)" pure --variable shared)

prefix      = $(shell "$(PKG_CONFIG)" pure --variable prefix)
bindir      = $(prefix)/bin
libdir      = $(shell "$(PKG_CONFIG)" pure --variable libdir)

ifeq ($(DLL),.dylib)
dllname = -install_name "$(libdir)/pure/$@"
endif

MOD_CFLAGS  = $(PIC) $(shell "$(PKG_CONFIG)" pure --cflags) $(CFLAGS) $(CPPFLAGS)
MOD_LDFLAGS = $(shell "$(PKG_CONFIG)" pure --libs) $(LDFLAGS) $(LIBS)

# Compilation options to link with OpenGL.
ifeq ($(DLL),.dylib)
MOD_CFLAGS += -Wno-deprecated-declarations
LinkGL = -framework GLUT -framework OpenGL
else
ifeq ($(DLL),.dll)
LinkGL = -lopengl32 -lglu32
else
LinkGL = -lGL -lglut -ldl
endif
endif

MOD_LDFLAGS += $(LinkGL)

# No need to edit below this line, usually.

# Generated stuff:
modules = GL.pure GL_ARB.pure GL_EXT.pure GL_NV.pure GL_ATI.pure \
GLU.pure GLUT.pure
c-modules = $(patsubst %.pure,%.c,$(modules))

override DISTFILES = .pure-gl-source COPYING Makefile README gl.templ CMakeLists.txt WINDOWS.md THIRD_PARTY.md \
cmake/SealBuiltArtifacts.cmake tests/RunnerRetention.ps1 tests/runner_retention_fixture.c tests/built_authority_contract.cmake \
tests/LegacyRetention.ps1 tests/legacy_retention_fixture.c tests/IsolateSource.ps1 tests/VerifyExtractedSource.cmake tests/VerifyCTestInventory.cmake tests/source_preflight_contract.cmake \
debian/changelog debian/compat debian/control debian/copyright debian/docs debian/rules debian/source/format debian/watch \
examples/Imlib2.pure examples/fractal.jpg examples/simple_glut_example.pure examples/teapot.pure examples/texture.pure \
examples/flexi-line/flexi-line-auto.pure examples/flexi-line/flexi-line.pure examples/flexi-line/glamour.pure examples/flexi-line/vector_math.pure \
GL/all_gl.h GL/all_gl_freeglut.h $(modules) $(c-modules) \
cmake/Install.cmake cmake/LegacyPathPolicy.cmake cmake/LegacyWorkflow.cmake cmake/LegacyWorkflow.ps1 cmake/PeHelpers.cmake cmake/RunPureTest.cmake \
cmake/VerifyInstalledPackage.cmake cmake/VerifyWindowsDependencies.cmake cmake/pure_gl_install_guard.c cmake/pure_gl_runner.c \
tests/AuditHelpers.cmake tests/ReleaseChecks.cmake tests/cleanup_contract.cmake tests/configure_contract.cmake tests/hidden-render.pure \
tests/install_contract.cmake tests/install_guard_contract.cmake tests/interactive.pure tests/load.pure \
tests/render_contract.cmake tests/runner_contract.cmake tests/runner_probe.pure tests/runtime_verifier_contract.cmake tests/source_dist_contract.cmake tests/workflow_contract.cmake \
tests/fixtures/freeglut-imports.txt tests/fixtures/libc++-imports.txt tests/fixtures/libgmp-10-imports.txt \
tests/fixtures/libiconv-2-imports.txt tests/fixtures/libmpfr-6-imports.txt tests/fixtures/libpcre-1-imports.txt \
tests/fixtures/libpcreposix-0-imports.txt tests/fixtures/libpure-imports.txt tests/fixtures/libwinpthread-1-imports.txt \
tests/fixtures/libzstd-imports.txt tests/fixtures/pure-gl-imports.txt tests/fixtures/zlib1-imports.txt
SEDFILES = README

.PHONY: all clean realclean generate install uninstall dist distcheck

# Reject invalid discovery even under make -n; no suffix enters a deletion path.
ifneq ($(filter clean realclean generate dist distcheck deb,$(MAKECMDGOALS)),)
ifneq ($(words $(DLL)),1)
$(error Invalid Pure DLL suffix; check pure.pc)
endif
ifeq ($(filter .dll .so .dylib,$(DLL)),)
$(error Invalid Pure DLL suffix; check pure.pc)
endif
endif
legacy_workflow = "$(CMAKE)" "-DMODE=$@" "-DSOURCE_ROOT=$(CURDIR)" "-DDLL_SUFFIX=$(DLL)" "-DPKG_CONFIG_EXECUTABLE=$(PKG_CONFIG)" "-DDIST_FILES=$(DISTFILES)" "-DDIST_AUDIT_BUILD=$(DIST_AUDIT_BUILD)" "-DGNU_MAKE_EXECUTABLE=$(MAKE)" "-DDEBUILD_FLAGS=$(DEBUILD_FLAGS)" -P "$(CURDIR)/cmake/LegacyWorkflow.cmake"

all: pure-gl$(DLL)

pure-gl$(DLL): $(c-modules)
	$(CC) $(shared) $(dllname) $(MOD_CFLAGS) $(c-modules) -o $@ $(MOD_LDFLAGS)

# Clean, but keep generated modules.

clean:
	$(legacy_workflow)

# Clean all, including generated modules. NOTE: This will delete stuff that
# needs special tools to rebuild (see below), so only do this if you know what
# you're doing.

realclean:
	$(legacy_workflow)

# Build the generated modules, preserving existing wrapper sources. To request
# regeneration, run 'make realclean' first, then 'make generate'; pure-gen and
# the OpenGL development headers are required for the missing-source rules.

generate: gl.templ $(wildcard GL/*.h)
	$(legacy_workflow)
	"$(MAKE)" all

# Install targets.

install:
	test -d "$(DESTDIR)$(libdir)/pure" || mkdir -p "$(DESTDIR)$(libdir)/pure"
	cp $(modules) pure-gl$(DLL) "$(DESTDIR)$(libdir)/pure"

uninstall:
	rm -f "$(DESTDIR)$(libdir)/pure/"GL*.pure "$(DESTDIR)$(libdir)/pure/pure-gl$(DLL)"

# Roll a distribution tarball.

date = $(shell date "+%B %-d, %Y")
datesubst = sed -e "s?@version@?$(version)?g" -e "s?|today|?$(date)?g" < $(1) > $(2)

dist:
	$(legacy_workflow)

distcheck:
	$(legacy_workflow)

# Debian packaging

debsrc = pure-gl_$(version).orig.tar.gz

deb:
	$(legacy_workflow)

$(debsrc):
	wget -nv https://bitbucket.org/purelang/pure-lang/downloads/$(dist).tar.gz -O $@

#############################################################################
# Generator stuff. You only need this if you want to regenerate the wrappers.
# You need pure-gen and the OpenGL headers to do this.
#############################################################################

# Path to the installed OpenGL headers (gl.h, glext.h, glu.h, glut.h):
# Note: You can also use your own custom headers. Either adjust the path below
# accordingly, or place them into the GL subdirectory of the pure-gl sources.
glpath = /usr/include

# Use this if you have freeglut and want the freeglut extensions (default):
source = GL/all_gl_freeglut.h
# Use this if you only want the vanilla GLUT stuff:
#source = GL/all_gl.h

# OpenGL proper
# Note: NVidia extensions must be filtered out using '[_a-z]NV', just 'NV'
# will also catch the GL_TEXTURE_ENV constant.
GL.pure: GL.c
GL.c:
	pure-gen -I. -I$(glpath) $(source) -fc -t gl.templ -p GL -m GL -s './GL/*.h,$(glpath)/GL/*.h::^(GL_[A-Z_0-9]+|gl[A-Z].*)$$' -x '(EXT|ARB|[_a-z]NV|ATI|APPLE|SGI|SGIS|SGIX|3DFX|SUN|SUNX|MESA|INTEL|IBM|GREMEDY|HP|PGI|INGR|S3TC|OML|OES)$$' -o $(@:.c=.pure) -c $@ -lpure-gl

# ARB extensions
GL_ARB.pure: GL_ARB.c
GL_ARB.c:
	pure-gen -I. -I$(glpath) $(source) -fc -t gl.templ -p GL -m GL -s './GL/*.h,$(glpath)/GL/*.h::^(GL_[A-Z_0-9]+ARB|gl[A-Z].*ARB)$$' -o $(@:.c=.pure) -c $@ -lpure-gl

# EXT extensions
GL_EXT.pure: GL_EXT.c
GL_EXT.c:
	pure-gen -I. -I$(glpath) $(source) -fc -t gl.templ -p GL -m GL -s './GL/*.h,$(glpath)/GL/*.h::^(GL_[A-Z_0-9]+EXT|gl[A-Z].*EXT)$$' -o $(@:.c=.pure) -c $@ -lpure-gl

# NV extensions
GL_NV.pure: GL_NV.c
GL_NV.c:
	pure-gen -I. -I$(glpath) $(source) -fc -t gl.templ -p GL -m GL -s './GL/*.h,$(glpath)/GL/*.h::^(GL_[A-Z_0-9]+_NV|gl[A-Z].*NV)$$' -o $(@:.c=.pure) -c $@ -lpure-gl

# ATI extensions
GL_ATI.pure: GL_ATI.c
GL_ATI.c:
	pure-gen -I. -I$(glpath) $(source) -fc -t gl.templ -p GL -m GL -s './GL/*.h,$(glpath)/GL/*.h::^(GL_[A-Z_0-9]+ATI|gl[A-Z].*ATI)$$' -o $(@:.c=.pure) -c $@ -lpure-gl

# GLU
GLU.pure: GLU.c
GLU.c:
	pure-gen -I. -I$(glpath) $(source) -fc -t gl.templ -p GLU -m GLU -s './GL/*.h,$(glpath)/GL/*.h::^(GLU_[A-Z_0-9]+|glu[A-Z].*)$$' -o $(@:.c=.pure) -c $@ -lpure-gl

# GLUT
GLUT.pure: GLUT.c
GLUT.c:
	pure-gen -I. -I$(glpath) $(source) -fc -t gl.templ -p GLUT -m GLUT -s './GL/*.h,$(glpath)/GL/*.h::^(GLUT_[A-Z_0-9]+|glut[A-Z].*)$$' -o $(@:.c=.pure) -c $@ -lpure-gl
