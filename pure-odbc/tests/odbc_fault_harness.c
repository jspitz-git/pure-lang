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
  INFO_NUMERIC
};

static enum fault_mode mode;
static SQLRETURN getdata_return;
static int getdata_calls;
static int getdata_null_result;
static int getdata_info_then_no_data;
static int getinfo_calls;
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

static SQLRETURN SQL_API fake_SQLFetch(SQLHSTMT statement)
{
  (void)statement;
  return SQL_SUCCESS;
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
  (void)info_type;
  ++getinfo_calls;
  if (mode == INFO_NUMERIC) {
    *(SQLUSMALLINT *)value = 31;
    *length = sizeof(SQLUSMALLINT);
    return SQL_SUCCESS;
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
    fault_free(pointer);
    released = true;
  }
  free(tuple_items);
  free(list_items);
  return released;
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
    {"binary does not read a poisoned indicator after SQL_NO_DATA",
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
    check(getdata_calls == (cases[i].info_then_no_data ? 2 : 1),
          "SQLGetData uses the expected number of calls");
    if (result && (cases[i].sql_type != SQL_VARBINARY ||
                   !release_binary_result(result)))
      pure_freenew(result);
    pure_freenew(database_value);
    check(allocation_count == 0, "getdata case has zero net allocations");
  }
}

static pure_expr *run_getinfo(enum fault_mode requested_mode,
                              bool fail_allocation)
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
  result = odbc_getinfo(database_value, SQL_DBMS_NAME);
  pure_freenew(database_value);
  return result;
}

static void run_getinfo_cases(void)
{
  pure_expr *result;
  void *pointer = NULL;
  size_t i;
  bool exact = true;

  result = run_getinfo(INFO_NEGATIVE_LENGTH, false);
  check(!pure_is_pointer(result, &pointer), "negative SQLGetInfo length rejected");
  check(allocation_count == 0, "negative length has zero net allocations");
  if (result)
    pure_freenew(result);

  result = run_getinfo(INFO_NO_TOTAL, false);
  check(!pure_is_pointer(result, &pointer), "SQL_NO_TOTAL length rejected");
  check(allocation_count == 0, "SQL_NO_TOTAL has zero net allocations");
  if (result)
    pure_freenew(result);

  result = run_getinfo(INFO_RETRY_FAILURE, false);
  check(!pure_is_pointer(result, &pointer), "SQLGetInfo retry failure rejected");
  check(getinfo_calls == 2, "truncated SQLGetInfo retried exactly once");
  check(allocation_count == 0, "retry failure has zero net allocations");
  if (result)
    pure_freenew(result);

  result = run_getinfo(INFO_LONG_TEXT, true);
  check(!pure_is_pointer(result, &pointer), "SQLGetInfo allocator failure rejected");
  check(allocation_count == 0, "allocator failure has zero net allocations");
  if (result)
    pure_freenew(result);

  result = run_getinfo(INFO_LONG_TEXT, false);
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
  if (pointer)
    fault_free(pointer);
  check(allocation_count == 0, "long value cleanup has zero net allocations");

  result = run_getinfo(INFO_NUMERIC, false);
  check(pure_is_pointer(result, &pointer), "numeric SQLGetInfo value returned");
  check(pointer && *(SQLUSMALLINT *)pointer == 31,
        "numeric SQLGetInfo uses SQLUSMALLINT storage");
  if (pointer)
    fault_free(pointer);
  check(allocation_count == 0, "numeric value cleanup has zero net allocations");
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
  run_getinfo_cases();
  printf("SUMMARY: %d failure(s), %zu net allocation(s)\n",
         failures, allocation_count);
  fflush(stdout);
  return failures == 0 && allocation_count == 0 ? 0 : 1;
}
