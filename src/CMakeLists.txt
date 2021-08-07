project(core)

include_directories(../third_party)
include_directories(../third_party/lua)

aux_source_directory(${CMAKE_CURRENT_SOURCE_DIR} CORE_SOURCES)

find_package(Threads)

if(CMAKE_SYSTEM_NAME MATCHES "Windows")
    add_definitions(-D_CRT_SECURE_NO_WARNINGS)
    add_definitions(-DLUA_BUILD_AS_DLL)
    add_definitions(-DLUA_LIB)
endif()

add_library(hive SHARED ${CORE_SOURCES})
if(CMAKE_SYSTEM_NAME MATCHES "Linux")
    set(JEMALLOC_LIBRARY ${CMAKE_CURRENT_SOURCE_DIR}/../third_party/jemalloc/lib/libjemalloc_pic.a)

    add_custom_target(
        build_jemalloc ALL ./autogen.sh --enable-prof --disable-initial-exec-tls
        COMMAND ${CMAKE_MAKE_PROGRAM}
        WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}/../third_party/jemalloc/
        COMMENT "Original jemalloc makefile target"
    )

    add_library(jemalloc STATIC IMPORTED)

    set_property(TARGET jemalloc APPEND PROPERTY IMPORTED_CONFIGURATIONS NOCONFIG)
    set_target_properties(jemalloc PROPERTIES IMPORTED_LOCATION_NOCONFIG "${JEMALLOC_LIBRARY}")

    add_dependencies(jemalloc build_jemalloc)
    target_link_libraries(hive liblua ${CMAKE_THREAD_LIBS_INIT} jemalloc)
else()
    target_link_libraries(hive liblua ${CMAKE_THREAD_LIBS_INIT})
endif()
