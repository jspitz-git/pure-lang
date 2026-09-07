
/* Copyright (c) 2009 by Albert Graef <Dr.Graef@t-online.de>.
   Copyright (c) 2009 by Jiri Spitz <jiri.spitz@bluetone.cz>.

   pure-odbc is free software: you can redistribute it and/or modify it under
   the terms of the GNU Lesser General Public License as published by the Free
   Software Foundation, either version 3 of the License, or (at your option)
   any later version.

   pure-odbc is distributed in the hope that it will be useful, but WITHOUT
   ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
   FITNESS FOR A PARTICULAR PURPOSE.  See the GNU Lesser General Public
   License for more details.

   You should have received a copy of the GNU Lesser General Public License
   along with this program.  If not, see <http://www.gnu.org/licenses/>. */

#ifdef _WIN32
#include <windows.h>
#endif

/* system headers */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>
#include <limits.h>
#include <stdint.h>

#ifdef __MINGW32__
#include <malloc.h>
#endif

#include <sql.h>
#include <sqlext.h>
#include "odbc_api.h"

#if (ODBCVER < 0x0300)
#error "Sorry, this module requires ODBC 3.0 or later!"
#endif

#include <gmp.h>
#include <pure/runtime.h>

static const struct pure_odbc_api pure_odbc_production_api = {
  SQLAllocHandle,
  SQLFreeHandle,
  SQLSetEnvAttr,
  SQLDriverConnect,
  SQLDisconnect,
  SQLGetDiagRec,
  SQLDrivers,
  SQLDataSources,
  SQLGetInfo,
  SQLGetTypeInfo,
  SQLBindCol,
  SQLFetch,
  SQLFreeStmt,
  SQLTables,
  SQLColumns,
  SQLPrimaryKeys,
  SQLForeignKeys,
  SQLPrepare,
  SQLBindParameter,
  SQLExecute,
  SQLNumResultCols,
  SQLRowCount,
  SQLDescribeCol,
  SQLGetData,
  SQLMoreResults,
  SQLCloseCursor
};

static const struct pure_odbc_api *api = &pure_odbc_production_api;

#ifdef PURE_ODBC_TESTING
static struct pure_odbc_api pure_odbc_test_api;

void pure_odbc_set_api_for_test(const struct pure_odbc_api *test_api)
{
  if (!test_api) {
    api = &pure_odbc_production_api;
    return;
  }
  pure_odbc_test_api = pure_odbc_production_api;
#define PURE_ODBC_OVERRIDE(member) \
  if (test_api->member) pure_odbc_test_api.member = test_api->member
  PURE_ODBC_OVERRIDE(alloc_handle);
  PURE_ODBC_OVERRIDE(free_handle);
  PURE_ODBC_OVERRIDE(set_env_attr);
  PURE_ODBC_OVERRIDE(driver_connect);
  PURE_ODBC_OVERRIDE(disconnect);
  PURE_ODBC_OVERRIDE(get_diag_rec);
  PURE_ODBC_OVERRIDE(drivers);
  PURE_ODBC_OVERRIDE(data_sources);
  PURE_ODBC_OVERRIDE(get_info);
  PURE_ODBC_OVERRIDE(get_type_info);
  PURE_ODBC_OVERRIDE(bind_col);
  PURE_ODBC_OVERRIDE(fetch);
  PURE_ODBC_OVERRIDE(free_stmt);
  PURE_ODBC_OVERRIDE(tables);
  PURE_ODBC_OVERRIDE(columns);
  PURE_ODBC_OVERRIDE(primary_keys);
  PURE_ODBC_OVERRIDE(foreign_keys);
  PURE_ODBC_OVERRIDE(prepare);
  PURE_ODBC_OVERRIDE(bind_parameter);
  PURE_ODBC_OVERRIDE(execute);
  PURE_ODBC_OVERRIDE(num_result_cols);
  PURE_ODBC_OVERRIDE(row_count);
  PURE_ODBC_OVERRIDE(describe_col);
  PURE_ODBC_OVERRIDE(get_data);
  PURE_ODBC_OVERRIDE(more_results);
  PURE_ODBC_OVERRIDE(close_cursor);
#undef PURE_ODBC_OVERRIDE
  api = &pure_odbc_test_api;
}
#endif

#ifdef SQLAllocHandle
#undef SQLAllocHandle
#endif
#define SQLAllocHandle(...) api->alloc_handle(__VA_ARGS__)
#define SQLFreeHandle(...) api->free_handle(__VA_ARGS__)
#define SQLSetEnvAttr(...) api->set_env_attr(__VA_ARGS__)
#define SQLDriverConnect(...) api->driver_connect(__VA_ARGS__)
#define SQLDisconnect(...) api->disconnect(__VA_ARGS__)
#define SQLGetDiagRec(...) api->get_diag_rec(__VA_ARGS__)
#define SQLDrivers(...) api->drivers(__VA_ARGS__)
#define SQLDataSources(...) api->data_sources(__VA_ARGS__)
#define SQLGetInfo(...) api->get_info(__VA_ARGS__)
#define SQLGetTypeInfo(...) api->get_type_info(__VA_ARGS__)
#define SQLBindCol(...) api->bind_col(__VA_ARGS__)
#define SQLFetch(...) api->fetch(__VA_ARGS__)
#define SQLFreeStmt(...) api->free_stmt(__VA_ARGS__)
#define SQLTables(...) api->tables(__VA_ARGS__)
#define SQLColumns(...) api->columns(__VA_ARGS__)
#define SQLPrimaryKeys(...) api->primary_keys(__VA_ARGS__)
#define SQLForeignKeys(...) api->foreign_keys(__VA_ARGS__)
#define SQLPrepare(...) api->prepare(__VA_ARGS__)
#define SQLBindParameter(...) api->bind_parameter(__VA_ARGS__)
#define SQLExecute(...) api->execute(__VA_ARGS__)
#define SQLNumResultCols(...) api->num_result_cols(__VA_ARGS__)
#define SQLRowCount(...) api->row_count(__VA_ARGS__)
#define SQLDescribeCol(...) api->describe_col(__VA_ARGS__)
#define SQLGetData(...) api->get_data(__VA_ARGS__)
#define SQLMoreResults(...) api->more_results(__VA_ARGS__)
#define SQLCloseCursor(...) api->close_cursor(__VA_ARGS__)

/* SQL NULL representation. */

static int32_t sqlnull_sym = 0; /* FIXME: TLD */

static inline pure_expr *pure_sqlnull(void)
{
  if (sqlnull_sym == 0) sqlnull_sym = pure_sym("odbc::SQLNULL");
  return pure_symbol(sqlnull_sym);
}

static inline bool pure_is_sqlnull(pure_expr *x)
{
  int32_t sym;
  if (sqlnull_sym == 0) sqlnull_sym = pure_sym("odbc::SQLNULL");
  return pure_is_symbol(x, &sym) && sym == sqlnull_sym;
}

/* Query parameter structure */

typedef struct {
  SQLSMALLINT type; /* SQL parameter type */
  SQLSMALLINT ctype; /* C parameter type */
  SQLLEN len; /* length or indicator */
  SQLLEN buflen; /* real buffer length */
  SQLULEN prec; /* precision */
  void *ptr; /* buffer pointer */
  union {
    SQLINTEGER iv; /* integer parameter */
    double fv; /* floating point parameter */
    char *buf; /* string or byte string parameter */
  } data;
} ODBCParam;

/* ODBC handle structure */

#define ODBC_MAGIC 9029 /* the 1122th prime */

typedef struct {
  short magic; /* this provides for some type safety */
  SQLHENV henv; /* environment handle */
  SQLHDBC hdbc; /* connection handle */
  SQLHSTMT hstmt; /* statement handle */
  unsigned char exec; /* set while statement is being executed */
  SQLSMALLINT *coltype; /* column types in current result set */
  SQLSMALLINT cols; /* number of columns */
  ODBCParam *argv; /* marked parameters */
  size_t argc; /* number of marked parameters */
} ODBCHandle;

static inline bool is_db_pointer(pure_expr *x, ODBCHandle **db)
{
  return pure_is_pointer(x, (void**)db) && *db &&
    (*db)->magic == ODBC_MAGIC && (*db)->henv;
}

static bool checked_multiply(size_t count, size_t element_size, size_t *bytes)
{
  if (element_size != 0 && count > SIZE_MAX / element_size)
    return false;
  *bytes = count * element_size;
  return true;
}

static SQLLEN sql_len_max(void)
{
  return (SQLLEN)(((SQLULEN)~(SQLULEN)0) >> 1);
}

static bool size_to_sql_len(size_t value, SQLLEN *result)
{
  if (sizeof(size_t) >= sizeof(SQLLEN) && value > (size_t)sql_len_max())
    return false;
  *result = (SQLLEN)value;
  return true;
}

static bool size_to_sql_ulen(size_t value, SQLULEN *result)
{
  SQLULEN maximum = (SQLULEN)~(SQLULEN)0;

  if (sizeof(size_t) > sizeof(SQLULEN) && value > (size_t)maximum)
    return false;
  *result = (SQLULEN)value;
  return true;
}

static bool int64_to_size(int64_t value, size_t *result)
{
  if (value < 0 ||
      (sizeof(size_t) < sizeof(uint64_t) &&
       (uint64_t)value > (uint64_t)SIZE_MAX))
    return false;
  *result = (size_t)value;
  return true;
}

static bool mpz_fits_int64(const mpz_t value)
{
  mpz_t limit;
  int comparison;
  int sign = mpz_sgn(value);

  mpz_init_set_ui(limit, 1);
  mpz_mul_2exp(limit, limit, 63);
  comparison = mpz_cmpabs(value, limit);
  mpz_clear(limit);
  return sign < 0 ? comparison <= 0 : comparison < 0;
}

static int init_args(ODBCHandle *db, size_t argc)
{
  size_t i;
  size_t bytes;

  if (argc == 0)
    return 1;
  if (!checked_multiply(argc, sizeof(ODBCParam), &bytes) ||
      !(db->argv = malloc(bytes)))
    return 0;
  memset(db->argv, 0, bytes);
  db->argc = argc;
  for (i = 0; i < argc; i++) {
    db->argv[i].type = SQL_UNKNOWN_TYPE;
    db->argv[i].len = SQL_NULL_DATA;
  }
  return 1;
}

static void free_args(ODBCHandle *db)
{
  if (db->argv) {
    ODBCParam *argv = db->argv;
    size_t argc = db->argc;
    size_t i;

    db->argv = NULL;
    db->argc = 0;
    SQLFreeStmt(db->hstmt, SQL_RESET_PARAMS);
    for (i = 0; i < argc; i++)
      if ((argv[i].type == SQL_BIGINT || argv[i].type == SQL_CHAR ||
	   argv[i].type == SQL_BINARY) &&
	  argv[i].data.buf)
	free(argv[i].data.buf);
    free(argv);
  }
}

