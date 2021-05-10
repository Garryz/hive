#include "hive_scheduler.h"
#include "concurrent_queue.h"
#include "crash_dump.h"
#include "hive_cell.h"
#include "hive_env.h"

#include <atomic>
#include <cassert>
#include <chrono>
#include <thread>
#include <vector>

static const lua_Integer DEFAULT_THREAD = 4;

struct global_queue {
    std::atomic<int> *total;
    concurrent_queue<cell *> *queue;
};

struct timer {
    long long current;
    cell *sys;
    global_queue *mq;
};

void globalmq_push(global_queue *q, cell *c) {
    assert(c);
    q->queue->push(c);
}

cell *globalmq_pop(global_queue *q) {
    cell *c = nullptr;
    q->queue->pop(c);
    return c;
}

static void globalmq_init(global_queue *q) {
    q->total = new std::atomic<int>{0};
    q->queue = new concurrent_queue<cell *>{};
}

static void globalmq_release(global_queue *q) {
    delete q->total;
    delete q->queue;
}

void globalmq_inc(global_queue *q) { q->total->fetch_add(1); }

void globalmq_dec(global_queue *q) { q->total->fetch_sub(1); }

int globalmq_size(global_queue *q) { return q->total->load(); }

lua_State *scheduler_newtask(lua_State *pL, bool inc) {
    lua_State *L = luaL_newstate();
    luaL_openlibs(L);

    auto copy = [](lua_State *L, lua_State *pL, const char *table,
                   const char *field) {
        lua_getglobal(pL, table);
        lua_getfield(pL, -1, field);
        std::string str = luaL_checkstring(pL, -1);
        lua_pop(pL, 2);

        lua_getglobal(L, table);
        lua_pushstring(L, str.c_str());
        lua_setfield(L, -2, field);
        lua_pop(L, 1);
    };
    copy(L, pL, "package", "cpath");
    copy(L, pL, "package", "path");

    hive_createenv(L);

    global_queue *mq =
        static_cast<global_queue *>(hive_copyenv(L, pL, "message_queue"));
    if (inc) {
        globalmq_inc(mq);
    }
    hive_copyenv(L, pL, "system_pointer");

    lua_newtable(L);
    lua_newtable(L);
    lua_pushliteral(L, "v");
    lua_setfield(L, -2, "__mode");
    lua_setmetatable(L, -2);
    hive_setenv(L, "cell_map");

    return L;
}

void scheduler_starttask(lua_State *L) {
    hive_getenv(L, "message_queue");
    auto gmq = static_cast<global_queue *>(lua_touserdata(L, -1));
    lua_pop(L, 1);
    hive_getenv(L, "cell_pointer");
    auto c = static_cast<cell *>(lua_touserdata(L, -1));
    lua_pop(L, 1);
    globalmq_push(gmq, c);
}

void scheduler_deletetask(lua_State *L) { lua_close(L); }

static void _cell(global_queue *gmq, cell *c) {
    for (;;) {
        if (!cell_dispatch_message(c)) {
            std::this_thread::sleep_for(std::chrono::microseconds(1000));
            if (globalmq_size(gmq) <= 0) {
                return;
            }
        }
    }
}

static long long _gettime() {
    auto time_now = std::chrono::system_clock::now();
    auto duration_in_ms = std::chrono::duration_cast<std::chrono::milliseconds>(
        time_now.time_since_epoch());
    return duration_in_ms.count();
}

static void timer_init(timer *t, cell *sys, global_queue *mq) {
    t->current = _gettime();
    t->sys = sys;
    t->mq = mq;
}

static inline void send_tick(cell *c) { cell_send(c, 0, nullptr); }

static void _updatetime(timer *t) {
    long long ct = _gettime();
    if (ct > t->current) {
        long long diff = ct - t->current;
        t->current = ct;
        for (long long i = 0; i < diff; i++) {
            send_tick(t->sys);
        }
    }
}

static void _timer(timer *t) {
    for (;;) {
        _updatetime(t);
        std::this_thread::sleep_for(std::chrono::microseconds(2500));
        if (globalmq_size(t->mq) <= 0) {
            return;
        }
    }
}

static cell *_message_dispatch(global_queue *q, cell *c) {
    if (c == nullptr) {
        c = globalmq_pop(q);
        if (c == nullptr) {
            return nullptr;
        }
    }

    if (!cell_dispatch_message(c)) {
        return globalmq_pop(q);
    }

    cell *nc = globalmq_pop(q);
    if (nc) {
        // If global mq is not empty , push q back, and return next queue (nq)
        // Else (global mq is empty or block, don't push q back, and return q
        // again (for next dispatch)
        globalmq_push(q, c);
        c = nc;
    }

    return c;
}

static void _worker(global_queue *gmq) {
    cell *c = nullptr;
    for (;;) {
        c = _message_dispatch(gmq, c);
        if (c == nullptr) {
            std::this_thread::sleep_for(std::chrono::microseconds(1000));
            if (globalmq_size(gmq) <= 0) {
                return;
            }
        }
    }
}

static void _start(global_queue *gmq, cell *sys, cell *socket, timer *t,
                   int threadnum) {
    std::vector<std::thread> threads;

    threads.emplace_back(_cell, gmq, sys);

    threads.emplace_back(_cell, gmq, socket);

    threads.emplace_back(_timer, t);

    for (int i = 0; i < threadnum; i++) {
        threads.emplace_back(_worker, gmq);
    }

    for (auto &thread : threads) {
        thread.join();
    }
}

int scheduler_start(lua_State *L) {
    crash_dump();

    luaL_checktype(L, 1, LUA_TTABLE);
    const char *system_lua = luaL_checkstring(L, 2);
    const char *socket_lua = luaL_checkstring(L, 3);
    const char *main_lua = luaL_checkstring(L, 4);
    lua_getfield(L, 1, "thread");
    int thread = static_cast<int>(luaL_optinteger(L, -1, DEFAULT_THREAD));
    lua_pop(L, 1);

    hive_createenv(L);
    auto gmq = static_cast<global_queue *>(
        lua_newuserdatauv(L, sizeof(global_queue), 0));
    globalmq_init(gmq);

    lua_pushvalue(L, -1);
    hive_setenv(L, "message_queue");

    lua_State *sL = scheduler_newtask(L, false);
    cell *sys = cell_alloc(sL);

    lua_State *socketL = scheduler_newtask(L, false);
    cell *socket = cell_socket(socketL, sys, socket_lua);
    if (socket == nullptr) {
        return 0;
    }

    sys = cell_sys(sL, sys, socket, system_lua, main_lua);
    if (sys == nullptr) {
        return 0;
    }

    auto t = static_cast<timer *>(lua_newuserdatauv(L, sizeof(timer), 0));
    timer_init(t, sys, gmq);

    _start(gmq, sys, socket, t, thread);
    globalmq_release(gmq);

    return 0;
}