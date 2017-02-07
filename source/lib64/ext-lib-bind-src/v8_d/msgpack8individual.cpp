#define _GLIBCXX_USE_CXX11_ABI    0
#include "cbor.h"

#include <string.h>
#include <iostream>
#include <math.h>
#include "msgpuck.h"
#include "msgpack8individual.h"

uint32_t write_individual(Individual *individual, const char *in_buff)
{
    char     *pos;
    uint64_t map_len = individual->resources.size() + 1;

    pos = mp_encode_array(pos, 2);
    pos = mp_encode_str(pos, individual->uri.c_str(), individual->uri.length());

    pos = mp_encode_map(pos, individual->resources.size());

    map < string, vector <Resource> >::iterator p;
    for (p = individual->resources.begin(); p != individual->resources.end(); ++p)
    {
        std::string strKey = p->first;
        if (p->second.size() > 0)
            pos = write_resources(p->first, p->second, pos);
    }
    return(pos - in_buff);
}

char *write_resources(string uri, vector <Resource> vv, char *w)
{
    w = mp_encode_str(w, uri.c_str(), uri.length());

    w = mp_encode_array(w, vv.size());

    for (int i = 0; i < vv.size(); i++)
    {
        Resource value = vv[ i ];

        if (value.type == _Uri)
        {
            string svalue = value.str_data;
            w = mp_encode_str(w, svalue.c_str(), svalue.length());
        }
        else if (value.type == _Integer)
        {
            w = mp_encode_uint(w, value.long_data);
        }
        else if (value.type == _Datetime)
        {
            w = mp_encode_array(w, 2);
            w = mp_encode_uint(w, _Datetime);
            w = mp_encode_uint(w, value.long_data);
        }
        else if (value.type == _Decimal)
        {
            w = mp_encode_array(w, 3);
            w = mp_encode_uint(w, _Decimal);
            w = mp_encode_uint(w, value.decimal_mantissa_data);
            w = mp_encode_uint(w, value.decimal_expanent_data);
        }
        else if (value.type == _Boolean)
        {
            w = mp_encode_bool(w, value.bool_data);
        }
        else
        {
            string svalue = value.str_data;

            if (value.lang != LANG_NONE)
            {
                w = mp_encode_array(w, 3);
                w = mp_encode_uint(w, _String);
                w = mp_encode_str(w, svalue.c_str(), svalue.length());
                w = mp_encode_uint(w, value.lang);
            }
            else
            {
                w = mp_encode_array(w, 2);
                w = mp_encode_uint(w, _String);
                w = mp_encode_str(w, svalue.c_str(), svalue.length());
            }
        }
    }
    return w;
}

/////////////////////////////////////////////////////////////////////////////////////


int msgpack2individual(Individual *individual, string in_str)
{
    const char *ptr    = (char *)in_str.c_str();
    const char *in_ptr = ptr;

    int        root_el_size = mp_decode_array(&ptr);

    if (root_el_size != 2)
        return -1;

    uint        uri_lenght;
    const char  *uri = mp_decode_str(&ptr, &uri_lenght);

    std::string str(ptr, uri_lenght);

    individual->uri = str;

    int predicates_length = mp_decode_map(&ptr);

    for (int idx = 0; idx < predicates_length; idx++)
    {
        uint              key_lenght;
        const char        *key = mp_decode_str(&ptr, &key_lenght);

        std::string       predicate(ptr, key_lenght);

        vector <Resource> resources;

        int               resources_el_length = mp_decode_array(&ptr);
        for (int i_resource; i_resource < resources_el_length; i_resource++)
        {
            mp_type el_type = mp_typeof(*ptr);
            //          writeln ("@0 el_type=", text (cast(mp_type)el_type));

            if (el_type == MP_ARRAY)
            {
                int predicate_el_length = mp_decode_array(&ptr);
                if (predicate_el_length == 2)
                {
                    long type = mp_decode_uint(&ptr);

                    if (type == _Datetime)
                    {
                        long     value = mp_decode_uint(&ptr);

                        Resource rr;
                        rr.type      = _Datetime;
                        rr.long_data = value;
                        resources.push_back(rr);
                    }
                    else if (type == _String)
                    {
                        uint        val_length;
                        const char  *val = mp_decode_str(&ptr, &val_length);

                        Resource    rr;
                        rr.type = _String;
                        std::string value(ptr, val_length);
                        rr.str_data = value;
                        rr.lang     = LANG_NONE;
                        resources.push_back(rr);
                    }
                    else
                    {
                        //writeln ("@1");
                        return -1;
                    }
                }
                else if (predicate_el_length == 3)
                {
                    long type = mp_decode_uint(&ptr);

                    if (type == _Decimal)
                    {
                        long     mantissa = mp_decode_uint(&ptr);
                        long     exponent = mp_decode_uint(&ptr);

                        Resource rr;
                        rr.type                  = _Decimal;
                        rr.decimal_mantissa_data = mantissa;
                        rr.decimal_expanent_data = exponent;
                        resources.push_back(rr);
                    }
                    else if (type == _String)
                    {
                        uint        val_length;
                        const char  *val = mp_decode_str(&ptr, &val_length);
                        long        lang = mp_decode_uint(&ptr);

                        Resource    rr;
                        rr.type = _String;
                        std::string value(ptr, val_length);
                        rr.str_data = value;
                        rr.lang     = lang;
                        resources.push_back(rr);
                    }
                    else
                    {
                        //writeln ("@2");
                        return -1;
                    }
                }
                else
                {
                    //writeln ("@3");
                    return -1;
                }
            }
            else if (el_type == MP_STR)
            {
                // this uri
                uint        val_length;
                const char  *val = mp_decode_str(&ptr, &val_length);

                Resource    rr;
                rr.type = _Uri;
                std::string value(ptr, val_length);
                rr.str_data = value;
                resources.push_back(rr);
            }
            else if (el_type == MP_INT || el_type == MP_UINT)
            {
                // this int
                long     value = mp_decode_uint(&ptr);
                Resource rr;
                rr.type      = _Integer;
                rr.long_data = value;
                resources.push_back(rr);
            }
            else if (el_type == MP_BOOL)
            {
                // this bool
                long     value = mp_decode_bool(&ptr);
                Resource rr;
                rr.type      = _Boolean;
                rr.long_data = value;
                resources.push_back(rr);
            }
            else
            {
                //writeln ("@4 el_type=", text (cast(mp_type)el_type));
                return -1;
            }
        }
        individual->resources[ predicate ] = resources;
    }

    return (int)(ptr - in_ptr);
}

uint32_t individual2msgpack(Individual *individual, const char *in_buff)
{
    return write_individual(individual, in_buff);
}

