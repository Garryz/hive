#ifndef concurrent_queue_h
#define concurrent_queue_h

#include <condition_variable>
#include <initializer_list>
#include <mutex>
#include <queue>

template <typename T> class concurrent_queue {
  private:
    mutable std::mutex mut;
    using queue_type = std::queue<T>;
    queue_type data_queue;

  public:
    using value_type = typename queue_type::value_type;
    using container_type = typename queue_type::container_type;
    concurrent_queue() = default;
    concurrent_queue(const concurrent_queue &) = delete;
    concurrent_queue &operator=(const concurrent_queue &) = delete;

    template <typename _InputIterator>
    concurrent_queue(_InputIterator first, _InputIterator last) {
        for (auto itor = first; itor != last; ++itor) {
            data_queue.push(*itor);
        }
    }

    explicit concurrent_queue(const container_type &c) : data_queue(c) {}

    concurrent_queue(std::initializer_list<value_type> list)
        : concurrent_queue(list.begin(), list.end()) {}

    template <typename U> void push(U &&new_value) {
        mut.lock();
        data_queue.push(std::forward<U>(new_value));
        mut.unlock();
    }

    bool pop(value_type &value) {
        mut.lock();
        if (data_queue.empty()) {
            mut.unlock();
            return false;
        }
        value = std::move(data_queue.front());
        data_queue.pop();
        mut.unlock();
        return true;
    }

    auto empty() const -> decltype(data_queue.empty()) {
        mut.lock();
        auto e = data_queue.empty();
        mut.unlock();
        return e;
    }

    auto size() const -> decltype(data_queue.size()) {
        mut.lock();
        auto s = data_queue.size();
        mut.unlock();
        return s;
    }
};

#endif