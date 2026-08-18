#define PURE_FASTCGI_CODEC_TEST
#include "protocol_harness.c"

#include <stdio.h>
#include <string.h>

#define CHECK(expression)                                                      \
  do {                                                                         \
    if (!(expression)) {                                                       \
      fprintf(stderr, "%s:%d: check failed: %s\n", __FILE__, __LINE__,       \
              #expression);                                                    \
      return 1;                                                                \
    }                                                                          \
  } while (0)

static int test_begin_request_header(void) {
  unsigned char out[16] = {0};
  const unsigned char content[8] = {0, 1, 0, 0, 0, 0, 0, 0};
  const unsigned char expected[16] = {
      1, FCGI_BEGIN_REQUEST, 0, 7, 0, 8, 0, 0,
      0, 1,                  0, 0, 0, 0, 0, 0};
  size_t used = fcgi_encode_record(out, sizeof out, 1, FCGI_BEGIN_REQUEST, 7,
                                   content, sizeof content);

  CHECK(used == sizeof expected);
  CHECK(memcmp(out, expected, sizeof expected) == 0);
  return 0;
}

static int test_record_padding_is_zero_and_aligned(void) {
  unsigned char out[16];
  const unsigned char expected[16] = {
      1, FCGI_STDIN, 0, 1, 0, 1, 7, 0,
      'x', 0,          0, 0, 0, 0, 0, 0};
  memset(out, 0xa5, sizeof out);

  CHECK(fcgi_encode_record(out, sizeof out, 1, FCGI_STDIN, 1, "x", 1) ==
        sizeof expected);
  CHECK(memcmp(out, expected, sizeof expected) == 0);
  CHECK(fcgi_encode_record(out, sizeof out - 1, 1, FCGI_STDIN, 1, "x", 1) ==
        0);
  return 0;
}

static int test_name_value_uses_one_byte_lengths(void) {
  unsigned char out[8] = {0};
  const unsigned char expected[] = {3, 2, 'F', 'O', 'O', 'o', 'k'};

  CHECK(fcgi_write_name_value(out, sizeof out, "FOO", 3, "ok", 2) ==
        sizeof expected);
  CHECK(memcmp(out, expected, sizeof expected) == 0);
  return 0;
}

static int test_name_value_uses_four_byte_lengths(void) {
  unsigned char name[128];
  unsigned char out[137];
  unsigned char expected[137];
  memset(name, 'n', sizeof name);
  memset(expected, 'n', sizeof expected);
  expected[0] = 0x80;
  expected[1] = 0;
  expected[2] = 0;
  expected[3] = 128;
  expected[4] = 1;
  expected[5] = 'n';
  expected[133] = 'v';

  CHECK(fcgi_write_name_value(out, sizeof out, name, sizeof name, "v", 1) ==
        134);
  CHECK(memcmp(out, expected, 134) == 0);
  CHECK(fcgi_write_name_value(out, 133, name, sizeof name, "v", 1) == 0);
  return 0;
}

static int test_decode_rejects_wrong_version_or_request_id(void) {
  const unsigned char wrong_version[8] = {2, FCGI_STDOUT, 0, 1, 0, 0, 0, 0};
  const unsigned char wrong_request[8] = {1, FCGI_STDOUT, 0, 2, 0, 0, 0, 0};
  struct fcgi_record record;

  CHECK(fcgi_decode_record(wrong_version, sizeof wrong_version, 1, &record) ==
        FCGI_IO_PROTOCOL);
  CHECK(fcgi_decode_record(wrong_request, sizeof wrong_request, 1, &record) ==
        FCGI_IO_PROTOCOL);
  return 0;
}

static int test_encode_rejects_wrong_version(void) {
  unsigned char out[8] = {0};

  CHECK(fcgi_encode_record(out, sizeof out, 2, FCGI_STDOUT, 1, NULL, 0) == 0);
  return 0;
}

static int test_decode_rejects_truncated_content_or_padding(void) {
  const unsigned char short_content[8] = {1, FCGI_STDOUT, 0, 1, 0, 1, 0, 0};
  const unsigned char short_padding[9] = {
      1, FCGI_STDOUT, 0, 1, 0, 1, 7, 0, 'x'};
  struct fcgi_record record;

  CHECK(fcgi_decode_record(short_content, sizeof short_content, 1, &record) ==
        FCGI_IO_PROTOCOL);
  CHECK(fcgi_decode_record(short_padding, sizeof short_padding, 1, &record) ==
        FCGI_IO_PROTOCOL);
  return 0;
}

static int test_records_after_end_request_are_rejected(void) {
  struct fcgi_response_state state = {0};
  struct fcgi_record end_request = {
      FCGI_END_REQUEST, 1, 8, {0, 0, 0, 23, FCGI_REQUEST_COMPLETE, 0, 0, 0}};
  struct fcgi_record trailing_stdout = {FCGI_STDOUT, 1, 1, {'x'}};
  struct fcgi_record second_end_request = {
      FCGI_END_REQUEST, 1, 8, {0, 0, 0, 23, FCGI_REQUEST_COMPLETE, 0, 0, 0}};

  CHECK(fcgi_track_response_record(&state, &end_request) == FCGI_IO_OK);
  CHECK(state.terminal == 1);
  CHECK(state.end_request_count == 1);
  CHECK(fcgi_track_response_record(&state, &trailing_stdout) ==
        FCGI_IO_PROTOCOL);
  CHECK(fcgi_track_response_record(&state, &second_end_request) ==
        FCGI_IO_PROTOCOL);
  CHECK(state.trailing_record_count == 2);
  CHECK(state.end_request_count == 2);
  return 0;
}

static enum fcgi_io_result run_trailing_record_pipe_fixture(
    struct fcgi_response_state *state) {
  static volatile LONG fixture_counter;
  wchar_t pipe_name[128];
  HANDLE server = INVALID_HANDLE_VALUE;
  HANDLE client = INVALID_HANDLE_VALUE;
  unsigned char wire[32];
  const unsigned char end_content[8] = {
      0, 0, 0, 23, FCGI_REQUEST_COMPLETE, 0, 0, 0};
  size_t stdout_record_len;
  size_t end_record_len;
  DWORD written = 0;
  enum fcgi_io_result result = FCGI_IO_SYSTEM;

  if (swprintf(pipe_name, sizeof pipe_name / sizeof pipe_name[0],
               L"\\\\.\\pipe\\FastCGI\\pure-fastcgi-codec-%lu-%ld",
               GetCurrentProcessId(),
               InterlockedIncrement(&fixture_counter)) < 0) {
    goto cleanup;
  }
  server = CreateNamedPipeW(pipe_name, PIPE_ACCESS_OUTBOUND,
                            PIPE_TYPE_BYTE | PIPE_READMODE_BYTE | PIPE_WAIT, 1,
                            4096, 4096, 0, NULL);
  if (server == INVALID_HANDLE_VALUE) {
    goto cleanup;
  }
  client = CreateFileW(pipe_name, GENERIC_READ, 0, NULL, OPEN_EXISTING,
                       FILE_FLAG_OVERLAPPED, NULL);
  if (client == INVALID_HANDLE_VALUE) {
    goto cleanup;
  }
  if (!ConnectNamedPipe(server, NULL) && GetLastError() != ERROR_PIPE_CONNECTED) {
    goto cleanup;
  }
  stdout_record_len = fcgi_encode_record(
      wire, sizeof wire, FCGI_VERSION_1, FCGI_STDOUT, 1, "x", 1);
  end_record_len = fcgi_encode_record(
      wire + stdout_record_len, sizeof wire - stdout_record_len,
      FCGI_VERSION_1, FCGI_END_REQUEST, 1, end_content, sizeof end_content);
  if (stdout_record_len == 0 || end_record_len == 0 ||
      !WriteFile(server, wire, (DWORD)(stdout_record_len + end_record_len),
                 &written, NULL) ||
      written != stdout_record_len + end_record_len) {
    goto cleanup;
  }
  CloseHandle(server);
  server = INVALID_HANDLE_VALUE;
  result = fcgi_drain_after_terminal(client, state, fcgi_now_ms() + 2000);

cleanup:
  if (client != INVALID_HANDLE_VALUE) {
    CloseHandle(client);
  }
  if (server != INVALID_HANDLE_VALUE) {
    CloseHandle(server);
  }
  return result;
}

static int test_trailing_pipe_records_are_drained_and_rejected(void) {
  struct fcgi_response_state state = {1, 1, 0};

  CHECK(run_trailing_record_pipe_fixture(&state) == FCGI_IO_PROTOCOL);
  CHECK(state.trailing_record_count == 2);
  CHECK(state.end_request_count == 2);
  return 0;
}

int main(void) {
  CHECK(test_begin_request_header() == 0);
  CHECK(test_record_padding_is_zero_and_aligned() == 0);
  CHECK(test_name_value_uses_one_byte_lengths() == 0);
  CHECK(test_name_value_uses_four_byte_lengths() == 0);
  CHECK(test_decode_rejects_wrong_version_or_request_id() == 0);
  CHECK(test_encode_rejects_wrong_version() == 0);
  CHECK(test_decode_rejects_truncated_content_or_padding() == 0);
  CHECK(test_records_after_end_request_are_rejected() == 0);
  CHECK(test_trailing_pipe_records_are_drained_and_rejected() == 0);
#ifdef PURE_FASTCGI_NDEBUG_PROBE
  CHECK(0 && "codec checks must remain active under NDEBUG");
#endif
  puts("pure-fastcgi protocol codec passed");
  return 0;
}
