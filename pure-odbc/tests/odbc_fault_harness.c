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

enum operation_fault {
  OPERATION_OK,
  FAIL_ENV_ALLOC,
  FAIL_ENV_ATTR,
  FAIL_DBC_ALLOC,
  FAIL_DRIVER_CONNECT,
  FAIL_STMT_ALLOC,
  FAIL_PREPARE,
  FAIL_PARAMETER_CONVERSION,
  FAIL_PARAMETER_BIND,
  FAIL_EXECUTE,
  FAIL_RESULT_METADATA_ALLOCATION
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
static int fail_allocation_countdown;
static size_t allocation_count;
static void *allocations[32];
static enum operation_fault operation_fault;
static int alloc_env_calls;
static int alloc_dbc_calls;
static int alloc_stmt_calls;
static int free_env_calls;
static int free_dbc_calls;
static int free_stmt_calls;
static int set_env_attr_calls;
static int driver_connect_calls;
static int disconnect_calls;
static int close_cursor_calls;
static int reset_params_calls;
static int close_statement_calls;
static int prepare_calls;
static int bind_parameter_calls;
static int execute_calls;
static int num_result_cols_calls;
static int row_count_calls;
static int describe_col_calls;
static int more_results_calls;
static bool handle_protocol_ok;
static short result_cols[4];
static SQLLEN result_rows[4];
static int result_count;
static int result_index;
static void *watched_descriptor;
static int watched_descriptor_free_calls;
static int allocation_ids[32];
static int next_allocation_id;

enum resource_event_kind {
  EVENT_ALLOC,
  EVENT_REALLOC,
  EVENT_FREE,
  EVENT_RESET_PARAMS,
  EVENT_CLOSE_STATEMENT,
  EVENT_CLOSE_CURSOR,
  EVENT_FREE_STMT_HANDLE,
  EVENT_DISCONNECT,
  EVENT_FREE_DBC,
  EVENT_FREE_ENV
};

struct resource_event {
  enum resource_event_kind kind;
  int detail;
};

static struct resource_event resource_events[256];
static size_t resource_event_count;
static bool cursor_open;
static bool cursor_state_error;

#define FAKE_ENV ((SQLHENV)(uintptr_t)0x101)
#define FAKE_DBC ((SQLHDBC)(uintptr_t)0x202)
#define FAKE_STMT ((SQLHSTMT)(uintptr_t)0x303)

static void record_resource_event(enum resource_event_kind kind, int detail)
{
  if (resource_event_count <
      sizeof(resource_events) / sizeof(resource_events[0])) {
    resource_events[resource_event_count].kind = kind;
    resource_events[resource_event_count].detail = detail;
    ++resource_event_count;
  }
}

static void *fault_malloc(size_t size)
{
  void *ptr;
  size_t i;

  if (fail_next_allocation) {
    fail_next_allocation = 0;
    return NULL;
  }
  if (fail_allocation_countdown > 0 && --fail_allocation_countdown == 0)
    return NULL;
  ptr = malloc(size);
  if (!ptr)
    return NULL;
  for (i = 0; i < sizeof(allocations) / sizeof(allocations[0]); ++i) {
    if (!allocations[i]) {
      allocations[i] = ptr;
      allocation_ids[i] = ++next_allocation_id;
      ++allocation_count;
      record_resource_event(EVENT_ALLOC, allocation_ids[i]);
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
      record_resource_event(EVENT_REALLOC, allocation_ids[i]);
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
  if (ptr == watched_descriptor)
    ++watched_descriptor_free_calls;
  for (i = 0; i < sizeof(allocations) / sizeof(allocations[0]); ++i) {
    if (allocations[i] == ptr) {
      record_resource_event(EVENT_FREE, allocation_ids[i]);
      allocations[i] = NULL;
      allocation_ids[i] = 0;
      --allocation_count;
      free(ptr);
      return;
    }
  }
  /* Pure's vector accessors allocate their returned arrays outside the
     interposed allocator.  odbc.c owns and releases those arrays normally. */
  record_resource_event(EVENT_FREE, 0);
  free(ptr);
}

static bool fault_forget(void *ptr)
{
  size_t i;

  if (!ptr)
    return false;
  for (i = 0; i < sizeof(allocations) / sizeof(allocations[0]); ++i) {
    if (allocations[i] == ptr) {
      allocations[i] = NULL;
      allocation_ids[i] = 0;
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

static SQLRETURN SQL_API fake_SQLAllocHandle(SQLSMALLINT handle_type,
                                             SQLHANDLE input_handle,
                                             SQLHANDLE *output_handle)
{
  switch (handle_type) {
  case SQL_HANDLE_ENV:
    ++alloc_env_calls;
    handle_protocol_ok = handle_protocol_ok && output_handle != NULL &&
      *output_handle == SQL_NULL_HANDLE && input_handle == SQL_NULL_HANDLE;
    if (operation_fault == FAIL_ENV_ALLOC)
      return SQL_ERROR;
    *output_handle = FAKE_ENV;
    return SQL_SUCCESS;
  case SQL_HANDLE_DBC:
    ++alloc_dbc_calls;
    handle_protocol_ok = handle_protocol_ok && output_handle != NULL &&
      *output_handle == SQL_NULL_HANDLE && input_handle == FAKE_ENV;
    if (operation_fault == FAIL_DBC_ALLOC)
      return SQL_ERROR;
    *output_handle = FAKE_DBC;
    return SQL_SUCCESS;
  case SQL_HANDLE_STMT:
    ++alloc_stmt_calls;
    handle_protocol_ok = handle_protocol_ok && output_handle != NULL &&
      *output_handle == SQL_NULL_HANDLE && input_handle == FAKE_DBC;
    if (operation_fault == FAIL_STMT_ALLOC)
      return SQL_ERROR;
    *output_handle = FAKE_STMT;
    return SQL_SUCCESS;
  default:
    handle_protocol_ok = false;
    return SQL_ERROR;
  }
}

static SQLRETURN SQL_API fake_SQLFreeHandle(SQLSMALLINT handle_type,
                                            SQLHANDLE handle)
{
  switch (handle_type) {
  case SQL_HANDLE_ENV:
    ++free_env_calls;
    record_resource_event(EVENT_FREE_ENV, 0);
    handle_protocol_ok = handle_protocol_ok && handle == FAKE_ENV;
    break;
  case SQL_HANDLE_DBC:
    ++free_dbc_calls;
    record_resource_event(EVENT_FREE_DBC, 0);
    handle_protocol_ok = handle_protocol_ok && handle == FAKE_DBC;
    break;
  case SQL_HANDLE_STMT:
    ++free_stmt_calls;
    record_resource_event(EVENT_FREE_STMT_HANDLE, 0);
    handle_protocol_ok = handle_protocol_ok && handle == FAKE_STMT;
    break;
  default:
    handle_protocol_ok = false;
    return SQL_ERROR;
  }
  return SQL_SUCCESS;
}

static SQLRETURN SQL_API fake_SQLSetEnvAttr(SQLHENV environment,
                                            SQLINTEGER attribute,
                                            SQLPOINTER value,
                                            SQLINTEGER length)
{
  ++set_env_attr_calls;
  handle_protocol_ok = handle_protocol_ok && environment == FAKE_ENV &&
    attribute == SQL_ATTR_ODBC_VERSION && value == (SQLPOINTER)SQL_OV_ODBC3 &&
    length == SQL_IS_UINTEGER;
  return operation_fault == FAIL_ENV_ATTR ? SQL_ERROR : SQL_SUCCESS;
}

static SQLRETURN SQL_API fake_SQLDriverConnect(SQLHDBC connection,
                                               SQLHWND window,
                                               SQLCHAR *input,
                                               SQLSMALLINT input_length,
                                               SQLCHAR *output,
                                               SQLSMALLINT output_length,
                                               SQLSMALLINT *actual_length,
                                               SQLUSMALLINT completion)
{
  (void)output;
  (void)output_length;
  (void)actual_length;
  ++driver_connect_calls;
  handle_protocol_ok = handle_protocol_ok && connection == FAKE_DBC &&
    window == NULL && input != NULL && input_length == SQL_NTS &&
    completion == SQL_DRIVER_NOPROMPT;
  return operation_fault == FAIL_DRIVER_CONNECT ? SQL_ERROR : SQL_SUCCESS;
}

static SQLRETURN SQL_API fake_SQLDisconnect(SQLHDBC connection)
{
  ++disconnect_calls;
  record_resource_event(EVENT_DISCONNECT, 0);
  handle_protocol_ok = handle_protocol_ok && connection == FAKE_DBC;
  return SQL_SUCCESS;
}

static SQLRETURN SQL_API fake_SQLFreeStmt(SQLHSTMT statement,
                                         SQLUSMALLINT option)
{
  handle_protocol_ok = handle_protocol_ok && statement == FAKE_STMT;
  if (option == SQL_RESET_PARAMS) {
    ++reset_params_calls;
    record_resource_event(EVENT_RESET_PARAMS, 0);
  } else if (option == SQL_CLOSE) {
    ++close_statement_calls;
    record_resource_event(EVENT_CLOSE_STATEMENT, 0);
    cursor_open = false;
  } else
    handle_protocol_ok = false;
  return SQL_SUCCESS;
}

static SQLRETURN SQL_API fake_SQLPrepare(SQLHSTMT statement, SQLCHAR *query,
                                        SQLINTEGER length)
{
  ++prepare_calls;
  handle_protocol_ok = handle_protocol_ok && statement == FAKE_STMT &&
    query != NULL && length == SQL_NTS;
  return operation_fault == FAIL_PREPARE ? SQL_ERROR : SQL_SUCCESS;
}

static SQLRETURN SQL_API fake_SQLBindParameter(
  SQLHSTMT statement, SQLUSMALLINT parameter, SQLSMALLINT input_output_type,
  SQLSMALLINT value_type, SQLSMALLINT parameter_type, SQLULEN column_size,
  SQLSMALLINT decimal_digits, SQLPOINTER value, SQLLEN buffer_length,
  SQLLEN *indicator)
{
  (void)value_type;
  (void)parameter_type;
  (void)column_size;
  (void)decimal_digits;
  (void)value;
  (void)buffer_length;
  (void)indicator;
  ++bind_parameter_calls;
  handle_protocol_ok = handle_protocol_ok && statement == FAKE_STMT &&
    parameter >= 1 && parameter <= 2 &&
    input_output_type == SQL_PARAM_INPUT;
  return operation_fault == FAIL_PARAMETER_BIND && parameter == 2 ?
    SQL_ERROR : SQL_SUCCESS;
}

static SQLRETURN SQL_API fake_SQLExecute(SQLHSTMT statement)
{
  ++execute_calls;
  handle_protocol_ok = handle_protocol_ok && statement == FAKE_STMT;
  if (operation_fault == FAIL_EXECUTE)
    return SQL_ERROR;
  cursor_open = true;
  return SQL_SUCCESS;
}

static SQLRETURN SQL_API fake_SQLNumResultCols(SQLHSTMT statement,
                                              SQLSMALLINT *columns)
{
  ++num_result_cols_calls;
  handle_protocol_ok = handle_protocol_ok && statement == FAKE_STMT &&
    result_index >= 0 && result_index < result_count;
  if (!handle_protocol_ok)
    return SQL_ERROR;
  *columns = result_cols[result_index];
  return SQL_SUCCESS;
}

static SQLRETURN SQL_API fake_SQLRowCount(SQLHSTMT statement, SQLLEN *rows)
{
  ++row_count_calls;
  handle_protocol_ok = handle_protocol_ok && statement == FAKE_STMT &&
    result_index >= 0 && result_index < result_count;
  if (!handle_protocol_ok)
    return SQL_ERROR;
  *rows = result_rows[result_index];
  return SQL_SUCCESS;
}

static SQLRETURN SQL_API fake_SQLDescribeCol(
  SQLHSTMT statement, SQLUSMALLINT column, SQLCHAR *name,
  SQLSMALLINT name_capacity, SQLSMALLINT *name_length, SQLSMALLINT *type,
  SQLULEN *column_size, SQLSMALLINT *decimal_digits, SQLSMALLINT *nullable)
{
  static const char column_name[] = "value";
  size_t copy_length = sizeof(column_name);

  (void)column_size;
  (void)decimal_digits;
  (void)nullable;
  ++describe_col_calls;
  handle_protocol_ok = handle_protocol_ok && statement == FAKE_STMT &&
    column == 1 && name_capacity >= (SQLSMALLINT)sizeof(column_name);
  if (!handle_protocol_ok)
    return SQL_ERROR;
  memcpy(name, column_name, copy_length);
  if (name_length)
    *name_length = (SQLSMALLINT)(copy_length - 1);
  *type = SQL_INTEGER;
  return SQL_SUCCESS;
}

static SQLRETURN SQL_API fake_SQLMoreResults(SQLHSTMT statement)
{
  ++more_results_calls;
  handle_protocol_ok = handle_protocol_ok && statement == FAKE_STMT;
  if (!handle_protocol_ok || result_index + 1 >= result_count)
    return SQL_NO_DATA;
  ++result_index;
  return SQL_SUCCESS;
}

static SQLRETURN SQL_API fake_SQLCloseCursor(SQLHSTMT statement)
{
  ++close_cursor_calls;
  record_resource_event(EVENT_CLOSE_CURSOR, 0);
  handle_protocol_ok = handle_protocol_ok && statement == FAKE_STMT;
  if (!cursor_open) {
    cursor_state_error = true;
    return SQL_ERROR;
  }
  cursor_open = false;
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

static bool is_singleton_list(pure_expr *value);
static void release_pure_result(pure_expr *value);

static void check_case(bool condition, const char *case_name,
                       const char *expectation)
{
  char name[192];

  snprintf(name, sizeof(name), "%s: %s", case_name, expectation);
  check(condition, name);
}

static void reset_operation_state(void)
{
  memset(allocation_ids, 0, sizeof(allocation_ids));
  next_allocation_id = 0;
  resource_event_count = 0;
  cursor_open = false;
  cursor_state_error = false;
  operation_fault = OPERATION_OK;
  fail_next_allocation = 0;
  fail_allocation_countdown = 0;
  alloc_env_calls = 0;
  alloc_dbc_calls = 0;
  alloc_stmt_calls = 0;
  free_env_calls = 0;
  free_dbc_calls = 0;
  free_stmt_calls = 0;
  set_env_attr_calls = 0;
  driver_connect_calls = 0;
  disconnect_calls = 0;
  close_cursor_calls = 0;
  reset_params_calls = 0;
  close_statement_calls = 0;
  prepare_calls = 0;
  bind_parameter_calls = 0;
  execute_calls = 0;
  num_result_cols_calls = 0;
  row_count_calls = 0;
  describe_col_calls = 0;
  more_results_calls = 0;
  handle_protocol_ok = true;
  memset(result_cols, 0, sizeof(result_cols));
  memset(result_rows, 0, sizeof(result_rows));
  result_count = 1;
  result_index = 0;
  watched_descriptor = NULL;
  watched_descriptor_free_calls = 0;
}

static int resource_event_position(enum resource_event_kind kind, int detail)
{
  size_t i;

  for (i = 0; i < resource_event_count; ++i)
    if (resource_events[i].kind == kind &&
        (detail < 0 || resource_events[i].detail == detail))
      return (int)i;
  return -1;
}

static int resource_event_occurrences(enum resource_event_kind kind,
                                      int detail)
{
  size_t i;
  int count = 0;

  for (i = 0; i < resource_event_count; ++i)
    if (resource_events[i].kind == kind &&
        (detail < 0 || resource_events[i].detail == detail))
      ++count;
  return count;
}

static bool connection_cleanup_is_ordered(bool expect_disconnect,
                                          bool expect_free_dbc,
                                          bool expect_free_env)
{
  int disconnect_position =
    resource_event_position(EVENT_DISCONNECT, -1);
  int dbc_position = resource_event_position(EVENT_FREE_DBC, -1);
  int env_position = resource_event_position(EVENT_FREE_ENV, -1);

  if (!expect_free_env)
    return disconnect_position < 0 && dbc_position < 0 && env_position < 0;
  if (env_position < 0)
    return false;
  if (expect_free_dbc && (dbc_position < 0 || dbc_position >= env_position))
    return false;
  if (expect_disconnect &&
      (disconnect_position < 0 || disconnect_position >= dbc_position))
    return false;
  return true;
}

static bool owned_argument_cleanup_is_ordered(int owned_buffers)
{
  int reset_position = resource_event_position(EVENT_RESET_PARAMS, -1);
  int close_position = resource_event_position(EVENT_CLOSE_STATEMENT, -1);
  int i;

  if (owned_buffers == 0)
    return reset_position < 0 && close_position >= 0;
  if (reset_position < 0 || close_position < 0 ||
      reset_position >= close_position)
    return false;
  for (i = 0; i < owned_buffers; ++i) {
    int allocation_id = i + 2;
    int allocation_position =
      resource_event_position(EVENT_ALLOC, allocation_id);
    int free_position = resource_event_position(EVENT_FREE, allocation_id);

    if (resource_event_occurrences(EVENT_ALLOC, allocation_id) != 1 ||
        allocation_position < 0 || allocation_position >= reset_position ||
        resource_event_occurrences(EVENT_FREE, allocation_id) != 1 ||
        free_position <= reset_position || free_position >= close_position)
      return false;
  }
  return true;
}

static bool is_odbc_error(pure_expr *value)
{
  pure_expr *head = NULL;
  pure_expr *state = NULL;
  pure_expr *constructor = NULL;
  pure_expr *message = NULL;
  int32_t symbol = 0;

  return value && pure_is_app(value, &head, &state) &&
    pure_is_app(head, &constructor, &message) &&
    pure_is_symbol(constructor, &symbol) && symbol == pure_sym("odbc::error");
}

static bool is_int_value(pure_expr *value, int32_t expected)
{
  int32_t actual = 0;

  return value && pure_is_int(value, &actual) && actual == expected;
}

static bool is_wide_int_value(pure_expr *value, int64_t expected)
{
  int32_t narrow = 0;

  return value && !pure_is_int(value, &narrow) &&
    pure_get_int64(value) == expected;
}

static void initialize_test_database(ODBCHandle *database)
{
  memset(database, 0, sizeof(*database));
  database->magic = ODBC_MAGIC;
  database->henv = FAKE_ENV;
  database->hdbc = FAKE_DBC;
  database->hstmt = FAKE_STMT;
}

static void drain_tracked_allocations(void)
{
  size_t i;

  for (i = 0; i < sizeof(allocations) / sizeof(allocations[0]); ++i)
    if (allocations[i])
      fault_free(allocations[i]);
}

struct connection_case {
  const char *name;
  enum operation_fault fault;
  int alloc_env;
  int alloc_dbc;
  int alloc_stmt;
  int set_env_attr;
  int driver_connect;
  int free_env;
  int free_dbc;
  int disconnect;
  bool null_result;
};

static void run_connection_failure_cases(void)
{
  static const struct connection_case cases[] = {
    {"environment allocation failure", FAIL_ENV_ALLOC,
     1, 0, 0, 0, 0, 0, 0, 0, true},
    {"failure after environment allocation", FAIL_ENV_ATTR,
     1, 0, 0, 1, 0, 1, 0, 0, false},
    {"connection allocation failure", FAIL_DBC_ALLOC,
     1, 1, 0, 1, 0, 1, 0, 0, false},
    {"failure after connection allocation", FAIL_DRIVER_CONNECT,
     1, 1, 0, 1, 1, 1, 1, 0, false},
    {"failure after driver connect", FAIL_STMT_ALLOC,
     1, 1, 1, 1, 1, 1, 1, 1, false}
  };
  size_t i;

  for (i = 0; i < sizeof(cases) / sizeof(cases[0]); ++i) {
    pure_expr *result;

    check(allocation_count == 0, "connection case starts without allocations");
    reset_operation_state();
    operation_fault = cases[i].fault;
    result = odbc_connect("Driver={deterministic-missing-driver}");
    check_case(cases[i].null_result ? result == NULL : is_odbc_error(result),
               cases[i].name, "preserves the public failure result shape");
    release_pure_result(result);
    check_case(alloc_env_calls == cases[i].alloc_env &&
               alloc_dbc_calls == cases[i].alloc_dbc &&
               alloc_stmt_calls == cases[i].alloc_stmt &&
               set_env_attr_calls == cases[i].set_env_attr &&
               driver_connect_calls == cases[i].driver_connect,
               cases[i].name, "acquires only the expected handles");
    check_case(free_env_calls == cases[i].free_env &&
               free_dbc_calls == cases[i].free_dbc && free_stmt_calls == 0,
               cases[i].name, "frees each acquired handle exactly once");
    check_case(disconnect_calls == cases[i].disconnect &&
               close_cursor_calls == 0,
               cases[i].name, "disconnects only an established connection");
    check_case(handle_protocol_ok, cases[i].name,
               "uses initialized handles throughout cleanup");
    check_case(connection_cleanup_is_ordered(cases[i].disconnect != 0,
                                             cases[i].free_dbc != 0,
                                             cases[i].free_env != 0),
               cases[i].name,
               "orders disconnect, DBC release, and ENV release");
    check_case(allocation_count == 0, cases[i].name,
               "retains no connection storage");
    if (allocation_count != 0)
      drain_tracked_allocations();
  }
}

static void run_successful_connection_cleanup(void)
{
  pure_expr *database_value;
  pure_expr *disconnect_result;
  ODBCHandle *database = NULL;

  check(allocation_count == 0, "successful connection starts without allocations");
  reset_operation_state();
  database_value = odbc_connect("Driver={deterministic-success}");
  check(pure_is_pointer(database_value, (void **)&database) &&
        database && database->magic == ODBC_MAGIC,
        "successful connection preserves the public database pointer shape");
  disconnect_result = odbc_disconnect(database_value);
  check(disconnect_result != NULL,
        "successful disconnect preserves the public unit result shape");
  release_pure_result(disconnect_result);
  pure_freenew(database_value);
  check(alloc_env_calls == 1 && alloc_dbc_calls == 1 && alloc_stmt_calls == 1,
        "successful connection acquires each handle exactly once");
  check(set_env_attr_calls == 1 && driver_connect_calls == 1,
        "successful connection configures and connects exactly once");
  check(free_env_calls == 1 && free_dbc_calls == 1 && free_stmt_calls == 1,
        "successful disconnect frees each handle exactly once");
  check(disconnect_calls == 1 && close_cursor_calls == 0 &&
        close_statement_calls == 0,
        "inactive disconnect does not close a nonexistent cursor");
  check(!cursor_state_error,
        "inactive disconnect does not suppress an invalid cursor-state error");
  check(connection_cleanup_is_ordered(true, true, true),
        "successful disconnect orders disconnect, DBC release, and ENV release");
  check(handle_protocol_ok, "successful connection uses the exact handles");
  check(allocation_count == 0,
        "successful disconnect retains no connection storage");
}

static void run_active_statement_disconnect(void)
{
  pure_expr *database_value;
  pure_expr *args;
  pure_expr *execution_result;
  pure_expr *disconnect_result;
  ODBCHandle *database = NULL;
  int close_position;
  int free_statement_position;
  int disconnect_position;

  check(allocation_count == 0,
        "active disconnect starts without allocations");
  reset_operation_state();
  database_value = odbc_connect("Driver={deterministic-success}");
  check(pure_is_pointer(database_value, (void **)&database) && database,
        "active disconnect obtains a production database value");
  result_cols[0] = 0;
  result_rows[0] = 4;
  args = pure_listl(0);
  execution_result = odbc_sql_exec(database_value, "active update", args);
  check(is_int_value(execution_result, 4) && database->exec,
        "active disconnect reaches an executed statement through production");
  release_pure_result(execution_result);
  pure_freenew(args);

  disconnect_result = odbc_disconnect(database_value);
  check(disconnect_result != NULL,
        "active disconnect preserves the public unit result shape");
  release_pure_result(disconnect_result);
  pure_freenew(database_value);
  check(close_statement_calls == 1 && close_cursor_calls == 0,
        "active disconnect closes its cursor exactly once");
  check(!cursor_open && !cursor_state_error,
        "active disconnect neither leaves a cursor nor suppresses a state error");
  check(free_stmt_calls == 1 && disconnect_calls == 1 &&
        free_dbc_calls == 1 && free_env_calls == 1,
        "active disconnect releases every native resource exactly once");
  close_position = resource_event_position(EVENT_CLOSE_STATEMENT, -1);
  free_statement_position =
    resource_event_position(EVENT_FREE_STMT_HANDLE, -1);
  disconnect_position = resource_event_position(EVENT_DISCONNECT, -1);
  check(close_position >= 0 && close_position < free_statement_position &&
        free_statement_position < disconnect_position &&
        connection_cleanup_is_ordered(true, true, true),
        "active disconnect orders cursor close, statement release, disconnect, DBC, ENV");
  check(handle_protocol_ok,
        "active disconnect uses the exact native handles");
  check(allocation_count == 0,
        "active disconnect retains no connection storage");
}

static void run_repeated_driver_failure(void)
{
  int i;

  check(allocation_count == 0,
        "repeated missing-driver test starts without allocations");
  reset_operation_state();
  operation_fault = FAIL_DRIVER_CONNECT;
  for (i = 0; i < 16; ++i) {
    pure_expr *result =
      odbc_connect("Driver={deterministic-missing-driver}");

    check_case(is_odbc_error(result), "repeated missing-driver connection",
               "preserves the public error shape");
    release_pure_result(result);
    check_case(allocation_count == 0, "repeated missing-driver connection",
               "releases storage before the next attempt");
    if (allocation_count != 0)
      drain_tracked_allocations();
  }
  check(alloc_env_calls == 16 && alloc_dbc_calls == 16 &&
        set_env_attr_calls == 16 && driver_connect_calls == 16,
        "repeated missing-driver connections perform every attempted acquisition");
  check(free_env_calls == 16 && free_dbc_calls == 16 &&
        disconnect_calls == 0,
        "repeated missing-driver connections exactly balance acquired handles");
  check(handle_protocol_ok, "repeated missing-driver handle use remains valid");
}

struct execution_case {
  const char *name;
  enum operation_fault fault;
  int expected_prepare;
  int expected_bind;
  int expected_execute;
  int expected_num_cols;
  int expected_reset;
  int expected_close;
  int expected_owned_buffers;
};

static void run_execution_failure_cases(void)
{
  static const struct execution_case cases[] = {
    {"prepare failure", FAIL_PREPARE, 1, 0, 0, 0, 0, 1, 0},
    {"parameter conversion failure", FAIL_PARAMETER_CONVERSION,
     1, 0, 0, 0, 1, 1, 1},
    {"parameter bind failure", FAIL_PARAMETER_BIND, 1, 2, 0, 0, 1, 1, 2},
    {"execute failure", FAIL_EXECUTE, 1, 2, 1, 0, 1, 1, 2},
    {"result metadata allocation failure", FAIL_RESULT_METADATA_ALLOCATION,
     1, 2, 1, 1, 1, 1, 2}
  };
  size_t i;

  for (i = 0; i < sizeof(cases) / sizeof(cases[0]); ++i) {
    unsigned char bytes[] = {0xde, 0xad, 0xbe, 0xef};
    ODBCHandle database;
    pure_expr *database_value;
    pure_expr *args;
    pure_expr *result;
    bool binary_parameters = cases[i].expected_owned_buffers > 0;

    check(allocation_count == 0, "execution case starts without allocations");
    reset_operation_state();
    operation_fault = cases[i].fault;
    result_cols[0] = cases[i].fault == FAIL_RESULT_METADATA_ALLOCATION ? 1 : 0;
    if (cases[i].fault == FAIL_PARAMETER_CONVERSION)
      fail_allocation_countdown = 3;
    else if (cases[i].fault == FAIL_RESULT_METADATA_ALLOCATION)
      fail_allocation_countdown = 5;
    initialize_test_database(&database);
    database_value = pure_pointer(&database);
    if (binary_parameters)
      args = pure_listl(2,
                        pure_tuplel(2, pure_int((int)sizeof(bytes)),
                                    pure_pointer(bytes)),
                        pure_tuplel(2, pure_int((int)sizeof(bytes)),
                                    pure_pointer(bytes)));
    else
      args = pure_listl(0);
    result = odbc_sql_exec(database_value,
                           binary_parameters ? "select ?, ?" : "select ?",
                           args);
    check_case(is_odbc_error(result), cases[i].name,
               "preserves the public error constructor");
    release_pure_result(result);
    pure_freenew(args);
    pure_freenew(database_value);
    check_case(prepare_calls == cases[i].expected_prepare &&
               bind_parameter_calls == cases[i].expected_bind &&
               execute_calls == cases[i].expected_execute &&
               num_result_cols_calls == cases[i].expected_num_cols,
               cases[i].name, "stops at the injected phase");
    check_case(reset_params_calls == cases[i].expected_reset &&
               close_statement_calls == cases[i].expected_close,
               cases[i].name, "resets and closes the statement exactly once");
    check_case(database.argv == NULL && database.argc == 0 &&
               database.coltype == NULL && database.exec == 0,
               cases[i].name, "clears every database-side owner");
    check_case(handle_protocol_ok, cases[i].name,
               "uses the existing statement handle consistently");
    check_case(owned_argument_cleanup_is_ordered(
                 cases[i].expected_owned_buffers),
               cases[i].name,
               "orders RESET_PARAMS, owned-buffer release, and SQL_CLOSE");
    check_case(allocation_count == 0, cases[i].name,
               "retains no converted arguments or metadata");

    /* Keep later RED cases independent if the implementation leaked state. */
    if (database.argv)
      free_args(&database);
    if (database.coltype) {
      fault_free(database.coltype);
      database.coltype = NULL;
    }
    if (allocation_count != 0)
      drain_tracked_allocations();
  }
}

static void run_update_count_to_result_set(void)
{
  ODBCHandle database;
  pure_expr *database_value;
  pure_expr *args;
  pure_expr *result;
  pure_expr *next;
  pure_expr *row;

  check(allocation_count == 0,
        "update-to-result transition starts without allocations");
  reset_operation_state();
  result_count = 2;
  result_cols[0] = 0;
  result_rows[0] = 7;
  result_cols[1] = 1;
  initialize_test_database(&database);
  database_value = pure_pointer(&database);
  args = pure_listl(0);
  result = odbc_sql_exec(database_value, "update then select", args);
  check(is_int_value(result, 7),
        "update-count to result-set starts with the exact row count");
  release_pure_result(result);
  pure_freenew(args);
  next = odbc_sql_more(database_value);
  check(is_singleton_list(next),
        "update-count to result-set returns one column descriptor");
  check(database.coltype != NULL && database.cols == 1,
        "update-count to result-set transfers the new descriptor owner");
  watched_descriptor = database.coltype;
  release_pure_result(next);
  getdata_return = SQL_SUCCESS;
  binary_read_mode = BINARY_DEFAULT;
  row = odbc_sql_fetch(database_value);
  check(is_singleton_list(row),
        "update-count to result-set permits the next row fetch");
  release_pure_result(row);
  sql_close(&database);
  check(watched_descriptor != NULL && watched_descriptor_free_calls == 1,
        "update-count to result-set releases its descriptor exactly once");
  check(close_statement_calls == 1,
        "update-count to result-set closes the statement exactly once");
  check(handle_protocol_ok,
        "update-count to result-set keeps statement handle ownership valid");
  check(allocation_count == 0,
        "update-count to result-set retains no descriptor");
  pure_freenew(database_value);
  if (allocation_count != 0)
    drain_tracked_allocations();
}

static void run_result_set_to_update_count(void)
{
  ODBCHandle database;
  pure_expr *database_value;
  pure_expr *args;
  pure_expr *result;
  pure_expr *next;

  check(allocation_count == 0,
        "result-to-update transition starts without allocations");
  reset_operation_state();
  result_count = 2;
  result_cols[0] = 1;
  result_cols[1] = 0;
  result_rows[1] = 11;
  initialize_test_database(&database);
  database_value = pure_pointer(&database);
  args = pure_listl(0);
  result = odbc_sql_exec(database_value, "select then update", args);
  check(is_singleton_list(result),
        "result-set to update-count starts with one column descriptor");
  check(database.coltype != NULL && database.cols == 1,
        "result-set to update-count owns its initial descriptor");
  watched_descriptor = database.coltype;
  release_pure_result(result);
  pure_freenew(args);
  next = odbc_sql_more(database_value);
  check(is_int_value(next, 11),
        "result-set to update-count returns the exact next row count");
  check(database.coltype == NULL && database.cols == 0,
        "result-set to update-count clears the old descriptor owner");
  check(watched_descriptor_free_calls == 1,
        "result-set to update-count releases the old descriptor exactly once");
  release_pure_result(next);
  sql_close(&database);
  check(watched_descriptor_free_calls == 1,
        "result-set to update-count does not release the descriptor twice");
  check(close_statement_calls == 1,
        "result-set to update-count closes the statement exactly once");
  check(handle_protocol_ok,
        "result-set to update-count keeps statement handle ownership valid");
  check(allocation_count == 0,
        "result-set to update-count retains no descriptor");
  pure_freenew(database_value);
  if (allocation_count != 0)
    drain_tracked_allocations();
}

static void run_wide_update_count(void)
{
  const int64_t expected = (int64_t)INT32_MAX + 1;
  ODBCHandle database;
  pure_expr *database_value;
  pure_expr *args;
  pure_expr *result;

  check(allocation_count == 0,
        "wide update-count case starts without allocations");
  reset_operation_state();
  result_cols[0] = 0;
  result_rows[0] = (SQLLEN)expected;
  initialize_test_database(&database);
  database_value = pure_pointer(&database);
  args = pure_listl(0);
  result = odbc_sql_exec(database_value, "wide update count", args);
  check(is_wide_int_value(result, expected),
        "row counts outside 32-bit range use an exact Pure wide integer");
  release_pure_result(result);
  pure_freenew(args);
  sql_close(&database);
  check(close_statement_calls == 1 && allocation_count == 0,
        "wide update-count cleanup releases the statement exactly once");
  pure_freenew(database_value);
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
    test_api.alloc_handle = fake_SQLAllocHandle;
    test_api.free_handle = fake_SQLFreeHandle;
    test_api.set_env_attr = fake_SQLSetEnvAttr;
    test_api.driver_connect = fake_SQLDriverConnect;
    test_api.disconnect = fake_SQLDisconnect;
    test_api.fetch = fake_SQLFetch;
    test_api.free_stmt = fake_SQLFreeStmt;
    test_api.prepare = fake_SQLPrepare;
    test_api.bind_parameter = fake_SQLBindParameter;
    test_api.execute = fake_SQLExecute;
    test_api.num_result_cols = fake_SQLNumResultCols;
    test_api.row_count = fake_SQLRowCount;
    test_api.describe_col = fake_SQLDescribeCol;
    test_api.get_data = fake_SQLGetData;
    test_api.more_results = fake_SQLMoreResults;
    test_api.close_cursor = fake_SQLCloseCursor;
    test_api.get_info = fake_SQLGetInfo;
    test_api.get_diag_rec = fake_SQLGetDiagRec;
    pure_odbc_set_api_for_test(&test_api);
  }
  run_connection_failure_cases();
  run_successful_connection_cleanup();
  run_active_statement_disconnect();
  run_repeated_driver_failure();
  run_execution_failure_cases();
  run_update_count_to_result_set();
  run_result_set_to_update_count();
  run_wide_update_count();
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
