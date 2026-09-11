#include "midi_bounds.h"
#include <limits.h>
#include <stdint.h>

typedef struct { size_t size; int *data; } MidiBlock;
typedef struct {
  size_t rows, columns, stride;
  int *data;
  MidiBlock *block;
  int owner;
} MidiMatrix;

/* Check size_t metadata before Pure's dimension operations can narrow it.
   Submatrix views may start within the block, but their whole contiguous
   payload must still fit the owning block. */
static MidiMatrix *packed_matrix(pure_expr *value, size_t *count)
{
  MidiMatrix *m;
  size_t bytes, block_bytes;
  uintptr_t start, base, offset;
  if (!value || !pure_is_int_matrix(value,(void**)&m) || !m ||
      !m->rows || !m->columns || m->stride!=m->columns ||
      m->rows>INT_MAX || m->columns>INT_MAX ||
      m->rows>INT32_MAX || m->columns>INT32_MAX ||
      m->rows>SIZE_MAX/m->columns ||
      m->rows*m->columns>SIZE_MAX/sizeof(int) ||
      !m->data || !m->block || !m->block->data ||
      m->block->size>SIZE_MAX/sizeof(int)) return NULL;
  *count=m->rows*m->columns;
  bytes=*count*sizeof(int); block_bytes=m->block->size*sizeof(int);
  start=(uintptr_t)m->data; base=(uintptr_t)m->block->data;
  if (start<base) return NULL;
  offset=start-base;
  if (offset>block_bytes || offset%sizeof(int)!=0 ||
      bytes>block_bytes-offset) return NULL;
  return m;
}

int pure_midi_event_count(pure_expr *value)
{
  size_t count;
  MidiMatrix *m=packed_matrix(value,&count);
  if (!m || m->columns!=2) return -1;
  return (int)m->rows;
}

int pure_midi_byte_count(pure_expr *value)
{
  size_t count,i;
  MidiMatrix *m=packed_matrix(value,&count);
  if (!m || (m->rows!=1 && m->columns!=1) || count>INT_MAX || count>INT32_MAX) return -1;
  for (i=0;i<count;++i) if (m->data[i]<0 || m->data[i]>255) return -1;
  return (int)count;
}
