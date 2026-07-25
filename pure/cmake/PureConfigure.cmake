include_guard(GLOBAL)

include(CheckCSourceCompiles)
include(CheckIncludeFile)
include(CheckIncludeFiles)
include(CheckLinkerFlag)
include(CheckSymbolExists)
include(CheckTypeSize)
include(GNUInstallDirs)
include(TestBigEndian)

option(PURE_ENABLE_FASTCC "Enable fast calling conventions and tail calls" ON)
option(PURE_VERSIONED_INSTALL "Install the Pure library in a versioned directory" OFF)

check_type_size("long" SIZEOF_LONG LANGUAGE C)
check_type_size("size_t" SIZEOF_SIZE_T LANGUAGE C)
set(SIZEOF_VOID_P "${CMAKE_SIZEOF_VOID_P}")
test_big_endian(WORDS_BIGENDIAN)

check_include_file("alloca.h" HAVE_ALLOCA_H)
check_include_file("sys/fcntl.h" HAVE_SYS_FCNTL_H)
check_include_file("sys/wait.h" HAVE_SYS_WAIT_H)
set(_pure_required_includes "${CMAKE_REQUIRED_INCLUDES}")
list(APPEND CMAKE_REQUIRED_INCLUDES ${READLINE_INCLUDE_DIRS})
check_include_files("stdio.h;readline/readline.h" HAVE_READLINE_READLINE_H)
check_include_files("stdio.h;readline/history.h" HAVE_READLINE_HISTORY_H)

check_symbol_exists(_setjmp "setjmp.h" HAVE__SETJMP)
check_symbol_exists(_longjmp "setjmp.h" HAVE__LONGJMP)
check_symbol_exists(fstat "sys/stat.h" HAVE_FSTAT)
check_symbol_exists(mkstemp "stdlib.h" HAVE_MKSTEMP)
check_symbol_exists(readdir "dirent.h" HAVE_READDIR)
set(_pure_required_definitions "${CMAKE_REQUIRED_DEFINITIONS}")
list(APPEND CMAKE_REQUIRED_DEFINITIONS -D_XOPEN_SOURCE=700)
check_symbol_exists(strptime "time.h" HAVE_XOPEN_STRPTIME)
set(CMAKE_REQUIRED_DEFINITIONS "${_pure_required_definitions}")
set(HAVE_STRPTIME "${HAVE_XOPEN_STRPTIME}")

set(CMAKE_REQUIRED_LIBRARIES PkgConfig::READLINE)
check_symbol_exists(
  history_set_history_state
  "stdio.h;readline/history.h"
  HAVE_HISTORY_SET_HISTORY_STATE
)
unset(CMAKE_REQUIRED_LIBRARIES)
set(CMAKE_REQUIRED_INCLUDES "${_pure_required_includes}")

check_c_source_compiles(
  "int main(void) { _Complex float value = 0; (void)value; return 0; }"
  HAVE__COMPLEX_FLOAT
)
check_c_source_compiles(
  "int main(void) { _Complex double value = 0; (void)value; return 0; }"
  HAVE__COMPLEX_DOUBLE
)

check_linker_flag(CXX "-Wl,-l:libm.a" GNU_LINKER)

if(PURE_VERSIONED_INSTALL)
  set(PURE_LIBRARY_DIRECTORY "pure-${PROJECT_VERSION}")
else()
  set(PURE_LIBRARY_DIRECTORY "pure")
endif()

set(PURELIB_INSTALL "${CMAKE_INSTALL_FULL_LIBDIR}/${PURE_LIBRARY_DIRECTORY}")
file(
  RELATIVE_PATH
  PURELIB_RELATIVE_FROM_RUNTIME
  "/${CMAKE_INSTALL_BINDIR}"
  "/${CMAKE_INSTALL_LIBDIR}/${PURE_LIBRARY_DIRECTORY}"
)
string(REPLACE "\\" "/" PURELIB_RELATIVE_FROM_RUNTIME "${PURELIB_RELATIVE_FROM_RUNTIME}")
file(
  RELATIVE_PATH
  PURETOOLS_RELATIVE_FROM_RUNTIME
  "/${CMAKE_INSTALL_BINDIR}"
  "/tools/bin"
)
string(REPLACE "\\" "/" PURETOOLS_RELATIVE_FROM_RUNTIME "${PURETOOLS_RELATIVE_FROM_RUNTIME}")
if(WIN32)
  set(PURELIB "${PURELIB_RELATIVE_FROM_RUNTIME}")
  set(TOOL_PREFIX "")
else()
  set(PURELIB "${PURELIB_INSTALL}")
  set(TOOL_PREFIX "${LLVM_TOOLS_BINARY_DIR}/")
endif()
set(DLLEXT "${CMAKE_SHARED_LIBRARY_SUFFIX}")
set(EXEEXT "${CMAKE_EXECUTABLE_SUFFIX}")
set(LLVM_VERSION "${LLVM_PACKAGE_VERSION}")
set(HOST "${PURE_HOST_TRIPLE}")
set(PCRE_LIBS "-lpcreposix")

set(HAVE_FASTCC "${PURE_ENABLE_FASTCC}")
set(HAVE_LIBREADLINE TRUE)
set(HAVE_READLINE_HISTORY TRUE)
set(USE_PCRE TRUE)
set(USE_READLINE TRUE)
set(HAVE_BISON3 TRUE)

configure_file(
  "${CMAKE_CURRENT_SOURCE_DIR}/config.h.cmake"
  "${CMAKE_CURRENT_BINARY_DIR}/config.h"
  @ONLY
)

message(STATUS "Host triple: ${HOST}")
message(STATUS "Pure library directory: ${PURELIB_INSTALL}")
message(STATUS "Generated configuration: ${CMAKE_CURRENT_BINARY_DIR}/config.h")
