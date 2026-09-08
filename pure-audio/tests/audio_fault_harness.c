#include <limits.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <portaudio.h>
#include <pthread.h>
#include <stdatomic.h>
#include <errno.h>

/* Track only the module's owned resources, below its allocation/init boundary.
   Pointer stack checks prove rollback reverses successful acquisitions. */
static int resource_fail_at, resource_attempt, resource_depth, resource_errors;
static bool resource_tracking;
static _Atomic int owned_sync;
static void *resource_stack[32];
static void resource_acquired(void *p)
{ if (resource_tracking) resource_stack[resource_depth++] = p; }
static void resource_released(void *p)
{
  if (resource_tracking && p &&
      (!resource_depth || resource_stack[--resource_depth] != p)) ++resource_errors;
}
static bool resource_fail(void)
{ return resource_tracking && ++resource_attempt == resource_fail_at; }
static void *tracked_malloc(size_t size)
{
  void *p = resource_fail() ? NULL : malloc(size);
  if (p) resource_acquired(p);
  return p;
}
static void tracked_free(void *p) { resource_released(p); free(p); }
static int tracked_mutex_init(pthread_mutex_t *m, const pthread_mutexattr_t *a)
{
  int error = resource_fail() ? EAGAIN : pthread_mutex_init(m, a);
  if (!error) { resource_acquired(m); ++owned_sync; }
  return error;
}
static int tracked_cond_init(pthread_cond_t *c, const pthread_condattr_t *a)
{
  int error = resource_fail() ? EAGAIN : pthread_cond_init(c, a);
  if (!error) { resource_acquired(c); ++owned_sync; }
  return error;
}
static int tracked_mutex_destroy(pthread_mutex_t *m)
{ resource_released(m); --owned_sync; return pthread_mutex_destroy(m); }
static int tracked_cond_destroy(pthread_cond_t *c)
{ resource_released(c); --owned_sync; return pthread_cond_destroy(c); }

static _Atomic unsigned wait_entries;
static _Atomic unsigned waiting_workers;
static _Thread_local unsigned worker_bit;
static _Atomic bool callback_paused, release_callback;
static _Thread_local bool pause_this_callback;
static pthread_mutex_t *callback_pause_mutex;
static int tracked_mutex_lock(pthread_mutex_t *mutex)
{
  if (pause_this_callback && mutex == callback_pause_mutex) {
    callback_paused = true;
    while (!release_callback) {
      struct timespec pause = {0, 1000000};
      nanosleep(&pause, NULL);
    }
    pause_this_callback = false;
  }
  return pthread_mutex_lock(mutex);
}
static int tracked_timedwait(pthread_cond_t *cond, pthread_mutex_t *mutex,
                             const struct timespec *deadline)
{
  ++wait_entries;
  waiting_workers |= worker_bit;
  return pthread_cond_timedwait(cond, mutex, deadline);
}

static _Atomic int lifecycle_failure, native_streams, native_closes;
static _Atomic int native_stops, native_aborts, native_queries;
static PaStreamFinishedCallback *saved_finished;
static PaStreamCallback *saved_callback;
static void *saved_data;
static PaError fake_initialize(void) { return lifecycle_failure == 1 ? paInternalError : paNoError; }
static PaError fake_terminate(void)
{
  if (lifecycle_failure == 10 || lifecycle_failure == 15) return paInternalError;
  native_streams = 0;
  return paNoError;
}
static const PaDeviceInfo *fake_device(PaDeviceIndex device)
{
  static const PaDeviceInfo info = {2, "deterministic", 0, 2, 2, .01, .01, .1, .1, 48000};
  return device == 0 && lifecycle_failure != 2 ? &info : NULL;
}
static PaError fake_open(PaStream **stream, const PaStreamParameters *in,
                         const PaStreamParameters *out, double sr,
                         unsigned long size, PaStreamFlags flags,
                         PaStreamCallback *callback, void *data)
{
  (void)in; (void)out; (void)sr; (void)size; (void)flags; (void)callback; (void)data;
  if (lifecycle_failure == 3) return paDeviceUnavailable;
  ++native_streams;
  saved_callback = callback;
  saved_data = data;
  *stream = (PaStream *)(uintptr_t)42;
  resource_acquired(*stream);
  return paNoError;
}
static const PaStreamInfo *fake_info(PaStream *stream)
{
  static const PaStreamInfo info = {1, .01, .01, 48000};
  (void)stream;
  return lifecycle_failure == 9 ? NULL : &info;
}
static PaError fake_start(PaStream *stream)
{
  (void)stream;
  if (lifecycle_failure == 14) saved_finished(saved_data);
  return lifecycle_failure == 4 ? paDeviceUnavailable : paNoError;
}
static PaError fake_stop(PaStream *stream)
{ (void)stream; ++native_stops; return lifecycle_failure == 5 || lifecycle_failure == 15 ? paInternalError : paNoError; }
static PaError fake_abort(PaStream *stream)
{ (void)stream; ++native_aborts; return lifecycle_failure == 6 || lifecycle_failure == 15 ? paInternalError : paNoError; }
static PaError fake_close(PaStream *stream)
{
  (void)stream;
  ++native_closes;
  if (lifecycle_failure == 7 || lifecycle_failure == 15) return paInternalError;
  resource_released(stream);
  --native_streams;
  return paNoError;
}

