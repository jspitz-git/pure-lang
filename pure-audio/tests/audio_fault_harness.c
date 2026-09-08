#include <limits.h>
#include <stdint.h>
#include <stdio.h>
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
  memset(stream, 0, sizeof(*stream));
  stream->as = (PaStream *)(uintptr_t)1;
  if (input) {
    stream->in = 0;
    stream->out = paNoDevice;
    stream->in_format = format;
    stream->in_channels = channels;
    stream->in_bps = bps;
    stream->in_bpf = bps * channels;
    CHECK(MyRingBuffer_Init(&stream->in_buf, (long)storage_size, storage) == 0,
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
    CHECK(MyRingBuffer_Init(&stream->out_buf, (long)storage_size, storage) == 0,
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
}

static void test_int16_conversion(void)
{
  static const int source[] = {INT16_MIN, 0, INT16_MAX};
  static const int16_t raw[] = {INT16_MIN, 0, INT16_MAX};
  char storage[64] = {0};
  MyStream stream;
  int converted[3] = {1, 1, 1};

  init_test_stream(&stream, storage, sizeof(storage), paInt16, 3, 2, false);
  CHECK(write_audio_stream_int(&stream, NULL, (int *)source, 1) == 1,
        "paInt16 write result");
  CHECK(MyRingBuffer_GetReadAvailable(&stream.out_buf) == (long)sizeof(raw),
        "paInt16 writes exactly one frame");
  CHECK(memcmp(storage, raw, sizeof(raw)) == 0, "paInt16 exact write values");
  destroy_test_stream(&stream, false);

  memset(storage, 0, sizeof(storage));
  memcpy(storage, raw, sizeof(raw));
  init_test_stream(&stream, storage, sizeof(storage), paInt16, 3, 2, true);
  MyRingBuffer_AdvanceWriteIndex(&stream.in_buf, (long)sizeof(raw));
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

  init_test_stream(&stream, storage, sizeof(storage), paInt8, 3, 1, false);
  CHECK(write_audio_stream_int(&stream, NULL, (int *)source, 1) == 1,
        "paInt8 write result");
  CHECK(MyRingBuffer_GetReadAvailable(&stream.out_buf) == (long)sizeof(raw),
        "paInt8 writes exactly one frame");
  CHECK(memcmp(storage, raw, sizeof(raw)) == 0, "paInt8 exact write values");
  destroy_test_stream(&stream, false);

  memset(storage, 0, sizeof(storage));
  memcpy(storage, raw, sizeof(raw));
  init_test_stream(&stream, storage, sizeof(storage), paInt8, 3, 1, true);
  MyRingBuffer_AdvanceWriteIndex(&stream.in_buf, (long)sizeof(raw));
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

  init_test_stream(&stream, storage, sizeof(storage), paUInt8, 3, 1, false);
  CHECK(write_audio_stream_int(&stream, NULL, (int *)source, 1) == 1,
        "paUInt8 write result");
  CHECK(MyRingBuffer_GetReadAvailable(&stream.out_buf) == (long)sizeof(raw),
        "paUInt8 writes exactly one frame");
  CHECK(memcmp(storage, raw, sizeof(raw)) == 0, "paUInt8 exact write values");
  destroy_test_stream(&stream, false);

  memset(storage, 0, sizeof(storage));
  memcpy(storage, raw, sizeof(raw));
  init_test_stream(&stream, storage, sizeof(storage), paUInt8, 3, 1, true);
  MyRingBuffer_AdvanceWriteIndex(&stream.in_buf, (long)sizeof(raw));
  CHECK(read_audio_stream_int(&stream, NULL, converted, 1) == 1,
        "paUInt8 read result");
  CHECK(memcmp(converted, source, sizeof(source)) == 0,
        "paUInt8 exact read values");
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
  CHECK(MyRingBuffer_GetReadAvailable(&stream.out_buf) == (long)sizeof(raw),
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
  MyRingBuffer_AdvanceWriteIndex(&stream.in_buf, (long)sizeof(raw));
  CHECK(read_audio_stream(&stream, NULL, converted, 1) == 1,
        "paInt24 raw read result");
  CHECK(memcmp(converted, raw, sizeof(raw)) == 0, "paInt24 raw read opaque");
  MyRingBuffer_Flush(&stream.in_buf);
  MyRingBuffer_Write(&stream.in_buf, raw, (long)sizeof(raw));
  attempts = pure_audio_test_allocation_attempts();
  CHECK(read_audio_stream_int(&stream, NULL, numeric, 1) == -1,
        "paInt24 numeric read rejected");
  CHECK(MyRingBuffer_GetReadAvailable(&stream.in_buf) == (long)sizeof(raw),
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
  const long safe_capacity =
    (long)(((unsigned long)LONG_MAX + 1UL) / 4UL);
  const long unsafe_capacity = safe_capacity * 2;
  char storage = 0;
  MyRingBuffer ring;

  CHECK(MyRingBuffer_Init(&ring, unsafe_capacity, &storage) == -1,
        "unsafe ring capacity rejected by actual initializer");
  CHECK(MyRingBuffer_Init(&ring, safe_capacity, &storage) == 0,
        "largest safe ring capacity initializes");
  CHECK(ring.bigMask == safe_capacity * 2 - 1,
        "largest safe ring mask is representable");
  ring.writeIndex = ring.bigMask;
  CHECK(MyRingBuffer_AdvanceWriteIndex(&ring, safe_capacity) ==
          safe_capacity - 1,
        "write index wraps without signed overflow");
  ring.readIndex = ring.bigMask;
  CHECK(MyRingBuffer_AdvanceReadIndex(&ring, safe_capacity) ==
          safe_capacity - 1,
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

  test_int16_conversion();
  test_int8_conversion();
  test_uint8_conversion();
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
