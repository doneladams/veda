#ifndef RIGHT_H
#define RIGHT_H

#include <iostream>
#include <map>
#include <stdint.h>

#define MEMBERSHIP_PREFIX   "M"
#define PERMISSION_PREFIX   "P"
#define FILTER_PREFIX       "F"

#define ACCESS_CAN_CREATE  (1 << 0)
#define ACCESS_CAN_READ    (1 << 1)
#define ACCESS_CAN_UPDATE  (1 << 2)
#define ACCESS_CAN_DELETE  (1 << 3)

#define DEFAULT_ACCESS 15

using namespace std;

struct Right {
    string id;
    uint8_t  access;
    bool is_deleted = false;
};

#endif