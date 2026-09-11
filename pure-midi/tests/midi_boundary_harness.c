#include <limits.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <pure/runtime.h>

#ifdef PURE_MIDI_BOUNDARY_FAKE

typedef struct PmEvent
{
	int32_t message;
	int32_t timestamp;
} PmEvent;

typedef struct BoundaryFakeBlock
{
  size_t size;
  int *data;
} BoundaryFakeBlock;

typedef struct BoundaryFakeMatrix
{
  size_t rows,cols,stride;
  int *data;
  BoundaryFakeBlock *block;
  int owner;
} BoundaryFakeMatrix;

static int boundary_calls;
static int input_stream;
static int output_stream;
static int read_messages[2], read_count, read_index;
static void *bad_buffer_bases[2], *bad_buffer_blocks[2], *bad_buffer_matrices[2];
static size_t bad_buffer_count;

void pure_midi_boundary_release_bad_buffers(void)
{
  size_t i;
  for (i=0;i<bad_buffer_count;++i) {
    BoundaryFakeMatrix *matrix=(BoundaryFakeMatrix *)bad_buffer_matrices[i];
    matrix->data=NULL;
    matrix->block=NULL;
    free(bad_buffer_bases[i]);
    free(bad_buffer_blocks[i]);
    bad_buffer_bases[i]=NULL;
    bad_buffer_blocks[i]=NULL;
    bad_buffer_matrices[i]=NULL;
  }
  bad_buffer_count=0;
}

pure_expr *pure_midi_boundary_bad_buffer(int kind)
{
  BoundaryFakeMatrix *m=malloc(sizeof(*m));
  BoundaryFakeBlock *b=malloc(sizeof(*b));
  if (!m || !b) { free(m); free(b); return NULL; }
  b->size=2; b->data=calloc(2,sizeof(int));
  if (!b->data) { free(b); free(m); return NULL; }
  m->rows=1; m->cols=2; m->stride=2; m->data=b->data; m->block=b; m->owner=1;
  if (kind==0) m->rows=((size_t)UINT32_MAX)+2;
  else if (kind==1) m->cols=m->stride=((size_t)UINT32_MAX)+3;
  else if (kind==2) m->rows=2; /* shape fits the ABI but exceeds its actual block */
  else if (kind==3) {
    b->size=3;
    free(b->data);
    b->data=calloc(3,sizeof(int));
    if (!b->data) { free(b); free(m); return NULL; }
    m->rows=1; m->cols=2; m->stride=2;
    m->data=(int *)((unsigned char *)b->data+1);
  } else if (kind==4) {
    unsigned char *base;
    pure_expr *value;
    if (bad_buffer_count==sizeof(bad_buffer_bases)/sizeof(bad_buffer_bases[0])) {
      free(b->data); free(b); free(m); return NULL;
    }
    base=calloc(1,2*sizeof(int)+1);
    if (!base) { free(b->data); free(b); free(m); return NULL; }
    value=pure_int_matrix(m);
    if (!value) { free(base); free(b->data); free(b); free(m); return NULL; }
    free(b->data);
    b->size=2;
    b->data=(int *)(base+1);
    m->data=b->data;
    m->owner=0;
    bad_buffer_bases[bad_buffer_count]=base;
    bad_buffer_blocks[bad_buffer_count]=b;
    bad_buffer_matrices[bad_buffer_count++]=m;
    return value;
  } else { free(b->data); free(b); free(m); return NULL; }
  return pure_int_matrix(m);
}

void pure_midi_boundary_read_queue(int first, int second, int count)
{
  read_messages[0]=first; read_messages[1]=second;
  read_count=(count>=0 && count<=2) ? count : 0; read_index=0;
}

int pure_midi_boundary_calls(void) { return boundary_calls; }
void pure_midi_boundary_reset_calls(void) { boundary_calls = 0; }

