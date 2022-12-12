#include "hive_socket_lib.h"

#include "client.h"
#include "server.h"
#include "udp_client.h"
#include "udp_server.h"

static int llisten(lua_State *L) {
    cell *c = cell_fromuserdata(L, 1);
    if (c == nullptr) {
        return 0;
    }
    const char *addr = luaL_checkstring(L, 2);
    unsigned short port = static_cast<unsigned short>(luaL_checkinteger(L, 3));

    auto s = std::make_shared<server>(c, addr, port);
    if (s->listen()) {
        server_map[s->session_id()] = s;
        lua_pushinteger(L, s->session_id());
        return 1;
    }

    return 0;
}

static int lconnect(lua_State *L) {
    cell *c = cell_fromuserdata(L, 1);
    if (c == nullptr) {
        return 0;
    }
    const char *addr = luaL_checkstring(L, 2);
    unsigned short port = static_cast<unsigned short>(luaL_checkinteger(L, 3));
    lua_Integer event = luaL_checkinteger(L, 4);

    auto cl = std::make_shared<client>(c, addr, port);
    if (cl->connect(event)) {
        client_map[cl->session_id()] = cl;
        session_map[cl->session_id()] = cl->get_session();
    }

    return 0;
}

static int lpollonce(lua_State *L) {
    lua_pushinteger(L, io_context.poll());
    return 1;
}

static int lpollfor(lua_State *L) {
    lua_Integer ts = 100;
    if (lua_gettop(L) > 0) {
        ts = luaL_checkinteger(L, 1);
    }
    lua_pushinteger(L, io_context.run_for(std::chrono::milliseconds(ts)));
    return 1;
}

static int lforward(lua_State *L) {
    uint32_t session_id = static_cast<uint32_t>(luaL_checkinteger(L, 1));
    cell *c = cell_fromuserdata(L, 2);
    if (c == nullptr) {
        return 0;
    }
    auto session = session_map[session_id];
    if (session == nullptr) {
        return 0;
    }
    int boolean = session->set_to_cell(c);
    lua_pushboolean(L, boolean);
    return 1;
}

static int lsendpack(lua_State *L) {
    std::size_t len = 0;
    const char *str = luaL_checklstring(L, 1, &len);
    lua_pushinteger(L, static_cast<lua_Integer>(len));
    char *msg = new char[len];
    memcpy(msg, str, len);
    lua_pushlightuserdata(L, msg);
    return 2;
}

static int lsend(lua_State *L) {
    uint32_t id = static_cast<uint32_t>(luaL_checkinteger(L, 1));
    std::size_t sz = static_cast<std::size_t>(luaL_checkinteger(L, 2));
    auto msg = static_cast<const char *>(lua_touserdata(L, 3));
    auto session = session_map[id];
    if (session == nullptr) {
        delete[] msg;
        return luaL_error(L, "Write to invalid socket %d", id);
    }
    session->write(msg, sz);
    return 0;
}

static int lfree(lua_State *L) {
    read_buffer *buffer = static_cast<read_buffer *>(lua_touserdata(L, 1));
    buffer->free();
    return 0;
}

static int lpush(lua_State *L) {
    read_buffer *buffer = static_cast<read_buffer *>(lua_touserdata(L, 1));
    std::size_t bytes = 0;
    if (buffer) {
        bytes = buffer->len;
    }
    r_block *block = static_cast<r_block *>(lua_touserdata(L, 2));
    if (block == nullptr) {
        lua_settop(L, 1);
        lua_pushinteger(L, bytes);
        return 2;
    }

    if (buffer == nullptr) {
        buffer = static_cast<read_buffer *>(
            lua_newuserdatauv(L, sizeof(read_buffer), 0));
        lua_newtable(L);
        lua_pushcfunction(L, lfree);
        lua_setfield(L, -2, "__gc");
        lua_setmetatable(L, -2);

        buffer->init(block);
    } else {
        lua_settop(L, 1);
        buffer->append(block);
    }
    lua_pushinteger(L, buffer->len);
    return 2;
}

