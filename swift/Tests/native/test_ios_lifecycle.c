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
/* Host-side runtime substitute. Compile the adapter with
 * SEEKDB_SWIFT_TEST_IOS to exercise iOS ownership without engine archives.
 * Each case runs in a separate process because the engine is single-use.
 */
#include "../../Sources/CSeekDB/include/CSeekDB.h"
#include "../../Sources/CSeekDB/Runtime/seekdb_ios.h"
#include <assert.h>
#include <fcntl.h>
#include <limits.h>
#include <pthread.h>
#include <stdatomic.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/un.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

enum { NORMAL, START_FAILURE, STOP_FAILURE, START_TIMEOUT, MISSING_SOCKET };
static int mode;
static atomic_int state = SEEKDB_IOS_IDLE;
static atomic_bool stop_requested;
static atomic_int invocation_count;
static char directory[PATH_MAX];
static char fixture[PATH_MAX];
static char original_directory[PATH_MAX];

static void pause_briefly(void)
{
    const struct timespec interval = {0, 1000000};
    nanosleep(&interval, NULL);
}

enum seekdb_ios_state seekdb_ios_get_state(void)
{
    return atomic_load(&state);
}

void seekdb_ios_request_stop(void)
{
    atomic_store(&stop_requested, true);
}

int seekdb_ios_run(const char *path)
{
    atomic_fetch_add(&invocation_count, 1);
    assert(strcmp(path, directory) == 0);
#ifdef __APPLE__
    assert(pthread_get_stacksize_np(pthread_self()) >= 8 * 1024 * 1024);
#endif
    atomic_store(&state, SEEKDB_IOS_STARTING);
    if (mode == START_FAILURE) {
        atomic_store(&state, SEEKDB_IOS_FAILED);
        return -42;
    }
    if (mode == START_TIMEOUT) {
        while (!atomic_load(&stop_requested)) {
            pause_briefly();
        }
        atomic_store(&state, SEEKDB_IOS_STOPPED);
        return 0;
    }

    int previous_directory = open(".", O_RDONLY);
    assert(previous_directory >= 0);
    assert(chdir(path) == 0);
    assert(mkdir("run", 0700) == 0);
    int listener = -1;
    if (mode != MISSING_SOCKET) {
        listener = socket(AF_UNIX, SOCK_STREAM, 0);
        assert(listener >= 0);
        struct sockaddr_un address = {0};
        address.sun_family = AF_UNIX;
        strcpy(address.sun_path, "run/sql.sock");
        assert(bind(listener, (struct sockaddr *)&address, sizeof(address)) == 0);
        assert(listen(listener, 1) == 0);
    }
    atomic_store(&state, SEEKDB_IOS_RUNNING);
    while (!atomic_load(&stop_requested)) {
        pause_briefly();
    }
    atomic_store(&state, SEEKDB_IOS_STOPPING);
    if (listener >= 0) {
        close(listener);
        assert(unlink("run/sql.sock") == 0);
    }
    assert(rmdir("run") == 0);
    assert(fchdir(previous_directory) == 0);
    close(previous_directory);
    atomic_store(&state, mode == STOP_FAILURE ? SEEKDB_IOS_FAILED : SEEKDB_IOS_STOPPED);
    return mode == STOP_FAILURE ? -43 : 0;
}

static void make_fixture(void)
{
    assert(getcwd(original_directory, sizeof(original_directory)) != NULL);
    assert(mkdir("build", 0700) == 0 || access("build", F_OK) == 0);
    assert(mkdir("build/swift-native-fixtures", 0700) == 0 || access("build/swift-native-fixtures", F_OK) == 0);
    assert(snprintf(fixture, sizeof(fixture), "%s/build/swift-native-fixtures/ios-XXXXXX", original_directory) < (int)sizeof(fixture));
    assert(mkdtemp(fixture) != NULL);
    /* An absolute socket endpoint here exceeds Darwin's 104-byte sun_path. */
    assert(snprintf(directory, sizeof(directory), "%s/%s", fixture,
                    "database-with-a-directory-name-long-enough-to-exceed-the-simulator-unix-socket-path-limit-0123456789") < (int)sizeof(directory));
    assert(mkdir(directory, 0700) == 0);
    assert(strlen(directory) + strlen("/run/sql.sock") >= sizeof(((struct sockaddr_un *)0)->sun_path));
}

static void remove_fixture(void)
{
    assert(chdir(original_directory) == 0);
    assert(rmdir(directory) == 0);
    assert(rmdir(fixture) == 0);
}

static void *fail_open_on_other_thread(void *unused)
{
    (void)unused;
    SeekdbHandle handle = NULL;
    const char *parameters[] = {"memory_budget", "2G", NULL};
    assert(seekdb_open(directory, parameters, &handle) == SEEKDB_INVALID_ARGUMENT);
    assert(strstr(seekdb_last_open_error(), "does not support parameters") != NULL);
    return NULL;
}

