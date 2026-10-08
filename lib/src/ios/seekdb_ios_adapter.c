/*
 * Copyright (c) 2025 OceanBase.
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
#include "seekdb/seekdb.h"

#ifdef __APPLE__
#include <TargetConditionals.h>
#endif

#if (defined(__APPLE__) && TARGET_OS_IOS) || defined(SEEKDB_IOS_HOST_TEST)
#include "seekdb_ios.h"
#include <errno.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <time.h>

enum { RUNTIME_STACK_SIZE = 8 * 1024 * 1024 };
#ifdef SEEKDB_IOS_HOST_TEST
static const double startup_timeout_seconds = 0.25;
#else
static const double startup_timeout_seconds = 180.0;
#endif

/* The engine owns process globals even after a failed start. Retain this state
 * and its directory for the process lifetime, including after startup timeout.
 * A detached, timed-out startup must never access a freed caller-owned handle.
 */
static struct {
    char *directory;
    pthread_t thread;
    bool claimed;
    bool has_handle;
    bool finished;
    bool joined;
    bool joining;
    int result;
} runtime;
static pthread_mutex_t runtime_lock = PTHREAD_MUTEX_INITIALIZER;
static _Thread_local char last_open_error[1024];

const char *seekdb_last_open_error(void)
{
    return last_open_error;
}

static void *run_engine(void *unused)
{
    (void)unused;
    int result = seekdb_ios_run(runtime.directory);
    pthread_mutex_lock(&runtime_lock);
    runtime.result = result;
    runtime.finished = true;
    pthread_mutex_unlock(&runtime_lock);
    return NULL;
}

static double monotonic_seconds(void)
{
    struct timespec now;
    clock_gettime(CLOCK_MONOTONIC, &now);
    return (double)now.tv_sec + (double)now.tv_nsec / 1000000000.0;
}

int seekdb_open(const char *db_dir, const char **parameters, SeekdbHandle *out_handle)
{
    last_open_error[0] = '\0';
    if (out_handle != NULL) {
        *out_handle = NULL;
    }
    if (out_handle == NULL || db_dir == NULL || db_dir[0] != '/') {
        snprintf(last_open_error, sizeof(last_open_error),
                 "iOS requires an absolute writable database directory and an output handle");
        return SEEKDB_INVALID_ARGUMENT;
    }
    if (parameters != NULL && parameters[0] != NULL) {
        snprintf(last_open_error, sizeof(last_open_error),
                 "iOS runtime does not support parameters; it uses memory_budget=1G, "
                 "vector_memory_limit=128M, log_disk_size=2G, mysql_port_mode=disabled, "
                 "sql_net_thread_count=2, and cpu_count=2");
        return SEEKDB_INVALID_ARGUMENT;
    }

    pthread_mutex_lock(&runtime_lock);
    if (runtime.claimed || seekdb_ios_get_state() != SEEKDB_IOS_IDLE) {
        pthread_mutex_unlock(&runtime_lock);
        snprintf(last_open_error, sizeof(last_open_error),
                 "iOS supports one engine invocation per process; another open or restart is unsupported");
        return SEEKDB_INTERNAL_ERROR;
    }
    runtime.directory = strdup(db_dir);
    if (runtime.directory == NULL) {
        pthread_mutex_unlock(&runtime_lock);
        snprintf(last_open_error, sizeof(last_open_error), "Unable to copy the iOS database directory");
        return SEEKDB_INTERNAL_ERROR;
    }

    pthread_attr_t attributes;
    int error = pthread_attr_init(&attributes);
    if (error == 0) {
        error = pthread_attr_setstacksize(&attributes, RUNTIME_STACK_SIZE);
        if (error == 0) {
            runtime.claimed = true;
            error = pthread_create(&runtime.thread, &attributes, run_engine, NULL);
        }
        pthread_attr_destroy(&attributes);
    }
    if (error != 0) {
        runtime.claimed = false;
        free(runtime.directory);
        runtime.directory = NULL;
        pthread_mutex_unlock(&runtime_lock);
        snprintf(last_open_error, sizeof(last_open_error), "Unable to start the iOS runtime thread: %s", strerror(error));
        return SEEKDB_INTERNAL_ERROR;
    }
    pthread_mutex_unlock(&runtime_lock);

    const double deadline = monotonic_seconds() + startup_timeout_seconds;
    for (;;) {
        pthread_mutex_lock(&runtime_lock);
        bool finished = runtime.finished;
        int result = runtime.result;
        pthread_mutex_unlock(&runtime_lock);
        if (finished) {
            /* Only this opener can join before a handle has been published. */
            error = pthread_join(runtime.thread, NULL);
            pthread_mutex_lock(&runtime_lock);
            runtime.joined = error == 0;
            pthread_mutex_unlock(&runtime_lock);
            snprintf(last_open_error, sizeof(last_open_error),
                     "iOS engine exited during startup (engine code %d); inspect log/seekdb.log; restart the application", result);
            return SEEKDB_INTERNAL_ERROR;
        }

        struct stat socket_info;
        if (seekdb_ios_get_state() == SEEKDB_IOS_RUNNING &&
            stat("run/sql.sock", &socket_info) == 0 && S_ISSOCK(socket_info.st_mode)) {
            pthread_mutex_lock(&runtime_lock);
            runtime.has_handle = true;
            *out_handle = &runtime;
            pthread_mutex_unlock(&runtime_lock);
            return SEEKDB_SUCCESS;
        }
        if (monotonic_seconds() >= deadline) {
            seekdb_ios_request_stop();
            pthread_detach(runtime.thread);
            snprintf(last_open_error, sizeof(last_open_error),
                     "iOS engine startup timed out waiting for RUNNING and run/sql.sock; "
                     "shutdown requested; inspect log/seekdb.log and restart the application");
            return SEEKDB_INTERNAL_ERROR;
        }
        const struct timespec interval = {0, 10000000};
        nanosleep(&interval, NULL);
    }
}

