/* Failure injection is below the real ownership protocol. No MIDI device is
   opened: the dispatch returns tracked heap handles and fixed device records. */
#ifdef PURE_MIDI_LIFECYCLE_BASELINE
#include <pure/runtime.h>
#include <stdio.h>
int main(int argc, char **argv)
{
  int32_t ok=0;
  pure_interp *interp=pure_create_interp(argc,argv);
  pure_expr *value;
  if (!interp) return 2;
  pure_eval("using midi; let owned=midi::open_input 0 0; let alias=owned;");
  value=pure_eval("midi::streamp owned && midi::streamp alias;");
  if (!value || !pure_is_int(value,&ok) || !ok) return 2;
  pure_eval("midi::stop;");
  value=pure_eval("~midi::streamp owned && ~midi::streamp alias;");
  if (!value || !pure_is_int(value,&ok)) return 2;
  if (!ok) {
    fprintf(stderr,"FAIL: stop left owned stream and alias usable after native termination\n");
    return 1;
  }
  pure_delete_interp(interp);
  return 0;
}
#else
#include "../midi_stream.h"
#include <windows.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define CHECK(x) do { if (!(x)) { fprintf(stderr,"FAIL line %d: %s\n",__LINE__,#x); ExitProcess(1); } } while (0)
enum { FAIL_NONE, FAIL_ALLOC, FAIL_INIT, FAIL_DEVICE, FAIL_INPUT, FAIL_OUTPUT,
       FAIL_TIMER_START, FAIL_READ, FAIL_WRITE, FAIL_ABORT, FAIL_CLOSE,
       FAIL_TERMINATE, FAIL_TIMER_STOP, FAIL_PARTIAL_INPUT, FAIL_PARTIAL_OUTPUT,
       FAIL_PARTIAL_CLOSE, FAIL_TIMER_ROLLBACK, FAIL_NULL_OPEN };
