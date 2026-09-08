#include <limits.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define PURE_AUDIO_TEST_SEAM 1
#include "../audio_test_api.h"
#include "../audio.c"

static int failures;
static int checks;

#define CHECK(condition, message)                                                \
  do {                                                                           \
    ++checks;                                                                    \
    if (!(condition)) {                                                          \
      ++failures;                                                                \
      fprintf(stderr, "audio fault test failed: %s\n", message);                \
    }                                                                            \
  } while (0)

static void init_test_stream(MyStream *stream, char *storage, size_t storage_size,
                             PaSampleFormat format, int channels, int bps,
                             bool input)
{
  size_t frame_bytes = (size_t)channels * (size_t)bps;
  size_t maximum_frames = frame_bytes ? storage_size / frame_bytes : 0;
  size_t frame_capacity = 1;
  while (frame_capacity <= maximum_frames / 2)
    frame_capacity <<= 1;
  memset(stream, 0, sizeof(*stream));
  stream->as = (PaStream *)(uintptr_t)1;
  stream->sample_rate = 48000.0;
  CHECK(pthread_mutex_init(&stream->data_mutex, NULL) == 0,
        "data mutex initialization");
  if (input) {
    stream->in = 0;
    stream->out = paNoDevice;
    stream->in_format = format;
    stream->in_channels = channels;
    stream->in_bps = bps;
    stream->in_bpf = bps * channels;
    CHECK(MyRingBuffer_Init(&stream->in_buf, frame_capacity,
                            (unsigned)channels, (unsigned)bps, storage) == 0,
          "input ring initialization");
    CHECK(pthread_mutex_init(&stream->in_mutex, NULL) == 0,
          "input mutex initialization");
    CHECK(pthread_cond_init(&stream->in_cond, NULL) == 0,
          "input condition initialization");
  } else {
    stream->in = paNoDevice;
    stream->out = 0;
    stream->out_format = format;
    stream->out_channels = channels;
    stream->out_bps = bps;
    stream->out_bpf = bps * channels;
    CHECK(MyRingBuffer_Init(&stream->out_buf, frame_capacity,
                            (unsigned)channels, (unsigned)bps, storage) == 0,
          "output ring initialization");
    CHECK(pthread_mutex_init(&stream->out_mutex, NULL) == 0,
          "output mutex initialization");
    CHECK(pthread_cond_init(&stream->out_cond, NULL) == 0,
          "output condition initialization");
  }
}

static void destroy_test_stream(MyStream *stream, bool input)
{
  if (input) {
    pthread_cond_destroy(&stream->in_cond);
    pthread_mutex_destroy(&stream->in_mutex);
  } else {
    pthread_cond_destroy(&stream->out_cond);
    pthread_mutex_destroy(&stream->out_mutex);
  }
  pthread_mutex_destroy(&stream->data_mutex);
}

enum {
  CALLBACK_FRAMES = 4,
  CALLBACK_CHANNELS = 3,
  CALLBACK_SAMPLE_BYTES = 4,
  CALLBACK_GUARD_BYTES = 16,
  CALLBACK_DATA_BYTES =
    CALLBACK_FRAMES * CALLBACK_CHANNELS * CALLBACK_SAMPLE_BYTES
};

typedef struct {
  PaSampleFormat format;
  int sample_bytes;
  const char *name;
} CallbackFormat;

static const CallbackFormat callback_formats[] = {
  {paFloat32, 4, "Float32"},
  {paInt32, 4, "Int32"},
  {paInt24, 3, "Int24"},
  {paInt16, 2, "Int16"},
  {paInt8, 1, "Int8"},
  {paUInt8, 1, "UInt8"}
};

static int dispatched_format;

static int fake_get_sample_size(unsigned long format)
{
  dispatched_format = (int)format;
  return 7;
}

static void test_portaudio_dispatch(void)
{
  const pure_audio_api fake_api = {fake_get_sample_size};
  size_t format_index;
  pure_audio_test_reset_api();
  for (format_index = 0;
       format_index < sizeof(callback_formats) / sizeof(callback_formats[0]);
       ++format_index)
    CHECK(pure_audio_sample_bytes(callback_formats[format_index].format |
                                  paNonInterleaved) ==
            callback_formats[format_index].sample_bytes,
          "production dispatch uses PortAudio sample sizes");
  dispatched_format = 0;
  pure_audio_test_set_api(&fake_api);
  CHECK(pure_audio_sample_bytes(paInt16 | paNonInterleaved) == 7,
        "test dispatch injection controls sample-size query");
  CHECK(dispatched_format == (int)paInt16,
        "dispatch receives the base sample format");
  pure_audio_test_reset_api();
}

static void check_callback_case(bool condition, const CallbackFormat *format,
                                int channels, const char *layout,
                                const char *direction, const char *property)
{
  ++checks;
  if (!condition) {
    ++failures;
    fprintf(stderr,
            "audio callback test failed: %s %d-channel %s %s %s\n",
            format->name, channels, layout, direction, property);
  }
}

