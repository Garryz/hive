#include "hive_cell.h"
#include "hive_cell_lib.h"
#include "hive_env.h"
#include "hive_scheduler.h"
#include "hive_seri.h"
#include "hive_socket_lib.h"
#include "hive_system_lib.h"

#include <atomic>
#include <cassert>
#include <functional>
#include <mutex>
#include <queue>

struct message {
    int type{-1};
    void *buffer{nullptr};

    message() = default;
    message(int type, void *buffer) : type(type), buffer(buffer) {}
};

static std::atomic<int> __cell_id{1};

struct cell {
    std::mutex mut;
    std::atomic<int> ref{0};
    lua_State *L{nullptr};
    std::queue<message> mq;
    global_queue *gmq{nullptr};
    bool in_gmq{true};
    bool single_thread{false};
    bool close{false};
    int id{__cell_id.fetch_add(1)};
    int message_count{0};

    void lock() { mut.lock(); }

    void unlock() { mut.unlock(); }

    void push_in_gmq() {
        if (!single_thread && !in_gmq) {
            globalmq_push(gmq, this);
            in_gmq = true;
        }
    }

    void pop_out_gmq() { in_gmq = false; }

    void push(int type, void *buffer) {
        mq.emplace(type, buffer);
        push_in_gmq();
    }

    bool pop(message *m) {
        if (mq.empty()) {
            pop_out_gmq();
            return false;
        }
        *m = std::move(mq.front());
        mq.pop();
        return true;
    }

    ~cell() {
        assert(ref.load() == 0);
        assert(L == nullptr);
    }
};

struct cell_ud {
    cell *c;
};

static int __cell = 0;
#define CELL_TAG (&__cell)

cell *cell_alloc(lua_State *L) {
    cell *c = new cell;
    c->L = L;
    hive_getenv(L, "message_queue");
    c->gmq = static_cast<global_queue *>(lua_touserdata(L, -1));
    lua_pop(L, 1);
    return c;
}

static void require_socket(lua_State *L) {
    luaL_requiref(L, "cell.c.socket", socket_lib, 0);
    lua_pop(L, 1);
}

static void require_cell(lua_State *L, cell *c,
                         std::function<void(lua_State *, int)> set_sys) {
    hive_getenv(L, "cell_map");
    int cell_map = lua_absindex(L, -1);      // cell_map
    luaL_requiref(L, "cell.c", cell_lib, 0); // cell_map cell_lib

    cell_touserdata(L, cell_map, c); // cell_map cell_lib cell_ud
    lua_setfield(L, -2, "self");     // cell_map cell_lib

    set_sys(L, cell_map);

    lua_pop(L, 2);

    lua_pushlightuserdata(L, c);
    hive_setenv(L, "cell_pointer");
}

static void require_sys(lua_State *L, cell *socket, const char *mainfile,
                        const char *loaderfile) {
    hive_getenv(L, "cell_map");
    int cell_map = lua_absindex(L, -1);
    luaL_requiref(L, "cell.system", cell_system_lib, 0);

    cell_touserdata(L, cell_map, socket);
    lua_setfield(L, -2, "socket");

    lua_pushstring(L, mainfile);
    lua_setfield(L, -2, "maincell");

    lua_pushstring(L, loaderfile);
    lua_setfield(L, -2, "loader");

    lua_pop(L, 2);
}

static int traceback(lua_State *L) {
    const char *msg = lua_tostring(L, 1);
    if (msg) {
        luaL_traceback(L, L, msg, 1);
    } else {
        lua_pushliteral(L, "(no error message)");
    }
    return 1;
}

static int lcallback(lua_State *L) {
    int port = static_cast<int>(lua_tointeger(L, 1));
    void *msg = lua_touserdata(L, 2);
    int err = 0;
    lua_settop(L, 0);
    lua_pushvalue(L, lua_upvalueindex(1)); // traceback
    if (msg == nullptr) {
        lua_pushvalue(L, lua_upvalueindex(3)); // traceback dispatcher
        lua_pushinteger(L, port);
        err = lua_pcall(L, 1, 0, 1);
    } else {
        lua_pushvalue(L, lua_upvalueindex(3)); // traceback dispatcher
        lua_pushinteger(L, port);              // traceback dispatcher port
        lua_pushvalue(
            L,
            lua_upvalueindex(2)); // traceback dispatcher port data_unpack
        lua_pushlightuserdata(L,
                              msg); // traceback dispatcher port data_unpack msg
        err = lua_pcall(L, 1, LUA_MULTRET, 1);
        if (err) {
            printf("Unpack failed : %s\n", lua_tostring(L, -1));
            return 0;
        }
        int n = lua_gettop(L);           // traceback dispatcher ...
        err = lua_pcall(L, n - 2, 0, 1); // traceback 1
    }

    if (err) {
        printf("[cell %p] err_code = %d, err = %s\n",
               lua_touserdata(L, lua_upvalueindex(4)), err,
               lua_tostring(L, -1));
    }
    return 0;
}

