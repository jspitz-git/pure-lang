#include "midi_stream.h"
#include <limits.h>
#include <stdlib.h>
#include <string.h>
#ifdef _WIN32
#include <windows.h>
typedef SRWLOCK MidiMutex;
typedef CONDITION_VARIABLE MidiCondition;
#define MIDI_MUTEX_INIT SRWLOCK_INIT
#define MIDI_CONDITION_INIT CONDITION_VARIABLE_INIT
static void mutex_init(MidiMutex *m) { InitializeSRWLock(m); }
static void condition_init(MidiCondition *c) { InitializeConditionVariable(c); }
static void lock(MidiMutex *m) { AcquireSRWLockExclusive(m); }
static void unlock(MidiMutex *m) { ReleaseSRWLockExclusive(m); }
static void notify(MidiCondition *c) { WakeAllConditionVariable(c); }
static uint64_t milliseconds(void) { return GetTickCount64(); }
static int wait_until(MidiCondition *c,MidiMutex *m,uint64_t deadline) {
  uint64_t now=milliseconds();
  return now<deadline && SleepConditionVariableSRW(c,m,(DWORD)(deadline-now),0);
}
static void sync_destroy(MidiMutex *m,MidiCondition *c) { (void)m;(void)c; }
#else
#include <pthread.h>
#include <time.h>
typedef pthread_mutex_t MidiMutex;
typedef pthread_cond_t MidiCondition;
#define MIDI_MUTEX_INIT PTHREAD_MUTEX_INITIALIZER
#define MIDI_CONDITION_INIT PTHREAD_COND_INITIALIZER
static void mutex_init(MidiMutex *m) { pthread_mutex_init(m,NULL); }
static void condition_init(MidiCondition *c) { pthread_cond_init(c,NULL); }
static void lock(MidiMutex *m) { pthread_mutex_lock(m); }
static void unlock(MidiMutex *m) { pthread_mutex_unlock(m); }
static void notify(MidiCondition *c) { pthread_cond_broadcast(c); }
static uint64_t milliseconds(void) { struct timespec t;clock_gettime(CLOCK_MONOTONIC,&t);return (uint64_t)t.tv_sec*1000+(uint64_t)t.tv_nsec/1000000; }
static int wait_until(MidiCondition *c,MidiMutex *m,uint64_t deadline) {
  struct timespec t;uint64_t now=milliseconds(),n;
  if(now>=deadline)return 0;
  clock_gettime(CLOCK_REALTIME,&t);n=(uint64_t)t.tv_nsec+(deadline-now)*1000000;
  t.tv_sec+=(time_t)(n/1000000000);t.tv_nsec=(long)(n%1000000000);
  return pthread_cond_timedwait(c,m,&t)==0;
}
static void sync_destroy(MidiMutex *m,MidiCondition *c) { pthread_cond_destroy(c);pthread_mutex_destroy(m); }
#endif

#ifndef PURE_MIDI_TEST_SEAM
/* Keep the dispatch type private in production; no setter or counters export. */
typedef struct {
  PmError (*initialize)(void),(*terminate)(void);
  const PmDeviceInfo *(*device_info)(PmDeviceID);
  PmError (*open_input)(PortMidiStream **,PmDeviceID,void *,int32_t,PmTimeProcPtr,void *);
  PmError (*open_output)(PortMidiStream **,PmDeviceID,void *,int32_t,PmTimeProcPtr,void *,int32_t);
  PmError (*close)(PortMidiStream *),(*abort)(PortMidiStream *),(*poll)(PortMidiStream *);
  PmError (*set_filter)(PortMidiStream *,int32_t),(*set_channel_mask)(PortMidiStream *,int);
  int (*read)(PortMidiStream *,PmEvent *,int32_t);
  PmError (*write)(PortMidiStream *,PmEvent *,int32_t);
  PmError (*write_short)(PortMidiStream *,PmTimestamp,PmMessage);
  PmError (*write_sysex)(PortMidiStream *,PmTimestamp,unsigned char *);
  PtError (*timer_start)(int,PtCallback *,void *),(*timer_stop)(void);
  void *(*allocate)(size_t);
  void (*deallocate)(void *);
  void (*wake)(PortMidiStream *);
} PureMidiApi;
#endif
static const PureMidiApi real_api={Pm_Initialize,Pm_Terminate,Pm_GetDeviceInfo,
  Pm_OpenInput,Pm_OpenOutput,Pm_Close,Pm_Abort,Pm_Poll,Pm_SetFilter,
  Pm_SetChannelMask,Pm_Read,Pm_Write,Pm_WriteShort,Pm_WriteSysEx,
  Pt_Start,Pt_Stop,malloc,free,NULL};
