#ifndef DB_GET_H
#define DB_GET_H

#include <msgpack.hpp>
size_t db_get(msgpack::object_str &key, char *out_buf);

#endif