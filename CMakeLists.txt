cmake_minimum_required(VERSION 3.14)
project(seekdb_driver C CXX)

set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED ON)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

if(NOT CMAKE_BUILD_TYPE AND NOT CMAKE_CONFIGURATION_TYPES)
    set(CMAKE_BUILD_TYPE Release CACHE STRING "Build type" FORCE)
endif()

# Override CMake's default Release optimization (-O3) with -O2.
set(CMAKE_C_FLAGS_RELEASE   "-O2 -DNDEBUG" CACHE STRING "" FORCE)
set(CMAKE_CXX_FLAGS_RELEASE "-O2 -DNDEBUG" CACHE STRING "" FORCE)

enable_testing()

if (WIN32)
    add_compile_definitions(WIN32_LEAN_AND_MEAN)
endif()

if (ANDROID AND DEFINED OPENSSL_ROOT_DIR)
    list(APPEND CMAKE_FIND_ROOT_PATH "${OPENSSL_ROOT_DIR}")
endif()

set(WITH_UNIT_TESTS    OFF CACHE BOOL "" FORCE)
set(WITH_CURL          OFF CACHE BOOL "" FORCE)
set(WITH_DOCS          OFF CACHE BOOL "" FORCE)

# Windows-only workaround.
if(WIN32)
    set(ZLIB_LIBRARY zlib CACHE STRING "" FORCE)
endif()

set(CMAKE_POSITION_INDEPENDENT_CODE ON)

include(GNUInstallDirs)
set(INSTALL_PLUGINDIR "lib/mariadb/plugin")
set(INSTALL_LIBDIR    "lib")

add_subdirectory(deps/mariadb-connector-c EXCLUDE_FROM_ALL)

set(MARIADB_INCLUDE_DIRS
    "${CMAKE_CURRENT_SOURCE_DIR}/deps/mariadb-connector-c/include"
    "${CMAKE_CURRENT_BINARY_DIR}/deps/mariadb-connector-c/include")
set(MARIADB_LIBRARY mariadbclient)   # CMake target from the submodule

# ----------------------------------------------------------------------------
# seekdb_driver library
# ----------------------------------------------------------------------------

set(THREADS_PREFER_PTHREAD_FLAG ON)
find_package(Threads REQUIRED)

add_library(seekdb_driver_objs OBJECT
            src/seekdb.cc
            src/port.cc)

target_include_directories(seekdb_driver_objs
    PUBLIC  $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/include>
            $<INSTALL_INTERFACE:include>
    PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/src
            ${MARIADB_INCLUDE_DIRS})

set_property(TARGET seekdb_driver_objs PROPERTY POSITION_INDEPENDENT_CODE ON)

if (NOT MSVC)
    target_compile_options(seekdb_driver_objs PRIVATE -Wall -Wextra -Wno-unused-parameter)
endif()

# Enable the tlog timestamped debug prints. Off by default. When ON, the
# SEEKDB_ENABLE_LOG macro is defined for seekdb_driver_objs's compile units;
# tlog.h gates its body on that.
option(SEEKDB_ENABLE_LOG "Enable tlog() debug prints in seekdb_driver" OFF)
if (SEEKDB_ENABLE_LOG)
    target_compile_definitions(seekdb_driver_objs PRIVATE SEEKDB_ENABLE_LOG)
endif()

add_library(seekdb_driver        SHARED $<TARGET_OBJECTS:seekdb_driver_objs>)
add_library(seekdb_driver_static STATIC $<TARGET_OBJECTS:seekdb_driver_objs>)

if (NOT WIN32)
    set_target_properties(seekdb_driver_static PROPERTIES OUTPUT_NAME seekdb_driver)
endif()

set_target_properties(seekdb_driver PROPERTIES WINDOWS_EXPORT_ALL_SYMBOLS ON)

# Propagate include dirs + link deps to downstream consumers of either target.
foreach(_t seekdb_driver seekdb_driver_static)
    target_include_directories(${_t}
        PUBLIC  $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/include>
                $<INSTALL_INTERFACE:include>
        PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/src
                ${MARIADB_INCLUDE_DIRS})
    target_link_libraries(${_t} PRIVATE ${MARIADB_LIBRARY} Threads::Threads)
