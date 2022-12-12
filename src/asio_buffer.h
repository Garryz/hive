#ifndef asio_buffer_h
#define asio_buffer_h

#include <array>
#include <list>
#include <vector>

#include "asio/buffer.hpp"

static const int READ_BLOCK_SIZE = 512;
static const int UDP_BLOCK_SIZE = 1400;

struct r_block {
    std::array<char, READ_BLOCK_SIZE> data;
    std::size_t len{READ_BLOCK_SIZE};
    std::size_t ptr{0};
    r_block *next{nullptr};
};

struct read_buffer {
    r_block *head;
    r_block *tail;
    std::size_t len;

    void init(r_block *block) {
        head = block;
        tail = block;
        len = block->len;
    }

    void append(r_block *block) {
        if (head == nullptr) {
            head = block;
            tail = block;
            len = block->len;
        } else {
            tail->next = block;
            tail = block;
            len += block->len;
        }
    }

    const char *peek(std::size_t index) {
        if (index >= len || head == nullptr) {
            return nullptr;
        }
        if (index >= (len - tail->len)) {
            return &tail->data[index - (len - tail->len)];
        }
        if (index < (head->len - head->ptr)) {
            return &head->data[head->ptr + index];
        }
        index -= (head->len - head->ptr);
        r_block *next = head->next;
        while (next != tail) {
            if (index >= next->len) {
                index -= next->len;
                next = next->next;
            } else {
                return &next->data[index];
            }
        }
        return nullptr;
    }

    int check_sep(std::size_t from, const char *sep, std::size_t sz) {
        for (std::size_t i = 0; i < sz; i++) {
            std::size_t index = from + i;
            const char *p = peek(index);
            if (p == nullptr) {
                return 0;
            }
            if (*p != sep[i]) {
                return 0;
            }
        }
        return 1;
    }

    void free() {
        while (head != tail) {
            r_block *next = head->next;
            delete head;
            head = next;
        }
        if (head) {
            delete head;
        }
        head = nullptr;
        tail = nullptr;
        len = 0;
    }
};

struct w_block {
    const char *data{nullptr};
    std::size_t len{0};
    std::size_t ptr{0};

    ~w_block() { delete[] data; }
};

class write_buffer {
   public:
    write_buffer() = default;
    write_buffer(const write_buffer &) = delete;
    write_buffer &operator=(const write_buffer &) = delete;

    void append(const char *data, std::size_t len) {
        w_block *blk = new w_block;
        blk->data = data;
        blk->len = len;
        buffer.push_back(blk);
    }

    const std::vector<asio::const_buffer> &const_buffer() {
        c_buffer.clear();
        std::list<w_block *>::iterator iter = buffer.begin();
        if (iter != buffer.end()) {
            c_buffer.push_back(asio::buffer((*iter)->data + (*iter)->ptr,
                                            (*iter)->len - (*iter)->ptr));
            iter++;
        }
        for (; iter != buffer.end(); ++iter) {
            c_buffer.push_back(asio::buffer((*iter)->data, (*iter)->len));
        }
        return c_buffer;
    }

    void retrieve(std::size_t len) {
        std::list<w_block *>::iterator iter = buffer.begin();
        if (iter != buffer.end()) {
            if ((*iter)->ptr + len < (*iter)->len) {
                (*iter)->ptr += len;
                return;
            } else {
                len -= ((*iter)->len - (*iter)->ptr);
                delete (*iter);
                iter = buffer.erase(iter);
            }
        }

        while (iter != buffer.end()) {
            if (len > (*iter)->len) {
                len -= (*iter)->len;
                delete (*iter);
                iter = buffer.erase(iter);
            } else {
                (*iter)->ptr = len;
                break;
            }
        }
    }

    ~write_buffer() {
        for (std::list<w_block *>::iterator iter = buffer.begin();
             iter != buffer.end(); ++iter) {
            delete (*iter);
        }
        buffer.clear();
    }

   private:
    std::list<w_block *> buffer;
    std::vector<asio::const_buffer> c_buffer;
};

struct udp_r_block {
    std::array<char, UDP_BLOCK_SIZE> data;
    std::size_t len{UDP_BLOCK_SIZE};
    udp_r_block *next{nullptr};
};

struct udp_read_buffer {
    udp_r_block *head;

    void init(udp_r_block *block) { head = block; }

    void append(udp_r_block *block) {
        if (head == nullptr) {
            head = block;
        } else {
            head->next = block;
        }
    }

    udp_r_block *pop() {
        auto block = head;
        if (head != nullptr) {
            head = head->next;
        }
        return block;
    }

    void free() {
        while (head != nullptr) {
            auto block = head;
            head = head->next;
            delete block;
        }
    }
};

struct udp_w_block {
    const char *data{nullptr};
    std::size_t len{0};

    ~udp_w_block() { delete[] data; }
};

class udp_write_buffer {
   public:
    udp_write_buffer() = default;
    udp_write_buffer(const udp_write_buffer &) = delete;
    udp_write_buffer *operator=(const udp_write_buffer &) = delete;

    void append(const char *data, std::size_t len) {
        udp_w_block *blk = new udp_w_block;
        blk->data = data;
        blk->len = len;
        buffer.push_back(blk);
    }

    const std::vector<asio::const_buffer> &const_buffer() {
        c_buffer.clear();
        std::list<udp_w_block *>::iterator iter = buffer.begin();
        if (iter != buffer.end()) {
            c_buffer.push_back(asio::buffer((*iter)->data, (*iter)->len));
        }
        return c_buffer;
    }

    void retrieve() {
        std::list<udp_w_block *>::iterator iter = buffer.begin();
        if (iter != buffer.end()) {
            delete (*iter);
            iter = buffer.erase(iter);
        }
    }

    ~udp_write_buffer() {
        for (std::list<udp_w_block *>::iterator iter = buffer.begin();
             iter != buffer.end(); ++iter) {
            delete (*iter);
        }
        buffer.clear();
    }

   private:
    std::list<udp_w_block *> buffer;
    std::vector<asio::const_buffer> c_buffer;
};

#endif