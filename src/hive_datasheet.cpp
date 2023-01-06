#include <cstdint>

#include "endian.h"
#include "lua.hpp"

static const char *NODECACHE = "_ctable";
static const char *PROXYCACHE = "_proxy";
static const char *TABLES = "_ctables";

enum class value_type {
    VALUE_NIL = 0,
    VALUE_INTEGER = 1,
    VALUE_REAL = 2,
    VALUE_BOOLEAN = 3,
    VALUE_TABLE = 4,
    VALUE_STRING = 5,
    VALUE_INVALID = 6
};

static const uint32_t INVALID_OFFSET = 0xffffffff;

struct proxy {
    const void *data;
    uint32_t index;
};

struct document {
    uint32_t strtbl;
    uint32_t n;
    uint32_t index[1];
    // table[n]
    // strings
};

struct table {
    uint32_t dict;
    uint8_t type[1];
    // kvpair[dict]
};

static inline const table *gettable(const document *doc, uint32_t index) {
    if (doc->index[index] == INVALID_OFFSET) {
        return nullptr;
    }
    return reinterpret_cast<const table *>(
        reinterpret_cast<const char *>(doc) + sizeof(uint32_t) +
        sizeof(uint32_t) + doc->n * sizeof(uint32_t) + doc->index[index]);
}

static void create_proxy(lua_State *L, const void *data, uint32_t index) {
    const table *t = gettable(static_cast<const document *>(data), index);

    if (t == nullptr) {
        luaL_error(L, "Invalid index %d", index);
    }
    lua_getfield(L, LUA_REGISTRYINDEX, NODECACHE);
    if (lua_rawgetp(L, -1, t) == LUA_TTABLE) {
        lua_replace(L, -2);
        return;
    }
    lua_pop(L, 1);
    lua_newtable(L);
    lua_pushvalue(L, lua_upvalueindex(1));
    lua_setmetatable(L, -2);
    lua_pushvalue(L, -1);
    // NODECACHE, table, table
    lua_rawsetp(L, -3, t);
    // NODECACHE, table
    lua_getfield(L, LUA_REGISTRYINDEX, PROXYCACHE);
    // NODECACHE, table, PROXYCACHE
    lua_pushvalue(L, -2);
    // NODECACHE, table, PROXYCACHE, table
    proxy *p = static_cast<proxy *>(lua_newuserdatauv(L, sizeof(proxy), 0));
    // NODECACHE, table, PROXYCACHE, table, proxy
    p->data = data;
    p->index = index;
    lua_rawset(L, -3);
    // NODECACHE, table, PROXYCACHE
    lua_pop(L, 1);
    // NODECACHE, table
    lua_replace(L, -2);
    // table
}

static void clear_table(lua_State *L) {
    int t = lua_gettop(L);  // clear top
    if (lua_type(L, t) != LUA_TTABLE) {
        luaL_error(L, "Invalid cache");
    }
    lua_pushnil(L);
    while (lua_next(L, t) != 0) {
        // key value
        lua_pop(L, 1);
        lua_pushvalue(L, -1);
        lua_pushnil(L);
        // key key nil
        lua_rawset(L, t);
        // key
    }
}

static void update_cache(lua_State *L, const void *data, const void *newdata) {
    lua_getfield(L, LUA_REGISTRYINDEX, NODECACHE);
    int t = lua_gettop(L);
    lua_getfield(L, LUA_REGISTRYINDEX, PROXYCACHE);
    int pt = t + 1;
    lua_newtable(L);  // temp table
    int nt = pt + 1;
    lua_pushnil(L);
    while (lua_next(L, t) != 0) {
        // pointer (-2) -> table (-1)
        lua_pushvalue(L, -1);
        if (lua_rawget(L, pt) == LUA_TUSERDATA) {
            // pointer, table, proxy
            proxy *p = static_cast<proxy *>(lua_touserdata(L, -1));
            if (p->data == data) {
                p->data = newdata;
                const table *newt =
                    gettable(static_cast<const document *>(newdata), p->index);
                lua_pop(L, 1);
                // pointer, table
                clear_table(L);
                lua_pushvalue(L, lua_upvalueindex(1));
                // pointer, table, meta
                lua_setmetatable(L, -2);
                // pointer, table
                if (newt) {
                    lua_rawsetp(L, nt, newt);
                } else {
                    lua_pop(L, 1);
                }
                // pointer
                lua_pushvalue(L, -1);
                lua_pushnil(L);
                lua_rawset(L, t);
            } else {
                lua_pop(L, 2);
            }
        } else {
            lua_pop(L, 2);
            // pointer
        }
    }
    // copy nt to t
    lua_pushnil(L);
    while (lua_next(L, nt) != 0) {
        lua_pushvalue(L, -2);
        lua_insert(L, -2);
        // key key value
        lua_rawset(L, t);
    }
    // NODECACHE PROXYCACHE TEMP
    lua_pop(L, 3);
}

static int lupdate(lua_State *L) {
    lua_getfield(L, LUA_REGISTRYINDEX, PROXYCACHE);
    lua_pushvalue(L, 1);
    // PROXYCACHE, table
    if (lua_rawget(L, -2) != LUA_TUSERDATA) {
        luaL_error(L, "Invalid proxy table %p", lua_topointer(L, 1));
    }
    proxy *p = static_cast<proxy *>(lua_touserdata(L, -1));
    luaL_checktype(L, 2, LUA_TLIGHTUSERDATA);
    const void *newdata = lua_touserdata(L, 2);
    update_cache(L, p->data, newdata);
    return 1;
}

