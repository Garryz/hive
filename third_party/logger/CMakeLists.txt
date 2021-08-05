project(logger)

if(CMAKE_SYSTEM_NAME MATCHES "Windows")
    add_definitions(-DLUA_BUILD_AS_DLL)
endif()

include_directories(../lua)

aux_source_directory(${CMAKE_CURRENT_SOURCE_DIR} LOGGER_SOURCES)

add_library(logger SHARED ${LOGGER_SOURCES})
target_link_libraries(logger liblua)