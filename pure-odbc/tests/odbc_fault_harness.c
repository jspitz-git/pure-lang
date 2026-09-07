#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <windows.h>
#include <sql.h>
#include <sqlext.h>
#include <gmp.h>
#include <pure/runtime.h>

enum fault_mode {
  FAULT_GETDATA,
  INFO_LONG_TEXT,
  INFO_NEGATIVE_LENGTH,
  INFO_NO_TOTAL,
  INFO_RETRY_FAILURE,
  INFO_USMALLINT,
  INFO_UINTEGER,
  INFO_XOPEN_TEXT,
  INFO_YN_TEXT,
  INFO_HSTMT,
  INFO_HDESC
};

enum binary_mode {
  BINARY_DEFAULT,
  BINARY_SHORT_INFO,
  BINARY_MULTI_CHUNK,
  BINARY_NO_TOTAL,
  BINARY_INFO_THEN_NO_DATA
};

static enum fault_mode mode;
static SQLRETURN getdata_return;
static int getdata_calls;
static int getdata_null_result;
static int getdata_info_then_no_data;
static enum binary_mode binary_read_mode;
static int getinfo_calls;
static SQLUSMALLINT expected_info_type;
static SQLSMALLINT expected_info_buffer_length;
static SQLHANDLE expected_info_input;
static bool check_info_input;
static bool getinfo_request_ok;
static int fail_next_allocation;
static size_t allocation_count;
static void *allocations[32];

static void *fault_malloc(size_t size)
{
  void *ptr;
  size_t i;

  if (fail_next_allocation) {
    fail_next_allocation = 0;
    return NULL;
  }
  ptr = malloc(size);
  if (!ptr)
    return NULL;
  for (i = 0; i < sizeof(allocations) / sizeof(allocations[0]); ++i) {
    if (!allocations[i]) {
      allocations[i] = ptr;
      ++allocation_count;
      return ptr;
    }
  }
  free(ptr);
  return NULL;
}

static void *fault_realloc(void *ptr, size_t size)
{
  void *new_ptr;
  size_t i;

  if (!ptr)
    return fault_malloc(size);
  if (fail_next_allocation) {
    fail_next_allocation = 0;
    return NULL;
  }
  new_ptr = realloc(ptr, size);
  if (!new_ptr)
    return NULL;
  for (i = 0; i < sizeof(allocations) / sizeof(allocations[0]); ++i) {
    if (allocations[i] == ptr) {
      allocations[i] = new_ptr;
      return new_ptr;
    }
  }
  fprintf(stderr, "untracked realloc\n");
  abort();
}

static void fault_free(void *ptr)
{
  size_t i;

  if (!ptr)
    return;
  for (i = 0; i < sizeof(allocations) / sizeof(allocations[0]); ++i) {
    if (allocations[i] == ptr) {
      allocations[i] = NULL;
      --allocation_count;
      free(ptr);
      return;
    }
  }
  fprintf(stderr, "untracked free\n");
  abort();
}

static bool fault_forget(void *ptr)
{
  size_t i;

  if (!ptr)
    return false;
  for (i = 0; i < sizeof(allocations) / sizeof(allocations[0]); ++i) {
    if (allocations[i] == ptr) {
      allocations[i] = NULL;
      --allocation_count;
      return true;
    }
  }
  return false;
}

static SQLRETURN SQL_API fake_SQLFetch(SQLHSTMT statement)
{
  (void)statement;
  return SQL_SUCCESS;
}

static void fill_binary(SQLPOINTER target, SQLLEN length, unsigned char seed)
{
  SQLLEN i;

  for (i = 0; i < length; ++i)
    ((unsigned char *)target)[i] = (unsigned char)(seed + (unsigned char)i);
}

