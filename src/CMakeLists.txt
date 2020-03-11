project(libresolv_wrapper C)

add_library(resolv_wrapper SHARED resolv_wrapper.c)
target_link_libraries(resolv_wrapper ${RWRAP_REQUIRED_LIBRARIES})

target_compile_options(resolv_wrapper
                       PRIVATE
                           ${DEFAULT_C_COMPILE_FLAGS}
                          -D_GNU_SOURCE)
target_include_directories(resolv_wrapper
                           PRIVATE ${CMAKE_BINARY_DIR})

set_target_properties(
  resolv_wrapper
    PROPERTIES
      VERSION
        ${LIBRARY_VERSION}
      SOVERSION
        ${LIBRARY_SOVERSION}
)

install(TARGETS resolv_wrapper
        RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR}
        LIBRARY DESTINATION ${CMAKE_INSTALL_LIBDIR}
        ARCHIVE DESTINATION ${CMAKE_INSTALL_LIBDIR})

set(RESOLV_WRAPPER_LOCATION "${CMAKE_CURRENT_BINARY_DIR}/${CMAKE_SHARED_LIBRARY_PREFIX}resolv_wrapper${CMAKE_SHARED_LIBRARY_SUFFIX}" PARENT_SCOPE)