static int set_arg(ODBCHandle *db, size_t i, pure_expr *x)
{
  int32_t iv;
  double fv;
  char *s;
  mpz_t z;
  size_t nelems;
  unsigned char *buf;
  int64_t length_value;
  size_t buffer_size;
  SQLLEN buffer_length;
  SQLULEN precision;
  if (pure_is_int(x, &iv)) {
    db->argv[i].type = SQL_INTEGER;
    db->argv[i].ctype = SQL_C_SLONG;
    db->argv[i].len = (SQLLEN)sizeof(SQLINTEGER);
    db->argv[i].buflen = (SQLLEN)sizeof(SQLINTEGER);
    db->argv[i].prec = 10;
    db->argv[i].data.iv = iv;
    db->argv[i].ptr = &db->argv[i].data.iv;
    return 1;
  } else if (pure_is_mpz(x, &z)) {
    /* convert big integer values to BIGINTs via a string representation,
       so we don't have to fiddle with long long's here */
    char *value;

    if (!mpz_fits_int64(z)) {
      mpz_clear(z);
      return 0;
    }
    value = mpz_get_str(NULL, 10, z);
    mpz_clear(z);
    if (!value)
      return 0;
    buffer_size = strlen(value) + 1;
    if (!size_to_sql_len(buffer_size, &buffer_length) ||
        !size_to_sql_ulen(buffer_size - 1, &precision)) {
      free(value);
      return 0;
    }
    db->argv[i].type = SQL_BIGINT;
    db->argv[i].ctype = SQL_C_CHAR;
    db->argv[i].len = SQL_NTS;
    db->argv[i].data.buf = value;
    db->argv[i].buflen = buffer_length;
    db->argv[i].prec = precision;
    db->argv[i].ptr = db->argv[i].data.buf;
    return 1;
  } else if (pure_is_double(x, &fv)) {
    db->argv[i].type = SQL_DOUBLE;
    db->argv[i].ctype = SQL_C_DOUBLE;
    db->argv[i].len = (SQLLEN)sizeof(double);
    db->argv[i].buflen = (SQLLEN)sizeof(double);
    db->argv[i].prec = 15;
    db->argv[i].data.fv = fv;
    db->argv[i].ptr = &db->argv[i].data.fv;
    return 1;
  } else if (pure_is_cstring_dup(x, &s)) {
    if (!s) return 0;
    buffer_size = strlen(s) + 1;
    if (!size_to_sql_len(buffer_size, &buffer_length) ||
        !size_to_sql_ulen(buffer_size, &precision)) {
      free(s);
      return 0;
    }
    db->argv[i].type = SQL_CHAR;
    db->argv[i].ctype = SQL_C_CHAR;
    db->argv[i].len = SQL_NTS;
    db->argv[i].buflen = buffer_length;
    /* FIXME: The prec value should actually be buflen-1 here, but the MS
       Access ODBC interface barks at these. Hopefully this doesn't mess
       things up with other ODBC drivers. */
    db->argv[i].prec = precision;
    db->argv[i].data.buf = s;
    db->argv[i].ptr = s;
    return 1;
  } else if (pure_is_tuplev(x, &nelems, NULL) && nelems==2) {
    pure_expr **elems;
    pure_is_tuplev(x, &nelems, &elems);
    if (!pure_is_pointer(elems[1], (void**)&buf)) {
      free(elems);
      return 0;
    }
    if (pure_is_int(elems[0], &iv))
      length_value = (int64_t)iv;
    else if (pure_is_mpz(elems[0], &z)) {
      if (!mpz_fits_int64(z)) {
        mpz_clear(z);
        free(elems);
        return 0;
      }
      mpz_clear(z);
      length_value = pure_get_int64(elems[0]);
    } else {
      free(elems);
      return 0;
    }
    free(elems);
    if (!int64_to_size(length_value, &buffer_size) ||
        (buffer_size > 0 && !buf) ||
        !size_to_sql_len(buffer_size, &buffer_length) ||
        !size_to_sql_ulen(buffer_size, &precision))
      return 0;
    db->argv[i].type = SQL_BINARY;
    db->argv[i].ctype = SQL_C_BINARY;
    db->argv[i].len = buffer_length;
    db->argv[i].buflen = buffer_length;
    db->argv[i].prec = precision;
    if (buffer_size > 0) {
      if (!(db->argv[i].data.buf = malloc(buffer_size)))
	return 0;
      memcpy(db->argv[i].data.buf, buf, buffer_size);
    } else
      db->argv[i].data.buf = NULL;
    db->argv[i].ptr = db->argv[i].data.buf;
    return 1;
  } else if (pure_is_sqlnull(x)) {
    db->argv[i].type = SQL_CHAR;
    db->argv[i].ctype = SQL_C_DEFAULT;
    db->argv[i].len = SQL_NULL_DATA;
    db->argv[i].buflen = 0;
    /* FIXME: The prec value should actually be zero, but again MS Access
       doesn't seem to like zero values here. Hopefully this doesn't mess
       things up with other ODBC drivers. */
    db->argv[i].prec = 1;
    db->argv[i].data.buf = NULL;
    db->argv[i].ptr = NULL;
    return 1;
  } else
    return 0;
}

static void sql_close(ODBCHandle *db)
{
  if (db->exec) {
    SQLSMALLINT *coltype = db->coltype;

    db->coltype = NULL;
    db->cols = 0;
    db->exec = 0;
    if (coltype) free(coltype);
    free_args(db);
    SQLFreeStmt(db->hstmt, SQL_CLOSE);
  }
}

static inline pure_expr* pure_err_internal(const char *msg)
{
  return pure_app(pure_app(pure_symbol(pure_sym("odbc::error")),
			   pure_cstring_dup("[Pure ODBC]internal error")),
		  pure_cstring_dup(msg));
}

static pure_expr *pure_odbc_error(const char *message, const char *state)
{
  return pure_app(pure_app(pure_symbol(pure_sym("odbc::error")),
			   pure_cstring_dup(message)),
		  pure_cstring_dup(state));
}

static pure_expr *pure_err_for_handle(SQLSMALLINT handle_type,
                                      SQLHANDLE handle, bool *found)
{
  SQLCHAR state[6] = {0};
  SQLCHAR *record_message = NULL;
  char *messages = NULL;
  size_t record_capacity = 256;
  size_t messages_capacity = 0;
  size_t messages_length = 0;
  SQLSMALLINT record = 1;
  char first_state[6] = {0};

  *found = false;
  if (!(record_message = (SQLCHAR *)malloc(record_capacity)))
    return pure_err_internal("insufficient memory");
  while (record > 0) {
    SQLINTEGER native_error = 0;
    SQLSMALLINT text_length = 0;
    SQLRETURN ret = SQLGetDiagRec(handle_type, handle, record, state,
                                  &native_error, record_message,
                                  (SQLSMALLINT)record_capacity, &text_length);
    size_t required;

    if (ret == SQL_NO_DATA)
      break;
    if (!SQL_SUCCEEDED(ret) || text_length < 0)
      break;
    required = (size_t)text_length + 1;
    if (required > record_capacity) {
      SQLCHAR *grown;

      if (required > (size_t)SHRT_MAX ||
          !(grown = (SQLCHAR *)realloc(record_message, required))) {
        free(messages);
        free(record_message);
        *found = true;
        return pure_err_internal("insufficient memory");
      }
      record_message = grown;
      record_capacity = required;
      continue;
    }
    record_message[text_length] = 0;
    if (!*found) {
      memcpy(first_state, state, sizeof(first_state));
      first_state[sizeof(first_state) - 1] = 0;
    }
    if (messages_length > SIZE_MAX - (size_t)text_length -
                            (*found ? 2U : 1U)) {
      free(messages);
      free(record_message);
      *found = true;
      return pure_err_internal("insufficient memory");
    }
    required = messages_length + (size_t)text_length + (*found ? 2U : 1U);
    if (required > messages_capacity) {
      size_t grown_capacity = messages_capacity ? messages_capacity : 256;
      char *grown;

      while (grown_capacity < required) {
        if (grown_capacity > SIZE_MAX / 2) {
          grown_capacity = required;
          break;
        }
        grown_capacity *= 2;
      }
      if (!(grown = (char *)realloc(messages, grown_capacity))) {
        free(messages);
        free(record_message);
        *found = true;
        return pure_err_internal("insufficient memory");
      }
      messages = grown;
      messages_capacity = grown_capacity;
    }
    if (*found)
      messages[messages_length++] = '\n';
    memcpy(messages + messages_length, record_message, (size_t)text_length);
    messages_length += (size_t)text_length;
    messages[messages_length] = 0;
    *found = true;
    if (record == SHRT_MAX)
      break;
    ++record;
  }
  free(record_message);
  if (*found) {
    pure_expr *result = pure_odbc_error(messages, first_state);
    free(messages);
    return result;
  }
  free(messages);
  return NULL;
}

static pure_expr *pure_err(SQLHENV henv, SQLHDBC hdbc, SQLHSTMT hstmt)
{
  SQLSMALLINT types[3];
  SQLHANDLE handles[3];
  size_t count = 0;
  size_t i;
  if (hstmt) {
    types[count] = SQL_HANDLE_STMT;
    handles[count++] = hstmt;
  }
  if (hdbc) {
    types[count] = SQL_HANDLE_DBC;
    handles[count++] = hdbc;
  }
  if (henv) {
    types[count] = SQL_HANDLE_ENV;
    handles[count++] = henv;
  }
  for (i = 0; i < count; ++i) {
    bool found;
    pure_expr *result = pure_err_for_handle(types[i], handles[i], &found);

    if (found || result)
      return result;
  }
  return NULL;
}

typedef SQLRETURN (SQL_API *odbc_enumerator)(
  SQLHENV, SQLUSMALLINT, SQLCHAR *, SQLSMALLINT, SQLSMALLINT *, SQLCHAR *,
  SQLSMALLINT, SQLSMALLINT *);

static bool grow_enumeration_buffer(SQLCHAR **buffer, size_t *capacity,
                                    size_t required)
{
  SQLCHAR *grown;

  if (required > (size_t)SHRT_MAX)
    return false;
  if (required <= *capacity)
    return true;
  grown = (SQLCHAR *)realloc(*buffer, required);
  if (!grown)
    return false;
  *buffer = grown;
  *capacity = required;
  return true;
}

static bool grow_expression_vector(pure_expr ***values, size_t *capacity,
                                   size_t required)
{
  size_t grown_capacity = *capacity ? *capacity : 8;
  size_t bytes;
  pure_expr **grown;

  while (grown_capacity < required) {
    if (grown_capacity > SIZE_MAX / 2) {
      grown_capacity = required;
      break;
    }
    grown_capacity *= 2;
  }
  if (!checked_multiply(grown_capacity, sizeof(**values), &bytes) ||
      !(grown = (pure_expr **)realloc(*values, bytes)))
    return false;
  *values = grown;
  *capacity = grown_capacity;
  return true;
}

static pure_expr *driver_attributes(SQLCHAR *attributes, size_t length)
{
  pure_expr **values = NULL;
  pure_expr *result;
  size_t count = 0;
  size_t capacity = 0;
  size_t offset = 0;

  while (offset < length && attributes[offset] != 0) {
    SQLCHAR *terminator = (SQLCHAR *)memchr(attributes + offset, 0,
                                             length - offset);
    size_t item_length = terminator ?
      (size_t)(terminator - (attributes + offset)) : length - offset;

    if (!grow_expression_vector(&values, &capacity, count + 1))
      goto error;
    values[count] = pure_cstring_dup((const char *)(attributes + offset));
    if (!values[count])
      goto error;
    ++count;
    offset += item_length + 1;
  }
  result = pure_listv(count, values);
  free(values);
  return result;

 error:
  while (count > 0)
    pure_freenew(values[--count]);
  free(values);
  return NULL;
}