int seekdb_connection_options(SeekdbHandle handle, SeekdbConnectionOptions *out_options)
{
    if (out_options == NULL) {
        return SEEKDB_INVALID_ARGUMENT;
    }
    memset(out_options, 0, sizeof(*out_options));
    pthread_mutex_lock(&runtime_lock);
    if (handle != &runtime || !runtime.has_handle) {
        pthread_mutex_unlock(&runtime_lock);
        return SEEKDB_INVALID_ARGUMENT;
    }
    if (runtime.joining || seekdb_ios_get_state() != SEEKDB_IOS_RUNNING) {
        pthread_mutex_unlock(&runtime_lock);
        return SEEKDB_INTERNAL_ERROR;
    }
    out_options->transport = SEEKDB_CONNECTION_TRANSPORT_UNIX_SOCKET;
    out_options->unix_socket = "run/sql.sock";
    out_options->user = "root";
    pthread_mutex_unlock(&runtime_lock);
    return SEEKDB_SUCCESS;
}

int seekdb_close(SeekdbHandle handle)
{
    pthread_mutex_lock(&runtime_lock);
    if (handle != &runtime || !runtime.has_handle) {
        pthread_mutex_unlock(&runtime_lock);
        return SEEKDB_INVALID_ARGUMENT;
    }
    if (runtime.joining) {
        pthread_mutex_unlock(&runtime_lock);
        return SEEKDB_INTERNAL_ERROR;
    }
    runtime.joining = true;
    bool already_joined = runtime.joined;
    pthread_mutex_unlock(&runtime_lock);

    seekdb_ios_request_stop();
    int error = already_joined ? 0 : pthread_join(runtime.thread, NULL);
    pthread_mutex_lock(&runtime_lock);
    runtime.joining = false;
    if (error != 0) {
        pthread_mutex_unlock(&runtime_lock);
        return SEEKDB_INTERNAL_ERROR;
    }
    runtime.joined = true;
    if (runtime.result != 0) {
        /* Preserve the handle on every error, matching the Swift close contract.
         * Failed engine teardown cannot be retried as a new engine invocation. */
        pthread_mutex_unlock(&runtime_lock);
        return SEEKDB_INTERNAL_ERROR;
    }
    runtime.has_handle = false;
    pthread_mutex_unlock(&runtime_lock);
    return SEEKDB_SUCCESS;
}
#endif
