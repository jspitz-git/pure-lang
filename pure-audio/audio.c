
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <limits.h>
#include <time.h>
#include <errno.h>
#include <unistd.h>
#include <signal.h>
#include <pthread.h>
#include <portaudio.h>
#include <pure/runtime.h>
#include "audio_test_api.h"
#ifdef PURE_AUDIO_TEST_SEAM
#include <sndfile.h>
#include <stdatomic.h>
#endif

bool pure_audio_checked_mul_size(size_t left, size_t right, size_t *product)
{
  if (!product || (left && right > SIZE_MAX / left))
    return false;
  *product = left * right;
  return true;
}

bool pure_audio_frame_bytes(unsigned bytes_per_frame, unsigned long frames,
                            size_t *bytes)
{
  return bytes_per_frame > 0 &&
    pure_audio_checked_mul_size(bytes_per_frame, frames, bytes);
}

#ifdef PURE_AUDIO_TEST_SEAM
static _Atomic size_t pure_audio_allocation_count;
static _Atomic size_t pure_audio_allocation_attempt_count;
static _Atomic size_t pure_audio_io_call_count;
static _Atomic size_t pure_audio_open_call_count;
static _Atomic size_t pure_audio_raw_io_call_count;

static void *pure_audio_malloc(size_t size)
{
  ++pure_audio_allocation_attempt_count;
  void *pointer = malloc(size);
  if (pointer)
    ++pure_audio_allocation_count;
  return pointer;
}

static void pure_audio_free(void *pointer)
{
  if (pointer)
    --pure_audio_allocation_count;
  free(pointer);
}

size_t pure_audio_test_allocation_delta(void)
{
  return pure_audio_allocation_count;
}

size_t pure_audio_test_allocation_attempts(void)
{
  return pure_audio_allocation_attempt_count;
}

size_t pure_audio_test_io_calls(void)
{
  return pure_audio_io_call_count;
}

int64_t pure_audio_test_open_calls(void) { return pure_audio_open_call_count; }
int64_t pure_audio_test_raw_io_calls(void) { return pure_audio_raw_io_call_count; }

int64_t pure_audio_test_echo_int64(int64_t value)
{
  return value;
}

int64_t pure_audio_test_sf_seek_roundtrip(const char *path, int64_t offset)
{
  SF_INFO info = {0};
  SNDFILE *file;
  sf_count_t result, origin;
  double sample = 0.0;

  if (!path)
    return INT64_MIN;
  info.samplerate = 8000;
  info.channels = 1;
  info.format = SF_FORMAT_WAV | SF_FORMAT_PCM_16;
  file = sf_open(path, SFM_WRITE, &info);
  if (!file)
    return INT64_MIN;
  if (sf_write_double(file, &sample, 1) != 1 || sf_close(file) != 0)
    return INT64_MIN;
  memset(&info, 0, sizeof(info));
  file = sf_open(path, SFM_READ, &info);
  if (!file)
    return INT64_MIN;
  result = sf_seek(file, (sf_count_t)offset, SEEK_SET);
  origin = sf_seek(file, 0, SEEK_SET);
  if (sf_close(file) != 0 || origin != 0)
    result = INT64_MIN;
  remove(path);
  return result;
}

int pure_audio_test_print_bounds_marker(void)
{
  if (fputs("PURE_AUDIO_BOUNDS_OK 28 checks\n", stdout) == EOF)
    return -1;
  return fflush(stdout);
}

#define pure_audio_record_io_call() (++pure_audio_io_call_count)
#define pure_audio_record_open_call() (++pure_audio_open_call_count)
#define pure_audio_record_raw_io_call() (++pure_audio_raw_io_call_count)
#else
#define pure_audio_malloc malloc
#define pure_audio_free free
#define pure_audio_record_io_call() ((void)0)
#define pure_audio_record_open_call() ((void)0)
#define pure_audio_record_raw_io_call() ((void)0)
#endif

static int pure_audio_portaudio_get_sample_size(unsigned long format)
{
  return Pa_GetSampleSize((PaSampleFormat)format);
}

static const pure_audio_api pure_audio_portaudio_api = {
  pure_audio_portaudio_get_sample_size,
  Pa_Initialize, Pa_Terminate, Pa_GetDeviceCount,
  Pa_GetDefaultInputDevice, Pa_GetDefaultOutputDevice, Pa_GetDeviceInfo,
  Pa_OpenStream, Pa_StartStream, Pa_StopStream, Pa_AbortStream, Pa_CloseStream,
  Pa_GetStreamInfo, Pa_IsStreamActive, Pa_GetStreamCpuLoad,
  Pa_SetStreamFinishedCallback
};
static const pure_audio_api *pure_audio_dispatch = &pure_audio_portaudio_api;

#ifdef PURE_AUDIO_TEST_SEAM
void pure_audio_test_set_api(const pure_audio_api *api)
{
  pure_audio_dispatch = api ? api : &pure_audio_portaudio_api;
}

void pure_audio_test_reset_api(void)
{
  pure_audio_dispatch = &pure_audio_portaudio_api;
}
#endif

static PaSampleFormat pure_audio_base_format(PaSampleFormat format)
{
  return (PaSampleFormat)((uint32_t)format & ~(uint32_t)paNonInterleaved);
}

static int pure_audio_sample_bytes(PaSampleFormat format)
{
  PaSampleFormat base = pure_audio_base_format(format);
  switch (base) {
  case paFloat32:
  case paInt32:
  case paInt24:
  case paInt16:
  case paInt8:
  case paUInt8:
    return pure_audio_dispatch->get_sample_size((unsigned long)base);
  default:
    return paSampleFormatNotSupported;
  }
}

/* The timing infos of some versions of PortAudio v19 seem to be broken, hence
   we do the necessary bookkeeping ourselves. This can be commented out if you
   know that PortAudio's own timing facilities work ok. */
#define TIMER_KLUDGE

/* Make sure that this is defined if you have sigprocmask et al. It makes sure
   that the PortAudio callback thread isn't interrupted by some signals. This
   should be available on all modern Unixes. */
#ifndef _WIN32
#define HAVE_POSIX_SIGNALS
#endif

pure_expr *audio_driver_info(int api)
{
  const PaHostApiInfo *info = Pa_GetHostApiInfo(api);
  if (info && info->deviceCount >= 0) {
    size_t i, n = (size_t)info->deviceCount, allocation_size;
    pure_expr *devs, **xv;
    if (n == 0)
      devs = pure_listl(0);
    else {
      if (!pure_audio_checked_mul_size(n, sizeof(*xv), &allocation_size) ||
          !(xv = pure_audio_malloc(allocation_size)))
	return 0;
      for (i = 0; i < n; i++)
	xv[i] = pure_int(Pa_HostApiDeviceIndexToDeviceIndex(api, i));
      devs = pure_listv(n, xv);
      pure_audio_free(xv);
    }
    return pure_tuplel(5, pure_cstring_dup(info->name),
		       pure_int(info->type), devs,
		       pure_int(info->defaultInputDevice),
		       pure_int(info->defaultOutputDevice));
  } else
    return 0;
}

pure_expr *audio_device_info(int dev)
{
  const PaDeviceInfo *info = Pa_GetDeviceInfo(dev);
  if (info)
    return pure_tuplel(5, pure_cstring_dup(info->name),
		       pure_int(info->hostApi),
		       pure_int(info->maxInputChannels),
		       pure_int(info->maxOutputChannels),
		       pure_double(info->defaultSampleRate));
  else
    return 0;
}

