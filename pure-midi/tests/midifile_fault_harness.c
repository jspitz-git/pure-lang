#include "midifile.h"
#include "midifile_test_api.h"

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#ifdef _WIN32
#include <windows.h>
#else
#include <signal.h>
#include <sys/wait.h>
#include <unistd.h>
#endif

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
static int fault_fired;
static int cases_run;
static unsigned long delayed_read_ms;
static int delayed_read_fired;
static int deadline_contract;
static int deadline_violation_observed;

static double wall_time_seconds(void);

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
	if ((allocation_fail_at != 0) && (allocation_calls == allocation_fail_at))
	{
		fault_fired = 1;
		return NULL;
	}
	pointer = malloc(size);
	track_pointer(pointer);
	return pointer;
}

static void *test_allocate_zeroed(size_t count, size_t size)
{
	void *pointer;
	allocation_calls++;
	if ((allocation_fail_at != 0) && (allocation_calls == allocation_fail_at))
	{
		fault_fired = 1;
		return NULL;
	}
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
	if ((io_fail_at != 0) && (io_calls == io_fail_at))
	{
		fault_fired = 1;
		return 1;
	}
	return 0;
}

static FILE *test_open_file(const char *filename, const char *mode)
{
	FILE *file = fopen(filename, mode);
	if (file != NULL) live_file_count++;
	return file;
}