static void invalid_arguments(void)
{
    SeekdbHandle handle = (void *)1;
    assert(seekdb_last_open_error()[0] == '\0');
    assert(seekdb_open("relative", NULL, &handle) == SEEKDB_INVALID_ARGUMENT);
    assert(handle == NULL);
    char error[1024];
    strcpy(error, seekdb_last_open_error());
    pthread_t other;
    assert(pthread_create(&other, NULL, fail_open_on_other_thread, NULL) == 0);
    assert(pthread_join(other, NULL) == 0);
    assert(strcmp(seekdb_last_open_error(), error) == 0);
    assert(seekdb_open(NULL, NULL, &handle) == SEEKDB_INVALID_ARGUMENT);
    assert(seekdb_open(directory, NULL, NULL) == SEEKDB_INVALID_ARGUMENT);
    const char *parameters[] = {"memory_budget", "1G", NULL};
    assert(seekdb_open(directory, parameters, &handle) == SEEKDB_INVALID_ARGUMENT);
    assert(handle == NULL && atomic_load(&invocation_count) == 0);
    assert(seekdb_close(NULL) == SEEKDB_INVALID_ARGUMENT);
    SeekdbConnectionOptions options;
    assert(seekdb_connection_options(NULL, &options) == SEEKDB_INVALID_ARGUMENT);
    assert(seekdb_connection_options(NULL, NULL) == SEEKDB_INVALID_ARGUMENT);
    const char *empty_parameters[] = {NULL};
    assert(seekdb_open(directory, empty_parameters, &handle) == SEEKDB_SUCCESS);
    assert(seekdb_last_open_error()[0] == '\0');
    assert(seekdb_close(handle) == SEEKDB_SUCCESS);
}

static void lifecycle(void)
{
    SeekdbHandle handle = NULL;
    assert(seekdb_open(directory, NULL, &handle) == SEEKDB_SUCCESS);
    assert(handle != NULL && atomic_load(&invocation_count) == 1);
    SeekdbConnectionOptions options;
    assert(seekdb_connection_options(handle, &options) == SEEKDB_SUCCESS);
    assert(strcmp(options.transport, "unix_socket") == 0);
    assert(strcmp(options.unix_socket, "run/sql.sock") == 0);
    assert(strcmp(options.user, "root") == 0);
    assert(options.port == 0 && options.host == NULL && options.named_pipe == NULL);

    int client = socket(AF_UNIX, SOCK_STREAM, 0);
    assert(client >= 0);
    struct sockaddr_un address = {0};
    address.sun_family = AF_UNIX;
    strcpy(address.sun_path, options.unix_socket);
    assert(connect(client, (struct sockaddr *)&address, sizeof(address)) == 0);
    close(client);

    SeekdbHandle second = NULL;
    assert(seekdb_open(directory, NULL, &second) == SEEKDB_INTERNAL_ERROR);
    assert(second == NULL && atomic_load(&invocation_count) == 1);
    assert(seekdb_close(handle) == SEEKDB_SUCCESS);
    assert(atomic_load(&stop_requested));
    assert(seekdb_ios_get_state() == SEEKDB_IOS_STOPPED);
    char current[PATH_MAX];
    assert(getcwd(current, sizeof(current)) != NULL);
    assert(strcmp(current, original_directory) == 0);
    assert(seekdb_connection_options(handle, &options) == SEEKDB_INVALID_ARGUMENT);
    assert(seekdb_close(handle) == SEEKDB_INVALID_ARGUMENT);
    assert(seekdb_open(directory, NULL, &second) == SEEKDB_INTERNAL_ERROR);
    assert(atomic_load(&invocation_count) == 1);
}

static void startup_failure(void)
{
    mode = START_FAILURE;
    SeekdbHandle handle = (void *)1;
    assert(seekdb_open(directory, NULL, &handle) == SEEKDB_INTERNAL_ERROR);
    assert(handle == NULL);
    assert(strstr(seekdb_last_open_error(), "engine code -42") != NULL);
    assert(seekdb_open(directory, NULL, &handle) == SEEKDB_INTERNAL_ERROR);
    assert(atomic_load(&invocation_count) == 1);
}

static void shutdown_failure(void)
{
    mode = STOP_FAILURE;
    SeekdbHandle handle = NULL;
    assert(seekdb_open(directory, NULL, &handle) == SEEKDB_SUCCESS);
    assert(seekdb_close(handle) == SEEKDB_INTERNAL_ERROR);
    /* Failed close retains a valid failed handle, instead of a dangling one. */
    assert(seekdb_close(handle) == SEEKDB_INTERNAL_ERROR);
    SeekdbConnectionOptions options;
    assert(seekdb_connection_options(handle, &options) == SEEKDB_INTERNAL_ERROR);
    assert(atomic_load(&invocation_count) == 1);
}

static void timeout_case(int requested_mode)
{
    mode = requested_mode;
    SeekdbHandle handle = (void *)1;
    assert(seekdb_open(directory, NULL, &handle) == SEEKDB_INTERNAL_ERROR);
    assert(handle == NULL);
    assert(strstr(seekdb_last_open_error(), "timed out") != NULL);
    assert(atomic_load(&stop_requested));
    for (int i = 0; i < 1000 && seekdb_ios_get_state() != SEEKDB_IOS_STOPPED; ++i) {
        pause_briefly();
    }
    assert(seekdb_ios_get_state() == SEEKDB_IOS_STOPPED);
    assert(seekdb_open(directory, NULL, &handle) == SEEKDB_INTERNAL_ERROR);
    assert(atomic_load(&invocation_count) == 1);
}

static void startup_timeout(void) { timeout_case(START_TIMEOUT); }
static void missing_socket(void) { timeout_case(MISSING_SOCKET); }

int main(void)
{
    void (*cases[])(void) = {invalid_arguments, lifecycle, startup_failure,
                            shutdown_failure, startup_timeout, missing_socket};
    const char *names[] = {"invalid arguments and thread-local diagnostics", "lifecycle and long socket path",
                          "startup failure", "shutdown failure retains handle", "startup timeout", "missing socket timeout"};
    for (size_t i = 0; i < sizeof(cases) / sizeof(cases[0]); ++i) {
        pid_t child = fork();
        assert(child >= 0);
        if (child == 0) {
            make_fixture();
            cases[i]();
            remove_fixture();
            _exit(0);
        }
        int status;
        assert(waitpid(child, &status, 0) == child);
        assert(WIFEXITED(status) && WEXITSTATUS(status) == 0);
        printf("PASS %s\n", names[i]);
    }
    return 0;
}
