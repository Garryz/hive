#include "hive_seri.h"

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
    luaL_checktype(L, 2, LUA_TTABLE);
    lua_settop(L, 2);

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

    rb.close();

    return lua_gettop(L) - 2;
}