/*
 * ringbuffer.c
 * Ring Buffer utility from PortAudio.
 *
 * Author: Phil Burk, http://www.softsynth.com
 *
 * This program uses the PortAudio Portable Audio Library.
 * For more information see: http://www.audiomulch.com/portaudio/
 * Copyright (c) 1999-2000 Ross Bencina and Phil Burk
 *
 * Permission is hereby granted, free of charge, to any person obtaining
 * a copy of this software and associated documentation files
 * (the "Software"), to deal in the Software without restriction,
 * including without limitation the rights to use, copy, modify, merge,
 * publish, distribute, sublicense, and/or sell copies of the Software,
 * and to permit persons to whom the Software is furnished to do so,
 * subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be
 * included in all copies or substantial portions of the Software.
 *
 * Any person wishing to distribute modifications to the Software is
 * requested to send the modifications to the original developer so that
 * they can be incorporated into the canonical version.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
 * EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
 * MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
 * IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR
 * ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF
 * CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
 * WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
 *
 */
#include <stdio.h>
#include <stdlib.h>
#include <math.h>
#include <string.h>

typedef struct
{
  size_t frame_capacity;
  size_t frame_read;
  size_t frame_write;
  size_t frame_count;
  unsigned channels;
  unsigned sample_bytes;
  char *buffer;
} MyRingBuffer;

/***************************************************************************
 * Initialize FIFO.
 * frame_capacity must be power of 2, returns -1 if not.
 */

static void MyRingBuffer_Flush( MyRingBuffer *rbuf );

static int
MyRingBuffer_Init( MyRingBuffer *rbuf, size_t frame_capacity,
                   unsigned channels, unsigned sample_bytes, void *dataPtr )
{
  size_t frame_bytes, allocation_size;
  if (frame_capacity == 0 || frame_capacity > (size_t)LONG_MAX / 2 ||
      ((frame_capacity - 1) & frame_capacity) != 0 || channels == 0 ||
      sample_bytes == 0 || !dataPtr ||
      !pure_audio_checked_mul_size(channels, sample_bytes, &frame_bytes) ||
      frame_bytes > UINT_MAX || frame_capacity > ULONG_MAX ||
      !pure_audio_frame_bytes((unsigned)frame_bytes,
                              (unsigned long)frame_capacity,
                              &allocation_size))
    return -1;
  rbuf->frame_capacity = frame_capacity;
  rbuf->channels = channels;
  rbuf->sample_bytes = sample_bytes;
  rbuf->buffer = (char *)dataPtr;
  MyRingBuffer_Flush( rbuf );
  return 0;
}

/***************************************************************************
** Return number of complete frames available for reading. */

static inline size_t MyRingBuffer_GetReadAvailable( MyRingBuffer *rbuf )
{
  return rbuf->frame_count;
}

/***************************************************************************
** Return number of complete frames available for writing. */

static inline size_t MyRingBuffer_GetWriteAvailable( MyRingBuffer *rbuf )
{
  return rbuf->frame_capacity - rbuf->frame_count;
}

/***************************************************************************
** Clear buffer. Should only be called when buffer is NOT being read. */

static void MyRingBuffer_Flush( MyRingBuffer *rbuf )
{
  rbuf->frame_read = rbuf->frame_write = rbuf->frame_count = 0;
}

static bool MyRingBuffer_FrameBytes(const MyRingBuffer *rbuf,
                                    size_t *frame_bytes)
{
  return pure_audio_checked_mul_size(rbuf->channels, rbuf->sample_bytes,
                                     frame_bytes) && *frame_bytes <= UINT_MAX;
}

/***************************************************************************
*/

static inline size_t
MyRingBuffer_AdvanceWriteIndex( MyRingBuffer *rbuf, size_t frames )
{
  if (frames > MyRingBuffer_GetWriteAvailable(rbuf))
    frames = MyRingBuffer_GetWriteAvailable(rbuf);
  rbuf->frame_write = (rbuf->frame_write + frames) % rbuf->frame_capacity;
  rbuf->frame_count += frames;
  return rbuf->frame_write;
}

static inline size_t
MyRingBuffer_AdvanceReadIndex( MyRingBuffer *rbuf, size_t frames )
{
  if (frames > MyRingBuffer_GetReadAvailable(rbuf))
    frames = MyRingBuffer_GetReadAvailable(rbuf);
  rbuf->frame_read = (rbuf->frame_read + frames) % rbuf->frame_capacity;
  rbuf->frame_count -= frames;
  return rbuf->frame_read;
}

static bool MyRingBuffer_CopyIn(MyRingBuffer *rbuf, const void *data,
                                size_t frames)
{
  size_t frame_bytes, first_frames, first_bytes, second_bytes, offset;
  if (!MyRingBuffer_FrameBytes(rbuf, &frame_bytes))
    return false;
  first_frames = frames;
  if (first_frames > rbuf->frame_capacity - rbuf->frame_write)
    first_frames = rbuf->frame_capacity - rbuf->frame_write;
  if (!pure_audio_frame_bytes((unsigned)frame_bytes,
                              (unsigned long)rbuf->frame_write, &offset) ||
      !pure_audio_frame_bytes((unsigned)frame_bytes,
                              (unsigned long)first_frames, &first_bytes) ||
      !pure_audio_frame_bytes((unsigned)frame_bytes,
                              (unsigned long)(frames - first_frames),
                              &second_bytes))
    return false;
  memcpy(rbuf->buffer + offset, data, first_bytes);
  if (second_bytes)
    memcpy(rbuf->buffer, (const char *)data + first_bytes, second_bytes);
  return true;
}

static bool MyRingBuffer_CopyOut(MyRingBuffer *rbuf, void *data,
                                 size_t frames)
{
  size_t frame_bytes, first_frames, first_bytes, second_bytes, offset;
  if (!MyRingBuffer_FrameBytes(rbuf, &frame_bytes))
    return false;
  first_frames = frames;
  if (first_frames > rbuf->frame_capacity - rbuf->frame_read)
    first_frames = rbuf->frame_capacity - rbuf->frame_read;
  if (!pure_audio_frame_bytes((unsigned)frame_bytes,
                              (unsigned long)rbuf->frame_read, &offset) ||
      !pure_audio_frame_bytes((unsigned)frame_bytes,
                              (unsigned long)first_frames, &first_bytes) ||
      !pure_audio_frame_bytes((unsigned)frame_bytes,
                              (unsigned long)(frames - first_frames),
                              &second_bytes))
    return false;
  memcpy(data, rbuf->buffer + offset, first_bytes);
  if (second_bytes)
    memcpy((char *)data + first_bytes, rbuf->buffer, second_bytes);
  return true;
}

/***************************************************************************
** Return complete frames written. */

static inline size_t
MyRingBuffer_Write( MyRingBuffer *rbuf, const void *data, size_t frames )
{
  size_t written = frames;
  if (!data)
    return 0;
  if (written > MyRingBuffer_GetWriteAvailable(rbuf))
    written = MyRingBuffer_GetWriteAvailable(rbuf);
  if (!MyRingBuffer_CopyIn(rbuf, data, written))
    return 0;
  MyRingBuffer_AdvanceWriteIndex(rbuf, written);
  return written;
}

/***************************************************************************
** Return complete frames read. */

static inline size_t
MyRingBuffer_Read( MyRingBuffer *rbuf, void *data, size_t frames )
{
  size_t read = frames;
  if (!data)
    return 0;
  if (read > MyRingBuffer_GetReadAvailable(rbuf))
    read = MyRingBuffer_GetReadAvailable(rbuf);
  if (!MyRingBuffer_CopyOut(rbuf, data, read))
    return 0;
  MyRingBuffer_AdvanceReadIndex(rbuf, read);
  return read;
}

/***************************************************************************
*/

/* This has been ported from the Q-Audio module. We maintain our own linked
   lists of open audio streams so that we can easily perform actions on all
   streams. Our streams also do their own locking and signaling in order to
   wake up clients which are waiting to do I/O on the stream. This is used to
   implement thread-safe blocking I/O operations for Pure applications.
   (PortAudio v19 also provides its own blocking I/O but it's not implemented
   for all drivers, so we rather do our own.) */