int Pm_Initialize(void) { boundary_calls++; return 0; }
int Pm_Terminate(void) { boundary_calls++; return 0; }
int Pm_CountDevices(void) { boundary_calls++; return 0; }
int Pm_GetDefaultInputDeviceID(void) { boundary_calls++; return -1; }
int Pm_GetDefaultOutputDeviceID(void) { boundary_calls++; return -1; }
const void *Pm_GetDeviceInfo(int id) {
  static const struct { int version; const char *interf,*name; int input,output,opened,is_virtual; }
    info={1,"boundary","fake",1,1,0,0};
  boundary_calls++; return id==0 ? &info : NULL;
}
int Pm_HasHostError(void *stream) { (void)stream; boundary_calls++; return 0; }
const char *Pm_GetErrorText(int error) { (void)error; boundary_calls++; return "boundary fake"; }
void Pm_GetHostErrorText(char *message, int length)
{
	boundary_calls++;
	if ((message != NULL) && (length > 0)) message[0] = '\0';
}
int Pm_OpenInput(void **stream, int id, void *input_driver_info, int buffer_size,
	void *time_proc, void *time_info)
{
	(void)id; (void)input_driver_info; (void)buffer_size; (void)time_proc; (void)time_info;
	boundary_calls++;
	*stream = &input_stream;
	return 0;
}
int Pm_OpenOutput(void **stream, int id, void *output_driver_info, int buffer_size,
	void *time_proc, void *time_info, int latency)
{
	(void)id; (void)output_driver_info; (void)buffer_size; (void)time_proc; (void)time_info;
	(void)latency;
	boundary_calls++;
	*stream = &output_stream;
	return 0;
}
int Pm_Read(void *stream, PmEvent *buffer, int length)
{
  boundary_calls++;
  if (stream!=&input_stream || !buffer || length<1 || read_index>=read_count) return -9995;
  buffer[0].message=read_messages[read_index++]; buffer[0].timestamp=42;
  return 1;
}
int Pm_Write(void *stream, PmEvent *buffer, int length)
{
	(void)stream; (void)buffer; (void)length; boundary_calls++; return -9995;
}
int Pm_WriteShort(void *stream, int when, int message)
{
	(void)stream; (void)when; (void)message; boundary_calls++; return -9995;
}
int Pm_WriteSysEx(void *stream, int when, unsigned char *message)
{
	(void)stream; (void)when; (void)message; boundary_calls++; return -9995;
}
int Pm_Close(void *stream) { (void)stream; boundary_calls++; return 0; }
int Pm_SetFilter(void *stream, int filters)
{
	(void)stream; (void)filters; boundary_calls++; return 0;
}
int Pm_SetChannelMask(void *stream, int channels)
{
	(void)stream; (void)channels; boundary_calls++; return 0;
}
int Pm_Abort(void *stream) { (void)stream; boundary_calls++; return 0; }
int Pm_Synchronize(void *stream) { (void)stream; boundary_calls++; return 0; }
int Pm_Poll(void *stream) { (void)stream; boundary_calls++; return 0; }
void Pt_Sleep(int duration) { (void)duration; boundary_calls++; }
int Pt_Start(int resolution, void *callback, void *user_data)
{
	(void)resolution; (void)callback; (void)user_data; boundary_calls++; return 0;
}
int Pt_Stop(void) { boundary_calls++; return 0; }
int Pt_Started(void) { boundary_calls++; return 1; }
int Pt_Time(void) { boundary_calls++; return 0; }

#else

#include "mf.h"
#include "../midi_bounds.h"
#include "midifile.h"
#include "midifile_test_api.h"

typedef struct BoundaryBlock
{
	size_t size;
	int *data;
} BoundaryBlock;

typedef struct BoundaryMatrix
{
	size_t size1;
	size_t size2;
	size_t tda;
	int *data;
	BoundaryBlock *block;
	int owner;
} BoundaryMatrix;

static int cases_run;

static int test_legacy_channels(void);
static int test_seven_bit_values(void);

static int fail(const char *message)
{
	fprintf(stderr, "FAIL: %s\n", message);
	return 0;
}