static size_t test_read(void *buffer, size_t size, size_t count, FILE *file)
{
	if ((delayed_read_ms != 0) && !delayed_read_fired)
	{
		/* Deliberately nonreturning parser seam: only a separate process can
		   enforce the malformed-case deadline. */
		if (delayed_read_ms == 2100) for (;;) {}
		double started = wall_time_seconds();
		delayed_read_fired = 1;
		if (started >= 0.0)
			while ((wall_time_seconds() - started) < ((double)delayed_read_ms / 1000.0)) {}
	}
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
	fault_fired = 0;
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

static double wall_time_seconds(void)
{
	struct timespec now;
	if (timespec_get(&now, TIME_UTC) != TIME_UTC) return -1.0;
	return (double)now.tv_sec + ((double)now.tv_nsec / 1000000000.0);
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

static int reject_fixture_child(size_t size)
{
	const char *path = "midifile-fault-input.mid";
	MidiFile_t midi_file;
	MidiFileParserCounters counters;
	reset_faults();
	midi_file = MidiFile_load((char *)path);
	if (midi_file != NULL)
	{
		MidiFile_free(midi_file);
		return fail("malformed fixture accepted by parser child");
	}
	counters = MidiFile_getTestParserCounters();
	if ((counters.bytes_read > size) || (counters.vlq_bytes_read > 4))
		return fail("parser child counters exceeded bounds");
	return resources_are_zero("malformed parser child");
}

/* A hung parser cannot prevent its parent from enforcing this deadline.
   Terminate only the disposable child process; never a parser thread. */
static int supervise_rejected_fixture(size_t size)
{
#ifdef _WIN32
	wchar_t executable[32768], command[32864];
	STARTUPINFOW startup={0};
	PROCESS_INFORMATION child={0};
	DWORD count=GetModuleFileNameW(NULL,executable,32768), status, code=1;
	if (!count || count>=32768) return fail("parser supervisor executable path");
	if (swprintf(command,32864,L"\"%ls\" --reject-child %zu %d",executable,size,deadline_contract)<0)
		return fail("parser supervisor command");
	startup.cb=sizeof(startup);
	if (!CreateProcessW(executable,command,NULL,NULL,FALSE,CREATE_NO_WINDOW,NULL,NULL,&startup,&child))
		return fail("parser supervisor launch");
	status=WaitForSingleObject(child.hProcess,2000);
	if (status!=WAIT_OBJECT_0) {
		int stopped=TerminateProcess(child.hProcess,124) && WaitForSingleObject(child.hProcess,1000)==WAIT_OBJECT_0;
		deadline_violation_observed=status==WAIT_TIMEOUT && stopped;
	} else if (!GetExitCodeProcess(child.hProcess,&code)) code=1;
	CloseHandle(child.hThread); CloseHandle(child.hProcess);
	return status==WAIT_OBJECT_0 && code==0;
#else
	pid_t child=fork();
	struct timespec started, now, pause={0,1000000};
	int status=0;
	if (child<0) return fail("parser supervisor fork");
	if (child==0) _exit(reject_fixture_child(size) ? 0 : 1);
	clock_gettime(CLOCK_MONOTONIC,&started);
	for (;;) {
		pid_t result=waitpid(child,&status,WNOHANG);
		if (result==child) return WIFEXITED(status) && WEXITSTATUS(status)==0;
		clock_gettime(CLOCK_MONOTONIC,&now);
		if (result<0 || (now.tv_sec-started.tv_sec)+(now.tv_nsec-started.tv_nsec)/1e9>=2.0) {
			kill(child,SIGKILL);
			deadline_violation_observed=result==0 && waitpid(child,&status,0)==child;
			return 0;
		}
		nanosleep(&pause,NULL);
	}
#endif
}

static int expect_rejected_bytes(const char *name, const unsigned char *data, size_t size)
{
	const char *path="midifile-fault-input.mid";
	int ok;
	reset_faults();
	if (!write_fixture(path,data,size)) return fail("could not create malformed fixture");
	ok=supervise_rejected_fixture(size);
	remove(path);
	if (!ok) {
		fprintf(deadline_contract && deadline_violation_observed ? stdout : stderr,
			"%s: %s: %s\n",deadline_contract && deadline_violation_observed ? "PASS" : "FAIL",
			deadline_violation_observed ? "malformed fixture exceeded two-second deadline" : "malformed fixture child failed",name);
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
		0, 0x80, 60, 64, 0, 0x90, 60, 64, 0, 0xa0, 60, 64,
		0, 0xb0, 1, 2, 0, 0xc0, 5, 0, 0xd0, 6, 0, 0xe0, 0, 64,
		0, 0xf0, 2, 1, 0xf7,
		0, 0xff, 1, 2, 'A', 'B', 0, 0xff, 0x2f, 0
	};
	unsigned char fixture[128];
	const char *path = "midifile-allocation.mid";
	size_t size = make_smf(fixture, sizeof(fixture), payload, sizeof(payload));
	size_t failure;
	size_t baseline_calls;
	MidiFile_t file;

	if (!write_fixture(path, fixture, size)) return fail("could not create allocation fixture");
	reset_faults();
	file = MidiFile_load((char *)path);
	if (file == NULL) return fail("allocation baseline did not load");
	baseline_calls = allocation_calls;
	MidiFile_free(file);
	if (!resources_are_zero("allocation baseline")) return 0;

	for (failure = 1; failure <= baseline_calls; failure++)
	{
		reset_faults();
		allocation_fail_at = failure;
		file = MidiFile_load((char *)path);
		if (!fault_fired)
		{
			if (file != NULL) MidiFile_free(file);
			return fail("scheduled allocation fault did not fire");
		}
		if (file != NULL)
		{
			MidiFile_free(file);
			return fail("load succeeded after injected allocation failure");
		}
		cases_run++;
		if (!resources_are_zero("allocation failure rollback")) return 0;
	}

	reset_faults();
	allocation_fail_at = baseline_calls + 1;
	file = MidiFile_load((char *)path);
	if ((file == NULL) || fault_fired) return fail("allocation terminal success boundary was not clean");
	MidiFile_free(file);
	cases_run++;
	if (!resources_are_zero("allocation terminal success boundary")) return 0;
	remove(path);
	return 1;
}

static int test_load_io_failure(IoFault fault, const char *name)
{
	static const unsigned char fixture[] = {
		'M', 'T', 'h', 'd', 0, 0, 0, 6, 0, 0, 0, 1, 0, 96,
		'M', 'T', 'r', 'k', 0, 0, 0, 8, 0, 0x90, 60, 64, 0, 0xff, 0x2f, 0
	};
	const char *path = "midifile-io-load.mid";
	size_t failure;
	size_t baseline_calls;
	MidiFile_t file;

	if (!write_fixture(path, fixture, sizeof(fixture))) return fail("could not create I/O fixture");
	reset_faults();
	io_fault = fault;
	file = MidiFile_load((char *)path);
	if (file == NULL) return fail("load I/O baseline did not load");
	baseline_calls = io_calls;
	MidiFile_free(file);
	if (!resources_are_zero("load I/O baseline")) return 0;

	for (failure = 1; failure <= baseline_calls; failure++)
	{
		reset_faults();
		io_fault = fault;
		io_fail_at = failure;
		file = MidiFile_load((char *)path);
		if (!fault_fired)
		{
			if (file != NULL) MidiFile_free(file);
			return fail("scheduled load I/O fault did not fire");
		}
		if (file != NULL)
		{
			MidiFile_free(file);
			return fail("load succeeded after injected I/O failure");
		}
		cases_run++;
		if (!resources_are_zero(name)) return 0;
	}

	reset_faults();
	io_fault = fault;
	io_fail_at = baseline_calls + 1;
	file = MidiFile_load((char *)path);
	if ((file == NULL) || fault_fired) return fail("load I/O terminal success boundary was not clean");
	MidiFile_free(file);
	cases_run++;
	if (!resources_are_zero(name)) return 0;
	remove(path);
	return 1;
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
	size_t baseline_calls;
	MidiFile_t file;
	int result;

	reset_faults();
	file = make_save_fixture();
	if (file == NULL) return fail("could not create save baseline fixture");
	io_fault = fault;
	io_calls = 0;
	result = MidiFile_save(file, path);
	baseline_calls = io_calls;
	MidiFile_free(file);
	remove(path);
	if ((result != 0) || !resources_are_zero("save I/O baseline")) return fail("save I/O baseline failed");

	for (failure = 1; failure <= baseline_calls; failure++)
	{
		reset_faults();
		file = make_save_fixture();
		if (file == NULL) return fail("could not create save fixture");
		io_fault = fault;
		io_fail_at = failure;
		io_calls = 0;
		result = MidiFile_save(file, path);
		MidiFile_free(file);
		remove(path);
		if (!fault_fired) return fail("scheduled save I/O fault did not fire");
		if (result == 0)
		{
			return fail("save succeeded after injected I/O failure");
		}
		cases_run++;
		if (!resources_are_zero(name)) return 0;
	}

	reset_faults();
	file = make_save_fixture();
	if (file == NULL) return fail("could not create terminal save fixture");
	io_fault = fault;
	io_fail_at = baseline_calls + 1;
	io_calls = 0;
	result = MidiFile_save(file, path);
	MidiFile_free(file);
	remove(path);
	if ((result != 0) || fault_fired) return fail("save I/O terminal success boundary was not clean");
	cases_run++;
	return resources_are_zero(name);
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

static int test_native_event_boundaries(void)
{
  unsigned char sysex[]={0xf0,1,0xf7}, invalid[]={0x90}, payload[]={1};
  MidiFile_t file;
  MidiFileTrack_t track;
  reset_faults();
  if (MidiFile_new(-1,MIDI_FILE_DIVISION_TYPE_PPQ,96) ||
      MidiFile_new(1,MIDI_FILE_DIVISION_TYPE_INVALID,96) ||
      MidiFile_new(1,MIDI_FILE_DIVISION_TYPE_PPQ,0) ||
      MidiFile_new(1,MIDI_FILE_DIVISION_TYPE_SMPTE25,256))
    return fail("invalid native file parameters accepted");
  file=MidiFile_new(1,MIDI_FILE_DIVISION_TYPE_PPQ,96);
  track=MidiFile_createTrack(file);
  if (!track) return fail("native boundary setup");
  if (MidiFileTrack_createSysexEvent(track,-1,3,sysex) ||
      MidiFileTrack_createSysexEvent(track,0,0,sysex) ||
      MidiFileTrack_createSysexEvent(track,0,3,NULL) ||
      MidiFileTrack_createSysexEvent(track,0,1,invalid) ||
      MidiFileTrack_createMetaEvent(track,-1,1,1,payload) ||
      MidiFileTrack_createMetaEvent(track,0,256,1,payload) ||
      MidiFileTrack_createMetaEvent(track,0,1,-1,payload) ||
      MidiFileTrack_createMetaEvent(track,0,1,1,NULL) ||
      MidiFileTrack_createMetaEvent(track,0,0x2f,1,payload) ||
      MidiFileTrack_createVoiceEvent(track,-1,0x403c90) ||
      MidiFileTrack_createVoiceEvent(track,0,0x00403c00) ||
      MidiFileTrack_createVoiceEvent(track,0,0x01403c90) ||
      MidiFile_getFirstEvent(file)) return fail("invalid native event accepted or linked");
  if (!MidiFileTrack_createMetaEvent(track,0,1,0,NULL) ||
      !MidiFileTrack_createSysexEvent(track,0,3,sysex) ||
      !MidiFileTrack_createVoiceEvent(track,0,0x403c90)) return fail("native valid control rejected");
  MidiFile_free(file);
  cases_run+=19;
  return resources_are_zero("native event boundaries");
}

static int test_save_header(void)
{
  static const unsigned char sentinel[]={ 'k','e','e','p' };
  const char *path="midifile-invalid-header.mid";
  unsigned char actual[4];
  MidiFile_t file;
  FILE *in;
  int rc, i;
  MidiFile_resetTestApis();
  file=MidiFile_new(0,MIDI_FILE_DIVISION_TYPE_PPQ,96);
  if (!file || !MidiFile_createTrack(file) || !MidiFile_createTrack(file)) return fail("header fixture");
  if (!write_fixture(path,sentinel,sizeof(sentinel))) return fail("header sentinel");
  rc=MidiFile_save(file,path);
  MidiFile_free(file);
  in=fopen(path,"rb");
  if (!in) return fail("header sentinel missing");
  i=(fread(actual,1,sizeof(actual),in)==sizeof(actual) && memcmp(actual,sentinel,sizeof(actual))==0);
  fclose(in); remove(path);
  if (rc==0 || !i) return fail("format zero with two tracks saved or truncated destination");
  file=MidiFile_new(1,MIDI_FILE_DIVISION_TYPE_PPQ,96);
  /* createTrack and free are linear overall; 65536 empty tracks use ~4 MiB. */
  for (i=0;i<65535;++i) if (!MidiFile_createTrack(file)) return fail("UINT16 track fixture");
  if (MidiFile_save(file,path)!=0) return fail("UINT16_MAX tracks rejected");
  {
    MidiFile_t loaded=MidiFile_load((char *)path);
    if (!loaded || MidiFile_getNumberOfTracks(loaded)!=65535) return fail("UINT16_MAX saved header changed");
    MidiFile_free(loaded);
  }
  if (!MidiFile_createTrack(file) || !write_fixture(path,sentinel,sizeof(sentinel))) return fail("UINT16 overflow fixture");
  rc=MidiFile_save(file,path);
  MidiFile_free(file);
  in=fopen(path,"rb");
  if (!in) return fail("overflow sentinel missing");
  i=(fread(actual,1,sizeof(actual),in)==sizeof(actual) && memcmp(actual,sentinel,sizeof(actual))==0);
  fclose(in); remove(path);
  if (rc==0 || !i) return fail("UINT16 overflow saved or truncated destination");
  cases_run+=3;
  return 1;
}

static int test_running_status_reset(void)
{
  static const unsigned char tracks[][17]={
    {0,0x90,60,64,0,0xf0,1,0xf7,0,61,64,0,0xff,0x2f,0},
    {0,0x90,60,64,0,0xf7,1,0xf7,0,61,64,0,0xff,0x2f,0},
    {0,0x90,60,64,0,0xff,1,1,65,0,61,64,0,0xff,0x2f,0},
    {0,0x90,60,64,0,61,64,0,0xff,0x2f,0}
  };
  static const size_t lengths[]={15,15,16,11};
  unsigned char fixture[64];
  size_t i;
  int ok=1;
  for (i=0;i<3;++i) {
    size_t size=make_smf(fixture,sizeof(fixture),tracks[i],lengths[i]);
    if (!expect_rejected_bytes(i==0 ? "running after F0" : i==1 ? "running after F7" : "running after FF",fixture,size)) ok=0;
  }
  if (!expect_accepted_bytes("consecutive channel running status",fixture,
      make_smf(fixture,sizeof(fixture),tracks[3],lengths[3]))) ok=0;
  return ok;
}

static int test_native_seven_bit(void)
{
  const char *path="midifile-invalid-event.mid";
  MidiFile_t file=MidiFile_new(1,MIDI_FILE_DIVISION_TYPE_PPQ,96);
  MidiFileTrack_t track=MidiFile_createTrack(file);
  MidiFileEvent_t event;
  if (!track) return fail("native seven-bit setup");
  event=MidiFileTrack_createNoteOnEvent(track,0,0,128,64);
  if (!event || MidiFile_save(file,path)==0) return fail("serializer silently masked invalid channel data");
  MidiFileEvent_delete(event);
  event=MidiFileTrack_createMetaEvent(track,0,1,0,NULL);
  MidiFileMetaEvent_setNumber(event,128);
  if (MidiFile_save(file,path)==0) return fail("serializer accepted invalid meta type");
  MidiFileEvent_delete(event);
  if (MidiFileTrack_createVoiceEvent(track,0,0x408090) ||
      MidiFileTrack_createMetaEvent(track,0,128,0,NULL)) return fail("native constructor accepted seven-bit overflow");
  MidiFile_free(file); remove(path); cases_run+=4;
  return 1;
}

int main(int argc, char **argv)
{
	size_t valid_event_count = 0;
	if (argc==4 && strcmp(argv[1],"--reject-child")==0) {
		delayed_read_ms=strcmp(argv[3],"1")==0 ? 2100 : 0;
		return reject_fixture_child((size_t)strtoull(argv[2],NULL,10)) ? 0 : 1;
	}
	if (argc==3 && strcmp(argv[2],"--header")==0) return test_save_header() ? 0 : 1;
	if (argc==3 && strcmp(argv[2],"--running")==0) return test_running_status_reset() ? 0 : 1;
	if (argc==3 && strcmp(argv[2],"--seven-bit")==0) return test_native_seven_bit() ? 0 : 1;
	if ((argc != 2) && !((argc == 3) && (strcmp(argv[2], "--deadline-contract") == 0)))
	{
		fail("expected fixture path and optional --deadline-contract");
		return 2;
	}
	if (argc == 3)
	{
		deadline_contract = 1;
		delayed_read_ms = 2100;
		if (test_truncation_matrix() || !deadline_violation_observed)
		{
			fail("deadline contract did not observe an over-budget malformed fixture");
			return 1;
		}
		return 0;
	}
	if (!test_save_header() || !test_native_seven_bit() || !test_running_status_reset() ||
		!test_native_event_boundaries() || !test_truncation_matrix() || !test_hostile_lengths() || !test_allocation_failures() ||
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
