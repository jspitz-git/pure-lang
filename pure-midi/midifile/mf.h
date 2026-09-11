
#include <pure/runtime.h>
#include <stddef.h>
#include <stdint.h>

bool pure_midi_matrix_elements(size_t rows, size_t columns, size_t *elements);
bool pure_midi_validate_event(int64_t tick, size_t rows, size_t columns,
                              size_t stride, const int *data, size_t *length);
#ifdef PURE_MIDI_TEST_SEAM
/* Fail the nth bridge allocation/construction; SIZE_MAX disables injection. */
void pure_midi_test_fail_after(size_t count);
size_t pure_midi_test_allocation_count(void);
#endif

pure_expr *mf_new(int format, int division, int resolution);
pure_expr *mf_load(char *filename);
bool mf_save(pure_expr *x, char *filename);
bool mf_free(pure_expr *mf);
pure_expr *mf_info(pure_expr *mf);
pure_expr *mf_get_track(pure_expr *mf, int number);
pure_expr *mf_get_tracks(pure_expr *mf);
bool mf_put_track(pure_expr *x, pure_expr *xs);
bool mf_put_tracks(pure_expr *x, pure_expr *xs);
