#ifndef DB_PUT_H
#define DB_PUT_H

#include <msgpack.hpp>
int db_put(msgpack::object_str &indiv_msgpack, msgpack::object_str &user_id, bool need_auth);

#endif