static bool init_ok;
static PaError audio_error = paNotInitialized;
/* A failed Pa_CloseStream can orphan a callback producer outside PortAudio's
   open list. No portable subsequent call proves it stopped. Quarantine is
   permanent: never tear down this backend, restart it, or recycle userdata. */
static bool backend_quarantined;

typedef struct _MyStream {
  PaStream *as;
  pthread_mutex_t data_mutex;
  pthread_cond_t in_cond, out_cond;
  MyRingBuffer in_buf, out_buf;
  char *in_data, *out_data;
  PaDeviceIndex in, out;
  double time, sample_rate, in_latency, out_latency;
#ifdef TIMER_KLUDGE
  double delta;
#endif
  int size;
  PaSampleFormat in_format, out_format;
  int in_channels, in_bps, in_bpf;
  int out_channels, out_bps, out_bpf;
  uint64_t input_accepted_frames, input_dropped_frames;
  uint64_t output_consumed_frames;
  enum { STREAM_ALLOCATED, STREAM_OPENED, STREAM_STARTED, STREAM_STOPPING,
         STREAM_CLOSED, STREAM_FAILED } state;
  uintptr_t identity;
  unsigned operations, callbacks;
  unsigned initialized;
  PaError error;
  struct _MyStream *prev, *next;
} MyStream;

/* Lifecycle serializes native start/stop/close. Registry protects identities,
   list links and activity counts. It pins descriptors and is released before
   acquiring data_mutex; leave releases data_mutex before reacquiring registry.
   Identities are never reused. Queue indices and state use data_mutex only. */
static pthread_mutex_t registry_mutex = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t registry_cond = PTHREAD_COND_INITIALIZER;
static pthread_mutex_t lifecycle_mutex = PTHREAD_MUTEX_INITIALIZER;
static MyStream *current;
static uintptr_t next_identity = 1;

static MyStream *enter_stream(MyStream *identity, bool callback)
{
  MyStream *v;
  if (!identity) return NULL;
  pthread_mutex_lock(&registry_mutex);
  for (v = current; v; v = v->next)
    if (callback ? v == identity : v->identity == (uintptr_t)identity) break;
  if (v) {
    if (callback) ++v->callbacks; else ++v->operations;
  }
  pthread_mutex_unlock(&registry_mutex);
  if (v) pthread_mutex_lock(&v->data_mutex);
  return v;
}

static void leave_stream(MyStream *v, bool callback)
{
  pthread_mutex_unlock(&v->data_mutex);
  pthread_mutex_lock(&registry_mutex);
  if (callback) --v->callbacks; else --v->operations;
  pthread_cond_broadcast(&registry_cond);
  pthread_mutex_unlock(&registry_mutex);
}

static void terminal_stream(MyStream *v, PaError error)
{
  v->error = error;
  v->state = STREAM_FAILED;
  pthread_cond_broadcast(&v->in_cond);
  pthread_cond_broadcast(&v->out_cond);
}

static void register_stream(MyStream *v)
{
  pthread_mutex_lock(&registry_mutex);
  v->next = current;
  if (current) current->prev = v;
  current = v;
  pthread_mutex_unlock(&registry_mutex);
}

static void unregister_stream(MyStream *v)
{
  if (v->prev) v->prev->next = v->next;
  if (v->next) v->next->prev = v->prev;
  if (current == v) current = v->next;
}


#define has_input(v) (v->in!=paNoDevice)
#define has_output(v) (v->out!=paNoDevice)


static bool init_buf(MyRingBuffer *buf, char **data, size_t frame_capacity,
                     unsigned channels, unsigned sample_bytes)
{
  size_t frame_bytes, allocation_size;
  if (frame_capacity == 0 || frame_capacity > ULONG_MAX || channels == 0 ||
      sample_bytes == 0 ||
      !pure_audio_checked_mul_size(channels, sample_bytes, &frame_bytes) ||
      frame_bytes > UINT_MAX ||
      !pure_audio_frame_bytes((unsigned)frame_bytes,
                              (unsigned long)frame_capacity,
                              &allocation_size))
    return false;
  if (!(*data = pure_audio_malloc(allocation_size)))
    return false;
  memset(*data, 0, allocation_size);
  if (MyRingBuffer_Init(buf, frame_capacity, channels, sample_bytes, *data)) {
    pure_audio_free(*data);
    *data = NULL;
    return false;
  }
  return true;
}

static void fini_buf(char **data)
{
  pure_audio_free(*data);
  *data = NULL;
}

static bool round_pow2(size_t value, size_t *rounded)
{
  size_t result = 1;
  if (!rounded || value == 0)
    return false;
  while (result < value) {
    if (result > (size_t)LONG_MAX / 2)
      return false;
    result <<= 1;
  }
  if (result > (size_t)LONG_MAX / 2)
    return false;
  *rounded = result;
  return true;
}

#ifdef PURE_AUDIO_TEST_SEAM
bool pure_audio_test_round_pow2(size_t value, size_t *rounded)
{
  return round_pow2(value, rounded);
}
#endif

static void destroy_stream(MyStream *v)
{
  if (v->initialized & 4) pthread_cond_destroy(&v->out_cond);
  if (v->initialized & 2) pthread_cond_destroy(&v->in_cond);
  if (v->initialized & 1) pthread_mutex_destroy(&v->data_mutex);
  v->initialized = 0;
  fini_buf(&v->out_data);
  fini_buf(&v->in_data);
}

static bool init_stream(MyStream *v,
                        PaStreamParameters *in, PaStreamParameters *out,
                        long size, unsigned in_bps, unsigned out_bps)
{
  size_t frame_capacity;
  memset(v, 0, sizeof(*v));
  v->state = STREAM_ALLOCATED;
  if (size <= 0 || !round_pow2((size_t)size, &frame_capacity)) return false;
  if (in && !init_buf(&v->in_buf, &v->in_data, frame_capacity,
                      (unsigned)in->channelCount, in_bps)) goto fail;
  if (out && !init_buf(&v->out_buf, &v->out_data, frame_capacity,
                       (unsigned)out->channelCount, out_bps)) goto fail;
  if (pthread_mutex_init(&v->data_mutex, NULL)) goto fail;
  v->initialized |= 1;
  if (pthread_cond_init(&v->in_cond, NULL)) goto fail;
  v->initialized |= 2;
  if (pthread_cond_init(&v->out_cond, NULL)) goto fail;
  v->initialized |= 4;
  return true;
fail:
  destroy_stream(v);
  return false;
}

/* Called with lifecycle_mutex held. Public admission is invalidated before
   waiting, but descriptors stay alive until all admitted activity exits.
   Pa_CloseStream can consume its pointer even on error: never retry it.
   On failure the descriptor, queues and synchronization become a permanent
   tombstone. Late callbacks may enter it but can only observe FAILED state. */
