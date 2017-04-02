#include "individual.h"

bool Resource::operator== (Resource &res) {
    if (this->type != res.type)
        return false;
    
    switch (this->type) {
        case _Uri: {
            if (this->str_data == res.str_data)
                return true;
            break;
        } 
        case  _String: {
            if (this->str_data == res.str_data && this->lang == lang)
                return true;
            break;
        }
        case _Integer: {
            if (this->long_data == res.long_data)
                return true;
            break;
        }
        case _Datetime: {
            if (this->long_data == res.long_data)
                return true;
            break;
        }
        case _Decimal: {
            if (this->decimal_mantissa_data == res.decimal_mantissa_data &&
                this->decimal_exponent_data == res.decimal_exponent_data)
                return true;
            break;
        }
        case _Boolean: {
            if (this->bool_data == res.bool_data)
                return true;
        }
        default: {
            cout << "@ERR LISTENER! UNKNOWN RESOURCE TYPE " << this->type << endl;
            return false;
        }
    }

    return false;
}

int32_t 
msgpack_to_individual(Individual *individual, const char *ptr, uint32_t len)
{
    msgpack::unpacker unpk;    

    unpk.reserve_buffer(len);
    memcpy(unpk.buffer(), ptr, len);
    unpk.buffer_consumed(len);
    msgpack::object_handle result;
    unpk.next(result);
    msgpack::object glob_obj(result.get()); 
    msgpack::object_array obj_arr = glob_obj.via.array;

    if (obj_arr.size != 2) {
        cerr << "@ERR DECODING! INVALID ROOT ARR SIZE " << obj_arr.size << endl;
        cerr << ptr << endl;
        cerr << obj_arr.ptr[0].via.str.ptr << endl;        
        return -1;
    }
    
    msgpack::object *obj_uri = obj_arr.ptr;
    msgpack::object *obj_map = obj_arr.ptr + 1;
    
    individual->uri = string(obj_uri->via.str.ptr, obj_uri->via.str.size);
    
    msgpack::object_map map = obj_map->via.map;
    
    for (int i = 0; i < map.size; i++ ) {
        msgpack::object_kv pair = map.ptr[i];
        msgpack::object key = pair.key;
        msgpack::object_array res_objs = pair.val.via.array;
        if (key.type != msgpack::type::STR) {
            std::cerr << "@ERR! PREDICATE IS NOT STRING!" << endl;
            return -1;
        }

        std::string predicate(key.via.str.ptr, key.via.str.size);
        vector <Resource> resources;
        

        for (int j = 0; j < res_objs.size; j++) {
            msgpack::object value = res_objs.ptr[j];
            
            switch (value.type) {
                case msgpack::type::ARRAY: {
                    msgpack::object_array res_arr = value.via.array;
                    if (res_arr.size == 2) {
                        long type = res_arr.ptr[0].via.u64;

                        if (type == _Datetime) {
                            Resource rr;
                            rr.type      = _Datetime;
                            if (res_arr.ptr[1].type == msgpack::type::POSITIVE_INTEGER)
                                rr.long_data = res_arr.ptr[1].via.u64;
                            else
                                rr.long_data = res_arr.ptr[1].via.i64;
                                
                            resources.push_back(rr);
                        }
                        else if (type == _String) {
                            Resource    rr;

                            rr.type = _String;
                            
                            if (res_arr.ptr[1].type == msgpack::type::STR)
                                rr.str_data = string(res_arr.ptr[1].via.str.ptr, 
                                    res_arr.ptr[1].via.str.size);
                            else if (res_arr.ptr[1].type == msgpack::type::NIL)
                                rr.str_data = "";
                            else {
                                std::cerr << "@ERR! NOT A STRING IN RESOURCE ARRAY 2" << endl;
                                return -1;
                            }

                            rr.lang = LANG_NONE;
                            resources.push_back(rr);
                        }
                        else {
                            std::cerr << "@1" << endl;
                            return -1;
                        }
                    } else if (res_arr.size == 3) {
                        long type = res_arr.ptr[0].via.u64;
                        if (type == _Decimal) {
                            long mantissa, exponent;
                            if (res_arr.ptr[1].type == msgpack::type::POSITIVE_INTEGER)
                                mantissa = res_arr.ptr[1].via.u64;
                            else
                                mantissa = res_arr.ptr[1].via.i64;
                            if (res_arr.ptr[2].type == msgpack::type::POSITIVE_INTEGER)
                                exponent = res_arr.ptr[2].via.u64;
                            else
                                exponent = res_arr.ptr[2].via.i64;

                            Resource rr;
                            rr.type                  = _Decimal;
                            rr.decimal_mantissa_data = mantissa;
                            rr.decimal_exponent_data = exponent;
                            resources.push_back(rr);
                        }
                        else if (type == _String) {
                            Resource    rr;
                            
                            rr.type = _String;
                            if (res_arr.ptr[1].type == msgpack::type::STR)
                                rr.str_data = string(res_arr.ptr[1].via.str.ptr, 
                                    res_arr.ptr[1].via.str.size);
                            else if (res_arr.ptr[1].type == msgpack::type::NIL)
                                rr.str_data = "";
                            else {
                                std::cerr << "@ERR! NOT A STRING IN RESOURCE ARRAY 2" << endl;
                                return -1;
                            }
                
                            long lang = res_arr.ptr[2].via.u64;
                            rr.lang     = lang;
                            resources.push_back(rr);

                        } else {
                            std::cerr << "@2" << endl;
                            return -1;
                        }
                    }
                    else {
                        std::cerr << "@3" << endl;
                        return -1;
                    }
                    break;
                }

                case msgpack::type::STR: {
                    Resource    rr;
                    rr.type = _Uri;
                    rr.str_data = string(string(value.via.str.ptr, value.via.str.size));
                    resources.push_back(rr);
                    break;
                }

                case msgpack::type::POSITIVE_INTEGER: {
                    Resource rr;
                    rr.type      = _Integer;
                    rr.long_data = value.via.u64;
                    resources.push_back(rr);
                    break;
                }

                case msgpack::type::NEGATIVE_INTEGER: {
                    Resource rr;
                    rr.type      = _Integer;
                    rr.long_data = value.via.i64;
                    resources.push_back(rr);
                    break;
                }       

                case msgpack::type::BOOLEAN: {
                    Resource rr;
                    rr.type      = _Boolean;
                    rr.bool_data = value.via.boolean;
                    resources.push_back(rr);
                    break;
                } 

                default: {
                    cerr << "@ERR! UNSUPPORTED RESOURCE TYPE " << value.type << endl;
                    return -1;  
                }  
            }
        }

        individual->resources[ predicate ] = resources;        
    }

    return 0;
}