static pure_expr *odbc_enumeration(bool drivers)
{
  odbc_enumerator enumerate = drivers ? api->drivers : api->data_sources;
  SQLHENV henv = (SQLHENV)SQL_NULL_HANDLE;
  SQLCHAR *name = NULL;
  SQLCHAR *detail = NULL;
  pure_expr **values = NULL;
  pure_expr *result = NULL;
  size_t name_capacity = 128;
  size_t detail_capacity = 128;
  size_t value_capacity = 0;
  size_t value_count = 0;
  SQLUSMALLINT direction = SQL_FETCH_FIRST;
  SQLRETURN ret;
  bool odbc_failure = false;

  if ((ret = SQLAllocHandle(SQL_HANDLE_ENV, SQL_NULL_HANDLE, &henv)) !=
      SQL_SUCCESS && ret != SQL_SUCCESS_WITH_INFO)
    return NULL;
  if ((ret = SQLSetEnvAttr(henv, SQL_ATTR_ODBC_VERSION,
			   (SQLPOINTER)SQL_OV_ODBC3, SQL_IS_UINTEGER)) !=
      SQL_SUCCESS && ret != SQL_SUCCESS_WITH_INFO) {
    result = pure_err(henv, 0, 0);
    goto cleanup;
  }
  name = (SQLCHAR *)malloc(name_capacity);
  detail = (SQLCHAR *)malloc(detail_capacity);
  if (!name || !detail)
    goto allocation_failure;
  while (1) {
    SQLSMALLINT name_length = 0;
    SQLSMALLINT detail_length = 0;
    size_t required_name;
    size_t required_detail;
    bool retry;

    ret = enumerate(henv, direction, name, (SQLSMALLINT)name_capacity,
                    &name_length, detail, (SQLSMALLINT)detail_capacity,
                    &detail_length);
    if (ret == SQL_NO_DATA)
      break;
    if (!SQL_SUCCEEDED(ret) || name_length < 0 || detail_length < 0) {
      odbc_failure = true;
      break;
    }
    required_name = (size_t)name_length + 1;
    required_detail = (size_t)detail_length + (drivers ? 2U : 1U);
    retry = required_name > name_capacity ||
      required_detail > detail_capacity;
    if (required_detail < (size_t)detail_length ||
        !grow_enumeration_buffer(&name, &name_capacity, required_name) ||
        !grow_enumeration_buffer(&detail, &detail_capacity, required_detail))
      goto allocation_failure;
    if (retry)
      continue;
    name[name_length] = 0;
    detail[detail_length] = 0;
    if (drivers)
      detail[(size_t)detail_length + 1] = 0;
    if (!grow_expression_vector(&values, &value_capacity, value_count + 1))
      goto allocation_failure;
    if (drivers) {
      pure_expr *attributes = driver_attributes(detail, (size_t)detail_length);

      if (!attributes)
        goto allocation_failure;
      values[value_count] = pure_tuplel(
        2, pure_cstring_dup((const char *)name), attributes);
    } else {
      values[value_count] = pure_tuplel(
        2, pure_cstring_dup((const char *)name),
        pure_cstring_dup((const char *)detail));
    }
    if (!values[value_count])
      goto allocation_failure;
    ++value_count;
    direction = SQL_FETCH_NEXT;
  }
  if (odbc_failure)
    result = pure_err(henv, 0, 0);
  else {
    result = pure_listv(value_count, values);
    if (result)
      value_count = 0;
  }
  goto cleanup;

 allocation_failure:
  result = pure_err_internal("insufficient memory");
 cleanup:
  while (value_count > 0)
    pure_freenew(values[--value_count]);
  free(values);
  free(detail);
  free(name);
  SQLFreeHandle(SQL_HANDLE_ENV, henv);
  return result;
}

pure_expr *odbc_sources()
{
  return odbc_enumeration(false);
}

pure_expr *odbc_drivers()
{
  return odbc_enumeration(true);
}

pure_expr *odbc_connect(char* conn)
{
  ODBCHandle *db = NULL;
  pure_expr *res = NULL;
  SQLRETURN ret;
  SQLSMALLINT buflen = 0;
  char buf[1024] = {0};
  bool connected = false;

  if (!conn)
    return 0;
  if (!(db = (ODBCHandle*)malloc(sizeof(ODBCHandle)))) {
    res = pure_err_internal("insufficient memory");
    goto cleanup;
  }
  memset(db, 0, sizeof(*db));
  db->magic = ODBC_MAGIC;
  db->henv = (SQLHENV)SQL_NULL_HANDLE;
  db->hdbc = (SQLHDBC)SQL_NULL_HANDLE;
  db->hstmt = (SQLHSTMT)SQL_NULL_HANDLE;
  /* create the environment handle */
  if ((ret = SQLAllocHandle(SQL_HANDLE_ENV, SQL_NULL_HANDLE, &db->henv)) !=
      SQL_SUCCESS && ret != SQL_SUCCESS_WITH_INFO)
    goto cleanup;
  if ((ret = SQLSetEnvAttr(db->henv, SQL_ATTR_ODBC_VERSION,
			   (SQLPOINTER) SQL_OV_ODBC3,
			   SQL_IS_UINTEGER)) != SQL_SUCCESS &&
      ret != SQL_SUCCESS_WITH_INFO) {
    res = pure_err(db->henv, 0, 0);
    goto cleanup;
  }
  /* create the connection handle */
  if ((ret = SQLAllocHandle(SQL_HANDLE_DBC, db->henv, &db->hdbc)) !=
      SQL_SUCCESS && ret != SQL_SUCCESS_WITH_INFO) {
    res = pure_err(db->henv, 0, 0);
    goto cleanup;
  }
  /* connect */
  if ((ret = SQLDriverConnect(db->hdbc, 0, (SQLCHAR*)conn, SQL_NTS,
			      (SQLCHAR*)buf, sizeof(buf), &buflen,
			      SQL_DRIVER_NOPROMPT)) != SQL_SUCCESS &&
      ret != SQL_SUCCESS_WITH_INFO) {
    res = pure_err(db->henv, db->hdbc, 0);
    goto cleanup;
  }
  connected = true;
  /* create the statement handle */
  if ((ret = SQLAllocHandle(SQL_HANDLE_STMT, db->hdbc, &db->hstmt)) !=
      SQL_SUCCESS && ret != SQL_SUCCESS_WITH_INFO) {
    res = pure_err(db->henv, db->hdbc, 0);
    goto cleanup;
  }
  /* return the result and transfer the initialized handle storage */
  res = pure_sentry(pure_symbol(pure_sym("odbc::disconnect")),
		    pure_pointer(db));
  if (res)
    db = NULL;

 cleanup:
  if (db) {
    if (db->hstmt)
      SQLFreeHandle(SQL_HANDLE_STMT, db->hstmt);
    if (connected)
      SQLDisconnect(db->hdbc);
    if (db->hdbc)
      SQLFreeHandle(SQL_HANDLE_DBC, db->hdbc);
    if (db->henv)
      SQLFreeHandle(SQL_HANDLE_ENV, db->henv);
    free(db);
  }
  return res;
}

pure_expr *odbc_disconnect(pure_expr *dbx)
{
  ODBCHandle *db;
  if (is_db_pointer(dbx, &db)) {
    sql_close(db);
    SQLFreeHandle(SQL_HANDLE_STMT, db->hstmt);
    SQLDisconnect(db->hdbc);
    SQLFreeHandle(SQL_HANDLE_DBC, db->hdbc);
    SQLFreeHandle(SQL_HANDLE_ENV, db->henv);
    free(db);
    dbx->data.p = NULL;
    return pure_tuplel(0);
  } else
    return 0;
}

pure_expr *odbc_info(pure_expr *dbx)
{
  ODBCHandle *db;
  if (is_db_pointer(dbx, &db)) {
    SQLRETURN ret;
    size_t n = 0;
    pure_expr *xv[8], *res;
    char info[1024];
    SQLSMALLINT len;
    if ((ret  = SQLGetInfo(db->hdbc, SQL_DATA_SOURCE_NAME,
			   info, sizeof(info), &len)) == SQL_SUCCESS ||
	ret == SQL_SUCCESS_WITH_INFO)
      xv[n++] = pure_cstring_dup(info);
    else
      xv[n++] = pure_string_dup("");
    if ((ret  = SQLGetInfo(db->hdbc, SQL_DATABASE_NAME,
			   info, sizeof(info), &len)) == SQL_SUCCESS ||
	ret == SQL_SUCCESS_WITH_INFO)
      xv[n++] = pure_cstring_dup(info);
    else
      xv[n++] = pure_string_dup("");
    if ((ret  = SQLGetInfo(db->hdbc, SQL_DBMS_NAME,
			   info, sizeof(info), &len)) == SQL_SUCCESS ||
	ret == SQL_SUCCESS_WITH_INFO)
      xv[n++] = pure_cstring_dup(info);
    else
      xv[n++] = pure_string_dup("");
    if ((ret  = SQLGetInfo(db->hdbc, SQL_DBMS_VER,
			   info, sizeof(info), &len)) == SQL_SUCCESS ||
	ret == SQL_SUCCESS_WITH_INFO)
      xv[n++] = pure_cstring_dup(info);
    else
      xv[n++] = pure_string_dup("");
    if ((ret  = SQLGetInfo(db->hdbc, SQL_DRIVER_NAME,
			   info, sizeof(info), &len)) == SQL_SUCCESS ||
	ret == SQL_SUCCESS_WITH_INFO)
      xv[n++] = pure_cstring_dup(info);
    else
      xv[n++] = pure_string_dup("");
    if ((ret  = SQLGetInfo(db->hdbc, SQL_DRIVER_VER,
			   info, sizeof(info), &len)) == SQL_SUCCESS ||
	ret == SQL_SUCCESS_WITH_INFO)
      xv[n++] = pure_cstring_dup(info);
    else
      xv[n++] = pure_string_dup("");
    if ((ret  = SQLGetInfo(db->hdbc, SQL_DRIVER_ODBC_VER,
			   info, sizeof(info), &len)) == SQL_SUCCESS ||
	ret == SQL_SUCCESS_WITH_INFO)
      xv[n++] = pure_cstring_dup(info);
    else
      xv[n++] = pure_string_dup("");
    if ((ret  = SQLGetInfo(db->hdbc, SQL_ODBC_VER,
			   info, sizeof(info), &len)) == SQL_SUCCESS ||
	ret == SQL_SUCCESS_WITH_INFO)
      xv[n++] = pure_cstring_dup(info);
    else
      xv[n++] = pure_string_dup("");
    res = pure_tuplev(n, xv);
    return res;
  } else
    return 0;
}

enum odbc_info_value_kind {
  ODBC_INFO_TEXT,
  ODBC_INFO_USMALLINT,
  ODBC_INFO_UINTEGER,
  ODBC_INFO_HANDLE
};

struct odbc_info_value_type {
  SQLUSMALLINT info_type;
  enum odbc_info_value_kind value_kind;
};

#define ODBC_INFO(type, kind) { type, kind }

/* The value kinds below follow the Windows ODBC SQLGetInfo documentation.
   The explicitly listed Y/N values are character strings, not numeric flags.
   Other unlisted info types remain textual for compatibility. */
