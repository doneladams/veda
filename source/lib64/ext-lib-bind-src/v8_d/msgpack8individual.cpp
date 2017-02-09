#define _GLIBCXX_USE_CXX11_ABI    0

#include <string.h>
#include <iostream>
#include <math.h>
#include "msgpuck.h"
#include "msgpack8individual.h"

uint32_t write_individual(Individual *individual, char *in_buff)
{
    char     *pos = in_buff;
    uint32_t map_len = individual->resources.size() + 1;

    pos = mp_encode_array(pos, 2);
    pos = mp_encode_str(pos, individual->uri.c_str(), individual->uri.length());

    pos = mp_encode_map(pos, individual->resources.size());

    map < string, vector <Resource> >::iterator p;
    for (p = individual->resources.begin(); p != individual->resources.end(); ++p)
    {
        std::string strKey = p->first;
        //if (p->second.size() > 0)
        //if (p->second.size() == 0)
	//std::cout << "@c write_individual resources.length==0" << std::endl;        
        
            pos = write_resources(p->first, p->second, pos);
    }
    return(pos - in_buff);
}

char *write_resources(string uri, vector <Resource> vv, char *w)
{
    w = mp_encode_str(w, uri.c_str(), uri.length());

    w = mp_encode_array(w, vv.size());

    for (uint32_t i = 0; i < vv.size(); i++)
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


int32_t msgpack2individual(Individual *individual, string in_str)
{
    const char *ptr    = (char *)in_str.c_str();
    const char *in_ptr = ptr;

	//std::cout << "@c msgpack2individual #1 [" << in_str << "]" << std::endl;

//uint32_t r = mp_check(&ptr, ptr + in_str.length ());
//  assert(!r);

    uint32_t        root_el_size = mp_decode_array(&ptr);

    if (root_el_size != 2)
        return -1;

    uint32_t       uri_lenght;
    const char  *uri = mp_decode_str(&ptr, &uri_lenght);

    std::string str(uri, uri_lenght);
	//std::cout << "@c msgpack2individual uri= [" << str << "]" << std::endl;

    individual->uri = str;

    uint32_t predicates_length = mp_decode_map(&ptr);
	//std::cout << "@c msgpack2individual predicates_length= [" << predicates_length << "]" << std::endl;

    for (uint32_t idx = 0; idx < predicates_length; idx++)
    {
	//std::cout << "@c msgpack2individual idx= [" << idx << "]" << std::endl;
        uint32_t              key_lenght;
        const char        *key = mp_decode_str(&ptr, &key_lenght);
	//std::cout << "@c msgpack2individual key_lenght= [" << key_lenght << "]" << std::endl;

        std::string       predicate(key, key_lenght);
	//std::cout << "@c msgpack2individual predicate= [" << predicate << "]" << std::endl;

        vector <Resource> resources;

        uint32_t               resources_el_length = mp_decode_array(&ptr);
	//std::cout << "@c msgpack2individual resources_el_length= [" << resources_el_length << "]" << std::endl;
        for (uint32_t i_resource = 0; i_resource < resources_el_length; i_resource++)
        {
            mp_type el_type = mp_typeof(*ptr);
	//std::cout << "@c msgpack2individual el_type= [" << el_type << "]" << std::endl;

            if (el_type == MP_ARRAY)
            {
                uint32_t predicate_el_length = mp_decode_array(&ptr);
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
                        std::string value(val, val_length);
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
                        std::string value(val, val_length);
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
                std::string value(val, val_length);
                rr.str_data = value;
                resources.push_back(rr);
            }
            else if (el_type == MP_INT || el_type == MP_UINT)
            {
                // this uint32_t
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
       // individual->resources[ predicate ] = resources;
    }

    return (int32_t)(ptr - in_ptr);
}

int32_t individual2msgpack(Individual *individual, char *in_buff)
{
    return write_individual(individual, in_buff);
}

