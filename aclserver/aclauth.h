#ifndef ACLAUTH_H
#define ACLAUTH_H

#include <stdlib.h>
int aclauth(const char *user_id, size_t user_id_len, const char *res_uri, size_t res_uri_len);

#endif