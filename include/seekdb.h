#pragma once

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef void *SeekdbHandle;        // a seekdb instance
typedef void *SeekdbConnection;
typedef void *SeekdbResult;
typedef void *SeekdbType;
typedef void *SeekdbValue;
// typedef void *SeekdbConfig;

typedef enum {
    SEEKDB_SUCCESS = 0,
    SEEKDB_INTERNAL_ERROR = -1,
    SEEKDB_INVALID_ARGUMENT = -2,
    SEEKDB_NO_MORE_ROWS = -3,
    // ...
} SeekdbReturnCode;

typedef enum {
    SEEKDB_TYPE_NULL,
    SEEKDB_TYPE_INT64,
    SEEKDB_TYPE_UINT64,
    SEEKDB_TYPE_FLOAT,
    SEEKDB_TYPE_DECIMAL,
    SEEKDB_TYPE_DATE,
    SEEKDB_TYPE_DATETIME,
    SEEKDB_TYPE_TIMESTAMP,
    SEEKDB_TYPE_VARCHAR,
    // ...
} SeekdbTypeId;

/* Locates the seekdb server binary as "<libseekdb_client.so's dir>/seekdb"
 * (".exe" suffix on Windows) — the binary must ship alongside the shared
 * library, which is the wheel / install layout. */
int seekdb_open(const char *db_dir, int port, SeekdbHandle *out_handle);
int seekdb_close(SeekdbHandle handle);

int seekdb_connect(SeekdbHandle handle, const char *database, bool autocommit,
                   SeekdbConnection *out_connection);
int seekdb_disconnect(SeekdbConnection connection);

/* Underlying server error from the most recent failed call on this
 * connection. *out_errno is the server error number (0 when there is no
 * pending error); *out_msg is a NUL-terminated string owned by the
 * connection and valid only until the next call on it. Either out
 * parameter may be NULL. */
int seekdb_last_error(SeekdbConnection connection, int *out_errno,
                      const char **out_msg);

int seekdb_query(SeekdbConnection connection, const char *sql, int64_t sql_len,
                 SeekdbResult *out_result);

int seekdb_result_free(SeekdbResult result);
int seekdb_result_column_count(SeekdbResult result, int64_t *out_ncolumn);
int seekdb_result_column_name(SeekdbResult result, int64_t index,
                              const char **out_name);
int seekdb_result_column_type_id(SeekdbResult result, int64_t index,
                                 SeekdbTypeId *out_typeid);
int seekdb_result_row_count(SeekdbResult result, int64_t *out_nrows);
int seekdb_result_next(SeekdbResult result);
int seekdb_result_get_int64(SeekdbResult result, int64_t index,
                            int64_t *out_value);
int seekdb_result_get_uint64(SeekdbResult result, int64_t index,
                             uint64_t *out_value);
int seekdb_result_get_float(SeekdbResult result, int64_t index,
                            double *out_value);
/* Returns a borrowed pointer into the current row's cell bytes; valid
 * until the next seekdb_result_next or seekdb_result_free. Used for
 * VARCHAR/DECIMAL/DATE/DATETIME/TIMESTAMP and any text-protocol cell.
 * *out_is_null is set to 1 if the cell is NULL (out_data undefined). */
int seekdb_result_get_str(SeekdbResult result, int64_t index,
                          const char **out_data, size_t *out_len,
                          int *out_is_null);

int seekdb_trx_begin(SeekdbConnection connection);
int seekdb_trx_commit(SeekdbConnection connection);
int seekdb_trx_rollback(SeekdbConnection connection);

int seekdb_value_free(SeekdbValue value);
int seekdb_value_create_int64(int64_t int_value, SeekdbValue *out_value);
int seekdb_value_get_int64(SeekdbValue value, int64_t *out_value);

// utils
void *seekdb_malloc(size_t size);
void seekdb_free(void *ptr);

#ifdef __cplusplus
}
#endif
