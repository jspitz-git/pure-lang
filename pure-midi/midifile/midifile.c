
/* NOTE: The original source had the byte order of pitch wheel messages (0xe0
   status) wrong, this has hopefully been fixed -- watch out for '- ag' in the
   code.  */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <limits.h>
#include <stdbool.h>
#include <stdint.h>
#include "midifile.h"

#ifdef PURE_MIDI_TEST_SEAM
#include "midifile_test_api.h"
#endif

/* Silence clang warnings about undefined switch cases. We should maybe look
   into these some time. */
#pragma clang diagnostic ignored "-Wswitch-enum"

/*
 * Data Types
 */

struct MidiFile
{
	int file_format;
	MidiFileDivisionType_t division_type;
	int resolution;
	int number_of_tracks;
	struct MidiFileTrack *first_track;
	struct MidiFileTrack *last_track;
	struct MidiFileEvent *first_event;
	struct MidiFileEvent *last_event;
};

struct MidiFileTrack
{
	struct MidiFile *midi_file;
	int number;
	int32_t end_tick;
	struct MidiFileTrack *previous_track;
	struct MidiFileTrack *next_track;
	struct MidiFileEvent *first_event;
	struct MidiFileEvent *last_event;
};

struct MidiFileEvent
{
	struct MidiFileTrack *track;
	struct MidiFileEvent *previous_event_in_track;
	struct MidiFileEvent *next_event_in_track;
	struct MidiFileEvent *previous_event_in_file;
	struct MidiFileEvent *next_event_in_file;
	int32_t tick;
	MidiFileEventType_t type;

	union
	{
		struct
		{
			int channel;
			int note;
			int velocity;
		}
		note_off;

		struct
		{
			int channel;
			int note;
			int velocity;
		}
		note_on;

		struct
		{
			int channel;
			int note;
			int amount;
		}
		key_pressure;

		struct
		{
			int channel;
			int number;
			int value;
		}
		control_change;

		struct
		{
			int channel;
			int number;
		}
		program_change;

		struct
		{
			int channel;
			int amount;
		}
		channel_pressure;

		struct
		{
			int channel;
			int value;
		}
		pitch_wheel;

		struct
		{
			int data_length;
			unsigned char *data_buffer;
		}
		sysex;

		struct
		{
			int number;
			int data_length;
			unsigned char *data_buffer;
		}
		meta;
	}
	u;

	int should_be_visited;
};

/*
 * Helpers
 */

static FILE *runtime_open_file(const char *filename, const char *mode) { return fopen(filename, mode); }
static size_t runtime_read(void *buffer, size_t size, size_t count, FILE *file) { return fread(buffer, size, count, file); }
static size_t runtime_write(const void *buffer, size_t size, size_t count, FILE *file) { return fwrite(buffer, size, count, file); }
static int runtime_seek(FILE *file, long offset, int origin) { return fseek(file, offset, origin); }
static long runtime_tell(FILE *file) { return ftell(file); }
static int runtime_flush(FILE *file) { return fflush(file); }
static int runtime_close(FILE *file) { return fclose(file); }
static void *runtime_allocate(size_t size) { return malloc(size); }
static void *runtime_allocate_zeroed(size_t count, size_t size) { return calloc(count, size); }
static void runtime_deallocate(void *pointer) { free(pointer); }

#ifdef PURE_MIDI_TEST_SEAM
static const MidiFileIoApi runtime_io_api = {
	runtime_open_file, runtime_read, runtime_write, runtime_seek, runtime_tell,
	runtime_flush, runtime_close
};
static const MidiFileAllocApi runtime_alloc_api = {
	runtime_allocate, runtime_allocate_zeroed, runtime_deallocate
};
static MidiFileIoApi active_io_api = {
	runtime_open_file, runtime_read, runtime_write, runtime_seek, runtime_tell,
	runtime_flush, runtime_close
};
static MidiFileAllocApi active_alloc_api = {
	runtime_allocate, runtime_allocate_zeroed, runtime_deallocate
};
static MidiFileParserCounters parser_counters;

void MidiFile_setTestIoApi(const MidiFileIoApi *api)
{
	active_io_api = (api == NULL) ? runtime_io_api : *api;
}

void MidiFile_setTestAllocApi(const MidiFileAllocApi *api)
{
	active_alloc_api = (api == NULL) ? runtime_alloc_api : *api;
}

void MidiFile_resetTestApis(void)
{
	active_io_api = runtime_io_api;
	active_alloc_api = runtime_alloc_api;
	memset(&parser_counters, 0, sizeof(parser_counters));
}

MidiFileParserCounters MidiFile_getTestParserCounters(void)
{
	return parser_counters;
}

#define MIDI_IO(name) active_io_api.name
#define MIDI_ALLOC(name) active_alloc_api.name
#define COUNT_READ(n) (parser_counters.bytes_read += (n))
#define COUNT_CHUNK() (parser_counters.chunks_read++)
#define COUNT_TRACK() (parser_counters.tracks_read++)
#define COUNT_EVENT() (parser_counters.events_read++)
#define COUNT_VLQ() (parser_counters.vlq_bytes_read++)
#define RESET_COUNTERS() memset(&parser_counters, 0, sizeof(parser_counters))
#else
#define MIDI_IO(name) runtime_##name
#define MIDI_ALLOC(name) runtime_##name
#define COUNT_READ(n) ((void)(n))
#define COUNT_CHUNK() ((void)0)
#define COUNT_TRACK() ((void)0)
#define COUNT_EVENT() ((void)0)
#define COUNT_VLQ() ((void)0)
#define RESET_COUNTERS() ((void)0)
#endif

static void *midi_malloc(size_t size) { return MIDI_ALLOC(allocate)(size); }
static void *midi_calloc(size_t count, size_t size) { return MIDI_ALLOC(allocate_zeroed)(count, size); }
static void midi_free(void *pointer) { MIDI_ALLOC(deallocate)(pointer); }

bool midi_checked_add_size(size_t a, size_t b, size_t *out)
{
	if ((out == NULL) || (b > SIZE_MAX - a)) return false;
	*out = a + b;
	return true;
}

bool midi_checked_mul_size(size_t a, size_t b, size_t *out)
{
	if ((out == NULL) || ((a != 0) && (b > SIZE_MAX / a))) return false;
	*out = a * b;
	return true;
}

static unsigned short interpret_uint16(unsigned char *buffer)
{
	return ((unsigned short)(buffer[0]) << 8) | (unsigned short)(buffer[1]);
}

static void encode_uint16(unsigned char buffer[2], unsigned short value)
{
	buffer[0] = (unsigned char)((value >> 8) & 0xFF);
	buffer[1] = (unsigned char)(value & 0xFF);
}

static uint32_t interpret_uint32(unsigned char *buffer)
{
	return ((uint32_t)(buffer[0]) << 24) | ((uint32_t)(buffer[1]) << 16) | ((uint32_t)(buffer[2]) << 8) | (uint32_t)(buffer[3]);
}

static uint32_t interpret_little_uint32(const unsigned char *buffer)
{
	return ((uint32_t)(buffer[3]) << 24) | ((uint32_t)(buffer[2]) << 16) |
		((uint32_t)(buffer[1]) << 8) | (uint32_t)(buffer[0]);
}

static void encode_uint32(unsigned char buffer[4], uint32_t value)
{
	buffer[0] = (unsigned char)(value >> 24);
	buffer[1] = (unsigned char)((value >> 16) & 0xFF);
	buffer[2] = (unsigned char)((value >> 8) & 0xFF);
	buffer[3] = (unsigned char)(value & 0xFF);
}

static void add_event(MidiFileEvent_t new_event)
{
	/* Add in proper sorted order.  Search backwards to optimize for appending. */

	MidiFileEvent_t event;

	for (event = new_event->track->last_event; (event != NULL) && (new_event->tick < event->tick); event = event->previous_event_in_track) {}

	new_event->previous_event_in_track = event;

	if (event == NULL)
	{
		new_event->next_event_in_track = new_event->track->first_event;
		new_event->track->first_event = new_event;
	}
	else
	{
		new_event->next_event_in_track = event->next_event_in_track;
		event->next_event_in_track = new_event;
	}

	if (new_event->next_event_in_track == NULL)
	{
		new_event->track->last_event = new_event;
	}
	else
	{
		new_event->next_event_in_track->previous_event_in_track = new_event;
	}

	for (event = new_event->track->midi_file->last_event; (event != NULL) && (new_event->tick < event->tick); event = event->previous_event_in_file) {}

	new_event->previous_event_in_file = event;

	if (event == NULL)
	{
		new_event->next_event_in_file = new_event->track->midi_file->first_event;
		new_event->track->midi_file->first_event = new_event;
	}
	else
	{
		new_event->next_event_in_file = event->next_event_in_file;
		event->next_event_in_file = new_event;
	}

	if (new_event->next_event_in_file == NULL)
	{
		new_event->track->midi_file->last_event = new_event;
	}
	else
	{
		new_event->next_event_in_file->previous_event_in_file = new_event;
	}

	if (new_event->tick > new_event->track->end_tick) new_event->track->end_tick = new_event->tick;
}

static void remove_event(MidiFileEvent_t event)
{
	if (event->previous_event_in_track == NULL)
	{
		event->track->first_event = event->next_event_in_track;
	}
	else
	{
		event->previous_event_in_track->next_event_in_track = event->next_event_in_track;
	}

	if (event->next_event_in_track == NULL)
	{
		event->track->last_event = event->previous_event_in_track;
	}
	else
	{
		event->next_event_in_track->previous_event_in_track = event->previous_event_in_track;
	}

	if (event->previous_event_in_file == NULL)
	{
		event->track->midi_file->first_event = event->next_event_in_file;
	}
	else
	{
		event->previous_event_in_file->next_event_in_file = event->next_event_in_file;
	}

	if (event->next_event_in_file == NULL)
	{
		event->track->midi_file->last_event = event->previous_event_in_file;
	}
	else
	{
		event->next_event_in_file->previous_event_in_file = event->previous_event_in_file;
	}
}

static void free_events_in_track(MidiFileTrack_t track)
{
	MidiFileEvent_t event, next_event_in_track;

	for (event = track->first_event; event != NULL; event = next_event_in_track)
	{
		next_event_in_track = event->next_event_in_track;

		switch (event->type)
		{
			case MIDI_FILE_EVENT_TYPE_SYSEX:
			{
				midi_free(event->u.sysex.data_buffer);
				break;
			}
			case MIDI_FILE_EVENT_TYPE_META:
			{
				midi_free(event->u.meta.data_buffer);
				break;
			}
			default: ;
		}

		midi_free(event);
	}
}

typedef struct MidiFileReader
{
	FILE *file;
	size_t offset;
	size_t limit;
} MidiFileReader;

static bool reader_read(MidiFileReader *reader, void *buffer, size_t size)
{
	if ((reader == NULL) || (buffer == NULL) || (reader->offset > reader->limit) ||
		(size > reader->limit - reader->offset)) return false;
	if ((size != 0) && (MIDI_IO(read)(buffer, 1, size, reader->file) != size)) return false;
	reader->offset += size;
	COUNT_READ(size);
	return true;
}

