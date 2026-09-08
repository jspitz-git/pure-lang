#ifndef PURE_AUDIO_TEST_API_H
#define PURE_AUDIO_TEST_API_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <portaudio.h>

bool pure_audio_checked_mul_size(size_t left, size_t right, size_t *product);
bool pure_audio_frame_bytes(unsigned bytes_per_frame, unsigned long frames,
                            size_t *bytes);

typedef struct pure_audio_api {
  int (*get_sample_size)(unsigned long format);
  PaError (*initialize)(void);
  PaError (*terminate)(void);
  PaDeviceIndex (*device_count)(void);
  PaDeviceIndex (*default_input)(void);
  PaDeviceIndex (*default_output)(void);
  const PaDeviceInfo *(*device_info)(PaDeviceIndex);
  PaError (*open)(PaStream **, const PaStreamParameters *,
                  const PaStreamParameters *, double, unsigned long,
                  PaStreamFlags, PaStreamCallback *, void *);
  PaError (*start)(PaStream *);
  PaError (*stop)(PaStream *);
  PaError (*abort)(PaStream *);
  PaError (*close)(PaStream *);
  const PaStreamInfo *(*info)(PaStream *);
  PaError (*active)(PaStream *);
  double (*cpu_load)(PaStream *);
  PaError (*finished)(PaStream *, PaStreamFinishedCallback *);
} pure_audio_api;

#ifdef PURE_AUDIO_TEST_SEAM
void pure_audio_test_set_api(const pure_audio_api *api);
void pure_audio_test_reset_api(void);
size_t pure_audio_test_allocation_delta(void);
size_t pure_audio_test_allocation_attempts(void);
bool pure_audio_test_round_pow2(size_t value, size_t *rounded);
size_t pure_audio_test_io_calls(void);
int64_t pure_audio_test_echo_int64(int64_t value);
int64_t pure_audio_test_sf_seek_roundtrip(const char *path, int64_t offset);
int pure_audio_test_print_bounds_marker(void);
int pure_audio_test_invoke_callback(void *stream, const void *input,
                                    void *output, unsigned long frames);
uint64_t pure_audio_test_consumed_frames(void *stream);
uint64_t pure_audio_test_input_accepted_frames(void *stream);
uint64_t pure_audio_test_input_dropped_frames(void *stream);
#endif

#endif