static PaDeviceIndex fake_device_count(void)
{ return lifecycle_failure == 11 ? paInternalError : 1; }
static PaDeviceIndex fake_default(void) { return 0; }
static PaError fake_active(PaStream *stream)
{ (void)stream; ++native_queries; return lifecycle_failure == 8 ? paDeviceUnavailable : (lifecycle_failure == 12 ? 0 : 1); }
static double fake_cpu(PaStream *stream) { (void)stream; return .25; }
static PaError fake_finished(PaStream *stream, PaStreamFinishedCallback *cb)
{ (void)stream; saved_finished = cb; return lifecycle_failure == 13 ? paInternalError : paNoError; }
#ifdef _WIN32
#include <process.h>
#else
#include <sys/types.h>
#include <sys/wait.h>
#endif

#define PURE_AUDIO_TEST_SEAM 1
#include "../audio_test_api.h"
#define malloc tracked_malloc
#define free tracked_free
#define pthread_mutex_init tracked_mutex_init
#define pthread_cond_init tracked_cond_init
#define pthread_mutex_destroy tracked_mutex_destroy
#define pthread_cond_destroy tracked_cond_destroy
#define pthread_mutex_lock tracked_mutex_lock
#define pthread_cond_timedwait tracked_timedwait
#include "../audio.c"
#undef malloc
#undef free
#undef pthread_mutex_init
#undef pthread_cond_init
#undef pthread_mutex_destroy
#undef pthread_cond_destroy
#undef pthread_mutex_lock
#undef pthread_cond_timedwait

static int failures;
static int checks;
static const char *test_executable;

static void use_fake_backend(void)
{
  static pure_audio_api api;
  api = pure_audio_portaudio_api;
  api.initialize = fake_initialize;
  api.terminate = fake_terminate;
  api.device_count = fake_device_count;
  api.default_input = api.default_output = fake_default;
  api.device_info = fake_device;
  api.open = fake_open;
  api.start = fake_start;
  api.stop = fake_stop;
  api.abort = fake_abort;
  api.close = fake_close;
  api.info = fake_info;
  api.active = fake_active;
  api.cpu_load = fake_cpu;
  api.finished = fake_finished;
  pure_audio_test_set_api(&api);
}

pure_expr *pure_audio_test_make_stream(int in_channels, int out_channels,
                                      int in_format, int out_format)
{
  int in[] = {0, in_channels, in_format, 0};
  int out[] = {0, out_channels, out_format, 0};
  use_fake_backend();
  if (!init_ok) start_audio();
  return open_audio_stream(in, out, 48000, 4, 0);
}

void pure_audio_test_destroy_stream(pure_expr *value)
{ close_audio_stream(value); }

#define CHECK(condition, message)                                                \
  do {                                                                           \
    ++checks;                                                                    \
    if (!(condition)) {                                                          \
      ++failures;                                                                \
      fprintf(stderr, "audio fault test failed: %s\n", message);                \
    }                                                                            \
  } while (0)

static void test_failed_start_rollback(void)
{
  int out[] = {0, 1, paInt16, 0}, error = 0;
  pure_expr *result;
  size_t baseline = pure_audio_test_allocation_delta();
  use_fake_backend();
  start_audio();
  lifecycle_failure = 4;
  result = open_audio_stream(NULL, out, 48000, 4, 0);
  CHECK(result && pure_is_int(result, &error) && error == paDeviceUnavailable,
        "failed start returns exact error without a usable stream");
  CHECK(native_streams == 0 && native_closes == 1,
        "failed start closes its native stream");
  CHECK(pure_audio_test_allocation_delta() == baseline,
        "failed start rolls back all owned resources");
  close_audio_stream(result);
  lifecycle_failure = 0;
  stop_audio();
}

static MyStream *stream_identity(pure_expr *value)
{
  pure_expr *f, *a;
  void *identity = NULL;
  pure_expr *sentry = pure_get_sentry(value);
  if (sentry && pure_is_app(sentry, &f, &a)) pure_is_pointer(a, &identity);
  return identity;
}

static void test_lifecycle_failures(void)
{
  int parameters[] = {0, 1, paInt16, 0};
  const int stages[] = {1, 2, 3, 4, 9, 11, 13, 14};
  const int errors[] = {paInternalError, paInvalidDevice, paDeviceUnavailable,
    paDeviceUnavailable, paInternalError, paInternalError, paInternalError,
    paDeviceUnavailable};
  size_t baseline = pure_audio_test_allocation_delta();
  use_fake_backend();
  for (size_t i = 0; i < sizeof(stages)/sizeof(stages[0]); ++i) {
    lifecycle_failure = stages[i] == 1 ? 1 : 0;
    start_audio();
    lifecycle_failure = stages[i];
    pure_expr *value = open_audio_stream(parameters, parameters, 48000, 4, 0);
    int error = 0;
    CHECK(value && pure_is_int(value, &error) && error == errors[i],
          "lifecycle failure returns exact error");
    CHECK(native_streams == 0 && current == NULL &&
          pure_audio_test_allocation_delta() == baseline,
          "lifecycle failure leaves zero native, descriptor, and queue resources");
    lifecycle_failure = 0;
    stop_audio();
  }
  start_audio();
  for (int device = -3; device <= 2; ++device) {
    if (device == 0) continue;
    parameters[0] = device;
    pure_expr *value = open_audio_stream(parameters, parameters, 48000, 4, 0);
    int error = 0;
    CHECK(value && pure_is_int(value, &error) && error == paInvalidDevice,
          "out-of-range explicit device rejected before descriptor allocation");
  }
  parameters[0] = fake_default();
  lifecycle_failure = 2;
  pure_expr *value = open_audio_stream(parameters, NULL, 48000, 4, 0);
  int error = 0;
  CHECK(value && pure_is_int(value, &error) && error == paInvalidDevice,
        "default device with NULL info rejected without dereference");
  lifecycle_failure = 0;
  for (int fail = 1; fail <= 6; ++fail) {
    resource_tracking = true;
    resource_fail_at = fail;
    resource_attempt = resource_depth = resource_errors = 0;
    value = open_audio_stream(parameters, parameters, 48000, 4, 0);
    CHECK(value == NULL && resource_attempt == fail,
          "each owned allocation and synchronization init failure rejects open");
    CHECK(resource_depth == 0 && resource_errors == 0,
          "rollback releases exactly initialized resources in reverse order");
    CHECK(native_streams == 0 && current == NULL &&
          pure_audio_test_allocation_delta() == baseline,
          "injected resource failure has zero resource delta");
    resource_tracking = false;
  }
  for (int stage = 3; stage <= 13; ++stage) {
    if (stage != 3 && stage != 4 && stage != 9 && stage != 13) continue;
    resource_tracking = true;
    resource_fail_at = 100;
    resource_attempt = resource_depth = resource_errors = 0;
    lifecycle_failure = stage;
    value = open_audio_stream(parameters, parameters, 48000, 4, 0);
    CHECK(value && pure_is_int(value, &error) && resource_depth == 0 &&
          resource_errors == 0 && owned_sync == 0,
          "native open/start/query/finished failure unwinds native then sync then queues");
    resource_tracking = false;
  }
  lifecycle_failure = 0;
  stop_audio();
}

