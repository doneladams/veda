#ifndef RIGHT_H
#define RIGHT_H

#include <iostream>
#include <map>
#include <stdint.h>

#define MEMBERSHIP_PREFIX   "M"
#define PERMISSION_PREFIX   "P"
#define FILTER_PREFIX       "F"

#define ACCESS_CAN_CREATE 		(1U << 0)
#define ACCESS_CAN_READ 		(1U << 1)
#define ACCESS_CAN_UPDATE 		(1U << 2)
#define ACCESS_CAN_DELETE	 	(1U << 3)
#define ACCESS_CAN_NOT_CREATE 	(1U << 4)
#define ACCESS_CAN_NOT_READ		(1U << 5)
#define ACCESS_CAN_NOT_UPDATE 	(1U << 6)
#define ACCESS_CAN_NOT_DELETE 	(1U << 7)

#define DEFAULT_ACCESS 15

using namespace std;

struct Right {
    string id;
    uint8_t  access;
    bool is_deleted = false;
};

#endif