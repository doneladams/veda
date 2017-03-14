#ifndef DB_AUTH_H
#define DB_AUTH_H

#include <stdlib.h>
int db_auth(const char *user_id, size_t user_id_len, const char *res_uri, size_t res_uri_len);

#endif