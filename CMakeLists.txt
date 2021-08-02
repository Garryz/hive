project(hive)

set(EXE ${CMAKE_CURRENT_SOURCE_DIR})
set(LIB ${CMAKE_CURRENT_SOURCE_DIR}/luaclib)

if(CMAKE_SYSTEM_NAME MATCHES "Windows")
    cmake_minimum_required(VERSION 3.3.2)

    set(CMAKE_ARCHIVE_OUTPUT_DIRECTORY_DEBUG ${LIB})
    set(CMAKE_ARCHIVE_OUTPUT_DIRECTORY_RELEASE ${LIB})
    set(CMAKE_ARCHIVE_OUTPUT_DIRECTORY_MINSIZEREL ${LIB})
    set(CMAKE_ARCHIVE_OUTPUT_DIRECTORY_RELWITHDEBINFO ${LIB})
    set(CMAKE_RUNTIME_OUTPUT_DIRECTORY_DEBUG ${LIB})
    set(CMAKE_RUNTIME_OUTPUT_DIRECTORY_RELEASE ${LIB})
    set(CMAKE_RUNTIME_OUTPUT_DIRECTORY_MINSIZEREL ${LIB})
    set(CMAKE_RUNTIME_OUTPUT_DIRECTORY_RELWITHDEBINFO ${LIB})

    macro(get_WIN32_WINNT version)
        if (CMAKE_SYSTEM_VERSION)
            set(ver ${CMAKE_SYSTEM_VERSION})
            string(REGEX MATCH "^([0-9]+).([0-9])" ver ${ver})
            string(REGEX MATCH "^([0-9]+)" verMajor ${ver})
            # Check for Windows 10, b/c we'll need to convert to hex 'A'.
            if ("${verMajor}" MATCHES "10")
                set(verMajor "A")
                string(REGEX REPLACE "^([0-9]+)" ${verMajor} ver ${ver})
            endif ("${verMajor}" MATCHES "10")
            # Remove all remaining '.' characters.
            string(REPLACE "." "" ver ${ver})
            # Prepend each digit with a zero.
            string(REGEX REPLACE "([0-9A-Z])" "0\\1" ver ${ver})
            set(${version} "0x${ver}")
        endif(CMAKE_SYSTEM_VERSION)
    endmacro(get_WIN32_WINNT)

    get_WIN32_WINNT(ver)
    add_definitions(-D_WIN32_WINNT=${ver})
else()
    cmake_minimum_required(VERSION 3.1.3)

    set(EXECUTABLE_OUTPUT_PATH ${EXE})
    set(LIBRARY_OUTPUT_PATH ${LIB})

    set(CMAKE_CXX_FLAGS "-std=c++11 ${CMAKE_CXX_FLAGS}")

    if(CMAKE_SYSTEM_NAME MATCHES "Darwin")
        set(CMAKE_MACOSX_RPATH 1)
    endif()
endif()

add_subdirectory(./src)
add_subdirectory(./third_party/lua)
add_subdirectory(./third_party/pb)
add_subdirectory(./third_party/protobuf/cmake)
add_subdirectory(./third_party/crypt)
add_subdirectory(./third_party/boringssl)
add_subdirectory(./third_party/lfs)