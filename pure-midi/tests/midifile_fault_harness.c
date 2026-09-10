#include "midifile.h"
#include "midifile_test_api.h"

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define ARRAY_COUNT(a) (sizeof(a) / sizeof((a)[0]))
#define MAX_TRACKED_ALLOCATIONS 8192

typedef enum IoFault
{
	IO_FAULT_NONE,
	IO_FAULT_READ,
	IO_FAULT_WRITE,
	IO_FAULT_SEEK,
	IO_FAULT_TELL,
	IO_FAULT_FLUSH,
	IO_FAULT_CLOSE
} IoFault;

static void *live_allocations[MAX_TRACKED_ALLOCATIONS];
static size_t live_allocation_count;
static size_t allocation_calls;
static size_t allocation_fail_at;
static size_t live_file_count;
static size_t io_calls;
static size_t io_fail_at;
static IoFault io_fault;
static int cases_run;

static int fail(const char *message)
{
	fprintf(stderr, "FAIL: %s\n", message);
	return 0;
}

static void track_pointer(void *pointer)
{
	if ((pointer == NULL) || (live_allocation_count >= MAX_TRACKED_ALLOCATIONS)) abort();
	live_allocations[live_allocation_count++] = pointer;
}

static void *test_allocate(size_t size)
{
	void *pointer;
	allocation_calls++;
	if ((allocation_fail_at != 0) && (allocation_calls == allocation_fail_at)) return NULL;
	pointer = malloc(size);
	track_pointer(pointer);
	return pointer;
}

static void *test_allocate_zeroed(size_t count, size_t size)
{
	void *pointer;
	allocation_calls++;
	if ((allocation_fail_at != 0) && (allocation_calls == allocation_fail_at)) return NULL;
	pointer = calloc(count, size);
	track_pointer(pointer);
	return pointer;
}

static void test_deallocate(void *pointer)
{
	size_t index;
	if (pointer == NULL) return;
	for (index = 0; index < live_allocation_count; index++)
	{
		if (live_allocations[index] == pointer)
		{
			live_allocations[index] = live_allocations[--live_allocation_count];
			free(pointer);
			return;
		}
	}
	abort();
}

static int inject(IoFault operation)
{
	if (io_fault != operation) return 0;
	io_calls++;
	return (io_fail_at != 0) && (io_calls == io_fail_at);
}

static FILE *test_open_file(const char *filename, const char *mode)
{
	FILE *file = fopen(filename, mode);
	if (file != NULL) live_file_count++;
	return file;
}

static size_t test_read(void *buffer, size_t size, size_t count, FILE *file)
{
	if (inject(IO_FAULT_READ)) return 0;
	return fread(buffer, size, count, file);
}

static size_t test_write(const void *buffer, size_t size, size_t count, FILE *file)
{
	if (inject(IO_FAULT_WRITE)) return 0;
	return fwrite(buffer, size, count, file);
}

static int test_seek(FILE *file, long offset, int origin)
{
	if (inject(IO_FAULT_SEEK)) return -1;
	return fseek(file, offset, origin);
}

static long test_tell(FILE *file)
{
	if (inject(IO_FAULT_TELL)) return -1;
	return ftell(file);
}

static int test_flush(FILE *file)
{
	if (inject(IO_FAULT_FLUSH)) return EOF;
	return fflush(file);
}

static int test_close(FILE *file)
{
	int result = fclose(file);
	if (live_file_count == 0) abort();
	live_file_count--;
	if (inject(IO_FAULT_CLOSE)) return EOF;
	return result;
}

static const MidiFileIoApi test_io_api = {
	test_open_file, test_read, test_write, test_seek, test_tell, test_flush, test_close
};

static const MidiFileAllocApi test_alloc_api = {
	test_allocate, test_allocate_zeroed, test_deallocate
};

static void reset_faults(void)
{
	allocation_calls = 0;
	allocation_fail_at = 0;
	io_calls = 0;
	io_fail_at = 0;
	io_fault = IO_FAULT_NONE;
	MidiFile_setTestIoApi(&test_io_api);
	MidiFile_setTestAllocApi(&test_alloc_api);
}

