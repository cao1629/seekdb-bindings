cmake_minimum_required(VERSION 3.18)
project(python-client LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

# Default to Release with -O2 (not CMake's default -O3) when no build type
# is set. scikit-build-core / cibuildwheel typically invoke this CMakeLists
# without -DCMAKE_BUILD_TYPE, so this is the path that fires in practice.
if(NOT CMAKE_BUILD_TYPE AND NOT CMAKE_CONFIGURATION_TYPES)
    set(CMAKE_BUILD_TYPE Release CACHE STRING "Build type" FORCE)
endif()
set(CMAKE_C_FLAGS_RELEASE   "-O2 -DNDEBUG" CACHE STRING "" FORCE)
set(CMAKE_CXX_FLAGS_RELEASE "-O2 -DNDEBUG" CACHE STRING "" FORCE)

# ------ Find Python + pybind11 ------
find_package(Python3 COMPONENTS Interpreter Development.Module REQUIRED)
execute_process(
    COMMAND "${Python3_EXECUTABLE}" -c "import pybind11; print(pybind11.get_cmake_dir())"
    OUTPUT_VARIABLE pybind11_DIR
    OUTPUT_STRIP_TRAILING_WHITESPACE
    RESULT_VARIABLE _pybind11_rc
)
if(NOT _pybind11_rc EQUAL 0)
    message(FATAL_ERROR "pybind11 not importable in ${Python3_EXECUTABLE}. Install with: pip install --user pybind11")
endif()
message(STATUS "pybind11 cmake dir: ${pybind11_DIR}")
find_package(pybind11 CONFIG REQUIRED)

# ------ seekdb-client build location ------
# Defaults to the top-level project's build/ directory (../build relative to
# this python/ subdir). Override with -DSEEKDB_CLIENT_LIB_DIR=<path> if your
# layout is different. The directory must already contain both the
# libseekdb_client shared library and the seekdb binary (produced by the
# top-level build with -DSEEKDB_BIN=<path>).
set(SEEKDB_CLIENT_LIB_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../build" CACHE PATH
    "Build dir containing libseekdb_client.{so,dylib} and the seekdb binary")

# Shared-lib suffix is .so on Linux, .dylib on macOS, .dll on Windows.
set(_seekdb_client_lib
    "${SEEKDB_CLIENT_LIB_DIR}/libseekdb_client${CMAKE_SHARED_LIBRARY_SUFFIX}")

if (NOT EXISTS "${_seekdb_client_lib}")
    message(FATAL_ERROR
        "libseekdb_client${CMAKE_SHARED_LIBRARY_SUFFIX} not found at ${SEEKDB_CLIENT_LIB_DIR}.\n"
        "Build the top-level project first, or pass\n"
        "    -DSEEKDB_CLIENT_LIB_DIR=<path-to-build-dir>")
endif()
if (NOT EXISTS "${SEEKDB_CLIENT_LIB_DIR}/seekdb")
    message(FATAL_ERROR
        "seekdb binary not found at ${SEEKDB_CLIENT_LIB_DIR}/seekdb.\n"
        "Configure the top-level build with -DSEEKDB_BIN=<path-to-seekdb>.")
endif()

# ------ Build the extension ------
# Module name `pylibseekdb` — distinct from `libseekdb_client.so` to avoid
# CMake target/link-library name collision.
pybind11_add_module(pylibseekdb src/bindings.cpp)

target_include_directories(pylibseekdb PRIVATE
    "${CMAKE_CURRENT_SOURCE_DIR}/../include")
target_link_libraries(pylibseekdb PRIVATE
    "${_seekdb_client_lib}"
)

# libseekdb_client.{so,dylib} and the seekdb binary are both expected to live
# next to pylibseekdb at runtime (matches the wheel-bundling layout, and lets
# seekdb_open()'s dladdr-based binary discovery find seekdb in the same dir).
# RPATH/@loader_path makes the dynamic linker look alongside the extension.
# macOS dyld doesn't understand $ORIGIN; use @loader_path there.
if(APPLE)
    set(_seekdb_origin "@loader_path")
else()
    set(_seekdb_origin "\$ORIGIN")
endif()
set_target_properties(pylibseekdb PROPERTIES
    INSTALL_RPATH         "${_seekdb_origin}"
    BUILD_RPATH           "${_seekdb_origin}"
    BUILD_WITH_INSTALL_RPATH TRUE
)

# In-tree dev: copy libseekdb_client + seekdb into this python build dir at
# CONFIGURE time so $ORIGIN/@loader_path RPATH (and seekdb_open's dladdr
# discovery) find them next to pylibseekdb at runtime when running tests via
# PYTHONPATH=python/build.
file(COPY "${_seekdb_client_lib}"            DESTINATION "${CMAKE_BINARY_DIR}")
file(COPY "${SEEKDB_CLIENT_LIB_DIR}/seekdb"  DESTINATION "${CMAKE_BINARY_DIR}")

# Wheel-build install rules (dormant during cmake --build; fired by
# scikit-build-core when building a wheel via `python -m build`).
# All three artifacts land inside the wheel's pylibseekdb/ package dir.
install(TARGETS pylibseekdb LIBRARY DESTINATION pylibseekdb)
install(FILES "${_seekdb_client_lib}"
        DESTINATION pylibseekdb)
install(PROGRAMS "${SEEKDB_CLIENT_LIB_DIR}/seekdb"
        DESTINATION pylibseekdb)
# Runtime deps of the seekdb binary that aren't shipped on every distro.
# Staged into ${SEEKDB_CLIENT_LIB_DIR} by the cibuildwheel before-build hook.
install(FILES "${SEEKDB_CLIENT_LIB_DIR}/libaio.so.1"
        DESTINATION pylibseekdb
        OPTIONAL)