static void pushvalue(lua_State *L, const uint32_t *v, value_type type,
                      const document *doc) {
    switch (type) {
        case value_type::VALUE_NIL:
            lua_pushnil(L);
            break;
        case value_type::VALUE_INTEGER:
            lua_pushinteger(
                L, adapte_endian(*reinterpret_cast<const int32_t *>(v), false));
            break;
        case value_type::VALUE_REAL:
            lua_pushnumber(
                L, adapte_endian(*reinterpret_cast<const float *>(v), false));
            break;
        case value_type::VALUE_BOOLEAN:
            lua_pushboolean(L, adapte_endian(*v, false));
            break;
        case value_type::VALUE_TABLE:
            create_proxy(L, doc, adapte_endian(*v, false));
            break;
        case value_type::VALUE_STRING:
            lua_pushstring(L, reinterpret_cast<const char *>(doc) +
                                  doc->strtbl + adapte_endian(*v, false));
            break;
        default:
            luaL_error(L, "Invalid type %d at %p", type, v);
    }
}

static void copytable(lua_State *L, int tbl, proxy *p) {
    const document *doc = reinterpret_cast<const document *>(p->data);
    if (p->index < 0 || p->index >= doc->n) {
        luaL_error(L, "Invalid proxy (index = %d, total = %d)", p->index,
                   doc->n);
    }
    const table *t = gettable(doc, p->index);
    if (t == nullptr) {
        return;
    }
    const uint32_t *v = reinterpret_cast<const uint32_t *>(
        reinterpret_cast<const char *>(t) + sizeof(uint32_t) +
        ((t->dict * 2 + 3) & ~3));
    for (uint32_t i = 0; i < t->dict; i++) {
        pushvalue(L, v++, static_cast<value_type>(t->type[2 * i]), doc);
        pushvalue(L, v++, static_cast<value_type>(t->type[2 * i + 1]), doc);
        lua_rawset(L, tbl);
    }
}

static int lnew(lua_State *L) {
    luaL_checktype(L, 1, LUA_TLIGHTUSERDATA);
    const void *data = lua_touserdata(L, 1);
    // hold ref to data
    lua_getfield(L, LUA_REGISTRYINDEX, TABLES);
    lua_pushvalue(L, 1);
    lua_rawsetp(L, -2, data);

    create_proxy(L, data, 0);
    return 1;
}

static void copyfromdata(lua_State *L) {
    lua_getfield(L, LUA_REGISTRYINDEX, PROXYCACHE);
    lua_pushvalue(L, 1);
    // PROXYCACHE, table
    if (lua_rawget(L, -2) != LUA_TUSERDATA) {
        luaL_error(L, "Invalid proxy table %p", lua_topointer(L, 1));
    }
    proxy *p = static_cast<proxy *>(lua_touserdata(L, -1));
    lua_pop(L, 2);
    copytable(L, 1, p);
    lua_pushnil(L);
    lua_setmetatable(L, 1);  // remove metatable
}

static int lindex(lua_State *L) {
    copyfromdata(L);
    lua_rawget(L, 1);
    return 1;
}

static int lnext(lua_State *L) {
    luaL_checktype(L, 1, LUA_TTABLE);
    lua_settop(L, 2); /* create a 2nd argument if there isn't one */
    if (lua_next(L, 1)) {
        return 2;
    } else {
        lua_pushnil(L);
        return 1;
    }
}

static int lpairs(lua_State *L) {
    copyfromdata(L);
    lua_pushcfunction(L, lnext);
    lua_pushvalue(L, 1);
    lua_pushnil(L);
    return 3;
}

static int llen(lua_State *L) {
    copyfromdata(L);
    lua_pushinteger(L, lua_rawlen(L, 1));
    return 1;
}

static void new_weak_table(lua_State *L, const char *mode) {
    lua_newtable(L);

    lua_createtable(L, 0, 1);  // weak meta table
    lua_pushstring(L, mode);
    lua_setfield(L, -2, "__mode");

    lua_setmetatable(L, -2);  // make weak
}

static void gen_metatable(lua_State *L) {
    new_weak_table(L, "kv");  // NODECACHE { pointer:table }
    lua_setfield(L, LUA_REGISTRYINDEX, NODECACHE);

    new_weak_table(L, "k");  // PROXYCACHE { table:userdata }
    lua_setfield(L, LUA_REGISTRYINDEX, PROXYCACHE);

    lua_newtable(L);
    lua_setfield(L, LUA_REGISTRYINDEX, TABLES);

    lua_createtable(L, 0, 1);  // mod table

    lua_createtable(L, 0, 2);  // metatable
    luaL_Reg l[] = {
        {"__index", lindex},
        {"__pairs", lpairs},
        {"__len", llen},
        {NULL, NULL},
    };
    lua_pushvalue(L, -1);
    luaL_setfuncs(L, l, 1);
}

static int lstringpointer(lua_State *L) {
    const void *str = luaL_checkstring(L, 1);
    lua_pushlightuserdata(L, const_cast<void *>(str));
    return 1;
}

extern "C" {
LUALIB_API int luaopen_hive_datasheet(lua_State *L) {
    luaL_checkversion(L);
    luaL_Reg l[] = {
        {"new", lnew},
        {"update", lupdate},
        {nullptr, nullptr},
    };

    luaL_newlibtable(L, l);
    gen_metatable(L);
    luaL_setfuncs(L, l, 1);
    lua_pushcfunction(L, lstringpointer);
    lua_setfield(L, -2, "stringpointer");
    return 1;
}
}