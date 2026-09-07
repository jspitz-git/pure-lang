
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
  short type; /* SQL parameter type */
  short ctype; /* C parameter type */
  SQLLEN len; /* length or indicator */
  long buflen; /* real buffer length */
  long prec; /* precision */
  void *ptr; /* buffer pointer */
  union {
    long iv; /* integer parameter */
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
  short *coltype; /* column types in current result set */
  short cols; /* number of columns */
  ODBCParam *argv; /* marked parameters */
  int argc; /* number of marked parameters */
} ODBCHandle;

static inline bool is_db_pointer(pure_expr *x, ODBCHandle **db)
{
  return pure_is_pointer(x, (void**)db) && *db &&
    (*db)->magic == ODBC_MAGIC && (*db)->henv;
}

static int init_args(ODBCHandle *db, int argc)
{
  int i;
  if (!(db->argv = malloc(argc*sizeof(ODBCParam))))
    return 0;
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
    int i;
    SQLFreeStmt(db->hstmt, SQL_RESET_PARAMS);
    for (i = 0; i < db->argc; i++)
      if ((db->argv[i].type == SQL_BIGINT || db->argv[i].type == SQL_CHAR ||
	   db->argv[i].type == SQL_BINARY) &&
	  db->argv[i].data.buf)
	free(db->argv[i].data.buf);
    free(db->argv);
    db->argv = NULL;
    db->argc = 0;
  }
}