static int failure, native_live, memory_live, init_live, timer_live;
static LONG reads,writes,closes,aborts,wakes,terminates,timer_stops;
static int blocked, ignore_wake;
static HANDLE entered, released, closing;
static HANDLE native_close_entered, native_close_released;
static PortMidiStream *last_opened_native, *blocked_native_close;
static SRWLOCK fake_lock=SRWLOCK_INIT;
static char events[256];
static size_t event_count;
typedef struct { int direction; LONG active; } FakeStream;
static void event(char e) { AcquireSRWLockExclusive(&fake_lock); CHECK(event_count<255); events[event_count++]=e; events[event_count]=0; ReleaseSRWLockExclusive(&fake_lock); }
static PmError initialize(void) { event('I'); if (failure==FAIL_INIT) return pmHostError; CHECK(!init_live); init_live=1; return pmNoError; }
static PmError terminate(void) { event('T'); InterlockedIncrement(&terminates); CHECK(!native_live); if (failure==FAIL_TERMINATE || failure==FAIL_TIMER_ROLLBACK) return pmHostError; CHECK(init_live); init_live=0; return pmNoError; }
static const PmDeviceInfo *device_info(int id) {
  static const PmDeviceInfo input={.structVersion=1,.interf="fake",.name="input",.input=1};
  static const PmDeviceInfo output={.structVersion=1,.interf="fake",.name="output",.output=1};
  static const PmDeviceInfo opened={.structVersion=1,.interf="fake",.name="opened",.input=1,.output=1,.opened=1};
  event('D'); if (failure==FAIL_DEVICE) return NULL;
  return id==0 ? &input : id==1 ? &output : id==2 ? &opened : NULL;
}
static PmError open_common(PortMidiStream **out,int id,int size,int direction) {
  FakeStream *s; event(direction==1?'i':'o'); CHECK(init_live && timer_live && id==direction-1 && size>=0);
  if (failure==(direction==1?FAIL_INPUT:FAIL_OUTPUT)) return pmHostError;
  if (failure==FAIL_NULL_OPEN) return pmNoError;
  s=calloc(1,sizeof(*s)); CHECK(s); s->direction=direction; native_live++; *out=s; last_opened_native=s;
  return failure==(direction==1?FAIL_PARTIAL_INPUT:FAIL_PARTIAL_OUTPUT) || failure==FAIL_PARTIAL_CLOSE ? pmHostError : pmNoError;
}
static PmError open_input(PortMidiStream **s,int id,void *driver,int32_t n,PmTimeProcPtr p,void *info) { (void)p;(void)info;CHECK(!driver);return open_common(s,id,n,1); }
static PmError open_output(PortMidiStream **s,int id,void *driver,int32_t n,PmTimeProcPtr p,void *info,int32_t latency) { (void)p;(void)info;(void)latency;CHECK(!driver);return open_common(s,id,n,2); }
static PmError close_stream(PortMidiStream *ptr) {
  FakeStream *s=ptr; event('C'); InterlockedIncrement(&closes); CHECK(s && !s->active);
  if(ptr==blocked_native_close) {
    CHECK(SetEvent(native_close_entered));
    CHECK(WaitForSingleObject(native_close_released,5000)==WAIT_OBJECT_0);
  }
  if (failure==FAIL_CLOSE || failure==FAIL_PARTIAL_CLOSE) return pmHostError;
  free(s); native_live--; return pmNoError;
}
static PmError abort_stream(PortMidiStream *ptr) { FakeStream *s=ptr; CHECK(s && s->direction==2); InterlockedIncrement(&aborts);return failure==FAIL_ABORT?pmHostError:pmNoError; }
static PmError poll_stream(PortMidiStream *ptr) { CHECK(ptr); return pmNoError; }
static PmError filter(PortMidiStream *ptr,int32_t mask) { (void)mask; CHECK(((FakeStream*)ptr)->direction==1); return pmNoError; }
static int io(PortMidiStream *ptr,int direction) {
  FakeStream *s=ptr; CHECK(s && s->direction==direction); CHECK(InterlockedIncrement(&s->active)==1);
  if (direction==1) InterlockedIncrement(&reads); else InterlockedIncrement(&writes);
  if (blocked) { SetEvent(entered); CHECK(WaitForSingleObject(released,5000)==WAIT_OBJECT_0); }
  InterlockedDecrement(&s->active);
  if (failure==(direction==1?FAIL_READ:FAIL_WRITE)) return pmHostError;
  return direction==1?1:0;
}
static int read_stream(PortMidiStream *s,PmEvent *b,int32_t n) { CHECK(b && n>0); b[0].message=0x403c90; b[0].timestamp=42; return io(s,1); }
static PmError write_stream(PortMidiStream *s,PmEvent *b,int32_t n) { CHECK(b && n>0); return (PmError)io(s,2); }
static PmError short_stream(PortMidiStream *s,PmTimestamp t,PmMessage m) { (void)t;(void)m;return (PmError)io(s,2); }
static PmError sysex_stream(PortMidiStream *s,PmTimestamp t,unsigned char *b) { (void)t;CHECK(b);return (PmError)io(s,2); }
static PtError timer_start(int n,PtCallback *cb,void *info) { event('S');CHECK(n==1 && !cb && !info); if(failure==FAIL_TIMER_START || failure==FAIL_TIMER_ROLLBACK)return ptHostError;CHECK(!timer_live);timer_live=1;return ptNoError; }
static PtError timer_stop(void) { event('s');InterlockedIncrement(&timer_stops);if(failure==FAIL_TIMER_STOP)return ptHostError;CHECK(timer_live);timer_live=0;return ptNoError; }
static void *allocate(size_t n) { void *p;event('A');if(failure==FAIL_ALLOC)return NULL;p=malloc(n);if(p)memory_live++;return p; }
static void deallocate(void *p) { CHECK(p && memory_live>0);event('F');memory_live--;free(p); }
static void wake(PortMidiStream *s) { CHECK(s);InterlockedIncrement(&wakes);if(closing)SetEvent(closing);if(!ignore_wake && released)SetEvent(released); }
static const PureMidiApi api={initialize,terminate,device_info,open_input,open_output,
  close_stream,abort_stream,poll_stream,filter,filter,read_stream,write_stream,
  short_stream,sysex_stream,timer_start,timer_stop,allocate,deallocate,wake};
