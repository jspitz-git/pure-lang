#ifndef PURE_AUDIO_TEST_API_H
#define PURE_AUDIO_TEST_API_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

bool pure_audio_checked_mul_size(size_t left, size_t right, size_t *product);
bool pure_audio_frame_bytes(unsigned bytes_per_frame, unsigned long frames,
                            size_t *bytes);

#ifdef PURE_AUDIO_TEST_SEAM
size_t pure_audio_test_allocation_delta(void);
size_t pure_audio_test_allocation_attempts(void);
bool pure_audio_test_round_pow2(size_t value, size_t *rounded);
size_t pure_audio_test_io_calls(void);
int64_t pure_audio_test_echo_int64(int64_t value);
int64_t pure_audio_test_sf_seek_roundtrip(const char *path, int64_t offset);
int pure_audio_test_print_bounds_marker(void);
#endif

#endif
