#ifndef endian_h
#define endian_h

#include <cstdint>
#include <cstdio>

static bool is_small_endian() {
    union {
        int i;
        char ch;
    } endian;
    endian.i = 1;
    return endian.ch;
}

template <typename BASE_DATA_TYPE>
static BASE_DATA_TYPE change_endian(BASE_DATA_TYPE value) {
    BASE_DATA_TYPE result = 0;
    unsigned char *value_p = reinterpret_cast<unsigned char *>(&value);
    unsigned char *result_p = reinterpret_cast<unsigned char *>(&result);
    std::size_t byte = sizeof(BASE_DATA_TYPE);
    for (std::size_t i = 0; i < byte; ++i) {
        result_p[i] = value_p[byte - i - 1];
    }
    return result;
}

template <typename BASE_DATA_TYPE>
static BASE_DATA_TYPE adapte_endian(BASE_DATA_TYPE value,
                                    bool big_endian = true) {
    bool system_small_endian = is_small_endian();
    if ((system_small_endian && big_endian) ||
        (!system_small_endian && !big_endian)) {
        return change_endian<BASE_DATA_TYPE>(value);
    }
    return value;
}

#endif