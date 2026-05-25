if(WIN32)
    set(SEEKDB_TEST_DATA_ROOT "${CMAKE_CURRENT_BINARY_DIR}/test_data")
else()
    set(SEEKDB_TEST_DATA_ROOT "/tmp/seekdb_tests")
endif()

if (NOT WIN32)
    add_executable(test_one_client_process test_one_client_process.cc)
    target_include_directories(test_one_client_process PRIVATE
        ${CMAKE_SOURCE_DIR}/c/src
        ${MARIADB_INCLUDE_DIRS})
    target_compile_definitions(test_one_client_process PRIVATE
        SEEKDB_TEST_DATA_ROOT="${SEEKDB_TEST_DATA_ROOT}")
    target_link_libraries(test_one_client_process PRIVATE seekdb_driver GTest::gtest_main)
    gtest_discover_tests(test_one_client_process DISCOVERY_MODE PRE_TEST)
endif()

add_executable(test_two_clients_threads test_two_clients_threads.cc)
target_include_directories(test_two_clients_threads PRIVATE
    ${CMAKE_SOURCE_DIR}/c/src
    ${MARIADB_INCLUDE_DIRS})
target_compile_definitions(test_two_clients_threads PRIVATE
    SEEKDB_TEST_DATA_ROOT="${SEEKDB_TEST_DATA_ROOT}")
target_link_libraries(test_two_clients_threads PRIVATE seekdb_driver GTest::gtest_main)
gtest_discover_tests(test_two_clients_threads DISCOVERY_MODE PRE_TEST)