static bool reader_seek(MidiFileReader *reader, size_t offset)
{
	if ((reader == NULL) || (offset > reader->limit) || (offset > (size_t)LONG_MAX)) return false;
	if (MIDI_IO(seek)(reader->file, (long)offset, SEEK_SET) != 0) return false;
	reader->offset = offset;
	return true;
}

static bool reader_uint16(MidiFileReader *reader, unsigned short *value)
{
	unsigned char buffer[2];
	if ((value == NULL) || !reader_read(reader, buffer, sizeof(buffer))) return false;
	*value = interpret_uint16(buffer);
	return true;
}

static bool reader_uint32(MidiFileReader *reader, uint32_t *value)
{
	unsigned char buffer[4];
	if ((value == NULL) || !reader_read(reader, buffer, sizeof(buffer))) return false;
	*value = interpret_uint32(buffer);
	return true;
}

static bool reader_little_uint32(MidiFileReader *reader, uint32_t *value)
{
	unsigned char buffer[4];
	if ((value == NULL) || !reader_read(reader, buffer, sizeof(buffer))) return false;
	*value = interpret_little_uint32(buffer);
	return true;
}

static bool reader_vlq(MidiFileReader *reader, uint32_t *value)
{
	uint32_t result = 0;
	unsigned int index;

	if (value == NULL) return false;
	for (index = 0; index < 4; index++)
	{
		unsigned char byte;
		if (!reader_read(reader, &byte, 1)) return false;
		COUNT_VLQ();
		result = (result << 7) | (uint32_t)(byte & 0x7f);
		if ((byte & 0x80) == 0)
		{
			*value = result;
			return true;
		}
	}
	return false;
}

static bool read_data_byte(MidiFileReader *reader, int *value)
{
	unsigned char byte;
	if ((value == NULL) || !reader_read(reader, &byte, 1) || (byte >= 0x80)) return false;
	*value = byte;
	return true;
}

static bool checked_tick(int32_t previous_tick, uint32_t delta, int32_t *tick)
{
	if ((tick == NULL) || (previous_tick < 0) || (delta > (uint32_t)(INT32_MAX - previous_tick))) return false;
	*tick = previous_tick + (int32_t)delta;
	return true;
}

static bool parse_track(MidiFileReader *reader, MidiFile_t midi_file)
{
	MidiFileTrack_t track;
	int32_t previous_tick = 0;
	unsigned char running_status = 0;
	bool found_end_of_track = false;

	track = MidiFile_createTrack(midi_file);
	if (track == NULL) return false;
	COUNT_TRACK();

	while ((reader->offset < reader->limit) && !found_end_of_track)
	{
		uint32_t delta;
		int32_t tick;
		unsigned char first_byte;
		unsigned char status;
		bool have_first_data = false;
		MidiFileEvent_t event = NULL;

		if (!reader_vlq(reader, &delta) || !checked_tick(previous_tick, delta, &tick) ||
			!reader_read(reader, &first_byte, 1)) return false;
		previous_tick = tick;

		if ((first_byte & 0x80) == 0)
		{
			if ((running_status < 0x80) || (running_status >= 0xf0)) return false;
			status = running_status;
			have_first_data = true;
		}
		else
		{
			status = first_byte;
			if (status < 0xf0) running_status = status;
		}

		switch (status & 0xf0)
		{
			case 0x80:
			case 0x90:
			case 0xa0:
			case 0xb0:
			case 0xe0:
			{
				int first;
				int second;
				if (have_first_data)
					first = first_byte;
				else if (!read_data_byte(reader, &first))
					return false;
				if (!read_data_byte(reader, &second)) return false;
				switch (status & 0xf0)
				{
					case 0x80: event = MidiFileTrack_createNoteOffEvent(track, tick, status & 0x0f, first, second); break;
					case 0x90: event = MidiFileTrack_createNoteOnEvent(track, tick, status & 0x0f, first, second); break;
					case 0xa0: event = MidiFileTrack_createKeyPressureEvent(track, tick, status & 0x0f, first, second); break;
					case 0xb0: event = MidiFileTrack_createControlChangeEvent(track, tick, status & 0x0f, first, second); break;
					case 0xe0: event = MidiFileTrack_createPitchWheelEvent(track, tick, status & 0x0f, first | (second << 7)); break;
					default: return false;
				}
				if (event == NULL) return false;
				break;
			}
			case 0xc0:
			case 0xd0:
			{
				int data;
				if (have_first_data)
					data = first_byte;
				else if (!read_data_byte(reader, &data))
					return false;
				if ((status & 0xf0) == 0xc0)
					event = MidiFileTrack_createProgramChangeEvent(track, tick, status & 0x0f, data);
				else
					event = MidiFileTrack_createChannelPressureEvent(track, tick, status & 0x0f, data);
				if (event == NULL) return false;
				break;
			}
			case 0xf0:
			{
				uint32_t encoded_length;
				size_t allocation_size;
				int data_length;
				unsigned char *data = NULL;

				if (have_first_data) return false;
				if ((status == 0xf0) || (status == 0xf7))
				{
					if (!reader_vlq(reader, &encoded_length) ||
						!midi_checked_add_size((size_t)encoded_length, 1, &allocation_size) ||
						(allocation_size > (size_t)INT_MAX) ||
						(encoded_length > reader->limit - reader->offset)) return false;
					data = (unsigned char *)midi_malloc(allocation_size);
					if (data == NULL) return false;
					data[0] = status;
					if (!reader_read(reader, data + 1, encoded_length))
					{
						midi_free(data);
						return false;
					}
					data_length = (int)allocation_size;
					event = MidiFileTrack_createSysexEvent(track, tick, data_length, data);
					midi_free(data);
					if (event == NULL) return false;
				}
				else if (status == 0xff)
				{
					unsigned char number;
					if (!reader_read(reader, &number, 1) || !reader_vlq(reader, &encoded_length) ||
						(encoded_length > (uint32_t)INT_MAX) ||
						(encoded_length > reader->limit - reader->offset)) return false;
					if (number == 0x2f)
					{
						if (encoded_length != 0) return false;
						if (MidiFileTrack_setEndTick(track, tick) != 0) return false;
						found_end_of_track = true;
					}
					else
					{
						if (encoded_length != 0)
						{
							data = (unsigned char *)midi_malloc((size_t)encoded_length);
							if (data == NULL) return false;
							if (!reader_read(reader, data, (size_t)encoded_length))
							{
								midi_free(data);
								return false;
							}
						}
						event = MidiFileTrack_createMetaEvent(track, tick, number, (int)encoded_length, data);
						midi_free(data);
						if (event == NULL) return false;
					}
				}
				else
				{
					return false;
				}
				break;
			}
			default:
				return false;
		}

		if (event != NULL) COUNT_EVENT();
	}

	return found_end_of_track;
}

typedef struct MidiFileWriter
{
	FILE *file;
	bool failed;
} MidiFileWriter;

static bool writer_write(MidiFileWriter *writer, const void *buffer, size_t size)
{
	if ((writer == NULL) || writer->failed || ((size != 0) &&
		(MIDI_IO(write)(buffer, 1, size, writer->file) != size)))
	{
		if (writer != NULL) writer->failed = true;
		return false;
	}
	return true;
}

static bool writer_byte(MidiFileWriter *writer, unsigned char value)
{
	return writer_write(writer, &value, 1);
}

static bool writer_uint16(MidiFileWriter *writer, unsigned short value)
{
	unsigned char buffer[2];
	encode_uint16(buffer, value);
	return writer_write(writer, buffer, sizeof(buffer));
}

static bool writer_uint32(MidiFileWriter *writer, uint32_t value)
{
	unsigned char buffer[4];
	encode_uint32(buffer, value);
	return writer_write(writer, buffer, sizeof(buffer));
}

static bool writer_vlq(MidiFileWriter *writer, uint32_t value)
{
	unsigned char buffer[4];
	int offset = 3;

	if (value > 0x0fffffffU) return false;
	do
	{
		buffer[offset] = (unsigned char)(value & 0x7f);
		if (offset < 3) buffer[offset] |= 0x80;
		value >>= 7;
		offset--;
	}
	while (value != 0);
	return writer_write(writer, buffer + offset + 1, (size_t)(3 - offset));
}

static bool writer_tell(MidiFileWriter *writer, long *offset)
{
	long result;
	if ((writer == NULL) || (offset == NULL) || writer->failed ||
		((result = MIDI_IO(tell)(writer->file)) < 0))
	{
		if (writer != NULL) writer->failed = true;
		return false;
	}
	*offset = result;
	return true;
}

static bool writer_seek(MidiFileWriter *writer, long offset)
{
	if ((writer == NULL) || writer->failed || (MIDI_IO(seek)(writer->file, offset, SEEK_SET) != 0))
	{
		if (writer != NULL) writer->failed = true;
		return false;
	}
	return true;
}

/*
 * Public API
 */