static size_t callback_byte_count(int frames, int channels, int sample_bytes)
{
  return (size_t)frames * (size_t)channels * (size_t)sample_bytes;
}

static void fill_callback_samples(unsigned char *samples, int frames,
                                  int channels, int sample_bytes,
                                  unsigned char seed)
{
  int frame, channel, byte;
  for (frame = 0; frame < frames; ++frame)
    for (channel = 0; channel < channels; ++channel)
      for (byte = 0; byte < sample_bytes; ++byte)
        samples[((size_t)frame * (size_t)channels + (size_t)channel) *
                (size_t)sample_bytes + (size_t)byte] =
          (unsigned char)(seed + frame * 37 + channel * 11 + byte);
}

static void interleaved_to_planar(const unsigned char *interleaved,
                                  unsigned char planar[][CALLBACK_DATA_BYTES +
                                                         2 * CALLBACK_GUARD_BYTES],
                                  void **channel_pointers, int frames,
                                  int channels, int sample_bytes)
{
  int frame, channel;
  for (channel = 0; channel < channels; ++channel) {
    memset(planar[channel], 0xa5, sizeof(planar[channel]));
    channel_pointers[channel] = planar[channel] + CALLBACK_GUARD_BYTES;
    for (frame = 0; frame < frames; ++frame)
      memcpy((unsigned char *)channel_pointers[channel] +
               (size_t)frame * (size_t)sample_bytes,
             interleaved +
               ((size_t)frame * (size_t)channels + (size_t)channel) *
                 (size_t)sample_bytes,
             (size_t)sample_bytes);
  }
}

static bool callback_channel_guards_ok(
  unsigned char planar[][CALLBACK_DATA_BYTES + 2 * CALLBACK_GUARD_BYTES],
  int frames, int channels, int sample_bytes)
{
  int channel, byte;
  const int used = frames * sample_bytes;
  for (channel = 0; channel < channels; ++channel) {
    for (byte = 0; byte < CALLBACK_GUARD_BYTES; ++byte)
      if (planar[channel][byte] != 0xa5)
        return false;
    for (byte = CALLBACK_GUARD_BYTES + used;
         byte < (int)sizeof(planar[channel]); ++byte)
      if (planar[channel][byte] != 0xa5)
        return false;
  }
  return true;
}

static bool callback_planar_matches(
  const unsigned char *interleaved,
  unsigned char planar[][CALLBACK_DATA_BYTES + 2 * CALLBACK_GUARD_BYTES],
  int frames, int channels, int sample_bytes)
{
  int frame, channel;
  for (channel = 0; channel < channels; ++channel)
    for (frame = 0; frame < frames; ++frame)
      if (memcmp(planar[channel] + CALLBACK_GUARD_BYTES +
                   (size_t)frame * (size_t)sample_bytes,
                 interleaved +
                   ((size_t)frame * (size_t)channels + (size_t)channel) *
                     (size_t)sample_bytes,
                 (size_t)sample_bytes) != 0)
        return false;
  return true;
}