static PureMidiStream *open_stream(int direction) {
  PureMidiStream *s=NULL;
  int r=direction==1?pure_midi_open_input(&s,0,0,NULL,NULL):pure_midi_open_output(&s,1,0,NULL,NULL,0);
  CHECK(r==0 && s);return s;
}
static void clean(void) {
  PureMidiResources r=pure_midi_test_resources();
  CHECK(!r.wrappers && !r.live && !r.quarantined && !r.active && !r.references);
  CHECK(r.allocated==r.freed && !r.initialized && !r.timer_started && !r.failure);
  CHECK(!native_live && !memory_live && !init_live && !timer_live);
}
static void failure_case(int which,const char *expected_events) {
  PureMidiStream *s=(PureMidiStream*)(uintptr_t)1;
  PureMidiResources r;
  failure=which;
  CHECK(pure_midi_open_input(NULL,0,0,NULL,NULL)==pmBadPtr);
  if (which==FAIL_OUTPUT || which==FAIL_PARTIAL_OUTPUT)
    CHECK(pure_midi_open_output(&s,1,0,NULL,NULL,0)<0 && !s);
  else CHECK(pure_midi_open_input(&s,0,0,NULL,NULL)<0 && !s);
  CHECK(!memory_live && !native_live);
  r=pure_midi_test_resources();CHECK(!r.wrappers && !r.references && r.allocated==r.freed);
  failure=FAIL_NONE;CHECK(pure_midi_stop()==0);clean();
  CHECK(!strcmp(events,expected_events));
  if (which==FAIL_TIMER_START) CHECK(strstr(events,"ST")!=NULL);
  if (which==FAIL_PARTIAL_INPUT || which==FAIL_PARTIAL_OUTPUT) CHECK(strstr(events,"CF")!=NULL);
}
static void matrix(void) {
  int i; PureMidiStream *in,*out,*bad=NULL; PmEvent b={0x403c90,0};
  const struct { int failure;const char *events; } failures[]={
    {FAIL_ALLOC,"ISDAsT"},{FAIL_INIT,"I"},{FAIL_DEVICE,"ISDsT"},
    {FAIL_INPUT,"ISDAiFsT"},{FAIL_OUTPUT,"ISDAoFsT"},{FAIL_TIMER_START,"IST"},
    {FAIL_PARTIAL_INPUT,"ISDAiCFsT"},{FAIL_PARTIAL_OUTPUT,"ISDAoCFsT"},
    {FAIL_NULL_OPEN,"ISDAiFsT"}};
  for(size_t n=0;n<sizeof(failures)/sizeof(failures[0]);n++) { event_count=0; failure_case(failures[n].failure,failures[n].events); }
  CHECK(pure_midi_open_input(&bad,-1,0,NULL,NULL)==pmInvalidDeviceId && !bad);
  CHECK(pure_midi_open_input(&bad,1,0,NULL,NULL)==pmInvalidDeviceId && !bad);
  CHECK(pure_midi_open_output(&bad,0,0,NULL,NULL,0)==pmInvalidDeviceId && !bad);
  CHECK(pure_midi_open_input(&bad,2,0,NULL,NULL)==pmInvalidDeviceId && !bad);
  CHECK(pure_midi_open_input(&bad,0,-1,NULL,NULL)==pmBadData && !bad);
  /* Negative latency remains the documented immediate-output mode. */
  CHECK(pure_midi_open_output(&out,1,0,NULL,NULL,-1)==0);pure_midi_release(out);
  in=open_stream(1);out=open_stream(2);
  CHECK(pure_midi_read(out,&b,1)==pmBadPtr && pure_midi_write(in,&b,1)==pmBadPtr);
  CHECK(pure_midi_poll(out)==pmBadPtr && pure_midi_abort(in)==pmBadPtr);
  CHECK(pure_midi_set_filter(out,0)==pmBadPtr && pure_midi_set_channel_mask(out,1)==pmBadPtr);
  CHECK(pure_midi_read(in,NULL,1)==pmBadData && pure_midi_write(out,&b,-1)==pmBadData);
  CHECK(pure_midi_write_short(out,-1,0x403c90)==pmBadData);
  CHECK(pure_midi_write_sysex(out,0,(unsigned char*)"\xf0\xf7",1)==pmBadData);
  failure=FAIL_READ;CHECK(pure_midi_read(in,&b,1)==pmHostError);
  failure=FAIL_WRITE;CHECK(pure_midi_write(out,&b,1)==pmHostError);
  failure=FAIL_ABORT;CHECK(pure_midi_abort(out)==pmHostError);
  failure=FAIL_NONE;CHECK(pure_midi_read(in,&b,1)==1 && b.message==0x403c90 && b.timestamp==42);
  CHECK(pure_midi_set_filter(in,1)==0 && pure_midi_set_channel_mask(in,1)==0);
  CHECK(pure_midi_write(out,&b,1)==0 && pure_midi_abort(out)==0);
  CHECK(pure_midi_retain(in)==0);CHECK(pure_midi_retain(in)==0);
  i=(int)closes;CHECK(pure_midi_close(in)==0 && pure_midi_close(in)==0 && closes==i+1);
  CHECK(!pure_midi_valid(in,0) && pure_midi_state(in)==PURE_MIDI_CLOSED);
  CHECK(pure_midi_read(in,&b,1)==pmBadPtr);
  pure_midi_release(in);pure_midi_release(in);pure_midi_release(in);
  CHECK(pure_midi_start()==0 && !pure_midi_valid(out,0));pure_midi_release(out);
  CHECK(pure_midi_stop()==0 && pure_midi_stop()==0);clean();
  puts("PASS lifecycle failure matrix: allocation/init/device/input/output/timer/read/write/abort, aliases, restart; zero net resources");
}
static void quarantine(int which) {
  PureMidiStream *s=open_stream(2);PureMidiResources r;PmEvent b={0x403c90,0};
  CHECK(pure_midi_retain(s)==0);failure=which;
  CHECK(pure_midi_stop()==pmHostError);
  r=pure_midi_test_resources();CHECK(r.failure==pmHostError);
  CHECK(pure_midi_stop()==pmHostError && pure_midi_start()==pmHostError);
  if(which==FAIL_CLOSE) {
    CHECK(pure_midi_state(s)==PURE_MIDI_FAILED && !pure_midi_valid(s,0));
    CHECK(pure_midi_close(s)==pmHostError && pure_midi_write(s,&b,1)==pmBadPtr);
    CHECK(closes==1 && !terminates && !timer_stops && native_live==1);
    pure_midi_release(s);pure_midi_release(s);r=pure_midi_test_resources();
    CHECK(r.wrappers==1 && r.quarantined==1 && r.references==0 && r.active==0 && r.allocated==1 && !r.freed);
  } else {
    pure_midi_release(s);pure_midi_release(s);
    CHECK(closes==1 && terminates==1 && timer_stops==1 && !memory_live && !native_live);
  }
  printf("PASS permanent cleanup failure %d: closes=%ld terminate=%ld timer-stop=%ld native=%d memory=%d\n",which,closes,terminates,timer_stops,native_live,memory_live);
}
static void multiple_close_failure(void) {
  PureMidiStream *first=open_stream(2),*second=open_stream(2);
  PureMidiResources r;failure=FAIL_CLOSE;
  CHECK(pure_midi_stop()==pmHostError);
  CHECK(closes==2); /* An earlier failure must not strand another owned stream. */
  CHECK(!pure_midi_valid(first,0) && !pure_midi_valid(second,0));
  pure_midi_release(first);pure_midi_release(second);r=pure_midi_test_resources();
  CHECK(r.quarantined==2 && r.wrappers==2 && !r.live && !r.active && !r.references);
  CHECK(native_live==2 && memory_live==2 && !terminates && !timer_stops);
  CHECK(pure_midi_stop()==pmHostError && closes==2);
  puts("PASS multiple failed closes: two quarantines, no live streams, no repeated native close or termination");
}
static void partial_failure(int which) {
  PureMidiStream *s=(PureMidiStream*)(uintptr_t)1;PureMidiResources r;
  failure=which;CHECK(pure_midi_open_input(&s,0,0,NULL,NULL)==pmHostError && !s);
  CHECK(pure_midi_stop()==pmHostError && pure_midi_start()==pmHostError);
  r=pure_midi_test_resources();CHECK(r.failure==pmHostError && !r.active && !r.references && !r.live);
  if(which==FAIL_PARTIAL_CLOSE) {
    CHECK(r.quarantined==1 && r.wrappers==1 && r.allocated==1 && !r.freed);
    CHECK(native_live==1 && memory_live==1 && closes==1 && !terminates && !timer_stops);
    CHECK(!strcmp(events,"ISDAiC"));
  } else {
    CHECK(!r.wrappers && !r.allocated && !r.freed && !r.timer_started && r.initialized);
    CHECK(!native_live && !memory_live && !closes && terminates==1 && !timer_stops);
    CHECK(!strcmp(events,"IST"));
  }
  printf("PASS partial failure %d: exact reverse cleanup, no usable wrapper, permanently blocked restart\n",which);
}
typedef struct { PureMidiStream *s; int operation,result; } Job;
static DWORD WINAPI run_job(void *data) {
  Job *j=data;PmEvent b={0x403c90,0};
  if(j->operation==4) { pure_midi_release(j->s);j->result=0;return 0; }
  j->result=j->operation==0?pure_midi_close(j->s):j->operation==3?pure_midi_stop():
    j->operation==1?pure_midi_read(j->s,&b,1):pure_midi_write(j->s,&b,1);
  return 0;
}
static void race(int direction,int timeout,int release_alias) {
  PureMidiStream *s=open_stream(direction);PureMidiResources r;PmEvent b={0x403c90,0};
  Job io_job={s,direction,123},close_job={s,release_alias?4:0,123},stop_job={s,3,123};HANDLE threads[3];
  entered=CreateEvent(NULL,TRUE,FALSE,NULL);released=CreateEvent(NULL,TRUE,FALSE,NULL);closing=CreateEvent(NULL,TRUE,FALSE,NULL);
  CHECK(entered && released && closing);blocked=1;ignore_wake=1;
  threads[0]=CreateThread(NULL,0,run_job,&io_job,0,NULL);CHECK(threads[0]);
  CHECK(WaitForSingleObject(entered,2000)==WAIT_OBJECT_0);
  threads[1]=CreateThread(NULL,0,run_job,&close_job,0,NULL);CHECK(threads[1]);
  CHECK(WaitForSingleObject(closing,2000)==WAIT_OBJECT_0);
  r=pure_midi_test_resources();CHECK(r.active==1 && r.live==1 && !r.freed && !closes);
  CHECK(r.references==(release_alias?0U:1U));
  CHECK(!pure_midi_valid(s,0));CHECK(pure_midi_read(s,&b,1)==pmBadPtr && pure_midi_write(s,&b,1)==pmBadPtr);
  CHECK(WaitForSingleObject(threads[1],0)==WAIT_TIMEOUT);
  threads[2]=CreateThread(NULL,0,run_job,&stop_job,0,NULL);CHECK(threads[2]);
  if(timeout) CHECK(WaitForSingleObject(threads[1],3500)==WAIT_OBJECT_0);
  SetEvent(released);CHECK(WaitForMultipleObjects(3,threads,TRUE,4000)==WAIT_OBJECT_0);
  CHECK(io_job.result==(direction==1?1:0));
  if(timeout) {
    CHECK(close_job.result==pmHostError && stop_job.result==pmHostError && !closes && !terminates);
    pure_midi_release(s);r=pure_midi_test_resources();CHECK(r.quarantined==1 && !r.active && !r.references && r.wrappers==1);
  } else {
    CHECK(close_job.result==0 && stop_job.result==0 && closes==1 && terminates==1 && timer_stops==1 && wakes==1);
    CHECK(reads==(direction==1) && writes==(direction==2));pure_midi_release(s);clean();
  }
  for(int i=0;i<3;i++)CHECK(CloseHandle(threads[i]));
  CHECK(CloseHandle(entered) && CloseHandle(released) && CloseHandle(closing));
  printf("PASS concurrent %s%s: read=%ld write=%ld close=%ld wake=%ld terminate=%ld timer-stop=%ld native=%d memory=%d\n",direction==1?"read":"write",timeout?" timeout quarantine":release_alias?" last-alias release":"",reads,writes,closes,wakes,terminates,timer_stops,native_live,memory_live);
}
static void automatic_wake(void) {
  PureMidiStream *s=open_stream(1);Job job={s,1,123};HANDLE thread;
  entered=CreateEvent(NULL,TRUE,FALSE,NULL);released=CreateEvent(NULL,TRUE,FALSE,NULL);
  CHECK(entered && released);blocked=1;
  thread=CreateThread(NULL,0,run_job,&job,0,NULL);CHECK(thread);
  CHECK(WaitForSingleObject(entered,2000)==WAIT_OBJECT_0);
  CHECK(pure_midi_close(s)==0);
  CHECK(WaitForSingleObject(thread,2000)==WAIT_OBJECT_0 && job.result==1);
  CHECK(reads==1 && !writes && closes==1 && wakes==1);
  pure_midi_release(s);CHECK(pure_midi_stop()==0);clean();
  CHECK(CloseHandle(thread) && CloseHandle(entered) && CloseHandle(released));
  puts("PASS close wakes blocked backend: exactly one read/wake/close, zero net resources");
}
static void pending_close_shutdown(void) {
  PureMidiStream *later=open_stream(2),*head=open_stream(2);
  PureMidiResources r;PmEvent b={0x403c90,0};
  Job close_job={head,0,123},stop_job={NULL,3,123};HANDLE close_thread,stop_thread;
  blocked_native_close=last_opened_native;
  native_close_entered=CreateEvent(NULL,TRUE,FALSE,NULL);
  native_close_released=CreateEvent(NULL,TRUE,FALSE,NULL);
  CHECK(native_close_entered && native_close_released);
  close_thread=CreateThread(NULL,0,run_job,&close_job,0,NULL);CHECK(close_thread);
  CHECK(WaitForSingleObject(native_close_entered,2000)==WAIT_OBJECT_0);
  stop_thread=CreateThread(NULL,0,run_job,&stop_job,0,NULL);CHECK(stop_thread);
  CHECK(WaitForSingleObject(stop_thread,3500)==WAIT_OBJECT_0 && stop_job.result==pmHostError);
  /* The original defect returned from stop with this later stream still OPEN. */
  CHECK(!pure_midi_valid(later,0));
  CHECK(pure_midi_write(later,&b,1)==pmBadPtr && !pure_midi_valid(head,0));
  CHECK(pure_midi_write(head,&b,1)==pmBadPtr && !reads && !writes);
  CHECK(pure_midi_state(later)==PURE_MIDI_CLOSED && pure_midi_state(head)==PURE_MIDI_CLOSING);
  CHECK(WaitForSingleObject(close_thread,0)==WAIT_TIMEOUT);
  r=pure_midi_test_resources();
  CHECK(r.wrappers==2 && r.live==1 && !r.quarantined && !r.active && r.references==2);
  CHECK(r.allocated==2 && !r.freed && r.close_attempts==2 && r.failure==pmHostError);
  CHECK(r.initialized==1 && r.timer_started==1 && closes==2 && wakes==2 && !terminates && !timer_stops);
  CHECK(native_live==1 && memory_live==2);
  pure_midi_release(later);
  r=pure_midi_test_resources();CHECK(r.wrappers==1 && r.live==1 && r.references==1 && r.freed==1);
  CHECK(native_live==1 && memory_live==1);
  CHECK(SetEvent(native_close_released));
  CHECK(WaitForSingleObject(close_thread,2000)==WAIT_OBJECT_0 && close_job.result==0);
  CHECK(pure_midi_state(head)==PURE_MIDI_CLOSED && pure_midi_close(head)==0);
  pure_midi_release(head);
  CHECK(pure_midi_stop()==pmHostError && pure_midi_start()==pmHostError);
  r=pure_midi_test_resources();
  CHECK(!r.wrappers && !r.live && !r.quarantined && !r.active && !r.references);
  CHECK(r.allocated==2 && r.freed==2 && r.close_attempts==2 && r.failure==pmHostError);
  CHECK(!native_live && !memory_live && closes==2 && wakes==2 && !terminates && !timer_stops);
  CHECK(init_live==1 && timer_live==1 && !strcmp(events,"ISDAoDAoCCFF"));
  CHECK(CloseHandle(close_thread) && CloseHandle(stop_thread));
  CHECK(CloseHandle(native_close_entered) && CloseHandle(native_close_released));
  puts("PASS pending native close shutdown: later stream closed/rejects I/O; close=2 wake=2 terminate=0 timer-stop=0 allocated=2 freed=2 native=0 memory=0; sticky process failure");
}
/* Every scenario, including every stress iteration, is a fresh child process
   with a hard parent-enforced deadline independent of library/backend waits. */