MidiFile_t MidiFile_load(char *filename)
{
	MidiFile_t midi_file = NULL;
	FILE *in = NULL;
	MidiFileReader reader;
	unsigned char chunk_id[4];
	unsigned char division_bytes[2];
	uint32_t chunk_size;
	size_t chunk_end;
	size_t container_end;
	unsigned short file_format;
	unsigned short number_of_tracks;
	unsigned short division;
	unsigned int tracks_read = 0;
	MidiFileDivisionType_t division_type;
	int resolution;
	long file_end;
	bool ok = false;

	RESET_COUNTERS();
	if ((filename == NULL) || ((in = MIDI_IO(open_file)(filename, "rb")) == NULL)) return NULL;
	if ((MIDI_IO(seek)(in, 0, SEEK_END) != 0) || ((file_end = MIDI_IO(tell)(in)) < 0) ||
		(MIDI_IO(seek)(in, 0, SEEK_SET) != 0)) goto cleanup;
	reader.file = in;
	reader.offset = 0;
	reader.limit = (size_t)file_end;
	container_end = reader.limit;

	if (!reader_read(&reader, chunk_id, sizeof(chunk_id))) goto cleanup;
	if (memcmp(chunk_id, "RIFF", 4) == 0)
	{
		uint32_t riff_size;
		if (!reader_little_uint32(&reader, &riff_size) ||
			!midi_checked_add_size(8, (size_t)riff_size, &container_end) ||
			(container_end < 12) || (container_end > reader.limit)) goto cleanup;
		reader.limit = container_end;
		if (!reader_read(&reader, chunk_id, sizeof(chunk_id)) || (memcmp(chunk_id, "RMID", 4) != 0)) goto cleanup;
		while (reader.offset < container_end)
		{
			size_t data_end;
			reader.limit = container_end;
			if (!reader_read(&reader, chunk_id, sizeof(chunk_id)) ||
				!reader_little_uint32(&reader, &chunk_size) ||
				!midi_checked_add_size(reader.offset, (size_t)chunk_size, &data_end) ||
				(data_end > container_end)) goto cleanup;
			COUNT_CHUNK();
			if (memcmp(chunk_id, "data", 4) == 0)
			{
				container_end = data_end;
				reader.limit = container_end;
				if (!reader_read(&reader, chunk_id, sizeof(chunk_id))) goto cleanup;
				break;
			}
			{
				size_t next_chunk;
				if (!midi_checked_add_size(data_end, (chunk_size & 1U) != 0U, &next_chunk) ||
					!reader_seek(&reader, next_chunk)) goto cleanup;
			}
		}
	}

	if (memcmp(chunk_id, "MThd", 4) != 0 || !reader_uint32(&reader, &chunk_size) ||
		(chunk_size < 6) || !midi_checked_add_size(reader.offset, (size_t)chunk_size, &chunk_end) ||
		(chunk_end > container_end)) goto cleanup;
	COUNT_CHUNK();
	if (!reader_uint16(&reader, &file_format) || !reader_uint16(&reader, &number_of_tracks) ||
		!reader_read(&reader, division_bytes, sizeof(division_bytes))) goto cleanup;
	division = interpret_uint16(division_bytes);
	if ((file_format > 2) || (number_of_tracks == 0) || ((file_format == 0) && (number_of_tracks != 1))) goto cleanup;
	if ((division & 0x8000U) == 0)
	{
		division_type = MIDI_FILE_DIVISION_TYPE_PPQ;
		resolution = division;
		if (resolution == 0) goto cleanup;
	}
	else
	{
		resolution = division_bytes[1];
		if (resolution == 0) goto cleanup;
		switch ((signed char)division_bytes[0])
		{
			case -24: division_type = MIDI_FILE_DIVISION_TYPE_SMPTE24; break;
			case -25: division_type = MIDI_FILE_DIVISION_TYPE_SMPTE25; break;
			case -29: division_type = MIDI_FILE_DIVISION_TYPE_SMPTE30DROP; break;
			case -30: division_type = MIDI_FILE_DIVISION_TYPE_SMPTE30; break;
			default: goto cleanup;
		}
	}

	midi_file = MidiFile_new(file_format, division_type, resolution);
	if ((midi_file == NULL) || !reader_seek(&reader, chunk_end)) goto cleanup;
	while (tracks_read < number_of_tracks)
	{
		size_t payload_start;
		reader.limit = container_end;
		if (!reader_read(&reader, chunk_id, sizeof(chunk_id)) || !reader_uint32(&reader, &chunk_size)) goto cleanup;
		payload_start = reader.offset;
		if (!midi_checked_add_size(payload_start, (size_t)chunk_size, &chunk_end) ||
			(chunk_end > container_end)) goto cleanup;
		COUNT_CHUNK();
		if (memcmp(chunk_id, "MTrk", 4) == 0)
		{
			reader.limit = chunk_end;
			if (!parse_track(&reader, midi_file)) goto cleanup;
			tracks_read++;
		}
		reader.limit = container_end;
		if (!reader_seek(&reader, chunk_end)) goto cleanup;
	}
	ok = true;

cleanup:
	if (in != NULL)
	{
		if (MIDI_IO(close)(in) != 0) ok = false;
		in = NULL;
	}
	if (!ok)
	{
		MidiFile_free(midi_file);
		midi_file = NULL;
	}
	return midi_file;
}

int MidiFile_save(MidiFile_t midi_file, const char* filename)
{
	FILE *out = NULL;
	MidiFileWriter writer;
	MidiFileTrack_t track;
	bool ok = true;

	if ((midi_file == NULL) || (filename == NULL) || ((out = MIDI_IO(open_file)(filename, "wb")) == NULL)) return -1;
	writer.file = out;
	writer.failed = false;
	ok = writer_write(&writer, "MThd", 4) && writer_uint32(&writer, 6) &&
		writer_uint16(&writer, (unsigned short)MidiFile_getFileFormat(midi_file)) &&
		writer_uint16(&writer, (unsigned short)MidiFile_getNumberOfTracks(midi_file));

	switch (MidiFile_getDivisionType(midi_file))
	{
		case MIDI_FILE_DIVISION_TYPE_PPQ:
		{
			ok = ok && writer_uint16(&writer, (unsigned short)MidiFile_getResolution(midi_file));
			break;
		}
		case MIDI_FILE_DIVISION_TYPE_SMPTE24:
		{
			ok = ok && writer_byte(&writer, (unsigned char)-24) && writer_byte(&writer, (unsigned char)MidiFile_getResolution(midi_file));
			break;
		}
		case MIDI_FILE_DIVISION_TYPE_SMPTE25:
		{
			ok = ok && writer_byte(&writer, (unsigned char)-25) && writer_byte(&writer, (unsigned char)MidiFile_getResolution(midi_file));
			break;
		}
		case MIDI_FILE_DIVISION_TYPE_SMPTE30DROP:
		{
			ok = ok && writer_byte(&writer, (unsigned char)-29) && writer_byte(&writer, (unsigned char)MidiFile_getResolution(midi_file));
			break;
		}
		case MIDI_FILE_DIVISION_TYPE_SMPTE30:
		{
			ok = ok && writer_byte(&writer, (unsigned char)-30) && writer_byte(&writer, (unsigned char)MidiFile_getResolution(midi_file));
			break;
		}
		default: ok = false;
	}

	for (track = MidiFile_getFirstTrack(midi_file); ok && (track != NULL); track = MidiFileTrack_getNextTrack(track))
	{
		MidiFileEvent_t event;
		long track_size_offset, track_start_offset, track_end_offset;
		int32_t tick, previous_tick;

		ok = writer_write(&writer, "MTrk", 4) && writer_tell(&writer, &track_size_offset) &&
			writer_uint32(&writer, 0) && writer_tell(&writer, &track_start_offset);

		previous_tick = 0;

		for (event = MidiFileTrack_getFirstEvent(track); ok && (event != NULL); event = MidiFileEvent_getNextEventInTrack(event))
		{
			tick = MidiFileEvent_getTick(event);
			if ((tick < previous_tick) || !writer_vlq(&writer, (uint32_t)(tick - previous_tick))) { ok = false; break; }

			switch (MidiFileEvent_getType(event))
			{
				case MIDI_FILE_EVENT_TYPE_NOTE_OFF:
				{
					ok = writer_byte(&writer, (unsigned char)(0x80 | (MidiFileNoteOffEvent_getChannel(event) & 0x0f))) &&
						writer_byte(&writer, (unsigned char)(MidiFileNoteOffEvent_getNote(event) & 0x7f)) &&
						writer_byte(&writer, (unsigned char)(MidiFileNoteOffEvent_getVelocity(event) & 0x7f));
					break;
				}
				case MIDI_FILE_EVENT_TYPE_NOTE_ON:
				{
					ok = writer_byte(&writer, (unsigned char)(0x90 | (MidiFileNoteOnEvent_getChannel(event) & 0x0f))) &&
						writer_byte(&writer, (unsigned char)(MidiFileNoteOnEvent_getNote(event) & 0x7f)) &&
						writer_byte(&writer, (unsigned char)(MidiFileNoteOnEvent_getVelocity(event) & 0x7f));
					break;
				}
				case MIDI_FILE_EVENT_TYPE_KEY_PRESSURE:
				{
					ok = writer_byte(&writer, (unsigned char)(0xa0 | (MidiFileKeyPressureEvent_getChannel(event) & 0x0f))) &&
						writer_byte(&writer, (unsigned char)(MidiFileKeyPressureEvent_getNote(event) & 0x7f)) &&
						writer_byte(&writer, (unsigned char)(MidiFileKeyPressureEvent_getAmount(event) & 0x7f));
					break;
				}
				case MIDI_FILE_EVENT_TYPE_CONTROL_CHANGE:
				{
					ok = writer_byte(&writer, (unsigned char)(0xb0 | (MidiFileControlChangeEvent_getChannel(event) & 0x0f))) &&
						writer_byte(&writer, (unsigned char)(MidiFileControlChangeEvent_getNumber(event) & 0x7f)) &&
						writer_byte(&writer, (unsigned char)(MidiFileControlChangeEvent_getValue(event) & 0x7f));
					break;
				}
				case MIDI_FILE_EVENT_TYPE_PROGRAM_CHANGE:
				{
					ok = writer_byte(&writer, (unsigned char)(0xc0 | (MidiFileProgramChangeEvent_getChannel(event) & 0x0f))) &&
						writer_byte(&writer, (unsigned char)(MidiFileProgramChangeEvent_getNumber(event) & 0x7f));
					break;
				}
				case MIDI_FILE_EVENT_TYPE_CHANNEL_PRESSURE:
				{
					ok = writer_byte(&writer, (unsigned char)(0xd0 | (MidiFileChannelPressureEvent_getChannel(event) & 0x0f))) &&
						writer_byte(&writer, (unsigned char)(MidiFileChannelPressureEvent_getAmount(event) & 0x7f));
					break;
				}
				case MIDI_FILE_EVENT_TYPE_PITCH_WHEEL:
				{
					int value = MidiFilePitchWheelEvent_getValue(event);
					ok = writer_byte(&writer, (unsigned char)(0xe0 | (MidiFilePitchWheelEvent_getChannel(event) & 0x0f))) &&
						writer_byte(&writer, (unsigned char)(value & 0x7f)) &&
						writer_byte(&writer, (unsigned char)((value >> 7) & 0x7f));
					break;
				}
				case MIDI_FILE_EVENT_TYPE_SYSEX:
				{
					int data_length = MidiFileSysexEvent_getDataLength(event);
					unsigned char *data = MidiFileSysexEvent_getData(event);
					ok = (data_length >= 1) && (data != NULL) && ((data[0] == 0xf0) || (data[0] == 0xf7)) &&
						writer_byte(&writer, data[0]) && writer_vlq(&writer, (uint32_t)(data_length - 1)) &&
						writer_write(&writer, data + 1, (size_t)(data_length - 1));
					break;
				}
				case MIDI_FILE_EVENT_TYPE_META:
				{
					int data_length = MidiFileMetaEvent_getDataLength(event);
					unsigned char *data = MidiFileMetaEvent_getData(event);
					ok = (data_length >= 0) && ((data_length == 0) || (data != NULL)) &&
						writer_byte(&writer, 0xff) && writer_byte(&writer, (unsigned char)(MidiFileMetaEvent_getNumber(event) & 0x7f)) &&
						writer_vlq(&writer, (uint32_t)data_length) && writer_write(&writer, data, (size_t)data_length);
					break;
				}
				default: ok = false;
			}

			previous_tick = tick;
		}

		if ((MidiFileTrack_getEndTick(track) < previous_tick) ||
			!writer_vlq(&writer, (uint32_t)(MidiFileTrack_getEndTick(track) - previous_tick)) ||
			!writer_write(&writer, "\xff\x2f\x00", 3) || !writer_tell(&writer, &track_end_offset) ||
			(track_end_offset < track_start_offset) ||
			((unsigned long)(track_end_offset - track_start_offset) > UINT32_MAX) ||
			!writer_seek(&writer, track_size_offset) ||
			!writer_uint32(&writer, (uint32_t)(track_end_offset - track_start_offset)) ||
			!writer_seek(&writer, track_end_offset)) ok = false;
	}
	if (ok && (MIDI_IO(flush)(out) != 0)) ok = false;
	if (MIDI_IO(close)(out) != 0) ok = false;
	return ok ? 0 : -1;
}