static const struct odbc_info_value_type odbc_info_value_types[] = {
  ODBC_INFO(SQL_ACTIVE_CONNECTIONS, ODBC_INFO_USMALLINT),
  ODBC_INFO(SQL_ACTIVE_STATEMENTS, ODBC_INFO_USMALLINT),
  ODBC_INFO(SQL_ODBC_API_CONFORMANCE, ODBC_INFO_USMALLINT),
  ODBC_INFO(SQL_ODBC_SAG_CLI_CONFORMANCE, ODBC_INFO_USMALLINT),
  ODBC_INFO(SQL_ODBC_SQL_CONFORMANCE, ODBC_INFO_USMALLINT),
  ODBC_INFO(SQL_CONCAT_NULL_BEHAVIOR, ODBC_INFO_USMALLINT),
  ODBC_INFO(SQL_CURSOR_COMMIT_BEHAVIOR, ODBC_INFO_USMALLINT),
  ODBC_INFO(SQL_CURSOR_ROLLBACK_BEHAVIOR, ODBC_INFO_USMALLINT),
  ODBC_INFO(SQL_IDENTIFIER_CASE, ODBC_INFO_USMALLINT),
  ODBC_INFO(SQL_MAX_COLUMN_NAME_LEN, ODBC_INFO_USMALLINT),
  ODBC_INFO(SQL_MAX_CURSOR_NAME_LEN, ODBC_INFO_USMALLINT),
  ODBC_INFO(SQL_MAX_SCHEMA_NAME_LEN, ODBC_INFO_USMALLINT),
  ODBC_INFO(SQL_MAX_PROCEDURE_NAME_LEN, ODBC_INFO_USMALLINT),
  ODBC_INFO(SQL_MAX_CATALOG_NAME_LEN, ODBC_INFO_USMALLINT),
  ODBC_INFO(SQL_MAX_TABLE_NAME_LEN, ODBC_INFO_USMALLINT),
  ODBC_INFO(SQL_TXN_CAPABLE, ODBC_INFO_USMALLINT),
  ODBC_INFO(SQL_CORRELATION_NAME, ODBC_INFO_USMALLINT),
  ODBC_INFO(SQL_NON_NULLABLE_COLUMNS, ODBC_INFO_USMALLINT),
  ODBC_INFO(SQL_FILE_USAGE, ODBC_INFO_USMALLINT),
  ODBC_INFO(SQL_NULL_COLLATION, ODBC_INFO_USMALLINT),
  ODBC_INFO(SQL_GROUP_BY, ODBC_INFO_USMALLINT),
  ODBC_INFO(SQL_QUOTED_IDENTIFIER_CASE, ODBC_INFO_USMALLINT),
  ODBC_INFO(SQL_MAX_COLUMNS_IN_GROUP_BY, ODBC_INFO_USMALLINT),
  ODBC_INFO(SQL_MAX_COLUMNS_IN_INDEX, ODBC_INFO_USMALLINT),
  ODBC_INFO(SQL_MAX_COLUMNS_IN_ORDER_BY, ODBC_INFO_USMALLINT),
  ODBC_INFO(SQL_MAX_COLUMNS_IN_SELECT, ODBC_INFO_USMALLINT),
  ODBC_INFO(SQL_MAX_COLUMNS_IN_TABLE, ODBC_INFO_USMALLINT),
  ODBC_INFO(SQL_MAX_TABLES_IN_SELECT, ODBC_INFO_USMALLINT),
  ODBC_INFO(SQL_MAX_USER_NAME_LEN, ODBC_INFO_USMALLINT),
  ODBC_INFO(SQL_QUALIFIER_LOCATION, ODBC_INFO_USMALLINT),
  ODBC_INFO(SQL_ACTIVE_ENVIRONMENTS, ODBC_INFO_USMALLINT),
  ODBC_INFO(SQL_MAX_IDENTIFIER_LEN, ODBC_INFO_USMALLINT),

  ODBC_INFO(SQL_ROW_UPDATES, ODBC_INFO_TEXT),
  ODBC_INFO(SQL_ACCESSIBLE_TABLES, ODBC_INFO_TEXT),
  ODBC_INFO(SQL_ACCESSIBLE_PROCEDURES, ODBC_INFO_TEXT),
  ODBC_INFO(SQL_PROCEDURES, ODBC_INFO_TEXT),
  ODBC_INFO(SQL_EXPRESSIONS_IN_ORDERBY, ODBC_INFO_TEXT),
  ODBC_INFO(SQL_MULT_RESULT_SETS, ODBC_INFO_TEXT),
  ODBC_INFO(SQL_MULTIPLE_ACTIVE_TXN, ODBC_INFO_TEXT),
  ODBC_INFO(SQL_OUTER_JOINS, ODBC_INFO_TEXT),
  ODBC_INFO(SQL_COLUMN_ALIAS, ODBC_INFO_TEXT),
  ODBC_INFO(SQL_ORDER_BY_COLUMNS_IN_SELECT, ODBC_INFO_TEXT),
  ODBC_INFO(SQL_MAX_ROW_SIZE_INCLUDES_LONG, ODBC_INFO_TEXT),
  ODBC_INFO(SQL_NEED_LONG_DATA_LEN, ODBC_INFO_TEXT),
  ODBC_INFO(SQL_LIKE_ESCAPE_CLAUSE, ODBC_INFO_TEXT),
  ODBC_INFO(SQL_DESCRIBE_PARAMETER, ODBC_INFO_TEXT),
  ODBC_INFO(SQL_CATALOG_NAME, ODBC_INFO_TEXT),
  ODBC_INFO(SQL_XOPEN_CLI_YEAR, ODBC_INFO_TEXT),

  ODBC_INFO(SQL_FETCH_DIRECTION, ODBC_INFO_UINTEGER),
  ODBC_INFO(SQL_DEFAULT_TXN_ISOLATION, ODBC_INFO_UINTEGER),
  ODBC_INFO(SQL_SCROLL_CONCURRENCY, ODBC_INFO_UINTEGER),
  ODBC_INFO(SQL_SCROLL_OPTIONS, ODBC_INFO_UINTEGER),
  ODBC_INFO(SQL_CONVERT_FUNCTIONS, ODBC_INFO_UINTEGER),
  ODBC_INFO(SQL_NUMERIC_FUNCTIONS, ODBC_INFO_UINTEGER),
  ODBC_INFO(SQL_STRING_FUNCTIONS, ODBC_INFO_UINTEGER),
  ODBC_INFO(SQL_SYSTEM_FUNCTIONS, ODBC_INFO_UINTEGER),
  ODBC_INFO(SQL_TIMEDATE_FUNCTIONS, ODBC_INFO_UINTEGER),
  ODBC_INFO(SQL_CONVERT_BIGINT, ODBC_INFO_UINTEGER),
  ODBC_INFO(SQL_CONVERT_BINARY, ODBC_INFO_UINTEGER),
  ODBC_INFO(SQL_CONVERT_BIT, ODBC_INFO_UINTEGER),
  ODBC_INFO(SQL_CONVERT_CHAR, ODBC_INFO_UINTEGER),
  ODBC_INFO(SQL_CONVERT_DATE, ODBC_INFO_UINTEGER),
  ODBC_INFO(SQL_CONVERT_DECIMAL, ODBC_INFO_UINTEGER),
  ODBC_INFO(SQL_CONVERT_DOUBLE, ODBC_INFO_UINTEGER),
  ODBC_INFO(SQL_CONVERT_FLOAT, ODBC_INFO_UINTEGER),
  ODBC_INFO(SQL_CONVERT_INTEGER, ODBC_INFO_UINTEGER),
  ODBC_INFO(SQL_CONVERT_LONGVARCHAR, ODBC_INFO_UINTEGER),
  ODBC_INFO(SQL_CONVERT_NUMERIC, ODBC_INFO_UINTEGER),
  ODBC_INFO(SQL_CONVERT_REAL, ODBC_INFO_UINTEGER),
  ODBC_INFO(SQL_CONVERT_SMALLINT, ODBC_INFO_UINTEGER),
  ODBC_INFO(SQL_CONVERT_TIME, ODBC_INFO_UINTEGER),
  ODBC_INFO(SQL_CONVERT_TIMESTAMP, ODBC_INFO_UINTEGER),
  ODBC_INFO(SQL_CONVERT_TINYINT, ODBC_INFO_UINTEGER),
  ODBC_INFO(SQL_CONVERT_VARBINARY, ODBC_INFO_UINTEGER),
  ODBC_INFO(SQL_CONVERT_VARCHAR, ODBC_INFO_UINTEGER),
  ODBC_INFO(SQL_CONVERT_LONGVARBINARY, ODBC_INFO_UINTEGER),
  ODBC_INFO(SQL_TXN_ISOLATION_OPTION, ODBC_INFO_UINTEGER),
  ODBC_INFO(SQL_LOCK_TYPES, ODBC_INFO_UINTEGER),
  ODBC_INFO(SQL_POS_OPERATIONS, ODBC_INFO_UINTEGER),
  ODBC_INFO(SQL_POSITIONED_STATEMENTS, ODBC_INFO_UINTEGER),
  ODBC_INFO(SQL_GETDATA_EXTENSIONS, ODBC_INFO_UINTEGER),
  ODBC_INFO(SQL_BOOKMARK_PERSISTENCE, ODBC_INFO_UINTEGER),
  ODBC_INFO(SQL_STATIC_SENSITIVITY, ODBC_INFO_UINTEGER),
  ODBC_INFO(SQL_ALTER_TABLE, ODBC_INFO_UINTEGER),
  ODBC_INFO(SQL_OWNER_USAGE, ODBC_INFO_UINTEGER),
  ODBC_INFO(SQL_QUALIFIER_USAGE, ODBC_INFO_UINTEGER),
  ODBC_INFO(SQL_SUBQUERIES, ODBC_INFO_UINTEGER),
  ODBC_INFO(SQL_UNION, ODBC_INFO_UINTEGER),
  ODBC_INFO(SQL_MAX_INDEX_SIZE, ODBC_INFO_UINTEGER),
  ODBC_INFO(SQL_MAX_ROW_SIZE, ODBC_INFO_UINTEGER),
  ODBC_INFO(SQL_MAX_STATEMENT_LEN, ODBC_INFO_UINTEGER),
  ODBC_INFO(SQL_MAX_CHAR_LITERAL_LEN, ODBC_INFO_UINTEGER),
  ODBC_INFO(SQL_TIMEDATE_ADD_INTERVALS, ODBC_INFO_UINTEGER),
  ODBC_INFO(SQL_TIMEDATE_DIFF_INTERVALS, ODBC_INFO_UINTEGER),
  ODBC_INFO(SQL_MAX_BINARY_LITERAL_LEN, ODBC_INFO_UINTEGER),
  ODBC_INFO(SQL_OJ_CAPABILITIES, ODBC_INFO_UINTEGER),
  ODBC_INFO(SQL_ALTER_DOMAIN, ODBC_INFO_UINTEGER),
  ODBC_INFO(SQL_SQL_CONFORMANCE, ODBC_INFO_UINTEGER),
  ODBC_INFO(SQL_DATETIME_LITERALS, ODBC_INFO_UINTEGER),
  ODBC_INFO(SQL_BATCH_ROW_COUNT, ODBC_INFO_UINTEGER),
  ODBC_INFO(SQL_BATCH_SUPPORT, ODBC_INFO_UINTEGER),
  ODBC_INFO(SQL_CONVERT_WCHAR, ODBC_INFO_UINTEGER),
  ODBC_INFO(SQL_CONVERT_INTERVAL_DAY_TIME, ODBC_INFO_UINTEGER),
  ODBC_INFO(SQL_CONVERT_INTERVAL_YEAR_MONTH, ODBC_INFO_UINTEGER),
  ODBC_INFO(SQL_CONVERT_WLONGVARCHAR, ODBC_INFO_UINTEGER),
  ODBC_INFO(SQL_CONVERT_WVARCHAR, ODBC_INFO_UINTEGER),
  ODBC_INFO(SQL_CREATE_ASSERTION, ODBC_INFO_UINTEGER),
  ODBC_INFO(SQL_CREATE_CHARACTER_SET, ODBC_INFO_UINTEGER),
  ODBC_INFO(SQL_CREATE_COLLATION, ODBC_INFO_UINTEGER),
  ODBC_INFO(SQL_CREATE_DOMAIN, ODBC_INFO_UINTEGER),
  ODBC_INFO(SQL_CREATE_SCHEMA, ODBC_INFO_UINTEGER),
  ODBC_INFO(SQL_CREATE_TABLE, ODBC_INFO_UINTEGER),
  ODBC_INFO(SQL_CREATE_TRANSLATION, ODBC_INFO_UINTEGER),
  ODBC_INFO(SQL_CREATE_VIEW, ODBC_INFO_UINTEGER),
  ODBC_INFO(SQL_DROP_ASSERTION, ODBC_INFO_UINTEGER),
  ODBC_INFO(SQL_DROP_CHARACTER_SET, ODBC_INFO_UINTEGER),
  ODBC_INFO(SQL_DROP_COLLATION, ODBC_INFO_UINTEGER),
  ODBC_INFO(SQL_DROP_DOMAIN, ODBC_INFO_UINTEGER),
  ODBC_INFO(SQL_DROP_SCHEMA, ODBC_INFO_UINTEGER),
  ODBC_INFO(SQL_DROP_TABLE, ODBC_INFO_UINTEGER),
  ODBC_INFO(SQL_DROP_TRANSLATION, ODBC_INFO_UINTEGER),
  ODBC_INFO(SQL_DROP_VIEW, ODBC_INFO_UINTEGER),
  ODBC_INFO(SQL_DYNAMIC_CURSOR_ATTRIBUTES1, ODBC_INFO_UINTEGER),
  ODBC_INFO(SQL_DYNAMIC_CURSOR_ATTRIBUTES2, ODBC_INFO_UINTEGER),
  ODBC_INFO(SQL_FORWARD_ONLY_CURSOR_ATTRIBUTES1, ODBC_INFO_UINTEGER),
  ODBC_INFO(SQL_FORWARD_ONLY_CURSOR_ATTRIBUTES2, ODBC_INFO_UINTEGER),
  ODBC_INFO(SQL_INDEX_KEYWORDS, ODBC_INFO_UINTEGER),
  ODBC_INFO(SQL_INFO_SCHEMA_VIEWS, ODBC_INFO_UINTEGER),
  ODBC_INFO(SQL_KEYSET_CURSOR_ATTRIBUTES1, ODBC_INFO_UINTEGER),
  ODBC_INFO(SQL_KEYSET_CURSOR_ATTRIBUTES2, ODBC_INFO_UINTEGER),
  ODBC_INFO(SQL_ODBC_INTERFACE_CONFORMANCE, ODBC_INFO_UINTEGER),
  ODBC_INFO(SQL_PARAM_ARRAY_ROW_COUNTS, ODBC_INFO_UINTEGER),
  ODBC_INFO(SQL_PARAM_ARRAY_SELECTS, ODBC_INFO_UINTEGER),
  ODBC_INFO(SQL_SQL92_DATETIME_FUNCTIONS, ODBC_INFO_UINTEGER),
  ODBC_INFO(SQL_SQL92_FOREIGN_KEY_DELETE_RULE, ODBC_INFO_UINTEGER),
  ODBC_INFO(SQL_SQL92_FOREIGN_KEY_UPDATE_RULE, ODBC_INFO_UINTEGER),
  ODBC_INFO(SQL_SQL92_GRANT, ODBC_INFO_UINTEGER),
  ODBC_INFO(SQL_SQL92_NUMERIC_VALUE_FUNCTIONS, ODBC_INFO_UINTEGER),
  ODBC_INFO(SQL_SQL92_PREDICATES, ODBC_INFO_UINTEGER),
  ODBC_INFO(SQL_SQL92_RELATIONAL_JOIN_OPERATORS, ODBC_INFO_UINTEGER),
  ODBC_INFO(SQL_SQL92_REVOKE, ODBC_INFO_UINTEGER),
  ODBC_INFO(SQL_SQL92_ROW_VALUE_CONSTRUCTOR, ODBC_INFO_UINTEGER),
  ODBC_INFO(SQL_SQL92_STRING_FUNCTIONS, ODBC_INFO_UINTEGER),
  ODBC_INFO(SQL_SQL92_VALUE_EXPRESSIONS, ODBC_INFO_UINTEGER),
  ODBC_INFO(SQL_STANDARD_CLI_CONFORMANCE, ODBC_INFO_UINTEGER),
  ODBC_INFO(SQL_STATIC_CURSOR_ATTRIBUTES1, ODBC_INFO_UINTEGER),
  ODBC_INFO(SQL_STATIC_CURSOR_ATTRIBUTES2, ODBC_INFO_UINTEGER),
  ODBC_INFO(SQL_AGGREGATE_FUNCTIONS, ODBC_INFO_UINTEGER),
  ODBC_INFO(SQL_DDL_INDEX, ODBC_INFO_UINTEGER),
  ODBC_INFO(SQL_INSERT_STATEMENT, ODBC_INFO_UINTEGER),
  ODBC_INFO(SQL_CONVERT_GUID, ODBC_INFO_UINTEGER),
  ODBC_INFO(SQL_CURSOR_SENSITIVITY, ODBC_INFO_UINTEGER),
  ODBC_INFO(SQL_ASYNC_MODE, ODBC_INFO_UINTEGER),
  ODBC_INFO(SQL_MAX_ASYNC_CONCURRENT_STATEMENTS, ODBC_INFO_UINTEGER),
  ODBC_INFO(SQL_DRIVER_AWARE_POOLING_SUPPORTED, ODBC_INFO_UINTEGER),
#if (ODBCVER >= 0x0380)
  ODBC_INFO(SQL_ASYNC_DBC_FUNCTIONS, ODBC_INFO_UINTEGER),
  ODBC_INFO(SQL_ASYNC_NOTIFICATION, ODBC_INFO_UINTEGER),
#endif

  ODBC_INFO(SQL_DRIVER_HDBC, ODBC_INFO_HANDLE),
  ODBC_INFO(SQL_DRIVER_HENV, ODBC_INFO_HANDLE),
  ODBC_INFO(SQL_DRIVER_HSTMT, ODBC_INFO_HANDLE),
  ODBC_INFO(SQL_DRIVER_HLIB, ODBC_INFO_HANDLE),
  ODBC_INFO(SQL_DRIVER_HDESC, ODBC_INFO_HANDLE)
};