static pure_expr *make_matrix(size_t rows, size_t columns, const int *values)
{
	BoundaryMatrix *matrix = (BoundaryMatrix *)malloc(sizeof(*matrix));
	BoundaryBlock *block = (BoundaryBlock *)malloc(sizeof(*block));
	size_t count = rows * columns;
	if ((matrix == NULL) || (block == NULL))
	{
		free(matrix);
		free(block);
		return NULL;
	}
	block->size = count;
	block->data = (int *)malloc(count * sizeof(*block->data));
	if (block->data == NULL)
	{
		free(block);
		free(matrix);
		return NULL;
	}
	memcpy(block->data, values, count * sizeof(*values));
	matrix->size1 = rows;
	matrix->size2 = columns;
	matrix->tda = columns;
	matrix->data = block->data;
	matrix->block = block;
	matrix->owner = 1;
	return pure_int_matrix(matrix);
}

static int test_one_byte_meta(void)
{
	static const int bytes[] = {0xff};
	pure_expr *file = mf_new(1, 0, 96);
	pure_expr *matrix = make_matrix(1, 1, bytes);
	pure_expr *event;
	pure_expr *track;
	int accepted;
	if ((file == NULL) || (matrix == NULL)) return fail("could not construct one-byte meta fixture");
	event = pure_tuplel(2, pure_int(0), matrix);
	track = pure_listl(1, event);
	if ((event == NULL) || (track == NULL)) return fail("could not construct one-byte meta event");
	accepted = mf_put_track(file, track);
	cases_run++;
	pure_freenew(track);
	mf_free(file);
	pure_freenew(file);
	return accepted ? fail("one-byte meta event was accepted") : 1;
}

static int test_legacy_channels(void)
{
  static const int channels[][4]={{0x90,60,64,0},{0xc0,5,0,0},{0xd0,6,0,0}};
  size_t i;
  for (i=0;i<3;++i) {
    pure_expr *file=mf_new(1,0,96), *list, *decoded;
    pure_expr **events=NULL, **tuple=NULL;
    BoundaryMatrix *matrix=NULL;
    size_t count=0;
    int32_t tick=-1;
    list=pure_listl(1,pure_tuplel(2,pure_int(0),make_matrix(1,4,channels[i])));
    if (!mf_put_track(file,list)) return fail("legacy four-byte channel vector rejected");
    decoded=mf_get_track(file,0);
    if (!decoded || !pure_is_listv(decoded,&count,&events) || count!=1 ||
        !pure_is_tuplev(events[0],&count,&tuple) || count!=2 ||
        !pure_is_int(tuple[0],&tick) || tick!=0 ||
        !pure_is_int_matrix(tuple[1],(void**)&matrix) ||
        matrix->size1!=1 || matrix->size2!=4 ||
        memcmp(matrix->data,channels[i],sizeof(channels[i]))!=0)
      return fail("channel decode changed literal four-byte shape");
    free(tuple); free(events);
    pure_freenew(decoded); pure_freenew(list); mf_free(file); pure_freenew(file);
    ++cases_run;
  }
  return 1;
}

static int test_seven_bit_values(void)
{
  static const int invalid[][3]={{0x90,128,64},{0x90,60,255},{0xc0,128,0},{0xff,128,1},{0xff,255,1}};
  size_t i;
  for (i=0;i<5;++i) {
    pure_expr *file=mf_new(1,0,96), *list;
    MidiFile_t native=NULL;
    list=pure_listl(1,pure_tuplel(2,pure_int(0),make_matrix(1,i==2 ? 2 : 3,invalid[i])));
    pure_is_pointer(file,(void**)&native);
    if (mf_put_track(file,list) || MidiFile_getNumberOfTracks(native)!=0)
      return fail("seven-bit channel/meta value accepted or mutated file");
    pure_freenew(list); mf_free(file); pure_freenew(file); ++cases_run;
  }
  return 1;
}

/* Each fixture reaches the public native entry point. Exact allocations give
   ASan redzones on both sides; malformed metadata is restored before release. */