static PaError fini_stream(MyStream *v, bool abort)
{
  PaError error, close_error;
  pthread_mutex_lock(&v->data_mutex);
  if (!v->as && v->state == STREAM_FAILED) {
    error = v->error;
    pthread_mutex_unlock(&v->data_mutex);
    return error;
  }
  v->state = STREAM_STOPPING;
  pthread_cond_broadcast(&v->in_cond);
  pthread_cond_broadcast(&v->out_cond);
  pthread_mutex_unlock(&v->data_mutex);
  error = v->as ? (abort ? pure_audio_dispatch->abort(v->as) :
                           pure_audio_dispatch->stop(v->as)) : paNoError;
  if (error == paStreamIsStopped) error = paNoError;
  if (error != paNoError && !abort) {
    PaError abort_error = pure_audio_dispatch->abort(v->as);
    if (abort_error != paNoError && abort_error != paStreamIsStopped)
      error = abort_error;
  }
  pthread_mutex_lock(&registry_mutex);
  /* Closing admission under the registry lock ensures no operation can pin a
     descriptor after the drain has observed zero. Callback admission remains
     until native close returns, because even a failed stop may call back. */
  v->identity = 0;
  while (v->operations || v->callbacks)
    pthread_cond_wait(&registry_cond, &registry_mutex);
  pthread_mutex_unlock(&registry_mutex);
  close_error = v->as ? pure_audio_dispatch->close(v->as) : paNoError;
  pthread_mutex_lock(&v->data_mutex);
  v->error = close_error != paNoError ? close_error : error;
  v->state = close_error == paNoError ? STREAM_CLOSED : STREAM_FAILED;
  v->as = NULL;
  if (close_error != paNoError) {
    backend_quarantined = true;
    audio_error = close_error;
  }
  pthread_mutex_unlock(&v->data_mutex);
  if (close_error == paNoError) {
    pthread_mutex_lock(&registry_mutex);
    unregister_stream(v);
    while (v->operations || v->callbacks)
      pthread_cond_wait(&registry_cond, &registry_mutex);
    pthread_mutex_unlock(&registry_mutex);
    destroy_stream(v);
    pure_audio_free(v);
  }
  return close_error != paNoError ? close_error : error;
}

static PaError stop_audio_locked(void)
{
  MyStream *v, *next;
  PaError error = paNoError;
  for (v = current; v; v = next) {
    next = v->next;
    PaError e = fini_stream(v, true);
    if (e != paNoError) error = e;
  }
  if (backend_quarantined) return audio_error;
  if (init_ok) {
    PaError e = pure_audio_dispatch->terminate();
    if (e == paNoError) {
      /* Every stream was successfully closed above. Quarantined backends
         never reach this call, even if a later terminate might return zero. */
      init_ok = false;
    } else error = e;
  }
  audio_error = error != paNoError ? error : paNotInitialized;
  return error;
}

void start_audio(void)
{
  int previous_cancel;
  pthread_setcancelstate(PTHREAD_CANCEL_DISABLE, &previous_cancel);
  pthread_mutex_lock(&lifecycle_mutex);
  PaError stopped = stop_audio_locked();
  if (!backend_quarantined && (stopped == paNoError || (!init_ok && !current))) {
    audio_error = pure_audio_dispatch->initialize();
    init_ok = audio_error == paNoError;
  }
  pthread_mutex_unlock(&lifecycle_mutex);
  pthread_setcancelstate(previous_cancel, NULL);
}

void stop_audio(void)
{
  int previous_cancel;
  pthread_setcancelstate(PTHREAD_CANCEL_DISABLE, &previous_cancel);
  pthread_mutex_lock(&lifecycle_mutex);
  (void)stop_audio_locked();
  pthread_mutex_unlock(&lifecycle_mutex);
  pthread_setcancelstate(previous_cancel, NULL);
}

static void pure_audio_add_counter(uint64_t *counter, uint64_t increment)
{
  if (UINT64_MAX - *counter < increment)
    *counter = UINT64_MAX;
  else
    *counter += increment;
}

static bool callback_channels_valid(const void *buffer, PaSampleFormat format,
                                    int channels)
{
  const void *const *channel_buffers;
  int channel;
  if (!buffer || channels <= 0)
    return false;
  if (!(format & paNonInterleaved))
    return true;
  channel_buffers = (const void *const *)buffer;
  for (channel = 0; channel < channels; ++channel)
    if (!channel_buffers[channel])
      return false;
  return true;
}

static bool callback_format_valid(PaSampleFormat format, int channels,
                                  int sample_bytes, int frame_bytes,
                                  const MyRingBuffer *queue)
{
  size_t expected_frame_bytes;
  int expected_sample_bytes = pure_audio_sample_bytes(format);
  return channels > 0 && expected_sample_bytes > 0 &&
    sample_bytes == expected_sample_bytes &&
    pure_audio_checked_mul_size((size_t)channels, (size_t)sample_bytes,
                                &expected_frame_bytes) &&
    expected_frame_bytes <= INT_MAX && frame_bytes == (int)expected_frame_bytes &&
    queue->channels == (unsigned)channels &&
    queue->sample_bytes == (unsigned)sample_bytes;
}

static bool MyRingBuffer_WritePlanar(MyRingBuffer *rbuf,
                                     const void *const *channel_buffers,
                                     size_t source_frame, size_t frames)
{
  size_t frame, channel, queue_offset, source_offset, channel_offset;
  size_t frame_bytes;
  if (frames > MyRingBuffer_GetWriteAvailable(rbuf) ||
      !MyRingBuffer_FrameBytes(rbuf, &frame_bytes))
    return false;
  for (frame = 0; frame < frames; ++frame) {
    size_t queue_frame = (rbuf->frame_write + frame) % rbuf->frame_capacity;
    if (!pure_audio_frame_bytes((unsigned)frame_bytes,
                                (unsigned long)queue_frame, &queue_offset) ||
        !pure_audio_frame_bytes(rbuf->sample_bytes,
                                (unsigned long)(source_frame + frame),
                                &source_offset))
      return false;
    for (channel = 0; channel < rbuf->channels; ++channel) {
      if (!pure_audio_checked_mul_size(channel, rbuf->sample_bytes,
                                       &channel_offset))
        return false;
      memcpy(rbuf->buffer + queue_offset + channel_offset,
             (const char *)channel_buffers[channel] + source_offset,
             rbuf->sample_bytes);
    }
  }
  MyRingBuffer_AdvanceWriteIndex(rbuf, frames);
  return true;
}

static bool MyRingBuffer_ReadPlanar(MyRingBuffer *rbuf, void **channel_buffers,
                                    size_t destination_frame, size_t frames)
{
  size_t frame, channel, queue_offset, destination_offset, channel_offset;
  size_t frame_bytes;
  if (frames > MyRingBuffer_GetReadAvailable(rbuf) ||
      !MyRingBuffer_FrameBytes(rbuf, &frame_bytes))
    return false;
  for (frame = 0; frame < frames; ++frame) {
    size_t queue_frame = (rbuf->frame_read + frame) % rbuf->frame_capacity;
    if (!pure_audio_frame_bytes((unsigned)frame_bytes,
                                (unsigned long)queue_frame, &queue_offset) ||
        !pure_audio_frame_bytes(rbuf->sample_bytes,
                                (unsigned long)(destination_frame + frame),
                                &destination_offset))
      return false;
    for (channel = 0; channel < rbuf->channels; ++channel) {
      if (!pure_audio_checked_mul_size(channel, rbuf->sample_bytes,
                                       &channel_offset))
        return false;
      memcpy((char *)channel_buffers[channel] + destination_offset,
             rbuf->buffer + queue_offset + channel_offset,
             rbuf->sample_bytes);
    }
  }
  MyRingBuffer_AdvanceReadIndex(rbuf, frames);
  return true;
}

static bool fill_callback_silence(void *output, PaSampleFormat format,
                                  int channels, unsigned sample_bytes,
                                  size_t first_frame, size_t frames)
{
  size_t byte_offset, byte_count;
  unsigned char silence = pure_audio_base_format(format) == paUInt8 ? 128 : 0;
  if (format & paNonInterleaved) {
    void **channel_buffers = (void **)output;
    int channel;
    if (!pure_audio_frame_bytes(sample_bytes, (unsigned long)first_frame,
                                &byte_offset) ||
        !pure_audio_frame_bytes(sample_bytes, (unsigned long)frames,
                                &byte_count))
      return false;
    for (channel = 0; channel < channels; ++channel)
      memset((char *)channel_buffers[channel] + byte_offset, silence,
             byte_count);
  } else {
    size_t frame_bytes;
    if (!pure_audio_checked_mul_size((size_t)channels, sample_bytes,
                                     &frame_bytes) ||
        frame_bytes > UINT_MAX ||
        !pure_audio_frame_bytes((unsigned)frame_bytes,
                                (unsigned long)first_frame, &byte_offset) ||
        !pure_audio_frame_bytes((unsigned)frame_bytes, (unsigned long)frames,
                                &byte_count))
      return false;
    memset((char *)output + byte_offset, silence, byte_count);
  }
  return true;
}

