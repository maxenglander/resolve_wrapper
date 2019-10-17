project(tests C)

set(TORTURE_LIBRARY torture)

# A simple DNS server for testing
add_executable(dns_srv dns_srv.c)
target_compile_options(dns_srv PRIVATE ${DEFAULT_C_COMPILE_FLAGS})
target_include_directories(dns_srv PRIVATE ${CMAKE_BINARY_DIR})
target_link_libraries(dns_srv ${RWRAP_REQUIRED_LIBRARIES})

add_executable(test_real_res_query test_real_res_query.c)
target_compile_options(test_real_res_query PRIVATE ${DEFAULT_C_COMPILE_FLAGS})
target_include_directories(test_real_res_query PRIVATE ${CMAKE_BINARY_DIR} ${CMOCKA_INCLUDE_DIR})
target_link_libraries(test_real_res_query ${RWRAP_REQUIRED_LIBRARIES} ${CMOCKA_LIBRARY})

configure_file(fake_hosts.in ${CMAKE_CURRENT_BINARY_DIR}/fake_hosts @ONLY)

add_library(${TORTURE_LIBRARY} STATIC torture.c)
target_compile_options(${TORTURE_LIBRARY} PRIVATE ${DEFAULT_C_COMPILE_FLAGS})
target_include_directories(${TORTURE_LIBRARY} PRIVATE ${CMAKE_BINARY_DIR} ${CMOCKA_INCLUDE_DIR})
target_link_libraries(${TORTURE_LIBRARY}
    ${CMOCKA_LIBRARY}
    ${SWRAP_REQUIRED_LIBRARIES})


set(TESTSUITE_LIBRARIES ${RWRAP_REQUIRED_LIBRARIES} ${CMOCKA_LIBRARY})

# Some tests require socket_wrapper as well.
find_package(socket_wrapper REQUIRED)

set(RWRAP_TESTS test_res_init)

if (HAVE_LIBRESOLV)
    set(RWRAP_TESTS ${RWRAP_TESTS} test_res_query_search)
endif()

function(ADD_CMOCKA_TEST_ENVIRONMENT _TEST_NAME)
    if (CMAKE_BUILD_TYPE)
        string(TOLOWER "${CMAKE_BUILD_TYPE}" CMAKE_BUILD_TYPE_LOWER)
        if (CMAKE_BUILD_TYPE_LOWER STREQUAL "addresssanitizer")
            find_library(ASAN_LIBRARY
                         NAMES asan)
            if (NOT ASAN_LIBRARY)
                foreach(version RANGE 10 1)
                    if (NOT ASAN_LIBRARY)
                        find_library(ASAN_LIBRARY libasan.so.${version})
                    endif()
                endforeach()
            endif()
        endif()
    endif()

    if (ASAN_LIBRARY)
        list(APPEND PRELOAD_LIBRARIES ${ASAN_LIBRARY})
    endif()
    list(APPEND PRELOAD_LIBRARIES ${RESOLV_WRAPPER_LOCATION})
    list(APPEND PRELOAD_LIBRARIES ${SOCKET_WRAPPER_LIBRARY})

    if (OSX)
        set(TORTURE_ENVIRONMENT "DYLD_FORCE_FLAT_NAMESPACE=1;DYLD_INSERT_LIBRARIES=${RESOLV_WRAPPER_LOCATION}:${SOCKET_WRAPPER_LIBRARY}")
    else ()
        string(REPLACE ";" ":" _TMP_ENV "${PRELOAD_LIBRARIES}")
        set(TORTURE_ENVIRONMENT "LD_PRELOAD=${_TMP_ENV}")
    endif()

    list(APPEND TORTURE_ENVIRONMENT RESOLV_WRAPPER=1)

    foreach(_arg ${ARGN})
        list(APPEND TORTURE_ENVIRONMENT ${_arg})
    endforeach()

    set_property(TEST
                    ${_TEST_NAME}
                PROPERTY
                    ENVIRONMENT "${TORTURE_ENVIRONMENT}")
endfunction()

foreach(_RWRAP_TEST ${RWRAP_TESTS})
    add_cmocka_test(${_RWRAP_TEST}
                    SOURCES ${_RWRAP_TEST}.c
                    COMPILE_OPTIONS ${DEFAULT_C_COMPILE_FLAGS}
                    LINK_LIBRARIES ${TORTURE_LIBRARY} ${TESTSUITE_LIBRARIES}
                    LINK_OPTIONS ${DEFAULT_LINK_FLAGS})
    target_include_directories(${_RWRAP_TEST} PRIVATE ${CMAKE_BINARY_DIR} ${CMOCKA_INCLUDE_DIR})

    add_cmocka_test_environment(${_RWRAP_TEST})
endforeach()

add_cmocka_test(test_dns_fake
                SOURCES test_dns_fake.c
                COMPILE_OPTIONS ${DEFAULT_C_COMPILE_FLAGS}
                LINK_LIBRARIES ${TORTURE_LIBRARY} ${TESTSUITE_LIBRARIES}
                LINK_OPTIONS ${DEFAULT_LINK_FLAGS})
target_include_directories(test_dns_fake PRIVATE ${CMAKE_BINARY_DIR} ${CMOCKA_INCLUDE_DIR})
add_cmocka_test_environment(test_dns_fake RESOLV_WRAPPER_HOSTS=${CMAKE_CURRENT_BINARY_DIR}/fake_hosts)
