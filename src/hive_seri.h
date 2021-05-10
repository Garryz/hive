#ifndef hive_seri_h
#define hive_seri_h

#include "hive_cell.h"
#include "lua.hpp"

#include <cstddef>
#include <cstring>
#include <functional>

static const int BLOCK_SIZE = 128;
static const int MAX_DEPTH = 32;
static const int MAX_COOKIE = 32;

enum class data_type {
    TYPE_NIL,
    TYPE_BOOLEAN, // hibits 0 false 1 true
    TYPE_NUMBER,  // hibits 0 : 0 , 1: byte, 2:word, 4: dword, 8 : double
    TYPE_USERDATA,
    TYPE_SHORT_STRING, // hibits 0~31 : len
    TYPE_LONG_STRING,
    TYPE_TABLE,
    TYPE_CELL,
};

enum class number_type {
    TYPE_NUMBER_ZERO = 0,
    TYPE_NUMBER_BYTE = 1,
    TYPE_NUMBER_WORD = 2,
    TYPE_NUMBER_DWORD = 4,
    TYPE_NUMBER_QWORD = 6,
    TYPE_NUMBER_REAL = 8,
};

static constexpr uint8_t COMBINE_TYPE(data_type t, uint8_t v) {
    return static_cast<uint8_t>(t) | v << 3;
}

struct block {
    block *next{nullptr};
    char buffer[BLOCK_SIZE];
};

struct write_block {
    block *head{nullptr};
    int len{0};
    block *current{nullptr};
    int ptr{0};

    void push(const void *buf, int sz) {
        auto buffer = static_cast<const char *>(buf);

        auto new_next_block = [&]() {
            current->next = new block;
            current = current->next;
            ptr = 0;
        };

        std::function<void()> copy_buf = [&]() {
            if (ptr <= BLOCK_SIZE - sz) {
                memcpy(current->buffer + ptr, buffer, sz);
                ptr += sz;
                len += sz;
            } else {
                int copy = BLOCK_SIZE - ptr;
                memcpy(current->buffer + ptr, buffer, copy);
                buffer += copy;
                len += copy;
                sz -= copy;
                new_next_block();
                copy_buf();
            }
        };

        if (ptr == BLOCK_SIZE) {
            new_next_block();
        }
        copy_buf();
    }

    void init(block *b) {
        if (b == nullptr) {
            head = new block;
            current = head;
            push(&len, sizeof(len));
        } else {
            head = b;
            auto plen = reinterpret_cast<int *>(b->buffer);
            int sz = *plen;
            len = sz;
            while (b->next) {
                sz -= BLOCK_SIZE;
                b = b->next;
            }
            current = b;
            ptr = sz;
        }
    }

    block *close() {
        current = head;
        ptr = 0;
        push(&len, sizeof(len));
        current = nullptr;
        return head;
    }

    void free() {
        block *blk = head;
        while (blk) {
            block *next = blk->next;
            delete blk;
            blk = next;
        }
        head = nullptr;
        current = nullptr;
        ptr = 0;
        len = 0;
    }

    void wb_nil() {
        uint8_t n = static_cast<uint8_t>(data_type::TYPE_NIL);
        push(&n, sizeof(n));
    }

    void wb_integer(lua_Integer v) {
        data_type type = data_type::TYPE_NUMBER;
        if (v == 0) {
            uint8_t n = COMBINE_TYPE(
                type, static_cast<uint8_t>(number_type::TYPE_NUMBER_ZERO));
            push(&n, sizeof(n));
        } else if (v != static_cast<int32_t>(v)) {
            uint8_t n = COMBINE_TYPE(
                type, static_cast<uint8_t>(number_type::TYPE_NUMBER_QWORD));
            int64_t v64 = static_cast<int64_t>(v);
            push(&n, sizeof(n));
            push(&v64, sizeof(v64));
        } else if (v < 0) {
            uint8_t n = COMBINE_TYPE(
                type, static_cast<uint8_t>(number_type::TYPE_NUMBER_DWORD));
            int32_t v32 = static_cast<int32_t>(v);
            push(&n, sizeof(n));
            push(&v32, sizeof(v32));
        } else if (v < 0x100) {
            uint8_t n = COMBINE_TYPE(
                type, static_cast<uint8_t>(number_type::TYPE_NUMBER_BYTE));
            push(&n, sizeof(n));
            uint8_t byte = static_cast<uint8_t>(v);
            push(&byte, sizeof(byte));
        } else if (v < 0x10000) {
            uint8_t n = COMBINE_TYPE(
                type, static_cast<uint8_t>(number_type::TYPE_NUMBER_WORD));
            push(&n, sizeof(n));
            uint16_t word = static_cast<uint16_t>(v);
            push(&word, sizeof(word));
        } else {
            uint8_t n = COMBINE_TYPE(
                type, static_cast<uint8_t>(number_type::TYPE_NUMBER_DWORD));
            push(&n, sizeof(n));
            uint32_t v32 = static_cast<uint32_t>(v);
            push(&v32, sizeof(v32));
        }
    }

