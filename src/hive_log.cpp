#include "hive_log.h"
#include "hive_seri.h"

static cell *logger = nullptr;

static const int LOG_MESSAGE_SIZE = 256;

void set_logger(cell *c) { logger = c; }

cell *get_logger() { return logger; }

void log_error(const char *msg, ...) {
    if (logger == nullptr) {
        va_list ap;
        va_start(ap, msg);
        vprintf(msg, ap);
        va_end(ap);
        return;
    }

    char tmp[LOG_MESSAGE_SIZE];
    char *data = nullptr;

    va_list ap;

    va_start(ap, msg);
    int len = vsnprintf(tmp, LOG_MESSAGE_SIZE, msg, ap);
    va_end(ap);
    if (len >= 0 && len < LOG_MESSAGE_SIZE) {
        std::size_t sz = strlen(tmp);
        data = new char[sz + 1];
        memcpy(data, tmp, sz + 1);
    } else {
        int max_size = LOG_MESSAGE_SIZE;
        while (true) {
            max_size *= 2;
            data = new char[max_size];
            va_start(ap, msg);
            len = vsnprintf(data, max_size, msg, ap);
            va_end(ap);
            if (len < max_size) {
                break;
            }
            delete[] data;
        }
    }
    if (len < 0) {
        delete[] data;
        perror("vsnprintf error");
        return;
    }

    write_block b;
    b.init(nullptr);
    b.wb_string(data, len);
    delete[] data;
    block *ret = b.close();
    if (cell_send(logger, 11, ret)) {
        b.free();
    }
}