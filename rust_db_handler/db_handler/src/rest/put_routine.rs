extern crate core;
extern crate rmp_bind;

use std;
use std::collections::HashMap;
use std::cmp::Eq;
use std::io::{ Write, stderr, Cursor };
use rmp_bind:: { decode, encode };

#[derive(PartialEq, Eq)]
enum ResourceType {
    Uri = 1,
    Str = 2,
    Integer = 4,
    Datetime = 8,
    Decimal = 32,
    Boolean = 64
}

#[derive(PartialEq, Eq)]
enum Lang {
    LangNone = 0,
    LangRu  = 1,
    LangEn   = 2
}

#[derive(PartialEq, Eq)]
struct Resource {
    res_type: ResourceType,
    lang: Lang,
    str_data: Vec<u8>,
    bool_data: bool,
    long_data: i64,
    decimal_mantissa_data: i64,
    decimal_exponent_data: i64,
}

pub struct Individual {
    uri: Vec<u8>,
    resources: HashMap<String, Vec<Resource>>    
}

impl Individual {
    pub fn new() -> Individual {
        return Individual { uri: Vec::default(), resources: HashMap::new() };
    }
}

fn resources_equeal(r1: &Resource, r2: &Resource) -> bool {
    if r1.res_type != r2.res_type {
        return false;
    }

    match r1.res_type {
        ResourceType::Uri => {
            if r1.str_data == r2.str_data { 
                return true; 
            }
        },
        ResourceType::Str => { 
            if r1.str_data == r2.str_data && r1.lang == r2.lang { 
                return true; 
            }
        },
        ResourceType::Integer | ResourceType::Datetime => { 
            if r1.long_data == r2.long_data { 
                return true 
            }
        },
        ResourceType::Decimal => {
            if r1.decimal_exponent_data == r2.decimal_exponent_data &&
                r1.decimal_mantissa_data == r2.decimal_mantissa_data { 
                return true 
            }
        },
        ResourceType::Boolean => { 
            if r1.bool_data == r2.bool_data {
                return true;
            }
        },
    }

   return false;
}

pub fn test() {

}

pub fn msgpack_to_individual(cursor: &mut Cursor<&[u8]>, individual: &mut Individual) -> Result<(), String> {
    let mut arr_size: u64;
    match decode::decode_array(cursor) {
        Err(err) => return Err(format!("@ERR DECODING INDIVIDUAL MSGPACK ARRAY {0}", err)),
        Ok(size) => arr_size = size
    }

    if arr_size != 2 {
        return Err("@ERR INVALID INDIVIDUAL MSGPACK SIZE".to_string());    
    }

    match decode::decode_string(cursor, &mut individual.uri) {
        Err(err) => writeln!(stderr(), "@ERR DECODING INDIVIDUAL URI {0}", err).unwrap(),
        Ok(_) => {}
    }

    writeln!(stderr(), "@INDIVIDUAL URI {0}", std::str::from_utf8(&individual.uri[..]).unwrap()).unwrap();

    let mut map_size: u64;
    match decode::decode_map(cursor) {
        Err(err) => return Err(format!("@ERR DECODING INDIVIDUAL MAP {0}", err)),
        Ok(size) => map_size = size
    }

    writeln!(stderr(), "@MAP LEN {0}", map_size);

    for i in 0..map_size {
        let mut key: Vec<u8> = Vec::default();
        match decode::decode_string(cursor, &mut key) {
            Err(err) => writeln!(stderr(), "@ERR DECODING INDIVIDUAL URI {0}", err).unwrap(),
            Ok(_) => {}
        }
        writeln!(stderr(), "@RESOURCE KEY {0}", std::str::from_utf8(&key[..]).unwrap()).unwrap();
/*  msgpack::object_kv pair = map.ptr[i];
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

        individual->resources[ predicate ] = resources;     */   
    }

/*
    
   
    
    for (int i = 0; i < map.size; i++ ) {
       
    }

    return 0;*/

    return Ok(());
}
