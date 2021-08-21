#define LUA_LIB

#if (defined(_WIN32) || defined(WIN32))
#define _CRT_SECURE_NO_WARNINGS
#include <direct.h>
#include <io.h>
#include <windows.h>
#else
#include <sys/stat.h>
#include <unistd.h>
#endif

#include "lua.hpp"

#include <chrono>
#include <cstring>
#include <ctime>
#include <iomanip>
#include <map>
#include <sstream>

#if (defined(_WIN32) || defined(WIN32))
#define ACCESS(fileName, accessMode) _access(fileName, accessMode)
#define MKDIR(path) _mkdir(path)
#else
#define ACCESS(fileName, accessMode) access(fileName, accessMode)
#define MKDIR(path) mkdir(path, S_IRWXU | S_IRWXG | S_IROTH | S_IXOTH)
#endif

enum class logger_level {
    LEVEL_NONE = 0,
    LEVEL_PRINT = 1 << 0,
    LEVEL_WARNING = 1 << 1,
    LEVEL_DEBUG = 1 << 2,
    LEVEL_INFO = 1 << 3,
    LEVEL_ERROR = 1 << 4,
};

struct logger {
    FILE *file;
    const char *filedir;
    const char *filename;
    long long create_timestamp;
    int flag;
};

static std::map<logger_level, const char *> level_map = {
    {logger_level::LEVEL_WARNING, " [WARNING] "},
    {logger_level::LEVEL_DEBUG, " [DEBUG] "},
    {logger_level::LEVEL_INFO, " [INFO] "},
    {logger_level::LEVEL_ERROR, " [ERROR] "},
};

static const char *get_level_text(logger_level level) {
    const char *text = level_map[level];
    if (text == nullptr) {
        text = "";
    }
    return text;
};

static long long get_timestamp() {
    std::chrono::system_clock::duration d =
        std::chrono::system_clock::now().time_since_epoch();
    return std::chrono::duration_cast<std::chrono::seconds>(d).count();
}

static std::string get_timestamp_fmt(long long timestamp, const char *fmt) {
    std::time_t t(timestamp);
    std::stringstream ss;
    ss << std::put_time(std::localtime(&t), fmt);
    return ss.str();
}

static bool is_diff_day(long long a, long long b) {
    std::time_t ta(a);
    std::tm *tma = std::localtime(&ta);
    std::time_t tb(b);
    std::tm *tmb = std::localtime(&tb);
    return tma->tm_year != tmb->tm_year || tma->tm_mon != tmb->tm_mon ||
           tma->tm_mday != tmb->tm_mday;
}

static int32_t create_dir(const std::string &dir_path) {
    std::size_t dir_path_len = dir_path.length();
    char *tmp_dir_path = new char[dir_path_len];
    memset(tmp_dir_path, 0, dir_path_len);
    for (std::size_t i = 0; i < dir_path_len; i++) {
        tmp_dir_path[i] = dir_path[i];
        if (tmp_dir_path[i] == '\\' || tmp_dir_path[i] == '/') {
            if (ACCESS(tmp_dir_path, 0) != 0) {
                int32_t ret = MKDIR(tmp_dir_path);
                if (ret != 0) {
                    delete[] tmp_dir_path;
                    return ret;
                }
            }
        }
    }
    delete[] tmp_dir_path;
    return 0;
}

static FILE *new_file(lua_State *L, const char *filedir, const char *filename,
                      long long create_timestamp) {
    std::string fname;
    fname = fname + filedir + "/";
    if (create_dir(fname) != 0) {
        luaL_error(L, "Can not create dir %s", fname.c_str());
    }
    fname = fname + filename + "_" + get_timestamp_fmt(create_timestamp, "%F") +
            ".log";
    FILE *file = fopen(fname.c_str(), "a");
    if (file == nullptr) {
        luaL_error(L, "Can not create file %s", fname.c_str());
    }
    return file;
}

static bool has_level(logger *log, int level) {
    return (log->flag & level) == level ? true : false;
}

static void log_printf(logger_level level, const char *head, const char *text) {
#if (defined(_WIN32) || defined(WIN32))
#define NONE 0x000F
#define RED 0x000C
#define GREEN 0x0002
#define YELLOW 0x000E
    switch (level) {
    case logger_level::LEVEL_WARNING: {
        SetConsoleTextAttribute(GetStdHandle(STD_OUTPUT_HANDLE), YELLOW);
        printf("%s%s\n", head, text);
        break;
    }
    case logger_level::LEVEL_DEBUG: {
        SetConsoleTextAttribute(GetStdHandle(STD_OUTPUT_HANDLE), GREEN);
        printf("%s%s\n", head, text);
        break;
    }
    case logger_level::LEVEL_ERROR: {
        SetConsoleTextAttribute(GetStdHandle(STD_OUTPUT_HANDLE), RED);
        printf("%s%s\n", head, text);
        break;
    }
    default: {
        SetConsoleTextAttribute(GetStdHandle(STD_OUTPUT_HANDLE), NONE);
        printf("%s%s\n", head, text);
        break;
    }
    }
#else
#define NONE "\e[0m\n"
#define RED "\e[1;31m"
#define GREEN "\e[1;32m"
#define YELLOW "\e[1;33m"
    switch (level) {
    case logger_level::LEVEL_WARNING: {
        printf(YELLOW "%s%s" NONE, head, text);
        break;
    }
    case logger_level::LEVEL_DEBUG: {
        printf(GREEN "%s%s" NONE, head, text);
        break;
    }
    case logger_level::LEVEL_ERROR: {
        printf(RED "%s%s" NONE, head, text);
        break;
    }
    default: {
        printf("%s%s" NONE, head, text);
        break;
    }
    }
#endif
}

