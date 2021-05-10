#ifndef session_h
#define session_h

#include "asio_buffer.h"
#include "common.h"
#include "hive_cell.h"
#include "hive_seri.h"

#include "asio/ip/tcp.hpp"

#include <vector>

static const std::size_t WARNING_SIZE = 1014 * 1024;

class session : public std::enable_shared_from_this<session> {
  public:
    session(const session &) = delete;
    session &operator=(const session &) = delete;

    session(asio::ip::tcp::socket socket, uint32_t session_id)
        : socket(std::move(socket)), id(session_id) {}

    asio::ip::tcp::socket &get_socket() { return socket; }

    uint32_t session_id() { return id; }

    int set_to_cell(cell *c) {
        if (to_cell) {
            return 0;
        }
        to_cell = c;
        cell_grab(c);
        std::size_t size = unsend_read_buffers.size();
        for (std::size_t i = 0; i < size; i++) {
            notify_message(unsend_read_buffers[i]);
        }
        unsend_read_buffers.clear();
        return 1;
    }

    cell *get_to_cell() { return to_cell; }

    void start() {
        reading = true;
        read();
    }

    void write(const char *data, std::size_t len) {
        pending_write_buffer.append(data, len);
        pending_write_len += len;
        write();
    }

    void pause() { reading = false; }

    void resume() {
        if (!reading) {
            reading = true;
            read();
        }
    }

    void close() { closing = true; }

    ~session() {
        if (to_cell) {
            cell_release(to_cell);
        }
        for (int i = 0; i < unsend_read_buffers.size(); i++) {
            delete unsend_read_buffers[i];
        }
        unsend_read_buffers.clear();
    }

  private:
    void write() {
        if (!writing && pending_write_len > 0) {
            writing = true;
            auto self(shared_from_this());

            socket.async_write_some(
                pending_write_buffer.const_buffer(),
                [this, self](std::error_code ec, std::size_t length) {
                    handle_write(ec, length);
                });
        }
    }

    void handle_write(std::error_code ec, std::size_t length) {
        writing = false;
        auto close_after_last_write = [this]() {
            std::error_code ec;
            socket.shutdown(asio::ip::tcp::socket::shutdown_send, ec);
        };

        if (!ec) {
            pending_write_buffer.retrieve(length);
            pending_write_len -= length;
            if (pending_write_len >= WARNING_SIZE &&
                pending_write_len >= warning_size) {
                warning_size =
                    warning_size == 0 ? WARNING_SIZE * 2 : warning_size * 2;
                notify_warning();
            } else if (pending_write_len < WARNING_SIZE) {
                warning_size = 0;
            }
            if (pending_write_len > 0) {
                write();
            } else if (closing) {
                close_after_last_write();
            }
        } else {
            printf("session id = %d, write error_code = %d, error = %s\n", id,
                   ec.value(), ec.message().c_str());
            if (ec != asio::error::operation_aborted &&
                ec != asio::error::bad_descriptor &&
                ec != asio::error::connection_aborted) {
                close_after_last_write();
                if (!closing) {
                    notify_close();
                }
            }
        }
    }

    void read() {
        auto self(shared_from_this());
        auto block = new r_block;
        socket.async_read_some(
            asio::buffer(block->data, block->len),
            [this, self, block](std::error_code ec, std::size_t length) {
                handle_read(block, ec, length);
            });
    }

    void handle_read(r_block *block, std::error_code ec, std::size_t length) {
        if (closing) {
            delete block;
            std::error_code ec;
            socket.shutdown(asio::ip::tcp::socket::shutdown_receive, ec);
            return;
        }

        if (!ec) {
            block->len = length;
            if (to_cell) {
                notify_message(block);
            } else {
                unsend_read_buffers.push_back(block);
            }
            if (reading) {
                read();
            }
        } else {
            printf("session id = %d, read error_code = %d, error = %s\n", id,
                   ec.value(), ec.message().c_str());
            if (ec != asio::error::operation_aborted &&
                ec != asio::error::bad_descriptor) {
                notify_close();
            }
        }
    }

    void notify_message(r_block *buffer) {
        write_block b;
        b.init(nullptr);
        b.wb_integer(id);
        b.wb_pointer(buffer, data_type::TYPE_USERDATA);
        block *ret = b.close();
        if (cell_send(to_cell, 7, ret)) {
            b.free();
            delete buffer;
        }
    }

    void notify_close() {
        if (!to_cell) {
            return;
        }

        write_block b;
        b.init(nullptr);
        b.wb_integer(id);
        block *ret = b.close();
        if (cell_send(to_cell, 8, ret)) {
            b.free();
        }
    }

    void notify_warning() {
        if (!to_cell) {
            return;
        }

        write_block b;
        b.init(nullptr);
        b.wb_integer(id);
        b.wb_integer(pending_write_len % 1024 == 0
                         ? pending_write_len / 1024
                         : pending_write_len / 1024 + 1);
        block *ret = b.close();
        if (cell_send(to_cell, 9, ret)) {
            b.free();
        }
    }

    cell *to_cell{nullptr};
    asio::ip::tcp::socket socket;
    uint32_t id;
    std::vector<r_block *> unsend_read_buffers;
    write_buffer pending_write_buffer;
    std::size_t pending_write_len{0};
    std::size_t warning_size{0};
    bool writing{false};
    bool reading{false};
    bool closing{false};
};

#endif