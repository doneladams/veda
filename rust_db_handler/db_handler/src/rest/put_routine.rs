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

impl Resource {
    pub fn new() -> Resource {
        return Resource { res_type: ResourceType::Uri, lang: Lang::LangNone, str_data: Vec::default(),
            bool_data: false, long_data: 0, decimal_mantissa_data: 0, decimal_exponent_data: 0};
    }
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
        Err(err) => return Err(format!("@ERR DECODING INDIVIDUAL URI {0}", err)),
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
        let mut resources: Vec<Resource> = Vec::new();

        match decode::decode_string(cursor, &mut key) {
            Err(err) => return Err(format!("@ERR DECODING INDIVIDUAL URI {0}", err)),
            Ok(_) => {}
        }
        writeln!(stderr(), "@RESOURCE KEY {0}", std::str::from_utf8(&key[..]).unwrap()).unwrap();
        
        let mut res_size: u64;
        match decode::decode_array(cursor) {
            Ok(rs) => res_size = rs,
            Err(err) => return Err(format!("@ERR DECODING RESOURCES ARRAY {0}", err))
        }

        writeln!(stderr(), "@RESOURCE ARRAY LEN {0}", res_size);
        for j in 0.. res_size {
            let mut objtype: decode::Type;
            match decode::decode_type(cursor) {
                Ok(t) => objtype = t,
                Err(err) => return Err(format!("@ERR DECODING RESOURCE TYPE {0}", err))
            }

            match objtype {
                decode::Type::ArrayObj => {
                    let res_arr_size = decode::decode_array(cursor).unwrap();
                    writeln!(stderr(), "@DECODE RES ARR 2").unwrap();
                    let mut res_type: u64;
                    match decode::decode_uint(cursor) {
                        Ok(rt) => res_type = rt,
                        Err(err) => return Err(format!("@ERR DECODING RESOURCE TYPE {0}", err))
                    }
                    writeln!(stderr(), "@RES TYPE {0}", res_type);
                    if res_arr_size == 2 {
                        if res_type == ResourceType::Datetime as u64 {
                            let mut datetime: u64;
                            match decode::decode_uint(cursor) {
                                Ok(dt) => datetime = dt,
                                Err(err) => return Err(format!("@ERR DECODING DATETIME {0}", err))
                            }
                            writeln!(stderr(), "@DATETIME {0}", datetime);
                            let mut resource = Resource::new();
                            resource.res_type = ResourceType::Datetime;
                            resource.long_data = datetime as i64;
                            resources.push(resource);
                        } else if res_type == ResourceType::Str as u64 {
                            let mut resource = Resource::new();
                            
                            let mut decode_type: decode::Type;
                            match decode::decode_type(cursor) {
                                Ok(dt) => decode_type = dt,
                                Err(err) => return Err(format!("@ERR DECODING STRING RES TYPE {0}", err))
                            }

                            match decode_type {
                                decode::Type::StringObj => 
                                    decode::decode_string(cursor, &mut resource.str_data).unwrap(),
                                decode::Type::NilObj => {},
                                _ => return Err("@UNKNOWN TYPE IN STRING RESOURCE".to_string())
                            }
                            resource.lang = Lang::LangNone;
                            writeln!(stderr(), "@STR DATA {0}", std::str::from_utf8(
                                    &resource.str_data[..]).unwrap()).unwrap();
                            resources.push(resource);
                        } else {
                            return Err("@UNKNOWN RESOURCE TYPE".to_string());
                        }
                    } else if res_arr_size == 3 {
                        /*
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
                        } */                       
                    }
                }
                _ => {}
            }
        }

        
/*  msgpack::object_kv pair = map.ptr[i];
       
        

        for (int j = 0; j < res_objs.size; j++) {
            msgpack::object value = res_objs.ptr[j];
            
            switch (value.type) {

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
