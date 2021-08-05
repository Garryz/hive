#ifndef client_h
#define client_h

#include "session.h"

class client : public std::enable_shared_from_this<client> {
  public:
    client(const client &) = delete;
    client &operator=(const client &) = delete;

    client(cell *c, const char *addr, unsigned short port)
        : addr(addr), port(port) {
        asio::ip::tcp::socket socket(io_context);
        session_ptr = std::make_shared<session>(std::move(socket),
                                                get_session_increase_id());
        session_ptr->set_to_cell(c);
    }

    bool connect(lua_Integer event) {
        asio::ip::tcp::resolver resolver(io_context);
        std::error_code ec;
        asio::ip::tcp::resolver::iterator iter =
            resolver.resolve(addr, std::to_string(port), ec);
        asio::ip::tcp::resolver::iterator end;

        if (iter == end || ec) {
            log_error("client connect address = %s, port = %d, id = %d, "
                      "error_code = %d, error = %s",
                      addr, port, session_ptr->session_id(), ec.value(),
                      ec.message().c_str());
            return false;
        }

        auto self(shared_from_this());
        session_ptr->get_socket().async_connect(
            *iter, [this, self, event](std::error_code ec) {
                handle_connect(event, ec);
            });
        return true;
    }

    std::shared_ptr<session> get_session() { return session_ptr; }

    uint32_t session_id() { return session_ptr->session_id(); }

    void close() { session_ptr->close(); }

    ~client() {}

  private:
    void handle_connect(lua_Integer event, std::error_code &ec) {
        if (!ec) {
            session_ptr->get_socket().set_option(
                asio::socket_base::debug(true));
            session_ptr->get_socket().set_option(
                asio::socket_base::enable_connection_aborted(true));
            session_ptr->get_socket().set_option(
                asio::socket_base::linger(true, 30));
            session_ptr->get_socket().set_option(asio::ip::tcp::no_delay(true));
            session_ptr->get_socket().non_blocking(true);
            session_ptr->start();

            notify_connect_succ(event);
        } else {
            client_map[session_ptr->session_id()] = nullptr;
            session_map[session_ptr->session_id()] = nullptr;

            log_error("client connect address = %s, port = %d, id = %d, "
                      "error_code = %d, error = %s",
                      addr, port, session_ptr->session_id(), ec.value(),
                      ec.message().c_str());

            notify_connect_fail(event, ec.message());
        }
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

    const char *addr;
    unsigned short port;
    std::shared_ptr<session> session_ptr;
};

#endif