static SQLRETURN fake_binary_getdata(SQLPOINTER target, SQLLEN buffer_length,
                                     SQLLEN *length)
{
  static const unsigned char short_value[] = {0xde, 0xad, 0xbe, 0xef};
  static const unsigned char tail[] = {0xfa, 0xce, 0xb0, 0x0c};

  switch (binary_read_mode) {
  case BINARY_SHORT_INFO:
    if (getdata_calls != 1)
      return SQL_ERROR;
    memcpy(target, short_value, sizeof(short_value));
    *length = sizeof(short_value);
    return SQL_SUCCESS_WITH_INFO;
  case BINARY_MULTI_CHUNK:
    if (getdata_calls == 1) {
      fill_binary(target, buffer_length, 0x10);
      *length = buffer_length;
      return SQL_SUCCESS_WITH_INFO;
    }
    if (getdata_calls == 2) {
      memcpy(target, tail, sizeof(tail));
      *length = sizeof(tail);
      return SQL_SUCCESS;
    }
    return SQL_ERROR;
  case BINARY_NO_TOTAL:
    if (getdata_calls == 1) {
      fill_binary(target, buffer_length, 0x40);
      *length = SQL_NO_TOTAL;
      return SQL_SUCCESS_WITH_INFO;
    }
    if (getdata_calls == 2) {
      memcpy(target, tail, sizeof(tail));
      *length = sizeof(tail);
      return SQL_SUCCESS;
    }
    return SQL_ERROR;
  case BINARY_INFO_THEN_NO_DATA:
    if (getdata_calls == 1) {
      fill_binary(target, buffer_length, 0x80);
      *length = SQL_NO_TOTAL;
      return SQL_SUCCESS_WITH_INFO;
    }
    if (getdata_calls == 2) {
      *length = SQL_NULL_DATA;
      return SQL_NO_DATA;
    }
    return SQL_ERROR;
  default:
    return SQL_ERROR;
  }
}

static SQLRETURN SQL_API fake_SQLGetData(SQLHSTMT statement,
                                         SQLUSMALLINT column,
                                         SQLSMALLINT target_type,
                                         SQLPOINTER target,
                                         SQLLEN buffer_length,
                                         SQLLEN *length)
{
  static const unsigned char binary_value[] = {0x10, 0x20, 0x30, 0x40};
  const char *text_value = "fault-poison";

  (void)statement;
  (void)column;
  ++getdata_calls;
  if (getdata_info_then_no_data && getdata_calls == 2) {
    *length = SQL_NULL_DATA;
    return SQL_NO_DATA;
  }
  if (getdata_null_result) {
    *length = SQL_NULL_DATA;
    return getdata_return;
  }
  if (target_type == SQL_BINARY && binary_read_mode != BINARY_DEFAULT)
    return fake_binary_getdata(target, buffer_length, length);
  if (target_type == SQL_INTEGER) {
    *(long *)target = INT32_C(0x12345678);
    *length = sizeof(long);
  } else if (target_type == SQL_DOUBLE) {
    *(double *)target = 12345.5;
    *length = sizeof(double);
  } else if (target_type == SQL_BINARY) {
    size_t count = sizeof(binary_value);
    if ((SQLLEN)count > buffer_length)
      count = (size_t)buffer_length;
    memcpy(target, binary_value, count);
    *length = (SQLLEN)count;
  } else {
    size_t count = strlen(text_value) + 1;
    if ((SQLLEN)count > buffer_length)
      count = (size_t)buffer_length;
    memcpy(target, text_value, count);
    if (count)
      ((char *)target)[count - 1] = 0;
    *length = (SQLLEN)(count - 1);
  }
  return getdata_return;
}