MidiFile_t MidiFile_new(int file_format, MidiFileDivisionType_t division_type, int resolution)
{
	MidiFile_t midi_file;
	if (file_format<0 || file_format>2 || division_type<MIDI_FILE_DIVISION_TYPE_PPQ ||
		division_type>MIDI_FILE_DIVISION_TYPE_SMPTE30 || resolution<1 ||
		resolution>(division_type==MIDI_FILE_DIVISION_TYPE_PPQ ? 32767 : 255)) return NULL;
	midi_file = (MidiFile_t)midi_calloc(1, sizeof(struct MidiFile));
	if (midi_file == NULL) return NULL;
	midi_file->file_format = file_format;
	midi_file->division_type = division_type;
	midi_file->resolution = resolution;
	midi_file->number_of_tracks = 0;
	midi_file->first_track = NULL;
	midi_file->last_track = NULL;
	midi_file->first_event = NULL;
	midi_file->last_event = NULL;
	return midi_file;
}

int MidiFile_free(MidiFile_t midi_file)
{
	MidiFileTrack_t track, next_track;

	if (midi_file == NULL) return -1;

	for (track = midi_file->first_track; track != NULL; track = next_track)
	{
		next_track = track->next_track;
		free_events_in_track(track);
		midi_free(track);
	}

	midi_free(midi_file);
	return 0;
}

int MidiFile_getFileFormat(MidiFile_t midi_file)
{
	if (midi_file == NULL) return -1;
	return midi_file->file_format;
}

int MidiFile_setFileFormat(MidiFile_t midi_file, int file_format)
{
	if (midi_file == NULL) return -1;
	midi_file->file_format = file_format;
	return 0;
}

MidiFileDivisionType_t MidiFile_getDivisionType(MidiFile_t midi_file)
{
	if (midi_file == NULL) return MIDI_FILE_DIVISION_TYPE_INVALID;
	return midi_file->division_type;
}

int MidiFile_setDivisionType(MidiFile_t midi_file, MidiFileDivisionType_t division_type)
{
	if (midi_file == NULL) return -1;
	midi_file->division_type = division_type;
	return 0;
}

int MidiFile_getResolution(MidiFile_t midi_file)
{
	if (midi_file == NULL) return -1;
	return midi_file->resolution;
}

int MidiFile_setResolution(MidiFile_t midi_file, int resolution)
{
	if (midi_file == NULL) return -1;
	midi_file->resolution = resolution;
	return 0;
}

MidiFileTrack_t MidiFile_createTrack(MidiFile_t midi_file)
{
	MidiFileTrack_t new_track;

	if (midi_file == NULL || midi_file->number_of_tracks==INT_MAX) return NULL;

	new_track = (MidiFileTrack_t)midi_calloc(1, sizeof(struct MidiFileTrack));
	if (new_track == NULL) return NULL;
	new_track->midi_file = midi_file;
	new_track->number = midi_file->number_of_tracks;
	new_track->end_tick = 0;
	new_track->previous_track = midi_file->last_track;
	new_track->next_track = NULL;
	midi_file->last_track = new_track;

	if (new_track->previous_track == NULL)
	{
		midi_file->first_track = new_track;
	}
	else
	{
		new_track->previous_track->next_track = new_track;
	}

	(midi_file->number_of_tracks)++;

	new_track->first_event = NULL;
	new_track->last_event = NULL;

	return new_track;
}

int MidiFile_getNumberOfTracks(MidiFile_t midi_file)
{
	if (midi_file == NULL) return -1;
	return midi_file->number_of_tracks;
}

MidiFileTrack_t MidiFile_getTrackByNumber(MidiFile_t midi_file, int number, int create)
{
	int current_track_number;
	MidiFileTrack_t track = NULL;

	for (current_track_number = 0; current_track_number <= number; current_track_number++)
	{
		if (track == NULL)
		{
			track = MidiFile_getFirstTrack(midi_file);
		}
		else
		{
			track = MidiFileTrack_getNextTrack(track);
		}

		if ((track == NULL) && create)
		{
			track = MidiFile_createTrack(midi_file);
		}
	}

	return track;
}

MidiFileTrack_t MidiFile_getFirstTrack(MidiFile_t midi_file)
{
	if (midi_file == NULL) return NULL;
	return midi_file->first_track;
}

MidiFileTrack_t MidiFile_getLastTrack(MidiFile_t midi_file)
{
	if (midi_file == NULL) return NULL;
	return midi_file->last_track;
}

MidiFileEvent_t MidiFile_getFirstEvent(MidiFile_t midi_file)
{
	if (midi_file == NULL) return NULL;
	return midi_file->first_event;
}

MidiFileEvent_t MidiFile_getLastEvent(MidiFile_t midi_file)
{
	if (midi_file == NULL) return NULL;
	return midi_file->last_event;
}

int MidiFile_visitEvents(MidiFile_t midi_file, MidiFileEventVisitorCallback_t visitor_callback, void *user_data)
{
	MidiFileEvent_t event, next_event;

	if ((midi_file == NULL) || (visitor_callback == NULL)) return -1;

	for (event = MidiFile_getFirstEvent(midi_file); event != NULL; event = MidiFileEvent_getNextEventInFile(event)) event->should_be_visited = 1;

	for (event = MidiFile_getFirstEvent(midi_file); event != NULL; event = next_event)
	{
		next_event = MidiFileEvent_getNextEventInFile(event);

		if (event->should_be_visited)
		{
			event->should_be_visited = 0;
			(*visitor_callback)(event, user_data);
		}
	}

	return 0;
}

float MidiFile_getTimeFromTick(MidiFile_t midi_file, int32_t tick)
{
	switch (MidiFile_getDivisionType(midi_file))
	{
		case MIDI_FILE_DIVISION_TYPE_PPQ:
		{
			MidiFileTrack_t conductor_track = MidiFile_getFirstTrack(midi_file);
			MidiFileEvent_t event;
			float tempo_event_time = 0.0;
			int32_t tempo_event_tick = 0;
			float tempo = 120.0;

			for (event = MidiFileTrack_getFirstEvent(conductor_track); (event != NULL) && (MidiFileEvent_getTick(event) < tick); event = MidiFileEvent_getNextEventInTrack(event))
			{
				if (MidiFileEvent_isTempoEvent(event))
				{
					tempo_event_time += (((float)(MidiFileEvent_getTick(event) - tempo_event_tick)) / MidiFile_getResolution(midi_file) / (tempo / 60));
					tempo_event_tick = MidiFileEvent_getTick(event);
					tempo = MidiFileTempoEvent_getTempo(event);
				}
			}

			return tempo_event_time + (((float)(tick - tempo_event_tick)) / MidiFile_getResolution(midi_file) / (tempo / 60));
		}
		case MIDI_FILE_DIVISION_TYPE_SMPTE24:
		{
			return (float)(tick) / (MidiFile_getResolution(midi_file) * 24.0);
		}
		case MIDI_FILE_DIVISION_TYPE_SMPTE25:
		{
			return (float)(tick) / (MidiFile_getResolution(midi_file) * 25.0);
		}
		case MIDI_FILE_DIVISION_TYPE_SMPTE30DROP:
		{
			return (float)(tick) / (MidiFile_getResolution(midi_file) * 29.97);
		}
		case MIDI_FILE_DIVISION_TYPE_SMPTE30:
		{
			return (float)(tick) / (MidiFile_getResolution(midi_file) * 30.0);
		}
		default:
		{
			return -1;
		}
	}
}

int32_t MidiFile_getTickFromTime(MidiFile_t midi_file, float time)
{
	switch (MidiFile_getDivisionType(midi_file))
	{
		case MIDI_FILE_DIVISION_TYPE_PPQ:
		{
			MidiFileTrack_t conductor_track = MidiFile_getFirstTrack(midi_file);
			MidiFileEvent_t event;
			float tempo_event_time = 0.0;
			int32_t tempo_event_tick = 0;
			float tempo = 120.0;

			for (event = MidiFileTrack_getFirstEvent(conductor_track); event != NULL; event = MidiFileEvent_getNextEventInTrack(event))
			{
				if (MidiFileEvent_isTempoEvent(event))
				{
					float next_tempo_event_time = tempo_event_time + (((float)(MidiFileEvent_getTick(event) - tempo_event_tick)) / MidiFile_getResolution(midi_file) / (tempo / 60));
					if (next_tempo_event_time >= time) break;
					tempo_event_time = next_tempo_event_time;
					tempo_event_tick = MidiFileEvent_getTick(event);
					tempo = MidiFileTempoEvent_getTempo(event);
				}
			}

			return tempo_event_tick + ((time - tempo_event_time) * (tempo / 60) * MidiFile_getResolution(midi_file));
		}
		case MIDI_FILE_DIVISION_TYPE_SMPTE24:
		{
			return (int32_t)(time * MidiFile_getResolution(midi_file) * 24.0);
		}
		case MIDI_FILE_DIVISION_TYPE_SMPTE25:
		{
			return (int32_t)(time * MidiFile_getResolution(midi_file) * 25.0);
		}
		case MIDI_FILE_DIVISION_TYPE_SMPTE30DROP:
		{
			return (int32_t)(time * MidiFile_getResolution(midi_file) * 29.97);
		}
		case MIDI_FILE_DIVISION_TYPE_SMPTE30:
		{
			return (int32_t)(time * MidiFile_getResolution(midi_file) * 30.0);
		}
		default:
		{
			return -1;
		}
	}
}

float MidiFile_getBeatFromTick(MidiFile_t midi_file, int32_t tick)
{
	switch (MidiFile_getDivisionType(midi_file))
	{
		case MIDI_FILE_DIVISION_TYPE_PPQ:
		{
			return (float)(tick) / MidiFile_getResolution(midi_file);
		}
		case MIDI_FILE_DIVISION_TYPE_SMPTE24:
		{
			return -1.0; /* TODO */
		}
		case MIDI_FILE_DIVISION_TYPE_SMPTE25:
		{
			return -1.0; /* TODO */
		}
		case MIDI_FILE_DIVISION_TYPE_SMPTE30DROP:
		{
			return -1.0; /* TODO */
		}
		case MIDI_FILE_DIVISION_TYPE_SMPTE30:
		{
			return -1.0; /* TODO */
		}
		default:
		{
			return -1.0;
		}
	}
}

int32_t MidiFile_getTickFromBeat(MidiFile_t midi_file, float beat)
{
	switch (MidiFile_getDivisionType(midi_file))
	{
		case MIDI_FILE_DIVISION_TYPE_PPQ:
		{
			return (int32_t)(beat * MidiFile_getResolution(midi_file));
		}
		case MIDI_FILE_DIVISION_TYPE_SMPTE24:
		{
			return -1; /* TODO */
		}
		case MIDI_FILE_DIVISION_TYPE_SMPTE25:
		{
			return -1; /* TODO */
		}
		case MIDI_FILE_DIVISION_TYPE_SMPTE30DROP:
		{
			return -1; /* TODO */
		}
		case MIDI_FILE_DIVISION_TYPE_SMPTE30:
		{
			return -1; /* TODO */
		}
		default:
		{
			return -1;
		}
	}
}