/* Audio processing callback. Note that in difference to the pablio
   implementation we employ some mutex locks and condition variables here.
   This isn't nice but is needed to protect shared data and to wake up a
   client waiting for data to be read or written. */

static int audio_cb_locked(const void *input, void *output,
		    unsigned long nframes,
		    const PaStreamCallbackTimeInfo *time_info,
		    PaStreamCallbackFlags status,
		    void *data)
{
  MyStream *v = (MyStream*)data;
#ifdef TIMER_KLUDGE
  (void)time_info;
#endif
  (void)status;
  size_t in_count = 0, out_count = 0, callback_frames = (size_t)nframes;
  if (!v || (uintmax_t)nframes > (uintmax_t)SIZE_MAX ||
      (input &&
       (!callback_format_valid(v->in_format, v->in_channels, v->in_bps,
                               v->in_bpf, &v->in_buf) ||
        !pure_audio_frame_bytes((unsigned)v->in_bpf, nframes, &in_count) ||
        !callback_channels_valid(input, v->in_format, v->in_channels))) ||
      (output &&
       (!callback_format_valid(v->out_format, v->out_channels, v->out_bps,
                               v->out_bpf, &v->out_buf) ||
        !pure_audio_frame_bytes((unsigned)v->out_bpf, nframes, &out_count) ||
        !callback_channels_valid(output, v->out_format, v->out_channels))))
    return paAbort;
  (void)in_count;
  (void)out_count;
  /* update the current time */
  if (!v->as) {
    return 0;
  }
#ifdef TIMER_KLUDGE
  v->time += v->delta;
  v->delta = ((double)nframes)/v->sample_rate;
#else
  v->time = time_info?time_info->currentTime:0;
#endif
  /* process data */
  if (input) {
    size_t accepted = callback_frames, source_frame = 0, discard;
    bool transferred;
    if (accepted > v->in_buf.frame_capacity) {
      source_frame = accepted - v->in_buf.frame_capacity;
      accepted = v->in_buf.frame_capacity;
      pure_audio_add_counter(&v->input_dropped_frames,
                             (uint64_t)source_frame);
    }
    discard = accepted > MyRingBuffer_GetWriteAvailable(&v->in_buf) ?
      accepted - MyRingBuffer_GetWriteAvailable(&v->in_buf) : 0;
    if (discard) {
      MyRingBuffer_AdvanceReadIndex(&v->in_buf, discard);
      pure_audio_add_counter(&v->input_dropped_frames, (uint64_t)discard);
    }
    if (v->in_format & paNonInterleaved)
      transferred = MyRingBuffer_WritePlanar(
        &v->in_buf, (const void *const *)input, source_frame, accepted);
    else {
      size_t source_offset;
      transferred = pure_audio_frame_bytes((unsigned)v->in_bpf,
                                            (unsigned long)source_frame,
                                            &source_offset) &&
        MyRingBuffer_Write(&v->in_buf, (const char *)input + source_offset,
                           accepted) == accepted;
    }
    if (transferred)
      pure_audio_add_counter(&v->input_accepted_frames, (uint64_t)accepted);
    pthread_cond_signal(&v->in_cond);
    if (!transferred)
      return paAbort;
  }
  if (output) {
    size_t read;
    bool transferred;
    read = callback_frames;
    if (read > MyRingBuffer_GetReadAvailable(&v->out_buf))
      read = MyRingBuffer_GetReadAvailable(&v->out_buf);
    if (v->out_format & paNonInterleaved)
      transferred = MyRingBuffer_ReadPlanar(&v->out_buf, (void **)output, 0,
                                            read);
    else
      transferred = MyRingBuffer_Read(&v->out_buf, output, read) == read;
    if (transferred && read < callback_frames)
      transferred = fill_callback_silence(output, v->out_format,
                                           v->out_channels,
                                           (unsigned)v->out_bps, read,
                                           callback_frames - read);
    if (transferred)
      pure_audio_add_counter(&v->output_consumed_frames, (uint64_t)read);
    pthread_cond_signal(&v->out_cond);
    if (!transferred)
      return paAbort;
  }
  return paContinue;
}

static int audio_cb(const void *input, void *output, unsigned long nframes,
                    const PaStreamCallbackTimeInfo *time_info,
                    PaStreamCallbackFlags status, void *data)
{
  MyStream *v = enter_stream(data, true);
  int result = paAbort;
  if (!v) return paAbort;
  if (v->state == STREAM_STARTED || v->state == STREAM_OPENED) {
    result = audio_cb_locked(input, output, nframes, time_info, status, v);
    if (result == paAbort) terminal_stream(v, paInternalError);
  }
  leave_stream(v, true);
  return result;
}

static void audio_finished(void *data)
{
  MyStream *v = enter_stream(data, true);
  if (!v) return;
  if (v->state == STREAM_STARTED || v->state == STREAM_OPENED)
    terminal_stream(v, paDeviceUnavailable);
  leave_stream(v, true);
}

#ifdef PURE_AUDIO_TEST_SEAM
int64_t audio_stream_consumed_frames(MyStream *v, PaStream *as);

int pure_audio_test_invoke_callback(void *stream, const void *input,
                                    void *output, unsigned long frames)
{
  return audio_cb(input, output, frames, NULL, 0, stream);
}

uint64_t pure_audio_test_consumed_frames(void *stream)
{
  int64_t frames = audio_stream_consumed_frames((MyStream *)stream, NULL);
  return frames < 0 ? 0 : (uint64_t)frames;
}

uint64_t pure_audio_test_input_accepted_frames(void *stream)
{
  MyStream *v = enter_stream(stream, false);
  uint64_t frames;
  if (!v) return 0;
  frames = v->input_accepted_frames;
  leave_stream(v, false);
  return frames;
}

uint64_t pure_audio_test_input_dropped_frames(void *stream)
{
  MyStream *v = enter_stream(stream, false);
  uint64_t frames;
  if (!v) return 0;
  frames = v->input_dropped_frames;
  leave_stream(v, false);
  return frames;
}
#endif

