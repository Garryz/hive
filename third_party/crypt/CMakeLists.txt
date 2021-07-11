project(crypt)

if(CMAKE_SYSTEM_NAME MATCHES "Windows")
    add_definitions(-DLUA_BUILD_AS_DLL)
    add_definitions("/wd4267")
    add_definitions("/wd4244")
endif()

include_directories(../lua)
include_directories(../boringssl/include)

aux_source_directory(${CMAKE_CURRENT_SOURCE_DIR} CRYPT_SOURCES)

add_library(crypt SHARED ${CRYPT_SOURCES})
target_link_libraries(crypt liblua crypto ssl)