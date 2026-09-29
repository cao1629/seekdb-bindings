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
#pragma once

#include "../../../../lib/include/seekdb/seekdb.h"

/* The iOS adapter implements only open, last_open_error, connection_options,
 * and close. It runs the engine in this process on a dedicated thread. All
 * nonempty parameter lists are unsupported, and only one open can succeed per
 * process. Open and close block: call them away from the UI thread.
 *
 * iOS returns the relative Unix socket path run/sql.sock. The runtime changes
 * the process working directory to the database directory; the application
 * must not change it until close completes. Close requests shutdown and joins
 * the runtime thread, with no shutdown timeout. On a close error the handle is
 * retained; engine failure may require terminating the application process.
 * Disconnect all SQL clients before closing the handle.
 */
