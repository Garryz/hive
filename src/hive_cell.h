#ifndef hive_cell_h
#define hive_cell_h

#include "lua.hpp"

struct cell;

cell *cell_alloc(lua_State *L);
cell *cell_socket(lua_State *L, cell *sys, const char *socketfile);
cell *cell_sys(lua_State *L, cell *sys, cell *socket, const char *systemfile,
               const char *mainfile, const char *loaderfie);
cell *cell_new(lua_State *L, const char *mainfile, const char *loaderfile);
void cell_close(cell *c);
bool cell_dispatch_message(cell *c);
int cell_send(cell *c, int type, void *msg);
void cell_touserdata(lua_State *L, int index, cell *c);
cell *cell_fromuserdata(lua_State *L, int index);
void cell_grab(cell *c);
void cell_release(cell *c);

#endif