static void test_callback_layout_case(const CallbackFormat *format,
                                      int channels, bool noninterleaved,
                                      bool input)
{
  unsigned char canonical[CALLBACK_DATA_BYTES];
  unsigned char storage[256] = {0};
  unsigned char interleaved[CALLBACK_GUARD_BYTES + CALLBACK_DATA_BYTES +
                            CALLBACK_GUARD_BYTES];
  unsigned char planar[CALLBACK_CHANNELS]
                      [CALLBACK_DATA_BYTES + 2 * CALLBACK_GUARD_BYTES];
  void *channel_pointers[16] = {0};
  unsigned char readback[CALLBACK_DATA_BYTES] = {0};
  const size_t bytes = callback_byte_count(CALLBACK_FRAMES, channels,
                                           format->sample_bytes);
  const char *layout = noninterleaved ? "non-interleaved" : "interleaved";
  const char *direction = input ? "input" : "output";
  PaSampleFormat callback_format = format->format |
    (noninterleaved ? paNonInterleaved : 0);
  MyStream stream;
  int result;

  fill_callback_samples(canonical, CALLBACK_FRAMES, channels,
                        format->sample_bytes, 17);
  memset(interleaved, 0xa5, sizeof(interleaved));
  memcpy(interleaved + CALLBACK_GUARD_BYTES, canonical, bytes);
  interleaved_to_planar(canonical, planar, channel_pointers, CALLBACK_FRAMES,
                        channels, format->sample_bytes);
  if (!input) {
    memset(interleaved + CALLBACK_GUARD_BYTES, 0x3c, bytes);
    for (int channel = 0; channel < channels; ++channel)
      memset(planar[channel] + CALLBACK_GUARD_BYTES, 0x3c,
             CALLBACK_FRAMES * format->sample_bytes);
  }

  init_test_stream(&stream, (char *)storage, sizeof(storage), callback_format,
                   channels, format->sample_bytes, input);
  if (!input)
    CHECK(MyRingBuffer_Write(&stream.out_buf, canonical, CALLBACK_FRAMES) ==
            CALLBACK_FRAMES,
          "callback output fixture queue write");

  result = pure_audio_test_invoke_callback(
    &stream,
    input ? (noninterleaved ? (const void *)channel_pointers :
                              interleaved + CALLBACK_GUARD_BYTES) : NULL,
    input ? NULL : (noninterleaved ? (void *)channel_pointers :
                                     interleaved + CALLBACK_GUARD_BYTES),
    CALLBACK_FRAMES);
  check_callback_case(result == paContinue, format, channels, layout,
                      direction, "callback result");
  if (input) {
    CHECK(MyRingBuffer_Read(&stream.in_buf, readback, CALLBACK_FRAMES) ==
            CALLBACK_FRAMES,
          "callback input fixture queue read");
    check_callback_case(memcmp(readback, canonical, bytes) == 0, format,
                        channels, layout, direction, "logical ordering");
  } else if (noninterleaved) {
    check_callback_case(callback_planar_matches(canonical, planar,
                                                CALLBACK_FRAMES, channels,
                                                format->sample_bytes),
                        format, channels, layout, direction,
                        "logical ordering");
  } else {
    check_callback_case(memcmp(interleaved + CALLBACK_GUARD_BYTES, canonical,
                               bytes) == 0,
                        format, channels, layout, direction,
                        "logical ordering");
  }
  if (noninterleaved)
    check_callback_case(callback_channel_guards_ok(planar, CALLBACK_FRAMES,
                                                   channels,
                                                   format->sample_bytes),
                        format, channels, layout, direction, "channel guards");
  else
    check_callback_case(
      memcmp(interleaved, "\xa5\xa5\xa5\xa5\xa5\xa5\xa5\xa5"
                          "\xa5\xa5\xa5\xa5\xa5\xa5\xa5\xa5",
             CALLBACK_GUARD_BYTES) == 0 &&
      memcmp(interleaved + CALLBACK_GUARD_BYTES + bytes,
             "\xa5\xa5\xa5\xa5\xa5\xa5\xa5\xa5"
             "\xa5\xa5\xa5\xa5\xa5\xa5\xa5\xa5",
             CALLBACK_GUARD_BYTES) == 0,
      format, channels, layout, direction, "buffer guards");
  destroy_test_stream(&stream, input);
}

static void test_callback_layouts(void)
{
  size_t format_index;
  int channels;
  for (format_index = 0;
       format_index < sizeof(callback_formats) / sizeof(callback_formats[0]);
       ++format_index)
    for (channels = 1; channels <= CALLBACK_CHANNELS; ++channels) {
      test_callback_layout_case(&callback_formats[format_index], channels,
                                false, true);
      test_callback_layout_case(&callback_formats[format_index], channels,
                                true, true);
      test_callback_layout_case(&callback_formats[format_index], channels,
                                false, false);
      test_callback_layout_case(&callback_formats[format_index], channels,
                                true, false);
    }
}

