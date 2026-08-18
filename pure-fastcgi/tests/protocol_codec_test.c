#define PURE_FASTCGI_CODEC_TEST
#include "protocol_harness.c"

#include <assert.h>
#include <stdio.h>
#include <string.h>

static void test_begin_request_header(void) {
  unsigned char out[16] = {0};
  const unsigned char content[8] = {0, 1, 0, 0, 0, 0, 0, 0};
  const unsigned char expected[16] = {
      1, FCGI_BEGIN_REQUEST, 0, 7, 0, 8, 0, 0,
      0, 1,                  0, 0, 0, 0, 0, 0};
  size_t used = fcgi_encode_record(out, sizeof out, 1, FCGI_BEGIN_REQUEST, 7,
                                   content, sizeof content);

  assert(used == sizeof expected);
  assert(memcmp(out, expected, sizeof expected) == 0);
}

static void test_record_padding_is_zero_and_aligned(void) {
  unsigned char out[16];
  const unsigned char expected[16] = {
      1, FCGI_STDIN, 0, 1, 0, 1, 7, 0,
      'x', 0,          0, 0, 0, 0, 0, 0};
  memset(out, 0xa5, sizeof out);

  assert(fcgi_encode_record(out, sizeof out, 1, FCGI_STDIN, 1, "x", 1) ==
         sizeof expected);
  assert(memcmp(out, expected, sizeof expected) == 0);
  assert(fcgi_encode_record(out, sizeof out - 1, 1, FCGI_STDIN, 1, "x", 1) ==
         0);
}

static void test_name_value_uses_one_byte_lengths(void) {
  unsigned char out[8] = {0};
  const unsigned char expected[] = {3, 2, 'F', 'O', 'O', 'o', 'k'};

  assert(fcgi_write_name_value(out, sizeof out, "FOO", 3, "ok", 2) ==
         sizeof expected);
  assert(memcmp(out, expected, sizeof expected) == 0);
}

static void test_name_value_uses_four_byte_lengths(void) {
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

  assert(fcgi_write_name_value(out, sizeof out, name, sizeof name, "v", 1) ==
         134);
  assert(memcmp(out, expected, 134) == 0);
  assert(fcgi_write_name_value(out, 133, name, sizeof name, "v", 1) == 0);
}

static void test_decode_rejects_wrong_version_or_request_id(void) {
  const unsigned char wrong_version[8] = {2, FCGI_STDOUT, 0, 1, 0, 0, 0, 0};
  const unsigned char wrong_request[8] = {1, FCGI_STDOUT, 0, 2, 0, 0, 0, 0};
  struct fcgi_record record;

  assert(fcgi_decode_record(wrong_version, sizeof wrong_version, 1, &record) ==
         FCGI_IO_PROTOCOL);
  assert(fcgi_decode_record(wrong_request, sizeof wrong_request, 1, &record) ==
         FCGI_IO_PROTOCOL);
}

static void test_encode_rejects_wrong_version(void) {
  unsigned char out[8] = {0};

  assert(fcgi_encode_record(out, sizeof out, 2, FCGI_STDOUT, 1, NULL, 0) ==
         0);
}

static void test_decode_rejects_truncated_content_or_padding(void) {
  const unsigned char short_content[8] = {1, FCGI_STDOUT, 0, 1, 0, 1, 0, 0};
  const unsigned char short_padding[9] = {
      1, FCGI_STDOUT, 0, 1, 0, 1, 7, 0, 'x'};
  struct fcgi_record record;

  assert(fcgi_decode_record(short_content, sizeof short_content, 1, &record) ==
         FCGI_IO_PROTOCOL);
  assert(fcgi_decode_record(short_padding, sizeof short_padding, 1, &record) ==
         FCGI_IO_PROTOCOL);
}

int main(void) {
  test_begin_request_header();
  test_record_padding_is_zero_and_aligned();
  test_name_value_uses_one_byte_lengths();
  test_name_value_uses_four_byte_lengths();
  test_decode_rejects_wrong_version_or_request_id();
  test_encode_rejects_wrong_version();
  test_decode_rejects_truncated_content_or_padding();
  puts("pure-fastcgi protocol codec passed");
  return 0;
}
