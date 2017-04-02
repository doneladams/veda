#ifndef DB_DELETE_H
#define DB_DELETE_H

#include <msgpack.hpp>
int db_remove(msgpack::object_str &key, msgpack::object_str &user_id, bool need_auth);

#endif