static void test_callback_silence_case(const CallbackFormat *format,
                                       int channels, bool noninterleaved)
{
  enum { SILENCE_FRAMES = 3 };
  unsigned char first_frame[CALLBACK_CHANNELS * CALLBACK_SAMPLE_BYTES];
  unsigned char expected[CALLBACK_DATA_BYTES];
  unsigned char storage[256] = {0};
  unsigned char interleaved[CALLBACK_GUARD_BYTES + CALLBACK_DATA_BYTES +
                            CALLBACK_GUARD_BYTES];
  unsigned char planar[CALLBACK_CHANNELS]
                      [CALLBACK_DATA_BYTES + 2 * CALLBACK_GUARD_BYTES];
  void *channel_pointers[16] = {0};
  const size_t frame_bytes = callback_byte_count(1, channels,
                                                 format->sample_bytes);
  const size_t bytes = callback_byte_count(SILENCE_FRAMES, channels,
                                           format->sample_bytes);
  const unsigned char silence = format->format == paUInt8 ? 128 : 0;
  const char *layout = noninterleaved ? "non-interleaved" : "interleaved";
  MyStream stream;

  fill_callback_samples(first_frame, 1, channels, format->sample_bytes, 73);
  memcpy(expected, first_frame, frame_bytes);
  memset(expected + frame_bytes, silence, bytes - frame_bytes);
  memset(interleaved, 0xa5, sizeof(interleaved));
  memset(interleaved + CALLBACK_GUARD_BYTES, 0x3c, bytes);
  interleaved_to_planar(expected, planar, channel_pointers, SILENCE_FRAMES,
                        channels, format->sample_bytes);
  for (int channel = 0; channel < channels; ++channel)
    memset(planar[channel] + CALLBACK_GUARD_BYTES, 0x3c,
           SILENCE_FRAMES * format->sample_bytes);

  init_test_stream(&stream, (char *)storage, sizeof(storage),
                   format->format | (noninterleaved ? paNonInterleaved : 0),
                   channels, format->sample_bytes, false);
  CHECK(MyRingBuffer_Write(&stream.out_buf, first_frame, 1) == 1,
        "callback silence fixture queue write");
  CHECK(pure_audio_test_invoke_callback(
          &stream, NULL,
          noninterleaved ? (void *)channel_pointers :
                           interleaved + CALLBACK_GUARD_BYTES,
          SILENCE_FRAMES) == paContinue,
        "callback silence result");
  check_callback_case(pure_audio_test_consumed_frames(&stream) == 1, format,
                      channels, layout, "output", "measured consumption");
  if (noninterleaved)
    check_callback_case(callback_planar_matches(expected, planar,
                                                SILENCE_FRAMES, channels,
                                                format->sample_bytes),
                        format, channels, layout, "output", "encoded silence");
  else
    check_callback_case(memcmp(interleaved + CALLBACK_GUARD_BYTES, expected,
                               bytes) == 0,
                        format, channels, layout, "output", "encoded silence");
  if (noninterleaved)
    check_callback_case(callback_channel_guards_ok(planar, SILENCE_FRAMES,
                                                   channels,
                                                   format->sample_bytes),
                        format, channels, layout, "output", "channel guards");
  CHECK(pure_audio_test_invoke_callback(
          &stream, NULL,
          noninterleaved ? (void *)channel_pointers :
                           interleaved + CALLBACK_GUARD_BYTES,
          SILENCE_FRAMES) == paContinue,
        "second callback underflow result");
  check_callback_case(pure_audio_test_consumed_frames(&stream) == 1, format,
                      channels, layout, "output",
                      "underflow is not counted as consumption");
  destroy_test_stream(&stream, false);
}

static void test_callback_silence(void)
{
  size_t format_index;
  int channels;
  for (format_index = 0;
       format_index < sizeof(callback_formats) / sizeof(callback_formats[0]);
       ++format_index)
    for (channels = 1; channels <= CALLBACK_CHANNELS; ++channels) {
      test_callback_silence_case(&callback_formats[format_index], channels,
                                 false);
      test_callback_silence_case(&callback_formats[format_index], channels,
                                 true);
    }
}

static void test_callback_frame_alignment(void)
{
  enum { FRAMES = 512, CHANNELS = 3, SAMPLE_BYTES = 4 };
  unsigned char storage[8192] = {0};
  unsigned char first[FRAMES * CHANNELS * SAMPLE_BYTES];
  unsigned char second[FRAMES * CHANNELS * SAMPLE_BYTES];
  unsigned char readback[FRAMES * CHANNELS * SAMPLE_BYTES];
  MyStream stream;
  const long frame_bytes = CHANNELS * SAMPLE_BYTES;
  const long block_bytes = FRAMES * frame_bytes;

  fill_callback_samples(first, FRAMES, CHANNELS, SAMPLE_BYTES, 13);
  fill_callback_samples(second, FRAMES, CHANNELS, SAMPLE_BYTES, 101);
  init_test_stream(&stream, (char *)storage, sizeof(storage), paFloat32,
                   CHANNELS, SAMPLE_BYTES, true);
  CHECK(pure_audio_test_invoke_callback(&stream, first, NULL, FRAMES) ==
          paContinue,
        "first 6144-byte callback accepted");
  CHECK(pure_audio_test_invoke_callback(&stream, second, NULL, FRAMES) ==
          paContinue,
        "second 6144-byte callback accepted");
  CHECK(MyRingBuffer_GetReadAvailable(&stream.in_buf) == FRAMES,
        "6144-byte input queue capacity is exactly 512 complete frames");
  CHECK(pure_audio_test_input_accepted_frames(&stream) == 2 * FRAMES,
        "input callback acceptance is counted in whole frames");
  CHECK(pure_audio_test_input_dropped_frames(&stream) == FRAMES,
        "input callback overflow drops a whole-frame block");
  CHECK(read_audio_stream(&stream, NULL, readback, FRAMES) == FRAMES,
        "callback input returns one complete capacity");
  CHECK(memcmp(readback, second, (size_t)block_bytes) == 0,
        "input overflow drops the older whole-frame block without channel shift");
  CHECK(MyRingBuffer_GetReadAvailable(&stream.in_buf) == 0,
        "callback input queue has no partial-frame residue");
  destroy_test_stream(&stream, true);
}