static int resources_are_zero(const char *context)
{
	if ((live_allocation_count != 0) || (live_file_count != 0))
	{
		fprintf(stderr, "FAIL: %s leaked %zu allocations and %zu files\n",
			context, live_allocation_count, live_file_count);
		return 0;
	}
	return 1;
}

static int write_fixture(const char *path, const unsigned char *data, size_t size)
{
	FILE *file = fopen(path, "wb");
	if (file == NULL) return 0;
	if (fwrite(data, 1, size, file) != size)
	{
		fclose(file);
		return 0;
	}
	return fclose(file) == 0;
}

static size_t make_smf(unsigned char *output, size_t capacity,
	const unsigned char *track_data, size_t track_size)
{
	static const unsigned char header[] = {
		'M', 'T', 'h', 'd', 0, 0, 0, 6, 0, 0, 0, 1, 0, 96,
		'M', 'T', 'r', 'k'
	};
	if ((capacity < 22) || (track_size > capacity - 22) || (track_size > UINT32_MAX)) abort();
	memcpy(output, header, sizeof(header));
	output[18] = (unsigned char)(track_size >> 24);
	output[19] = (unsigned char)(track_size >> 16);
	output[20] = (unsigned char)(track_size >> 8);
	output[21] = (unsigned char)track_size;
	memcpy(output + 22, track_data, track_size);
	return 22 + track_size;
}

static int expect_rejected_bytes(const char *name, const unsigned char *data, size_t size)
{
	const char *path = "midifile-fault-input.mid";
	MidiFile_t midi_file;
	MidiFileParserCounters counters;

	reset_faults();
	if (!write_fixture(path, data, size)) return fail("could not create malformed fixture");
	midi_file = MidiFile_load((char *)path);
	remove(path);
	if (midi_file != NULL)
	{
		MidiFile_free(midi_file);
		fprintf(stderr, "FAIL: malformed fixture accepted: %s\n", name);
		return 0;
	}
	counters = MidiFile_getTestParserCounters();
	if ((counters.bytes_read > size) || (counters.vlq_bytes_read > 4))
	{
		fprintf(stderr, "FAIL: parser counters exceeded bounds for %s\n", name);
		return 0;
	}
	cases_run++;
	return resources_are_zero(name);
}

static int expect_accepted_bytes(const char *name, const unsigned char *data, size_t size)
{
	const char *path = "midifile-valid-input.mid";
	MidiFile_t midi_file;
	reset_faults();
	if (!write_fixture(path, data, size)) return fail("could not create valid fixture");
	midi_file = MidiFile_load((char *)path);
	remove(path);
	if (midi_file == NULL)
	{
		fprintf(stderr, "FAIL: valid fixture rejected: %s\n", name);
		return 0;
	}
	MidiFile_free(midi_file);
	cases_run++;
	return resources_are_zero(name);
}

static int expect_truncated_payloads(const char *name, const unsigned char *payload,
	size_t payload_size, size_t first_cut)
{
	unsigned char fixture[128];
	size_t cut;
	for (cut = first_cut; cut < payload_size; cut++)
	{
		char case_name[96];
		size_t fixture_size = make_smf(fixture, sizeof(fixture), payload, cut);
		snprintf(case_name, sizeof(case_name), "%s at byte %zu", name, cut);
		if (!expect_rejected_bytes(case_name, fixture, fixture_size)) return 0;
	}
	return 1;
}

