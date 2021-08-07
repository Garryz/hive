#include "hive_cell_lib.h"
#include "hive_cell.h"
#include "hive_env.h"
#include "hive_log.h"
#include "hive_seri.h"

#include <chrono>

static int ldispatch(lua_State *L) {
    luaL_checktype(L, 1, LUA_TFUNCTION);
    lua_settop(L, 1);
    hive_setenv(L, "dispatcher");
    return 0;
}

static int lsend(lua_State *L) {
    cell *c = cell_fromuserdata(L, 1);
    if (c == nullptr) {
        return luaL_error(L, "Need cell object at param 1");
    }

    int port = static_cast<int>(luaL_checkinteger(L, 2));
    if (lua_gettop(L) == 2) {
        if (cell_send(c, port, nullptr)) {
            log_error("Cell object %p is closed", c);
            return 0;
        }
        lua_pushboolean(L, 1);
        return 1;
    }

    lua_pushcfunction(L, data_pack);
    lua_replace(L, 2); // cell data_pack ...
    int n = lua_gettop(L);
    lua_call(L, n - 2, 1);
    void *msg = lua_touserdata(L, 2);
    if (cell_send(c, port, msg)) {
        lua_pushcfunction(L, data_unpack);
        lua_pushvalue(L, 2);
        lua_call(L, 1, 0);
        log_error("Cell object %p is closed", c);
        return 0;
    }

    lua_pushboolean(L, 1);
    return 1;
}

static int ltime(lua_State *L) {
    auto time_now = std::chrono::system_clock::now();
    auto duration_in_ms = std::chrono::duration_cast<std::chrono::microseconds>(
        time_now.time_since_epoch());
    lua_pushnumber(L, static_cast<double>(duration_in_ms.count()) / 1000000);
    return 1;
}

int cell_lib(lua_State *L) {
    luaL_checkversion(L);
    luaL_Reg l[] = {
        {"dispatch", ldispatch},
        {"send", lsend},
        {"time", ltime},
        {nullptr, nullptr},
    };
    luaL_newlib(L, l);
    return 1;
}