static void test_noninterleaved_null_channels(void)
{
  unsigned char storage[256] = {0};
  unsigned char channel[CALLBACK_GUARD_BYTES + CALLBACK_DATA_BYTES +
                        CALLBACK_GUARD_BYTES];
  void *channels[2] = {channel + CALLBACK_GUARD_BYTES, NULL};
  MyStream stream;

  memset(channel, 0xa5, sizeof(channel));
  init_test_stream(&stream, (char *)storage, sizeof(storage),
                   paInt16 | paNonInterleaved, 2, 2, true);
  CHECK(pure_audio_test_invoke_callback(&stream, channels, NULL,
                                        CALLBACK_FRAMES) == paAbort,
        "non-interleaved input rejects a null channel");
  CHECK(MyRingBuffer_GetReadAvailable(&stream.in_buf) == 0,
        "rejected input does not enter the queue");
  for (size_t byte = 0; byte < sizeof(channel); ++byte)
    CHECK(channel[byte] == 0xa5,
          "rejected non-interleaved input preserves channel guards");
  destroy_test_stream(&stream, true);

  init_test_stream(&stream, (char *)storage, sizeof(storage),
                   paInt16 | paNonInterleaved, 2, 2, false);
  CHECK(pure_audio_test_invoke_callback(&stream, NULL, channels,
                                        CALLBACK_FRAMES) == paAbort,
        "non-interleaved output rejects a null channel");
  CHECK(pure_audio_test_consumed_frames(&stream) == 0,
        "rejected output does not increment consumption");
  for (size_t byte = 0; byte < sizeof(channel); ++byte)
    CHECK(channel[byte] == 0xa5,
          "rejected non-interleaved output preserves channel guards");
  destroy_test_stream(&stream, false);
}

static void test_unsupported_callback_formats(void)
{
  unsigned char storage[64] = {0};
  unsigned char samples[CALLBACK_DATA_BYTES] = {0};
  MyStream stream;

  init_test_stream(&stream, (char *)storage, sizeof(storage), paCustomFormat,
                   1, 1, true);
  CHECK(pure_audio_test_invoke_callback(&stream, samples, NULL,
                                        CALLBACK_FRAMES) == paAbort,
        "custom callback format fails closed");
  CHECK(MyRingBuffer_GetReadAvailable(&stream.in_buf) == 0,
        "custom callback format does not enter the queue");
  destroy_test_stream(&stream, true);

  init_test_stream(&stream, (char *)storage, sizeof(storage),
                   paInt16 | paInt8, 1, 2, true);
  CHECK(pure_audio_test_invoke_callback(&stream, samples, NULL,
                                        CALLBACK_FRAMES) == paAbort,
        "multiple callback format bits fail closed");
  CHECK(MyRingBuffer_GetReadAvailable(&stream.in_buf) == 0,
        "ambiguous callback format does not enter the queue");
  destroy_test_stream(&stream, true);
}

static void test_int16_conversion(void)
{
  static const int source[] = {INT16_MIN, 0, INT16_MAX};
  static const int16_t raw[] = {INT16_MIN, 0, INT16_MAX};
  char storage[64] = {0};
  MyStream stream;
  int converted[3] = {1, 1, 1};

  init_test_stream(&stream, storage, sizeof(storage),
                   paInt16 | paNonInterleaved, 3, 2, false);
  CHECK(write_audio_stream_int(&stream, NULL, (int *)source, 1) == 1,
        "paInt16 write result");
  CHECK(MyRingBuffer_GetReadAvailable(&stream.out_buf) == 1,
        "paInt16 writes exactly one frame");
  CHECK(memcmp(storage, raw, sizeof(raw)) == 0, "paInt16 exact write values");
  destroy_test_stream(&stream, false);

  memset(storage, 0, sizeof(storage));
  memcpy(storage, raw, sizeof(raw));
  init_test_stream(&stream, storage, sizeof(storage),
                   paInt16 | paNonInterleaved, 3, 2, true);
  MyRingBuffer_AdvanceWriteIndex(&stream.in_buf, 1);
  CHECK(read_audio_stream_int(&stream, NULL, converted, 1) == 1,
        "paInt16 read result");
  CHECK(memcmp(converted, source, sizeof(source)) == 0,
        "paInt16 exact read values");
  destroy_test_stream(&stream, true);
}

static void test_int8_conversion(void)
{
  static const int source[] = {INT8_MIN, 0, INT8_MAX};
  static const int8_t raw[] = {INT8_MIN, 0, INT8_MAX};
  char storage[64] = {0};
  MyStream stream;
  int converted[3] = {1, 1, 1};

  init_test_stream(&stream, storage, sizeof(storage),
                   paInt8 | paNonInterleaved, 3, 1, false);
  CHECK(write_audio_stream_int(&stream, NULL, (int *)source, 1) == 1,
        "paInt8 write result");
  CHECK(MyRingBuffer_GetReadAvailable(&stream.out_buf) == 1,
        "paInt8 writes exactly one frame");
  CHECK(memcmp(storage, raw, sizeof(raw)) == 0, "paInt8 exact write values");
  destroy_test_stream(&stream, false);

  memset(storage, 0, sizeof(storage));
  memcpy(storage, raw, sizeof(raw));
  init_test_stream(&stream, storage, sizeof(storage),
                   paInt8 | paNonInterleaved, 3, 1, true);
  MyRingBuffer_AdvanceWriteIndex(&stream.in_buf, 1);
  CHECK(read_audio_stream_int(&stream, NULL, converted, 1) == 1,
        "paInt8 read result");
  CHECK(memcmp(converted, source, sizeof(source)) == 0,
        "paInt8 exact read values");
  destroy_test_stream(&stream, true);
}

