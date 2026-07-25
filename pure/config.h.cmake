#ifndef PURE_CONFIG_H
#define PURE_CONFIG_H

#define PACKAGE_NAME "pure"
#define PACKAGE_VERSION "@PROJECT_VERSION@"
#define HOST "@HOST@"
#define LLVM_VERSION "@LLVM_VERSION@"
#define PURELIB "@PURELIB@"
#define PURELIB_RELATIVE_FROM_RUNTIME "@PURELIB_RELATIVE_FROM_RUNTIME@"
#define TOOL_PREFIX "@TOOL_PREFIX@"
#define DLLEXT "@DLLEXT@"
#define EXEEXT "@EXEEXT@"
#define PCRE_LIBS "@PCRE_LIBS@"

#define SIZEOF_LONG @SIZEOF_LONG@
#define SIZEOF_SIZE_T @SIZEOF_SIZE_T@
#define SIZEOF_VOID_P @SIZEOF_VOID_P@

#cmakedefine WORDS_BIGENDIAN 1
#cmakedefine GNU_LINKER 1
#cmakedefine HAVE_ALLOCA_H 1
#cmakedefine HAVE_SYS_FCNTL_H 1
#cmakedefine HAVE_SYS_WAIT_H 1
#cmakedefine HAVE_FSTAT 1
#cmakedefine HAVE_MKSTEMP 1
#cmakedefine HAVE_READDIR 1
#cmakedefine HAVE_STRPTIME 1
#cmakedefine HAVE__SETJMP 1
#cmakedefine HAVE__LONGJMP 1
#cmakedefine HAVE__COMPLEX_FLOAT 1
#cmakedefine HAVE__COMPLEX_DOUBLE 1

#cmakedefine HAVE_LIBREADLINE 1
#cmakedefine HAVE_READLINE_READLINE_H 1
#cmakedefine HAVE_READLINE_HISTORY 1
#cmakedefine HAVE_READLINE_HISTORY_H 1
#cmakedefine HAVE_HISTORY_SET_HISTORY_STATE 1
#cmakedefine USE_READLINE 1
#cmakedefine USE_PCRE 1
#cmakedefine HAVE_FASTCC 1
#cmakedefine HAVE_BISON3 1

#endif