static SQLRETURN SQL_API fake_SQLGetInfo(SQLHDBC connection,
                                         SQLUSMALLINT info_type,
                                         SQLPOINTER value,
                                         SQLSMALLINT buffer_length,
                                         SQLSMALLINT *length)
{
  size_t i;

  (void)connection;
  ++getinfo_calls;
  if (mode == INFO_USMALLINT) {
    SQLUSMALLINT numeric_value = 31;
    getinfo_request_ok = info_type == expected_info_type &&
      buffer_length == expected_info_buffer_length;
    memcpy(value, &numeric_value, sizeof(numeric_value));
    *length = sizeof(SQLUSMALLINT);
    return SQL_SUCCESS;
  }
  if (mode == INFO_UINTEGER) {
    SQLUINTEGER numeric_value = UINT32_C(0x87654321);
    getinfo_request_ok = info_type == expected_info_type &&
      buffer_length == expected_info_buffer_length;
    memcpy(value, &numeric_value, sizeof(numeric_value));
    *length = sizeof(numeric_value);
    return SQL_SUCCESS;
  }
  if (mode == INFO_XOPEN_TEXT) {
    static const char xopen_year[] = "1992";
    getinfo_request_ok = info_type == expected_info_type &&
      buffer_length == expected_info_buffer_length;
    memcpy(value, xopen_year, sizeof(xopen_year));
    *length = sizeof(xopen_year) - 1;
    return SQL_SUCCESS;
  }
  if (mode == INFO_YN_TEXT) {
    static const char yn_value[] = "Y";
    getinfo_request_ok = info_type == expected_info_type &&
      buffer_length == expected_info_buffer_length;
    memcpy(value, yn_value, sizeof(yn_value));
    *length = sizeof(yn_value) - 1;
    return SQL_SUCCESS;
  }
  if (mode == INFO_HSTMT) {
    SQLHANDLE statement_value = expected_info_input;
    getinfo_request_ok = info_type == expected_info_type &&
      buffer_length == expected_info_buffer_length &&
      (!check_info_input || *(SQLHANDLE *)value == expected_info_input);
    memcpy(value, &statement_value, sizeof(statement_value));
    *length = sizeof(statement_value);
    return SQL_SUCCESS;
  }
  if (mode == INFO_HDESC) {
    getinfo_request_ok = false;
    return SQL_ERROR;
  }
  if (mode == INFO_NEGATIVE_LENGTH) {
    if (value && buffer_length > 0)
      ((char *)value)[0] = 0;
    *length = -2;
    return SQL_SUCCESS_WITH_INFO;
  }
  if (mode == INFO_NO_TOTAL) {
    if (value && buffer_length > 0)
      ((char *)value)[0] = 0;
    *length = SQL_NO_TOTAL;
    return SQL_SUCCESS_WITH_INFO;
  }
  if (getinfo_calls == 1) {
    for (i = 0; value && i + 1 < (size_t)buffer_length; ++i)
      ((char *)value)[i] = (char)('A' + i % 26);
    if (value && buffer_length > 0)
      ((char *)value)[buffer_length - 1] = 0;
    *length = 2048;
    return SQL_SUCCESS_WITH_INFO;
  }
  if (mode == INFO_RETRY_FAILURE) {
    memset(value, 0xa5, (size_t)buffer_length);
    *length = 2048;
    return SQL_ERROR;
  }
  for (i = 0; i < 2048; ++i)
    ((char *)value)[i] = (char)('A' + i % 26);
  ((char *)value)[2048] = 0;
  *length = 2048;
  return SQL_SUCCESS;
}

static SQLRETURN SQL_API fake_SQLGetDiagRec(SQLSMALLINT handle_type,
                                            SQLHANDLE handle,
                                            SQLSMALLINT record,
                                            SQLCHAR *state,
                                            SQLINTEGER *native_error,
                                            SQLCHAR *message,
                                            SQLSMALLINT buffer_length,
                                            SQLSMALLINT *text_length)
{
  static const char state_value[] = "HY000";
  static const char message_value[] = "injected fault";

  (void)handle_type;
  (void)handle;
  (void)record;
  memcpy(state, state_value, sizeof(state_value));
  *native_error = 1;
  if (buffer_length > 0) {
    size_t count = sizeof(message_value);
    if (count > (size_t)buffer_length)
      count = (size_t)buffer_length;
    memcpy(message, message_value, count);
    message[count - 1] = 0;
  }
  *text_length = (SQLSMALLINT)strlen(message_value);
  return SQL_SUCCESS;
}

#define malloc fault_malloc
#define realloc fault_realloc
#define free fault_free
#include "../odbc.c"
#undef free
#undef realloc
#undef malloc

static int failures;

static void check(bool condition, const char *name)
{
  if (condition)
    printf("PASS: %s\n", name);
  else {
    printf("FAIL: %s\n", name);
    ++failures;
  }
  fflush(stdout);
}

static bool is_singleton_list(pure_expr *value)
{
  pure_expr **items = NULL;
  size_t count = 0;
  bool result = value && pure_is_listv(value, &count, &items) && count == 1;

  free(items);
  return result;
}

static bool is_singleton_sqlnull_list(pure_expr *value)
{
  pure_expr **items = NULL;
  size_t count = 0;
  int32_t symbol = 0;
  bool result = value && pure_is_listv(value, &count, &items) && count == 1 &&
    pure_is_symbol(items[0], &symbol) && symbol == pure_sym("odbc::SQLNULL");

  free(items);
  return result;
}