static void test_uint8_conversion(void)
{
  static const int source[] = {0, 128, UINT8_MAX};
  static const uint8_t raw[] = {0, 128, UINT8_MAX};
  char storage[64] = {0};
  MyStream stream;
  int converted[3] = {1, 1, 1};

  init_test_stream(&stream, storage, sizeof(storage),
                   paUInt8 | paNonInterleaved, 3, 1, false);
  CHECK(write_audio_stream_int(&stream, NULL, (int *)source, 1) == 1,
        "paUInt8 write result");
  CHECK(MyRingBuffer_GetReadAvailable(&stream.out_buf) == 1,
        "paUInt8 writes exactly one frame");
  CHECK(memcmp(storage, raw, sizeof(raw)) == 0, "paUInt8 exact write values");
  destroy_test_stream(&stream, false);

  memset(storage, 0, sizeof(storage));
  memcpy(storage, raw, sizeof(raw));
  init_test_stream(&stream, storage, sizeof(storage),
                   paUInt8 | paNonInterleaved, 3, 1, true);
  MyRingBuffer_AdvanceWriteIndex(&stream.in_buf, 1);
  CHECK(read_audio_stream_int(&stream, NULL, converted, 1) == 1,
        "paUInt8 read result");
  CHECK(memcmp(converted, source, sizeof(source)) == 0,
        "paUInt8 exact read values");
  destroy_test_stream(&stream, true);
}

static void test_noninterleaved_int32_and_float_conversions(void)
{
  static const int integer_source[] = {INT32_MIN, 0, INT32_MAX};
  static const double double_source[] = {-1.0, 0.0, 1.0};
  static const float float_source[] = {-1.0f, 0.0f, 1.0f};
  char storage[64] = {0};
  MyStream stream;
  int integers[3] = {1, 1, 1};
  double doubles[3] = {2.0, 2.0, 2.0};

  init_test_stream(&stream, storage, sizeof(storage),
                   paInt32 | paNonInterleaved, 3, 4, false);
  CHECK(write_audio_stream_int(&stream, NULL, (int *)integer_source, 1) == 1,
        "non-interleaved paInt32 blocking write result");
  CHECK(memcmp(storage, integer_source, sizeof(integer_source)) == 0,
        "non-interleaved paInt32 blocking write stays canonical");
  destroy_test_stream(&stream, false);

  memset(storage, 0, sizeof(storage));
  memcpy(storage, integer_source, sizeof(integer_source));
  init_test_stream(&stream, storage, sizeof(storage),
                   paInt32 | paNonInterleaved, 3, 4, true);
  MyRingBuffer_AdvanceWriteIndex(&stream.in_buf, 1);
  CHECK(read_audio_stream_int(&stream, NULL, integers, 1) == 1,
        "non-interleaved paInt32 blocking read result");
  CHECK(memcmp(integers, integer_source, sizeof(integer_source)) == 0,
        "non-interleaved paInt32 blocking read stays canonical");
  destroy_test_stream(&stream, true);

  memset(storage, 0, sizeof(storage));
  init_test_stream(&stream, storage, sizeof(storage),
                   paFloat32 | paNonInterleaved, 3, 4, false);
  CHECK(write_audio_stream_double(&stream, NULL, (double *)double_source, 1) ==
          1,
        "non-interleaved paFloat32 blocking write result");
  CHECK(memcmp(storage, float_source, sizeof(float_source)) == 0,
        "non-interleaved paFloat32 blocking write stays canonical");
  destroy_test_stream(&stream, false);

  memset(storage, 0, sizeof(storage));
  memcpy(storage, float_source, sizeof(float_source));
  init_test_stream(&stream, storage, sizeof(storage),
                   paFloat32 | paNonInterleaved, 3, 4, true);
  MyRingBuffer_AdvanceWriteIndex(&stream.in_buf, 1);
  CHECK(read_audio_stream_double(&stream, NULL, doubles, 1) == 1,
        "non-interleaved paFloat32 blocking read result");
  CHECK(memcmp(doubles, double_source, sizeof(double_source)) == 0,
        "non-interleaved paFloat32 blocking read stays canonical");
  destroy_test_stream(&stream, true);
}