static void test_aliases_and_teardown(void)
{
  int data = 0;
  double real = 0;
  size_t baseline = pure_audio_test_allocation_delta();
  for (int failure = 0; failure <= 13; ++failure) {
    if (failure && failure != 5 && failure != 6 && failure != 7 &&
        failure != 8 && failure != 10 && failure != 12) continue;
    lifecycle_failure = 0;
    pure_expr *value = pure_audio_test_make_stream(1, 1, paInt16, paInt16);
    MyStream *identity = stream_identity(value);
    CHECK(audio_stream_valid(identity) && audio_stream_info(identity, NULL) &&
          audio_stream_latencies(identity, NULL) &&
          audio_stream_cpu_load(identity, NULL) == .25,
          "open identity supports protected queries");
    pure_expr *alias = pure_sentry(pure_get_sentry(value), pure_pointer(value->data.p));
    int closes = native_closes, aborts = native_aborts;
    lifecycle_failure = failure;
    if (failure == 8 || failure == 12) {
      CHECK(audio_stream_time(identity, NULL) == -1 && !audio_stream_valid(identity),
            "negative or inactive query makes device-loss state terminal");
    }
    if (failure == 6 || failure == 10) stop_audio();
    else close_audio_stream(value);
    int queries = native_queries;
    CHECK(!audio_stream_valid(identity) && !audio_stream_info(identity, NULL) &&
          !audio_stream_latencies(identity, NULL) &&
          audio_stream_channels(identity, 1) == 0 &&
          audio_stream_channels(identity, 0) == 0 &&
          audio_stream_time(identity, NULL) == -1 &&
          audio_stream_cpu_load(identity, NULL) == -1 &&
          audio_stream_readable(identity, NULL) == 0 &&
          audio_stream_writeable(identity, NULL) == 0 &&
          audio_stream_consumed_frames(identity, NULL) == -1,
          "all stale alias query paths reject shared identity");
    CHECK(read_audio_stream(identity, NULL, &data, 1) == -1 &&
          write_audio_stream(identity, NULL, &data, 1) == -1 &&
          read_audio_stream_int(identity, NULL, &data, 1) == -1 &&
          write_audio_stream_int(identity, NULL, &data, 1) == -1 &&
          read_audio_stream_double(identity, NULL, &real, 1) == -1 &&
          write_audio_stream_double(identity, NULL, &real, 1) == -1,
          "all stale alias I/O paths reject without touching queue memory");
    close_audio_stream(alias);
    close_audio_stream(alias);
    close_audio_stream(value);
    audio_sentry(identity, NULL);
    audio_sentry(identity, NULL);
    CHECK(native_queries == queries && native_closes == closes + 1,
          "repeated alias close and finalizers never touch old native stream");
    if (failure == 5) CHECK(native_aborts == aborts + 1,
                           "failed graceful stop falls back to abort");
    if (failure == 7)
      CHECK(current && current->identity == 0 && native_streams == 1,
            "failed native close retains callback userdata with invalid identity");
    lifecycle_failure = 0;
    stop_audio();
    if (failure == 7)
      CHECK(native_closes == closes + 1,
            "native pointer is never retried after a failed consuming close");
    CHECK(!current && !native_streams && pure_audio_test_allocation_delta() == baseline,
          "stop/retry drains failed teardown resources");
    pure_expr *replacement = pure_audio_test_make_stream(1, 0, paInt16, 0);
    CHECK(stream_identity(replacement) != identity && !audio_stream_valid(identity),
          "new streams cannot resurrect stale identities after address reuse");
    close_audio_stream(replacement);
    stop_audio();
  }
}

static void test_conversion_allocation_failures(void)
{
  for (int kind = 0; kind < 4; ++kind) {
    int format = kind < 2 ? paInt16 : paFloat32;
    int sample = 99, result;
    double real = 99;
    pure_expr *value = pure_audio_test_make_stream(1, 1, format, format);
    MyStream *identity = stream_identity(value);
    size_t baseline = pure_audio_test_allocation_delta();
    resource_tracking = true;
    resource_fail_at = 1;
    resource_attempt = resource_depth = resource_errors = 0;
    if (kind == 0) result = read_audio_stream_int(identity, NULL, &sample, 1);
    else if (kind == 1) result = write_audio_stream_int(identity, NULL, &sample, 1);
    else if (kind == 2) result = read_audio_stream_double(identity, NULL, &real, 1);
    else result = write_audio_stream_double(identity, NULL, &real, 1);
    CHECK(result == -1 && resource_attempt == 1 && resource_depth == 0 &&
          resource_errors == 0 && sample == 99 && real == 99 &&
          pure_audio_test_allocation_delta() == baseline &&
          audio_stream_readable(identity, NULL) == 0 &&
          audio_stream_writeable(identity, NULL) == 4,
          "conversion allocation failure rejects before queue or caller-buffer access");
    resource_tracking = false;
    close_audio_stream(value);
    stop_audio();
  }
}