static int lreadline(lua_State *L) {
    read_buffer *buffer = static_cast<read_buffer *>(lua_touserdata(L, 1));
    if (buffer == nullptr) {
        return 0;
    }

    std::size_t len = 0;
    const char *sep = luaL_checklstring(L, 2, &len);
    bool read = !lua_toboolean(L, 3);

    if (buffer->len + 1 <= len) {
        return 0;
    }
    for (std::size_t i = 0; i < buffer->len + 1 - len; i++) {
        if (buffer->check_sep(i, sep, len)) {
            if (!read) {
                lua_pushboolean(L, 1);
            } else {
                std::size_t tmp_i = i;
                std::size_t tmp_len = len;
                if (i == 0) {
                    lua_pushlstring(L, "", 0);
                } else {
                    if (i < (buffer->head->len - buffer->head->ptr)) {
                        lua_pushlstring(
                            L, &buffer->head->data[buffer->head->ptr], i);
                        buffer->head->ptr += i;
                    } else {
                        luaL_Buffer b;
                        luaL_buffinit(L, &b);
                        luaL_addlstring(&b,
                                        &buffer->head->data[buffer->head->ptr],
                                        buffer->head->len - buffer->head->ptr);
                        r_block *block = buffer->head;
                        i -= (block->len - block->ptr);
                        buffer->head = block->next;
                        delete block;
                        while (buffer->head && i > buffer->head->len) {
                            luaL_addlstring(&b, &buffer->head->data[0],
                                            buffer->head->len);
                            block = buffer->head;
                            i -= block->len;
                            buffer->head = block->next;
                            delete block;
                        }
                        if (buffer->head && i > 0) {
                            luaL_addlstring(&b, &buffer->head->data[0], i);
                            luaL_pushresult(&b);
                            buffer->head->ptr = i;
                        } else {
                            luaL_pushresult(&b);
                        }
                    }
                }
                if (len < (buffer->head->len - buffer->head->ptr)) {
                    buffer->head->ptr += len;
                } else {
                    r_block *block = buffer->head;
                    len -= (block->len - block->ptr);
                    buffer->head = block->next;
                    delete block;
                    while (buffer->head && len > buffer->head->len) {
                        block = buffer->head;
                        len -= block->len;
                        buffer->head = block->next;
                        delete block;
                    }
                    if (buffer->head) {
                        if (len == buffer->head->len) {
                            block = buffer->head;
                            buffer->head = block->next;
                            delete block;
                            if (buffer->head == nullptr) {
                                buffer->tail = nullptr;
                            }
                        } else {
                            buffer->head->ptr = len;
                        }
                    } else {
                        buffer->tail = nullptr;
                    }
                }
                buffer->len -= (tmp_i + tmp_len);
            }
            return 1;
        }
    }
    return 0;
}

