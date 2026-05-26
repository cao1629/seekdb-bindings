cmake_minimum_required(VERSION 3.20)
project(seekdb_driver C CXX)

set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED ON)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

if(NOT CMAKE_BUILD_TYPE AND NOT CMAKE_CONFIGURATION_TYPES)
    set(CMAKE_BUILD_TYPE Release CACHE STRING "Build type" FORCE)
endif()

set(CMAKE_C_FLAGS_RELEASE   "-O2 -DNDEBUG" CACHE STRING "")
set(CMAKE_CXX_FLAGS_RELEASE "-O2 -DNDEBUG" CACHE STRING "")

include(CTest)

if (WIN32)
    add_compile_definitions(WIN32_LEAN_AND_MEAN)
endif()

if (ANDROID AND DEFINED OPENSSL_ROOT_DIR)
    list(APPEND CMAKE_FIND_ROOT_PATH "${OPENSSL_ROOT_DIR}")
endif()

set(CMAKE_POSITION_INDEPENDENT_CODE ON)

option(SEEKDB_BUILD_PYTHON "Build the pylibseekdb Python extension"      ON)
option(SEEKDB_BUILD_CLI    "Build the seekdb_cli executable"             ON)
option(SEEKDB_ENABLE_LOG   "Enable tlog() debug prints in seekdb_driver" OFF)

set(SEEKDB_BIN "$ENV{SEEKDB_BIN}" CACHE FILEPATH "Path to the seekdb server binary")

set(WITH_UNIT_TESTS OFF CACHE BOOL "" FORCE)
set(WITH_CURL       OFF CACHE BOOL "" FORCE)
set(WITH_DOCS       OFF CACHE BOOL "" FORCE)
if(WIN32)
    set(ZLIB_LIBRARY zlib CACHE STRING "" FORCE)
endif()

include(GNUInstallDirs)
set(INSTALL_PLUGINDIR "lib/mariadb/plugin")
set(INSTALL_LIBDIR    "lib")
add_subdirectory(deps/mariadb-connector-c EXCLUDE_FROM_ALL)

add_library(mariadb_client INTERFACE)
target_include_directories(mariadb_client INTERFACE
    "${CMAKE_CURRENT_SOURCE_DIR}/deps/mariadb-connector-c/include"
    "${CMAKE_CURRENT_BINARY_DIR}/deps/mariadb-connector-c/include")
target_link_libraries(mariadb_client INTERFACE mariadbclient)

if (BUILD_TESTING)
    set(gtest_force_shared_crt ON CACHE BOOL "" FORCE)
    add_subdirectory(deps/googletest EXCLUDE_FROM_ALL)
    include(GoogleTest)
endif()

add_subdirectory(driver)

if (SEEKDB_BUILD_PYTHON)
    add_subdirectory(python)
endif()