static int event_equal(MidiFileEvent_t left, MidiFileEvent_t right)
{
	if ((MidiFileEvent_getTick(left) != MidiFileEvent_getTick(right)) ||
		(MidiFileEvent_getType(left) != MidiFileEvent_getType(right))) return 0;
	switch (MidiFileEvent_getType(left))
	{
		case MIDI_FILE_EVENT_TYPE_NOTE_OFF:
			return (MidiFileNoteOffEvent_getChannel(left) == MidiFileNoteOffEvent_getChannel(right)) &&
				(MidiFileNoteOffEvent_getNote(left) == MidiFileNoteOffEvent_getNote(right)) &&
				(MidiFileNoteOffEvent_getVelocity(left) == MidiFileNoteOffEvent_getVelocity(right));
		case MIDI_FILE_EVENT_TYPE_NOTE_ON:
			return (MidiFileNoteOnEvent_getChannel(left) == MidiFileNoteOnEvent_getChannel(right)) &&
				(MidiFileNoteOnEvent_getNote(left) == MidiFileNoteOnEvent_getNote(right)) &&
				(MidiFileNoteOnEvent_getVelocity(left) == MidiFileNoteOnEvent_getVelocity(right));
		case MIDI_FILE_EVENT_TYPE_KEY_PRESSURE:
			return (MidiFileKeyPressureEvent_getChannel(left) == MidiFileKeyPressureEvent_getChannel(right)) &&
				(MidiFileKeyPressureEvent_getNote(left) == MidiFileKeyPressureEvent_getNote(right)) &&
				(MidiFileKeyPressureEvent_getAmount(left) == MidiFileKeyPressureEvent_getAmount(right));
		case MIDI_FILE_EVENT_TYPE_CONTROL_CHANGE:
			return (MidiFileControlChangeEvent_getChannel(left) == MidiFileControlChangeEvent_getChannel(right)) &&
				(MidiFileControlChangeEvent_getNumber(left) == MidiFileControlChangeEvent_getNumber(right)) &&
				(MidiFileControlChangeEvent_getValue(left) == MidiFileControlChangeEvent_getValue(right));
		case MIDI_FILE_EVENT_TYPE_PROGRAM_CHANGE:
			return (MidiFileProgramChangeEvent_getChannel(left) == MidiFileProgramChangeEvent_getChannel(right)) &&
				(MidiFileProgramChangeEvent_getNumber(left) == MidiFileProgramChangeEvent_getNumber(right));
		case MIDI_FILE_EVENT_TYPE_CHANNEL_PRESSURE:
			return (MidiFileChannelPressureEvent_getChannel(left) == MidiFileChannelPressureEvent_getChannel(right)) &&
				(MidiFileChannelPressureEvent_getAmount(left) == MidiFileChannelPressureEvent_getAmount(right));
		case MIDI_FILE_EVENT_TYPE_PITCH_WHEEL:
			return (MidiFilePitchWheelEvent_getChannel(left) == MidiFilePitchWheelEvent_getChannel(right)) &&
				(MidiFilePitchWheelEvent_getValue(left) == MidiFilePitchWheelEvent_getValue(right));
		case MIDI_FILE_EVENT_TYPE_SYSEX:
		{
			int length = MidiFileSysexEvent_getDataLength(left);
			return (length == MidiFileSysexEvent_getDataLength(right)) &&
				(memcmp(MidiFileSysexEvent_getData(left), MidiFileSysexEvent_getData(right), (size_t)length) == 0);
		}
		case MIDI_FILE_EVENT_TYPE_META:
		{
			int length = MidiFileMetaEvent_getDataLength(left);
			return (MidiFileMetaEvent_getNumber(left) == MidiFileMetaEvent_getNumber(right)) &&
				(length == MidiFileMetaEvent_getDataLength(right)) &&
				((length == 0) || (memcmp(MidiFileMetaEvent_getData(left), MidiFileMetaEvent_getData(right), (size_t)length) == 0));
		}
		default: return 0;
	}
}

static int files_equal(MidiFile_t left, MidiFile_t right, size_t *event_count)
{
	MidiFileTrack_t left_track;
	MidiFileTrack_t right_track;
	*event_count = 0;
	if ((MidiFile_getFileFormat(left) != MidiFile_getFileFormat(right)) ||
		(MidiFile_getDivisionType(left) != MidiFile_getDivisionType(right)) ||
		(MidiFile_getResolution(left) != MidiFile_getResolution(right)) ||
		(MidiFile_getNumberOfTracks(left) != MidiFile_getNumberOfTracks(right))) return 0;
	left_track = MidiFile_getFirstTrack(left);
	right_track = MidiFile_getFirstTrack(right);
	while ((left_track != NULL) && (right_track != NULL))
	{
		MidiFileEvent_t left_event = MidiFileTrack_getFirstEvent(left_track);
		MidiFileEvent_t right_event = MidiFileTrack_getFirstEvent(right_track);
		if (MidiFileTrack_getEndTick(left_track) != MidiFileTrack_getEndTick(right_track)) return 0;
		while ((left_event != NULL) && (right_event != NULL))
		{
			if (!event_equal(left_event, right_event)) return 0;
			(*event_count)++;
			left_event = MidiFileEvent_getNextEventInTrack(left_event);
			right_event = MidiFileEvent_getNextEventInTrack(right_event);
		}
		if ((left_event != NULL) || (right_event != NULL)) return 0;
		left_track = MidiFileTrack_getNextTrack(left_track);
		right_track = MidiFileTrack_getNextTrack(right_track);
	}
	return (left_track == NULL) && (right_track == NULL);
}