static bool release_binary_result(pure_expr *value)
{
  pure_expr **list_items = NULL;
  pure_expr **tuple_items = NULL;
  void *pointer = NULL;
  size_t list_count = 0;
  size_t tuple_count = 0;
  bool released = false;

  if (value && pure_is_listv(value, &list_count, &list_items) &&
      list_count == 1 && pure_is_tuplev(list_items[0], &tuple_count,
                                        &tuple_items) &&
      tuple_count == 2 && pure_is_pointer(tuple_items[1], &pointer)) {
    released = fault_forget(pointer);
  }
  free(tuple_items);
  free(list_items);
  return released;
}

static void release_pure_result(pure_expr *value)
{
  void *pointer = NULL;

  if (value && pure_is_pointer(value, &pointer))
    check(fault_forget(pointer), "Pure sentry transfers a tracked allocation");
  if (value)
    pure_freenew(value);
}

static bool binary_result(pure_expr *value, int64_t *length,
                          const unsigned char **bytes)
{
  pure_expr **list_items = NULL;
  pure_expr **tuple_items = NULL;
  void *pointer = NULL;
  size_t list_count = 0;
  size_t tuple_count = 0;
  bool result = false;

  if (value && pure_is_listv(value, &list_count, &list_items) &&
      list_count == 1 && pure_is_tuplev(list_items[0], &tuple_count,
                                        &tuple_items) && tuple_count == 2 &&
      pure_is_pointer(tuple_items[1], &pointer)) {
    *length = pure_get_int64(tuple_items[0]);
    *bytes = pointer;
    result = true;
  }
  free(tuple_items);
  free(list_items);
  return result;
}

struct getdata_case {
  const char *name;
  short sql_type;
  SQLRETURN result;
  bool should_produce_value;
  bool null_result;
  bool info_then_no_data;
  bool should_produce_sqlnull;
};

static void run_getdata_cases(void)
{
  static const struct getdata_case cases[] = {
    {"integer rejects SQL_ERROR without reading output", SQL_INTEGER,
     SQL_ERROR, false, false, false, false},
    {"integer rejects SQL_NO_DATA without reading output", SQL_INTEGER,
     SQL_NO_DATA, false, false, false, false},
    {"integer accepts SQL_SUCCESS_WITH_INFO", SQL_INTEGER,
     SQL_SUCCESS_WITH_INFO, true, false, false, false},
    {"double rejects SQL_ERROR without reading output", SQL_DOUBLE,
     SQL_ERROR, false, false, false, false},
    {"double rejects SQL_NO_DATA without reading output", SQL_DOUBLE,
     SQL_NO_DATA, false, false, false, false},
    {"double accepts SQL_SUCCESS_WITH_INFO", SQL_DOUBLE,
     SQL_SUCCESS_WITH_INFO, true, false, false, false},
    {"string rejects SQL_ERROR without reading output", SQL_VARCHAR,
     SQL_ERROR, false, false, false, false},
    {"string rejects initial SQL_NO_DATA without reading output", SQL_VARCHAR,
     SQL_NO_DATA, false, false, false, false},
    {"string accepts SQL_SUCCESS_WITH_INFO only with a valid indicator",
     SQL_VARCHAR, SQL_SUCCESS_WITH_INFO, true, true, false, true},
    {"string does not read a poisoned indicator after SQL_NO_DATA",
     SQL_VARCHAR, SQL_SUCCESS_WITH_INFO, true, false, true, false},
    {"binary rejects SQL_ERROR without reading output", SQL_VARBINARY,
     SQL_ERROR, false, false, false, false},
    {"binary rejects initial SQL_NO_DATA without reading output", SQL_VARBINARY,
     SQL_NO_DATA, false, false, false, false},
    {"binary accepts SQL_SUCCESS_WITH_INFO only with a valid indicator",
     SQL_VARBINARY, SQL_SUCCESS_WITH_INFO, true, true, false, true},
    {"binary short SQL_SUCCESS_WITH_INFO does not make a speculative read",
     SQL_VARBINARY, SQL_SUCCESS_WITH_INFO, true, false, true, false}
  };
  size_t i;

  for (i = 0; i < sizeof(cases) / sizeof(cases[0]); ++i) {
    short column_type = cases[i].sql_type;
    ODBCHandle database = {0};
    pure_expr *database_value;
    pure_expr *result;
    bool produced_value;

    mode = FAULT_GETDATA;
    getdata_return = cases[i].result;
    getdata_calls = 0;
    getdata_null_result = cases[i].null_result;
    getdata_info_then_no_data = cases[i].info_then_no_data;
    binary_read_mode = BINARY_DEFAULT;
    database.magic = ODBC_MAGIC;
    database.henv = (SQLHENV)(uintptr_t)1;
    database.hdbc = (SQLHDBC)(uintptr_t)2;
    database.hstmt = (SQLHSTMT)(uintptr_t)3;
    database.coltype = &column_type;
    database.cols = 1;
    database.exec = 1;
    database_value = pure_pointer(&database);
    result = odbc_sql_fetch(database_value);
    produced_value = is_singleton_list(result);
    check(produced_value == cases[i].should_produce_value, cases[i].name);
    check(!produced_value ||
          is_singleton_sqlnull_list(result) == cases[i].should_produce_sqlnull,
          "SQLGetData conversion has the expected SQL NULL state");
    check(getdata_calls == (cases[i].info_then_no_data &&
                            cases[i].sql_type != SQL_VARBINARY ? 2 : 1),
          "SQLGetData uses the expected number of calls");
    if (result && cases[i].sql_type == SQL_VARBINARY)
      (void)release_binary_result(result);
    release_pure_result(result);
    pure_freenew(database_value);
    check(allocation_count == 0, "getdata case has zero net allocations");
  }
}

