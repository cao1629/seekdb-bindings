// Copyright (c) 2026 OceanBase.
// SPDX-License-Identifier: Apache-2.0
#import <UIKit/UIKit.h>
#include "stability.h"
#include "client.h"
#include <algorithm>
#include <atomic>
#include <chrono>
#include <cstdlib>
#include <cstring>
#include <mach/mach.h>
#include <os/proc.h>
#include <pthread.h>
#include <string>
#include <thread>

namespace {
using Clock = std::chrono::steady_clock;

/** Read UIKit state on its owning thread so background suspension cannot count as a pass. */
bool foreground()
{
  __block bool active = false;
  dispatch_sync(dispatch_get_main_queue(), ^{ active = UIApplication.sharedApplication.applicationState == UIApplicationStateActive; });
  return active;
}

/** Measure this process's physical footprint; never substitute virtual allocation for resident cost. */
bool footprint(uint64_t &bytes)
{
  task_vm_info_data_t information{};
  mach_msg_type_number_t count = TASK_VM_INFO_COUNT;
  if (task_info(mach_task_self(), TASK_VM_INFO, reinterpret_cast<task_info_t>(&information), &count) != KERN_SUCCESS) {
    return false;
  }
  bytes = information.phys_footprint;
  return true;
}

/** Own one independent socket reader and its counters until the main worker joins it. */
struct Reader {
  const char *socket;
  std::atomic<bool> stop{false};
  std::atomic<bool> failed{false};
  std::atomic<uint64_t> reads{0};
  std::atomic<uint64_t> connections{0};
};

/** Reconnect periodically while reading committed state concurrently with the writer. */
void *read_loop(void *opaque)
{
  auto &state = *static_cast<Reader *>(opaque);
  mysql_thread_init();
  MYSQL *connection = nullptr;
  while (!state.stop.load()) {
    if (connection == nullptr) {
      connection = mysql_init(nullptr);
      if (!connect_socket_client(connection, state.socket, "framework_probe")) {
        state.failed.store(true);
        break;
      }
      state.connections.fetch_add(1);
      if (!execute_sql(connection, "SET ob_query_timeout=2000000")) {
        state.failed.store(true);
        break;
      }
    }
    int64_t value = -1;
    if (!read_int64(connection, "SELECT n FROM stability_counter WHERE id=1", value) || value < 0) {
      state.failed.store(true);
      break;
    }
    uint64_t reads = state.reads.fetch_add(1) + 1;
    if (reads % 32 == 0) {
      mysql_close(connection);
      connection = nullptr;
    }
    std::this_thread::sleep_for(std::chrono::milliseconds(100));
  }
  if (connection != nullptr) {
    mysql_close(connection);
  }
  mysql_thread_end();
  return nullptr;
}

/** Repeat committed and rolled-back updates and check exact visibility after each one. */
bool write_iteration(MYSQL *connection, uint64_t iteration, int64_t &expected)
{
  if (!execute_sql(connection, "START TRANSACTION")) {
    return false;
  }
  if (!execute_sql(connection, "UPDATE stability_counter SET n=n+1, payload='中文🙂稳定性测试' WHERE id=1")) {
    execute_sql(connection, "ROLLBACK");
    return false;
  }
  bool commit = iteration % 2 == 0;
  if (!execute_sql(connection, commit ? "COMMIT" : "ROLLBACK")) {
    return false;
  }
  expected += commit ? 1 : 0;
  int64_t actual = -1;
  return read_int64(connection, "SELECT n FROM stability_counter WHERE id=1", actual) && actual == expected;
}
} // namespace