static int lpop(lua_State *L) {
    read_buffer *buffer = static_cast<read_buffer *>(lua_touserdata(L, 1));
    if (buffer == nullptr) {
        return 0;
    }

    std::size_t sz = static_cast<std::size_t>(luaL_checkinteger(L, 2));

    if (sz > buffer->len || buffer->len == 0) {
        lua_pushnil(L);
        lua_pushinteger(L, buffer->len);
        return 2;
    }

    if (sz == 0) {
        sz = buffer->len;
    }

    std::size_t tmp_sz = sz;
    if (sz < (buffer->head->len - buffer->head->ptr)) {
        lua_pushlstring(L, &buffer->head->data[buffer->head->ptr], sz);
        buffer->head->ptr += sz;
    } else {
        luaL_Buffer b;
        luaL_buffinit(L, &b);
        luaL_addlstring(&b, &buffer->head->data[buffer->head->ptr],
                        buffer->head->len - buffer->head->ptr);
        r_block *block = buffer->head;
        sz -= (block->len - block->ptr);
        buffer->head = block->next;
        delete block;
        while (buffer->head && sz > buffer->head->len) {
            luaL_addlstring(&b, &buffer->head->data[0], buffer->head->len);
            block = buffer->head;
            sz -= block->len;
            buffer->head = block->next;
            delete block;
        }
        if (buffer->head && sz > 0) {
            luaL_addlstring(&b, &buffer->head->data[0], sz);
            luaL_pushresult(&b);
            if (sz == buffer->head->len) {
                block = buffer->head;
                buffer->head = block->next;
                delete block;
                if (buffer->head == nullptr) {
                    buffer->tail = nullptr;
                }
            } else {
                buffer->head->ptr = sz;
            }
        } else {
            luaL_pushresult(&b);
            if (buffer->head == nullptr) {
                buffer->tail = nullptr;
            }
        }
    }
    buffer->len -= tmp_sz;

    lua_pushinteger(L, buffer->len);

    return 2;
}

static int lreadall(lua_State *L) {
    read_buffer *buffer = static_cast<read_buffer *>(lua_touserdata(L, 1));
    if (buffer == nullptr) {
        return 0;
    }

    luaL_Buffer b;
    luaL_buffinit(L, &b);
    r_block *block = buffer->head;
    while (block) {
        luaL_addlstring(&b, &block->data[0], block->len);
        block = block->next;
    }
    buffer->free();
    luaL_pushresult(&b);
    return 1;
}

static int lpause(lua_State *L) {
    uint32_t id = static_cast<uint32_t>(luaL_checkinteger(L, 1));

    auto session = session_map[id];

    if (session) {
        session->pause();
    }

    return 0;
}

static int lresume(lua_State *L) {
    uint32_t id = static_cast<uint32_t>(luaL_checkinteger(L, 1));

    auto session = session_map[id];
    if (session) {
        session->resume();
    }

    return 0;
}

static int lclose(lua_State *L) {
    uint32_t id = static_cast<uint32_t>(luaL_checkinteger(L, 1));

    auto server = server_map[id];
    auto client = client_map[id];
    auto session = session_map[id];

    if (server) {
        server->close();
        server_map[id] = nullptr;
    } else if (client) {
        client->close();
        client_map[id] = nullptr;
        session_map[id] = nullptr;
    } else if (session) {
        session->close();
        session_map[id] = nullptr;
    }

    return 0;
}

static int ludp_listen(lua_State *L) {
    cell *c = cell_fromuserdata(L, 1);
    if (c == nullptr) {
        return 0;
    }
    const char *addr = luaL_checkstring(L, 2);
    unsigned short port = static_cast<unsigned short>(luaL_checkinteger(L, 3));

    auto s = std::make_shared<udp_server>(c, addr, port);
    if (s->listen()) {
        udp_server_map[s->session_id()] = s;
        lua_pushinteger(L, s->session_id());
        return 1;
    }

    return 0;
}

static int ludp_connect(lua_State *L) {
    cell *c = cell_fromuserdata(L, 1);
    if (c == nullptr) {
        return 0;
    }
    const char *addr = luaL_checkstring(L, 2);
    unsigned short port = static_cast<unsigned short>(luaL_checkinteger(L, 3));
    lua_Integer event = luaL_checkinteger(L, 4);

    auto cl = std::make_shared<udp_client>(c, addr, port);
    if (cl->connect(event)) {
        udp_client_map[cl->session_id()] = cl;
        udp_session_map[cl->session_id()] = cl->get_session();
    }

    return 0;
}

static int ludp_forward(lua_State *L) {
    uint32_t session_id = static_cast<uint32_t>(luaL_checkinteger(L, 1));
    cell *c = cell_fromuserdata(L, 2);
    if (c == nullptr) {
        return 0;
    }
    auto session = udp_session_map[session_id];
    if (session == nullptr) {
        return 0;
    }
    int boolean = session->set_to_cell(c);
    lua_pushboolean(L, boolean);
    return 1;
}

