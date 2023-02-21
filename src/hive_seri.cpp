#include "hive_seri.h"

#include "hive_env.h"

int data_pack(lua_State *L) {
    write_block b;
    b.init(nullptr);
    b._pack_from(L, 0);
    block *ret = b.close();
    lua_pushlightuserdata(L, ret);
    return 1;
}

int data_unpack(lua_State *L) {
    auto blk = static_cast<block *>(lua_touserdata(L, 1));
    if (blk == nullptr) {
        return luaL_error(L, "Need a block to unpack");
    }
    bool nodelete = lua_toboolean(L, 2) ? true : false;
    lua_settop(L, 1);
    hive_getenv(L, "cell_map");

    read_block rb;
    rb.init(blk);

    for (int i = 0;; i++) {
        if (i % 8 == 7) {
            luaL_checkstack(L, LUA_MINSTACK, nullptr);
        }
        uint8_t type = 0;
        uint8_t *t = static_cast<uint8_t *>(rb.read(&type, sizeof(type)));
        if (t == nullptr) {
            break;
        }
        rb._push_value(L, *t & 0x7, *t >> 3, 2);
    }

    if (!nodelete) {
        rb.close();
    }

    return lua_gettop(L) - 2;
}

extern "C" {
LUALIB_API int luaopen_hive_seri(lua_State *L) {
    luaL_checkversion(L);
    luaL_Reg l[] = {
        {"pack", data_pack},
        {"unpack", data_unpack},
        {nullptr, nullptr},
    };
    luaL_newlib(L, l);

    return 1;
}
}