#undef ODBC_INFO

static enum odbc_info_value_kind odbc_info_value_kind(SQLUSMALLINT info_type)
{
  size_t i;

  for (i = 0; i < sizeof(odbc_info_value_types) /
                  sizeof(odbc_info_value_types[0]); ++i) {
    if (odbc_info_value_types[i].info_type == info_type)
      return odbc_info_value_types[i].value_kind;
  }
  return ODBC_INFO_TEXT;
}

static pure_expr *odbc_getinfo_numeric(ODBCHandle *db, SQLUSMALLINT info_type,
                                       size_t value_size)
{
  SQLSMALLINT length = 0;
  SQLRETURN ret;
  unsigned char *buf = (unsigned char *)malloc(value_size);

  if (!buf)
    return pure_err_internal("insufficient memory");
  ret = SQLGetInfo(db->hdbc, info_type, buf, (SQLSMALLINT)value_size, &length);
  if (!SQL_SUCCEEDED(ret)) {
    free(buf);
    return pure_err(db->henv, db->hdbc, 0);
  }
  return pure_sentry(pure_symbol(pure_sym("free")), pure_pointer(buf));
}

static pure_expr *odbc_getinfo_handle(ODBCHandle *db, SQLUSMALLINT info_type)
{
  SQLHANDLE value;
  SQLSMALLINT length = 0;
  SQLRETURN ret;
  unsigned char *buf;

  if (info_type == SQL_DRIVER_HDESC)
    return pure_err_internal("SQL_DRIVER_HDESC requires a descriptor handle");
  switch (info_type) {
  case SQL_DRIVER_HENV:
    value = db->henv;
    break;
  case SQL_DRIVER_HDBC:
    value = db->hdbc;
    break;
  case SQL_DRIVER_HSTMT:
    value = db->hstmt;
    break;
  default:
    value = SQL_NULL_HANDLE;
    break;
  }
  ret = SQLGetInfo(db->hdbc, info_type, &value, sizeof(value), &length);
  if (!SQL_SUCCEEDED(ret))
    return pure_err(db->henv, db->hdbc, 0);
  if (!(buf = (unsigned char *)malloc(sizeof(value))))
    return pure_err_internal("insufficient memory");
  memcpy(buf, &value, sizeof(value));
  return pure_sentry(pure_symbol(pure_sym("free")), pure_pointer(buf));
}

static pure_expr *odbc_getinfo_text(ODBCHandle *db, SQLUSMALLINT info_type)
{
  char info[1024] = {0};
  SQLSMALLINT length = 0;
  SQLRETURN ret;
  unsigned char *buf;
  size_t buffer_size;

  ret = SQLGetInfo(db->hdbc, info_type, info, sizeof(info), &length);
  if (!SQL_SUCCEEDED(ret))
    return pure_err(db->henv, db->hdbc, 0);
  if (length < 0 || length == SQL_NO_TOTAL)
    return pure_err(db->henv, db->hdbc, 0);
  if ((size_t)length < sizeof(info)) {
    buffer_size = (size_t)length + 1;
    if (!(buf = (unsigned char *)malloc(buffer_size)))
      return pure_err_internal("insufficient memory");
    memcpy(buf, info, (size_t)length);
  } else {
    if ((size_t)length >= (size_t)SHRT_MAX)
      return pure_err(db->henv, db->hdbc, 0);
    buffer_size = (size_t)length + 1;
    if (!(buf = (unsigned char *)malloc(buffer_size)))
      return pure_err_internal("insufficient memory");
    ret = SQLGetInfo(db->hdbc, info_type, buf, (SQLSMALLINT)buffer_size,
                     &length);
    if (!SQL_SUCCEEDED(ret) || length < 0 ||
        (size_t)length >= buffer_size) {
      free(buf);
      return pure_err(db->henv, db->hdbc, 0);
    }
  }
  buf[length] = 0;
  return pure_sentry(pure_symbol(pure_sym("free")), pure_pointer(buf));
}

pure_expr *odbc_getinfo(pure_expr *dbx, unsigned int info_type)
{
  ODBCHandle *db;
  if (is_db_pointer(dbx, &db)) {
    switch (odbc_info_value_kind((SQLUSMALLINT)info_type)) {
    case ODBC_INFO_USMALLINT:
      return odbc_getinfo_numeric(db, (SQLUSMALLINT)info_type,
                                  sizeof(SQLUSMALLINT));
    case ODBC_INFO_UINTEGER:
      return odbc_getinfo_numeric(db, (SQLUSMALLINT)info_type,
                                  sizeof(SQLUINTEGER));
    case ODBC_INFO_HANDLE:
      return odbc_getinfo_handle(db, (SQLUSMALLINT)info_type);
    default:
      return odbc_getinfo_text(db, (SQLUSMALLINT)info_type);
    }
  } else
    return 0;
}

/* Number of entries in SQLGetTypeInfo() result set. Table entries are
   allocated in chunks of this value. */
#define NMAX 128