static int test_event_cases(void)
{
  static const struct { int bytes[6]; size_t rows, cols; int tick, accepted; } cases[] = {
    {{0xff},1,1,0,0}, {{0xff,0x2f,1},1,3,0,0},
    {{0xf0},1,1,0,1}, {{0xf7},1,1,0,1}, {{0},1,0,0,0},
    {{0x90,60},1,2,0,0}, {{0xc0,60,1},1,3,0,0},
    {{0x90,60,64,1},1,4,0,0}, {{0x90,60,64,0,0},1,5,0,0},
    {{-112,60,64},1,3,0,0}, {{0x190,60,64},1,3,0,0},
    {{0x90,-1,64},1,3,0,0}, {{0x90,256,64},1,3,0,0},
    {{0x90,60,64},1,3,-1,0}, {{0x90,60,64,0},2,2,0,0},
    {{0xf1,0},1,2,0,0}, {{0xff,1,-1},1,3,0,0},
    {{0x90,60,64},1,3,INT32_MAX,1}, {{0xc0,60},1,2,0,1},
    {{0xd0,60},2,1,0,1}, {{0x90,60,64,0},1,4,0,1},
    {{0xff,0x2f},1,2,0,1}, {{0xff,1},1,2,0,1},
    {{0xff,127,255},1,3,0,1}, {{0xf0,255,0xf7},1,3,0,1}
  };
  size_t i;
  for (i=0; i<sizeof(cases)/sizeof(cases[0]); ++i) {
    pure_expr *file=mf_new(1,0,96);
    pure_expr *matrix=make_matrix(cases[i].rows,cases[i].cols,cases[i].bytes);
    pure_expr *list=pure_listl(1,pure_tuplel(2,pure_int(cases[i].tick),matrix));
    MidiFile_t native=NULL;
    int accepted=mf_put_track(file,list);
    pure_is_pointer(file,(void**)&native);
    cases_run++;
    if (accepted!=cases[i].accepted || (!accepted && MidiFile_getNumberOfTracks(native)!=0)) {
      fprintf(stderr,"event case %zu: accepted=%d tracks=%d\n",i,accepted,MidiFile_getNumberOfTracks(native));
      return fail("event validation/rollback");
    }
    pure_freenew(list); mf_free(file); pure_freenew(file);
  }
  return 1;
}

static int test_transaction(void)
{
  static const int bytes[]={0x90,60,64};
  pure_expr *file=mf_new(1,0,96), *list;
  MidiFile_t native=NULL;
  MidiFileTrack_t original;
  MidiFileEvent_t event;
  list=pure_listl(1,pure_tuplel(2,pure_int(20),make_matrix(1,3,bytes)));
  if (!mf_put_track(file,list)) return fail("transaction setup");
  pure_freenew(list);
  pure_is_pointer(file,(void**)&native);
  original=MidiFile_getFirstTrack(native); event=MidiFile_getFirstEvent(native);
  list=pure_listl(2,
    pure_listl(1,pure_tuplel(2,pure_int(0),make_matrix(1,3,bytes))),
    pure_listl(2,pure_tuplel(2,pure_int(30),make_matrix(1,3,bytes)),pure_int(0)));
  cases_run++;
  if (mf_put_tracks(file,list) || MidiFile_getNumberOfTracks(native)!=1 ||
      MidiFile_getFirstTrack(native)!=original || MidiFile_getLastTrack(native)!=original ||
      MidiFile_getFirstEvent(native)!=event || MidiFile_getLastEvent(native)!=event ||
      MidiFileEvent_getNextEventInFile(event) || MidiFileEvent_getPreviousEventInFile(event))
    return fail("put_tracks did not restore original graph");
  pure_freenew(list); mf_free(file); pure_freenew(file);
  return 1;
}

static int test_metadata(void)
{
  const int guarded[]={0x12345678,0xf0,1,0xf7,0x12345678};
  size_t n;
  const struct { int64_t tick; size_t rows,cols,stride; const int *data; } bad[]={
    {-1,1,3,3,guarded+1}, {(int64_t)INT32_MAX+1,1,3,3,guarded+1},
    {0,1,3,4,guarded+1}, {0,3,1,2,guarded+1},
    {0,1,3,3,NULL}, {0,1,(size_t)INT_MAX+1,(size_t)INT_MAX+1,guarded+1},
    {0,SIZE_MAX,2,2,guarded+1}, {0,1,SIZE_MAX,SIZE_MAX,guarded+1},
    {0,2,2,2,guarded+1}
  };
  size_t i;
  if (pure_midi_matrix_elements(SIZE_MAX,2,&n) ||
      pure_midi_matrix_elements(1,SIZE_MAX,&n) ||
      pure_midi_matrix_elements(1,1,NULL)) return fail("matrix size overflow");
  cases_run+=3;
  for (i=0;i<sizeof(bad)/sizeof(bad[0]);++i) {
    if (pure_midi_validate_event(bad[i].tick,bad[i].rows,bad[i].cols,
                                  bad[i].stride,bad[i].data,&n))
      return fail("malformed native matrix/tick accepted");
    cases_run++;
  }
  if (guarded[0]!=0x12345678 || guarded[4]!=0x12345678) return fail("guard changed");
  return 1;
}