static bool binary_bytes_match(enum binary_mode requested_mode,
                               const unsigned char *bytes, int64_t length)
{
  static const unsigned char short_value[] = {0xde, 0xad, 0xbe, 0xef};
  static const unsigned char tail[] = {0xfa, 0xce, 0xb0, 0x0c};
  int64_t i;
  unsigned char seed;

  if (requested_mode == BINARY_SHORT_INFO)
    return length == (int64_t)sizeof(short_value) &&
      memcmp(bytes, short_value, sizeof(short_value)) == 0;
  if (requested_mode == BINARY_MULTI_CHUNK)
    seed = 0x10;
  else if (requested_mode == BINARY_NO_TOTAL)
    seed = 0x40;
  else
    seed = 0x80;
  for (i = 0; i < length - (requested_mode == BINARY_INFO_THEN_NO_DATA ? 0 :
                            (int64_t)sizeof(tail)); ++i)
    if (bytes[i] != (unsigned char)(seed + (unsigned char)i))
      return false;
  if (requested_mode != BINARY_INFO_THEN_NO_DATA &&
      memcmp(bytes + length - sizeof(tail), tail, sizeof(tail)) != 0)
    return false;
  return true;
}

static void run_binary_case(enum binary_mode requested_mode, const char *name,
                            int64_t expected_length, int expected_calls)
{
  short column_type = SQL_VARBINARY;
  ODBCHandle database = {0};
  pure_expr *database_value;
  pure_expr *result;
  const unsigned char *bytes = NULL;
  int64_t length = -1;

  mode = FAULT_GETDATA;
  binary_read_mode = requested_mode;
  getdata_calls = 0;
  getdata_null_result = 0;
  getdata_info_then_no_data = 0;
  database.magic = ODBC_MAGIC;
  database.henv = (SQLHENV)(uintptr_t)1;
  database.hdbc = (SQLHDBC)(uintptr_t)2;
  database.hstmt = (SQLHSTMT)(uintptr_t)3;
  database.coltype = &column_type;
  database.cols = 1;
  database.exec = 1;
  database_value = pure_pointer(&database);
  result = odbc_sql_fetch(database_value);
  check(binary_result(result, &length, &bytes) && length == expected_length,
        name);
  check(bytes && binary_bytes_match(requested_mode, bytes, length),
        "binary SQLGetData tuple bytes are exact");
  check(getdata_calls == expected_calls,
        "binary SQLGetData uses the expected number of calls");
  if (result)
    check(release_binary_result(result),
          "binary result sentry transfers a tracked allocation");
  release_pure_result(result);
  pure_freenew(database_value);
  check(allocation_count == 0, "binary case has zero net allocations");
}