/** Keep a bounded workload and its persistence proof separate from the basic lifecycle assertions. */
bool run_framework_stability(MYSQL *connection, const char *socket, NSMutableDictionary *report,
                             const std::function<void()> &checkpoint)
{
  const char *setting = getenv("SEEKDB_FRAMEWORK_STABILITY_SECONDS");
  if (setting == nullptr) {
    return true;
  }
  NSMutableDictionary *status = [NSMutableDictionary dictionary];
  report[@"stability"] = status;
  status[@"passed"] = @NO;
  char *end = nullptr;
  long seconds = strtol(setting, &end, 10);
  if (setting[0] == '\0' || *end != '\0' || seconds < 0 || seconds > 1800 || (seconds > 0 && seconds < 60)) {
    status[@"failure"] = @"duration must be zero or between 60 and 1800 seconds";
    checkpoint();
    return false;
  }
  status[@"requested_seconds"] = @(seconds);
  if (seconds == 0) {
    int64_t counter = -1;
    bool success = read_int64(connection, "SELECT n FROM stability_counter WHERE id=1", counter) && counter >= 0;
    status[@"mode"] = @"restart-persistence";
    status[@"final_counter"] = @(counter);
    status[@"passed"] = @(success);
    checkpoint();
    return success;
  }
  status[@"mode"] = @"foreground-soak";
  if (!execute_sql(connection, "CREATE TABLE IF NOT EXISTS stability_counter (id BIGINT PRIMARY KEY,n BIGINT NOT NULL,payload VARCHAR(512))")
      || !execute_sql(connection, "INSERT IGNORE INTO stability_counter VALUES (1,0,'')")
      || !execute_sql(connection, "SET ob_query_timeout=2000000")) {
    status[@"failure"] = @"workload setup failed";
    checkpoint();
    return false;
  }
  int64_t expected = -1;
  if (!read_int64(connection, "SELECT n FROM stability_counter WHERE id=1", expected)) {
    return false;
  }
  status[@"previous_counter"] = @(expected);
  Reader reader{socket};
  pthread_t thread;
  if (pthread_create(&thread, nullptr, read_loop, &reader) != 0) {
    status[@"failure"] = @"reader thread creation failed";
    checkpoint();
    return false;
  }
  // Run a fixed-size data workload and checkpoint process footprint after warmup.
  auto start = Clock::now();
  NSMutableArray *samples = [NSMutableArray array];
  status[@"samples"] = samples;
  uint64_t iterations = 0, baseline = 0, peak = 0, warmup_peak = 0;
  long warmup_seconds = std::min(60L, seconds / 2);
  status[@"warmup_seconds"] = @(warmup_seconds);
  double next_sample = 0, elapsed = 0, maximum_latency_ms = 0;
  bool success = true;
  while ((elapsed = std::chrono::duration<double>(Clock::now() - start).count()) < seconds) {
    @autoreleasepool {
      if (!foreground()) {
        status[@"failure"] = @"App left foreground";
        success = false;
        break;
      }
      auto operation = Clock::now();
      if (reader.failed.load() || !write_iteration(connection, iterations, expected)) {
        status[@"failure"] = @"socket SQL check failed";
        success = false;
        break;
      }
      double latency = std::chrono::duration<double, std::milli>(Clock::now() - operation).count();
      maximum_latency_ms = std::max(maximum_latency_ms, latency);
      ++iterations;
      if (elapsed >= next_sample) {
        uint64_t current = 0;
        if (!footprint(current)) {
          status[@"failure"] = @"physical footprint measurement failed";
          success = false;
          break;
        }
        peak = std::max(peak, current);
        if (elapsed >= warmup_seconds && baseline == 0) {
          baseline = current;
        }
        if (baseline > 0) {
          warmup_peak = std::max(warmup_peak, current);
        }
        [samples addObject:@{@"elapsed_seconds": @(elapsed), @"phys_footprint": @(current),
          @"available_memory": @(os_proc_available_memory())}];
        status[@"iterations"] = @(iterations);
        status[@"reader_queries"] = @(reader.reads.load());
        status[@"reader_connections"] = @(reader.connections.load());
        status[@"elapsed_seconds"] = @(elapsed);
        checkpoint();
        if (baseline > 0 && current > baseline + 256ULL * 1024 * 1024) {
          status[@"failure"] = @"footprint grew over 256 MiB after warmup";
          success = false;
          break;
        }
        next_sample += 10;
      }
      std::this_thread::sleep_for(std::chrono::milliseconds(200));
    }
  }
  // Join the client worker before the enclosing probe closes the engine handle.
  reader.stop.store(true);
  bool joined = pthread_join(thread, nullptr) == 0;
  if (!joined) {
    status[@"failure"] = @"reader join failed";
    status[@"reader_thread_exit"] = @NO;
    checkpoint();
    std::abort();
  }
  elapsed = std::chrono::duration<double>(Clock::now() - start).count();
  status[@"reader_thread_exit"] = @(joined);
  status[@"reader_queries"] = @(reader.reads.load());
  status[@"reader_connections"] = @(reader.connections.load());
  status[@"iterations"] = @(iterations);
  status[@"elapsed_seconds"] = @(elapsed);
  status[@"final_counter"] = @(expected);
  status[@"peak_phys_footprint"] = @(peak);
  status[@"warmup_baseline_phys_footprint"] = @(baseline);
  status[@"post_warmup_peak_phys_footprint"] = @(warmup_peak);
  status[@"growth_limit_bytes"] = @(256ULL * 1024 * 1024);
  status[@"maximum_iteration_latency_ms"] = @(maximum_latency_ms);
  success = success && joined && !reader.failed.load() && elapsed >= seconds && iterations >= 100
    && reader.reads.load() >= 100 && reader.connections.load() >= 2 && baseline > 0;
  status[@"passed"] = @(success);
  checkpoint();
  return success;
}
