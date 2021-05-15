extern "C" {
#include "hive_scheduler.h"

LUALIB_API int luaopen_hive_core(lua_State *L) {
    luaL_checkversion(L);
    luaL_Reg l[] = {
        {"start", scheduler_start},
        {nullptr, nullptr},
    };
    luaL_newlib(L, l);

    return 1;
}
}