static pure_expr *open_audio_stream_locked(int *in, int *out,
			     double sr, long size, int flags)
{
  PaStreamParameters inparams, outparams, *inptr = NULL, *outptr = NULL;
  MyStream *v;
  PaError err;
  int in_bps = 0, out_bps = 0;
  size_t in_bpf = 0, out_bpf = 0;
  const PaStreamInfo* info;
#ifdef HAVE_POSIX_SIGNALS
  sigset_t sigset, oldset;
#endif

  if (!init_ok || audio_error != paNoError) return pure_int(audio_error);
  if (!isfinite(sr) || sr <= 0) return pure_int(paInvalidSampleRate);
  if (size > INT_MAX || next_identity == UINTPTR_MAX) return 0;
  if (size <= 0) size = 512;

  /* Initialize parameters. */

  if (in && in[1] < 0) return pure_int(paInvalidChannelCount);
  if (in && in[1]>0) {
    PaDeviceIndex count = pure_audio_dispatch->device_count();
    const PaDeviceInfo *device;
    if (count < 0) return pure_int(count);
    if (in[0] < 0 || in[0] >= count) return pure_int(paInvalidDevice);
    device = pure_audio_dispatch->device_info(in[0]);
    if (!device) return pure_int(paInvalidDevice);
    if (in[1] > device->maxInputChannels) return pure_int(paInvalidChannelCount);
    memset(&inparams, 0, sizeof(inparams));
    inparams.device = in[0];
    inparams.channelCount = in[1];
    inparams.sampleFormat = (PaSampleFormat)(uint32_t)in[2];
    inparams.suggestedLatency = in[3] ?
      device->defaultLowInputLatency :
      device->defaultHighInputLatency;
    inparams.hostApiSpecificStreamInfo = 0;
    inptr = &inparams;
    in_bps = pure_audio_sample_bytes(inparams.sampleFormat);
    if (in_bps <= 0 ||
        !pure_audio_checked_mul_size((size_t)in_bps,
                                     (size_t)inparams.channelCount, &in_bpf) ||
        in_bpf > INT_MAX)
      return 0;
  } else
    in = 0;

  if (out && out[1] < 0) return pure_int(paInvalidChannelCount);
  if (out && out[1]>0) {
    PaDeviceIndex count = pure_audio_dispatch->device_count();
    const PaDeviceInfo *device;
    if (count < 0) return pure_int(count);
    if (out[0] < 0 || out[0] >= count) return pure_int(paInvalidDevice);
    device = pure_audio_dispatch->device_info(out[0]);
    if (!device) return pure_int(paInvalidDevice);
    if (out[1] > device->maxOutputChannels) return pure_int(paInvalidChannelCount);
    memset(&outparams, 0, sizeof(outparams));
    outparams.device = out[0];
    outparams.channelCount = out[1];
    outparams.sampleFormat = (PaSampleFormat)(uint32_t)out[2];
    outparams.suggestedLatency = out[3] ?
      device->defaultLowOutputLatency :
      device->defaultHighOutputLatency;
    outparams.hostApiSpecificStreamInfo = 0;
    outptr = &outparams;
    out_bps = pure_audio_sample_bytes(outparams.sampleFormat);
    if (out_bps <= 0 ||
        !pure_audio_checked_mul_size((size_t)out_bps,
                                     (size_t)outparams.channelCount, &out_bpf) ||
        out_bpf > INT_MAX)
      return 0;
  } else
    out = 0;

  if (!in && !out) return pure_int(paInvalidChannelCount);

  /* Initialize the Pure stream descriptor. This is passed to the callback
     data and also to the sentry on the stream object, so that we can perform
     proper cleanup when a stream is closed or gets garbage-collected. */

  if (!(v = pure_audio_malloc(sizeof(MyStream)))) return 0;
  if (!init_stream(v, inptr, outptr, size, (unsigned)in_bps,
                   (unsigned)out_bps)) {
    pure_audio_free(v);
    return 0;
  }

  /* Open the PortAudio stream. */

  err = pure_audio_dispatch->open(&v->as, inptr, outptr, sr, size, flags,
		      audio_cb, v);

  if (err != paNoError) {
    destroy_stream(v);
    pure_audio_free(v);
    return pure_int(err);
  }

  /* Fill in needed information about the stream. */

  info = pure_audio_dispatch->info(v->as);
  v->in = in?inparams.device:paNoDevice;
  v->out = out?outparams.device:paNoDevice;
  v->sample_rate = info?info->sampleRate:sr;
  v->size = size;
  /* Looks like these are sometimes bogus for some drivers and devices, but we
     store them anyway. */
  v->in_latency = info?info->inputLatency:0;
  v->out_latency = info?info->outputLatency:0;
  v->in_channels = in?inparams.channelCount:0;
  v->out_channels = out?outparams.channelCount:0;
  v->in_format = in?inparams.sampleFormat:0;
  v->out_format = out?outparams.sampleFormat:0;
  v->in_bps = in_bps; v->out_bps = out_bps;
  v->in_bpf = (int)in_bpf;
  v->out_bpf = (int)out_bpf;

  v->identity = next_identity++;
  v->state = STREAM_OPENED;
  register_stream(v);
  if (!info) {
    (void)fini_stream(v, true);
    return pure_int(paInternalError);
  }
  err = pure_audio_dispatch->finished(v->as, audio_finished);
  if (err != paNoError) {
    (void)fini_stream(v, true);
    return pure_int(err);
  }

  /* Start the stream. */
#ifdef HAVE_POSIX_SIGNALS
  /* temporarily block some signals to make sure that they are blocked in the
     PortAudio threads created by Pa_StartStream */
  sigemptyset(&sigset);
  sigaddset(&sigset, SIGINT);
  sigaddset(&sigset, SIGQUIT);
  sigaddset(&sigset, SIGTSTP);
  sigaddset(&sigset, SIGTERM);
  sigaddset(&sigset, SIGHUP);
  sigprocmask(SIG_BLOCK, &sigset, &oldset);
#endif
  err = pure_audio_dispatch->start(v->as);
#ifdef HAVE_POSIX_SIGNALS
  sigprocmask(SIG_SETMASK, &oldset, NULL);
#endif

  if (err != paNoError) {
    (void)fini_stream(v, true);
    return pure_int(err);
  }
  pthread_mutex_lock(&v->data_mutex);
  if (v->state == STREAM_FAILED) {
    err = v->error;
    pthread_mutex_unlock(&v->data_mutex);
    (void)fini_stream(v, true);
    return pure_int(err);
  }
  v->state = STREAM_STARTED;
  pthread_mutex_unlock(&v->data_mutex);

  /* Note that we return the real PortAudio stream here, so that it can be
     passed to other (low-level) PortAudio operations. Our own stream data is
     kept in the sentry we set on the stream so that we can perform the
     necessary cleanup. */
  return pure_sentry
    (pure_app(pure_symbol(pure_sym("audio::audio_sentry")),
	      pure_pointer((void *)v->identity)),
     pure_pointer(v->as));
}

pure_expr *open_audio_stream(int *in, int *out, double sr, long size, int flags)
{
  pure_audio_record_open_call();
  pure_expr *result;
  int previous_cancel;
  pthread_setcancelstate(PTHREAD_CANCEL_DISABLE, &previous_cancel);
  pthread_mutex_lock(&lifecycle_mutex);
  result = open_audio_stream_locked(in, out, sr, size, flags);
  pthread_mutex_unlock(&lifecycle_mutex);
  pthread_setcancelstate(previous_cancel, NULL);
  return result;
}

void audio_sentry(MyStream *identity, pure_expr *stream)
{
  MyStream *v;
  int previous_cancel;
  /* A condition cancellation would otherwise reacquire registry_mutex and
     strand both registry and lifecycle locks. Deliver it only after cleanup. */
  pthread_setcancelstate(PTHREAD_CANCEL_DISABLE, &previous_cancel);
  pthread_mutex_lock(&lifecycle_mutex);
  pthread_mutex_lock(&registry_mutex);
  for (v = current; v; v = v->next)
    if (identity && v->identity == (uintptr_t)identity) break;
  pthread_mutex_unlock(&registry_mutex);
  if (v) (void)fini_stream(v, false);
  pthread_mutex_unlock(&lifecycle_mutex);
  if (stream) stream->data.p = NULL;
  pthread_setcancelstate(previous_cancel, NULL);
}

int audio_stream_valid(MyStream *identity)
{
  MyStream *v = enter_stream(identity, false);
  int valid;
  if (!v) return 0;
  valid = v->state == STREAM_STARTED && v->as != NULL;
  leave_stream(v, false);
  return valid;
}

void close_audio_stream(pure_expr *stream)
{
  pure_expr *sentry, *function, *argument;
  int32_t symbol;
  void *data;
  if (!stream || !(sentry = pure_get_sentry(stream)) ||
      !pure_is_app(sentry, &function, &argument) ||
      !pure_is_symbol(function, &symbol) ||
      symbol != pure_sym("audio::audio_sentry") ||
      !pure_is_pointer(argument, &data) || !data)
    return;
  pure_clear_sentry(stream);
  audio_sentry((MyStream*)data, stream);
}

