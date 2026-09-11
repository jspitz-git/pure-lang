
#include <stdlib.h>
#include <string.h>
#include <limits.h>
#include "midifile.h"
#include "mf.h"
#include "../midi_bounds.h"

#ifdef PURE_MIDI_TEST_SEAM
static size_t fail_after = SIZE_MAX, allocation_count;
void pure_midi_test_fail_after(size_t count) { fail_after=count; allocation_count=0; }
size_t pure_midi_test_allocation_count(void) { return allocation_count; }
static bool can_allocate(void) { return allocation_count++ != fail_after; }
#else
static bool can_allocate(void) { return true; }
#endif
static void *bridge_malloc(size_t n) { return can_allocate() ? malloc(n) : NULL; }

bool pure_midi_matrix_elements(size_t rows, size_t columns, size_t *elements)
{
  size_t bytes;
  return midi_checked_mul_size(rows, columns, elements) &&
    midi_checked_mul_size(*elements, sizeof(int), &bytes);
}

bool pure_midi_validate_event(int64_t tick, size_t rows, size_t columns,
                              size_t stride, const int *data, size_t *length)
{
  size_t n, i, required;
  int status;
  if (!length || tick<0 || tick>INT32_MAX ||
      (rows!=1 && columns!=1) || stride!=columns ||
      !pure_midi_matrix_elements(rows, columns, &n) ||
      n==0 || n>INT_MAX || n>INT32_MAX || !data) return false;
  for (i=0; i<n; ++i) if (data[i]<0 || data[i]>255) return false;
  status=data[0];
  if (status>=0x80 && status<0xf0) {
    required=(status>=0xc0 && status<0xe0) ? 2 : 3;
    if (n!=required && n!=4) return false;
    for (i=1; i<required; ++i) if (data[i]>127) return false;
    for (i=required; i<n; ++i) if (data[i]!=0) return false;
  } else if (status==0xff) {
    if (n<2 || data[1]>127 || (data[1]==0x2f && n!=2)) return false;
  } else if (status!=0xf0 && status!=0xf7) return false;
  *length=n;
  return true;
}

/* GSL matrix data types and operations needed to represent MIDI data. */

typedef struct _gsl_block_int
{
  size_t size;
  int *data;
} gsl_block_int;

typedef struct _gsl_matrix_int
{
  size_t size1;
  size_t size2;
  size_t tda;
  int *data;
  gsl_block_int *block;
  int owner;
} gsl_matrix_int;

static gsl_matrix_int* 
gsl_matrix_int_alloc(const size_t n1, const size_t n2)
{
  gsl_block_int* block;
  gsl_matrix_int* m;
  size_t elements, bytes;
  if (n1 == 0 || n2 == 0 ||
      !pure_midi_matrix_elements(n1, n2, &elements) ||
      !midi_checked_mul_size(elements, sizeof(int), &bytes))
    return 0;
  m = (gsl_matrix_int*)bridge_malloc(sizeof(gsl_matrix_int));
  if (m == 0)
    return 0;
  block = (gsl_block_int*)bridge_malloc(sizeof(gsl_block_int));
  if (block == 0) {
    free(m);
    return 0;
  }
  block->size = elements;
  block->data = (int*)bridge_malloc(bytes);
  if (block->data == 0) {
    free(m);
    free(block);
    return 0;
  }
  m->data = block->data;
  m->size1 = n1;
  m->size2 = n2;
  m->tda = n2; 
  m->block = block;
  m->owner = 1;
  return m;
}

static gsl_matrix_int*
gsl_matrix_int_calloc(const size_t n1, const size_t n2)
{
  gsl_matrix_int* m = gsl_matrix_int_alloc(n1, n2);
  if (m == 0) return 0;
  memset(m->data, 0, m->block->size*sizeof(int));
  return m;
}

static inline gsl_matrix_int*
create_int_matrix(size_t nrows, size_t ncols)
{
  if (nrows == 0 || ncols == 0 ) {
    size_t nrows1 = (nrows>0)?nrows:1;
    size_t ncols1 = (ncols>0)?ncols:1;
    gsl_matrix_int *m = gsl_matrix_int_calloc(nrows1, ncols1);
    if (!m) return 0;
    m->size1 = nrows; m->size2 = ncols;
    return m;
  } else
    return gsl_matrix_int_alloc(nrows, ncols);
}

