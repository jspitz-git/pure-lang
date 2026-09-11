#ifndef PURE_MIDI_STREAM_H
#define PURE_MIDI_STREAM_H
#include <stddef.h>
#include <stdint.h>
#include <portmidi.h>
#include <porttime.h>

typedef struct PureMidiStream PureMidiStream;
typedef enum { PURE_MIDI_INPUT=1, PURE_MIDI_OUTPUT=2 } PureMidiDirection;
typedef enum { PURE_MIDI_OPEN=1, PURE_MIDI_CLOSING, PURE_MIDI_CLOSED,
               PURE_MIDI_FAILED } PureMidiState;

int pure_midi_start(void);
int pure_midi_stop(void);
int pure_midi_open_input(PureMidiStream **out, int id, int size,
                         PmTimeProcPtr time_proc, void *time_info);
int pure_midi_open_output(PureMidiStream **out, int id, int size,
                          PmTimeProcPtr time_proc, void *time_info, int latency);
/* Each independently owned alias must retain; release consumes one reference.
   Close invalidates all aliases, but retains storage until their last release. */
int pure_midi_retain(PureMidiStream *stream);
void pure_midi_release(PureMidiStream *stream);
int pure_midi_valid(PureMidiStream *stream, int direction);
int pure_midi_state(PureMidiStream *stream);
int pure_midi_close(PureMidiStream *stream);
int pure_midi_abort(PureMidiStream *stream);
int pure_midi_poll(PureMidiStream *stream);
int pure_midi_set_filter(PureMidiStream *stream, int filters);
int pure_midi_set_channel_mask(PureMidiStream *stream, int channels);
int pure_midi_read(PureMidiStream *stream, PmEvent *buffer, int length);
int pure_midi_write(PureMidiStream *stream, PmEvent *buffer, int length);
int pure_midi_write_short(PureMidiStream *stream, int when, int message);
int pure_midi_write_sysex(PureMidiStream *stream, int when,
                          unsigned char *message, int length);

#ifdef PURE_MIDI_TEST_SEAM
/* Only fault targets accept injection. Production uses the real library. */
typedef struct {
  PmError (*initialize)(void);
  PmError (*terminate)(void);
  const PmDeviceInfo *(*device_info)(PmDeviceID);
  PmError (*open_input)(PortMidiStream **,PmDeviceID,void *,int32_t,PmTimeProcPtr,void *);
  PmError (*open_output)(PortMidiStream **,PmDeviceID,void *,int32_t,PmTimeProcPtr,void *,int32_t);
  PmError (*close)(PortMidiStream *);
  PmError (*abort)(PortMidiStream *);
  PmError (*poll)(PortMidiStream *);
  PmError (*set_filter)(PortMidiStream *,int32_t);
  PmError (*set_channel_mask)(PortMidiStream *,int);
  int (*read)(PortMidiStream *,PmEvent *,int32_t);
  PmError (*write)(PortMidiStream *,PmEvent *,int32_t);
  PmError (*write_short)(PortMidiStream *,PmTimestamp,PmMessage);
  PmError (*write_sysex)(PortMidiStream *,PmTimestamp,unsigned char *);
  PtError (*timer_start)(int,PtCallback *,void *);
  PtError (*timer_stop)(void);
  void *(*allocate)(size_t);
  void (*deallocate)(void *);
  /* Wake the fake backend's deliberately blocked operation. Real PortMidi
     I/O is nonblocking; close never calls Pm_Abort concurrently with I/O. */
  void (*wake)(PortMidiStream *);
} PureMidiApi;
typedef struct {
  size_t wrappers, live, quarantined, active, references;
  size_t allocated, freed, close_attempts;
  int initialized, timer_started, failure;
} PureMidiResources;
int pure_midi_test_set_api(const PureMidiApi *api);
PureMidiResources pure_midi_test_resources(void);
#endif
#endif
