#define _GLIBCXX_USE_CXX11_ABI    0

#include <string.h>
#include <iostream>
#include <math.h>

#define MP_SOURCE 1

#include "msgpuck.h"
#include "msgpack8individual.h"

uint32_t write_individual(Individual *individual, char *in_buff)
{
    char     *pos = in_buff;
    uint32_t map_len = individual->resources.size() + 1;

    
    pos = mp_encode_array(pos, 2);
    // std::cerr << "TRY TO WRITE ";
    pos = mp_encode_str(pos, individual->uri.c_str(), individual->uri.length());
    // std::cerr << individual->uri << endl;

    pos = mp_encode_map(pos, individual->resources.size());
    // std::cerr << "TRY TO WRITE res size " << individual->resources.size() << endl;
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
    // std::cerr << "\tWRITE RES FOR ";
    w = mp_encode_str(w, uri.c_str(), uri.length());
    // std:cerr << uri << endl;

    // std::cerr << "\tWRITE ERR size ";
    w = mp_encode_array(w, vv.size());
    // std::cerr << vv.size() << endl;

    for (uint32_t i = 0; i < vv.size(); i++)
    {
        Resource value = vv[ i ];
        // std::cerr << "\t\tWRITE RES type is ";
        if (value.type == _Uri)
        {
            // std::cerr << "uri" << endl;
            string svalue = value.str_data;

            // std::cerr << "\t\tWRITE URI ";
            w = mp_encode_str(w, svalue.c_str(), svalue.length());
            // std::cerr << svalue << endl;
        }
        else if (value.type == _Integer)
        {
            // std::cerr << "integer" << endl;
            w = mp_encode_uint(w, value.long_data);
            // std::cerr << "\t\tWRITE INTEGER " << value.long_data << endl;
        }
        else if (value.type == _Datetime)
        {
            // std::cerr << "datatime" << endl;

            // std::cerr << "\t\tWRITE ARRAY OF 2" << endl;
            w = mp_encode_array(w, 2);
            w = mp_encode_uint(w, _Datetime);
            // std::cerr << "\t\tWRITE UINTEGER " << _Datetime << endl;
            w = mp_encode_uint(w, value.long_data);
            // std::cerr << "\t\tWRITE INTEGER " << value.long_data << endl;
        }
        else if (value.type == _Decimal)
        {
            // std::cerr << "\t\tWRITE ARRAY OF 3" << endl;
            w = mp_encode_array(w, 3);
            w = mp_encode_uint(w, _Decimal);
            // std::cerr << "\t\tWRITE UINTEGER " << _Decimal << endl;
            w = mp_encode_uint(w, value.decimal_mantissa_data);
            // std::cerr << "\t\tWRITE UINTEGER " << value.decimal_mantissa_data << endl;
            w = mp_encode_uint(w, value.decimal_expanent_data);
            // std::cerr << "\t\tWRITE UINTEGER " << value.decimal_expanent_data << endl;
        }
        else if (value.type == _Boolean)
        {
            // std::cerr << "boolean" << endl;
            w = mp_encode_bool(w, value.bool_data);
            // std::cerr << "\t\tWRITE BOOL " << value.bool_data << endl; 
        }
        else
        {
            // std::cerr << "lang ";
            string svalue = value.str_data;

            if (value.lang != LANG_NONE)
            {
                // std::cerr << "lang Not none" << endl;
                w = mp_encode_array(w, 3);
                // std::cerr << "\t\tWRITE ARRAY OF 3" << endl;
                w = mp_encode_uint(w, _String);
                // std::cerr << "\t\tWRITE UINTEGER " << _String << endl;
                w = mp_encode_str(w, svalue.c_str(), svalue.length());
                // std::cerr << "\t\tWRITE STRING " << svalue << endl;
                w = mp_encode_uint(w, value.lang);
                // std::cerr << "\t\tWRITE UINTEGER " << value.lang << endl;
            }
            else
            {
                // std::cerr << "lang Is none" << endl;
                w = mp_encode_array(w, 2);
                // std::cerr << "\t\tWRITE ARRAY OF 2" << endl;
                w = mp_encode_uint(w, _String);
                // std::cerr << "\t\tWRITE UINTEGER " << _String << endl;
                w = mp_encode_str(w, svalue.c_str(), svalue.length());
                // std::cerr << "\t\tWRITE STRING " << svalue << endl;
            }
        }
    }
    return w;
}
/////////////////////////////////////////////////////////////////////////////////////