static int llog(lua_State *L) {
    logger *log = static_cast<logger *>(luaL_checkudata(L, 1, "logger"));
    luaL_argcheck(L, log != nullptr, 1, "logger expected");

    int level = static_cast<int>(luaL_checkinteger(L, 2));
    std::size_t text_len;
    const char *text = luaL_checklstring(L, 3, &text_len);

    if (!has_level(log, level)) {
        return luaL_error(L, "Unsupport log level %d", level);
    }

    logger_level log_level = static_cast<logger_level>(level);

    long long timestamp = get_timestamp();

    std::string head =
        get_timestamp_fmt(timestamp, "[%T]") + get_level_text(log_level);

    if (has_level(log, static_cast<int>(logger_level::LEVEL_PRINT))) {
        log_printf(log_level, head.c_str(), text);
    }

    if (is_diff_day(log->create_timestamp, timestamp)) {
        if (log->file) {
            fclose(log->file);
            log->file = nullptr;
        }
        log->file = new_file(L, log->filedir, log->filename, timestamp);
        log->create_timestamp = timestamp;
    }

    if (!log->file) {
        return 0;
    }

    fwrite(head.c_str(), head.size(), 1, log->file);
    fwrite(text, text_len, 1, log->file);
    fprintf(log->file, "\n");
    fflush(log->file);

    return 0;
}

static int lenablelevel(lua_State *L) {
    logger *log = static_cast<logger *>(luaL_checkudata(L, 1, "logger"));
    luaL_argcheck(L, log != nullptr, 1, "logger expected");

    int level = static_cast<int>(luaL_checkinteger(L, 2));
    int enable = lua_toboolean(L, 3);
    if (enable) {
        log->flag |= level;
    } else {
        log->flag &= ~level;
    }

    return 0;
}

static int lrelease(lua_State *L) {
    logger *log = static_cast<logger *>(luaL_checkudata(L, 1, "logger"));
    luaL_argcheck(L, log != nullptr, 1, "logger expected");

    if (log->file) {
        fclose(log->file);
        log->file = nullptr;
    }
    if (log->filedir) {
        delete[] log->filedir;
        log->filedir = nullptr;
    }
    if (log->filename) {
        delete[] log->filename;
        log->filename = nullptr;
    }

    return 0;
}

static int lnew(lua_State *L) {
    std::size_t filedir_len;
    const char *filedir = luaL_checklstring(L, 1, &filedir_len);
    std::size_t filename_len;
    const char *filename = luaL_checklstring(L, 2, &filename_len);

    long long timestamp = get_timestamp();

    FILE *file = new_file(L, filedir, filename, timestamp);

    logger *log =
        static_cast<logger *>(lua_newuserdatauv(L, sizeof(logger), 0));
    log->file = file;
    log->filedir = new char[filedir_len];
    memcpy(const_cast<char *>(log->filedir), filedir, filedir_len);
    log->filename = new char[filename_len];
    memcpy(const_cast<char *>(log->filename), filename, filename_len);
    log->create_timestamp = timestamp;
    log->flag = static_cast<int>(logger_level::LEVEL_PRINT) |
                static_cast<int>(logger_level::LEVEL_WARNING) |
                static_cast<int>(logger_level::LEVEL_DEBUG) |
                static_cast<int>(logger_level::LEVEL_INFO) |
                static_cast<int>(logger_level::LEVEL_ERROR);

    if (luaL_newmetatable(L, "logger")) {
        luaL_Reg l[] = {
            {"log", llog},
            {"enablelevel", lenablelevel},
            {nullptr, nullptr},
        };

        luaL_newlib(L, l);
        lua_setfield(L, -2, "__index");
        lua_pushcfunction(L, lrelease);
        lua_setfield(L, -2, "__gc");
    }
    lua_setmetatable(L, -2);

    return 1;
}

extern "C" {
LUALIB_API int luaopen_logger(lua_State *L) {
    luaL_checkversion(L);
    luaL_Reg l[] = {
        {"new", lnew},
        {nullptr, nullptr},
    };
    luaL_newlib(L, l);

    lua_newtable(L);
    lua_pushinteger(L, static_cast<int>(logger_level::LEVEL_PRINT));
    lua_setfield(L, -2, "print");
    lua_pushinteger(L, static_cast<int>(logger_level::LEVEL_WARNING));
    lua_setfield(L, -2, "warning");
    lua_pushinteger(L, static_cast<int>(logger_level::LEVEL_DEBUG));
    lua_setfield(L, -2, "debug");
    lua_pushinteger(L, static_cast<int>(logger_level::LEVEL_INFO));
    lua_setfield(L, -2, "info");
    lua_pushinteger(L, static_cast<int>(logger_level::LEVEL_ERROR));
    lua_setfield(L, -2, "error");

    lua_setfield(L, -2, "level");

    return 1;
}
}