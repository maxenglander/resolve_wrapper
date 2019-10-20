include(CheckIncludeFile)
include(CheckSymbolExists)
include(CheckFunctionExists)
include(CheckLibraryExists)
include(CheckTypeSize)
include(CheckStructHasMember)
include(CheckPrototypeDefinition)
include(TestBigEndian)

set(PACKAGE ${PROJECT_NAME})
set(VERSION ${PROJECT_VERSION})
set(DATADIR ${DATA_INSTALL_DIR})
set(LIBDIR ${LIB_INSTALL_DIR})
set(PLUGINDIR "${PLUGIN_INSTALL_DIR}-${LIBRARY_SOVERSION}")
set(SYSCONFDIR ${SYSCONF_INSTALL_DIR})

set(BINARYDIR ${resolv_wrapper_BINARY_DIR})
set(SOURCEDIR ${resolv_wrapper_SOURCE_DIR})

function(COMPILER_DUMPVERSION _OUTPUT_VERSION)
    # Remove whitespaces from the argument.
    # This is needed for CC="ccache gcc" cmake ..
    string(REPLACE " " "" _C_COMPILER_ARG "${CMAKE_C_COMPILER_ARG1}")

    execute_process(
        COMMAND
            ${CMAKE_C_COMPILER} ${_C_COMPILER_ARG} -dumpversion
        OUTPUT_VARIABLE _COMPILER_VERSION
    )

    string(REGEX REPLACE "([0-9])\\.([0-9])(\\.[0-9])?" "\\1\\2"
           _COMPILER_VERSION "${_COMPILER_VERSION}")

    set(${_OUTPUT_VERSION} ${_COMPILER_VERSION} PARENT_SCOPE)
endfunction()