static void test_foreign_sentry_rejected(void)
{
  pure_expr *value = pure_audio_test_make_stream(0, 1, 0, paInt16);
  MyStream *identity = stream_identity(value);
  pure_expr *foreign = pure_sentry(
    pure_app(pure_symbol(pure_sym("foreign_sentry")), pure_pointer(identity)),
    pure_pointer(value->data.p));
  close_audio_stream(foreign);
  CHECK(audio_stream_valid(identity),
        "foreign sentry with a matching pointer argument cannot close audio identity");
  close_audio_stream(value);
  stop_audio();
}

static void test_failed_teardown_recovery(void)
{
  size_t baseline = pure_audio_test_allocation_delta();
  pure_expr *value = pure_audio_test_make_stream(1, 1, paInt16, paInt16);
  MyStream *identity = stream_identity(value);
  int closes = native_closes, parameters[] = {0, 1, paInt16, 0}, error = 0;
  lifecycle_failure = 15;
  close_audio_stream(value);
  stop_audio();
  CHECK(current && !current->as && !current->identity &&
        !audio_stream_valid(identity) && native_closes == closes + 1 && owned_sync == 3,
        "failed stop abort close and terminate retain only invalid callback userdata");
  pure_expr *rejected = open_audio_stream(parameters, NULL, 48000, 4, 0);
  CHECK(rejected && pure_is_int(rejected, &error) && error == paInternalError,
        "failed backend termination rejects new streams with its exact error");
  lifecycle_failure = 0;
  start_audio();
  CHECK(init_ok && audio_error == paNoError && !current && !owned_sync &&
        pure_audio_test_allocation_delta() == baseline && native_closes == closes + 1,
        "one restart recovers after successful termination without retrying consumed native pointer");
  stop_audio();
}

typedef struct {
  MyStream *identity;
  _Atomic bool done;
  int result;
  bool writer, callback, close;
  int frames;
  void *userdata;
} ConcurrentOperation;

static void *run_operation(void *data)
{
  ConcurrentOperation *operation = data;
  int samples[8] = {0};
  int frames = operation->frames ? operation->frames : 1;
  worker_bit = operation->writer ? 2 : 1;
  if (operation->close) {
    audio_sentry(operation->identity, NULL);
    operation->result = 0;
  } else if (operation->callback) {
    pause_this_callback = true;
    operation->result = saved_callback(NULL, samples, 1, NULL, 0, operation->userdata);
  } else if (operation->writer)
    operation->result = write_audio_stream_int(operation->identity, NULL, samples, frames);
  else
    operation->result = read_audio_stream_int(operation->identity, NULL, samples, frames);
  operation->done = true;
  return NULL;
}

static double monotonic_seconds(void)
{
  struct timespec value;
  clock_gettime(CLOCK_MONOTONIC, &value);
  return value.tv_sec + value.tv_nsec / 1e9;
}

/* A failed bounded wait exits the isolated fault process; never leave hung
   test threads behind or turn a timeout into a successful join. */
static void bounded_wait(_Atomic bool *value, const char *message)
{
  double end = monotonic_seconds() + 2;
  while (!*value && monotonic_seconds() < end) {
    struct timespec pause = {0, 1000000};
    nanosleep(&pause, NULL);
  }
  CHECK(*value, message);
  if (!*value) exit(1);
}

