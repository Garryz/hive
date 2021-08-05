#ifndef server_h
#define server_h

#include "session.h"

class server : public std::enable_shared_from_this<server> {
  public:
    server(const server &) = delete;
    server &operator=(const server &) = delete;

    server(cell *c, const char *addr, unsigned short port)
        : acceptor(io_context), to_cell(c), id(get_session_increase_id()),
          addr(addr), port(port) {
        cell_grab(c);
    }

    bool listen() {
        asio::ip::tcp::resolver resolver(io_context);
        std::error_code ec;
        asio::ip::tcp::resolver::iterator iter =
            resolver.resolve(addr, std::to_string(port), ec);
        asio::ip::tcp::resolver::iterator end;

        if (iter == end || ec) {
            log_error(
                "server listen address = %s, port = %d, id = %d, error_code "
                "= %d, error = %s",
                addr, port, id, ec.value(), ec.message().c_str());
            return false;
        }

        acceptor.open(iter->endpoint().protocol());
        acceptor.set_option(asio::ip::tcp::acceptor::reuse_address(true));
        acceptor.set_option(asio::socket_base::debug(true));
        acceptor.set_option(asio::socket_base::enable_connection_aborted(true));
        acceptor.set_option(asio::socket_base::linger(true, 30));
        acceptor.set_option(asio::ip::tcp::no_delay(true));
        acceptor.non_blocking(true);
        acceptor.bind(iter->endpoint());
        acceptor.listen();

        accept();
        return true;
    }

    uint32_t session_id() { return id; }

    void close() { acceptor.close(); }

    ~server() {
        if (to_cell) {
            cell_release(to_cell);
        }
    }

  private:
    void accept() {
        auto self(shared_from_this());

        acceptor.async_accept([this, self](std::error_code ec,
                                           asio::ip::tcp::socket socket) {
            if (!acceptor.is_open()) {
                log_error("accept not open, id = %d", id);
                return;
            }

            if (!ec) {
                auto s = std::make_shared<session>(std::move(socket),
                                                   get_session_increase_id());
                session_map[s->session_id()] = s;
                notify_accept(s);
                s->start();
                accept();
            } else if (ec != asio::error::operation_aborted) {
                log_error("accept error_code = %d, error = %s, id = %d",
                          ec.value(), ec.message().c_str(), id);
            }
        });
    }

    void notify_accept(std::shared_ptr<session> session) {
        write_block b;
        b.init(nullptr);
        b.wb_integer(id);
        b.wb_integer(session->session_id());
        std::string address =
            session->get_socket().remote_endpoint().address().to_string();
        b.wb_string(address.c_str(), address.length());
        block *ret = b.close();
        if (cell_send(to_cell, 6, ret)) {
            b.free();
        }
    }

    asio::ip::tcp::acceptor acceptor;
    cell *to_cell;
    uint32_t id;
    const char *addr;
    unsigned short port;
};

#endif