int MidiFileTrack_delete(MidiFileTrack_t track)
{
	MidiFileTrack_t subsequent_track;

	if (track == NULL) return -1;

	for (subsequent_track = track->next_track; subsequent_track != NULL; subsequent_track = subsequent_track->next_track)
	{
		(subsequent_track->number)--;
	}
	
	(track->midi_file->number_of_tracks)--;

	if (track->previous_track == NULL)
	{
		track->midi_file->first_track = track->next_track;
	}
	else
	{
		track->previous_track->next_track = track->next_track;
	}

	if (track->next_track == NULL)
	{
		track->midi_file->last_track = track->previous_track;
	}
	else
	{
		track->next_track->previous_track = track->previous_track;
	}

	/* Each event belongs to both the track and the file's sorted event list. */
	while (track->first_event != NULL) MidiFileEvent_delete(track->first_event);
	midi_free(track);
	return 0;
}

MidiFile_t MidiFileTrack_getMidiFile(MidiFileTrack_t track)
{
	if (track == NULL) return NULL;
	return track->midi_file;
}

int MidiFileTrack_getNumber(MidiFileTrack_t track)
{
	if (track == NULL) return -1;
	return track->number;
}

int32_t MidiFileTrack_getEndTick(MidiFileTrack_t track)
{
	if (track == NULL) return -1;
	return track->end_tick;
}

int MidiFileTrack_setEndTick(MidiFileTrack_t track, int32_t end_tick)
{
	if ((track == NULL) || ((track->last_event != NULL) && (end_tick < track->last_event->tick))) return -1;
	track->end_tick = end_tick;
	return 0;
}

MidiFileTrack_t MidiFileTrack_createTrackBefore(MidiFileTrack_t track)
{
	MidiFileTrack_t new_track, subsequent_track;

	if (track == NULL) return NULL;

	new_track = (MidiFileTrack_t)midi_calloc(1, sizeof(struct MidiFileTrack));
	if (new_track == NULL) return NULL;
	new_track->midi_file = track->midi_file;
	new_track->number = track->number;
	new_track->end_tick = 0;
	new_track->previous_track = track->previous_track;
	new_track->next_track = track;
	track->previous_track = new_track;

	if (new_track->previous_track == NULL)
	{
		track->midi_file->first_track = new_track;
	}
	else
	{
		new_track->previous_track->next_track = new_track;
	}

	for (subsequent_track = track; subsequent_track != NULL; subsequent_track = subsequent_track->next_track)
	{
		(subsequent_track->number)++;
	}

	new_track->first_event = NULL;
	new_track->last_event = NULL;

	return new_track;
}

MidiFileTrack_t MidiFileTrack_getPreviousTrack(MidiFileTrack_t track)
{
	if (track == NULL) return NULL;
	return track->previous_track;
}

MidiFileTrack_t MidiFileTrack_getNextTrack(MidiFileTrack_t track)
{
	if (track == NULL) return NULL;
	return track->next_track;
}

MidiFileEvent_t MidiFileTrack_createNoteOffEvent(MidiFileTrack_t track, int32_t tick, int channel, int note, int velocity)
{
	MidiFileEvent_t new_event;

	if (track == NULL) return NULL;

	new_event = (MidiFileEvent_t)midi_calloc(1, sizeof(struct MidiFileEvent));
	if (new_event == NULL) return NULL;
	new_event->track = track;
	new_event->tick = tick;
	new_event->type = MIDI_FILE_EVENT_TYPE_NOTE_OFF;
	new_event->u.note_off.channel = channel;
	new_event->u.note_off.note = note;
	new_event->u.note_off.velocity = velocity;
	new_event->should_be_visited = 0;
	add_event(new_event);

	return new_event;
}

MidiFileEvent_t MidiFileTrack_createNoteOnEvent(MidiFileTrack_t track, int32_t tick, int channel, int note, int velocity)
{
	MidiFileEvent_t new_event;

	if (track == NULL) return NULL;

	new_event = (MidiFileEvent_t)midi_calloc(1, sizeof(struct MidiFileEvent));
	if (new_event == NULL) return NULL;
	new_event->track = track;
	new_event->tick = tick;
	new_event->type = MIDI_FILE_EVENT_TYPE_NOTE_ON;
	new_event->u.note_on.channel = channel;
	new_event->u.note_on.note = note;
	new_event->u.note_on.velocity = velocity;
	new_event->should_be_visited = 0;
	add_event(new_event);

	return new_event;
}

MidiFileEvent_t MidiFileTrack_createKeyPressureEvent(MidiFileTrack_t track, int32_t tick, int channel, int note, int amount)
{
	MidiFileEvent_t new_event;

	if (track == NULL) return NULL;

	new_event = (MidiFileEvent_t)midi_calloc(1, sizeof(struct MidiFileEvent));
	if (new_event == NULL) return NULL;
	new_event->track = track;
	new_event->tick = tick;
	new_event->type = MIDI_FILE_EVENT_TYPE_KEY_PRESSURE;
	new_event->u.key_pressure.channel = channel;
	new_event->u.key_pressure.note = note;
	new_event->u.key_pressure.amount = amount;
	new_event->should_be_visited = 0;
	add_event(new_event);

	return new_event;
}

MidiFileEvent_t MidiFileTrack_createControlChangeEvent(MidiFileTrack_t track, int32_t tick, int channel, int number, int value)
{
	MidiFileEvent_t new_event;

	if (track == NULL) return NULL;

	new_event = (MidiFileEvent_t)midi_calloc(1, sizeof(struct MidiFileEvent));
	if (new_event == NULL) return NULL;
	new_event->track = track;
	new_event->tick = tick;
	new_event->type = MIDI_FILE_EVENT_TYPE_CONTROL_CHANGE;
	new_event->u.control_change.channel = channel;
	new_event->u.control_change.number = number;
	new_event->u.control_change.value = value;
	new_event->should_be_visited = 0;
	add_event(new_event);

	return new_event;
}

MidiFileEvent_t MidiFileTrack_createProgramChangeEvent(MidiFileTrack_t track, int32_t tick, int channel, int number)
{
	MidiFileEvent_t new_event;

	if (track == NULL) return NULL;

	new_event = (MidiFileEvent_t)midi_calloc(1, sizeof(struct MidiFileEvent));
	if (new_event == NULL) return NULL;
	new_event->track = track;
	new_event->tick = tick;
	new_event->type = MIDI_FILE_EVENT_TYPE_PROGRAM_CHANGE;
	new_event->u.program_change.channel = channel;
	new_event->u.program_change.number = number;
	new_event->should_be_visited = 0;
	add_event(new_event);

	return new_event;
}

MidiFileEvent_t MidiFileTrack_createChannelPressureEvent(MidiFileTrack_t track, int32_t tick, int channel, int amount)
{
	MidiFileEvent_t new_event;

	if (track == NULL) return NULL;

	new_event = (MidiFileEvent_t)midi_calloc(1, sizeof(struct MidiFileEvent));
	if (new_event == NULL) return NULL;
	new_event->track = track;
	new_event->tick = tick;
	new_event->type = MIDI_FILE_EVENT_TYPE_CHANNEL_PRESSURE;
	new_event->u.channel_pressure.channel = channel;
	new_event->u.channel_pressure.amount = amount;
	new_event->should_be_visited = 0;
	add_event(new_event);

	return new_event;
}

MidiFileEvent_t MidiFileTrack_createPitchWheelEvent(MidiFileTrack_t track, int32_t tick, int channel, int value)
{
	MidiFileEvent_t new_event;

	if (track == NULL) return NULL;

	new_event = (MidiFileEvent_t)midi_calloc(1, sizeof(struct MidiFileEvent));
	if (new_event == NULL) return NULL;
	new_event->track = track;
	new_event->tick = tick;
	new_event->type = MIDI_FILE_EVENT_TYPE_PITCH_WHEEL;
	new_event->u.pitch_wheel.channel = channel;
	new_event->u.pitch_wheel.value = value;
	new_event->should_be_visited = 0;
	add_event(new_event);

	return new_event;
}

MidiFileEvent_t MidiFileTrack_createSysexEvent(MidiFileTrack_t track, int32_t tick, int data_length, unsigned char *data_buffer)
{
	MidiFileEvent_t new_event;

	if ((track == NULL) || tick<0 || (data_length < 1) || (data_buffer == NULL) ||
		(data_buffer[0]!=0xf0 && data_buffer[0]!=0xf7)) return NULL;

	new_event = (MidiFileEvent_t)midi_calloc(1, sizeof(struct MidiFileEvent));
	if (new_event == NULL) return NULL;
	new_event->track = track;
	new_event->tick = tick;
	new_event->type = MIDI_FILE_EVENT_TYPE_SYSEX;
	new_event->u.sysex.data_length = data_length;
	new_event->u.sysex.data_buffer = midi_malloc((size_t)data_length);
	if (new_event->u.sysex.data_buffer == NULL)
	{
		midi_free(new_event);
		return NULL;
	}
	memcpy(new_event->u.sysex.data_buffer, data_buffer, data_length);
	new_event->should_be_visited = 0;
	add_event(new_event);

	return new_event;
}

MidiFileEvent_t MidiFileTrack_createMetaEvent(MidiFileTrack_t track, int32_t tick, int number, int data_length, unsigned char *data_buffer)
{
	MidiFileEvent_t new_event;

	if ((track == NULL) || tick<0 || number<0 || number>255 || (data_length < 0) ||
		(number==0x2f && data_length!=0) || ((data_length != 0) && (data_buffer == NULL))) return NULL;

	new_event = (MidiFileEvent_t)midi_calloc(1, sizeof(struct MidiFileEvent));
	if (new_event == NULL) return NULL;
	new_event->track = track;
	new_event->tick = tick;
	new_event->type = MIDI_FILE_EVENT_TYPE_META;
	new_event->u.meta.number = number;
	new_event->u.meta.data_length = data_length;
	new_event->u.meta.data_buffer = NULL;
	if (data_length != 0)
	{
		new_event->u.meta.data_buffer = midi_malloc((size_t)data_length);
		if (new_event->u.meta.data_buffer == NULL)
		{
			midi_free(new_event);
			return NULL;
		}
		memcpy(new_event->u.meta.data_buffer, data_buffer, (size_t)data_length);
	}
	new_event->should_be_visited = 0;
	add_event(new_event);

	return new_event;
}

MidiFileEvent_t MidiFileTrack_createNoteStartAndEndEvents(MidiFileTrack_t track, int32_t start_tick, int32_t end_tick, int channel, int note, int start_velocity, int end_velocity)
{
	MidiFileEvent_t start_event = MidiFileTrack_createNoteOnEvent(track, start_tick, channel, note, start_velocity);
	MidiFileTrack_createNoteOffEvent(track, end_tick, channel, note, end_velocity);
	return start_event;
}

