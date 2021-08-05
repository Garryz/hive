#ifndef hive_log_h
#define hive_log_h

#include "hive_cell.h"

void set_logger(cell *c);
cell *get_logger();
void log_error(const char *msg, ...);

#endif