/* Maximum length of string values. */
#define SL 256

#define checkstr(s,l) ((l==SQL_NULL_DATA)?pure_sqlnull():pure_cstring_dup((char*)s))
#define checkint(x,l) ((l==SQL_NULL_DATA)?pure_sqlnull():pure_int(x))
#define checkuint(x,l) ((l==SQL_NULL_DATA)?pure_sqlnull(): \
  ((x) <= (SQLUINTEGER)INT32_MAX ? pure_int((int32_t)(x)) : \
   pure_int64((int64_t)(x))))
#define checkbool(x,l) ((l==SQL_NULL_DATA)?pure_sqlnull():pure_int(x))

static bool odbc_bind_col(ODBCHandle *db, SQLUSMALLINT column,
                          SQLSMALLINT target_type, SQLPOINTER target,
                          SQLLEN buffer_length, SQLLEN *length)
{
  return SQL_SUCCEEDED(SQLBindCol(db->hstmt, column, target_type, target,
                                  buffer_length, length));
}

pure_expr *odbc_typeinfo(pure_expr *dbx, int id)
{
  ODBCHandle *db;
  if (is_db_pointer(dbx, &db)) {
    pure_expr *res, **xs = (pure_expr**)malloc(NMAX*sizeof(pure_expr*));
    size_t i, n = 0, m = NMAX;

    UCHAR  name[SL], prefix[SL], suffix[SL], params[SL], local_name[SL];
    SQLSMALLINT type, nullable, case_sen, searchable, unsign, money, auto_inc;
    SQLSMALLINT min_scale, max_scale;
    SQLUINTEGER prec;
    SQLLEN len[20];
    SQLRETURN ret;
    SQLSMALLINT sql_type, subcode, intv_prec;
    SQLUINTEGER prec_radix;

    if (!xs) return pure_err_internal("insufficient memory");
    if (id < SHRT_MIN || id > SHRT_MAX) {
      free(xs);
      return pure_err_internal("invalid SQL data type");
    }
    sql_close(db);

    if (!odbc_bind_col(db, 1, SQL_C_CHAR, name, SL, &len[1]) ||
        !odbc_bind_col(db, 2, SQL_C_SHORT, &type, 0, &len[2]) ||
        !odbc_bind_col(db, 3, SQL_C_LONG, &prec, 0, &len[3]) ||
        !odbc_bind_col(db, 4, SQL_C_CHAR, prefix, SL, &len[4]) ||
        !odbc_bind_col(db, 5, SQL_C_CHAR, suffix, SL, &len[5]) ||
        !odbc_bind_col(db, 6, SQL_C_CHAR, params, SL, &len[6]) ||
        !odbc_bind_col(db, 7, SQL_C_SHORT, &nullable, 0, &len[7]) ||
        !odbc_bind_col(db, 8, SQL_C_SHORT, &case_sen, 0, &len[8]) ||
        !odbc_bind_col(db, 9, SQL_C_SHORT, &searchable, 0, &len[9]) ||
        !odbc_bind_col(db, 10, SQL_C_SHORT, &unsign, 0, &len[10]) ||
        !odbc_bind_col(db, 11, SQL_C_SHORT, &money, 0, &len[11]) ||
        !odbc_bind_col(db, 12, SQL_C_SHORT, &auto_inc, 0, &len[12]) ||
        !odbc_bind_col(db, 13, SQL_C_CHAR, local_name, SL, &len[13]) ||
        !odbc_bind_col(db, 14, SQL_C_SHORT, &min_scale, 0, &len[14]) ||
        !odbc_bind_col(db, 15, SQL_C_SHORT, &max_scale, 0, &len[15]) ||
        !odbc_bind_col(db, 16, SQL_C_SHORT, &sql_type, 0, &len[16]) ||
        !odbc_bind_col(db, 17, SQL_C_SHORT, &subcode, 0, &len[17]) ||
        !odbc_bind_col(db, 18, SQL_C_LONG, &prec_radix, 0, &len[18]) ||
        !odbc_bind_col(db, 19, SQL_C_SHORT, &intv_prec, 0, &len[19]))
      goto err;

    ret = SQLGetTypeInfo(db->hstmt, (SQLSMALLINT)id);
    if (ret != SQL_SUCCESS && ret != SQL_SUCCESS_WITH_INFO) goto err;

    do {
      ret = SQLFetch(db->hstmt);
      switch (ret) {
       case SQL_SUCCESS_WITH_INFO:
       case SQL_SUCCESS:
	 if (n >= m && !grow_expression_vector(&xs, &m, n + 1))
	   goto fatal;
	 xs[n++] = pure_tuplel(19,
			       checkstr(name, len[1]),
			       checkint(type, len[2]),
			       checkuint(prec, len[3]),
			       checkstr(prefix, len[4]),
			       checkstr(suffix, len[5]),
			       checkstr(params, len[6]),
			       checkint(nullable, len[7]),
			       checkbool(case_sen, len[8]),
			       checkint(searchable, len[9]),
			       checkbool(unsign, len[10]),
			       checkbool(money, len[11]),
			       checkbool(auto_inc, len[12]),
			       checkstr(local_name, len[13]),
			       checkint(min_scale, len[14]),
			       checkint(max_scale, len[15]),
			       checkint(sql_type, len[16]),
			       checkint(subcode, len[17]),
			       checkuint(prec_radix, len[18]),
			       checkint(intv_prec, len[19]));
	 break;
       case SQL_NO_DATA_FOUND:
	 break;
      default:
	goto err;
      }
    } while (ret != SQL_NO_DATA_FOUND);
    SQLFreeStmt(db->hstmt, SQL_UNBIND);
    SQLFreeStmt(db->hstmt, SQL_CLOSE);
    if (n == 0) {
      free(xs);
      return pure_listl(0);
    } else {
      res = pure_listv(n, xs);
      free(xs);
      return res;
      }
  err:
    for (i = 0; i < n; i++) pure_freenew(xs[i]);
    free(xs);
    res = pure_err(db->henv, db->hdbc, db->hstmt);
    SQLFreeStmt(db->hstmt, SQL_UNBIND);
    SQLFreeStmt(db->hstmt, SQL_CLOSE);
    return res;
  fatal:
    for (i = 0; i < n; i++) pure_freenew(xs[i]);
    free(xs);
    SQLFreeStmt(db->hstmt, SQL_UNBIND);
    SQLFreeStmt(db->hstmt, SQL_CLOSE);
    return pure_err_internal("insufficient memory");
  } else
    return 0;
}

pure_expr *odbc_tables(pure_expr *dbx)
{
  ODBCHandle *db;
  if (is_db_pointer(dbx, &db)) {
    pure_expr *res, **xs = (pure_expr**)malloc(NMAX*sizeof(pure_expr*));
    size_t i, n = 0, m = NMAX;

    UCHAR  name[SL], type[SL];
    SQLLEN len[6];
    SQLRETURN ret;

    if (!xs) return pure_err_internal("insufficient memory");
    sql_close(db);

    if (!odbc_bind_col(db, 3, SQL_C_CHAR, name, SL, &len[3]) ||
        !odbc_bind_col(db, 4, SQL_C_CHAR, type, SL, &len[4]))
      goto err;

    ret = SQLTables(db->hstmt, NULL, 0, NULL, 0, NULL, 0, NULL, 0);
    if (ret != SQL_SUCCESS && ret != SQL_SUCCESS_WITH_INFO) goto err;

    do {
      ret = SQLFetch(db->hstmt);
      switch (ret) {
       case SQL_SUCCESS_WITH_INFO:
       case SQL_SUCCESS:
	 if (n >= m && !grow_expression_vector(&xs, &m, n + 1))
	   goto fatal;
	 xs[n++] = pure_tuplel(2,
			       checkstr(name, len[3]),
			       checkstr(type, len[4]));
	 break;
       case SQL_NO_DATA_FOUND:
	 break;
      default:
	goto err;
      }
    } while (ret != SQL_NO_DATA_FOUND);
    SQLFreeStmt(db->hstmt, SQL_UNBIND);
    SQLFreeStmt(db->hstmt, SQL_CLOSE);
    if (n == 0) {
      free(xs);
      return pure_listl(0);
    } else {
      res = pure_listv(n, xs);
      free(xs);
      return res;
      }
  err:
    for (i = 0; i < n; i++) pure_freenew(xs[i]);
    free(xs);
    res = pure_err(db->henv, db->hdbc, db->hstmt);
    SQLFreeStmt(db->hstmt, SQL_UNBIND);
    SQLFreeStmt(db->hstmt, SQL_CLOSE);
    return res;
  fatal:
    for (i = 0; i < n; i++) pure_freenew(xs[i]);
    free(xs);
    SQLFreeStmt(db->hstmt, SQL_UNBIND);
    SQLFreeStmt(db->hstmt, SQL_CLOSE);
    return pure_err_internal("insufficient memory");
  } else
    return 0;
}

pure_expr *odbc_columns(pure_expr *dbx, const char *tab)
{
  ODBCHandle *db;
  if (is_db_pointer(dbx, &db)) {
    pure_expr *res, **xs = (pure_expr**)malloc(NMAX*sizeof(pure_expr*));
    size_t i, n = 0, m = NMAX;

    UCHAR  name[SL], type[SL], nullable[SL], deflt[SL];
    SQLLEN len[19];
    SQLRETURN ret;

    if (!xs) return pure_err_internal("insufficient memory");
    if (!tab) {
      free(xs);
      return pure_err_internal("invalid table name string");
    }
    sql_close(db);

    if (!odbc_bind_col(db, 4, SQL_C_CHAR, name, SL, &len[4]) ||
        !odbc_bind_col(db, 6, SQL_C_CHAR, type, SL, &len[6]) ||
        !odbc_bind_col(db, 13, SQL_C_CHAR, deflt, SL, &len[13]) ||
        !odbc_bind_col(db, 18, SQL_C_CHAR, nullable, SL, &len[18]))
      goto err;

    ret = SQLColumns(db->hstmt, NULL, 0, NULL, 0, (SQLCHAR*)tab, SQL_NTS,
		     NULL, 0);
    if (ret != SQL_SUCCESS && ret != SQL_SUCCESS_WITH_INFO) goto err;

    do {
      ret = SQLFetch(db->hstmt);
      switch (ret) {
       case SQL_SUCCESS_WITH_INFO:
       case SQL_SUCCESS:
	 if (n >= m && !grow_expression_vector(&xs, &m, n + 1))
	   goto fatal;
	 xs[n++] = pure_tuplel(4,
			       checkstr(name, len[4]),
			       checkstr(type, len[6]),
			       checkstr(nullable, len[18]),
			       checkstr(deflt, len[13]));
	 break;
       case SQL_NO_DATA_FOUND:
	 break;
      default:
	goto err;
      }
    } while (ret != SQL_NO_DATA_FOUND);
    SQLFreeStmt(db->hstmt, SQL_UNBIND);
    SQLFreeStmt(db->hstmt, SQL_CLOSE);
    if (n == 0) {
      free(xs);
      return pure_listl(0);
    } else {
      res = pure_listv(n, xs);
      free(xs);
      return res;
      }
  err:
    for (i = 0; i < n; i++) pure_freenew(xs[i]);
    free(xs);
    res = pure_err(db->henv, db->hdbc, db->hstmt);
    SQLFreeStmt(db->hstmt, SQL_UNBIND);
    SQLFreeStmt(db->hstmt, SQL_CLOSE);
    return res;
  fatal:
    for (i = 0; i < n; i++) pure_freenew(xs[i]);
    free(xs);
    SQLFreeStmt(db->hstmt, SQL_UNBIND);
    SQLFreeStmt(db->hstmt, SQL_CLOSE);
    return pure_err_internal("insufficient memory");
  } else
    return 0;
}

