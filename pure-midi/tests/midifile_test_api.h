#ifndef PURE_MIDI_MIDIFILE_TEST_API_INCLUDED
#define PURE_MIDI_MIDIFILE_TEST_API_INCLUDED

#ifndef PURE_MIDI_TEST_SEAM
#error "midifile_test_api.h is available only to fault-test targets"
#endif

#include <stddef.h>
#include <stdio.h>

typedef struct MidiFileIoApi
{
	FILE *(*open_file)(const char *filename, const char *mode);
	size_t (*read)(void *buffer, size_t size, size_t count, FILE *file);
	size_t (*write)(const void *buffer, size_t size, size_t count, FILE *file);
	int (*seek)(FILE *file, long offset, int origin);
	long (*tell)(FILE *file);
	int (*flush)(FILE *file);
	int (*close)(FILE *file);
} MidiFileIoApi;

typedef struct MidiFileAllocApi
{
	void *(*allocate)(size_t size);
	void *(*allocate_zeroed)(size_t count, size_t size);
	void (*deallocate)(void *pointer);
} MidiFileAllocApi;

typedef struct MidiFileParserCounters
{
	size_t bytes_read;
	size_t chunks_read;
	size_t tracks_read;
	size_t events_read;
	size_t vlq_bytes_read;
} MidiFileParserCounters;

void MidiFile_setTestIoApi(const MidiFileIoApi *api);
void MidiFile_setTestAllocApi(const MidiFileAllocApi *api);
void MidiFile_resetTestApis(void);
MidiFileParserCounters MidiFile_getTestParserCounters(void);

#endif
