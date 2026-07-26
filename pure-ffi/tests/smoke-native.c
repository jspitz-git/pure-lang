#include <stdint.h>

#ifdef _WIN32
#define FFI_SMOKE_EXPORT __declspec(dllexport)
#else
#define FFI_SMOKE_EXPORT
#endif

typedef struct {
  int32_t number;
  double fraction;
} ffi_smoke_record;

typedef int32_t (*ffi_smoke_callback)(int32_t, int32_t);

static int32_t pointer_value = 37;

FFI_SMOKE_EXPORT int32_t ffi_smoke_add(int32_t x, int32_t y)
{
  return x + y;
}

FFI_SMOKE_EXPORT int32_t *ffi_smoke_pointer(void)
{
  return &pointer_value;
}

FFI_SMOKE_EXPORT int32_t ffi_smoke_read_pointer(const int32_t *pointer)
{
  return pointer ? *pointer : -1;
}

FFI_SMOKE_EXPORT ffi_smoke_record
ffi_smoke_transform_record(ffi_smoke_record value)
{
  value.number += 5;
  value.fraction *= 2.0;
  return value;
}

FFI_SMOKE_EXPORT int32_t
ffi_smoke_invoke_callback(ffi_smoke_callback callback, int32_t x, int32_t y)
{
  return callback ? callback(x, y) : -1;
}