static int test_truncation_matrix(void)
{
	static const unsigned char complete_smf[] = {
		'M', 'T', 'h', 'd', 0, 0, 0, 6, 0, 0, 0, 1, 0, 96,
		'M', 'T', 'r', 'k', 0, 0, 0, 4, 0, 0xff, 0x2f, 0
	};
	static const unsigned char delta[] = {0x81, 0, 0xff, 0x2f, 0};
	static const unsigned char running[] = {0, 0x90, 60, 64, 0, 62, 64, 0, 0xff, 0x2f, 0};
	static const unsigned char channel[] = {0, 0x90, 60, 64, 0, 0xff, 0x2f, 0};
	static const unsigned char sysex[] = {0, 0xf0, 2, 1, 0xf7, 0, 0xff, 0x2f, 0};
	static const unsigned char meta[] = {0, 0xff, 1, 2, 'A', 'B', 0, 0xff, 0x2f, 0};
	static const unsigned char end_of_track[] = {0, 0xff, 0x2f, 0};
	unsigned char rmid[64];
	size_t riff_size;
	size_t cut;

	for (cut = 0; cut < 14; cut++)
		if (!expect_rejected_bytes("MThd truncation", complete_smf, cut)) return 0;
	for (cut = 14; cut < 22; cut++)
		if (!expect_rejected_bytes("track-header truncation", complete_smf, cut)) return 0;

	rmid[0] = 'R'; rmid[1] = 'I'; rmid[2] = 'F'; rmid[3] = 'F';
	riff_size = 12 + sizeof(complete_smf);
	rmid[4] = (unsigned char)riff_size; rmid[5] = (unsigned char)(riff_size >> 8);
	rmid[6] = (unsigned char)(riff_size >> 16); rmid[7] = (unsigned char)(riff_size >> 24);
	memcpy(rmid + 8, "RMIDdata", 8);
	rmid[16] = (unsigned char)sizeof(complete_smf); rmid[17] = 0; rmid[18] = 0; rmid[19] = 0;
	memcpy(rmid + 20, complete_smf, sizeof(complete_smf));
	for (cut = 0; cut < 20; cut++)
		if (!expect_rejected_bytes("RIFF/RMID truncation", rmid, cut)) return 0;
	if (!expect_accepted_bytes("valid RIFF/RMID", rmid, 20 + sizeof(complete_smf))) return 0;

	return expect_truncated_payloads("delta VLQ truncation", delta, ARRAY_COUNT(delta), 0) &&
		expect_truncated_payloads("running-status truncation", running, ARRAY_COUNT(running), 4) &&
		expect_truncated_payloads("channel-event truncation", channel, ARRAY_COUNT(channel), 0) &&
		expect_truncated_payloads("SysEx truncation", sysex, ARRAY_COUNT(sysex), 0) &&
		expect_truncated_payloads("meta-event truncation", meta, ARRAY_COUNT(meta), 0) &&
		expect_truncated_payloads("end-of-track truncation", end_of_track, ARRAY_COUNT(end_of_track), 0);
}