/* Create a Pure pointer with midifile::free sentry from a midi file object. */

static pure_expr *make_file(MidiFile_t mf)
{
  if (mf) {
    pure_expr *x = can_allocate() ? pure_symbol(pure_sym("midifile::free")) : NULL;
    pure_expr *p = x && can_allocate() ? pure_pointer(mf) : NULL;
    if (p && pure_sentry(x, p)) return p;
    if (p) pure_freenew(p);
    if (x) pure_freenew(x);
    MidiFile_free(mf);
    return NULL;
  } else
    return pure_pointer(0);
}

static bool is_file(pure_expr *x, MidiFile_t *mf)
{
  pure_expr *y;
  return x && pure_is_pointer(x, (void**)mf) && *mf && (y = pure_get_sentry(x)) &&
    y->tag > 0 && strcmp(pure_sym_pname(y->tag), "midifile::free") == 0;
}

/* Interface operations. */

pure_expr *mf_new(int file_format, int division, int resolution)
{
  if (file_format<0 || file_format>2 || resolution<1 ||
      resolution>(division==0 ? 0x7fff : 0xff)) return NULL;
  MidiFileDivisionType_t division_type = MIDI_FILE_DIVISION_TYPE_INVALID;
  switch (division) {
  case 0:
    division_type = MIDI_FILE_DIVISION_TYPE_PPQ;
    break;
  case 24:
    division_type = MIDI_FILE_DIVISION_TYPE_SMPTE24;
    break;
  case 25:
    division_type = MIDI_FILE_DIVISION_TYPE_SMPTE25;
    break;
  case 29:
    division_type = MIDI_FILE_DIVISION_TYPE_SMPTE30DROP;
    break;
  case 30:
    division_type = MIDI_FILE_DIVISION_TYPE_SMPTE30;
    break;
  default:
    break;
  }
  if (division_type==MIDI_FILE_DIVISION_TYPE_INVALID) return NULL;
  return make_file(MidiFile_new(file_format, division_type, resolution));
}

pure_expr *mf_load(char *filename)
{
  return make_file(MidiFile_load(filename));
}

bool mf_save(pure_expr *x, char *filename)
{
  MidiFile_t mf;
  if (!is_file(x, &mf)) return false;
  return MidiFile_save(mf, filename) == 0;
}

bool mf_free(pure_expr *x)
{
  MidiFile_t mf;
  if (!is_file(x, &mf)) return false;
  pure_sentry(0, x);
  /* Detach before destruction; aliases no longer identify a live file. */
  return MidiFile_free(mf) == 0;
}

static const int divisions[] = {0, 24, 25, 29, 30};
static pure_expr *make_sequence(bool tuple, size_t n, pure_expr **xs);

pure_expr *mf_info(pure_expr *x)
{
  MidiFile_t mf;
  if (!is_file(x, &mf)) return 0;
  MidiFileDivisionType_t type = MidiFile_getDivisionType(mf);
  int division = (type>=0 && type<5)?divisions[type]:-1;
  pure_expr *xs[4]={NULL,NULL,NULL,NULL};
  const int values[]={MidiFile_getFileFormat(mf),division,
    MidiFile_getResolution(mf),MidiFile_getNumberOfTracks(mf)};
  size_t i;
  for (i=0;i<4;++i) {
    xs[i]=can_allocate() ? pure_int(values[i]) : NULL;
    if (!xs[i]) break;
  }
  return make_sequence(true,4,xs);
}

static void free_matrix(gsl_matrix_int *mat)
{
  if (mat) { free(mat->block->data); free(mat->block); free(mat); }
}

/* Constructors consume their temporary children on success only. */
static pure_expr *make_sequence(bool tuple, size_t n, pure_expr **xs)
{
  size_t i;
  pure_expr *result=NULL;
  for (i=0; i<n; ++i) if (!xs[i]) break;
  if (i==n && can_allocate())
    result=tuple ? pure_tuplev(n,xs) : pure_listv(n,xs);
  if (!result) for (i=0; i<n; ++i) if (xs[i]) pure_freenew(xs[i]);
  return result;
}

