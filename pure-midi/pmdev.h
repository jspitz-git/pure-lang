
#ifndef PURE_MIDI_PMDEV_H
#define PURE_MIDI_PMDEV_H
#include <pure/runtime.h>
#include "midi_stream.h"
pure_expr *pm_device_info(int id);
pure_expr *pm_open_input(int id,int size,void *proc,void *info);
pure_expr *pm_open_output(int id,int size,void *proc,void *info,int latency);
int pm_stream_close(pure_expr *value);
void pm_stream_sentry(pure_expr *value);
#endif