static int test_hostile_lengths(void)
{
	static const unsigned char five_byte_vlq[] = {0x81, 0x80, 0x80, 0x80, 0};
	static const unsigned char oversized_meta[] = {0, 0xff, 1, 0x7f, 0x41};
	static const unsigned char unsupported_running[] = {0, 60, 64, 0, 0xff, 0x2f, 0};
	static const unsigned char bad_eot[] = {0, 0xff, 0x2f, 1, 0};
	unsigned char fixture[128];
	size_t value;
	size_t size;

	if (midi_checked_add_size(SIZE_MAX, 1, &value) || midi_checked_add_size(1, 1, NULL) ||
		midi_checked_mul_size(SIZE_MAX, 2, &value) || midi_checked_mul_size(1, 1, NULL))
		return fail("checked size arithmetic accepted overflow or null output");
	if (!midi_checked_add_size(7, 9, &value) || (value != 16) ||
		!midi_checked_mul_size(7, 9, &value) || (value != 63)) return fail("checked size arithmetic rejected valid operands");
	cases_run += 6;

	size = make_smf(fixture, sizeof(fixture), five_byte_vlq, sizeof(five_byte_vlq));
	if (!expect_rejected_bytes("five-byte VLQ", fixture, size)) return 0;
	size = make_smf(fixture, sizeof(fixture), oversized_meta, sizeof(oversized_meta));
	if (!expect_rejected_bytes("event length beyond chunk", fixture, size)) return 0;
	size = make_smf(fixture, sizeof(fixture), unsupported_running, sizeof(unsupported_running));
	if (!expect_rejected_bytes("unsupported running status", fixture, size)) return 0;
	size = make_smf(fixture, sizeof(fixture), bad_eot, sizeof(bad_eot));
	if (!expect_rejected_bytes("nonempty end-of-track", fixture, size)) return 0;

	make_smf(fixture, sizeof(fixture), bad_eot, 0);
	fixture[18] = 0xff; fixture[19] = 0xff; fixture[20] = 0xff; fixture[21] = 0xff;
	return expect_rejected_bytes("chunk-start plus chunk-size wraparound", fixture, 22);
}

static int test_allocation_failures(void)
{
	static const unsigned char payload[] = {
		0, 0x90, 60, 64, 0, 0xf0, 2, 1, 0xf7,
		0, 0xff, 1, 2, 'A', 'B', 0, 0xff, 0x2f, 0
	};
	unsigned char fixture[128];
	const char *path = "midifile-allocation.mid";
	size_t size = make_smf(fixture, sizeof(fixture), payload, sizeof(payload));
	size_t failure;
	int reached_success = 0;

	if (!write_fixture(path, fixture, size)) return fail("could not create allocation fixture");
	for (failure = 1; failure < 32; failure++)
	{
		MidiFile_t file;
		reset_faults();
		allocation_fail_at = failure;
		file = MidiFile_load((char *)path);
		if (file != NULL)
		{
			MidiFile_free(file);
			reached_success = 1;
			cases_run++;
			if (!resources_are_zero("allocation success boundary")) return 0;
			break;
		}
		cases_run++;
		if (!resources_are_zero("allocation failure rollback")) return 0;
	}
	remove(path);
	return reached_success || fail("allocation failure sweep never reached success");
}

static int test_load_io_failure(IoFault fault, const char *name)
{
	static const unsigned char fixture[] = {
		'M', 'T', 'h', 'd', 0, 0, 0, 6, 0, 0, 0, 1, 0, 96,
		'M', 'T', 'r', 'k', 0, 0, 0, 8, 0, 0x90, 60, 64, 0, 0xff, 0x2f, 0
	};
	const char *path = "midifile-io-load.mid";
	size_t failure;
	int reached_success = 0;

	if (!write_fixture(path, fixture, sizeof(fixture))) return fail("could not create I/O fixture");
	for (failure = 1; failure < 64; failure++)
	{
		MidiFile_t file;
		reset_faults();
		io_fault = fault;
		io_fail_at = failure;
		file = MidiFile_load((char *)path);
		if (file != NULL)
		{
			MidiFile_free(file);
			reached_success = 1;
			cases_run++;
			if (!resources_are_zero(name)) return 0;
			break;
		}
		cases_run++;
		if (!resources_are_zero(name)) return 0;
		if (fault == IO_FAULT_CLOSE) break;
	}
	remove(path);
	return ((fault == IO_FAULT_CLOSE) || reached_success) || fail("load I/O sweep never reached success");
}