static pure_expr *decode_event(MidiFileEvent_t ev)
{
  gsl_matrix_int *mat;
  pure_expr *xs[2]={NULL,NULL};
  const unsigned char *data=NULL;
  size_t n=0, i, offset=0;
  int number=0, native_length;
  uint32_t word=0;
  if (!ev || MidiFileEvent_getTick(ev)<0) return NULL;
  if (MidiFileEvent_isVoiceEvent(ev)) {
    word=MidiFileVoiceEvent_getData(ev);
    n=4;
  } else if (MidiFileEvent_getType(ev)==MIDI_FILE_EVENT_TYPE_SYSEX) {
    native_length=MidiFileSysexEvent_getDataLength(ev);
    data=MidiFileSysexEvent_getData(ev);
    if (native_length<1 || !data) return NULL;
    n=(size_t)native_length;
  } else if (MidiFileEvent_getType(ev)==MIDI_FILE_EVENT_TYPE_META) {
    native_length=MidiFileMetaEvent_getDataLength(ev);
    data=MidiFileMetaEvent_getData(ev);
    number=MidiFileMetaEvent_getNumber(ev);
    if (native_length<0 || (native_length && !data) ||
        number<0 || number>127 ||
        !midi_checked_add_size((size_t)native_length,2,&n) ||
        n>INT_MAX || n>INT32_MAX) return NULL;
    offset=2;
  } else return NULL;
  mat=create_int_matrix(1,n);
  if (!mat) return NULL;
  if (offset) { mat->data[0]=0xff; mat->data[1]=number; }
  if (data) for (i=offset; i<n; ++i) mat->data[i]=data[i-offset];
  else if (!offset) for (i=0; i<n; ++i) { mat->data[i]=word&255; word>>=8; }
  xs[0]=can_allocate() ? pure_int(MidiFileEvent_getTick(ev)) : NULL;
  xs[1]=xs[0] && can_allocate() ? pure_int_matrix(mat) : NULL;
  if (!xs[1]) free_matrix(mat);
  return make_sequence(true,2,xs);
}

static pure_expr *decode_track(MidiFileTrack_t track)
{
  MidiFileEvent_t ev;
  size_t n=0, bytes, i=0;
  pure_expr *x, **xs;
  if (!track) return NULL;
  for (ev=MidiFileTrack_getFirstEvent(track); ev; ev=MidiFileEvent_getNextEventInTrack(ev))
    if (!midi_checked_add_size(n,1,&n)) return NULL;
  if (!midi_checked_mul_size(n,sizeof(*xs),&bytes)) return NULL;
  if (!n) return make_sequence(false,0,NULL);
  xs=bridge_malloc(bytes);
  if (!xs) return NULL;
  memset(xs,0,bytes);
  for (ev=MidiFileTrack_getFirstEvent(track); ev; ev=MidiFileEvent_getNextEventInTrack(ev)) {
    xs[i]=decode_event(ev);
    if (!xs[i++]) break;
  }
  x=make_sequence(false,n,xs);
  free(xs);
  return x;
}

pure_expr *mf_get_track(pure_expr *x, int number)
{
  MidiFile_t mf;
  if (!is_file(x,&mf) || number<0 || number>=MidiFile_getNumberOfTracks(mf)) return NULL;
  return decode_track(MidiFile_getTrackByNumber(mf,number,0));
}

pure_expr *mf_get_tracks(pure_expr *x)
{
  MidiFile_t mf;
  MidiFileTrack_t track;
  size_t n, bytes, i=0;
  pure_expr **xs, *result;
  int count;
  if (!is_file(x,&mf)) return NULL;
  count=MidiFile_getNumberOfTracks(mf);
  if (count<0) return NULL;
  n=(size_t)count;
  if (!n) return make_sequence(false,0,NULL);
  if (!midi_checked_mul_size(n,sizeof(*xs),&bytes)) return NULL;
  xs=bridge_malloc(bytes);
  if (!xs) return NULL;
  memset(xs,0,bytes);
  for (track=MidiFile_getFirstTrack(mf); track && i<n; track=MidiFileTrack_getNextTrack(track)) {
    xs[i]=decode_track(track);
    if (!xs[i++]) break;
  }
  result=make_sequence(false,n,xs);
  free(xs);
  return result;
}