static void test_int24_raw_boundary(void)
{
  static const unsigned char raw[] = {0x00, 0x00, 0x80,
                                      0xff, 0xff, 0x7f};
  char storage[64] = {0};
  unsigned char converted[sizeof(raw)] = {0};
  MyStream stream;
  int numeric[2] = {0};
  size_t attempts;

  init_test_stream(&stream, storage, sizeof(storage), paInt24, 2, 3, false);
  CHECK(write_audio_stream(&stream, NULL, (void *)raw, 1) == 1,
        "paInt24 raw write result");
  CHECK(MyRingBuffer_GetReadAvailable(&stream.out_buf) == 1,
        "paInt24 raw write size");
  CHECK(memcmp(storage, raw, sizeof(raw)) == 0, "paInt24 raw bytes opaque");
  attempts = pure_audio_test_allocation_attempts();
  MyRingBuffer_Flush(&stream.out_buf);
  CHECK(write_audio_stream_int(&stream, NULL, numeric, 1) == -1,
        "paInt24 numeric write rejected");
  CHECK(MyRingBuffer_GetReadAvailable(&stream.out_buf) == 0,
        "paInt24 numeric write does not enter queue");
  CHECK(pure_audio_test_allocation_attempts() == attempts,
        "paInt24 numeric write rejected before allocation");
  destroy_test_stream(&stream, false);

  memset(storage, 0, sizeof(storage));
  memcpy(storage, raw, sizeof(raw));
  init_test_stream(&stream, storage, sizeof(storage), paInt24, 2, 3, true);
  MyRingBuffer_AdvanceWriteIndex(&stream.in_buf, 1);
  CHECK(read_audio_stream(&stream, NULL, converted, 1) == 1,
        "paInt24 raw read result");
  CHECK(memcmp(converted, raw, sizeof(raw)) == 0, "paInt24 raw read opaque");
  MyRingBuffer_Flush(&stream.in_buf);
  MyRingBuffer_Write(&stream.in_buf, raw, 1);
  attempts = pure_audio_test_allocation_attempts();
  CHECK(read_audio_stream_int(&stream, NULL, numeric, 1) == -1,
        "paInt24 numeric read rejected");
  CHECK(MyRingBuffer_GetReadAvailable(&stream.in_buf) == 1,
        "paInt24 numeric read leaves queue untouched");
  CHECK(pure_audio_test_allocation_attempts() == attempts,
        "paInt24 numeric read rejected before allocation");
  destroy_test_stream(&stream, true);
}

static void test_size_arithmetic(void)
{
  const size_t channels = 3;
  const size_t safe_frames = SIZE_MAX / channels;
  size_t bytes = 123;

  CHECK(pure_audio_checked_mul_size(safe_frames, channels, &bytes),
        "last safe size product accepted");
  CHECK(bytes == safe_frames * channels, "last safe size product exact");
  CHECK(!pure_audio_checked_mul_size(safe_frames + 1, channels, &bytes),
        "one-past-safe size product rejected");
  CHECK(!pure_audio_checked_mul_size(1, 1, NULL),
        "null product destination rejected");

  CHECK(pure_audio_frame_bytes(1, (unsigned long)INT32_MAX, &bytes),
        "INT32_MAX frame count accepted");
  CHECK(bytes == (size_t)INT32_MAX, "INT32_MAX frame count exact");
  CHECK(pure_audio_frame_bytes(1, (unsigned long)INT32_MAX + 1UL, &bytes),
        "INT32_MAX plus one frame count accepted");
  CHECK(bytes == (size_t)INT32_MAX + 1U,
        "INT32_MAX plus one frame count exact");
  CHECK(pure_audio_frame_bytes(3, (unsigned long)INT32_MAX + 1UL, &bytes),
        "opaque paInt24 byte count accepted");
  CHECK(bytes == ((size_t)INT32_MAX + 1U) * 3U,
        "opaque paInt24 byte count exact");
  CHECK(!pure_audio_frame_bytes(0, 1, &bytes),
        "zero bytes per frame rejected");

  CHECK(pure_audio_test_round_pow2(1, &bytes) && bytes == 1,
        "one is an exact ring power of two");
  CHECK(pure_audio_test_round_pow2(3, &bytes) && bytes == 4,
        "ring size rounds upward");
  CHECK(!pure_audio_test_round_pow2((size_t)LONG_MAX / 2 + 1, &bytes),
        "ring power requiring unsafe signed indices rejected");
}

