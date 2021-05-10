#ifndef common_h
#define common_h

#include "asio/io_context.hpp"

#include <atomic>
#include <memory>
#include <unordered_map>

static std::atomic<uint32_t> auto_session_increase_id{1};

static uint32_t get_session_increase_id() {
    return auto_session_increase_id.fetch_add(1);
}

class session;
static std::unordered_map<uint32_t, std::shared_ptr<session>> session_map;

class server;
static std::unordered_map<uint32_t, std::shared_ptr<server>> server_map;

class client;
static std::unordered_map<uint32_t, std::shared_ptr<client>> client_map;

static asio::io_context io_context;
static asio::io_context::work work(io_context);

#endif