static void test_concurrent_shutdown(unsigned iterations)
{
  size_t baseline = pure_audio_test_allocation_delta();
  unsigned completed = 0, callback_drains = 0;
  for (unsigned iteration = 0; iteration < iterations; ++iteration) {
    for (int trigger = 0; trigger < 6; ++trigger) {
      pthread_t reader_thread, writer_thread;
      lifecycle_failure = 0;
      pure_expr *value = pure_audio_test_make_stream(1, 1, paInt16, paInt16);
      MyStream *identity = stream_identity(value);
      ConcurrentOperation reader = {.identity = identity},
                          writer = {.identity = identity, .writer = true};
      int initial[] = {11, 22, 33, 44};
      if (trigger == 5) {
        int16_t input[] = {11, 22};
        CHECK(saved_callback(input, NULL, 2, NULL, 0, saved_data) == paContinue,
              "partial reader setup provides exactly two frames");
        reader.frames = 4;
        writer.frames = 6;
      } else
        CHECK(write_audio_stream_int(identity, NULL, initial, 4) == 4,
              "writer setup fills exactly four frames");
      unsigned before_waits = wait_entries;
      waiting_workers = 0;
      CHECK(!pthread_create(&reader_thread, NULL, run_operation, &reader) &&
            !pthread_create(&writer_thread, NULL, run_operation, &writer),
            "create blocked reader and writer");
      double deadline = monotonic_seconds() + 2;
      while (waiting_workers != 3 && monotonic_seconds() < deadline) {
        struct timespec pause = {0, 1000000}; nanosleep(&pause, NULL);
      }
      CHECK(waiting_workers == 3 && wait_entries >= before_waits + 2 && !reader.done && !writer.done,
            "both operations reached a blocked queue wait");
      if (waiting_workers != 3) exit(1);
      if (trigger == 0) stop_audio();
      if (trigger == 1 || trigger == 5) close_audio_stream(value);
      if (trigger == 2) {
        void *channels[] = {NULL};
        MyStream *v = enter_stream(identity, false);
        v->in_format |= paNonInterleaved;
        leave_stream(v, false);
        CHECK(saved_callback(channels, NULL, 1, NULL, 0, saved_data) == paAbort,
              "malformed callback reports terminal error");
      }
      if (trigger == 3) saved_finished(saved_data);
      if (trigger == 4) lifecycle_failure = 8;
      bounded_wait(&reader.done, "reader wakes within two seconds on terminal state");
      bounded_wait(&writer.done, "writer wakes within two seconds on terminal state");
      pthread_join(reader_thread, NULL);
      pthread_join(writer_thread, NULL);
      CHECK(reader.result == -1 && writer.result == -1,
            "terminal wake rejects both operations instead of reporting partial success");
      lifecycle_failure = 0;
      close_audio_stream(value);
      stop_audio();
      CHECK(!current && !native_streams && !owned_sync && pure_audio_test_allocation_delta() == baseline,
            "blocked-operation drain releases every owned resource");
      completed += 2;
    }

    pure_expr *value = pure_audio_test_make_stream(0, 1, 0, paInt16);
    MyStream *identity = stream_identity(value);
    callback_pause_mutex = &((MyStream *)saved_data)->data_mutex;
    callback_paused = release_callback = false;
    ConcurrentOperation callback = {.identity = identity, .callback = true,
                                    .userdata = saved_data};
    ConcurrentOperation closer = {.identity = identity, .close = true};
    ConcurrentOperation second_closer = {.identity = identity, .close = true};
    pthread_t callback_thread, close_thread, second_close_thread;
    CHECK(!pthread_create(&callback_thread, NULL, run_operation, &callback),
          "create callback at controlled entry boundary");
    bounded_wait(&callback_paused, "callback admitted before close");
    int closes = native_closes, stops = native_stops;
    CHECK(!pthread_create(&close_thread, NULL, run_operation, &closer),
          "create racing close");
    CHECK(!pthread_create(&second_close_thread, NULL, run_operation, &second_closer),
          "create simultaneous alias finalizer");
    double deadline = monotonic_seconds() + 2;
    while (native_stops == stops && monotonic_seconds() < deadline) {
      struct timespec pause = {0, 1000000}; nanosleep(&pause, NULL);
    }
    CHECK(native_stops == stops + 1 && !closer.done && native_closes == closes,
          "close stops production but cannot close native stream before admitted callback drains");
    release_callback = true;
    bounded_wait(&callback.done, "admitted callback drains");
    bounded_wait(&closer.done, "close completes after callback release");
    bounded_wait(&second_closer.done, "concurrent alias close completes idempotently");
    pthread_join(callback_thread, NULL);
    pthread_join(close_thread, NULL);
    pthread_join(second_close_thread, NULL);
    CHECK(callback.result == paAbort && native_closes == closes + 1 &&
          !current && !native_streams && !owned_sync && pure_audio_test_allocation_delta() == baseline,
          "callback observes terminal state and resources close exactly once after drain");
    close_audio_stream(value);
    stop_audio();
    ++callback_drains;
  }
  printf("LIFECYCLE_CONCURRENCY_OK iterations=%u waiter_completions=%u callback_drains=%u descriptors=0 native_streams=0 owned_sync=0\n",
         iterations, completed, callback_drains);
}

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
  use_fake_backend();
  stream->identity = (uintptr_t)stream;
  stream->state = STREAM_STARTED;
  register_stream(stream);
  stream->as = (PaStream *)(uintptr_t)1;
  stream->sample_rate = 48000.0;
  CHECK(pthread_mutex_init(&stream->data_mutex, NULL) == 0,
        "data mutex initialization");
  CHECK(pthread_cond_init(&stream->in_cond, NULL) == 0,
        "input condition initialization");
  CHECK(pthread_cond_init(&stream->out_cond, NULL) == 0,
        "output condition initialization");
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
  }
}

