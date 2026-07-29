#ifndef PURE_OCTAVE_BRIDGE_API_H
#define PURE_OCTAVE_BRIDGE_API_H

#define PURE_OCTAVE_BRIDGE_ABI "pure-octave/11.3.0/windows-x86_64/v1"
#define PURE_OCTAVE_SIGNING_FINGERPRINT \
  "DBD9C84E39FE1AAE99F04446B05F05B75D36644B"
#define PURE_OCTAVE_FINGERPRINT_FILE "pure-octave.fingerprint"

#if defined(_WIN32)
#  if defined(PURE_OCTAVE_LOADER_BUILD)
#    define PURE_OCTAVE_LOADER_API __declspec(dllexport)
#  else
#    define PURE_OCTAVE_LOADER_API
#  endif
#  if defined(PURE_OCTAVE_IMPL_BUILD)
#    define PURE_OCTAVE_IMPL_API __declspec(dllexport)
#  else
#    define PURE_OCTAVE_IMPL_API
#  endif
#else
#  define PURE_OCTAVE_LOADER_API
#  define PURE_OCTAVE_IMPL_API
#endif

#ifdef __cplusplus
extern "C" {
#endif

PURE_OCTAVE_LOADER_API int octave_init(int argc, char **argv);
PURE_OCTAVE_LOADER_API void octave_fini(void);
PURE_OCTAVE_LOADER_API int octave_eval(const char *command);
PURE_OCTAVE_LOADER_API const char *octave_last_error(void);

PURE_OCTAVE_IMPL_API int pure_octave_impl_init(int argc, char **argv);
PURE_OCTAVE_IMPL_API void pure_octave_impl_fini(void);
PURE_OCTAVE_IMPL_API int pure_octave_impl_eval(const char *command);
PURE_OCTAVE_IMPL_API const char *pure_octave_impl_last_error(void);
PURE_OCTAVE_IMPL_API const char *pure_octave_impl_abi(void);

#ifdef __cplusplus
}
#endif

#endif
