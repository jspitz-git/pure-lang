#ifndef PURE_REDUCE_BRIDGE_H
#define PURE_REDUCE_BRIDGE_H

#if defined(PURE_REDUCE_STATIC)
#  define PURE_REDUCE_API
#elif defined(_WIN32)
#  if defined(PURE_REDUCE_BUILDING)
#    define PURE_REDUCE_API __declspec(dllexport)
#  else
#    define PURE_REDUCE_API __declspec(dllimport)
#  endif
#else
#  define PURE_REDUCE_API
#endif

#ifdef __cplusplus
extern "C" {
#endif

enum pure_reduce_state {
  PURE_REDUCE_UNINITIALIZED = 0,
  PURE_REDUCE_RUNNING = 1,
  PURE_REDUCE_FINISHED = 2,
  PURE_REDUCE_FAILED = 3
};

PURE_REDUCE_API int pure_reduce_start(const char *image_utf8);
PURE_REDUCE_API int pure_reduce_finish(void);
PURE_REDUCE_API int pure_reduce_state(void);
PURE_REDUCE_API const char *pure_reduce_last_error(void);

PURE_REDUCE_API int PROC_capture_output(int flag);
PURE_REDUCE_API const char *PROC_get_output(void);
PURE_REDUCE_API void PROC_clear_output(void);
PURE_REDUCE_API int PROC_feed_input(const char *input_utf8);
PURE_REDUCE_API int PROC_make_cons(void);
PURE_REDUCE_API int PROC_checksym(const char *symbol_utf8);

PURE_REDUCE_API int texmacs_valid(const char *text_utf8);
PURE_REDUCE_API const char *texmacs_post(const char *text_utf8);

#ifdef __cplusplus
}
#endif

#endif