static const PureMidiApi *api=&real_api;
struct PureMidiStream {
  PureMidiStream *next;
  MidiMutex mutex;
  MidiCondition condition;
  PortMidiStream *native;
  PureMidiDirection direction;
  PureMidiState state;
  size_t active, references, users;
  int result;
};
static MidiMutex registry_mutex=MIDI_MUTEX_INIT;
static MidiCondition registry_condition=MIDI_CONDITION_INIT;
static PureMidiStream *streams;
static int initialized,timer_started,transitioning,process_failure;
#ifdef PURE_MIDI_TEST_SEAM
static size_t allocated,freed,close_attempts;
#define COUNT(x) (++(x))
#else
#define COUNT(x) ((void)0)
#endif

/* Lock order is registry -> wrapper. Native I/O and close run without either
   lock. A registry pin protects every operation, waiter and close caller from
   the last alias release. Only CLOSED storage with no owners or pins is freed. */
static PureMidiStream *find(PureMidiStream *identity) {
  PureMidiStream *s;for(s=streams;s && s!=identity;s=s->next){}return s;
}
static PureMidiStream *pin(PureMidiStream *identity,int operation) {
  PureMidiStream *s;lock(&registry_mutex);s=find(identity);
  if(s && (!operation || !transitioning) && s->users<SIZE_MAX) ++s->users;else s=NULL;
  unlock(&registry_mutex);return s;
}
static void unpin(PureMidiStream *s) {
  PureMidiStream **p;int destroy;
  lock(&registry_mutex);--s->users;lock(&s->mutex);
  destroy=!s->users && !s->references && s->state==PURE_MIDI_CLOSED;
  unlock(&s->mutex);
  if(destroy) {
    for(p=&streams;*p!=s;p=&(*p)->next){}
    *p=s->next;sync_destroy(&s->mutex,&s->condition);api->deallocate(s);COUNT(freed);
  }
  unlock(&registry_mutex);
}
int pure_midi_retain(PureMidiStream *identity) {
  PureMidiStream *s;int r=pmBadPtr;lock(&registry_mutex);s=find(identity);
  if(s && s->references && s->references<SIZE_MAX) { ++s->references;r=pmNoError; }
  unlock(&registry_mutex);return r;
}
static void finish_close(PureMidiStream *s,int r) {
  lock(&registry_mutex);lock(&s->mutex);s->result=r;
  s->state=r==pmNoError?PURE_MIDI_CLOSED:PURE_MIDI_FAILED;
  if(r==pmNoError)s->native=NULL;
  else if(!process_failure)process_failure=r;
  notify(&s->condition);unlock(&s->mutex);unlock(&registry_mutex);
}
static int close_pinned(PureMidiStream *s) {
  int r;uint64_t deadline=milliseconds()+2000;
  lock(&s->mutex);
  while(s->state==PURE_MIDI_CLOSING) {
    if(!wait_until(&s->condition,&s->mutex,deadline) && s->state==PURE_MIDI_CLOSING) {
      unlock(&s->mutex);return pmHostError;
    }
  }
  if(s->state!=PURE_MIDI_OPEN) { r=s->result;unlock(&s->mutex);return r; }
  s->state=PURE_MIDI_CLOSING;notify(&s->condition);unlock(&s->mutex);
  if(api->wake)api->wake(s->native);
  lock(&s->mutex);
  while(s->active) {
    if(!wait_until(&s->condition,&s->mutex,deadline) && s->active) {
      unlock(&s->mutex);finish_close(s,pmHostError);return pmHostError;
    }
  }
  unlock(&s->mutex);
  lock(&registry_mutex);COUNT(close_attempts);unlock(&registry_mutex);
  r=api->close(s->native);finish_close(s,r);return r;
}
int pure_midi_close(PureMidiStream *identity) {
  PureMidiStream *s=pin(identity,0);int r;
  if(!s)return pmBadPtr;r=close_pinned(s);unpin(s);return r;
}
void pure_midi_release(PureMidiStream *identity) {
  PureMidiStream *s;int last=0;lock(&registry_mutex);s=find(identity);
  if(s && s->references) { last=--s->references==0;++s->users; } else s=NULL;
  unlock(&registry_mutex);if(!s)return;
  if(last)(void)close_pinned(s);unpin(s);
}
int pure_midi_state(PureMidiStream *identity) {
  PureMidiStream *s=pin(identity,0);int r=0;
  if(s) { lock(&s->mutex);r=s->state;unlock(&s->mutex);unpin(s); }return r;
}
int pure_midi_valid(PureMidiStream *identity,int direction) {
  PureMidiStream *s=pin(identity,1);int r=0;
  if(s) { lock(&s->mutex);r=s->state==PURE_MIDI_OPEN && (!direction || (int)s->direction==direction);unlock(&s->mutex);unpin(s); }return r;
}
static PureMidiStream *enter(PureMidiStream *identity,int direction) {
  PureMidiStream *s=pin(identity,1);uint64_t deadline=milliseconds()+2000;
  if(!s)return NULL;lock(&s->mutex);
  while(s->state==PURE_MIDI_OPEN && s->active && (int)s->direction==direction) {
    if(!wait_until(&s->condition,&s->mutex,deadline))break;
  }
  if(s->state!=PURE_MIDI_OPEN || s->active || (int)s->direction!=direction) {
    unlock(&s->mutex);unpin(s);return NULL;
  }
  ++s->active;unlock(&s->mutex);return s;
}
static int leave(PureMidiStream *s,int r) {
  lock(&s->mutex);--s->active;notify(&s->condition);unlock(&s->mutex);unpin(s);return r;
}
int pure_midi_read(PureMidiStream *identity,PmEvent *buffer,int length) {
  PureMidiStream *s=enter(identity,PURE_MIDI_INPUT);if(!s)return pmBadPtr;
  return leave(s,(!buffer || (uintptr_t)buffer%_Alignof(PmEvent) || length<=0)?pmBadData:api->read(s->native,buffer,length));
}
int pure_midi_write(PureMidiStream *identity,PmEvent *buffer,int length) {
  PureMidiStream *s=enter(identity,PURE_MIDI_OUTPUT);if(!s)return pmBadPtr;
  return leave(s,(!buffer || (uintptr_t)buffer%_Alignof(PmEvent) || length<=0)?pmBadData:api->write(s->native,buffer,length));
}
int pure_midi_write_short(PureMidiStream *identity,int when,int message) {
  PureMidiStream *s=enter(identity,PURE_MIDI_OUTPUT);if(!s)return pmBadPtr;
  return leave(s,when<0?pmBadData:api->write_short(s->native,when,(PmMessage)message));
}
int pure_midi_write_sysex(PureMidiStream *identity,int when,unsigned char *message,int length) {
  int valid=when>=0 && message && length>=2,i;
  PureMidiStream *s=enter(identity,PURE_MIDI_OUTPUT);if(!s)return pmBadPtr;
  if(valid) { valid=message[0]==0xf0 && message[length-1]==0xf7;for(i=1;valid && i<length-1;i++)valid=message[i]<128; }
  return leave(s,valid?api->write_sysex(s->native,when,message):pmBadData);
}
int pure_midi_abort(PureMidiStream *identity) { PureMidiStream *s=enter(identity,PURE_MIDI_OUTPUT);return s?leave(s,api->abort(s->native)):pmBadPtr; }
int pure_midi_poll(PureMidiStream *identity) { PureMidiStream *s=enter(identity,PURE_MIDI_INPUT);return s?leave(s,api->poll(s->native)):pmBadPtr; }
int pure_midi_set_filter(PureMidiStream *identity,int filters) { PureMidiStream *s=enter(identity,PURE_MIDI_INPUT);return s?leave(s,api->set_filter(s->native,filters)):pmBadPtr; }
int pure_midi_set_channel_mask(PureMidiStream *identity,int channels) { PureMidiStream *s=enter(identity,PURE_MIDI_INPUT);return s?leave(s,api->set_channel_mask(s->native,channels)):pmBadPtr; }