if(CMAKE_COMPILER_IS_GNUCC AND NOT MINGW AND NOT OS2)
    compiler_dumpversion(GNUCC_VERSION)
    if (NOT GNUCC_VERSION EQUAL 34)
        set(CMAKE_REQUIRED_FLAGS "-fvisibility=hidden")
        check_c_source_compiles(
"void __attribute__((visibility(\"default\"))) test() {}
int main(void){ return 0; }
" WITH_VISIBILITY_HIDDEN)
        set(CMAKE_REQUIRED_FLAGS "")
    endif (NOT GNUCC_VERSION EQUAL 34)
endif(CMAKE_COMPILER_IS_GNUCC AND NOT MINGW AND NOT OS2)

# HEADERS
check_include_file(sys/types.h HAVE_SYS_TYPES_H)
check_include_file(resolv.h HAVE_RESOLV_H)
check_include_file(arpa/nameser.h HAVE_ARPA_NAMESER_H)

# FUNCTIONS
find_library(RESOLV_LIRBRARY resolv)
if (RESOLV_LIRBRARY)
    check_library_exists(${RESOLV_LIRBRARY} res_send "" RES_SEND_IN_LIBRESOLV)
    check_library_exists(${RESOLV_LIRBRARY} __res_send "" __RES_SEND_IN_LIBRESOLV)
    if (RES_SEND_IN_LIBRESOLV OR __RES_SEND_IN_LIBRESOLV)
        set(HAVE_LIBRESOLV TRUE)
    endif()

    # If we have a libresolv, we need to check functions linking the library
    set(CMAKE_REQUIRED_LIBRARIES ${RESOLV_LIRBRARY})
endif()

check_function_exists(res_init HAVE_RES_INIT)
check_function_exists(__res_init HAVE___RES_INIT)

check_function_exists(res_ninit HAVE_RES_NINIT)
check_function_exists(__res_ninit HAVE___RES_NINIT)
if (RESOLV_LIRBRARY)
    check_library_exists(${RESOLV_LIRBRARY} res_ninit "" HAVE_RES_NINIT_IN_LIBRESOLV)
endif()

check_function_exists(res_close HAVE_RES_CLOSE)
check_function_exists(__res_close HAVE___RES_CLOSE)

check_function_exists(res_nclose HAVE_RES_NCLOSE)
check_function_exists(__res_nclose HAVE___RES_NCLOSE)
if (RESOLV_LIRBRARY)
    check_library_exists(${RESOLV_LIRBRARY} res_nclose "" HAVE_RES_NCLOSE_IN_LIBRESOLV)
endif()

check_function_exists(res_query HAVE_RES_QUERY)
check_function_exists(__res_query HAVE___RES_QUERY)

check_function_exists(res_nquery HAVE_RES_NQUERY)
check_function_exists(__res_nquery HAVE___RES_NQUERY)

check_function_exists(res_search HAVE_RES_SEARCH)
check_function_exists(__res_search HAVE___RES_SEARCH)

check_function_exists(res_nsearch HAVE_RES_NSEARCH)
check_function_exists(__res_nsearch HAVE___RES_NSEARCH)

unset(CMAKE_REQUIRED_LIBRARIES)

check_symbol_exists(ns_name_compress "sys/types.h;arpa/nameser.h" HAVE_NS_NAME_COMPRESS)

if (UNIX)
    if (NOT LINUX)
        # libsocket (Solaris)
        find_library(SOCKET_LIBRARY socket)
        if (SOCKET_LIBRARY)
            check_library_exists(${SOCKET_LIBRARY} getaddrinfo "" HAVE_LIBSOCKET)
        endif()

        # libnsl/inet_pton (Solaris)
        find_library(NSL_LIBRARY nsl)
        if (NSL_LIBRARY)
            check_library_exists(${NSL_LIBRARY} inet_pton "" HAVE_LIBNSL)
        endif()
    endif (NOT LINUX)

    check_function_exists(getaddrinfo HAVE_GETADDRINFO)
endif (UNIX)

find_library(DLFCN_LIBRARY dl)
if (DLFCN_LIBRARY)
    check_library_exists(${DLFCN_LIBRARY} dlopen "" HAVE_LIBDL)
endif()

# IPV6
check_c_source_compiles("
    #include <stdlib.h>
    #include <sys/socket.h>
    #include <netdb.h>
    #include <netinet/in.h>
    #include <net/if.h>

int main(void) {
    struct sockaddr_storage sa_store;
    struct addrinfo *ai = NULL;
    struct in6_addr in6addr;
    int idx = if_nametoindex(\"iface1\");
    int s = socket(AF_INET6, SOCK_STREAM, 0);
    int ret = getaddrinfo(NULL, NULL, NULL, &ai);
    if (ret != 0) {
        const char *es = gai_strerror(ret);
    }

    freeaddrinfo(ai);
    {
        int val = 1;
#ifdef HAVE_LINUX_IPV6_V6ONLY_26
#define IPV6_V6ONLY 26
#endif
        ret = setsockopt(s, IPPROTO_IPV6, IPV6_V6ONLY,
                         (const void *)&val, sizeof(val));
    }

    return 0;
}" HAVE_IPV6)

check_struct_has_member("struct __res_state" _u._ext.nsaddrs resolv.h HAVE_RESOLV_IPV6_NSADDRS)

check_c_source_compiles("
void log_fn(const char *format, ...) __attribute__ ((format (printf, 1, 2)));

int main(void) {
    return 0;
}" HAVE_ATTRIBUTE_PRINTF_FORMAT)

check_c_source_compiles("
void test_destructor_attribute(void) __attribute__ ((destructor));

void test_destructor_attribute(void)
{
    return;
}

int main(void) {
    return 0;
}" HAVE_DESTRUCTOR_ATTRIBUTE)

# ENDIAN
test_big_endian(WORDS_BIGENDIAN)

set(RWRAP_REQUIRED_LIBRARIES ${RESOLV_LIRBRARY} ${DLFCN_LIBRARY} ${SOCKET_LIBRARY} ${NSL_LIBRARY} CACHE INTERNAL "resolv_wrapper required system libraries")
