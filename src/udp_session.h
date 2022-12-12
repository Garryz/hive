#ifndef udp_session_h
#define udp_session_h

#include "asio/ip/udp.hpp"
#include "asio_buffer.h"
#include "common.h"
#include "hive_cell.h"
#include "hive_log.h"
#include "hive_seri.h"

class udp_session : public std::enable_shared_from_this<udp_session> {
   public:
    udp_session(const udp_session &) = delete;
    udp_session &operator=(const udp_session &) = delete;

    udp_session(std::shared_ptr<asio::ip::udp::socket> socket,
                asio::ip::udp::endpoint endpoint, uint32_t session_id,
                uint32_t belong_id)
        : socket(socket),
          endpoint(endpoint),
          id(session_id),
          belong_id(belong_id) {}

    std::shared_ptr<asio::ip::udp::socket> &get_socket() { return socket; }

    asio::ip::udp::endpoint &remote_endpoint() { return endpoint; }

    uint32_t session_id() { return id; }

    uint32_t belong_session_id() { return belong_id; }

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

    void read(udp_r_block *block) {
        if (closing) {
            delete block;
            return;
        }

        if (to_cell) {
            notify_message(block);
        } else {
            unsend_read_buffers.push_back(block);
        }
    }

    void write(const char *data, std::size_t len) {
        pending_write_buffer.append(data, len);
        pending_write_count++;
        write();
    }

    void close() { closing = true; }

    void notify_close() {
        if (!to_cell) {
            return;
        }

        write_block b;
        b.init(nullptr);
        b.wb_integer(id);
        block *ret = b.close();
        if (cell_send(to_cell, 14, ret)) {
            b.free();
        }
    }

    ~udp_session() {
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
        if (!writing && pending_write_count > 0) {
            writing = true;
            auto self(shared_from_this());

            socket->async_send_to(
                pending_write_buffer.const_buffer(), endpoint,
                [this, self](std::error_code ec, std::size_t length) {
                    handle_write(ec, length);
                });
        }
    }

    void handle_write(std::error_code ec, std::size_t length) {
        writing = false;
        auto close_after_last_write = [this]() {
            std::error_code ec;
            socket->shutdown(asio::ip::tcp::socket::shutdown_send, ec);
        };

        if (!ec) {
            pending_write_buffer.retrieve();
            pending_write_count--;
            if (pending_write_count > 0) {
                write();
            } else if (closing) {
                close_after_last_write();
            }
        } else {
            log_error("udp session id = %d, write error_code = %d, error = %s",
                      id, ec.value(), ec.message().c_str());
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

    void notify_message(udp_r_block *buffer) {
        write_block b;
        b.init(nullptr);
        b.wb_integer(id);
        b.wb_pointer(buffer, data_type::TYPE_USERDATA);
        block *ret = b.close();
        if (cell_send(to_cell, 13, ret)) {
            b.free();
            delete buffer;
        }
    }

    cell *to_cell{nullptr};
    std::shared_ptr<asio::ip::udp::socket> socket;
    asio::ip::udp::endpoint endpoint;
    uint32_t id;
    uint32_t belong_id;
    std::vector<udp_r_block *> unsend_read_buffers;
    udp_write_buffer pending_write_buffer;
    std::size_t pending_write_count{0};
    bool writing{false};
    bool closing{false};
};

#endif