/* Called with the registry lock. The timer starts before native open because
   PortMidi may otherwise start it implicitly, hiding ownership and failures. */
static int initialize_locked(void) {
  int r;
  if(process_failure)return process_failure;
  if(initialized)return pmNoError;
  r=api->initialize();if(r)return r;initialized=1;
  r=api->timer_start(1,NULL,NULL);
  if(r==ptAlreadyStarted)return pmNoError; /* borrowed timer */
  if(r) {
    int cleanup=api->terminate();if(!cleanup)initialized=0;else process_failure=cleanup;
    return r;
  }
  timer_started=1;return pmNoError;
}
static int open_stream(PureMidiStream **out,int id,int size,PmTimeProcPtr time_proc,void *time_info,int latency,PureMidiDirection direction) {
  PureMidiStream *s;const PmDeviceInfo *info;int r;
  if(!out)return pmBadPtr;*out=NULL;
  if(size<0)return pmBadData;if(id<0)return pmInvalidDeviceId;
  lock(&registry_mutex);
  if(transitioning || process_failure) { r=process_failure?process_failure:pmBadPtr;unlock(&registry_mutex);return r; }
  r=initialize_locked();if(r) { unlock(&registry_mutex);return r; }
  info=api->device_info(id);
  if(!info || info->opened || (direction==PURE_MIDI_INPUT?!info->input:!info->output)) { unlock(&registry_mutex);return pmInvalidDeviceId; }
  s=api->allocate(sizeof(*s));if(!s) { unlock(&registry_mutex);return pmInsufficientMemory; }
  COUNT(allocated);memset(s,0,sizeof(*s));mutex_init(&s->mutex);condition_init(&s->condition);
  s->direction=direction;s->state=PURE_MIDI_OPEN;s->references=1;
  r=direction==PURE_MIDI_INPUT?api->open_input(&s->native,id,NULL,size,time_proc,time_info):api->open_output(&s->native,id,NULL,size,time_proc,time_info,latency);
  if(!r && !s->native)r=pmBadPtr;
  if(r) {
    if(s->native) {
      int cleanup;COUNT(close_attempts);cleanup=api->close(s->native);
      if(cleanup) { s->state=PURE_MIDI_FAILED;s->result=cleanup;s->references=0;s->next=streams;streams=s;process_failure=cleanup;unlock(&registry_mutex);return r; }
    }
    sync_destroy(&s->mutex,&s->condition);api->deallocate(s);COUNT(freed);unlock(&registry_mutex);return r;
  }
  s->next=streams;streams=s;*out=s;unlock(&registry_mutex);return pmNoError;
}
int pure_midi_open_input(PureMidiStream **out,int id,int size,PmTimeProcPtr proc,void *info) { return open_stream(out,id,size,proc,info,0,PURE_MIDI_INPUT); }
int pure_midi_open_output(PureMidiStream **out,int id,int size,PmTimeProcPtr proc,void *info,int latency) { return open_stream(out,id,size,proc,info,latency,PURE_MIDI_OUTPUT); }