MidiFileEvent_t MidiFileTrack_createTempoEvent(MidiFileTrack_t track, int32_t tick, float tempo)
{
	int32_t midi_tempo = 60000000 / tempo;
	unsigned char buffer[3];
	buffer[0] = (midi_tempo >> 16) & 0xFF;
	buffer[1] = (midi_tempo >> 8) & 0xFF;
	buffer[2] = midi_tempo & 0xFF;
	return MidiFileTrack_createMetaEvent(track, tick, 0x51, 3, buffer);
}

MidiFileEvent_t MidiFileTrack_createVoiceEvent(MidiFileTrack_t track, int32_t tick, uint32_t data)
{
	MidiFileEvent_t new_event;

	if (track == NULL || tick<0 || (data&0xff)<0x80 || (data&0xff)>=0xf0 ||
		(data&0xff000000U) || (((data&0xf0)==0xc0 || (data&0xf0)==0xd0) &&
		(data&0xffff0000U))) return NULL;

	new_event = (MidiFileEvent_t)midi_calloc(1, sizeof(struct MidiFileEvent));
	if (new_event == NULL) return NULL;
	new_event->track = track;
	new_event->tick = tick;
	MidiFileVoiceEvent_setData(new_event, data);
	new_event->should_be_visited = 0;
	add_event(new_event);

	return new_event;
}

MidiFileEvent_t MidiFileTrack_getFirstEvent(MidiFileTrack_t track)
{
	if (track == NULL) return NULL;
	return track->first_event;
}

MidiFileEvent_t MidiFileTrack_getLastEvent(MidiFileTrack_t track)
{
	if (track == NULL) return NULL;
	return track->last_event;
}

int MidiFileTrack_visitEvents(MidiFileTrack_t track, MidiFileEventVisitorCallback_t visitor_callback, void *user_data)
{
	MidiFileEvent_t event, next_event;

	if ((track == NULL) || (visitor_callback == NULL)) return -1;

	for (event = MidiFileTrack_getFirstEvent(track); event != NULL; event = MidiFileEvent_getNextEventInTrack(event)) event->should_be_visited = 1;

	for (event = MidiFileTrack_getFirstEvent(track); event != NULL; event = next_event)
	{
		next_event = MidiFileEvent_getNextEventInTrack(event);

		if (event->should_be_visited)
		{
			event->should_be_visited = 0;
			(*visitor_callback)(event, user_data);
		}
	}

	return 0;
}

int MidiFileEvent_delete(MidiFileEvent_t event)
{
	if (event == NULL) return -1;
	remove_event(event);

	switch (event->type)
	{
		case MIDI_FILE_EVENT_TYPE_SYSEX:
		{
			midi_free(event->u.sysex.data_buffer);
			break;
		}
		case MIDI_FILE_EVENT_TYPE_META:
		{
			midi_free(event->u.meta.data_buffer);
			break;
		}
		default: ;
	}

	midi_free(event);
	return 0;
}

MidiFileTrack_t MidiFileEvent_getTrack(MidiFileEvent_t event)
{
	if (event == NULL) return NULL;
	return event->track;
}

MidiFileEvent_t MidiFileEvent_getPreviousEvent(MidiFileEvent_t event)
{
	return MidiFileEvent_getPreviousEventInTrack(event);
}

MidiFileEvent_t MidiFileEvent_getNextEvent(MidiFileEvent_t event)
{
	return MidiFileEvent_getNextEventInTrack(event);
}

MidiFileEvent_t MidiFileEvent_getPreviousEventInTrack(MidiFileEvent_t event)
{
	if (event == NULL) return NULL;
	return event->previous_event_in_track;
}

MidiFileEvent_t MidiFileEvent_getNextEventInTrack(MidiFileEvent_t event)
{
	if (event == NULL) return NULL;
	return event->next_event_in_track;
}

MidiFileEvent_t MidiFileEvent_getPreviousEventInFile(MidiFileEvent_t event)
{
	if (event == NULL) return NULL;
	return event->previous_event_in_file;
}

MidiFileEvent_t MidiFileEvent_getNextEventInFile(MidiFileEvent_t event)
{
	if (event == NULL) return NULL;
	return event->next_event_in_file;
}

int32_t MidiFileEvent_getTick(MidiFileEvent_t event)
{
	if (event == NULL) return -1;
	return event->tick;
}

int MidiFileEvent_setTick(MidiFileEvent_t event, int32_t tick)
{
	if (event == NULL) return -1;
	remove_event(event);
	event->tick = tick;
	add_event(event);
	return 0;
}

MidiFileEventType_t MidiFileEvent_getType(MidiFileEvent_t event)
{
	if (event == NULL) return MIDI_FILE_EVENT_TYPE_INVALID;
	return event->type;
}

int MidiFileEvent_isNoteStartEvent(MidiFileEvent_t event)
{
	return ((MidiFileEvent_getType(event) == MIDI_FILE_EVENT_TYPE_NOTE_ON) && (MidiFileNoteOnEvent_getVelocity(event) > 0));
}

int MidiFileEvent_isNoteEndEvent(MidiFileEvent_t event)
{
	return ((MidiFileEvent_getType(event) == MIDI_FILE_EVENT_TYPE_NOTE_OFF) || ((MidiFileEvent_getType(event) == MIDI_FILE_EVENT_TYPE_NOTE_ON) && (MidiFileNoteOnEvent_getVelocity(event) == 0)));
}

int MidiFileEvent_isTempoEvent(MidiFileEvent_t event)
{
	return ((MidiFileEvent_getType(event) == MIDI_FILE_EVENT_TYPE_META) && (MidiFileMetaEvent_getNumber(event) == 0x51));
}

int MidiFileEvent_isVoiceEvent(MidiFileEvent_t event)
{
	switch (event->type)
	{
		case MIDI_FILE_EVENT_TYPE_NOTE_OFF:
		case MIDI_FILE_EVENT_TYPE_NOTE_ON:
		case MIDI_FILE_EVENT_TYPE_KEY_PRESSURE:
		case MIDI_FILE_EVENT_TYPE_CONTROL_CHANGE:
		case MIDI_FILE_EVENT_TYPE_PROGRAM_CHANGE:
		case MIDI_FILE_EVENT_TYPE_CHANNEL_PRESSURE:
		case MIDI_FILE_EVENT_TYPE_PITCH_WHEEL:
		{
			return 1;
		}
		default:
		{
			return 0;
		}
	}
}

int MidiFileNoteOffEvent_getChannel(MidiFileEvent_t event)
{
	if ((event == NULL) || (event->type != MIDI_FILE_EVENT_TYPE_NOTE_OFF)) return -1;
	return event->u.note_off.channel;
}

int MidiFileNoteOffEvent_setChannel(MidiFileEvent_t event, int channel)
{
	if ((event == NULL) || (event->type != MIDI_FILE_EVENT_TYPE_NOTE_OFF)) return -1;
	event->u.note_off.channel = channel;
	return 0;
}

int MidiFileNoteOffEvent_getNote(MidiFileEvent_t event)
{
	if ((event == NULL) || (event->type != MIDI_FILE_EVENT_TYPE_NOTE_OFF)) return -1;
	return event->u.note_off.note;
}

int MidiFileNoteOffEvent_setNote(MidiFileEvent_t event, int note)
{
	if ((event == NULL) || (event->type != MIDI_FILE_EVENT_TYPE_NOTE_OFF)) return -1;
	event->u.note_off.note = note;
	return 0;
}

int MidiFileNoteOffEvent_getVelocity(MidiFileEvent_t event)
{
	if ((event == NULL) || (event->type != MIDI_FILE_EVENT_TYPE_NOTE_OFF)) return -1;
	return event->u.note_off.velocity;
}

int MidiFileNoteOffEvent_setVelocity(MidiFileEvent_t event, int velocity)
{
	if ((event == NULL) || (event->type != MIDI_FILE_EVENT_TYPE_NOTE_OFF)) return -1;
	event->u.note_off.velocity = velocity;
	return 0;
}

int MidiFileNoteOnEvent_getChannel(MidiFileEvent_t event)
{
	if ((event == NULL) || (event->type != MIDI_FILE_EVENT_TYPE_NOTE_ON)) return -1;
	return event->u.note_on.channel;
}

int MidiFileNoteOnEvent_setChannel(MidiFileEvent_t event, int channel)
{
	if ((event == NULL) || (event->type != MIDI_FILE_EVENT_TYPE_NOTE_ON)) return -1;
	event->u.note_on.channel = channel;
	return 0;
}

int MidiFileNoteOnEvent_getNote(MidiFileEvent_t event)
{
	if ((event == NULL) || (event->type != MIDI_FILE_EVENT_TYPE_NOTE_ON)) return -1;
	return event->u.note_on.note;
}

int MidiFileNoteOnEvent_setNote(MidiFileEvent_t event, int note)
{
	if ((event == NULL) || (event->type != MIDI_FILE_EVENT_TYPE_NOTE_ON)) return -1;
	event->u.note_on.note = note;
	return 0;
}

int MidiFileNoteOnEvent_getVelocity(MidiFileEvent_t event)
{
	if ((event == NULL) || (event->type != MIDI_FILE_EVENT_TYPE_NOTE_ON)) return -1;
	return event->u.note_on.velocity;
}

int MidiFileNoteOnEvent_setVelocity(MidiFileEvent_t event, int velocity)
{
	if ((event == NULL) || (event->type != MIDI_FILE_EVENT_TYPE_NOTE_ON)) return -1;
	event->u.note_on.velocity = velocity;
	return 0;
}

int MidiFileKeyPressureEvent_getChannel(MidiFileEvent_t event)
{
	if ((event == NULL) || (event->type != MIDI_FILE_EVENT_TYPE_KEY_PRESSURE)) return -1;
	return event->u.key_pressure.channel;
}

int MidiFileKeyPressureEvent_setChannel(MidiFileEvent_t event, int channel)
{
	if ((event == NULL) || (event->type != MIDI_FILE_EVENT_TYPE_KEY_PRESSURE)) return -1;
	event->u.key_pressure.channel = channel;
	return 0;
}

int MidiFileKeyPressureEvent_getNote(MidiFileEvent_t event)
{
	if ((event == NULL) || (event->type != MIDI_FILE_EVENT_TYPE_KEY_PRESSURE)) return -1;
	return event->u.key_pressure.note;
}

int MidiFileKeyPressureEvent_setNote(MidiFileEvent_t event, int note)
{
	if ((event == NULL) || (event->type != MIDI_FILE_EVENT_TYPE_KEY_PRESSURE)) return -1;
	event->u.key_pressure.note = note;
	return 0;
}

int MidiFileKeyPressureEvent_getAmount(MidiFileEvent_t event)
{
	if ((event == NULL) || (event->type != MIDI_FILE_EVENT_TYPE_KEY_PRESSURE)) return -1;
	return event->u.key_pressure.amount;
}

int MidiFileKeyPressureEvent_setAmount(MidiFileEvent_t event, int amount)
{
	if ((event == NULL) || (event->type != MIDI_FILE_EVENT_TYPE_KEY_PRESSURE)) return -1;
	event->u.key_pressure.amount = amount;
	return 0;
}

int MidiFileControlChangeEvent_getChannel(MidiFileEvent_t event)
{
	if ((event == NULL) || (event->type != MIDI_FILE_EVENT_TYPE_CONTROL_CHANGE)) return -1;
	return event->u.control_change.channel;
}

