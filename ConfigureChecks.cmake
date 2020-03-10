include(CheckIncludeFile)
include(CheckSymbolExists)
include(CheckFunctionExists)
include(CheckLibraryExists)
include(CheckTypeSize)
include(CheckStructHasMember)
include(CheckPrototypeDefinition)
include(TestBigEndian)

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
        unset(CMAKE_REQUIRED_FLAGS)
    endif (NOT GNUCC_VERSION EQUAL 34)
endif(CMAKE_COMPILER_IS_GNUCC AND NOT MINGW AND NOT OS2)

# HEADERS
check_include_file(sys/types.h HAVE_SYS_TYPES_H)
check_include_file(resolv.h HAVE_RESOLV_H)
check_include_file(arpa/nameser.h HAVE_ARPA_NAMESER_H)

# SYMBOLS
set(CMAKE_REQUIRED_FLAGS -D_GNU_SOURCE)
check_symbol_exists(program_invocation_short_name
                    "errno.h"
                    HAVE_PROGRAM_INVOCATION_SHORT_NAME)
unset(CMAKE_REQUIRED_FLAGS)

# FUNCTIONS
check_function_exists(getprogname HAVE_GETPROGNAME)
check_function_exists(getexecname HAVE_GETEXECNAME)

find_library(RESOLV_LIRBRARY resolv)
if (RESOLV_LIRBRARY)
    set(HAVE_LIBRESOLV TRUE)

    # If we have a libresolv, we need to check functions linking the library
    list(APPEND _REQUIRED_LIBRARIES ${RESOLV_LIRBRARY})
else()
    message(STATUS "libresolv not found on ${CMAKE_SYSTEM_NAME}: Only dns faking will be available")
endif()

set(CMAKE_REQUIRED_LIBRARIES ${RESOLV_LIRBRARY})
check_function_exists(res_init HAVE_RES_INIT)
check_function_exists(__res_init HAVE___RES_INIT)
unset(CMAKE_REQUIRED_LIBRARIES)

set(CMAKE_REQUIRED_LIBRARIES ${RESOLV_LIRBRARY})
check_function_exists(res_ninit HAVE_RES_NINIT)
check_function_exists(__res_ninit HAVE___RES_NINIT)
unset(CMAKE_REQUIRED_LIBRARIES)

set(CMAKE_REQUIRED_LIBRARIES ${RESOLV_LIRBRARY})
check_function_exists(res_close HAVE_RES_CLOSE)
check_function_exists(__res_close HAVE___RES_CLOSE)
unset(CMAKE_REQUIRED_LIBRARIES)

set(CMAKE_REQUIRED_LIBRARIES ${RESOLV_LIRBRARY})
check_function_exists(res_nclose HAVE_RES_NCLOSE)
check_function_exists(__res_nclose HAVE___RES_NCLOSE)
unset(CMAKE_REQUIRED_LIBRARIES)

set(CMAKE_REQUIRED_LIBRARIES ${RESOLV_LIRBRARY})
check_function_exists(res_query HAVE_RES_QUERY)
check_function_exists(__res_query HAVE___RES_QUERY)
unset(CMAKE_REQUIRED_LIBRARIES)

set(CMAKE_REQUIRED_LIBRARIES ${RESOLV_LIRBRARY})
check_function_exists(res_nquery HAVE_RES_NQUERY)
check_function_exists(__res_nquery HAVE___RES_NQUERY)
unset(CMAKE_REQUIRED_LIBRARIES)

set(CMAKE_REQUIRED_LIBRARIES ${RESOLV_LIRBRARY})
check_function_exists(res_search HAVE_RES_SEARCH)
check_function_exists(__res_search HAVE___RES_SEARCH)
unset(CMAKE_REQUIRED_LIBRARIES)

set(CMAKE_REQUIRED_LIBRARIES ${RESOLV_LIRBRARY})
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
            if (HAVE_LIBSOCKET)
                list(APPEND _REQUIRED_LIBRARIES ${SOCKET_LIBRARY})
            endif()
        endif()

        # libnsl/inet_pton (Solaris)
        find_library(NSL_LIBRARY nsl)
        if (NSL_LIBRARY)
            check_library_exists(${NSL_LIBRARY} inet_pton "" HAVE_LIBNSL)
            if (HAVE_LIBNSL)
                list(APPEND _REQUIRED_LIBRARIES ${NSL_LIBRARY})
            endif()
        endif()
    endif (NOT LINUX)

    check_function_exists(getaddrinfo HAVE_GETADDRINFO)
endif (UNIX)

find_library(DLFCN_LIBRARY dl)
if (DLFCN_LIBRARY)
    list(APPEND _REQUIRED_LIBRARIES ${DLFCN_LIBRARY})
else()
    check_function_exists(dlopen HAVE_DLOPEN)
    if (NOT HAVE_DLOPEN)
        message(FATAL_ERROR "FATAL: No dlopen() function detected")
    endif()
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

check_struct_has_member("struct __res_state" _u._ext.nsaddrs
                        "sys/socket.h;netinet/in.h;resolv.h"
                        HAVE_RES_STATE_U_EXT_NSADDRS)
check_struct_has_member("union res_sockaddr_union" sin
                        "sys/socket.h;netinet/in.h;resolv.h"
                        HAVE_RES_SOCKADDR_UNION_SIN)
check_struct_has_member("union res_sockaddr_union" sin6
                        "sys/socket.h;netinet/in.h;resolv.h"
                        HAVE_RES_SOCKADDR_UNION_SIN6)

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

set(RWRAP_REQUIRED_LIBRARIES ${_REQUIRED_LIBRARIES} CACHE INTERNAL "resolv_wrapper required system libraries")