static bool encode_event(MidiFileTrack_t track, pure_expr *x)
{
  pure_expr *fun, *head, *tail, *symbol;
  size_t n, i;
  int32_t tick;
  gsl_matrix_int *mat;
  unsigned char *data;
  bool ok;
  int status;
  if (!x || !pure_is_tuplev(x,&n,NULL) || n!=2 ||
      !pure_is_app(x,&fun,&tail) || !pure_is_app(fun,&symbol,&head)) return false;
  ok=pure_is_int(head,&tick) && pure_midi_byte_count(tail)>0 &&
    pure_is_int_matrix(tail,(void**)&mat);
  if (!ok || !mat || !pure_midi_validate_event(tick,mat->size1,mat->size2,
                                               mat->tda,mat->data,&n)) return false;
  status=mat->data[0];
  if (status<0xf0) {
    uint32_t word=0;
    for (i=0; i<n; ++i) word|=(uint32_t)mat->data[i]<<(8*i);
    return MidiFileTrack_createVoiceEvent(track,tick,word)!=NULL;
  }
  if (status==0xff && mat->data[1]==0x2f) return true;
  data=bridge_malloc(n);
  if (!data) return false;
  for (i=0; i<n; ++i) data[i]=(unsigned char)mat->data[i];
  if (status==0xff)
    ok=MidiFileTrack_createMetaEvent(track,tick,mat->data[1],(int)(n-2),data+2)!=NULL;
  else
    ok=MidiFileTrack_createSysexEvent(track,tick,(int)n,data)!=NULL;
  free(data);
  return ok;
}

/* Runtime list extraction asserts on malloc failure. Extract into our checked
   allocation after its nonallocating shape/count check instead. */
static bool extract_list(pure_expr *xs, size_t *n, pure_expr ***out)
{
  size_t bytes,i;
  pure_expr *fun,*symbol,*tail,**items;
  *out=NULL;
  if (!xs || !pure_is_listv(xs,n,NULL) || *n>INT_MAX || *n>INT32_MAX ||
      !midi_checked_mul_size(*n,sizeof(*items),&bytes)) return false;
  if (!*n) return true;
  items=bridge_malloc(bytes);
  if (!items) return false;
  for (i=0;i<*n;++i) {
    if (!pure_is_app(xs,&fun,&tail) || !pure_is_app(fun,&symbol,&items[i])) {
      free(items); return false;
    }
    xs=tail;
  }
  *out=items;
  return true;
}

bool mf_put_track(pure_expr *x, pure_expr *xs)
{
  MidiFile_t mf;
  MidiFileTrack_t track=NULL;
  pure_expr **xv=NULL;
  size_t i,n;
  if (!is_file(x,&mf) || !extract_list(xs,&n,&xv)) return false;
  if (n && (!xv || n>INT_MAX || n>INT32_MAX)) goto err;
  if (!n) { free(xv); return true; }
  track=MidiFile_createTrack(mf);
  if (!track) goto err;
  for (i=0; i<n; ++i) if (!encode_event(track,xv[i])) goto err;
  free(xv);
  return true;
err:
  if (track) MidiFileTrack_delete(track);
  free(xv);
  return false;
}

bool mf_put_tracks(pure_expr *x, pure_expr *xs)
{
  MidiFile_t mf;
  pure_expr **xv=NULL;
  size_t i,n;
  int boundary;
  if (!is_file(x,&mf) || !extract_list(xs,&n,&xv)) return false;
  boundary=MidiFile_getNumberOfTracks(mf);
  if (n && (!xv || n>INT_MAX || n>INT32_MAX)) goto err;
  for (i=0; i<n; ++i) if (!mf_put_track(x,xv[i])) goto err;
  free(xv);
  return true;
err:
  while (MidiFile_getNumberOfTracks(mf)>boundary)
    MidiFileTrack_delete(MidiFile_getLastTrack(mf));
  free(xv);
  return false;
}
