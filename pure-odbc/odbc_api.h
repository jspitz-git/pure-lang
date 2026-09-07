#ifndef PURE_ODBC_API_H
#define PURE_ODBC_API_H

#include <sql.h>
#include <sqlext.h>

/* This is deliberately an internal seam.  The production instance is bound
   to the native ODBC entry points; tests may replace individual entries. */
struct pure_odbc_api {
  SQLRETURN (SQL_API *alloc_handle)(SQLSMALLINT, SQLHANDLE, SQLHANDLE *);
  SQLRETURN (SQL_API *free_handle)(SQLSMALLINT, SQLHANDLE);
  SQLRETURN (SQL_API *set_env_attr)(SQLHENV, SQLINTEGER, SQLPOINTER,
                                    SQLINTEGER);
  SQLRETURN (SQL_API *driver_connect)(SQLHDBC, SQLHWND, SQLCHAR *,
                                      SQLSMALLINT, SQLCHAR *, SQLSMALLINT,
                                      SQLSMALLINT *, SQLUSMALLINT);
  SQLRETURN (SQL_API *disconnect)(SQLHDBC);
  SQLRETURN (SQL_API *get_diag_rec)(SQLSMALLINT, SQLHANDLE, SQLSMALLINT,
                                    SQLCHAR *, SQLINTEGER *, SQLCHAR *,
                                    SQLSMALLINT, SQLSMALLINT *);
  SQLRETURN (SQL_API *drivers)(SQLHENV, SQLUSMALLINT, SQLCHAR *,
                               SQLSMALLINT, SQLSMALLINT *, SQLCHAR *,
                               SQLSMALLINT, SQLSMALLINT *);
  SQLRETURN (SQL_API *data_sources)(SQLHENV, SQLUSMALLINT, SQLCHAR *,
                                    SQLSMALLINT, SQLSMALLINT *, SQLCHAR *,
                                    SQLSMALLINT, SQLSMALLINT *);
  SQLRETURN (SQL_API *get_info)(SQLHDBC, SQLUSMALLINT, SQLPOINTER,
                                SQLSMALLINT, SQLSMALLINT *);
  SQLRETURN (SQL_API *get_type_info)(SQLHSTMT, SQLSMALLINT);
  SQLRETURN (SQL_API *bind_col)(SQLHSTMT, SQLUSMALLINT, SQLSMALLINT,
                                SQLPOINTER, SQLLEN, SQLLEN *);
  SQLRETURN (SQL_API *fetch)(SQLHSTMT);
  SQLRETURN (SQL_API *free_stmt)(SQLHSTMT, SQLUSMALLINT);
  SQLRETURN (SQL_API *tables)(SQLHSTMT, SQLCHAR *, SQLSMALLINT, SQLCHAR *,
                              SQLSMALLINT, SQLCHAR *, SQLSMALLINT, SQLCHAR *,
                              SQLSMALLINT);
  SQLRETURN (SQL_API *columns)(SQLHSTMT, SQLCHAR *, SQLSMALLINT, SQLCHAR *,
                               SQLSMALLINT, SQLCHAR *, SQLSMALLINT, SQLCHAR *,
                               SQLSMALLINT);
  SQLRETURN (SQL_API *primary_keys)(SQLHSTMT, SQLCHAR *, SQLSMALLINT,
                                    SQLCHAR *, SQLSMALLINT, SQLCHAR *,
                                    SQLSMALLINT);
  SQLRETURN (SQL_API *foreign_keys)(SQLHSTMT, SQLCHAR *, SQLSMALLINT,
                                    SQLCHAR *, SQLSMALLINT, SQLCHAR *,
                                    SQLSMALLINT, SQLCHAR *, SQLSMALLINT,
                                    SQLCHAR *, SQLSMALLINT, SQLCHAR *,
                                    SQLSMALLINT);
  SQLRETURN (SQL_API *prepare)(SQLHSTMT, SQLCHAR *, SQLINTEGER);
  SQLRETURN (SQL_API *bind_parameter)(SQLHSTMT, SQLUSMALLINT, SQLSMALLINT,
                                      SQLSMALLINT, SQLSMALLINT, SQLULEN,
                                      SQLSMALLINT, SQLPOINTER, SQLLEN,
                                      SQLLEN *);
  SQLRETURN (SQL_API *execute)(SQLHSTMT);
  SQLRETURN (SQL_API *num_result_cols)(SQLHSTMT, SQLSMALLINT *);
  SQLRETURN (SQL_API *row_count)(SQLHSTMT, SQLLEN *);
  SQLRETURN (SQL_API *describe_col)(SQLHSTMT, SQLUSMALLINT, SQLCHAR *,
                                    SQLSMALLINT, SQLSMALLINT *, SQLSMALLINT *,
                                    SQLULEN *, SQLSMALLINT *, SQLSMALLINT *);
  SQLRETURN (SQL_API *get_data)(SQLHSTMT, SQLUSMALLINT, SQLSMALLINT,
                                SQLPOINTER, SQLLEN, SQLLEN *);
  SQLRETURN (SQL_API *more_results)(SQLHSTMT);
  SQLRETURN (SQL_API *close_cursor)(SQLHSTMT);
};

#ifdef PURE_ODBC_TESTING
void pure_odbc_set_api_for_test(const struct pure_odbc_api *test_api);
#endif

#endif
