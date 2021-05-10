#ifndef crash_dump_h
#define crash_dump_h

#if (defined(_WIN32) || defined(WIN32))

#include <Windows.h>

#include <DbgHelp.h>

#pragma comment(lib, "Dbghelp.lib")

LONG application_crash_handler(EXCEPTION_POINTERS *pk_exception) {
    HANDLE h_dump_file =
        CreateFile(__TEXT("core.dmp"), GENERIC_WRITE, 0, nullptr, CREATE_ALWAYS,
                   FILE_ATTRIBUTE_NORMAL, nullptr);
    if (h_dump_file == INVALID_HANDLE_VALUE) {
        return EXCEPTION_EXECUTE_HANDLER;
    }

    MINIDUMP_EXCEPTION_INFORMATION dump_info;
    dump_info.ExceptionPointers = pk_exception;
    dump_info.ThreadId = GetCurrentThreadId();
    dump_info.ClientPointers = TRUE;

    MiniDumpWriteDump(GetCurrentProcess(), GetCurrentProcessId(), h_dump_file,
                      MiniDumpNormal, &dump_info, nullptr, nullptr);

    CloseHandle(h_dump_file);

    return EXCEPTION_EXECUTE_HANDLER;
}

#endif

void crash_dump() {
#if (defined(_WIN32) || defined(WIN32))
    SetUnhandledExceptionFilter(application_crash_handler);
#endif
}

#endif