int32_t msgpack2individual(Individual *individual, string in_str)
{
//    std::cout << "@c #0" << std::endl;

    const char *ptr    = (char *)in_str.c_str();
    const char *in_ptr = ptr;
    // std::cerr << "TRY TO DECODE " << in_str << endl;
    uint32_t        root_el_size = mp_decode_array(&ptr);
    // std::cerr << "TRY TO DECODE root_el_size=" << root_el_size << endl;

    if (root_el_size != 2)
        return -1;

    uint32_t       uri_lenght;
    
//    std::cout << "@c #1" << std::endl;
    // std::cerr << "TRY TO DECODE uri ";
    
     if (mp_typeof(*ptr) == MP_NIL) {
		std::cerr << "ERR! #1 mp_type.MP_NIL " << in_str << endl;
     }
    
    const char  *uri = mp_decode_str(&ptr, &uri_lenght);

    std::string str(uri, uri_lenght);
    // std::cerr << str << endl;
    
//    std::cout << "@c #2 uri=" << str << std::endl;

    individual->uri = str;

    // std::cerr << "TRY TO DECODE map len ";
    uint32_t predicates_length = mp_decode_map(&ptr);
    // std::cerr << predicates_length << endl;
    //std::cout << "@c #2 decode_map, len=" << predicates_length << ", ptr-ptr0=" << (ptr - in_ptr) << std::endl;

    for (uint32_t idx = 0; idx < predicates_length; idx++)
    {
        uint32_t              key_lenght;
//    std::cout << "@c #2" << std::endl;
        // std::cerr << "\tTRY TO DECODE KEY ";
     if (mp_typeof(*ptr) == MP_NIL) {
		std::cerr << "ERR! #2 mp_type.MP_NIL " << in_str << endl;
     }
        const char        *key = mp_decode_str(&ptr, &key_lenght);

//    std::cout << "@c #3" << std::endl;

        std::string       predicate(key, key_lenght);
        //std:cerr << predicate << endl;

        vector <Resource> resources;

        uint32_t               resources_el_length = mp_decode_array(&ptr);
        for (uint32_t i_resource = 0; i_resource < resources_el_length; i_resource++)
        {
            // std::cerr << "\t\tFOREACH RESOURCE type ";
            mp_type el_type = mp_typeof(*ptr);
            // std::cerr << el_type << " ";

            if (el_type == MP_ARRAY)
            {
                // std::cerr << "is array" << endl;
                // std::cerr << "\t\t\tTRY ARR SIZE ";
                uint32_t predicate_el_length = mp_decode_array(&ptr);
                if (predicate_el_length == 2)
                {
                    long type;
                    // std::cerr << predicate_el_length << endl;

                    // std::cerr << "\t\t\tDECODE UINT type is ";
                    if (mp_typeof(*ptr) == MP_UINT)
                        type = mp_decode_uint(&ptr);
                    else
                        type = mp_decode_int(&ptr);
                    

                    if (type == _Datetime)
                    {
                        long value; 
                        // std::cerr << "datetime" << endl;
                        if (mp_typeof(*ptr) == MP_UINT)
                            value = mp_decode_uint(&ptr);
                        else
                            value = mp_decode_int(&ptr);

                        Resource rr;
                        rr.type      = _Datetime;
                        rr.long_data = value;
                        resources.push_back(rr);
                    }
                    else if (type == _String)
                    {
                        Resource    rr;
                        std::string value;

                        // std::cerr << "string" << endl;
                        rr.type = _String;
                        if (mp_typeof(*ptr) != MP_NIL) {
                            uint        val_length;                
                            const char  *val = mp_decode_str(&ptr, &val_length);                
                            value = string(val, val_length);
                        } else {
                            value = string("", 0);
                            mp_decode_nil(&ptr);
                        }

                        rr.str_data = value;
                        rr.lang     = LANG_NONE;
                        resources.push_back(rr);

/*                        std::cerr << "string" << endl;                        
                        uint        val_length;
//    std::cout << "@c #4" << std::endl;
                        std::cerr << "\t\t\t\tTRY STR ";
                        const char  *val = mp_decode_str(&ptr, &val_length);

//    std::cout << "@c #5" << std::endl;

                        Resource    rr;
                        rr.type = _String;
                        std::string value(val, val_length);
                        std::cerr << value << endl;
                        
                        rr.str_data = value;
                        rr.lang     = LANG_NONE;
                        resources.push_back(rr);*/
                    }
                    else
                    {
                        return -1;
                    }
                }
                else if (predicate_el_length == 3)
                {
                    long type;
                    // std::cerr << predicate_el_length << endl;

                    // std::cerr << "\t\t\tDECODE UINT type is ";
                    if (mp_typeof(*ptr) == MP_UINT)
                        type = mp_decode_uint(&ptr);
                    else
                        type = mp_decode_int(&ptr);

                    if (type == _Decimal)
                    {
                        long mantissa, exponent;
                        // std::cerr << "is decimal" << endl << "\t\t\t\tTRY MANTISSA";
                        if (mp_typeof(*ptr) == MP_UINT)
                            mantissa = mp_decode_uint(&ptr);
                        else
                            mantissa = mp_decode_int(&ptr);
                        // std::cerr << mantissa << endl << "\t\t\t\tTRY EXP";
                        if (mp_typeof(*ptr) == MP_UINT)
                            exponent = mp_decode_uint(&ptr);
                        else
                            exponent = mp_decode_int(&ptr);
                        // std::cerr << exponent << endl;

                        Resource rr;
                        rr.type                  = _Decimal;
                        rr.decimal_mantissa_data = mantissa;
                        rr.decimal_expanent_data = exponent;
                        resources.push_back(rr);
                    }
                    else if (type == _String)
                    {
                        Resource    rr;
                        std::string value;
                        
                        rr.type = _String;
                        if (mp_typeof(*ptr) != MP_NIL) {
                            uint        val_length;                
                            const char  *val = mp_decode_str(&ptr, &val_length);                
                            value = string(val, val_length);
                        } else {
                            value = string("", 0);
                            mp_decode_nil(&ptr);
                        }
            
                        long lang = mp_decode_uint(&ptr);
                        rr.lang     = lang;
                        rr.str_data = value;
                        resources.push_back(rr);

/*                        uint        val_length;
//    std::cout << "@c #6" << std::endl;
                        const char  *val = mp_decode_str(&ptr, &val_length);

//    std::cout << "@c #7" << std::endl;
                        long        lang = mp_decode_uint(&ptr);

                        Resource    rr;
                        rr.type = _String;
                        std::string value(val, val_length);
                        rr.str_data = value;
                        rr.lang     = lang;
                        resources.push_back(rr);*/
                    }
                    else
                    {
                        return -1;
                    }
                }
                else
                {
                    return -1;
                }
            }
            else if (el_type == MP_STR)
            {
                Resource    rr;
                std::string value;

                // std::cerr << "is string" << endl;                

                rr.type = _Uri;
                
                if (mp_typeof(*ptr) != MP_NIL) {
                    uint        val_length;                
                    const char  *val = mp_decode_str(&ptr, &val_length);                
                    value = string(val, val_length);
                } else {
                    value = string("", 0);
                    mp_decode_nil(&ptr);
                }
    

                rr.str_data = value;
                resources.push_back(rr);
                
                /*std::cerr << "is string" << endl;                
                // this uri
                uint        val_length;
//    std::cout << "@c #8" << std::endl;
                const char  *val = mp_decode_str(&ptr, &val_length);
//    std::cout << "@c #9" << std::endl;

                Resource    rr;
                rr.type = _Uri;
                std::string value(val, val_length);
                rr.str_data = value;
                resources.push_back(rr);*/
            }
            else if (el_type == MP_INT || el_type == MP_UINT)
            {
                // std::cerr << "is int or uint" << endl;
                // this uint32_t
                long value;
                if (mp_typeof(*ptr) == MP_UINT)
                    value = mp_decode_uint(&ptr);
                else
                    value = mp_decode_int(&ptr);
                Resource rr;
                rr.type      = _Integer;
                rr.long_data = value;
                resources.push_back(rr);
            }
            else if (el_type == MP_BOOL)
            {
                // std::cerr << "is bool" << endl;                
                // this bool
                long     value = mp_decode_bool(&ptr);

                Resource rr;
                rr.type      = _Boolean;
                rr.bool_data = value;
                resources.push_back(rr);
            }
            else
            {
                return -1;
            }
        }
        individual->resources[ predicate ] = resources;
    }

//    std::cout << "@c #e" << std::endl;

    return (int32_t)(ptr - in_ptr);
}

int32_t individual2msgpack(Individual *individual, char *in_buff)
{
    return write_individual(individual, in_buff);
}