static int set_arg(ODBCHandle *db, int i, pure_expr *x)
{
  int32_t iv;
  double fv;
  char *s;
  mpz_t z;
  size_t nelems;
  unsigned char *buf;
  int64_t buflen;
  if (pure_is_int(x, &iv)) {
    db->argv[i].type = SQL_INTEGER;
    db->argv[i].ctype = SQL_C_SLONG;
    db->argv[i].len = sizeof(long);
    db->argv[i].buflen = sizeof(long);
    db->argv[i].prec = 10;
    db->argv[i].data.iv = iv;
    db->argv[i].ptr = &db->argv[i].data.iv;
    return 1;
  } else if (pure_is_mpz(x, &z)) {
    /* convert big integer values to BIGINTs via a string representation,
       so we don't have to fiddle with long long's here */
    db->argv[i].type = SQL_BIGINT;
    db->argv[i].ctype = SQL_C_CHAR;
    db->argv[i].len = SQL_NTS;
    db->argv[i].data.buf = mpz_get_str(NULL, 10, z);
    if (!db->argv[i].data.buf) return 0;
    db->argv[i].buflen = strlen(db->argv[i].data.buf)+1;
    db->argv[i].prec = db->argv[i].buflen-1;
    db->argv[i].ptr = db->argv[i].data.buf;
    mpz_clear(z);
    return 1;
  } else if (pure_is_double(x, &fv)) {
    db->argv[i].type = SQL_DOUBLE;
    db->argv[i].ctype = SQL_C_DOUBLE;
    db->argv[i].len = sizeof(double);
    db->argv[i].buflen = sizeof(double);
    db->argv[i].prec = 15;
    db->argv[i].data.fv = fv;
    db->argv[i].ptr = &db->argv[i].data.fv;
    return 1;
  } else if (pure_is_cstring_dup(x, &s)) {
    if (!s) return 0;
    db->argv[i].type = SQL_CHAR;
    db->argv[i].ctype = SQL_C_CHAR;
    db->argv[i].len = SQL_NTS;
    db->argv[i].buflen = strlen(s)+1;
    /* FIXME: The prec value should actually be buflen-1 here, but the MS
       Access ODBC interface barks at these. Hopefully this doesn't mess
       things up with other ODBC drivers. */
    db->argv[i].prec = db->argv[i].buflen;
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
      buflen = (int64_t)iv;
    else if (pure_is_mpz(elems[0], NULL)) {
      buflen = pure_get_int64(elems[0]);
    } else {
      free(elems);
      return 0;
    }
    free(elems);
    if (buflen<0 || !buf) buflen = 0;
    db->argv[i].type = SQL_BINARY;
    db->argv[i].ctype = SQL_C_BINARY;
    db->argv[i].len = (SQLLEN) buflen;
    db->argv[i].buflen = (SQLLEN) buflen;
    db->argv[i].prec = (SQLLEN) buflen;
    if (buflen > 0) {
      if (!(db->argv[i].data.buf = malloc(buflen)))
	return 0;
      memcpy(db->argv[i].data.buf, buf, (size_t) buflen);
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
    if (db->coltype) free(db->coltype);
    free_args(db);
    SQLFreeStmt(db->hstmt, SQL_CLOSE);
    db->coltype = NULL;
    db->cols = 0;
    db->exec = 0;
  }
}

static pure_expr *pure_err(SQLHENV henv, SQLHDBC hdbc, SQLHSTMT hstmt)
{
  SQLCHAR stat[10], msg[300];
  SQLINTEGER err;
  short len;
  /* check for SQL statement errors */
  if (hstmt && SQLGetDiagRec(SQL_HANDLE_STMT, hstmt, 1, stat, &err,
			     msg, sizeof(msg), &len) == SQL_SUCCESS)
    goto exit;
  /* check for connection errors */
  if (hdbc && SQLGetDiagRec(SQL_HANDLE_DBC, hdbc, 1, stat, &err,
			    msg, sizeof(msg), &len) == SQL_SUCCESS)
    goto exit;
  /* check for environment errors */
  if (henv && SQLGetDiagRec(SQL_HANDLE_ENV, henv, 1, stat, &err,
			    msg, sizeof(msg), &len) == SQL_SUCCESS)
    goto exit;
  return 0;
 exit:
  return pure_app(pure_app(pure_symbol(pure_sym("odbc::error")),
			   pure_cstring_dup((const char*)msg)),
		  pure_cstring_dup((const char*)stat));
}

static inline pure_expr* pure_err_internal(const char *msg)
{
  return pure_app(pure_app(pure_symbol(pure_sym("odbc::error")),
			   pure_cstring_dup("[Pure ODBC]internal error")),
		  pure_cstring_dup(msg));
}

pure_expr *odbc_sources()
{
  SQLHENV henv;
  long ret;
  pure_expr **xv, *res;
  int n;
  SQLCHAR l_dsn[100],l_desc[100];
  short l_len1, l_len2, l_next;
  /* create an environment handle */
  if ((ret = SQLAllocHandle(SQL_HANDLE_ENV, NULL, &henv)) != SQL_SUCCESS &&
      ret != SQL_SUCCESS_WITH_INFO)
    return 0;
  if ((ret = SQLSetEnvAttr(henv, SQL_ATTR_ODBC_VERSION,
			   (SQLPOINTER) SQL_OV_ODBC3,
			   SQL_IS_UINTEGER)) != SQL_SUCCESS &&
      ret != SQL_SUCCESS_WITH_INFO) {
    pure_expr *msg = pure_err(henv, 0, 0);
    SQLFreeHandle(SQL_HANDLE_ENV, henv);
    return msg;
  }
  /* count the number of data sources */
  for (n = 0, l_next = SQL_FETCH_FIRST;
	SQLDataSources(henv, l_next, l_dsn, sizeof(l_dsn), &l_len1,
		       l_desc, sizeof(l_desc), &l_len2) == SQL_SUCCESS;
	l_next = SQL_FETCH_NEXT)
    n++;
  if (!(xv = (pure_expr**)malloc(n*sizeof(pure_expr*)))) {
    SQLFreeHandle(SQL_HANDLE_ENV, henv);
    return 0;
  }
  /* retrieve the data source names and descriptions */
  for (n = 0, l_next = SQL_FETCH_FIRST;
    SQLDataSources(henv, l_next, l_dsn, sizeof(l_dsn), &l_len1,
		l_desc, sizeof(l_desc), &l_len2) == SQL_SUCCESS;
    l_next = SQL_FETCH_NEXT)
    xv[n++] = pure_tuplel(2, pure_cstring_dup((const char*)l_dsn),
			  pure_cstring_dup((const char*)l_desc));
  /* free the environment handle */
  SQLFreeHandle(SQL_HANDLE_ENV, henv);
  res = pure_listv(n, xv);
  free(xv);
  return res;
}

pure_expr *odbc_drivers()
{
  SQLHENV henv;
  long ret;
  pure_expr **xv, *res;
  int n;
  SQLCHAR l_drv[100],l_attr[10000];
  short l_len1, l_len2, l_next;
  /* create an environment handle */
  if ((ret = SQLAllocHandle(SQL_HANDLE_ENV, NULL, &henv)) != SQL_SUCCESS &&
    ret != SQL_SUCCESS_WITH_INFO)
    return 0;
  if ((ret = SQLSetEnvAttr(henv, SQL_ATTR_ODBC_VERSION,
			   (SQLPOINTER) SQL_OV_ODBC3,
			   SQL_IS_UINTEGER)) != SQL_SUCCESS &&
      ret != SQL_SUCCESS_WITH_INFO) {
    pure_expr *msg = pure_err(henv, 0, 0);
    SQLFreeHandle(SQL_HANDLE_ENV, henv);
    return msg;
  }
  /* count the number of driver descriptions */
  for (n = 0, l_next = SQL_FETCH_FIRST;
       SQLDrivers(henv, l_next, l_drv, sizeof(l_drv), &l_len1,
		  l_attr, sizeof(l_attr), &l_len2) == SQL_SUCCESS;
       l_next = SQL_FETCH_NEXT)
    n++;
  if (!(xv = (pure_expr **) malloc(n*sizeof(pure_expr*)))) {
    SQLFreeHandle(SQL_HANDLE_ENV, henv);
    return pure_err_internal("insufficient memory");
  }
  /* retrieve the driver and descriptions */
  for (n = 0, l_next = SQL_FETCH_FIRST;
       SQLDrivers(henv, l_next, l_drv, sizeof(l_drv), &l_len1,
		  l_attr, sizeof(l_attr), &l_len2) == SQL_SUCCESS;
       l_next = SQL_FETCH_NEXT) {
    int k;
    SQLCHAR *l_attrp;
    pure_expr **yv;
    /* count the number of attributes */
    for (k = 0, l_attrp = l_attr; *l_attrp;
	 l_attrp = l_attrp+strlen((char*)l_attrp)+1)
      k++;
    if (!(yv = malloc(k*sizeof(pure_expr*)))) {
      int i;
      for (i = 0; i < n; i++)
	pure_freenew(xv[i]);
      free(xv);
      SQLFreeHandle(SQL_HANDLE_ENV, henv);
      return pure_err_internal("insufficient memory");
    }
    /* get the attribute strings */
    for (k = 0, l_attrp = l_attr; *l_attrp;
	 l_attrp = l_attrp+strlen((char*)l_attrp)+1)
      yv[k++] = pure_cstring_dup((const char*)l_attrp);
    xv[n++] = pure_tuplel(2, pure_cstring_dup((const char*)l_drv),
			  pure_listv(k, yv));
    free(yv);
  }
  /* free the environment handle */
  SQLFreeHandle(SQL_HANDLE_ENV, henv);
  res = pure_listv(n, xv);
  free(xv);
  return res;
}

pure_expr *odbc_connect(char* conn)
{
  if (conn) {
    ODBCHandle *db = (ODBCHandle*)malloc(sizeof(ODBCHandle));
    long ret;
    short buflen;
    char buf[1024];
    if (!db) return pure_err_internal("insufficient memory");
    db->magic = ODBC_MAGIC;
    /* create the environment handle */
    if ((ret = SQLAllocHandle(SQL_HANDLE_ENV, NULL, &db->henv)) !=
	SQL_SUCCESS &&
	ret != SQL_SUCCESS_WITH_INFO) {
      return 0;
    }
    if ((ret = SQLSetEnvAttr(db->henv, SQL_ATTR_ODBC_VERSION,
			     (SQLPOINTER) SQL_OV_ODBC3,
			     SQL_IS_UINTEGER)) != SQL_SUCCESS &&
	ret != SQL_SUCCESS_WITH_INFO) {
      pure_expr *msg = pure_err(db->henv, 0, 0);
      SQLFreeHandle(SQL_HANDLE_ENV, db->henv);
      return msg;
    }
    /* create the connection handle */
    if ((ret = SQLAllocHandle(SQL_HANDLE_DBC, db->henv, &db->hdbc)) !=
	SQL_SUCCESS &&
	ret != SQL_SUCCESS_WITH_INFO) {
      pure_expr *msg = pure_err(db->henv, 0, 0);
      SQLFreeHandle(SQL_HANDLE_ENV, db->henv);
      return msg;
    }
    /* connect */
    if ((ret = SQLDriverConnect(db->hdbc, 0, (SQLCHAR*)conn, SQL_NTS,
				(SQLCHAR*)buf, sizeof(buf), &buflen,
				SQL_DRIVER_NOPROMPT)) != SQL_SUCCESS &&
	ret != SQL_SUCCESS_WITH_INFO) {
      pure_expr *msg = pure_err(db->henv, db->hdbc, 0);
      SQLFreeHandle(SQL_HANDLE_DBC, db->hdbc);
      SQLFreeHandle(SQL_HANDLE_ENV, db->henv);
      return msg;
    }
    /* create the statement handle */
    if ((ret = SQLAllocHandle(SQL_HANDLE_STMT, db->hdbc, &db->hstmt)) !=
	SQL_SUCCESS &&
	ret != SQL_SUCCESS_WITH_INFO) {
      pure_expr *msg = pure_err(db->henv, db->hdbc, 0);
      SQLDisconnect(db->hdbc);
      SQLFreeHandle(SQL_HANDLE_DBC, db->hdbc);
      SQLFreeHandle(SQL_HANDLE_ENV, db->henv);
      return msg;
    }
    /* initialize statement properties */
    db->argv = NULL;
    db->argc = 0;
    db->coltype = NULL;
    db->cols = 0;
    db->exec = 0;
    /* return the result */
    return pure_sentry(pure_symbol(pure_sym("odbc::disconnect")),
		       pure_pointer(db));
  } else
    return 0;
}

pure_expr *odbc_disconnect(pure_expr *dbx)
{
  ODBCHandle *db;
  if (is_db_pointer(dbx, &db)) {
    sql_close(db);
    SQLCloseCursor(db->hstmt);
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
    long ret;
    int n = 0;
    pure_expr *xv[8], *res;
    char info[1024];
    short len;
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
   Info types not listed here are textual (including SQL_XOPEN_CLI_YEAR). */
static const struct odbc_info_value_type odbc_info_value_types[] = {
  ODBC_INFO(SQL_ACTIVE_CONNECTIONS, ODBC_INFO_USMALLINT),
  ODBC_INFO(SQL_ACTIVE_STATEMENTS, ODBC_INFO_USMALLINT),
  ODBC_INFO(SQL_ODBC_API_CONFORMANCE, ODBC_INFO_USMALLINT),
  ODBC_INFO(SQL_ROW_UPDATES, ODBC_INFO_USMALLINT),
  ODBC_INFO(SQL_ODBC_SAG_CLI_CONFORMANCE, ODBC_INFO_USMALLINT),
  ODBC_INFO(SQL_ODBC_SQL_CONFORMANCE, ODBC_INFO_USMALLINT),
  ODBC_INFO(SQL_ACCESSIBLE_TABLES, ODBC_INFO_USMALLINT),
  ODBC_INFO(SQL_ACCESSIBLE_PROCEDURES, ODBC_INFO_USMALLINT),
  ODBC_INFO(SQL_PROCEDURES, ODBC_INFO_USMALLINT),
  ODBC_INFO(SQL_CONCAT_NULL_BEHAVIOR, ODBC_INFO_USMALLINT),
  ODBC_INFO(SQL_CURSOR_COMMIT_BEHAVIOR, ODBC_INFO_USMALLINT),
  ODBC_INFO(SQL_CURSOR_ROLLBACK_BEHAVIOR, ODBC_INFO_USMALLINT),
  ODBC_INFO(SQL_EXPRESSIONS_IN_ORDERBY, ODBC_INFO_USMALLINT),
  ODBC_INFO(SQL_IDENTIFIER_CASE, ODBC_INFO_USMALLINT),
  ODBC_INFO(SQL_MAX_COLUMN_NAME_LEN, ODBC_INFO_USMALLINT),
  ODBC_INFO(SQL_MAX_CURSOR_NAME_LEN, ODBC_INFO_USMALLINT),
  ODBC_INFO(SQL_MAX_SCHEMA_NAME_LEN, ODBC_INFO_USMALLINT),
  ODBC_INFO(SQL_MAX_PROCEDURE_NAME_LEN, ODBC_INFO_USMALLINT),
  ODBC_INFO(SQL_MAX_CATALOG_NAME_LEN, ODBC_INFO_USMALLINT),
  ODBC_INFO(SQL_MAX_TABLE_NAME_LEN, ODBC_INFO_USMALLINT),
  ODBC_INFO(SQL_MULT_RESULT_SETS, ODBC_INFO_USMALLINT),
  ODBC_INFO(SQL_MULTIPLE_ACTIVE_TXN, ODBC_INFO_USMALLINT),
  ODBC_INFO(SQL_OUTER_JOINS, ODBC_INFO_USMALLINT),
  ODBC_INFO(SQL_TXN_CAPABLE, ODBC_INFO_USMALLINT),
  ODBC_INFO(SQL_CORRELATION_NAME, ODBC_INFO_USMALLINT),
  ODBC_INFO(SQL_NON_NULLABLE_COLUMNS, ODBC_INFO_USMALLINT),
  ODBC_INFO(SQL_FILE_USAGE, ODBC_INFO_USMALLINT),
  ODBC_INFO(SQL_NULL_COLLATION, ODBC_INFO_USMALLINT),
  ODBC_INFO(SQL_COLUMN_ALIAS, ODBC_INFO_USMALLINT),
  ODBC_INFO(SQL_GROUP_BY, ODBC_INFO_USMALLINT),
  ODBC_INFO(SQL_ORDER_BY_COLUMNS_IN_SELECT, ODBC_INFO_USMALLINT),
  ODBC_INFO(SQL_QUOTED_IDENTIFIER_CASE, ODBC_INFO_USMALLINT),
  ODBC_INFO(SQL_MAX_COLUMNS_IN_GROUP_BY, ODBC_INFO_USMALLINT),
  ODBC_INFO(SQL_MAX_COLUMNS_IN_INDEX, ODBC_INFO_USMALLINT),
  ODBC_INFO(SQL_MAX_COLUMNS_IN_ORDER_BY, ODBC_INFO_USMALLINT),
  ODBC_INFO(SQL_MAX_COLUMNS_IN_SELECT, ODBC_INFO_USMALLINT),
  ODBC_INFO(SQL_MAX_COLUMNS_IN_TABLE, ODBC_INFO_USMALLINT),
  ODBC_INFO(SQL_MAX_ROW_SIZE_INCLUDES_LONG, ODBC_INFO_USMALLINT),
  ODBC_INFO(SQL_MAX_TABLES_IN_SELECT, ODBC_INFO_USMALLINT),
  ODBC_INFO(SQL_MAX_USER_NAME_LEN, ODBC_INFO_USMALLINT),
  ODBC_INFO(SQL_NEED_LONG_DATA_LEN, ODBC_INFO_USMALLINT),
  ODBC_INFO(SQL_LIKE_ESCAPE_CLAUSE, ODBC_INFO_USMALLINT),
  ODBC_INFO(SQL_QUALIFIER_LOCATION, ODBC_INFO_USMALLINT),
  ODBC_INFO(SQL_ACTIVE_ENVIRONMENTS, ODBC_INFO_USMALLINT),
  ODBC_INFO(SQL_DESCRIBE_PARAMETER, ODBC_INFO_USMALLINT),
  ODBC_INFO(SQL_CATALOG_NAME, ODBC_INFO_USMALLINT),
  ODBC_INFO(SQL_MAX_IDENTIFIER_LEN, ODBC_INFO_USMALLINT),

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
#define checkuint(x,l) ((l==SQL_NULL_DATA)?pure_sqlnull():pure_int(x))
#define checkbool(x,l) ((l==SQL_NULL_DATA)?pure_sqlnull():pure_int(x))

pure_expr *odbc_typeinfo(pure_expr *dbx, int id)
{
  ODBCHandle *db;
  if (is_db_pointer(dbx, &db)) {
    pure_expr *res, **xs = (pure_expr**)malloc(NMAX*sizeof(pure_expr*)), **xs1;
    int i, n = 0, m = NMAX;

    UCHAR  name[SL], prefix[SL], suffix[SL], params[SL], local_name[SL];
    SWORD  type, nullable, case_sen, searchable, unsign, money, auto_inc;
    SWORD  min_scale, max_scale;
    UDWORD prec;
    SQLLEN len[20];
    SDWORD ret;
    SWORD  sql_type, subcode, intv_prec;
    UDWORD prec_radix;

    if (!xs) return pure_err_internal("insufficient memory");
    sql_close(db);

    ret = SQLBindCol(db->hstmt,  1, SQL_C_CHAR,  name,       SL, &len[1]);
    ret = SQLBindCol(db->hstmt,  2, SQL_C_SHORT, &type,       0, &len[2]);
    ret = SQLBindCol(db->hstmt,  3, SQL_C_LONG,  &prec,       0, &len[3]);
    ret = SQLBindCol(db->hstmt,  4, SQL_C_CHAR,  prefix,     SL, &len[4]);
    ret = SQLBindCol(db->hstmt,  5, SQL_C_CHAR,  suffix,     SL, &len[5]);
    ret = SQLBindCol(db->hstmt,  6, SQL_C_CHAR,  params,     SL, &len[6]);
    ret = SQLBindCol(db->hstmt,  7, SQL_C_SHORT, &nullable,   0, &len[7]);
    ret = SQLBindCol(db->hstmt,  8, SQL_C_SHORT, &case_sen,   0, &len[8]);
    ret = SQLBindCol(db->hstmt,  9, SQL_C_SHORT, &searchable, 0, &len[9]);
    ret = SQLBindCol(db->hstmt, 10, SQL_C_SHORT, &unsign,     0, &len[10]);
    ret = SQLBindCol(db->hstmt, 11, SQL_C_SHORT, &money,      0, &len[11]);
    ret = SQLBindCol(db->hstmt, 12, SQL_C_SHORT, &auto_inc,   0, &len[12]);
    ret = SQLBindCol(db->hstmt, 13, SQL_C_CHAR,  local_name, SL, &len[13]);
    ret = SQLBindCol(db->hstmt, 14, SQL_C_SHORT, &min_scale,  0, &len[14]);
    ret = SQLBindCol(db->hstmt, 15, SQL_C_SHORT, &max_scale,  0, &len[15]);
    ret = SQLBindCol(db->hstmt, 16, SQL_C_SHORT, &sql_type,   0, &len[16]);
    ret = SQLBindCol(db->hstmt, 17, SQL_C_SHORT, &subcode,    0, &len[17]);
    ret = SQLBindCol(db->hstmt, 18, SQL_C_LONG,  &prec_radix, 0, &len[18]);
    ret = SQLBindCol(db->hstmt, 19, SQL_C_SHORT, &intv_prec,  0, &len[19]);

    ret = SQLGetTypeInfo(db->hstmt, id);
    if (ret != SQL_SUCCESS && ret != SQL_SUCCESS_WITH_INFO) goto err;

    do {
      ret = SQLFetch(db->hstmt);
      switch (ret) {
       case SQL_SUCCESS_WITH_INFO:
       case SQL_SUCCESS:
	 if (n >= m) {
	   if ((xs1 = (pure_expr**)realloc(xs, (m+=NMAX)*sizeof(pure_expr*))))
	     xs = xs1;
	   else
	     goto fatal;
	 }
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
    pure_expr *res, **xs = (pure_expr**)malloc(NMAX*sizeof(pure_expr*)), **xs1;
    int i, n = 0, m = NMAX;

    UCHAR  name[SL], type[SL];
    SQLLEN len[6];
    SDWORD ret;

    if (!xs) return pure_err_internal("insufficient memory");
    sql_close(db);

    ret = SQLBindCol(db->hstmt,  3, SQL_C_CHAR,  name,       SL, &len[3]);
    ret = SQLBindCol(db->hstmt,  4, SQL_C_CHAR,  type,       SL, &len[4]);

    ret = SQLTables(db->hstmt, NULL, 0, NULL, 0, NULL, 0, NULL, 0);
    if (ret != SQL_SUCCESS && ret != SQL_SUCCESS_WITH_INFO) goto err;

    do {
      ret = SQLFetch(db->hstmt);
      switch (ret) {
       case SQL_SUCCESS_WITH_INFO:
       case SQL_SUCCESS:
	 if (n >= m) {
	   if ((xs1 = (pure_expr**)realloc(xs, (m+=NMAX)*sizeof(pure_expr*))))
	     xs = xs1;
	   else
	     goto fatal;
	 }
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
    pure_expr *res, **xs = (pure_expr**)malloc(NMAX*sizeof(pure_expr*)), **xs1;
    int i, n = 0, m = NMAX;

    UCHAR  name[SL], type[SL], nullable[SL], deflt[SL];
    SQLLEN len[19];
    SDWORD ret;

    if (!xs) return pure_err_internal("insufficient memory");
    if (!tab) {
      free(xs);
      return pure_err_internal("invalid table name string");
    }
    sql_close(db);

    ret = SQLBindCol(db->hstmt,  4, SQL_C_CHAR,  name,       SL, &len[4]);
    ret = SQLBindCol(db->hstmt,  6, SQL_C_CHAR,  type,       SL, &len[6]);
    ret = SQLBindCol(db->hstmt, 13, SQL_C_CHAR,  deflt,      SL, &len[13]);
    ret = SQLBindCol(db->hstmt, 18, SQL_C_CHAR,  nullable,   SL, &len[18]);

    ret = SQLColumns(db->hstmt, NULL, 0, NULL, 0, (SQLCHAR*)tab, SQL_NTS,
		     NULL, 0);
    if (ret != SQL_SUCCESS && ret != SQL_SUCCESS_WITH_INFO) goto err;

    do {
      ret = SQLFetch(db->hstmt);
      switch (ret) {
       case SQL_SUCCESS_WITH_INFO:
       case SQL_SUCCESS:
	 if (n >= m) {
	   if ((xs1 = (pure_expr**)realloc(xs, (m+=NMAX)*sizeof(pure_expr*))))
	     xs = xs1;
	   else
	     goto fatal;
	 }
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
    pure_expr *res, **xs = (pure_expr**)malloc(NMAX*sizeof(pure_expr*)), **xs1;
    int i, n = 0, m = NMAX;

    UCHAR  name[SL];
    SQLLEN len[5];
    SDWORD ret;

    if (!xs) return pure_err_internal("insufficient memory");
    if (!tab) {
      free(xs);
      return pure_err_internal("invalid table name string");
    }
    sql_close(db);

    ret = SQLBindCol(db->hstmt,  4, SQL_C_CHAR,  name,       SL, &len[4]);

    ret = SQLPrimaryKeys(db->hstmt, NULL, 0, NULL, 0, (SQLCHAR*)tab, SQL_NTS);
    if (ret != SQL_SUCCESS && ret != SQL_SUCCESS_WITH_INFO) goto err;

    do {
      ret = SQLFetch(db->hstmt);
      switch (ret) {
       case SQL_SUCCESS_WITH_INFO:
       case SQL_SUCCESS:
	 if (n >= m) {
	   if ((xs1 = (pure_expr**)realloc(xs, (m+=NMAX)*sizeof(pure_expr*))))
	     xs = xs1;
	   else
	     goto fatal;
	 }
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
    pure_expr *res, **xs = (pure_expr**)malloc(NMAX*sizeof(pure_expr*)), **xs1;
    int i, n = 0, m = NMAX;

    UCHAR  name[SL], pktabname[SL], pkname[SL];
    SQLLEN len[9];
    SDWORD ret;

    if (!xs) return pure_err_internal("insufficient memory");
    if (!tab) {
      free(xs);
      return pure_err_internal("invalid table name string");
    }
    sql_close(db);

    ret = SQLBindCol(db->hstmt,  3, SQL_C_CHAR,  pktabname,  SL, &len[3]);
    ret = SQLBindCol(db->hstmt,  4, SQL_C_CHAR,  pkname,     SL, &len[4]);
    ret = SQLBindCol(db->hstmt,  8, SQL_C_CHAR,  name,       SL, &len[8]);

    ret = SQLForeignKeys(db->hstmt, NULL, 0, NULL, 0, NULL, 0, NULL, 0,
			 NULL, 0, (SQLCHAR*)tab, SQL_NTS);
    if (ret != SQL_SUCCESS && ret != SQL_SUCCESS_WITH_INFO) goto err;

    do {
      ret = SQLFetch(db->hstmt);
      switch (ret) {
       case SQL_SUCCESS_WITH_INFO:
       case SQL_SUCCESS:
	 if (n >= m) {
	   if ((xs1 = (pure_expr**)realloc(xs, (m+=NMAX)*sizeof(pure_expr*))))
	     xs = xs1;
	   else
	     goto fatal;
	 }
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

pure_expr *odbc_sql_exec(pure_expr *dbx, const char *query, pure_expr *args)
{
  ODBCHandle *db;
  pure_expr **xv;
  size_t n;
  if (is_db_pointer(dbx, &db) && pure_is_listv(args, &n, &xv)) {
    long ret;
    pure_expr *res, **xs;
    size_t i;
    short cols, *coltype = NULL;
    char buf[BUFSZ2];
    /* finalize previous query */
    sql_close(db);
    /* prepare statement */
    if (!query) {
      free(xv);
      return pure_err_internal("invalid query string");
    }
    if ((ret = SQLPrepare(db->hstmt, (SQLCHAR*)query, SQL_NTS))
	!= SQL_SUCCESS &&
	ret != SQL_SUCCESS_WITH_INFO) {
      free(xv);
      return pure_err(db->henv, db->hdbc, db->hstmt);
    }
    /* bind parameters */
    if (n > 0) {
      if (n > INT_MAX || !init_args(db, (int)n))
	goto fatal;
      for (i = 0; i < n; i++)
	if (!set_arg(db, i, xv[i])) {
	  int alloc_error =
	    (db->argv[i].type == SQL_BIGINT ||
	     db->argv[i].type == SQL_CHAR ||
	     db->argv[i].type == SQL_BINARY) &&
	    !db->argv[i].data.buf;
	  if (alloc_error)
	    goto fatal;
	  else
	    goto fail;
	}
      free(xv);
    }
    for (i = 0; i < (size_t)db->argc; i++)
      if ((ret = SQLBindParameter(db->hstmt, i+1, SQL_PARAM_INPUT,
				  db->argv[i].ctype,
				  db->argv[i].type,
				  db->argv[i].prec, 0,
				  db->argv[i].ptr,
				  db->argv[i].buflen,
				  &db->argv[i].len)) != SQL_SUCCESS &&
	  ret != SQL_SUCCESS_WITH_INFO)
	goto err;
    /* execute statement */
    if ((ret = SQLExecute(db->hstmt)) != SQL_SUCCESS &&
	ret != SQL_SUCCESS_WITH_INFO)
      return pure_err(db->henv, db->hdbc, db->hstmt);
    /* determine the number of columns */
    if ((ret = SQLNumResultCols(db->hstmt, &cols)) != SQL_SUCCESS &&
	ret != SQL_SUCCESS_WITH_INFO)
      goto err;
    if (cols == 0) {
      SQLLEN rows;
      if ((ret = SQLRowCount(db->hstmt, &rows)) == SQL_SUCCESS ||
	  ret == SQL_SUCCESS_WITH_INFO)
	res = pure_int((long)rows);
      else
	res = pure_int(0);
      db->exec = 1;
      goto exit;
    }
    /* get the column names and types */
    if (!(coltype = malloc(cols*sizeof(short))))
      goto fatal;
    if (!(xs = malloc(cols*sizeof(pure_expr*))))
      goto fatal;
    for (i = 0; i < (size_t)cols; i++) {
      buf[0] = 0;
      if ((ret = SQLDescribeCol(db->hstmt, i+1, (SQLCHAR*)buf, sizeof(buf),
				NULL, &coltype[i], NULL, NULL, NULL))
	  != SQL_SUCCESS &&
	  ret != SQL_SUCCESS_WITH_INFO) {
	size_t j;
	for (j = 0; j < i; j++) pure_freenew(xs[j]);
	free(xs);
	goto err;
      }
      xs[i] = pure_cstring_dup(buf);
    }
    res = pure_listv(cols, xs);
    free(xs);
    if (res) {
      db->coltype = coltype;
      db->cols = cols;
      coltype = NULL;
      db->exec = 1;
    } else {
      free_args(db);
      SQLFreeStmt(db->hstmt, SQL_CLOSE);
    }
    goto exit;
  fail:
    free_args(db);
    free(xv);
    SQLFreeStmt(db->hstmt, SQL_CLOSE);
    res = 0;
    goto exit;
  err:
    res = pure_err(db->henv, db->hdbc, db->hstmt);
    free_args(db);
    SQLFreeStmt(db->hstmt, SQL_CLOSE);
    goto exit;
  fatal:
    free_args(db);
    free(xv);
    SQLFreeStmt(db->hstmt, SQL_CLOSE);
    res = pure_err_internal("insufficient memory");
  exit:
    if (coltype) free(coltype);
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
    short i, j, cols = db->cols, *coltype = db->coltype;
    long iv, sz = BUFSZ;
    double fv;
    char *buf = malloc(sz);
    SQLLEN len;
    if (!buf) goto fatal;
    /* fetch the next record */
    if ((ret = SQLFetch(db->hstmt)) == SQL_NO_DATA_FOUND) {
      res = 0;
      goto exit;
    } else if (ret != SQL_SUCCESS && ret != SQL_SUCCESS_WITH_INFO)
      goto err;
    if (!(xs = malloc(cols*sizeof(pure_expr*))))
      goto fatal;
    /* get the columns */
    for (i = 0; i < cols; i++) {
      switch (coltype[i]) {
      case SQL_BIT:
      case SQL_TINYINT:
      case SQL_SMALLINT:
      case SQL_INTEGER:
	ret = SQLGetData(db->hstmt, i+1, SQL_INTEGER, &iv, sizeof(iv), &len);
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
	ret = SQLGetData(db->hstmt, i+1, SQL_CHAR, buf, sz, &len);
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
	ret = SQLGetData(db->hstmt, i+1, SQL_DOUBLE, &fv, sizeof(fv), &len);
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
	SQLLEN total = 0, actsz = sz;
	bool is_null = false;
	*buf = 0;
	while (1) {
	  ret = SQLGetData(db->hstmt, i+1, SQL_BINARY, bufp, actsz, &len);
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
	    if (total+len < total)
	      goto fatal2;
	    total += len;
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
	      if (total+received < total)
		goto fatal2;
	      total += received;
	      break;
	    }
	    received = actsz;
	    if (total+received < total || sz > LONG_MAX-BUFSZ)
	      goto fatal2;
	    total += received;
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
	long total = 0, actsz = sz;
	bool is_null = false;
	*buf = 0;
	while (1) {
	  ret = SQLGetData(db->hstmt, i+1, SQL_CHAR, bufp, actsz, &len);
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
	    if (total+len < total)
	      goto fatal2;
	    else
	      total += len;
	    break;
	  } else {
	    /* we probably need to make room for additional data */
	    char *buf1;
	    if (len == SQL_NULL_DATA) {
	      is_null = true;
	      break;
	    }
#if 0
	    if (total+BUFSZ < total)
	      goto fatal2;
	    else
#endif
	      total += actsz-1;
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
    long ret;
    pure_expr *res, **xs;
    short i, cols, *coltype = NULL;
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
      if ((ret = SQLRowCount(db->hstmt, &rows)) == SQL_SUCCESS ||
	  ret == SQL_SUCCESS_WITH_INFO)
	res = pure_int((long)rows);
      else
	res = pure_int(0);
      if (db->coltype) free(db->coltype);
      db->coltype = NULL;
      db->cols = 0;
      goto exit;
    }
    /* get the column names and types */
    if (!(coltype = malloc(cols*sizeof(short))))
      goto fatal;
    if (!(xs = malloc(cols*sizeof(pure_expr*))))
      goto fatal;
    for (i = 0; i < cols; i++) {
      buf[0] = 0;
      if ((ret = SQLDescribeCol(db->hstmt, i+1, (SQLCHAR*)buf, sizeof(buf),
				NULL, &coltype[i], NULL, NULL, NULL))
	  != SQL_SUCCESS &&
	  ret != SQL_SUCCESS_WITH_INFO) {
	int j;
	for (j = 0; j < i; j++) pure_freenew(xs[j]);
	free(xs);
	goto err;
      }
      xs[i] = pure_cstring_dup(buf);
    }
    res = pure_listv(cols, xs);
    free(xs);
    if (res) {
      free(db->coltype);
      if (db->coltype) db->coltype = coltype;
      db->cols = cols;
      coltype = NULL;
    }
    goto exit;
  err:
    res = pure_err(db->henv, db->hdbc, db->hstmt);
    goto exit;
  fatal:
    res = pure_err_internal("insufficient memory");
  exit:
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
