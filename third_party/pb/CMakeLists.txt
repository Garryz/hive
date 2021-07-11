project(pb)

if(CMAKE_SYSTEM_NAME MATCHES "Windows")
    add_definitions(-DLUA_BUILD_AS_DLL)
    add_definitions("/wd4267")
endif()

include_directories(../lua)

aux_source_directory(${CMAKE_CURRENT_SOURCE_DIR} PB_SOURCES)

add_library(pb SHARED ${PB_SOURCES})
target_link_libraries(pb liblua)