static cell *init_cell(lua_State *L, cell *c, const char *mainfile,
                       const char *loaderfile) {
    auto _error = [](lua_State *L, cell *c) -> cell * {
        scheduler_deletetask(L);
        c->L = nullptr;
        delete c;
        return nullptr;
    };

    int err = 0;
    if (loaderfile != nullptr) {
        err = luaL_loadfile(L, loaderfile);
        if (err) {
            printf("%d : %s\n", err, lua_tostring(L, -1));
            lua_pop(L, 1);
            return _error(L, c);
        }

        err = lua_pcall(L, 0, 0, 0);
        if (err) {
            printf("loader (%s) error %d : %s\n", loaderfile, err,
                   lua_tostring(L, -1));
            lua_pop(L, 1);
            return _error(L, c);
        }
    }

    err = luaL_loadfile(L, mainfile);
    if (err) {
        printf("%d : %s\n", err, lua_tostring(L, -1));
        lua_pop(L, 1);
        return _error(L, c);
    }

    err = lua_pcall(L, 0, 0, 0);
    if (err) {
        printf("new cell (%s) error %d : %s\n", mainfile, err,
               lua_tostring(L, -1));
        lua_pop(L, 1);
        return _error(L, c);
    }

    lua_pushcfunction(L, traceback);   // upvalue 1
    lua_pushcfunction(L, data_unpack); // upvalue 2
    hive_getenv(L, "dispatcher");      // upvalue 3
    if (!lua_isfunction(L, -1)) {
        printf("set dispatcher first\n");
        return _error(L, c);
    }
    lua_pushlightuserdata(L, c); // upvalue 4
    lua_pushcclosure(L, lcallback, 4);

    return c;
}

cell *cell_socket(lua_State *L, cell *sys, const char *socketfile) {
    require_socket(L);

    cell *c = cell_alloc(L);
    c->single_thread = true;

    require_cell(L, c, [sys](lua_State *L, int cell_map) {
        cell_touserdata(L, cell_map, sys);
        lua_setfield(L, -2, "system");
    });

    return init_cell(L, c, socketfile, nullptr);
}

cell *cell_sys(lua_State *L, cell *sys, cell *socket, const char *systemfile,
               const char *mainfile, const char *loaderfile) {
    require_sys(L, socket, mainfile, loaderfile);

    sys->single_thread = true;

    require_cell(L, sys, [sys](lua_State *L, int cell_map) {
        cell_touserdata(L, cell_map, sys);
        lua_setfield(L, -2, "system");
    });

    lua_pushlightuserdata(L, sys);
    hive_setenv(L, "system_pointer");

    return init_cell(L, sys, systemfile, nullptr);
}

cell *cell_new(lua_State *L, const char *mainfile, const char *loaderfile) {
    require_socket(L);

    cell *c = cell_alloc(L);

    require_cell(L, c, [](lua_State *L, int cell_map) {
        hive_getenv(L, "system_pointer");
        auto sys = static_cast<cell *>(
            lua_touserdata(L, -1)); // cell_map cell_lib system_cell
        lua_pop(L, 1);
        if (sys) {
            cell_touserdata(L, cell_map, sys);
            lua_setfield(L, -2, "system");
        }
    });

    return init_cell(L, c, mainfile, loaderfile);
}

void cell_close(cell *c) {
    c->lock();
    if (!c->close) {
        c->close = true;
        c->push_in_gmq();
    }
    c->unlock();
}

static void _dispatch(lua_State *L, message *m) {
    lua_pushvalue(L, 1);
    lua_pushinteger(L, m->type);
    lua_pushlightuserdata(L, m->buffer);
    lua_call(L, 2, 0);
}