int MidiFileControlChangeEvent_setChannel(MidiFileEvent_t event, int channel)
{
	if ((event == NULL) || (event->type != MIDI_FILE_EVENT_TYPE_CONTROL_CHANGE)) return -1;
	event->u.control_change.channel = channel;
	return 0;
}

int MidiFileControlChangeEvent_getNumber(MidiFileEvent_t event)
{
	if ((event == NULL) || (event->type != MIDI_FILE_EVENT_TYPE_CONTROL_CHANGE)) return -1;
	return event->u.control_change.number;
}

int MidiFileControlChangeEvent_setNumber(MidiFileEvent_t event, int number)
{
	if ((event == NULL) || (event->type != MIDI_FILE_EVENT_TYPE_CONTROL_CHANGE)) return -1;
	event->u.control_change.number = number;
	return 0;
}

int MidiFileControlChangeEvent_getValue(MidiFileEvent_t event)
{
	if ((event == NULL) || (event->type != MIDI_FILE_EVENT_TYPE_CONTROL_CHANGE)) return -1;
	return event->u.control_change.value;
}

int MidiFileControlChangeEvent_setValue(MidiFileEvent_t event, int value)
{
	if ((event == NULL) || (event->type != MIDI_FILE_EVENT_TYPE_CONTROL_CHANGE)) return -1;
	event->u.control_change.value = value;
	return 0;
}

int MidiFileProgramChangeEvent_getChannel(MidiFileEvent_t event)
{
	if ((event == NULL) || (event->type != MIDI_FILE_EVENT_TYPE_PROGRAM_CHANGE)) return -1;
	return event->u.program_change.channel;
}

int MidiFileProgramChangeEvent_setChannel(MidiFileEvent_t event, int channel)
{
	if ((event == NULL) || (event->type != MIDI_FILE_EVENT_TYPE_PROGRAM_CHANGE)) return -1;
	event->u.program_change.channel = channel;
	return 0;
}

int MidiFileProgramChangeEvent_getNumber(MidiFileEvent_t event)
{
	if ((event == NULL) || (event->type != MIDI_FILE_EVENT_TYPE_PROGRAM_CHANGE)) return -1;
	return event->u.program_change.number;
}

int MidiFileProgramChangeEvent_setNumber(MidiFileEvent_t event, int number)
{
	if ((event == NULL) || (event->type != MIDI_FILE_EVENT_TYPE_PROGRAM_CHANGE)) return -1;
	event->u.program_change.number = number;
	return 0;
}

int MidiFileChannelPressureEvent_getChannel(MidiFileEvent_t event)
{
	if ((event == NULL) || (event->type != MIDI_FILE_EVENT_TYPE_CHANNEL_PRESSURE)) return -1;
	return event->u.channel_pressure.channel;
}

int MidiFileChannelPressureEvent_setChannel(MidiFileEvent_t event, int channel)
{
	if ((event == NULL) || (event->type != MIDI_FILE_EVENT_TYPE_CHANNEL_PRESSURE)) return -1;
	event->u.channel_pressure.channel = channel;
	return 0;
}

int MidiFileChannelPressureEvent_getAmount(MidiFileEvent_t event)
{
	if ((event == NULL) || (event->type != MIDI_FILE_EVENT_TYPE_CHANNEL_PRESSURE)) return -1;
	return event->u.channel_pressure.amount;
}

int MidiFileChannelPressureEvent_setAmount(MidiFileEvent_t event, int amount)
{
	if ((event == NULL) || (event->type != MIDI_FILE_EVENT_TYPE_CHANNEL_PRESSURE)) return -1;
	event->u.channel_pressure.amount = amount;
	return 0;
}

int MidiFilePitchWheelEvent_getChannel(MidiFileEvent_t event)
{
	if ((event == NULL) || (event->type != MIDI_FILE_EVENT_TYPE_PITCH_WHEEL)) return -1;
	return event->u.pitch_wheel.channel;
}

int MidiFilePitchWheelEvent_setChannel(MidiFileEvent_t event, int channel)
{
	if ((event == NULL) || (event->type != MIDI_FILE_EVENT_TYPE_PITCH_WHEEL)) return -1;
	event->u.pitch_wheel.channel = channel;
	return 0;
}

int MidiFilePitchWheelEvent_getValue(MidiFileEvent_t event)
{
	if ((event == NULL) || (event->type != MIDI_FILE_EVENT_TYPE_PITCH_WHEEL)) return -1;
	return event->u.pitch_wheel.value;
}

int MidiFilePitchWheelEvent_setValue(MidiFileEvent_t event, int value)
{
	if ((event == NULL) || (event->type != MIDI_FILE_EVENT_TYPE_PITCH_WHEEL)) return -1;
	event->u.pitch_wheel.value = value;
	return 0;
}

int MidiFileSysexEvent_getDataLength(MidiFileEvent_t event)
{
	if ((event == NULL) || (event->type != MIDI_FILE_EVENT_TYPE_SYSEX)) return -1;
	return event->u.sysex.data_length;
}

unsigned char *MidiFileSysexEvent_getData(MidiFileEvent_t event)
{
	if ((event == NULL) || (event->type != MIDI_FILE_EVENT_TYPE_SYSEX)) return NULL;
	return event->u.sysex.data_buffer;
}

int MidiFileSysexEvent_setData(MidiFileEvent_t event, int data_length, unsigned char *data_buffer)
{
	if ((event == NULL) || (event->type != MIDI_FILE_EVENT_TYPE_SYSEX) || (data_length < 1) || (data_buffer == NULL)) return -1;
	{
		unsigned char *replacement = (unsigned char *)midi_malloc((size_t)data_length);
		if (replacement == NULL) return -1;
		memcpy(replacement, data_buffer, (size_t)data_length);
		midi_free(event->u.sysex.data_buffer);
		event->u.sysex.data_length = data_length;
		event->u.sysex.data_buffer = replacement;
	}
	return 0;
}

int MidiFileMetaEvent_getNumber(MidiFileEvent_t event)
{
	if ((event == NULL) || (event->type != MIDI_FILE_EVENT_TYPE_META)) return -1;
	return event->u.meta.number;
}

int MidiFileMetaEvent_setNumber(MidiFileEvent_t event, int number)
{
	if ((event == NULL) || (event->type != MIDI_FILE_EVENT_TYPE_META)) return -1;
	event->u.meta.number = number;
	return 0;
}

int MidiFileMetaEvent_getDataLength(MidiFileEvent_t event)
{
	if ((event == NULL) || (event->type != MIDI_FILE_EVENT_TYPE_META)) return -1;
	return event->u.meta.data_length;
}

unsigned char *MidiFileMetaEvent_getData(MidiFileEvent_t event)
{
	if ((event == NULL) || (event->type != MIDI_FILE_EVENT_TYPE_META)) return NULL;
	return event->u.meta.data_buffer;
}

int MidiFileMetaEvent_setData(MidiFileEvent_t event, int data_length, unsigned char *data_buffer)
{
	if ((event == NULL) || (event->type != MIDI_FILE_EVENT_TYPE_META) || (data_length < 0) || ((data_length != 0) && (data_buffer == NULL))) return -1;
	{
		unsigned char *replacement = NULL;
		if (data_length != 0)
		{
			replacement = (unsigned char *)midi_malloc((size_t)data_length);
			if (replacement == NULL) return -1;
			memcpy(replacement, data_buffer, (size_t)data_length);
		}
		midi_free(event->u.meta.data_buffer);
		event->u.meta.data_length = data_length;
		event->u.meta.data_buffer = replacement;
	}
	return 0;
}

int MidiFileNoteStartEvent_getChannel(MidiFileEvent_t event)
{
	if (! MidiFileEvent_isNoteStartEvent(event)) return -1;
	return MidiFileNoteOnEvent_getChannel(event);
}

int MidiFileNoteStartEvent_setChannel(MidiFileEvent_t event, int channel)
{
	if (! MidiFileEvent_isNoteStartEvent(event)) return -1;
	return MidiFileNoteOnEvent_setChannel(event, channel);
}

int MidiFileNoteStartEvent_getNote(MidiFileEvent_t event)
{
	if (! MidiFileEvent_isNoteStartEvent(event)) return -1;
	return MidiFileNoteOnEvent_getNote(event);
}

int MidiFileNoteStartEvent_setNote(MidiFileEvent_t event, int note)
{
	if (! MidiFileEvent_isNoteStartEvent(event)) return -1;
	return MidiFileNoteOnEvent_setNote(event, note);
}

int MidiFileNoteStartEvent_getVelocity(MidiFileEvent_t event)
{
	if (! MidiFileEvent_isNoteStartEvent(event)) return -1;
	return MidiFileNoteOnEvent_getVelocity(event);
}

int MidiFileNoteStartEvent_setVelocity(MidiFileEvent_t event, int velocity)
{
	if (! MidiFileEvent_isNoteStartEvent(event)) return -1;
	return MidiFileNoteOnEvent_setVelocity(event, velocity);
}

MidiFileEvent_t MidiFileNoteStartEvent_getNoteEndEvent(MidiFileEvent_t event)
{
	MidiFileEvent_t subsequent_event;

	if (! MidiFileEvent_isNoteStartEvent(event)) return NULL;

	for (subsequent_event = MidiFileEvent_getNextEventInTrack(event); subsequent_event != NULL; subsequent_event = MidiFileEvent_getNextEventInTrack(subsequent_event))
	{
		if (MidiFileEvent_isNoteEndEvent(subsequent_event) && (MidiFileNoteEndEvent_getChannel(subsequent_event) == MidiFileNoteStartEvent_getChannel(event)) && (MidiFileNoteEndEvent_getNote(subsequent_event) == MidiFileNoteStartEvent_getNote(event)))
		{
			return subsequent_event;
		}
	}

	return NULL;
}

int MidiFileNoteEndEvent_getChannel(MidiFileEvent_t event)
{
	if (! MidiFileEvent_isNoteEndEvent(event)) return -1;

	switch (MidiFileEvent_getType(event))
	{
		case MIDI_FILE_EVENT_TYPE_NOTE_ON:
		{
			return MidiFileNoteOnEvent_getChannel(event);
		}
		case MIDI_FILE_EVENT_TYPE_NOTE_OFF:
		{
			return MidiFileNoteOffEvent_getChannel(event);
		}
		default:
		{
			return -1;
		}
	}
}

int MidiFileNoteEndEvent_setChannel(MidiFileEvent_t event, int channel)
{
	if (! MidiFileEvent_isNoteEndEvent(event)) return -1;

	switch (MidiFileEvent_getType(event))
	{
		case MIDI_FILE_EVENT_TYPE_NOTE_ON:
		{
			return MidiFileNoteOnEvent_setChannel(event, channel);
		}
		case MIDI_FILE_EVENT_TYPE_NOTE_OFF:
		{
			return MidiFileNoteOffEvent_setChannel(event, channel);
		}
		default:
		{
			return -1;
		}
	}
}