pure_expr *odbc_primary_keys(pure_expr *dbx, const char *tab)
{
  ODBCHandle *db;
  if (is_db_pointer(dbx, &db)) {
    pure_expr *res, **xs = (pure_expr**)malloc(NMAX*sizeof(pure_expr*));
    size_t i, n = 0, m = NMAX;

    UCHAR  name[SL];
    SQLLEN len[5];
    SQLRETURN ret;

    if (!xs) return pure_err_internal("insufficient memory");
    if (!tab) {
      free(xs);
      return pure_err_internal("invalid table name string");
    }
    sql_close(db);

    if (!odbc_bind_col(db, 4, SQL_C_CHAR, name, SL, &len[4]))
      goto err;

    ret = SQLPrimaryKeys(db->hstmt, NULL, 0, NULL, 0, (SQLCHAR*)tab, SQL_NTS);
    if (ret != SQL_SUCCESS && ret != SQL_SUCCESS_WITH_INFO) goto err;

    do {
      ret = SQLFetch(db->hstmt);
      switch (ret) {
       case SQL_SUCCESS_WITH_INFO:
       case SQL_SUCCESS:
	 if (n >= m && !grow_expression_vector(&xs, &m, n + 1))
	   goto fatal;
	 xs[n++] = checkstr(name, len[4]);
	 break;
       case SQL_NO_DATA_FOUND:
	 break;
      default:
	goto err;
      }
    } while (ret != SQL_NO_DATA_FOUND);
    SQLFreeStmt(db->hstmt, SQL_UNBIND);
    SQLFreeStmt(db->hstmt, SQL_CLOSE);
    if (n == 0) {
      free(xs);
      return pure_listl(0);
    } else {
      res = pure_listv(n, xs);
      free(xs);
      return res;
      }
  err:
    for (i = 0; i < n; i++) pure_freenew(xs[i]);
    free(xs);
    res = pure_err(db->henv, db->hdbc, db->hstmt);
    SQLFreeStmt(db->hstmt, SQL_UNBIND);
    SQLFreeStmt(db->hstmt, SQL_CLOSE);
    return res;
  fatal:
    for (i = 0; i < n; i++) pure_freenew(xs[i]);
    free(xs);
    SQLFreeStmt(db->hstmt, SQL_UNBIND);
    SQLFreeStmt(db->hstmt, SQL_CLOSE);
    return pure_err_internal("insufficient memory");
  } else
    return 0;
}

pure_expr *odbc_foreign_keys(pure_expr *dbx, const char *tab)
{
  ODBCHandle *db;
  if (is_db_pointer(dbx, &db)) {
    pure_expr *res, **xs = (pure_expr**)malloc(NMAX*sizeof(pure_expr*));
    size_t i, n = 0, m = NMAX;

    UCHAR  name[SL], pktabname[SL], pkname[SL];
    SQLLEN len[9];
    SQLRETURN ret;

    if (!xs) return pure_err_internal("insufficient memory");
    if (!tab) {
      free(xs);
      return pure_err_internal("invalid table name string");
    }
    sql_close(db);

    if (!odbc_bind_col(db, 3, SQL_C_CHAR, pktabname, SL, &len[3]) ||
        !odbc_bind_col(db, 4, SQL_C_CHAR, pkname, SL, &len[4]) ||
        !odbc_bind_col(db, 8, SQL_C_CHAR, name, SL, &len[8]))
      goto err;

    ret = SQLForeignKeys(db->hstmt, NULL, 0, NULL, 0, NULL, 0, NULL, 0,
			 NULL, 0, (SQLCHAR*)tab, SQL_NTS);
    if (ret != SQL_SUCCESS && ret != SQL_SUCCESS_WITH_INFO) goto err;

    do {
      ret = SQLFetch(db->hstmt);
      switch (ret) {
       case SQL_SUCCESS_WITH_INFO:
       case SQL_SUCCESS:
	 if (n >= m && !grow_expression_vector(&xs, &m, n + 1))
	   goto fatal;
	 xs[n++] = pure_tuplel(3,
			       checkstr(name, len[8]),
			       checkstr(pktabname, len[3]),
			       checkstr(pkname, len[4]));
	 break;
       case SQL_NO_DATA_FOUND:
	 break;
      default:
	goto err;
      }
    } while (ret != SQL_NO_DATA_FOUND);
    SQLFreeStmt(db->hstmt, SQL_UNBIND);
    SQLFreeStmt(db->hstmt, SQL_CLOSE);
    if (n == 0) {
      free(xs);
      return pure_listl(0);
    } else {
      res = pure_listv(n, xs);
      free(xs);
      return res;
      }
  err:
    for (i = 0; i < n; i++) pure_freenew(xs[i]);
    free(xs);
    res = pure_err(db->henv, db->hdbc, db->hstmt);
    SQLFreeStmt(db->hstmt, SQL_UNBIND);
    SQLFreeStmt(db->hstmt, SQL_CLOSE);
    return res;
  fatal:
    for (i = 0; i < n; i++) pure_freenew(xs[i]);
    free(xs);
    SQLFreeStmt(db->hstmt, SQL_UNBIND);
    SQLFreeStmt(db->hstmt, SQL_CLOSE);
    return pure_err_internal("insufficient memory");
  } else
    return 0;
}

#define BUFSZ 65536
#define BUFSZ2 5000

static pure_expr *pure_odbc_integer(SQLLEN value)
{
  if (value >= (SQLLEN)INT32_MIN && value <= (SQLLEN)INT32_MAX)
    return pure_int((int32_t)value);
  return pure_int64((int64_t)value);
}

pure_expr *odbc_sql_exec(pure_expr *dbx, const char *query, pure_expr *args)
{
  ODBCHandle *db;
  pure_expr **xv = NULL;
  size_t n = 0;
  if (is_db_pointer(dbx, &db) && pure_is_listv(args, &n, &xv)) {
    SQLRETURN ret;
    pure_expr *res = NULL, **xs = NULL;
    size_t i;
    size_t xs_count = 0;
    SQLSMALLINT cols = 0, *coltype = NULL;
    char buf[BUFSZ2];
    bool statement_started = false;
    bool operation_succeeded = false;
    /* finalize previous query */
    sql_close(db);
    /* prepare statement */
    if (!query) {
      res = pure_err_internal("invalid query string");
      goto cleanup;
    }
    statement_started = true;
    if ((ret = SQLPrepare(db->hstmt, (SQLCHAR*)query, SQL_NTS))
	!= SQL_SUCCESS &&
	ret != SQL_SUCCESS_WITH_INFO) {
      res = pure_err(db->henv, db->hdbc, db->hstmt);
      goto cleanup;
    }
    /* bind parameters */
    if (n > 0) {
      if (n > (size_t)USHRT_MAX) {
	res = pure_err_internal("too many parameters");
	goto cleanup;
      }
      if (!init_args(db, n)) {
	res = pure_err_internal("insufficient memory");
	goto cleanup;
      }
      for (i = 0; i < n; i++) {
	if (!set_arg(db, i, xv[i])) {
	  int alloc_error =
	    (db->argv[i].type == SQL_BIGINT ||
	     db->argv[i].type == SQL_CHAR ||
	     db->argv[i].type == SQL_BINARY) &&
	    !db->argv[i].data.buf;
	  res = alloc_error ? pure_err_internal("insufficient memory") : NULL;
	  goto cleanup;
	}
      }
    }
    for (i = 0; i < db->argc; i++) {
      SQLUSMALLINT parameter_number = (SQLUSMALLINT)(i + 1);

      if ((ret = SQLBindParameter(db->hstmt, parameter_number, SQL_PARAM_INPUT,
				  db->argv[i].ctype,
				  db->argv[i].type,
				  db->argv[i].prec, 0,
				  db->argv[i].ptr,
				  db->argv[i].buflen,
				  &db->argv[i].len)) != SQL_SUCCESS &&
	  ret != SQL_SUCCESS_WITH_INFO) {
	res = pure_err(db->henv, db->hdbc, db->hstmt);
	goto cleanup;
      }
    }
    /* execute statement */
    if ((ret = SQLExecute(db->hstmt)) != SQL_SUCCESS &&
	ret != SQL_SUCCESS_WITH_INFO) {
      res = pure_err(db->henv, db->hdbc, db->hstmt);
      goto cleanup;
    }
    /* determine the number of columns */
    if ((ret = SQLNumResultCols(db->hstmt, &cols)) != SQL_SUCCESS &&
	ret != SQL_SUCCESS_WITH_INFO) {
      res = pure_err(db->henv, db->hdbc, db->hstmt);
      goto cleanup;
    }
    if (cols == 0) {
      SQLLEN rows;
      if ((ret = SQLRowCount(db->hstmt, &rows)) == SQL_SUCCESS ||
	  ret == SQL_SUCCESS_WITH_INFO)
	res = pure_odbc_integer(rows);
      else
	res = pure_int(0);
      db->exec = 1;
      operation_succeeded = true;
      goto cleanup;
    }
    /* get the column names and types */
    {
      size_t column_count;
      size_t coltype_bytes;
      size_t expression_bytes;

      if (cols < 0) {
        res = pure_err_internal("invalid result column count");
        goto cleanup;
      }
      column_count = (size_t)cols;
      if (!checked_multiply(column_count, sizeof(SQLSMALLINT),
                            &coltype_bytes) ||
          !checked_multiply(column_count, sizeof(pure_expr *),
                            &expression_bytes) ||
          !(coltype = (SQLSMALLINT *)malloc(coltype_bytes)) ||
          !(xs = (pure_expr **)malloc(expression_bytes))) {
        res = pure_err_internal("insufficient memory");
        goto cleanup;
      }
    }
    for (i = 0; i < (size_t)cols; i++) {
      buf[0] = 0;

      if ((ret = SQLDescribeCol(db->hstmt, (SQLUSMALLINT)(i + 1),
                                (SQLCHAR*)buf, (SQLSMALLINT)sizeof(buf),
				NULL, &coltype[i], NULL, NULL, NULL))
	  != SQL_SUCCESS &&
	  ret != SQL_SUCCESS_WITH_INFO) {
	res = pure_err(db->henv, db->hdbc, db->hstmt);
	goto cleanup;
      }
      xs[i] = pure_cstring_dup(buf);
      if (!xs[i]) {
	res = pure_err_internal("insufficient memory");
	goto cleanup;
      }
      xs_count = i+1;
    }
    res = pure_listv((size_t)cols, xs);
    if (res) {
      SQLSMALLINT *old_coltype = db->coltype;

      xs_count = 0;
      if (old_coltype)
	free(old_coltype);
      db->coltype = coltype;
      coltype = NULL;
      db->cols = cols;
      db->exec = 1;
      operation_succeeded = true;
    }
  cleanup:
    if (xs) {
      for (i = 0; i < xs_count; i++)
	pure_freenew(xs[i]);
      free(xs);
    }
    if (xv) free(xv);
    if (coltype) free(coltype);
    if (!operation_succeeded && statement_started) {
      free_args(db);
      SQLFreeStmt(db->hstmt, SQL_CLOSE);
      db->coltype = NULL;
      db->cols = 0;
      db->exec = 0;
    }
    return res;
  } else
    return 0;
}

