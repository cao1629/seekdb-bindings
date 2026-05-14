cmake_minimum_required(VERSION 3.18)
project(python-client LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

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
# layout is different. The directory must already contain both
# libseekdb_client.so and the seekdb binary (produced by the top-level build
# with -DSEEKDB_BIN=<path>).
set(SEEKDB_CLIENT_LIB_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../build" CACHE PATH
    "Build dir containing libseekdb_client.so and the seekdb binary")

if (NOT EXISTS "${SEEKDB_CLIENT_LIB_DIR}/libseekdb_client.so")
    message(FATAL_ERROR
        "libseekdb_client.so not found at ${SEEKDB_CLIENT_LIB_DIR}.\n"
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
    "${SEEKDB_CLIENT_LIB_DIR}/libseekdb_client.so"
)

# libseekdb_client.so and the seekdb binary are both expected to live next to
# pylibseekdb.so at runtime (matches the wheel-bundling layout, and lets
# seekdb_open()'s dladdr-based binary discovery find seekdb in the same dir).
# RPATH=$ORIGIN makes the dynamic linker look alongside the extension.
set_target_properties(pylibseekdb PROPERTIES
    INSTALL_RPATH         "$ORIGIN"
    BUILD_RPATH           "$ORIGIN"
    BUILD_WITH_INSTALL_RPATH TRUE
)

# In-tree dev: copy libseekdb_client.so + seekdb into this python build dir at
# CONFIGURE time so $ORIGIN-RPATH (and seekdb_open's dladdr discovery) find
# them next to pylibseekdb.so when running tests via PYTHONPATH=python/build.
file(COPY "${SEEKDB_CLIENT_LIB_DIR}/libseekdb_client.so" DESTINATION "${CMAKE_BINARY_DIR}")
file(COPY "${SEEKDB_CLIENT_LIB_DIR}/seekdb"              DESTINATION "${CMAKE_BINARY_DIR}")

# Wheel-build install rules (dormant during cmake --build; fired by
# scikit-build-core when building a wheel via `python -m build`).
# All three artifacts land inside the wheel's pylibseekdb/ package dir.
install(TARGETS pylibseekdb LIBRARY DESTINATION pylibseekdb)
install(FILES "${SEEKDB_CLIENT_LIB_DIR}/libseekdb_client.so"
        DESTINATION pylibseekdb)
install(PROGRAMS "${SEEKDB_CLIENT_LIB_DIR}/seekdb"
        DESTINATION pylibseekdb)
# Runtime deps of the seekdb binary that aren't shipped on every distro.
# Staged into ${SEEKDB_CLIENT_LIB_DIR} by the cibuildwheel before-build hook.
install(FILES "${SEEKDB_CLIENT_LIB_DIR}/libaio.so.1"
        DESTINATION pylibseekdb
        OPTIONAL)
