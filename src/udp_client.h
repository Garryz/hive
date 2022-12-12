#ifndef udp_client_h
#define udp_client_h

#include "udp_session.h"

class udp_client : public std::enable_shared_from_this<udp_client> {
   public:
    udp_client(const udp_client &) = delete;
    udp_client &operator=(const udp_client &) = delete;

    udp_client(cell *c, const char *addr, unsigned short port)
        : to_cell(c), addr(addr), port(port) {}

    bool connect(lua_Integer event) {
        asio::ip::udp::resolver resolver(io_context);
        std::error_code ec;
        asio::ip::udp::resolver::iterator iter =
            resolver.resolve(addr, std::to_string(port), ec);
        asio::ip::udp::resolver::iterator end;

        if (iter == end || ec) {
            log_error(
                "udp client connect address = %s, port = %d, "
                "error_code = %d, error = %s",
                addr, port, ec.value(), ec.message().c_str());
            return false;
        }

        auto self(shared_from_this());
        auto socket = std::make_shared<asio::ip::udp::socket>(io_context);
        auto id = get_session_increase_id();
        session_ptr = std::make_shared<udp_session>(socket, *iter, id, id);
        session_ptr->set_to_cell(to_cell);
        session_ptr->get_socket()->async_connect(
            *iter, [this, self, event](std::error_code ec) {
                handle_connect(event, ec);
            });
        return true;
    }

    std::shared_ptr<udp_session> get_session() { return session_ptr; }

    uint32_t session_id() { return session_ptr->session_id(); }

    void close() { closing = true, session_ptr->close(); }

    ~udp_client() {}

   private:
    void handle_connect(lua_Integer event, std::error_code &ec) {
        if (!ec) {
            notify_connect_succ(event);
            handle_recv();
        } else {
            udp_client_map[session_ptr->session_id()] = nullptr;
            udp_session_map[session_ptr->session_id()] = nullptr;

            log_error(
                "udp client connect address = %s, port = %d, id = %d, "
                "error_code = %d, error = %s",
                addr, port, session_ptr->session_id(), ec.value(),
                ec.message().c_str());

            notify_connect_fail(event, ec.message());
        }
    }

    void handle_recv() {
        auto self(shared_from_this());
        auto block = new udp_r_block;
        session_ptr->get_socket()->async_receive(
            asio::buffer(block->data, block->len),
            [this, self, block](std::error_code ec, std::size_t length) {
                if (closing) {
                    delete block;
                    std::error_code ec;
                    session_ptr->get_socket()->shutdown(
                        asio::ip::udp::socket::shutdown_receive, ec);
                    return;
                }

                if (!ec) {
                    block->len = length;
                    session_ptr->read(block);
                    handle_recv();
                } else {
                    delete block;
                    log_error(
                        "session id = %d, read error_code = %d, error = %s",
                        session_ptr->session_id(), ec.value(),
                        ec.message().c_str());
                    if (ec != asio::error::operation_aborted &&
                        ec != asio::error::bad_descriptor) {
                        session_ptr->notify_close();
                    }
                }
            });
    }

    void notify_connect_succ(lua_Integer event) {
        write_block b;
        b.init(nullptr);
        b.wb_integer(event);
        b.wb_boolean(1);
        b.wb_integer(session_ptr->session_id());
        block *ret = b.close();
        if (cell_send(session_ptr->get_to_cell(), 1, ret)) {
            b.free();
        }
    }

    void notify_connect_fail(lua_Integer event, std::string msg) {
        write_block b;
        b.init(nullptr);
        b.wb_integer(event);
        b.wb_boolean(1);
        b.wb_nil();
        b.wb_string(msg.c_str(), msg.length());
        block *ret = b.close();
        if (cell_send(session_ptr->get_to_cell(), 1, ret)) {
            b.free();
        }
    }

    cell *to_cell;
    const char *addr;
    unsigned short port;
    std::shared_ptr<udp_session> session_ptr;
    bool closing{false};
};

#endif