    void wb_number(double v) {
        uint8_t n =
            COMBINE_TYPE(data_type::TYPE_NUMBER,
                         static_cast<uint8_t>(number_type::TYPE_NUMBER_REAL));
        push(&n, sizeof(n));
        push(&v, sizeof(v));
    }

    void wb_boolean(int boolean) {
        uint8_t n = COMBINE_TYPE(data_type::TYPE_BOOLEAN, boolean ? 1 : 0);
        push(&n, sizeof(n));
    }

    void wb_string(const char *str, std::size_t len) {
        if (len < MAX_COOKIE) {
            uint8_t n = COMBINE_TYPE(data_type::TYPE_SHORT_STRING,
                                     static_cast<uint8_t>(len));
            push(&n, sizeof(n));
            if (len > 0) {
                push(str, static_cast<int>(len));
            }
        } else {
            uint8_t n;
            if (len < 0x10000) {
                n = COMBINE_TYPE(data_type::TYPE_LONG_STRING, 2);
                push(&n, sizeof(n));
                uint16_t x = static_cast<uint16_t>(len);
                push(&x, sizeof(x));
            } else {
                n = COMBINE_TYPE(data_type::TYPE_LONG_STRING, 4);
                push(&n, sizeof(n));
                uint32_t x = static_cast<uint32_t>(len);
                push(&x, sizeof(x));
            }
            push(str, static_cast<int>(len));
        }
    }

    void wb_pointer(void *v, data_type type) {
        uint8_t n = static_cast<uint8_t>(type);
        push(&n, sizeof(n));
        push(&v, sizeof(v));
    }

    int wb_table_array(lua_State *L, int index, int depth) {
        int array_size = static_cast<int>(lua_rawlen(L, index));
        if (array_size >= MAX_COOKIE - 1) {
            uint8_t n = COMBINE_TYPE(data_type::TYPE_TABLE, MAX_COOKIE - 1);
            push(&n, sizeof(n));
            wb_integer(array_size);
        } else {
            uint8_t n = COMBINE_TYPE(data_type::TYPE_TABLE, array_size);
            push(&n, sizeof(n));
        }

        for (int i = 1; i <= array_size; i++) {
            lua_rawgeti(L, index, i);
            _pack_one(L, -1, depth);
            lua_pop(L, 1);
        }

        return array_size;
    }

    void wb_table_hash(lua_State *L, int index, int depth, int array_size) {
        lua_pushnil(L);
        while (lua_next(L, index) != 0) {
            if (lua_type(L, -2) == LUA_TNUMBER) {
                lua_Number k = lua_tonumber(L, 2);
                int32_t x = static_cast<int32_t>(lua_tointeger(L, -2));
                if (k == static_cast<lua_Number>(x) && x > 0 &&
                    x <= array_size) {
                    lua_pop(L, 1);
                    continue;
                }
            }
            _pack_one(L, -2, depth);
            _pack_one(L, -1, depth);
            lua_pop(L, 1);
        }
        wb_nil();
    }

    void wb_table(lua_State *L, int index, int depth) {
        if (index < 0) {
            index = lua_gettop(L) + index + 1;
        }
        int array_size = wb_table_array(L, index, depth);
        wb_table_hash(L, index, depth, array_size);
    }

