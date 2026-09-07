
# Package name and version number:
dist = pure-odbc-$(version)
version = 0.10

# compiler flags -- these can be overridden from the command line if needed,
# as well as CPPFLAGS, LDFLAGS and LIBS
CFLAGS = -O3
#CFLAGS = -g -O2

# platform-specific setup

PKG_CONFIG ?= pkg-config

DLL         = $(shell $(PKG_CONFIG) pure --variable DLL)
PIC         = $(shell $(PKG_CONFIG) pure --variable PIC)
shared      = $(shell $(PKG_CONFIG) pure --variable shared)

prefix      = $(shell $(PKG_CONFIG) pure --variable prefix)
bindir      = $(prefix)/bin
libdir      = $(shell $(PKG_CONFIG) pure --variable libdir)

ODBCLIB = -lodbc

ifeq ($(DLL),.dylib)
dllname = -install_name "$(libdir)/pure/$@"
endif

ifeq ($(DLL),.dll)
ODBCLIB = -lodbc32
LDFLAGS = -Wl,--enable-auto-import
endif

LIBS = $(ODBCLIB) -lgmp

MOD_CFLAGS  = $(PIC) $(shell $(PKG_CONFIG) pure --cflags) $(CFLAGS) $(CPPFLAGS)
MOD_LDFLAGS = $(shell $(PKG_CONFIG) pure --libs) $(LDFLAGS) $(LIBS)

DISTFILES = CMakeLists.txt COPYING COPYING.LESSER Makefile README WINDOWS.md \
cmake/Install.cmake cmake/RunPureTest.cmake \
cmake/VerifyInstalledPackage.cmake cmake/VerifyWindowsDependencies.cmake \
debian/changelog debian/compat debian/control debian/copyright debian/docs \
debian/rules debian/source/format debian/watch examples/menagerie.pure \
odbc.c odbc.pure odbc_api.h tests/ContractTestRoot.cmake \
tests/access_smoke.pure tests/cleanup_contract.cmake \
tests/configure_contract.cmake tests/data/people.csv tests/data/Schema.ini \
tests/install_contract.cmake tests/load.pure tests/odbc_fault_harness.c \
tests/run_pure_test.c tests/runner_contract.cmake \
tests/runtime_verifier_contract.cmake tests/smoke.pure \
tests/source_dist_contract.cmake
SEDFILES = README

all: odbc$(DLL)

odbc$(DLL): odbc.c
	$(CC) $(shared) $(dllname) -o $@ $(MOD_CFLAGS) $< $(MOD_LDFLAGS)

clean:
	@case "$(DLL)" in .dll|.so|.dylib) ;; *) \
	  echo "refusing to clean: Pure DLL suffix is invalid" >&2; \
	  exit 1 ;; esac
	rm -f "odbc$(DLL)" odbc.a odbc.o

install:
	test -d "$(DESTDIR)$(libdir)/pure" || mkdir -p "$(DESTDIR)$(libdir)/pure"
	cp odbc.pure odbc$(DLL) "$(DESTDIR)$(libdir)/pure"

uninstall:
	rm -f "$(DESTDIR)$(libdir)/pure/odbc.pure" "$(DESTDIR)$(libdir)/pure/odbc$(DLL)"

date = $(shell date "+%B %-d, %Y")
datesubst = sed -e "s?@version@?$(version)?g" -e "s?|today|?$(date)?g" < $(1) > $(2)

check-dist-name:
	@case "$(dist)" in \
	  pure-odbc-[0-9]*) ;; \
	  *) echo "refusing unsafe distribution name: $(dist)" >&2; exit 1 ;; \
	esac; \
	case "$(dist)" in *..*|*/*|*\\*) \
	  echo "refusing unsafe distribution name: $(dist)" >&2; exit 1 ;; \
	esac

dist: check-dist-name
	rm -rf "$(dist)"
	mkdir "$(dist)"
	@for x in $(DISTFILES); do \
	  test -f "$$x" && test ! -L "$$x" || { \
	    echo "refusing non-regular distribution input: $$x" >&2; exit 1; \
	  }; \
	  target="$(dist)/$$x"; \
	  mkdir -p "$${target%/*}"; \
	  cp -p "$$x" "$$target"; \
	done
	@for x in $(SEDFILES); do \
	  $(call datesubst,"$$PWD/$$x","$(dist)/$$x"); \
	done
	rm -f "$(dist).tar.gz"
	tar cfz "$(dist).tar.gz" "$(dist)"
	rm -rf "$(dist)"

distcheck: dist
	tar xfz "$(dist).tar.gz"
	cd "$(dist)" && make && make install DESTDIR=./BUILD
	rm -rf "$(dist)"

debsrc = $(shell echo $(dist) | sed -e 's/-$(version)/_$(version)/').orig.tar.gz

deb: $(debsrc) dist
	tar xfz "$(dist).tar.gz"
	cd "$(dist)" && debuild $(DEBUILD_FLAGS)
	rm -rf "$(dist)"

$(debsrc):
	wget -nv https://bitbucket.org/purelang/pure-lang/downloads/$(dist).tar.gz -O $@