endforeach()

set(SEEKDB_BIN "$ENV{SEEKDB_BIN}" CACHE FILEPATH "Path to the seekdb server binary")

if (SEEKDB_BIN)
    if (NOT EXISTS "${SEEKDB_BIN}")
        message(FATAL_ERROR "SEEKDB_BIN does not exist: ${SEEKDB_BIN}")
    endif()
    add_custom_command(TARGET seekdb_driver POST_BUILD
        COMMAND ${CMAKE_COMMAND} -E copy_if_different
                "${SEEKDB_BIN}" "$<TARGET_FILE_DIR:seekdb_driver>")
    if (WIN32)
        get_filename_component(_seekdb_bin_dir "${SEEKDB_BIN}" DIRECTORY)
        file(GLOB _seekdb_runtime_dlls "${_seekdb_bin_dir}/*.dll")
        foreach(_dll ${_seekdb_runtime_dlls})
            add_custom_command(TARGET seekdb_driver POST_BUILD
                COMMAND ${CMAKE_COMMAND} -E copy_if_different
                        "${_dll}" "$<TARGET_FILE_DIR:seekdb_driver>")
        endforeach()
    endif()
endif()

# ----------------------------------------------------------------------------
# CLI tool
# ----------------------------------------------------------------------------

add_executable(seekdb_cli tools/seekdb_cli.c)
target_include_directories(seekdb_cli PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/src
    ${MARIADB_INCLUDE_DIRS})
target_link_libraries(seekdb_cli PRIVATE seekdb_driver)
# Look for libseekdb_driver.{so,dylib} in seekdb_cli's own dir at runtime
# so the binary works from any install location, not just the build tree.
# macOS dyld doesn't understand $ORIGIN; use @loader_path there.
if(APPLE)
    set(_seekdb_origin "@loader_path")
else()
    set(_seekdb_origin "\$ORIGIN")
endif()
set_target_properties(seekdb_cli PROPERTIES
    INSTALL_RPATH         "${_seekdb_origin}"
    BUILD_RPATH           "${_seekdb_origin}"
    BUILD_WITH_INSTALL_RPATH TRUE)

# ----------------------------------------------------------------------------
# Tests
# ----------------------------------------------------------------------------

# Google Test — vendored as a git submodule at deps/googletest, pinned
# to v1.14.0.
set(gtest_force_shared_crt ON CACHE BOOL "" FORCE)
add_subdirectory(deps/googletest EXCLUDE_FROM_ALL)
include(GoogleTest)

if(WIN32)
    set(SEEKDB_TEST_DATA_ROOT "${CMAKE_CURRENT_BINARY_DIR}/test_data")
else()
    set(SEEKDB_TEST_DATA_ROOT "/tmp/seekdb_tests")
endif()

if (NOT WIN32)
add_executable(test_one_client_process tests/test_one_client_process.cc)
target_include_directories(test_one_client_process PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/src ${MARIADB_INCLUDE_DIRS})
target_compile_definitions(test_one_client_process PRIVATE SEEKDB_TEST_DATA_ROOT="${SEEKDB_TEST_DATA_ROOT}")
target_link_libraries(test_one_client_process PRIVATE seekdb_driver GTest::gtest_main)
gtest_discover_tests(test_one_client_process DISCOVERY_MODE PRE_TEST)
endif()

add_executable(test_two_clients_threads tests/test_two_clients_threads.cc)
target_include_directories(test_two_clients_threads PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/src ${MARIADB_INCLUDE_DIRS})
target_compile_definitions(test_two_clients_threads PRIVATE SEEKDB_TEST_DATA_ROOT="${SEEKDB_TEST_DATA_ROOT}")
target_link_libraries(test_two_clients_threads PRIVATE seekdb_driver GTest::gtest_main)
gtest_discover_tests(test_two_clients_threads DISCOVERY_MODE PRE_TEST)

# ----------------------------------------------------------------------------
# Python bindings
# ----------------------------------------------------------------------------

option(SEEKDB_BUILD_PYTHON "Build the pylibseekdb Python extension (requires Python3 + pybind11)" OFF)
if (SEEKDB_BUILD_PYTHON)
    add_subdirectory(python)
endif()