static void destroy_test_stream(MyStream *stream, bool input)
{
  pthread_mutex_lock(&registry_mutex);
  unregister_stream(stream);
  pthread_mutex_unlock(&registry_mutex);
  (void)input;
  pthread_cond_destroy(&stream->in_cond);
  pthread_cond_destroy(&stream->out_cond);
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
  pure_audio_api fake_api = pure_audio_portaudio_api;
  fake_api.get_sample_size = fake_get_sample_size;
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

static bool guarded_interleaved_ok(const unsigned char *buffer,
                                   size_t sample_bytes)
{
  size_t byte;
  for (byte = 0; byte < CALLBACK_GUARD_BYTES; ++byte)
    if (buffer[byte] != 0xa5)
      return false;
  for (byte = CALLBACK_GUARD_BYTES + sample_bytes;
       byte < 2 * CALLBACK_GUARD_BYTES + sample_bytes; ++byte)
    if (buffer[byte] != 0xa5)
      return false;
  return true;
}

static void prepare_callback_buffer(
  const unsigned char *samples, size_t bytes, int frames, int channels,
  int sample_bytes, bool noninterleaved,
  unsigned char *interleaved,
  unsigned char planar[][CALLBACK_DATA_BYTES + 2 * CALLBACK_GUARD_BYTES],
  void **channel_pointers)
{
  memset(interleaved, 0xa5,
         2 * CALLBACK_GUARD_BYTES + CALLBACK_DATA_BYTES);
  memcpy(interleaved + CALLBACK_GUARD_BYTES, samples, bytes);
  interleaved_to_planar(samples, planar, channel_pointers, frames, channels,
                        sample_bytes);
  if (!noninterleaved)
    channel_pointers[0] = interleaved + CALLBACK_GUARD_BYTES;
}

static void test_callback_input_wrap(bool noninterleaved)
{
  static const unsigned char first[] = {10, 11, 20, 21, 30, 31};
  static const unsigned char second[] = {40, 41, 50, 51, 60, 61};
  static const unsigned char retained[] = {30, 31, 40, 41,
                                           50, 51, 60, 61};
  unsigned char storage[8] = {0};
  unsigned char first_buffer[2 * CALLBACK_GUARD_BYTES + CALLBACK_DATA_BYTES];
  unsigned char second_buffer[2 * CALLBACK_GUARD_BYTES + CALLBACK_DATA_BYTES];
  unsigned char first_planar[CALLBACK_CHANNELS]
                            [CALLBACK_DATA_BYTES + 2 * CALLBACK_GUARD_BYTES];
  unsigned char second_planar[CALLBACK_CHANNELS]
                             [CALLBACK_DATA_BYTES + 2 * CALLBACK_GUARD_BYTES];
  void *first_channels[16] = {0};
  void *second_channels[16] = {0};
  unsigned char discarded[4] = {0};
  unsigned char readback[sizeof(retained)] = {0};
  MyStream stream;

  prepare_callback_buffer(first, sizeof(first), 3, 2, 1, noninterleaved,
                          first_buffer, first_planar, first_channels);
  prepare_callback_buffer(second, sizeof(second), 3, 2, 1, noninterleaved,
                          second_buffer, second_planar, second_channels);
  init_test_stream(&stream, (char *)storage, sizeof(storage),
                   paUInt8 | (noninterleaved ? paNonInterleaved : 0),
                   2, 1, true);
  CHECK(pure_audio_test_invoke_callback(
          &stream, noninterleaved ? (void *)first_channels : first_channels[0],
          NULL, 3) ==
          paContinue,
        "input wrap first callback result");
  CHECK(read_audio_stream(&stream, NULL, discarded, 2) == 2,
        "input wrap creates a partially occupied queue");
  CHECK(memcmp(discarded, first, sizeof(discarded)) == 0,
        "input wrap removes the first two distinct frames");
  CHECK(pure_audio_test_invoke_callback(
          &stream,
          noninterleaved ? (void *)second_channels : second_channels[0],
          NULL, 3) ==
          paContinue,
        "input wrap second callback result");
  CHECK(read_audio_stream(&stream, NULL, readback, 4) == 4,
        "input wrap returns four complete frames");
  CHECK(memcmp(readback, retained, sizeof(retained)) == 0,
        "input wrap preserves distinct frame and channel order");
  CHECK(pure_audio_test_input_accepted_frames(&stream) == 6,
        "input wrap accepted counter counts complete frames");
  CHECK(pure_audio_test_input_dropped_frames(&stream) == 0,
        "input wrap does not report overflow drops");
  if (noninterleaved) {
    CHECK(callback_channel_guards_ok(first_planar, 3, 2, 1),
          "input wrap first planar guards intact");
    CHECK(callback_channel_guards_ok(second_planar, 3, 2, 1),
          "input wrap second planar guards intact");
  } else {
    CHECK(guarded_interleaved_ok(first_buffer, sizeof(first)),
          "input wrap first interleaved guards intact");
    CHECK(guarded_interleaved_ok(second_buffer, sizeof(second)),
          "input wrap second interleaved guards intact");
  }
  destroy_test_stream(&stream, true);
}

static void prepare_output_buffer(
  int frames, bool noninterleaved, unsigned char *interleaved,
  unsigned char planar[][CALLBACK_DATA_BYTES + 2 * CALLBACK_GUARD_BYTES],
  void **channel_pointers)
{
  static const unsigned char zeros[CALLBACK_DATA_BYTES] = {0};
  prepare_callback_buffer(zeros, (size_t)frames * 2U, frames, 2, 1,
                          noninterleaved, interleaved, planar,
                          channel_pointers);
}

static void test_callback_output_wrap(bool noninterleaved)
{
  static const unsigned char first[] = {10, 11, 20, 21, 30, 31};
  static const unsigned char second[] = {40, 41, 50, 51, 60, 61};
  static const unsigned char retained[] = {30, 31, 40, 41,
                                           50, 51, 60, 61};
  unsigned char storage[8] = {0};
  unsigned char first_buffer[2 * CALLBACK_GUARD_BYTES + CALLBACK_DATA_BYTES];
  unsigned char second_buffer[2 * CALLBACK_GUARD_BYTES + CALLBACK_DATA_BYTES];
  unsigned char first_planar[CALLBACK_CHANNELS]
                            [CALLBACK_DATA_BYTES + 2 * CALLBACK_GUARD_BYTES];
  unsigned char second_planar[CALLBACK_CHANNELS]
                             [CALLBACK_DATA_BYTES + 2 * CALLBACK_GUARD_BYTES];
  void *first_channels[16] = {0};
  void *second_channels[16] = {0};
  MyStream stream;

  prepare_output_buffer(2, noninterleaved, first_buffer, first_planar,
                        first_channels);
  prepare_output_buffer(4, noninterleaved, second_buffer, second_planar,
                        second_channels);
  init_test_stream(&stream, (char *)storage, sizeof(storage),
                   paUInt8 | (noninterleaved ? paNonInterleaved : 0),
                   2, 1, false);
  CHECK(write_audio_stream(&stream, NULL, (void *)first, 3) == 3,
        "output wrap first queue write");
  CHECK(pure_audio_test_invoke_callback(
          &stream, NULL,
          noninterleaved ? (void *)first_channels : first_channels[0], 2) ==
          paContinue,
        "output wrap first callback result");
  if (noninterleaved)
    CHECK(callback_planar_matches(first, first_planar, 2, 2, 1),
          "output wrap first planar frames preserve order");
  else
    CHECK(memcmp(first_buffer + CALLBACK_GUARD_BYTES, first, 4) == 0,
          "output wrap first interleaved frames preserve order");
  CHECK(write_audio_stream(&stream, NULL, (void *)second, 3) == 3,
        "output wrap split queue write");
  CHECK(pure_audio_test_invoke_callback(
          &stream, NULL,
          noninterleaved ? (void *)second_channels : second_channels[0], 4) ==
          paContinue,
        "output wrap second callback result");
  if (noninterleaved)
    CHECK(callback_planar_matches(retained, second_planar, 4, 2, 1),
          "output wrap planar scatter preserves retained order");
  else
    CHECK(memcmp(second_buffer + CALLBACK_GUARD_BYTES, retained,
                 sizeof(retained)) == 0,
          "output wrap split copy preserves retained order");
  CHECK(pure_audio_test_consumed_frames(&stream) == 6,
        "output wrap consumed counter counts transferred frames");
  CHECK(MyRingBuffer_GetReadAvailable(&stream.out_buf) == 0,
        "output wrap leaves no queued frames");
  if (noninterleaved) {
    CHECK(callback_channel_guards_ok(first_planar, 2, 2, 1),
          "output wrap first planar guards intact");
    CHECK(callback_channel_guards_ok(second_planar, 4, 2, 1),
          "output wrap second planar guards intact");
  } else {
    CHECK(guarded_interleaved_ok(first_buffer, 4),
          "output wrap first interleaved guards intact");
    CHECK(guarded_interleaved_ok(second_buffer, sizeof(retained)),
          "output wrap second interleaved guards intact");
  }
  destroy_test_stream(&stream, false);
}

static void test_partially_occupied_input_overflow(void)
{
  static const unsigned char first[] = {10, 11, 20, 21, 30, 31};
  static const unsigned char second[] = {40, 41, 50, 51, 60, 61};
  static const unsigned char retained[] = {30, 31, 40, 41,
                                           50, 51, 60, 61};
  unsigned char storage[8] = {0};
  unsigned char first_buffer[2 * CALLBACK_GUARD_BYTES + CALLBACK_DATA_BYTES];
  unsigned char second_buffer[2 * CALLBACK_GUARD_BYTES + CALLBACK_DATA_BYTES];
  unsigned char planar[CALLBACK_CHANNELS]
                      [CALLBACK_DATA_BYTES + 2 * CALLBACK_GUARD_BYTES];
  void *first_channels[16] = {0};
  void *second_channels[16] = {0};
  unsigned char readback[sizeof(retained)] = {0};
  MyStream stream;

  prepare_callback_buffer(first, sizeof(first), 3, 2, 1, false,
                          first_buffer, planar, first_channels);
  prepare_callback_buffer(second, sizeof(second), 3, 2, 1, false,
                          second_buffer, planar, second_channels);
  init_test_stream(&stream, (char *)storage, sizeof(storage), paUInt8,
                   2, 1, true);
  CHECK(pure_audio_test_invoke_callback(&stream, first_channels[0], NULL, 3) ==
          paContinue,
        "partial overflow first callback result");
  CHECK(pure_audio_test_invoke_callback(&stream, second_channels[0], NULL, 3) ==
          paContinue,
        "partial overflow second callback result");
  CHECK(read_audio_stream(&stream, NULL, readback, 4) == 4,
        "partial overflow returns one complete capacity");
  CHECK(memcmp(readback, retained, sizeof(retained)) == 0,
        "partial overflow drops only the two oldest distinct frames");
  CHECK(pure_audio_test_input_accepted_frames(&stream) == 6,
        "partial overflow accepted counter counts both callbacks");
  CHECK(pure_audio_test_input_dropped_frames(&stream) == 2,
        "partial overflow dropped counter counts complete frames");
  CHECK(guarded_interleaved_ok(first_buffer, sizeof(first)) &&
        guarded_interleaved_ok(second_buffer, sizeof(second)),
        "partial overflow preserves callback guards");
  destroy_test_stream(&stream, true);
}

static void test_oversized_callback_prefix_discard(bool noninterleaved)
{
  static const unsigned char samples[] = {10, 11, 20, 21, 30, 31,
                                          40, 41, 50, 51, 60, 61};
  static const unsigned char retained[] = {30, 31, 40, 41,
                                           50, 51, 60, 61};
  unsigned char storage[8] = {0};
  unsigned char buffer[2 * CALLBACK_GUARD_BYTES + CALLBACK_DATA_BYTES];
  unsigned char planar[CALLBACK_CHANNELS]
                      [CALLBACK_DATA_BYTES + 2 * CALLBACK_GUARD_BYTES];
  void *channels[16] = {0};
  unsigned char readback[sizeof(retained)] = {0};
  MyStream stream;

  prepare_callback_buffer(samples, sizeof(samples), 6, 2, 1,
                          noninterleaved, buffer, planar, channels);
  init_test_stream(&stream, (char *)storage, sizeof(storage),
                   paUInt8 | (noninterleaved ? paNonInterleaved : 0),
                   2, 1, true);
  CHECK(pure_audio_test_invoke_callback(
          &stream, noninterleaved ? (void *)channels : channels[0], NULL, 6) ==
          paContinue,
        "oversized callback result");
  CHECK(read_audio_stream(&stream, NULL, readback, 4) == 4,
        "oversized callback retains one complete capacity");
  CHECK(memcmp(readback, retained, sizeof(retained)) == 0,
        "oversized callback discards its oldest distinct prefix");
  CHECK(pure_audio_test_input_accepted_frames(&stream) == 4,
        "oversized callback accepted counter is capacity-bounded");
  CHECK(pure_audio_test_input_dropped_frames(&stream) == 2,
        "oversized callback dropped counter counts prefix frames");
  if (noninterleaved)
    CHECK(callback_channel_guards_ok(planar, 6, 2, 1),
          "oversized planar callback guards intact");
  else
    CHECK(guarded_interleaved_ok(buffer, sizeof(samples)),
          "oversized interleaved callback guards intact");
  destroy_test_stream(&stream, true);
}

static void test_callback_wrap_and_overflow_sequences(void)
{
  test_callback_input_wrap(false);
  test_callback_input_wrap(true);
  test_callback_output_wrap(false);
  test_callback_output_wrap(true);
  test_partially_occupied_input_overflow();
  test_oversized_callback_prefix_discard(false);
  test_oversized_callback_prefix_discard(true);
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

static int run_invalid_noninterleaved_probe(const char *probe)
{
  MyStream stream;
  bool output = strncmp(probe, "output-", 7) == 0;
  const char *kind = output ? probe + 7 : probe + 6;
  memset(&stream, 0, sizeof(stream));
  stream.as = (PaStream *)(uintptr_t)1;
  stream.in = output ? paNoDevice : 0;
  stream.out = output ? 0 : paNoDevice;
  stream.in_format = stream.out_format = paInt16 | paNonInterleaved;
  stream.in_channels = stream.out_channels = 1;
  stream.in_bps = stream.out_bps = 2;
  stream.in_bpf = stream.out_bpf = 2;
  stream.in_buf.channels = stream.out_buf.channels = 1;
  stream.in_buf.sample_bytes = stream.out_buf.sample_bytes = 2;

  if (strcmp(kind, "format") == 0) {
    if (output)
      stream.out_format = paCustomFormat | paNonInterleaved;
    else
      stream.in_format = paCustomFormat | paNonInterleaved;
  } else if (strcmp(kind, "channels") == 0) {
    if (output) {
      stream.out_channels = INT_MAX;
      stream.out_bpf = INT_MAX;
    } else {
      stream.in_channels = INT_MAX;
      stream.in_bpf = INT_MAX;
    }
  } else if (strcmp(kind, "queue") == 0) {
    if (output)
      stream.out_buf.channels = 2;
    else
      stream.in_buf.channels = 2;
  } else
    return 2;

  return pure_audio_test_invoke_callback(&stream,
           output ? NULL : (const void *)(uintptr_t)1,
           output ? (void *)(uintptr_t)1 : NULL, 1) == paAbort ? 0 : 3;
}

static int spawn_invalid_noninterleaved_probe(const char *probe)
{
#ifdef _WIN32
  const char *arguments[] = {test_executable, "--invalid-ni-probe", probe,
                             NULL};
  return (int)_spawnv(_P_WAIT, test_executable, arguments);
#else
  pid_t child = fork();
  int status;
  if (child == 0)
    _exit(run_invalid_noninterleaved_probe(probe));
  if (child < 0 || waitpid(child, &status, 0) < 0)
    return -1;
  return WIFEXITED(status) ? WEXITSTATUS(status) : -1;
#endif
}

static void test_noninterleaved_metadata_precedes_pointer_access(void)
{
  CHECK(spawn_invalid_noninterleaved_probe("input-format") == 0,
        "invalid non-interleaved format rejects before pointer-array access");
  CHECK(spawn_invalid_noninterleaved_probe("input-channels") == 0,
        "unbounded non-interleaved channels reject before pointer-array access");
  CHECK(spawn_invalid_noninterleaved_probe("input-queue") == 0,
        "inconsistent non-interleaved queue rejects before pointer-array access");
  CHECK(spawn_invalid_noninterleaved_probe("output-format") == 0,
        "invalid non-interleaved output format rejects before pointer-array access");
  CHECK(spawn_invalid_noninterleaved_probe("output-channels") == 0,
        "unbounded non-interleaved output channels reject before pointer-array access");
  CHECK(spawn_invalid_noninterleaved_probe("output-queue") == 0,
        "inconsistent non-interleaved output queue rejects before pointer-array access");
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

int main(int argc, char **argv)
{
  const size_t allocation_start = pure_audio_test_allocation_delta();

  if (argc == 3 && strcmp(argv[1], "--invalid-ni-probe") == 0)
    return run_invalid_noninterleaved_probe(argv[2]);
  test_executable = argv[0];

  pure_interp *interpreter = pure_create_interp(0, NULL);
  test_failed_start_rollback();
  test_lifecycle_failures();
  test_aliases_and_teardown();
  test_conversion_allocation_failures();
  test_foreign_sentry_rejected();
  test_failed_teardown_recovery();
  test_concurrent_shutdown(getenv("PURE_AUDIO_STRESS_ITERATIONS") ?
    (unsigned)strtoul(getenv("PURE_AUDIO_STRESS_ITERATIONS"), NULL, 10) : 10);

  test_portaudio_dispatch();
  test_callback_layouts();
  test_callback_silence();
  test_callback_frame_alignment();
  test_callback_wrap_and_overflow_sequences();
  test_noninterleaved_null_channels();
  test_unsupported_callback_formats();
  test_noninterleaved_metadata_precedes_pointer_access();
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
  pure_delete_interp(interpreter);
  if (failures) {
    fprintf(stderr, "%d of %d audio fault checks failed\n", failures, checks);
    return 1;
  }
  printf("AUDIO_FAULT_HARNESS_OK %d checks allocation_delta=%zu\n", checks,
         pure_audio_test_allocation_delta() - allocation_start);
  return 0;
}