static MidiFile_t make_save_fixture(void)
{
	static unsigned char meta_data[] = {'A', 'B'};
	MidiFile_t file = MidiFile_new(0, MIDI_FILE_DIVISION_TYPE_PPQ, 96);
	MidiFileTrack_t track;
	if (file == NULL) return NULL;
	track = MidiFile_createTrack(file);
	if ((track == NULL) || (MidiFileTrack_createNoteOnEvent(track, 0, 0, 60, 64) == NULL) ||
		(MidiFileTrack_createMetaEvent(track, 5, 1, 2, meta_data) == NULL) ||
		(MidiFileTrack_setEndTick(track, 10) != 0))
	{
		MidiFile_free(file);
		return NULL;
	}
	return file;
}

static int test_save_io_failure(IoFault fault, const char *name)
{
	const char *path = "midifile-io-save.mid";
	size_t failure;
	int reached_success = 0;

	for (failure = 1; failure < 128; failure++)
	{
		MidiFile_t file;
		int result;
		reset_faults();
		file = make_save_fixture();
		if (file == NULL) return fail("could not create save fixture");
		io_fault = fault;
		io_fail_at = failure;
		io_calls = 0;
		result = MidiFile_save(file, path);
		MidiFile_free(file);
		remove(path);
		if (result == 0)
		{
			reached_success = 1;
			cases_run++;
			if (!resources_are_zero(name)) return 0;
			break;
		}
		cases_run++;
		if (!resources_are_zero(name)) return 0;
		if ((fault == IO_FAULT_FLUSH) || (fault == IO_FAULT_CLOSE)) break;
	}
	return (((fault == IO_FAULT_FLUSH) || (fault == IO_FAULT_CLOSE)) || reached_success) ||
		fail("save I/O sweep never reached success");
}

static int test_valid_roundtrip(const char *fixture_path, size_t *valid_event_count)
{
	const char *output_path = "midifile-roundtrip.mid";
	MidiFile_t original;
	MidiFile_t roundtrip;
	int equal;

	MidiFile_resetTestApis();
	original = MidiFile_load((char *)fixture_path);
	if (original == NULL) return fail("valid 1632-event fixture did not load");
	if (MidiFile_save(original, output_path) != 0)
	{
		MidiFile_free(original);
		return fail("valid fixture did not save");
	}
	roundtrip = MidiFile_load((char *)output_path);
	remove(output_path);
	if (roundtrip == NULL)
	{
		MidiFile_free(original);
		return fail("saved fixture did not reload");
	}
	equal = files_equal(original, roundtrip, valid_event_count);
	MidiFile_free(roundtrip);
	MidiFile_free(original);
	cases_run++;
	if (!equal) return fail("valid fixture changed across round trip");
	if (*valid_event_count != 1632) return fail("valid fixture did not contain 1632 events");
	return resources_are_zero("valid round trip");
}

int main(int argc, char **argv)
{
	size_t valid_event_count = 0;
	if (argc != 2)
	{
		fail("expected path to the valid MIDI fixture");
		return 2;
	}
	if (!test_truncation_matrix() || !test_hostile_lengths() || !test_allocation_failures() ||
		!test_load_io_failure(IO_FAULT_READ, "short read") ||
		!test_load_io_failure(IO_FAULT_SEEK, "failed load seek") ||
		!test_load_io_failure(IO_FAULT_TELL, "failed load tell") ||
		!test_load_io_failure(IO_FAULT_CLOSE, "failed load close") ||
		!test_save_io_failure(IO_FAULT_WRITE, "short write") ||
		!test_save_io_failure(IO_FAULT_SEEK, "failed save seek") ||
		!test_save_io_failure(IO_FAULT_TELL, "failed save tell") ||
		!test_save_io_failure(IO_FAULT_FLUSH, "failed save flush") ||
		!test_save_io_failure(IO_FAULT_CLOSE, "failed save close") ||
		!test_valid_roundtrip(argv[1], &valid_event_count)) return 1;
	MidiFile_resetTestApis();
	printf("PASS: %d midifile fault cases; %zu valid events round-tripped\n", cases_run, valid_event_count);
	return 0;
}