static void trash_msg(lua_State *L, cell *c) {
    // no new message in , because already set c->close
    // don't need lock c later
    message m;
    while (c->pop(&m)) {
        _dispatch(L, &m);
    }
    // HIVE_PORT 5 : exit
    // read cell.lua
    m.type = 5;
    m.buffer = nullptr;
    _dispatch(L, &m);
}

bool cell_dispatch_message(cell *c) {
    c->lock();
    lua_State *L = c->L;
    if (c->close && L) {
        c->L = nullptr;
        cell_grab(c);
        c->pop_out_gmq();
        c->unlock();
        trash_msg(L, c);
        cell_release(c);
        scheduler_deletetask(L);
        return false;
    }

    message m;
    if (!c->pop(&m) || L == nullptr) {
        c->unlock();
        return false;
    }

    cell_grab(c);
    ++c->message_count;
    c->unlock();
    _dispatch(L, &m);
    cell_release(c);

    return true;
}

int cell_send(cell *c, int type, void *msg) {
    c->lock();
    if (c->close) {
        c->unlock();
        return 1;
    }
    c->push(type, msg);
    c->unlock();
    return 0;
}

static int ltostring(lua_State *L) {
    char tmp[64];
    auto cud = static_cast<cell_ud *>(lua_touserdata(L, 1));
    int n = sprintf(tmp, "[cell %p, id %d]", cud->c, cud->c->id);
    lua_pushlstring(L, tmp, n);
    return 1;
}

static int lrelease(lua_State *L) {
    auto cud = static_cast<cell_ud *>(lua_touserdata(L, 1));
    cell_release(cud->c);
    cud->c = nullptr;
    return 0;
}

static int lmqlen(lua_State *L) {
    auto cud = static_cast<cell_ud *>(luaL_checkudata(L, 1, "cell"));
    luaL_argcheck(L, cud != nullptr, 1, "cell expected");
    cud->c->lock();
    lua_pushinteger(L, cud->c->mq.size());
    cud->c->unlock();
    return 1;
}

static int lmessage(lua_State *L) {
    auto cud = static_cast<cell_ud *>(luaL_checkudata(L, 1, "cell"));
    luaL_argcheck(L, cud != nullptr, 1, "cell expected");
    cud->c->lock();
    lua_pushinteger(L, cud->c->message_count);
    cud->c->unlock();
    return 1;
}

static int lid(lua_State *L) {
    auto cud = static_cast<cell_ud *>(luaL_checkudata(L, 1, "cell"));
    luaL_argcheck(L, cud != nullptr, 1, "cell expected");
    cud->c->lock();
    lua_pushinteger(L, cud->c->id);
    cud->c->unlock();
    return 1;
}

void cell_touserdata(lua_State *L, int index, cell *c) {
    lua_rawgetp(L, index, c);
    if (lua_isuserdata(L, -1)) {
        return;
    }
    lua_pop(L, 1);
    auto cud = static_cast<cell_ud *>(lua_newuserdatauv(L, sizeof(cell_ud), 0));
    cud->c = c;
    cell_grab(c);
    if (luaL_newmetatable(L, "cell")) {
        lua_pushboolean(L, 1);
        lua_rawsetp(L, -2, CELL_TAG);

        luaL_Reg l[] = {
            {"mqlen", lmqlen},
            {"message", lmessage},
            {"id", lid},
            {nullptr, nullptr},
        };
        luaL_newlib(L, l);
        lua_setfield(L, -2, "__index");
        lua_pushcfunction(L, ltostring);
        lua_setfield(L, -2, "__tostring");
        lua_pushcfunction(L, lrelease);
        lua_setfield(L, -2, "__gc");
    }
    lua_setmetatable(L, -2);
    lua_pushvalue(L, -1);
    lua_rawsetp(L, index, c);
}

cell *cell_fromuserdata(lua_State *L, int index) {
    if (lua_type(L, index) != LUA_TUSERDATA) {
        return nullptr;
    }
    if (lua_getmetatable(L, index)) {
        lua_rawgetp(L, -1, CELL_TAG);
        if (lua_toboolean(L, -1)) {
            lua_pop(L, 2);
            auto cud = static_cast<cell_ud *>(lua_touserdata(L, index));
            return cud->c;
        }
        lua_pop(L, 2);
    }
    return nullptr;
}

void cell_grab(cell *c) { c->ref.fetch_add(1); }

void cell_release(cell *c) {
    c->ref.fetch_sub(1);
    if (c->ref.load() == 0) {
        globalmq_dec(c->gmq);
        delete c;
    }
}