static int ludp_send(lua_State *L) {
    uint32_t id = static_cast<uint32_t>(luaL_checkinteger(L, 1));
    std::size_t sz = static_cast<std::size_t>(luaL_checkinteger(L, 2));
    auto msg = static_cast<const char *>(lua_touserdata(L, 3));
    auto session = udp_session_map[id];
    if (session == nullptr) {
        delete[] msg;
        return luaL_error(L, "Write to invalid udp socket %d", id);
    }
    session->write(msg, sz);
    return 0;
}

static int ludp_free(lua_State *L) {
    udp_read_buffer *buffer =
        static_cast<udp_read_buffer *>(lua_touserdata(L, 1));
    buffer->free();
    return 0;
}

static int ludp_push(lua_State *L) {
    udp_read_buffer *buffer =
        static_cast<udp_read_buffer *>(lua_touserdata(L, 1));
    udp_r_block *block = static_cast<udp_r_block *>(lua_touserdata(L, 2));
    if (block == nullptr) {
        lua_settop(L, 1);
        lua_pushboolean(L,
                        (buffer != nullptr && buffer->head != nullptr ? 1 : 0));
        return 2;
    }

    if (buffer == nullptr) {
        buffer = static_cast<udp_read_buffer *>(
            lua_newuserdatauv(L, sizeof(udp_read_buffer), 0));
        lua_newtable(L);
        lua_pushcfunction(L, ludp_free);
        lua_setfield(L, -2, "__gc");
        lua_setmetatable(L, -2);

        buffer->init(block);
    } else {
        lua_settop(L, 1);
        buffer->append(block);
    }
    lua_pushboolean(L, 1);
    return 2;
}

static int ludp_pop(lua_State *L) {
    udp_read_buffer *buffer =
        static_cast<udp_read_buffer *>(lua_touserdata(L, 1));
    if (buffer == nullptr) {
        return 0;
    }

    udp_r_block *block = buffer->pop();
    if (block == nullptr) {
        return 0;
    }

    lua_pushlstring(L, block->data.data(), block->len);
    delete block;
    return 1;
}

static int ludp_close(lua_State *L) {
    uint32_t id = static_cast<uint32_t>(luaL_checkinteger(L, 1));

    auto server = udp_server_map[id];
    auto client = udp_client_map[id];
    auto session = udp_session_map[id];

    if (server) {
        server->close();
        udp_server_map[id] = nullptr;
    } else if (client) {
        client->close();
        udp_client_map[id] = nullptr;
        udp_session_map[id] = nullptr;
    } else if (session) {
        session->close();
        udp_session_map[id] = nullptr;
        server = udp_server_map[session->belong_session_id()];
        if (server) {
            server->remove_session(session->remote_endpoint());
        }
    }

    return 0;
}

int socket_lib(lua_State *L) {
    luaL_checkversion(L);
    luaL_Reg l[] = {
        {"listen", llisten},
        {"connect", lconnect},
        {"pollonce", lpollonce},
        {"pollfor", lpollfor},
        {"forward", lforward},
        {"sendpack", lsendpack},
        {"send", lsend},
        {"push", lpush},
        {"readline", lreadline},
        {"pop", lpop},
        {"readall", lreadall},
        {"pause", lpause},
        {"resume", lresume},
        {"close", lclose},
        {"udp_listen", ludp_listen},
        {"udp_connect", ludp_connect},
        {"udp_forward", ludp_forward},
        {"udp_send", ludp_send},
        {"udp_push", ludp_push},
        {"udp_pop", ludp_pop},
        {"udp_close", ludp_close},
        {nullptr, nullptr},
    };
    luaL_newlib(L, l);

    return 1;
}