
/* This gives access to the PmDeviceInfo structure, as returned by the
   Pm_GetDeviceInfo routine. */

#include <portmidi.h>
#include "pmdev.h"
#include <string.h>

pure_expr *pm_device_info(int id)
{
  const PmDeviceInfo *info = Pm_GetDeviceInfo(id);
  if (!info) return 0;
  /* The first field is useless and seems to be bogus anyway, skip it. */
  return pure_tuplel(5,
		     pure_cstring_dup(info->interf),
		     pure_cstring_dup(info->name),
		     pure_int(info->input),
		     pure_int(info->output),
		     pure_int(info->opened));
}

static PureMidiStream *owned_stream(pure_expr *value)
{
  pure_expr *sentry;
  PureMidiStream *s=NULL;
  if (!value || !pure_is_pointer(value,(void**)&s) || !s ||
      !(sentry=pure_get_sentry(value)) || sentry->tag<=0 ||
      strcmp(pure_sym_pname(sentry->tag),"midi::stream_sentry")) return NULL;
  return s;
}

/* One native reference belongs to the Pure pointer expression. Ordinary Pure
   aliases retain that expression, so explicit close must keep its sentry.
   The finalizer detaches the sentry before consuming the native reference. */
static pure_expr *wrap_stream(PureMidiStream *s,int result)
{
  pure_expr *value,*sentry;
  if (result) return pure_int(result);
  sentry=pure_symbol(pure_sym("midi::stream_sentry"));
  value=sentry ? pure_pointer(s) : NULL;
  if (value && pure_sentry(sentry,value)) return value;
  if (value) pure_freenew(value);
  if (sentry) pure_freenew(sentry);
  pure_midi_release(s);
  return pure_int(pmInsufficientMemory);
}
pure_expr *pm_open_input(int id,int size,void *proc,void *info)
{
  PureMidiStream *s=NULL;
  int r=pure_midi_open_input(&s,id,size,(PmTimeProcPtr)proc,info);
  return wrap_stream(s,r);
}
pure_expr *pm_open_output(int id,int size,void *proc,void *info,int latency)
{
  PureMidiStream *s=NULL;
  int r=pure_midi_open_output(&s,id,size,(PmTimeProcPtr)proc,info,latency);
  return wrap_stream(s,r);
}
int pm_stream_close(pure_expr *value) { return pure_midi_close(owned_stream(value)); }
void pm_stream_sentry(pure_expr *value)
{
  PureMidiStream *s=owned_stream(value);
  if (!s) return;
  pure_clear_sentry(value);
  value->data.p=NULL;
  pure_midi_release(s);
}
