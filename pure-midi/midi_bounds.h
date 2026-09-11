#ifndef PURE_MIDI_BOUNDS_H
#define PURE_MIDI_BOUNDS_H
#include <pure/runtime.h>

/* Return an ABI-representable count, or -1 for an invalid layout/payload. */
int pure_midi_event_count(pure_expr *value);
int pure_midi_byte_count(pure_expr *value);
#endif