pure_expr *odbc_sql_fetch(pure_expr *dbx)
{
  ODBCHandle *db;
  if (is_db_pointer(dbx, &db) && db->coltype) {
    SQLRETURN ret;
    pure_expr *res, **xs;
    size_t i, j, cols, sz = BUFSZ;
    size_t xs_bytes;
    SQLSMALLINT *coltype = db->coltype;
    SQLINTEGER iv;
    double fv;
    char *buf = malloc(sz);
    SQLLEN len;
    if (db->cols <= 0 ||
        !checked_multiply((size_t)db->cols, sizeof(pure_expr *), &xs_bytes))
      goto fatal;
    cols = (size_t)db->cols;
    if (!buf) goto fatal;
    /* fetch the next record */
    if ((ret = SQLFetch(db->hstmt)) == SQL_NO_DATA_FOUND) {
      res = 0;
      goto exit;
    } else if (ret != SQL_SUCCESS && ret != SQL_SUCCESS_WITH_INFO)
      goto err;
    if (!(xs = malloc(xs_bytes)))
      goto fatal;
    /* get the columns */
    for (i = 0; i < cols; i++) {
      SQLUSMALLINT column = (SQLUSMALLINT)(i + 1);

      switch (coltype[i]) {
      case SQL_BIT:
      case SQL_TINYINT:
      case SQL_SMALLINT:
      case SQL_INTEGER:
	ret = SQLGetData(db->hstmt, column, SQL_INTEGER, &iv,
                         (SQLLEN)sizeof(iv), &len);
	if (!SQL_SUCCEEDED(ret))
	  goto err2;
	if (len == SQL_NULL_DATA)
	  xs[i] = pure_sqlnull();
	else
	  xs[i] = pure_int(iv);
	break;
      case SQL_BIGINT:
	/* hack to get bigint values converted to mpz_t, without having to
	   fiddle around with long long values
	   FIXME: we should really avoid the string conversion here */
	ret = SQLGetData(db->hstmt, column, SQL_CHAR, buf, (SQLLEN)sz, &len);
	if (!SQL_SUCCEEDED(ret))
	  goto err2;
	if (len == SQL_NULL_DATA)
	  xs[i] = pure_sqlnull();
	else {
	  mpz_t z;
	  mpz_init(z);
	  mpz_set_str(z, buf, 0);
	  xs[i] = pure_mpz(z);
	  mpz_clear(z);
	}
	break;
      case SQL_DOUBLE:
      case SQL_DECIMAL:
      case SQL_NUMERIC:
      case SQL_FLOAT:
      case SQL_REAL:
	ret = SQLGetData(db->hstmt, column, SQL_DOUBLE, &fv,
                         (SQLLEN)sizeof(fv), &len);
	if (!SQL_SUCCEEDED(ret))
	  goto err2;
	if (len == SQL_NULL_DATA)
	  xs[i] = pure_sqlnull();
	else
	  xs[i] = pure_double(fv);
	break;
      case SQL_BINARY:
      case SQL_VARBINARY:
      case SQL_LONGVARBINARY: {
	char *bufp = buf;
	size_t total = 0;
	SQLLEN actsz = (SQLLEN)sz;
	bool is_null = false;
	*buf = 0;
	while (1) {
	  ret = SQLGetData(db->hstmt, column, SQL_BINARY, bufp, actsz, &len);
	  if (ret == SQL_NO_DATA) {
	    if (total == 0)
	      goto err2;
	    break;
	  }
	  if (!SQL_SUCCEEDED(ret))
	    goto err2;
	  if (len == SQL_NULL_DATA) {
	    is_null = true;
	    break;
	  }
	  if (len < 0 && len != SQL_NO_TOTAL)
	    goto err2;
	  if (ret == SQL_SUCCESS) {
	    /* A successful read must describe the exact bytes in this buffer. */
	    if (len == SQL_NO_TOTAL || len > actsz)
	      goto err2;
	    if (total > SIZE_MAX - (size_t)len)
	      goto fatal2;
	    total += (size_t)len;
	    break;
	  } else {
	    SQLLEN received;
	    char *buf1;

	    /* SQL_SUCCESS_WITH_INFO is not necessarily truncation.  If the
	       driver reports a short, known length, it has already delivered the
	       complete value (with an unrelated warning).  SQL_NO_TOTAL and a
	       length filling this chunk mean that another SQLGetData call is
	       needed; only then is the entire chunk known to be initialized. */
	    if (len != SQL_NO_TOTAL && len < actsz) {
	      received = len;
	      if (total > SIZE_MAX - (size_t)received)
		goto fatal2;
	      total += (size_t)received;
	      break;
	    }
	    received = actsz;
	    if (total > SIZE_MAX - (size_t)received || sz > SIZE_MAX-BUFSZ)
	      goto fatal2;
	    total += (size_t)received;
	    if (!(buf1 = realloc(buf, sz+BUFSZ)))
	      goto fatal2;
	    buf = buf1;
	    bufp = buf+total;
	    sz += BUFSZ;
	    actsz = BUFSZ;
	  }
	}
	if (is_null)
	  xs[i] = pure_sqlnull();
	else if (total == 0) {
	  xs[i] = pure_tuplel(2, pure_int64(0),
			      pure_pointer(NULL));
	} else {
	  char *buf1 = realloc(buf, total);
	  if (buf1) buf = buf1;
	  xs[i] = pure_tuplel(2, pure_int64((int64_t) total),
			      pure_sentry(pure_symbol(pure_sym("free")),
					  pure_pointer(buf)));
	  /* make a new buffer */
	  if (!(buf = malloc(BUFSZ)))
	    goto fatal2;
	  else
	    sz = BUFSZ;
	}
	break;
      }
      default: {
	char *bufp = buf;
	size_t total = 0;
	SQLLEN actsz = (SQLLEN)sz;
	bool is_null = false;
	*buf = 0;
	while (1) {
	  ret = SQLGetData(db->hstmt, column, SQL_CHAR, bufp, actsz, &len);
	  if (ret == SQL_NO_DATA) {
	    if (total == 0)
	      goto err2;
	    break;
	  }
	  if (!SQL_SUCCEEDED(ret))
	    goto err2;
	  if (ret == SQL_SUCCESS) {
	    if (len == SQL_NULL_DATA) {
	      is_null = true;
	      break;
	    }
	    if (len < 0 || total > SIZE_MAX - (size_t)len)
	      goto fatal2;
	    else
	      total += (size_t)len;
	    break;
	  } else {
	    /* we probably need to make room for additional data */
	    char *buf1;
	    if (len == SQL_NULL_DATA) {
	      is_null = true;
	      break;
	    }
	    if (actsz <= 0 || total > SIZE_MAX - ((size_t)actsz - 1))
	      goto fatal2;
	    total += (size_t)actsz - 1;
	    if (sz > SIZE_MAX - BUFSZ)
	      goto fatal2;
	    if (!(buf1 = realloc(buf, sz+BUFSZ)))
	      goto fatal2;
	    buf = buf1;
	    bufp = buf+total;
	    sz += BUFSZ;
	    actsz = BUFSZ+1;
	  }
	}
	if (is_null)
	  xs[i] = pure_sqlnull();
	else {
	  xs[i] = pure_cstring_dup(buf);
	  if (sz > BUFSZ) {
	    /* shrink a (potentially large) buffer */
	    char *buf1 = realloc(buf, BUFSZ);
	    if (buf1) {
	      buf = buf1;
	      sz = BUFSZ;
	    }
	  }
	}
      }
      }
    }
    res = pure_listv(cols, xs);
    free(xs);
    goto exit;
  err2:
    for (j = 0; j < i; j++) pure_freenew(xs[j]);
    free(xs);
  err:
    res = pure_err(db->henv, db->hdbc, db->hstmt);
    goto exit;
  fatal2:
    for (j = 0; j < i; j++) pure_freenew(xs[j]);
    free(xs);
  fatal:
    res = pure_err_internal("insufficient memory");
  exit:
    if (buf) free(buf);
    return res;
  } else
    return 0;
}

pure_expr *odbc_sql_more(pure_expr *dbx)
{
  ODBCHandle *db;
  if (is_db_pointer(dbx, &db) && db->exec) {
    SQLRETURN ret;
    pure_expr *res = NULL, **xs = NULL;
    size_t i;
    SQLSMALLINT cols = 0, *coltype = NULL;
    size_t xs_count = 0;
    char buf[BUFSZ2];
    /* get the next result set */
    if ((ret = SQLMoreResults(db->hstmt)) == SQL_NO_DATA_FOUND) {
      res = 0;
      goto exit;
    } else if (ret != SQL_SUCCESS && ret != SQL_SUCCESS_WITH_INFO)
      goto err;
    /* determine the number of columns */
    if ((ret = SQLNumResultCols(db->hstmt, &cols)) != SQL_SUCCESS &&
	ret != SQL_SUCCESS_WITH_INFO)
      goto err;
    if (cols == 0) {
      SQLLEN rows;
      SQLSMALLINT *old_coltype;

      if ((ret = SQLRowCount(db->hstmt, &rows)) == SQL_SUCCESS ||
	  ret == SQL_SUCCESS_WITH_INFO)
	res = pure_odbc_integer(rows);
      else
	res = pure_int(0);
      old_coltype = db->coltype;
      db->coltype = NULL;
      db->cols = 0;
      if (old_coltype) free(old_coltype);
      goto exit;
    }
    /* get the column names and types */
    {
      size_t column_count;
      size_t coltype_bytes;
      size_t expression_bytes;

      if (cols < 0)
        goto fatal;
      column_count = (size_t)cols;
      if (!checked_multiply(column_count, sizeof(SQLSMALLINT),
                            &coltype_bytes) ||
          !checked_multiply(column_count, sizeof(pure_expr *),
                            &expression_bytes) ||
          !(coltype = (SQLSMALLINT *)malloc(coltype_bytes)) ||
          !(xs = (pure_expr **)malloc(expression_bytes)))
        goto fatal;
    }
    for (i = 0; i < (size_t)cols; i++) {
      buf[0] = 0;

      if ((ret = SQLDescribeCol(db->hstmt, (SQLUSMALLINT)(i + 1),
                                (SQLCHAR*)buf, (SQLSMALLINT)sizeof(buf),
				NULL, &coltype[i], NULL, NULL, NULL))
	  != SQL_SUCCESS &&
	  ret != SQL_SUCCESS_WITH_INFO)
	goto err;
      xs[i] = pure_cstring_dup(buf);
      if (!xs[i])
	goto fatal;
      xs_count = (size_t)i+1;
    }
    res = pure_listv((size_t)cols, xs);
    if (res) {
      SQLSMALLINT *old_coltype = db->coltype;

      xs_count = 0;
      db->coltype = NULL;
      if (old_coltype) free(old_coltype);
      db->coltype = coltype;
      coltype = NULL;
      db->cols = cols;
    }
    goto exit;
  err:
    res = pure_err(db->henv, db->hdbc, db->hstmt);
    goto exit;
  fatal:
    res = pure_err_internal("insufficient memory");
  exit:
    if (xs) {
      size_t j;

      for (j = 0; j < xs_count; j++) pure_freenew(xs[j]);
      free(xs);
    }
    if (coltype) free(coltype);
    return res;
  } else
    return 0;
}

pure_expr *odbc_sql_close(pure_expr *dbx)
{
  ODBCHandle *db;
  if (is_db_pointer(dbx, &db) && db->exec) {
    sql_close(db);
    return pure_tuplel(0);
  } else
    return 0;
}
