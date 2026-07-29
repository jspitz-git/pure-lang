#define WIN32_LEAN_AND_MEAN
#include <windows.h>

static void
unexpected_pure_runtime_call(void)
{
  ExitProcess(99);
}

#define PURE_RUNTIME_STUB(name) \
  __declspec(dllexport) void name(void) \
  { unexpected_pure_runtime_call(); }

PURE_RUNTIME_STUB(pure_appx)
PURE_RUNTIME_STUB(pure_complex)
PURE_RUNTIME_STUB(pure_complex_matrix)
PURE_RUNTIME_STUB(pure_cstring_dup)
PURE_RUNTIME_STUB(pure_double)
PURE_RUNTIME_STUB(pure_double_matrix)
PURE_RUNTIME_STUB(pure_free)
PURE_RUNTIME_STUB(pure_freenew)
PURE_RUNTIME_STUB(pure_get_sentry)
#ifndef PURE_RUNTIME_STUB_OMIT_PURE_INT
PURE_RUNTIME_STUB(pure_int)
#endif
PURE_RUNTIME_STUB(pure_int64)
PURE_RUNTIME_STUB(pure_int_matrix)
PURE_RUNTIME_STUB(pure_is_app)
PURE_RUNTIME_STUB(pure_is_complex)
PURE_RUNTIME_STUB(pure_is_complex_matrix)
PURE_RUNTIME_STUB(pure_is_cstring_dup)
PURE_RUNTIME_STUB(pure_is_double)
PURE_RUNTIME_STUB(pure_is_double_matrix)
PURE_RUNTIME_STUB(pure_is_int)
PURE_RUNTIME_STUB(pure_is_int_matrix)
PURE_RUNTIME_STUB(pure_is_pointer)
PURE_RUNTIME_STUB(pure_is_symbolic_matrix)
PURE_RUNTIME_STUB(pure_is_tuplev)
PURE_RUNTIME_STUB(pure_matrix_rowsl)
PURE_RUNTIME_STUB(pure_matrix_rowsv)
PURE_RUNTIME_STUB(pure_new)
PURE_RUNTIME_STUB(pure_pointer)
PURE_RUNTIME_STUB(pure_sentry)
PURE_RUNTIME_STUB(pure_sym)
PURE_RUNTIME_STUB(pure_sym_pname)
PURE_RUNTIME_STUB(pure_symbol)
PURE_RUNTIME_STUB(pure_symbolic_matrix)
PURE_RUNTIME_STUB(pure_tuplev)
PURE_RUNTIME_STUB(pure_unref)
PURE_RUNTIME_STUB(pure_uint64)
PURE_RUNTIME_STUB(str)

#ifdef PURE_RUNTIME_STUB_EXTRA
PURE_RUNTIME_STUB(pure_runtime_stub_extra)
#endif