static int test_misaligned_matrix(void)
{
  BoundaryMatrix *matrix;
  BoundaryBlock *block;
  unsigned char *base;
  pure_expr *value;
  int count;
  matrix=malloc(sizeof(*matrix));
  block=malloc(sizeof(*block));
  if (!matrix || !block) {
    free(matrix); free(block);
    return fail("misaligned fixture allocation");
  }
  block->size=3;
  block->data=calloc(block->size,sizeof(*block->data));
  if (!block->data) { free(block); free(matrix); return fail("misaligned block allocation"); }
  matrix->size1=1; matrix->size2=2; matrix->tda=2;
  matrix->data=(int *)((unsigned char *)block->data+1);
  matrix->block=block; matrix->owner=1;
  value=pure_int_matrix(matrix);
  if (!value) {
    free(block->data); free(block); free(matrix);
    return fail("misaligned Pure matrix");
  }
  count=pure_midi_event_count(value);
  pure_freenew(value);
  cases_run++;
  if (count>=0) return fail("relatively misaligned matrix accepted");

  matrix=malloc(sizeof(*matrix));
  block=malloc(sizeof(*block));
  base=calloc(1,2*sizeof(int)+1);
  if (!matrix || !block || !base) {
    free(matrix); free(block); free(base);
    return fail("absolute misalignment fixture allocation");
  }
  block->size=2;
  block->data=calloc(block->size,sizeof(*block->data));
  if (!block->data) {
    free(base); free(block); free(matrix);
    return fail("absolute misalignment block allocation");
  }
  matrix->size1=1; matrix->size2=2; matrix->tda=2;
  matrix->data=block->data;
  matrix->block=block; matrix->owner=1;
  value=pure_int_matrix(matrix);
  if (!value) {
    free(base); free(block->data); free(block); free(matrix);
    return fail("absolute misalignment Pure matrix");
  }
  free(block->data);
  block->data=(int *)(base+1);
  matrix->data=block->data;
  count=pure_midi_event_count(value);
  matrix->data=NULL;
  matrix->block=NULL;
  pure_freenew(value);
  free(base); free(block);
  cases_run++;
  return count<0 ? 1 : fail("absolutely misaligned matrix accepted");
}

static size_t native_calls, native_fail=SIZE_MAX, native_live;
static void *boundary_allocate(size_t n)
{
  void *p;
  if (native_calls++==native_fail) return NULL;
  p=malloc(n); if (p) ++native_live; return p;
}
static void *boundary_calloc(size_t n,size_t size)
{
  void *p=boundary_allocate(n*size); if (p) memset(p,0,n*size); return p;
}
static void boundary_free(void *p) { if (p) { --native_live; free(p); } }

static int test_allocation_rollback(void)
{
  MidiFileAllocApi api={boundary_allocate,boundary_calloc,boundary_free};
  static const int voice[]={0x90,60,64}, sysex[]={0xf0,1,0xf7}, meta[]={0xff,1,65};
  size_t domain, failure;
  MidiFile_setTestAllocApi(&api);
  /* Fail every bridge and native allocation separately, including failures
     after a prior track/event has been linked. Terminal iteration must succeed. */
  for (domain=0;domain<2;++domain) for (failure=0;failure<1000;++failure) {
    pure_expr *file=mf_new(1,0,96), *tracks;
    MidiFile_t native=NULL;
    int ok;
    tracks=pure_listl(2,
      pure_listl(1,pure_tuplel(2,pure_int(0),make_matrix(1,3,voice))),
      pure_listl(2,pure_tuplel(2,pure_int(1),make_matrix(1,3,sysex)),
                  pure_tuplel(2,pure_int(2),make_matrix(1,3,meta))));
    pure_is_pointer(file,(void**)&native);
    native_calls=0; native_fail=domain ? failure : SIZE_MAX;
    pure_midi_test_fail_after(domain ? SIZE_MAX : failure);
    ok=mf_put_tracks(file,tracks);
    native_fail=SIZE_MAX; pure_midi_test_fail_after(SIZE_MAX);
    cases_run++;
    if (!ok && (MidiFile_getNumberOfTracks(native)!=0 ||
        MidiFile_getFirstEvent(native) || MidiFile_getLastEvent(native) || native_live!=1))
      return fail("allocation failure left a partial graph or allocation");
    pure_freenew(tracks); mf_free(file); pure_freenew(file);
    if (native_live) return fail("allocation rollback leaked native memory");
    if (ok) break;
  }
  MidiFile_resetTestApis();
  return 1;
}