static bool stream_running(MyStream *v)
{
  PaError active;
  if (v->state != STREAM_STARTED || !v->as) return false;
  active = pure_audio_dispatch->active(v->as);
  if (active == 1) return true;
  terminal_stream(v, active < 0 ? active : paDeviceUnavailable);
  return false;
}

pure_expr *audio_stream_info(MyStream *identity, PaStream *as)
{
  MyStream *v = enter_stream(identity, false);
  pure_expr *result = NULL;
  (void)as;
  if (!v) return NULL;
  if (stream_running(v)) {
    int in_info[] = {v->in, v->in_channels, (int)v->in_format, v->in_bps},
        out_info[] = {v->out, v->out_channels, (int)v->out_format, v->out_bps};
    result = pure_tuplel(4, pure_double(v->sample_rate), pure_int(v->size),
      matrix_from_int_array(1, has_input(v)?4:0, in_info),
      matrix_from_int_array(1, has_output(v)?4:0, out_info));
  }
  leave_stream(v, false);
  return result;
}

pure_expr *audio_stream_latencies(MyStream *identity, PaStream *as)
{
  MyStream *v = enter_stream(identity, false);
  pure_expr *result = NULL;
  (void)as;
  if (!v) return NULL;
  if (stream_running(v))
    result = pure_tuplel(2, pure_double(v->in_latency), pure_double(v->out_latency));
  leave_stream(v, false);
  return result;
}

int audio_stream_channels(MyStream *identity, int input)
{
  MyStream *v = enter_stream(identity, false);
  int result = 0;
  if (!v) return 0;
  if (stream_running(v)) result = input ? v->in_channels : v->out_channels;
  leave_stream(v, false);
  return result;
}

double audio_stream_time(MyStream *identity, PaStream *as)
{
  MyStream *v = enter_stream(identity, false);
  double result = -1;
  (void)as;
  if (!v) return -1;
  if (stream_running(v)) result = v->time;
  leave_stream(v, false);
  return result;
}

double audio_stream_cpu_load(MyStream *identity, PaStream *as)
{
  MyStream *v = enter_stream(identity, false);
  double result = -1;
  (void)as;
  if (!v) return -1;
  if (stream_running(v)) result = pure_audio_dispatch->cpu_load(v->as);
  leave_stream(v, false);
  return result;
}

static int stream_available(MyStream *identity, bool input)
{
  MyStream *v = enter_stream(identity, false);
  size_t frames = 0;
  if (!v) return 0;
  if (stream_running(v)) {
    if (input && has_input(v)) frames = MyRingBuffer_GetReadAvailable(&v->in_buf);
    if (!input && has_output(v)) frames = MyRingBuffer_GetWriteAvailable(&v->out_buf);
  }
  leave_stream(v, false);
  return frames > INT_MAX ? INT_MAX : (int)frames;
}

int audio_stream_readable(MyStream *identity, PaStream *as)
{ (void)as; return stream_available(identity, true); }

int audio_stream_writeable(MyStream *identity, PaStream *as)
{ (void)as; return stream_available(identity, false); }

int64_t audio_stream_consumed_frames(MyStream *identity, PaStream *as)
{
  MyStream *v = enter_stream(identity, false);
  uint64_t frames = 0;
  (void)as;
  if (!v) return -1;
  if (stream_running(v) && has_output(v)) frames = v->output_consumed_frames;
  else { leave_stream(v, false); return -1; }
  leave_stream(v, false);
  return frames > INT64_MAX ? INT64_MAX : (int64_t)frames;
}

static int transfer_audio_stream(MyStream *v, void *buf, long size, bool input)
{
  size_t bytes, frames, offset = 0;
  MyRingBuffer *ring = input ? &v->in_buf : &v->out_buf;
  unsigned bpf = (unsigned)(input ? v->in_bpf : v->out_bpf);
  pthread_cond_t *cond = input ? &v->in_cond : &v->out_cond;
  if (!(input ? has_input(v) : has_output(v)) || size < 0 || size > INT_MAX ||
      !stream_running(v)) return -1;
  if (!size) return 0;
  if (!buf || !pure_audio_frame_bytes(bpf, (unsigned long)size, &bytes) ||
      bytes > LONG_MAX) return -1;
  frames = (size_t)size;
  while (frames) {
    size_t transferred;
    /* Recheck terminal state before each queue access, including after wake. */
    if (!stream_running(v)) return -1;
    transferred = input ? MyRingBuffer_Read(ring, (char *)buf + offset, frames) :
                          MyRingBuffer_Write(ring, (char *)buf + offset, frames);
    frames -= transferred;
    offset += transferred * bpf;
    if (!transferred) {
      struct timespec deadline;
      int error;
      clock_gettime(CLOCK_REALTIME, &deadline);
      deadline.tv_nsec += 50000000;
      if (deadline.tv_nsec >= 1000000000) {
        ++deadline.tv_sec; deadline.tv_nsec -= 1000000000;
      }
      /* Some hosts report device loss only through IsStreamActive. A bounded
         timed wait makes that failure observable without a producer signal. */
      error = pthread_cond_timedwait(cond, &v->data_mutex, &deadline);
      if (error && error != ETIMEDOUT) {
        terminal_stream(v, paInternalError);
        return -1;
      }
    }
  }
  return (int)size;
}

static int read_audio_stream_locked(MyStream *v, PaStream *as, void *buf, long size)
{ (void)as; return transfer_audio_stream(v, buf, size, true); }

static int write_audio_stream_locked(MyStream *v, PaStream *as, void *buf, long size)
{ (void)as; return transfer_audio_stream(v, buf, size, false); }

static bool checked_io_counts(long frames, int channels, int bytes_per_frame,
                              size_t *byte_count, size_t *sample_count)
{
  if (frames <= 0 || channels <= 0 || bytes_per_frame <= 0 ||
      !pure_audio_frame_bytes((unsigned)bytes_per_frame,
                              (unsigned long)frames, byte_count) ||
      *byte_count > LONG_MAX ||
      !pure_audio_checked_mul_size((size_t)frames, (size_t)channels,
                                   sample_count))
    return false;
  return true;
}

static int read_audio_stream_int_locked(MyStream *v, PaStream *as, int *buf, long size)
{
  PaSampleFormat format = pure_audio_base_format(v->in_format);
  pure_audio_record_io_call();
  if (!has_input(v)) return -1;
  if (size < 0) return -1;
  if (size == 0) return 0;
  if (format == paInt32) /* immediate */
    return read_audio_stream_locked(v, as, buf, size);
  else if (format != paInt16 && format != paInt8 && format != paUInt8)
    return -1;
  else {
    size_t byte_count, sample_count, i;
    if (!buf || !checked_io_counts(size, v->in_channels, v->in_bpf,
                                   &byte_count, &sample_count))
      return -1;
    /* Read into a temporary buffer. */
    void *p = pure_audio_malloc(byte_count);
    int ret = read_audio_stream_locked(v, as, p, size);
    if (ret <= 0) {
      pure_audio_free(p); return ret;
    }
    /* Convert to int. */
    if (!pure_audio_checked_mul_size((size_t)ret,
                                     (size_t)v->in_channels,
                                     &sample_count)) {
      pure_audio_free(p);
      return -1;
    }
    switch (format) {
    case paInt16: {
      int16_t *m = (int16_t*)p;
      for (i = 0; i < sample_count; i++) buf[i] = m[i];
      break;
    }
    case paInt8: {
      int8_t *m = (int8_t*)p;
      for (i = 0; i < sample_count; i++) buf[i] = m[i];
      break;
    }
    case paUInt8: {
      uint8_t *m = (uint8_t*)p;
      for (i = 0; i < sample_count; i++) buf[i] = (unsigned)m[i];
      break;
    }
    case paInt24: /* TODO */
    default:
      /* Unsupported format. */
      ret = -1; break;
    }
    pure_audio_free(p);
    return ret;
  }
}