    void _pack_one(lua_State *L, int index, int depth) {
        if (depth > MAX_DEPTH) {
            free();
            luaL_error(L, "serialize can't pack too depth table");
            return;
        }
        int type = lua_type(L, index);
        switch (type) {
        case LUA_TNIL:
            wb_nil();
            break;
        case LUA_TNUMBER: {
            if (lua_isinteger(L, index)) {
                lua_Integer x = lua_tointeger(L, index);
                wb_integer(x);
            } else {
                lua_Number n = lua_tonumber(L, index);
                wb_number(n);
            }
            break;
        }
        case LUA_TBOOLEAN:
            wb_boolean(lua_toboolean(L, index));
            break;
        case LUA_TSTRING: {
            std::size_t sz = 0;
            const char *str = lua_tolstring(L, index, &sz);
            wb_string(str, sz);
            break;
        }
        case LUA_TLIGHTUSERDATA:
            wb_pointer(lua_touserdata(L, index), data_type::TYPE_USERDATA);
            break;
        case LUA_TTABLE:
            wb_table(L, index, depth + 1);
            break;
        case LUA_TUSERDATA: {
            cell *c = cell_fromuserdata(L, index);
            if (c) {
                cell_grab(c);
                wb_pointer(c, data_type::TYPE_CELL);
                break;
            }
            // else go through
        }
        default:
            free();
            luaL_error(L, "Unsupport type %s to serialize",
                       lua_typename(L, type));
        }
    }

    void _pack_from(lua_State *L, int from) {
        int n = lua_gettop(L) - from;
        for (int i = 1; i <= n; i++) {
            _pack_one(L, from + i, 0);
        }
    }
};

struct read_block {
    char *buffer{nullptr};
    block *current{nullptr};
    int len{0};
    int ptr{0};

    int init(block *b) {
        current = b;
        memcpy(&len, b->buffer, sizeof(len));
        ptr = sizeof(len);
        len -= ptr;
        return len;
    }

    void *read(void *buf, int sz) {
        if (len < sz) {
            return nullptr;
        }

        if (buffer) {
            int tmp_ptr = ptr;
            ptr += sz;
            len -= sz;
            return buffer + tmp_ptr;
        }

        if (ptr == BLOCK_SIZE) {
            block *next = current->next;
            delete current;
            current = next;
            ptr = 0;
        }

        int copy = BLOCK_SIZE - ptr;

        if (sz <= copy) {
            void *ret = current->buffer + ptr;
            ptr += sz;
            len -= sz;
            return ret;
        }

        char *tmp = static_cast<char *>(buf);

        memcpy(tmp, current->buffer + ptr, copy);
        sz -= copy;
        tmp += copy;
        len -= copy;

        for (;;) {
            block *next = current->next;
            delete current;
            current = next;

            if (sz < BLOCK_SIZE) {
                memcpy(tmp, current->buffer, sz);
                ptr = sz;
                len -= sz;
                return buf;
            }

            memcpy(tmp, current->buffer, BLOCK_SIZE);
            sz -= BLOCK_SIZE;
            tmp += BLOCK_SIZE;
            len -= BLOCK_SIZE;
        }
    }

    void close() {
        while (current) {
            block *next = current->next;
            delete current;
            current = next;
        }
        len = 0;
        ptr = 0;
    }

    void __invalid_stream(lua_State *L, int line) {
        int tmp_len = len;
        if (buffer == nullptr) {
            close();
        }
        luaL_error(L, "Invalid serialize stream %d (line:%d)", len, line);
    }

#define _invalid_stream(L) __invalid_stream(L, __LINE__)

    lua_Integer _get_integer(lua_State *L, int cookie) {
        number_type type = static_cast<number_type>(cookie);
        switch (type) {
        case number_type::TYPE_NUMBER_ZERO:
            return 0;
        case number_type::TYPE_NUMBER_BYTE: {
            uint8_t n = 0;
            uint8_t *pn = static_cast<uint8_t *>(read(&n, sizeof(n)));
            if (pn == nullptr) {
                _invalid_stream(L);
            }
            return *pn;
        }
        case number_type::TYPE_NUMBER_WORD: {
            uint16_t n = 0;
            uint16_t *pn = static_cast<uint16_t *>(read(&n, sizeof(n)));
            if (pn == nullptr) {
                _invalid_stream(L);
            }
            return *pn;
        }
        case number_type::TYPE_NUMBER_DWORD: {
            int32_t n = 0;
            int32_t *pn = static_cast<int32_t *>(read(&n, sizeof(n)));
            if (pn == nullptr) {
                _invalid_stream(L);
            }
            return *pn;
        }
        case number_type::TYPE_NUMBER_QWORD: {
            int64_t n = 0;
            int64_t *pn = static_cast<int64_t *>(read(&n, sizeof(n)));
            if (pn == nullptr) {
                _invalid_stream(L);
            }
            return *pn;
        }
        default:
            _invalid_stream(L);
            return 0;
        }
    }

