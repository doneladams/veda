#ifndef INDIVIDUAL_H
#define INDIVIDUAL_H

#include <iostream>
#include <vector>
#include <map>
#include <iostream>

#define MP_SOURCE 1

#include "msgpuck.h"

using namespace std;

typedef enum
{
    LANG_NONE = 0,
    LANG_RU   = 1,
    LANG_EN   = 2
} tLANG;

typedef enum ResourceType
{
    _Uri      = 1,
    _String   = 2,
    _Integer  = 4,
    _Datetime = 8,
    _Decimal  = 32,
    _Boolean  = 64
} tResourceType;

typedef enum ResourceOrigin
{
    _local    = 1,
    _external = 2
} tResourceOrigin;

struct Resource
{
    uint8_t type;
    uint8_t origin;
    uint8_t lang;

    string  str_data;
    bool    bool_data;
    int64_t long_data;
    int64_t decimal_mantissa_data;
    int64_t decimal_exponent_data;

    Resource () : type(0), origin(0), lang(0), str_data (""), bool_data(false), long_data(0), decimal_mantissa_data(0), decimal_exponent_data(0){};
};

struct Individual
{
    string uri;
    map < string, vector <Resource> > resources;
};

#endif