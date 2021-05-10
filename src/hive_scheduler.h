#ifndef hive_scheduler_h
#define hive_scheduler_h

#include "lua.hpp"

struct global_queue;
struct cell;
void globalmq_push(global_queue *q, cell *c);
cell *globalmq_pop(global_queue *q);
void globalmq_inc(global_queue *q);
void globalmq_dec(global_queue *q);
int globalmq_size(global_queue *q);

lua_State *scheduler_newtask(lua_State *L, bool inc);
void scheduler_starttask(lua_State *L);
void scheduler_deletetask(lua_State *L);

extern "C" int scheduler_start(lua_State *L);

#endif