static void run_binary_cases(void)
{
  run_binary_case(BINARY_SHORT_INFO,
                  "short binary SQL_SUCCESS_WITH_INFO returns four bytes",
                  4, 1);
  run_binary_case(BINARY_MULTI_CHUNK,
                  "multi-chunk binary SQLGetData returns exact byte count",
                  BUFSZ + 4, 2);
  run_binary_case(BINARY_NO_TOTAL,
                  "SQL_NO_TOTAL binary SQLGetData returns exact byte count",
                  BUFSZ + 4, 2);
  run_binary_case(BINARY_INFO_THEN_NO_DATA,
                  "binary SQL_SUCCESS_WITH_INFO then SQL_NO_DATA preserves bytes",
                  BUFSZ, 2);
}

static pure_expr *run_getinfo(enum fault_mode requested_mode,
                              SQLUSMALLINT info_type, bool fail_allocation)
{
  ODBCHandle database = {0};
  pure_expr *database_value;
  pure_expr *result;

  mode = requested_mode;
  getinfo_calls = 0;
  fail_next_allocation = fail_allocation;
  database.magic = ODBC_MAGIC;
  database.henv = (SQLHENV)(uintptr_t)1;
  database.hdbc = (SQLHDBC)(uintptr_t)2;
  database.hstmt = (SQLHSTMT)(uintptr_t)3;
  database_value = pure_pointer(&database);
  result = odbc_getinfo(database_value, info_type);
  pure_freenew(database_value);
  return result;
}

static pure_expr *run_checked_getinfo(enum fault_mode requested_mode,
                                      SQLUSMALLINT info_type,
                                      SQLSMALLINT buffer_length,
                                      bool require_input)
{
  expected_info_type = info_type;
  expected_info_buffer_length = buffer_length;
  expected_info_input = (SQLHANDLE)(uintptr_t)3;
  check_info_input = require_input;
  getinfo_request_ok = false;
  return run_getinfo(requested_mode, info_type, false);
}