static int child(const char *exe,const char *scenario) {
  char command[32768];STARTUPINFOA si={0};PROCESS_INFORMATION pi={0};DWORD code;
  CHECK(snprintf(command,sizeof(command),"\"%s\" --child %s",exe,scenario)>0);si.cb=sizeof(si);
  CHECK(CreateProcessA(exe,command,NULL,NULL,FALSE,CREATE_NO_WINDOW,NULL,NULL,&si,&pi));
  if(WaitForSingleObject(pi.hProcess,8000)!=WAIT_OBJECT_0) { TerminateProcess(pi.hProcess,124);CHECK(WaitForSingleObject(pi.hProcess,2000)==WAIT_OBJECT_0);fprintf(stderr,"FAIL independent 8-second deadline: %s\n",scenario);exit(1); }
  CHECK(GetExitCodeProcess(pi.hProcess,&code));CHECK(CloseHandle(pi.hThread) && CloseHandle(pi.hProcess));return (int)code;
}
int main(int argc,char **argv) {
  if(argc==3 && !strcmp(argv[1],"--child")) {
    CHECK(pure_midi_test_set_api(&api)==0);
    if(!strcmp(argv[2],"matrix"))matrix();
    else if(!strcmp(argv[2],"close"))quarantine(FAIL_CLOSE);
    else if(!strcmp(argv[2],"terminate"))quarantine(FAIL_TERMINATE);
    else if(!strcmp(argv[2],"timer"))quarantine(FAIL_TIMER_STOP);
    else if(!strcmp(argv[2],"read"))race(1,0,0);
    else if(!strcmp(argv[2],"write"))race(2,0,0);
    else if(!strcmp(argv[2],"release-read"))race(1,0,1);
    else if(!strcmp(argv[2],"release-write"))race(2,0,1);
    else if(!strcmp(argv[2],"timeout"))race(1,1,0);
    else if(!strcmp(argv[2],"wake"))automatic_wake();
    else if(!strcmp(argv[2],"pending-close"))pending_close_shutdown();
    else if(!strcmp(argv[2],"multiple"))multiple_close_failure();
    else if(!strcmp(argv[2],"partial-close"))partial_failure(FAIL_PARTIAL_CLOSE);
    else if(!strcmp(argv[2],"partial-timer"))partial_failure(FAIL_TIMER_ROLLBACK);
    else return 2;
    return 0;
  }
  { char exe[32768];const char *cases[]={"matrix","close","terminate","timer","timeout","multiple","partial-close","partial-timer","wake","pending-close"};
    const char *races[]={"read","write","release-read","release-write"};
    CHECK(GetModuleFileNameA(NULL,exe,sizeof(exe))>0);
    for(size_t i=0;i<sizeof(cases)/sizeof(cases[0]);i++)CHECK(child(exe,cases[i])==0);
    for(int i=0;i<200;i++)CHECK(child(exe,races[i%4])==0);
    puts("PASS lifecycle: 10 matrices + 200 deterministic concurrency processes; 8-second independent deadline each; exact per-case counters");
  }
  return 0;
}
#endif
