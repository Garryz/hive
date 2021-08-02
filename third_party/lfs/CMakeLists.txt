project(lfs)

if(CMAKE_SYSTEM_NAME MATCHES "Windows")
    add_definitions(-DLUA_BUILD_AS_DLL)
    add_definitions("/wd4267")
    add_definitions("/wd4996")
    add_definitions("/wd4005")
endif()

add_definitions(-DLUA_LIB)

include_directories(../lua)

aux_source_directory(${CMAKE_CURRENT_SOURCE_DIR} LFS_SOURCES)

add_library(lfs SHARED ${LFS_SOURCES})
target_link_libraries(lfs liblua)