static void run_getinfo_cases(void)
{
  pure_expr *result;
  void *pointer = NULL;
  size_t i;
  bool exact = true;

  result = run_getinfo(INFO_NEGATIVE_LENGTH, SQL_DBMS_NAME, false);
  check(!pure_is_pointer(result, &pointer), "negative SQLGetInfo length rejected");
  check(allocation_count == 0, "negative length has zero net allocations");
  release_pure_result(result);

  result = run_getinfo(INFO_NO_TOTAL, SQL_DBMS_NAME, false);
  check(!pure_is_pointer(result, &pointer), "SQL_NO_TOTAL length rejected");
  check(allocation_count == 0, "SQL_NO_TOTAL has zero net allocations");
  release_pure_result(result);

  result = run_getinfo(INFO_RETRY_FAILURE, SQL_DBMS_NAME, false);
  check(!pure_is_pointer(result, &pointer), "SQLGetInfo retry failure rejected");
  check(getinfo_calls == 2, "truncated SQLGetInfo retried exactly once");
  check(allocation_count == 0, "retry failure has zero net allocations");
  release_pure_result(result);

  result = run_getinfo(INFO_LONG_TEXT, SQL_DBMS_NAME, true);
  check(!pure_is_pointer(result, &pointer), "SQLGetInfo allocator failure rejected");
  check(allocation_count == 0, "allocator failure has zero net allocations");
  release_pure_result(result);

  result = run_getinfo(INFO_LONG_TEXT, SQL_DBMS_NAME, false);
  check(pure_is_pointer(result, &pointer), "2048-byte SQLGetInfo value returned");
  if (pointer) {
    for (i = 0; i < 2048; ++i) {
      if (((char *)pointer)[i] != (char)('A' + i % 26)) {
        exact = false;
        break;
      }
    }
    exact = exact && ((char *)pointer)[2048] == 0;
  } else {
    exact = false;
  }
  check(exact, "2048-byte SQLGetInfo value is exact");
  release_pure_result(result);
  check(allocation_count == 0, "long value cleanup has zero net allocations");

  result = run_checked_getinfo(INFO_USMALLINT, SQL_MAX_TABLES_IN_SELECT,
                               sizeof(SQLUSMALLINT), false);
  check(getinfo_request_ok, "SQLUSMALLINT SQLGetInfo request is exact");
  check(pure_is_pointer(result, &pointer), "SQLUSMALLINT SQLGetInfo value returned");
  check(pointer && *(SQLUSMALLINT *)pointer == 31,
        "numeric SQLGetInfo uses SQLUSMALLINT storage");
  release_pure_result(result);
  check(allocation_count == 0, "SQLUSMALLINT value cleanup has zero net allocations");

  result = run_checked_getinfo(INFO_UINTEGER, SQL_ODBC_INTERFACE_CONFORMANCE,
                               sizeof(SQLUINTEGER), false);
  check(getinfo_request_ok,
        "SQL_ODBC_INTERFACE_CONFORMANCE uses a four-byte SQLUINTEGER buffer");
  check(pure_is_pointer(result, &pointer) &&
        *(SQLUINTEGER *)pointer == UINT32_C(0x87654321),
        "SQL_ODBC_INTERFACE_CONFORMANCE value is exact");
  release_pure_result(result);
  check(allocation_count == 0, "ODBC interface value cleanup has zero net allocations");

  result = run_checked_getinfo(INFO_UINTEGER, SQL_ASYNC_MODE,
                               sizeof(SQLUINTEGER), false);
  check(getinfo_request_ok, "SQL_ASYNC_MODE uses a four-byte SQLUINTEGER buffer");
  check(pure_is_pointer(result, &pointer) &&
        *(SQLUINTEGER *)pointer == UINT32_C(0x87654321),
        "SQL_ASYNC_MODE value is exact");
  release_pure_result(result);
  check(allocation_count == 0, "async mode value cleanup has zero net allocations");

  result = run_checked_getinfo(INFO_XOPEN_TEXT, SQL_XOPEN_CLI_YEAR, 1024,
                               false);
  check(getinfo_request_ok, "SQL_XOPEN_CLI_YEAR uses the text buffer");
  check(pure_is_pointer(result, &pointer) &&
        strcmp((const char *)pointer, "1992") == 0,
        "SQL_XOPEN_CLI_YEAR text value is exact");
  release_pure_result(result);
  check(allocation_count == 0, "X/Open text cleanup has zero net allocations");

  result = run_checked_getinfo(INFO_YN_TEXT, SQL_ROW_UPDATES, 1024, false);
  check(getinfo_request_ok, "SQL_ROW_UPDATES uses the text buffer");
  check(pure_is_pointer(result, &pointer) &&
        strcmp((const char *)pointer, "Y") == 0,
        "SQL_ROW_UPDATES Y/N value is exact");
  release_pure_result(result);
  check(allocation_count == 0, "Y/N text cleanup has zero net allocations");

  result = run_checked_getinfo(INFO_HSTMT, SQL_DRIVER_HSTMT,
                               sizeof(SQLHANDLE), true);
  check(getinfo_request_ok,
        "SQL_DRIVER_HSTMT receives a valid statement-handle input");
  check(pure_is_pointer(result, &pointer) &&
        *(SQLHANDLE *)pointer == (SQLHANDLE)(uintptr_t)3,
        "SQL_DRIVER_HSTMT handle value is exact");
  release_pure_result(result);
  check(allocation_count == 0, "statement handle cleanup has zero net allocations");

  result = run_getinfo(INFO_HDESC, SQL_DRIVER_HDESC, false);
  check(!pure_is_pointer(result, &pointer),
        "SQL_DRIVER_HDESC is rejected without a descriptor handle");
  check(getinfo_calls == 0,
        "SQL_DRIVER_HDESC does not call SQLGetInfo without a descriptor");
  release_pure_result(result);
  check(allocation_count == 0, "descriptor rejection has zero net allocations");
}

int main(void)
{
  pure_interp *interpreter = pure_create_interp(0, NULL);

  if (!interpreter) {
    fputs("FAIL: could not create Pure interpreter\n", stderr);
    return 2;
  }
  {
    struct pure_odbc_api test_api = {0};
    test_api.fetch = fake_SQLFetch;
    test_api.get_data = fake_SQLGetData;
    test_api.get_info = fake_SQLGetInfo;
    test_api.get_diag_rec = fake_SQLGetDiagRec;
    pure_odbc_set_api_for_test(&test_api);
  }
  run_getdata_cases();
  run_binary_cases();
  run_getinfo_cases();
  pure_odbc_set_api_for_test(NULL);
  pure_delete_interp(interpreter);
  printf("SUMMARY: %d failure(s), %zu net allocation(s)\n",
         failures, allocation_count);
  fflush(stdout);
  return failures == 0 && allocation_count == 0 ? 0 : 1;
}
