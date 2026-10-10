/*
 * Copyright (c) 2026 OceanBase.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */
#pragma once

#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <mysql.h>

inline bool connect_socket_client(MYSQL *client, const char *socket, const char *database)
{
    if (client == nullptr || socket == nullptr) {
        return false;
    }
    unsigned int protocol = MYSQL_PROTOCOL_SOCKET;
    char no_ssl = 0;
    mysql_options(client, MYSQL_OPT_PROTOCOL, &protocol);
    mysql_options(client, MYSQL_OPT_SSL_ENFORCE, &no_ssl);
    mysql_options(client, MYSQL_OPT_SSL_VERIFY_SERVER_CERT, &no_ssl);
    mysql_options(client, MYSQL_SET_CHARSET_NAME, "utf8mb4");
    return mysql_real_connect(client, nullptr, "root", "", database, 0, socket, 0) != nullptr;
}

inline bool execute_sql(MYSQL *client, const char *sql)
{
    if (mysql_real_query(client, sql, std::strlen(sql)) != 0) {
        return false;
    }
    MYSQL_RES *result = mysql_store_result(client);
    if (result != nullptr) {
        mysql_free_result(result);
        return true;
    }
    return mysql_field_count(client) == 0;
}

inline bool read_int64(MYSQL *client, const char *sql, int64_t &value)
{
    if (mysql_real_query(client, sql, std::strlen(sql)) != 0) {
        return false;
    }
    MYSQL_RES *result = mysql_store_result(client);
    if (result == nullptr) {
        return false;
    }
    MYSQL_ROW row = mysql_fetch_row(result);
    char *end = nullptr;
    bool success = row != nullptr && row[0] != nullptr && row[0][0] != '\0';
    if (success) {
        value = std::strtoll(row[0], &end, 10);
        success = *end == '\0' && mysql_fetch_row(result) == nullptr && mysql_errno(client) == 0;
    }
    mysql_free_result(result);
    return success;
}
