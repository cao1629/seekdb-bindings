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
// Copyright (c) 2026 OceanBase.
// SPDX-License-Identifier: Apache-2.0
#pragma once

/* Private runtime ABI from cao1629/seekdb, codex/iphone-arm64-port
 * 60ab0316de669395cb6ddc3988854087ca26b0f9, src/observer/ios/seekdb_ios.h.
 * Keep these declarations synchronized with the linked engine archives.
 */
#ifdef __cplusplus
extern "C" {
#endif

enum seekdb_ios_state {
    SEEKDB_IOS_IDLE = 0,
    SEEKDB_IOS_STARTING = 1,
    SEEKDB_IOS_RUNNING = 2,
    SEEKDB_IOS_STOPPING = 3,
    SEEKDB_IOS_STOPPED = 4,
    SEEKDB_IOS_FAILED = 5
};

int seekdb_ios_run(const char *absolute_directory);
void seekdb_ios_request_stop(void);
enum seekdb_ios_state seekdb_ios_get_state(void);

#ifdef __cplusplus
}
#endif
