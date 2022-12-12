#ifndef udp_server_h
#define udp_server_h

#include "udp_session.h"

class udp_server : public std::enable_shared_from_this<udp_server> {
   public:
    udp_server(const udp_server &) = delete;
    udp_server &operator=(const udp_server &) = delete;

    udp_server(cell *c, const char *addr, unsigned short port)
        : remote_endpoint(),
          to_cell(c),
          id(get_session_increase_id()),
          addr(addr),
          port(port) {
        acceptor = std::make_shared<asio::ip::udp::socket>(io_context);
        cell_grab(c);
    }

    bool listen() {
        asio::ip::udp::resolver resolver(io_context);
        std::error_code ec;
        asio::ip::udp::resolver::iterator iter =
            resolver.resolve(addr, std::to_string(port), ec);
        asio::ip::udp::resolver::iterator end;

        if (iter == end || ec) {
            log_error(
                "udp listen address = %s, port = %d, id = %d, error_code "
                "= %d, error = %s",
                addr, port, id, ec.value(), ec.message().c_str());
            return false;
        }

        acceptor->open(iter->endpoint().protocol());
        acceptor->bind(iter->endpoint());

        accept();
        return true;
    }

    uint32_t session_id() { return id; }

    void remove_session(asio::ip::udp::endpoint endpoint) {
        sessions[endpoint] = nullptr;
    }

    void close() { acceptor->close(); }

    ~udp_server() {
        if (to_cell) {
            cell_release(to_cell);
        }
    }

   private:
    void accept() {
        auto self(shared_from_this());
        auto block = new udp_r_block;
        acceptor->async_receive_from(
            asio::buffer(block->data, block->len), remote_endpoint,
            [this, self, block](std::error_code ec, std::size_t length) {
                if (!acceptor->is_open()) {
                    log_error("udp accept not open, id = %d", id);
                    return;
                }

                if (!ec) {
                    auto s = sessions[remote_endpoint];
                    if (s == nullptr) {
                        s = std::make_shared<udp_session>(
                            acceptor, remote_endpoint,
                            get_session_increase_id(), id);
                        udp_session_map[s->session_id()] = s;
                        sessions[remote_endpoint] = s;
                        notify_accept(s);
                    }
                    block->len = length;
                    s->read(block);
                    accept();
                } else if (ec != asio::error::operation_aborted) {
                    log_error("udp accept error_code = %d, error = %s, id = %d",
                              ec.value(), ec.message().c_str(), id);
                }
            });
    }

    void notify_accept(std::shared_ptr<udp_session> session) {
        write_block b;
        b.init(nullptr);
        b.wb_integer(id);
        b.wb_integer(session->session_id());
        std::string address = remote_endpoint.address().to_string();
        b.wb_string(address.c_str(), address.length());
        block *ret = b.close();
        if (cell_send(to_cell, 12, ret)) {
            b.free();
        }
    }

    std::shared_ptr<asio::ip::udp::socket> acceptor;
    asio::ip::udp::endpoint remote_endpoint;
    cell *to_cell;
    uint32_t id;
    const char *addr;
    unsigned short port;
    std::unordered_map<asio::ip::udp::endpoint, std::shared_ptr<udp_session>>
        sessions;
};

#endif