    double _get_number(lua_State *L) {
        double n = 0;
        double *pn = static_cast<double *>(read(&n, sizeof(n)));
        if (pn == nullptr) {
            _invalid_stream(L);
        }
        return *pn;
    }

    void *_get_pointer(lua_State *L) {
        void *userdata = nullptr;
        void **v = static_cast<void **>(read(&userdata, sizeof(userdata)));
        if (v == nullptr) {
            _invalid_stream(L);
        }
        return *v;
    }

    void _get_buffer(lua_State *L, int len) {
        char *tmp = new char[len];
        char *p = static_cast<char *>(read(tmp, len));
        lua_pushlstring(L, p, len);
        delete[] tmp;
    }

    void _unpack_one(lua_State *L, int table_index) {
        uint8_t type = 0;
        uint8_t *t = static_cast<uint8_t *>(read(&type, sizeof(type)));
        if (t == nullptr) {
            _invalid_stream(L);
        }
        _push_value(L, *t & 0x7, *t >> 3, table_index);
    }

    void _unpack_table(lua_State *L, int array_size, int table_index) {
        if (array_size == MAX_COOKIE - 1) {
            uint8_t type = 0;
            uint8_t *t = static_cast<uint8_t *>(read(&type, sizeof(type)));
            if (t == nullptr ||
                (*t & 0x7) != static_cast<uint8_t>(data_type::TYPE_NUMBER) ||
                (*t >> 3) ==
                    static_cast<uint8_t>(number_type::TYPE_NUMBER_REAL)) {
                _invalid_stream(L);
            }
            array_size = static_cast<int>(_get_integer(L, *t >> 3));
        }
        luaL_checkstack(L, LUA_MINSTACK, nullptr);
        lua_createtable(L, array_size, 0);
        for (int i = 1; i <= array_size; i++) {
            _unpack_one(L, table_index);
            lua_rawseti(L, -2, i);
        }

        for (;;) {
            _unpack_one(L, table_index);
            if (lua_isnil(L, -1)) {
                lua_pop(L, 1);
                return;
            }
            _unpack_one(L, table_index);
            lua_rawset(L, -3);
        }
    }

    void _push_value(lua_State *L, int type, int cookie, int table_index) {
        switch (static_cast<data_type>(type)) {
        case data_type::TYPE_NIL:
            lua_pushnil(L);
            break;
        case data_type::TYPE_BOOLEAN:
            lua_pushboolean(L, cookie);
            break;
        case data_type::TYPE_NUMBER:
            if (cookie == static_cast<int>(number_type::TYPE_NUMBER_REAL)) {
                lua_pushnumber(L, _get_number(L));
            } else {
                lua_pushinteger(L, _get_integer(L, cookie));
            }
            break;
        case data_type::TYPE_USERDATA:
            lua_pushlightuserdata(L, _get_pointer(L));
            break;
        case data_type::TYPE_CELL: {
            cell *c = static_cast<cell *>(_get_pointer(L));
            cell_touserdata(L, table_index, c);
            cell_release(c);
            break;
        }
        case data_type::TYPE_SHORT_STRING:
            _get_buffer(L, cookie);
            break;
        case data_type::TYPE_LONG_STRING:
            if (cookie == 2) {
                uint16_t len = 0;
                uint16_t *plen =
                    static_cast<uint16_t *>(read(&len, sizeof(len)));
                if (plen == nullptr) {
                    _invalid_stream(L);
                }
                _get_buffer(L, static_cast<int>(*plen));
            } else {
                if (cookie != 4) {
                    _invalid_stream(L);
                }
                uint32_t len = 0;
                uint32_t *plen =
                    static_cast<uint32_t *>(read(&len, sizeof(len)));
                if (plen == nullptr) {
                    _invalid_stream(L);
                }
                _get_buffer(L, static_cast<int>(*plen));
            }
            break;
        case data_type::TYPE_TABLE:
            _unpack_table(L, cookie, table_index);
            break;
        }
    }
};

int data_pack(lua_State *L);
int data_unpack(lua_State *L);

#endif