static int process_transition(int restart) {
  PureMidiStream *s;int r=0;uint64_t deadline=milliseconds()+4000;
  lock(&registry_mutex);
  while(transitioning)if(!wait_until(&registry_condition,&registry_mutex,deadline)) { unlock(&registry_mutex);return pmHostError; }
  transitioning=1;
  /* Visit each registry entry once, pinning its successor before unlocking.
     New opens are excluded by transitioning; alias releases may unlink only
     unpinned closed entries. A concurrent close that times out still owns its
     own pin/native handle, and must not prevent closing the rest of the list. */
  s=streams;
  if(s)++s->users;
  while(s) {
    PureMidiStream *next=s->next;
    if(next)++next->users;
    unlock(&registry_mutex);r=close_pinned(s);unpin(s);lock(&registry_mutex);
    if(r && !process_failure)process_failure=r;
    s=next;
  }
  if(!process_failure) {
    if(timer_started) {
      r=api->timer_stop();if(!r || r==ptAlreadyStopped)timer_started=0;else process_failure=r;
    }
    if(initialized) {
      r=api->terminate();if(!r)initialized=0;else if(!process_failure)process_failure=r;
    }
  }
  r=process_failure;
  if(!r && restart)r=initialize_locked();
  transitioning=0;notify(&registry_condition);unlock(&registry_mutex);return r;
}
int pure_midi_start(void) { return process_transition(1); }
int pure_midi_stop(void) { return process_transition(0); }

#ifdef PURE_MIDI_TEST_SEAM
int pure_midi_test_set_api(const PureMidiApi *replacement) {
  int r=pmBadPtr;lock(&registry_mutex);
  if(!streams && !initialized && !timer_started && !process_failure && !transitioning && replacement &&
     replacement->initialize && replacement->terminate && replacement->device_info &&
     replacement->open_input && replacement->open_output && replacement->close &&
     replacement->abort && replacement->poll && replacement->set_filter && replacement->set_channel_mask &&
     replacement->read && replacement->write && replacement->write_short && replacement->write_sysex &&
     replacement->timer_start && replacement->timer_stop && replacement->allocate && replacement->deallocate) {
    api=replacement;allocated=freed=close_attempts=0;r=0;
  }
  unlock(&registry_mutex);return r;
}
PureMidiResources pure_midi_test_resources(void) {
  PureMidiResources r={0};PureMidiStream *s;lock(&registry_mutex);
  for(s=streams;s;s=s->next) {
    lock(&s->mutex);++r.wrappers;r.references+=s->references;r.active+=s->active;
    r.live+=s->state==PURE_MIDI_OPEN || s->state==PURE_MIDI_CLOSING;
    r.quarantined+=s->state==PURE_MIDI_FAILED;unlock(&s->mutex);
  }
  r.allocated=allocated;r.freed=freed;r.close_attempts=close_attempts;
  r.initialized=initialized;r.timer_started=timer_started;r.failure=process_failure;
  unlock(&registry_mutex);return r;
}
#endif