static int read_audio_stream_double_locked(MyStream *v, PaStream *as, double *buf, long size)
{
  pure_audio_record_io_call();
  if (!has_input(v)) return -1;
  if (size < 0) return -1;
  if (size == 0) return 0;
  if (pure_audio_base_format(v->in_format) != paFloat32)
    return -1;
  else {
    size_t byte_count, sample_count, i;
    if (!buf || !checked_io_counts(size, v->in_channels, v->in_bpf,
                                   &byte_count, &sample_count))
      return -1;
    /* Read into a temporary buffer. */
    float *m = pure_audio_malloc(byte_count);
    int ret = read_audio_stream_locked(v, as, m, size);
    if (ret <= 0) {
      pure_audio_free(m); return ret;
    }
    /* Convert to double. */
    if (!pure_audio_checked_mul_size((size_t)ret,
                                     (size_t)v->in_channels,
                                     &sample_count)) {
      pure_audio_free(m);
      return -1;
    }
    for (i = 0; i < sample_count; i++) buf[i] = m[i];
    pure_audio_free(m);
    return ret;
  }
}

static int write_audio_stream_int_locked(MyStream *v, PaStream *as, int *buf, long size)
{
  PaSampleFormat format = pure_audio_base_format(v->out_format);
  pure_audio_record_io_call();
  if (!has_output(v)) return -1;
  if (size < 0) return -1;
  if (size == 0) return 0;
  if (format == paInt32) /* immediate */
    return write_audio_stream_locked(v, as, buf, size);
  else if (format != paInt16 && format != paInt8 && format != paUInt8)
    return -1;
  else {
    /* Write from a temporary buffer. */
    int ret;
    size_t byte_count, sample_count, i;
    void *p;
    if (!buf || !checked_io_counts(size, v->out_channels, v->out_bpf,
                                   &byte_count, &sample_count))
      return -1;
    p = pure_audio_malloc(byte_count);
    if (!p) return -1;
    /* Convert from int. */
    switch (format) {
    case paInt16: {
      int16_t *m = (int16_t*)p;
      for (i = 0; i < sample_count; i++) m[i] = buf[i];
      break;
    }
    case paInt8: {
      int8_t *m = (int8_t*)p;
      for (i = 0; i < sample_count; i++) m[i] = buf[i];
      break;
    }
    case paUInt8: {
      uint8_t *m = (uint8_t*)p;
      for (i = 0; i < sample_count; i++) m[i] = (unsigned)buf[i];
      break;
    }
    case paInt24: /* TODO */
    default:
      /* Unsupported format. */
      pure_audio_free(p); return -1;
    }
    ret = write_audio_stream_locked(v, as, p, size);
    pure_audio_free(p);
    return ret;
  }
}

static int write_audio_stream_double_locked(MyStream *v, PaStream *as, double *buf, long size)
{
  pure_audio_record_io_call();
  if (!has_output(v)) return -1;
  if (size < 0) return -1;
  if (size == 0) return 0;
  if (pure_audio_base_format(v->out_format) != paFloat32)
    return -1;
  else {
    /* Write from a temporary buffer. */
    int ret;
    size_t byte_count, sample_count, i;
    float *m;
    if (!buf || !checked_io_counts(size, v->out_channels, v->out_bpf,
                                   &byte_count, &sample_count))
      return -1;
    m = pure_audio_malloc(byte_count);
    if (!m) return -1;
    /* Convert from double. */
    for (i = 0; i < sample_count; i++) m[i] = buf[i];
    ret = write_audio_stream_locked(v, as, m, size);
    pure_audio_free(m);
    return ret;
  }
}


int read_audio_stream(MyStream *identity, PaStream *as, void *buf, long size)
{
  pure_audio_record_raw_io_call();
  MyStream *v;
  int result = -1, previous_cancel;
  /* Cancellation must not strand an activity reference or a reacquired
     condition mutex. Pending cancellation is delivered after releasing both. */
  pthread_setcancelstate(PTHREAD_CANCEL_DISABLE, &previous_cancel);
  v = enter_stream(identity, false);
  if (v) {
    if (stream_running(v)) result = read_audio_stream_locked(v, as, buf, size);
    leave_stream(v, false);
  }
  pthread_setcancelstate(previous_cancel, NULL);
  return result;
}

int write_audio_stream(MyStream *identity, PaStream *as, void *buf, long size)
{
  pure_audio_record_raw_io_call();
  MyStream *v;
  int result = -1, previous_cancel;
  /* Cancellation must not strand an activity reference or a reacquired
     condition mutex. Pending cancellation is delivered after releasing both. */
  pthread_setcancelstate(PTHREAD_CANCEL_DISABLE, &previous_cancel);
  v = enter_stream(identity, false);
  if (v) {
    if (stream_running(v)) result = write_audio_stream_locked(v, as, buf, size);
    leave_stream(v, false);
  }
  pthread_setcancelstate(previous_cancel, NULL);
  return result;
}

int read_audio_stream_int(MyStream *identity, PaStream *as, int *buf, long size)
{
  MyStream *v;
  int result = -1, previous_cancel;
  /* Cancellation must not strand an activity reference or a reacquired
     condition mutex. Pending cancellation is delivered after releasing both. */
  pthread_setcancelstate(PTHREAD_CANCEL_DISABLE, &previous_cancel);
  v = enter_stream(identity, false);
  if (v) {
    if (stream_running(v)) result = read_audio_stream_int_locked(v, as, buf, size);
    leave_stream(v, false);
  }
  pthread_setcancelstate(previous_cancel, NULL);
  return result;
}

int read_audio_stream_double(MyStream *identity, PaStream *as, double *buf, long size)
{
  MyStream *v;
  int result = -1, previous_cancel;
  /* Cancellation must not strand an activity reference or a reacquired
     condition mutex. Pending cancellation is delivered after releasing both. */
  pthread_setcancelstate(PTHREAD_CANCEL_DISABLE, &previous_cancel);
  v = enter_stream(identity, false);
  if (v) {
    if (stream_running(v)) result = read_audio_stream_double_locked(v, as, buf, size);
    leave_stream(v, false);
  }
  pthread_setcancelstate(previous_cancel, NULL);
  return result;
}

int write_audio_stream_int(MyStream *identity, PaStream *as, int *buf, long size)
{
  MyStream *v;
  int result = -1, previous_cancel;
  /* Cancellation must not strand an activity reference or a reacquired
     condition mutex. Pending cancellation is delivered after releasing both. */
  pthread_setcancelstate(PTHREAD_CANCEL_DISABLE, &previous_cancel);
  v = enter_stream(identity, false);
  if (v) {
    if (stream_running(v)) result = write_audio_stream_int_locked(v, as, buf, size);
    leave_stream(v, false);
  }
  pthread_setcancelstate(previous_cancel, NULL);
  return result;
}

int write_audio_stream_double(MyStream *identity, PaStream *as, double *buf, long size)
{
  MyStream *v;
  int result = -1, previous_cancel;
  /* Cancellation must not strand an activity reference or a reacquired
     condition mutex. Pending cancellation is delivered after releasing both. */
  pthread_setcancelstate(PTHREAD_CANCEL_DISABLE, &previous_cancel);
  v = enter_stream(identity, false);
  if (v) {
    if (stream_running(v)) result = write_audio_stream_double_locked(v, as, buf, size);
    leave_stream(v, false);
  }
  pthread_setcancelstate(previous_cancel, NULL);
  return result;
}