static int test_decode_failures(void)
{
  static const int voice[]={0x90,60,64}, meta[]={0xff,1,65}, sysex[]={0xf0,1,0xf7};
  pure_expr *file=mf_new(1,0,96), *track, *result;
  size_t failure;
  track=pure_listl(3,pure_tuplel(2,pure_int(0),make_matrix(1,3,voice)),
                      pure_tuplel(2,pure_int(1),make_matrix(1,3,meta)),
                      pure_tuplel(2,pure_int(2),make_matrix(1,3,sysex)));
  if (!mf_put_track(file,track)) return fail("decode fixture");
  pure_freenew(track);
  for (failure=0;failure<1000;++failure) {
    pure_midi_test_fail_after(failure);
    result=mf_get_tracks(file);
    cases_run++;
    if (result) { pure_freenew(result); break; }
  }
  pure_midi_test_fail_after(SIZE_MAX);
  mf_free(file); pure_freenew(file);
  if (failure==1000) return fail("decode allocation sweep did not reach success");
  return 1;
}

static int test_construction_failures(void)
{
  MidiFileAllocApi api={boundary_allocate,boundary_calloc,boundary_free};
  pure_expr *file,*value;
  size_t i;
  MidiFile_setTestAllocApi(&api);
  for (i=0;i<2;++i) {
    pure_midi_test_fail_after(i);
    file=mf_new(1,0,96);
    if (file || native_live) return fail("file wrapping failure leaked native file");
    cases_run++;
  }
  pure_midi_test_fail_after(SIZE_MAX);
  file=mf_new(1,0,96);
  for (i=0;i<5;++i) {
    pure_midi_test_fail_after(i);
    value=mf_info(file);
    if (value) return fail("info construction failure accepted");
    cases_run++;
  }
  pure_midi_test_fail_after(0);
  if (mf_get_tracks(file)) return fail("empty list construction failure accepted");
  pure_midi_test_fail_after(SIZE_MAX);
  value=pure_listl(0);
  if (!mf_put_track(file,value) || !mf_put_tracks(file,value)) return fail("empty extraction");
  cases_run+=3;
  pure_freenew(value); mf_free(file); pure_freenew(file);
  MidiFile_resetTestApis();
  return native_live ? fail("file construction leaked") : 1;
}

int main(int argc, char **argv)
{
	pure_interp *interpreter = pure_create_interp(0, NULL);
	if (interpreter == NULL) return fail("could not create Pure interpreter") ? 0 : 2;
  if (argc==2) {
    int ok=strcmp(argv[1],"--legacy")==0 ? test_legacy_channels() :
      strcmp(argv[1],"--seven-bit")==0 ? test_seven_bit_values() : 0;
    pure_delete_interp(interpreter);
    return ok ? 0 : 1;
  }
  if (!test_legacy_channels() || !test_seven_bit_values()) return 1;
	if (!test_one_byte_meta()) return 1;
  if (!test_event_cases() || !test_transaction() || !test_metadata() ||
      !test_misaligned_matrix() ||
      !test_allocation_rollback() || !test_decode_failures() || !test_construction_failures()) return 1;
	pure_delete_interp(interpreter);
	printf("PASS: %d native MIDI boundary cases\n", cases_run);
	return 0;
}

#endif