static void test_ring_index_boundaries(void)
{
  const size_t safe_capacity = ((size_t)LONG_MAX + 1U) / 4U;
  const size_t unsafe_capacity = safe_capacity * 2U;
  char storage = 0;
  MyRingBuffer ring;

  CHECK(MyRingBuffer_Init(&ring, unsafe_capacity, 1, 1, &storage) == -1,
        "unsafe ring capacity rejected by actual initializer");
  CHECK(MyRingBuffer_Init(&ring, safe_capacity, 1, 1, &storage) == 0,
        "largest safe ring capacity initializes");
  CHECK(ring.frame_capacity == safe_capacity,
        "largest safe frame capacity is represented exactly");
  ring.frame_write = safe_capacity - 1;
  CHECK(MyRingBuffer_AdvanceWriteIndex(&ring, 1) == 0,
        "write index wraps without signed overflow");
  ring.frame_read = safe_capacity - 1;
  CHECK(MyRingBuffer_AdvanceReadIndex(&ring, 1) == 0,
        "read index wraps without signed overflow");
}

static void test_invalid_counts(void)
{
  char storage[64] = {0};
  MyStream stream;
  int integers[3] = {0};
  double doubles[3] = {0.0};

  init_test_stream(&stream, storage, sizeof(storage), paInt16, 1, 2, false);
  CHECK(write_audio_stream(&stream, NULL, storage, -1) == -1,
        "negative raw write rejected");
  CHECK(write_audio_stream_int(&stream, NULL, integers, -1) == -1,
        "negative integer write rejected");
  stream.out_format = paFloat32;
  stream.out_bps = 4;
  stream.out_bpf = 4;
  CHECK(write_audio_stream_double(&stream, NULL, doubles, -1) == -1,
        "negative double write rejected");
  CHECK(MyRingBuffer_GetReadAvailable(&stream.out_buf) == 0,
        "negative writes do not enter queue");
  destroy_test_stream(&stream, false);

  init_test_stream(&stream, storage, sizeof(storage), paInt16, 1, 2, true);
  CHECK(read_audio_stream(&stream, NULL, storage, -1) == -1,
        "negative raw read rejected");
  CHECK(read_audio_stream_int(&stream, NULL, integers, -1) == -1,
        "negative integer read rejected");
  stream.in_format = paFloat32;
  stream.in_bps = 4;
  stream.in_bpf = 4;
  CHECK(read_audio_stream_double(&stream, NULL, doubles, -1) == -1,
        "negative double read rejected");
  destroy_test_stream(&stream, true);
}

static void test_overflow_before_allocation_or_loop(void)
{
  char storage[64] = {0};
  MyStream stream;
  int integer = 0;
  double real = 0.0;
  const size_t attempts = pure_audio_test_allocation_attempts();

  init_test_stream(&stream, storage, sizeof(storage), paInt16, 1, 2, false);
  CHECK(write_audio_stream(&stream, NULL, storage, LONG_MAX) == -1,
        "raw write byte overflow rejected");
  CHECK(write_audio_stream_int(&stream, NULL, &integer, LONG_MAX) == -1,
        "integer write byte overflow rejected");
  stream.out_format = paFloat32;
  stream.out_bps = 4;
  stream.out_bpf = 4;
  CHECK(write_audio_stream_double(&stream, NULL, &real, LONG_MAX) == -1,
        "double write byte overflow rejected");
  CHECK(MyRingBuffer_GetReadAvailable(&stream.out_buf) == 0,
        "overflow writes do not enter queue");
  destroy_test_stream(&stream, false);

  init_test_stream(&stream, storage, sizeof(storage), paInt16, 1, 2, true);
  CHECK(read_audio_stream(&stream, NULL, storage, LONG_MAX) == -1,
        "raw read byte overflow rejected");
  CHECK(read_audio_stream_int(&stream, NULL, &integer, LONG_MAX) == -1,
        "integer read byte overflow rejected");
  stream.in_format = paFloat32;
  stream.in_bps = 4;
  stream.in_bpf = 4;
  CHECK(read_audio_stream_double(&stream, NULL, &real, LONG_MAX) == -1,
        "double read byte overflow rejected");
  destroy_test_stream(&stream, true);

  CHECK(pure_audio_test_allocation_attempts() == attempts,
        "overflow rejected before allocation");
}

int main(void)
{
  const size_t allocation_start = pure_audio_test_allocation_delta();

  test_portaudio_dispatch();
  test_callback_layouts();
  test_callback_silence();
  test_callback_frame_alignment();
  test_noninterleaved_null_channels();
  test_unsupported_callback_formats();
  test_int16_conversion();
  test_int8_conversion();
  test_uint8_conversion();
  test_noninterleaved_int32_and_float_conversions();
  test_int24_raw_boundary();
  test_size_arithmetic();
  test_ring_index_boundaries();
  test_invalid_counts();
  test_overflow_before_allocation_or_loop();
  CHECK(pure_audio_test_allocation_delta() == allocation_start,
        "zero tracked allocation delta");
  if (failures) {
    fprintf(stderr, "%d of %d audio fault checks failed\n", failures, checks);
    return 1;
  }
  printf("AUDIO_FAULT_HARNESS_OK %d checks allocation_delta=%zu\n", checks,
         pure_audio_test_allocation_delta() - allocation_start);
  return 0;
}