int MidiFileNoteEndEvent_getNote(MidiFileEvent_t event)
{
	if (! MidiFileEvent_isNoteEndEvent(event)) return -1;

	switch (MidiFileEvent_getType(event))
	{
		case MIDI_FILE_EVENT_TYPE_NOTE_ON:
		{
			return MidiFileNoteOnEvent_getNote(event);
		}
		case MIDI_FILE_EVENT_TYPE_NOTE_OFF:
		{
			return MidiFileNoteOffEvent_getNote(event);
		}
		default:
		{
			return -1;
		}
	}
}

int MidiFileNoteEndEvent_setNote(MidiFileEvent_t event, int note)
{
	if (! MidiFileEvent_isNoteEndEvent(event)) return -1;

	switch (MidiFileEvent_getType(event))
	{
		case MIDI_FILE_EVENT_TYPE_NOTE_ON:
		{
			return MidiFileNoteOnEvent_setNote(event, note);
		}
		case MIDI_FILE_EVENT_TYPE_NOTE_OFF:
		{
			return MidiFileNoteOffEvent_setNote(event, note);
		}
		default:
		{
			return -1;
		}
	}
}

int MidiFileNoteEndEvent_getVelocity(MidiFileEvent_t event)
{
	if (! MidiFileEvent_isNoteEndEvent(event)) return -1;

	switch (MidiFileEvent_getType(event))
	{
		case MIDI_FILE_EVENT_TYPE_NOTE_OFF:
		{
			return MidiFileNoteOffEvent_getVelocity(event);
		}
		case MIDI_FILE_EVENT_TYPE_NOTE_ON:
		{
			return 0;
		}
		default:
		{
			return -1;
		}
	}
}

int MidiFileNoteEndEvent_setVelocity(MidiFileEvent_t event, int velocity)
{
	if (! MidiFileEvent_isNoteEndEvent(event)) return -1;

	switch (MidiFileEvent_getType(event))
	{
		case MIDI_FILE_EVENT_TYPE_NOTE_OFF:
		{
			return MidiFileNoteOffEvent_setVelocity(event, velocity);
		}
		case MIDI_FILE_EVENT_TYPE_NOTE_ON:
		{
			MidiFileTrack_createNoteOffEvent(MidiFileEvent_getTrack(event), MidiFileEvent_getTick(event), MidiFileNoteOnEvent_getChannel(event), MidiFileNoteOnEvent_getNote(event), velocity);
			MidiFileEvent_delete(event);
			return 0;
		}
		default:
		{
			return -1;
		}
	}
}

MidiFileEvent_t MidiFileNoteEndEvent_getNoteStartEvent(MidiFileEvent_t event)
{
	MidiFileEvent_t preceding_event;

	if (! MidiFileEvent_isNoteEndEvent(event)) return NULL;

	for (preceding_event = MidiFileEvent_getPreviousEventInTrack(event); preceding_event != NULL; preceding_event = MidiFileEvent_getPreviousEventInTrack(preceding_event))
	{
		if (MidiFileEvent_isNoteStartEvent(preceding_event) && (MidiFileNoteStartEvent_getChannel(preceding_event) == MidiFileNoteEndEvent_getChannel(event)) && (MidiFileNoteStartEvent_getNote(preceding_event) == MidiFileNoteEndEvent_getNote(event)))
		{
			return preceding_event;
		}
	}

	return NULL;
}

float MidiFileTempoEvent_getTempo(MidiFileEvent_t event)
{
	unsigned char *buffer;
	int32_t midi_tempo;

	if (! MidiFileEvent_isTempoEvent(event)) return -1;

	buffer = MidiFileMetaEvent_getData(event);
	midi_tempo = (buffer[0] << 16) | (buffer[1] << 8) | buffer[2];
	return 60000000.0 / midi_tempo;
}

int MidiFileTempoEvent_setTempo(MidiFileEvent_t event, float tempo)
{
	int32_t midi_tempo;
	unsigned char buffer[3];

	if (! MidiFileEvent_isTempoEvent(event)) return -1;

	midi_tempo = 60000000 / tempo;
	buffer[0] = (midi_tempo >> 16) & 0xFF;
	buffer[1] = (midi_tempo >> 8) & 0xFF;
	buffer[2] = midi_tempo & 0xFF;
	return MidiFileMetaEvent_setData(event, 3, buffer);
}

uint32_t MidiFileVoiceEvent_getData(MidiFileEvent_t event)
{
	switch (MidiFileEvent_getType(event))
	{
		case MIDI_FILE_EVENT_TYPE_NOTE_OFF:
		{
			union
			{
				unsigned char data_as_bytes[4];
				uint32_t data_as_uint32;
			}
			u;

			u.data_as_bytes[0] = 0x80 | MidiFileNoteOffEvent_getChannel(event);
			u.data_as_bytes[1] = MidiFileNoteOffEvent_getNote(event);
			u.data_as_bytes[2] = MidiFileNoteOffEvent_getVelocity(event);
			u.data_as_bytes[3] = 0;
			return u.data_as_uint32;
		}
		case MIDI_FILE_EVENT_TYPE_NOTE_ON:
		{
			union
			{
				unsigned char data_as_bytes[4];
				uint32_t data_as_uint32;
			}
			u;

			u.data_as_bytes[0] = 0x90 | MidiFileNoteOnEvent_getChannel(event);
			u.data_as_bytes[1] = MidiFileNoteOnEvent_getNote(event);
			u.data_as_bytes[2] = MidiFileNoteOnEvent_getVelocity(event);
			u.data_as_bytes[3] = 0;
			return u.data_as_uint32;
		}
		case MIDI_FILE_EVENT_TYPE_KEY_PRESSURE:
		{
			union
			{
				unsigned char data_as_bytes[4];
				uint32_t data_as_uint32;
			}
			u;

			u.data_as_bytes[0] = 0xA0 | MidiFileKeyPressureEvent_getChannel(event);
			u.data_as_bytes[1] = MidiFileKeyPressureEvent_getNote(event);
			u.data_as_bytes[2] = MidiFileKeyPressureEvent_getAmount(event);
			u.data_as_bytes[3] = 0;
			return u.data_as_uint32;
		}
		case MIDI_FILE_EVENT_TYPE_CONTROL_CHANGE:
		{
			union
			{
				unsigned char data_as_bytes[4];
				uint32_t data_as_uint32;
			}
			u;

			u.data_as_bytes[0] = 0xB0 | MidiFileControlChangeEvent_getChannel(event);
			u.data_as_bytes[1] = MidiFileControlChangeEvent_getNumber(event);
			u.data_as_bytes[2] = MidiFileControlChangeEvent_getValue(event);
			u.data_as_bytes[3] = 0;
			return u.data_as_uint32;
		}
		case MIDI_FILE_EVENT_TYPE_PROGRAM_CHANGE:
		{
			union
			{
				unsigned char data_as_bytes[4];
				uint32_t data_as_uint32;
			}
			u;

			u.data_as_bytes[0] = 0xC0 | MidiFileProgramChangeEvent_getChannel(event);
			u.data_as_bytes[1] = MidiFileProgramChangeEvent_getNumber(event);
			u.data_as_bytes[2] = 0;
			u.data_as_bytes[3] = 0;
			return u.data_as_uint32;
		}
		case MIDI_FILE_EVENT_TYPE_CHANNEL_PRESSURE:
		{
			union
			{
				unsigned char data_as_bytes[4];
				uint32_t data_as_uint32;
			}
			u;

			u.data_as_bytes[0] = 0xD0 | MidiFileChannelPressureEvent_getChannel(event);
			u.data_as_bytes[1] = MidiFileChannelPressureEvent_getAmount(event);
			u.data_as_bytes[2] = 0;
			u.data_as_bytes[3] = 0;
			return u.data_as_uint32;
		}
		case MIDI_FILE_EVENT_TYPE_PITCH_WHEEL:
		{
			union
			{
				unsigned char data_as_bytes[4];
				uint32_t data_as_uint32;
			}
			u;

			u.data_as_bytes[0] = 0xE0 | MidiFilePitchWheelEvent_getChannel(event);
			// fixed reversed byte order -- ag
			u.data_as_bytes[1] = MidiFilePitchWheelEvent_getValue(event) & 0x7F;
			u.data_as_bytes[2] = (MidiFilePitchWheelEvent_getValue(event) >> 7) & 0x7F;
			u.data_as_bytes[3] = 0;
			return u.data_as_uint32;
		}
		default:
		{
			return 0;
		}
	}
}

int MidiFileVoiceEvent_setData(MidiFileEvent_t event, uint32_t data)
{
	union
	{
		uint32_t data_as_uint32;
		unsigned char data_as_bytes[4];
	}
	u;

	if (event == NULL) return -1;

	u.data_as_uint32 = data;

	switch (u.data_as_bytes[0] & 0xF0)
	{
		case 0x80:
		{
			event->type = MIDI_FILE_EVENT_TYPE_NOTE_OFF;
			event->u.note_off.channel = u.data_as_bytes[0] & 0x0F;
			event->u.note_off.note = u.data_as_bytes[1];
			event->u.note_off.velocity = u.data_as_bytes[2];
			return 0;
		}
		case 0x90:
		{
			event->type = MIDI_FILE_EVENT_TYPE_NOTE_ON;
			event->u.note_on.channel = u.data_as_bytes[0] & 0x0F;
			event->u.note_on.note = u.data_as_bytes[1];
			event->u.note_on.velocity = u.data_as_bytes[2];
			return 0;
		}
		case 0xA0:
		{
			event->type = MIDI_FILE_EVENT_TYPE_KEY_PRESSURE;
			event->u.key_pressure.channel = u.data_as_bytes[0] & 0x0F;
			event->u.key_pressure.note = u.data_as_bytes[1];
			event->u.key_pressure.amount = u.data_as_bytes[2];
			return 0;
		}
		case 0xB0:
		{
			event->type = MIDI_FILE_EVENT_TYPE_CONTROL_CHANGE;
			event->u.control_change.channel = u.data_as_bytes[0] & 0x0F;
			event->u.control_change.number = u.data_as_bytes[1];
			event->u.control_change.value = u.data_as_bytes[2];
			return 0;
		}
		case 0xC0:
		{
			event->type = MIDI_FILE_EVENT_TYPE_PROGRAM_CHANGE;
			event->u.program_change.channel = u.data_as_bytes[0] & 0x0F;
			event->u.program_change.number = u.data_as_bytes[1];
			return 0;
		}
		case 0xD0:
		{
			event->type = MIDI_FILE_EVENT_TYPE_CHANNEL_PRESSURE;
			event->u.channel_pressure.channel = u.data_as_bytes[0] & 0x0F;
			event->u.channel_pressure.amount = u.data_as_bytes[1];
			return 0;
		}
		case 0xE0:
		{
			event->type = MIDI_FILE_EVENT_TYPE_PITCH_WHEEL;
			event->u.pitch_wheel.channel = u.data_as_bytes[0] & 0x0F;
			// fixed reversed byte order -- ag
			event->u.pitch_wheel.value = u.data_as_bytes[1] | (u.data_as_bytes[2] << 7);
			return 0;
		}
		default:
		{
			return -1;
		}
	}
}

