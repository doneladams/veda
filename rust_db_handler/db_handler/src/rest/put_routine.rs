extern crate core;
extern crate rmp_bind;

use std;
use std::collections::HashMap;
use std::cmp::Eq;
use std::ffi::{ CString, CStr };
use std::io::{ Write, stderr, Cursor };
use std::os::raw::c_char;
use std::ptr::null_mut;
use rmp_bind:: { decode, encode };

include!("../../module.rs");

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
pub struct Resource {
    res_type: ResourceType,
    lang: Lang,
    pub str_data: Vec<u8>,
    bool_data: bool,
    long_data: i64,
    decimal_mantissa_data: i64,
    decimal_exponent_data: i64,
}

pub struct Individual {
    pub uri: Vec<u8>,
    pub resources: HashMap<String, Vec<Resource>>    
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

impl Lang {
    fn from_u64(val: u64) -> Lang {
        match val {
            1 => Lang::LangRu,
            2 => Lang::LangEn,
            _ => Lang::LangNone
        }
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

    // writeln!(stderr(), "@INDIVIDUAL URI {0}", std::str::from_utf8(&individual.uri[..]).unwrap()).unwrap();

    let mut map_size: u64;
    match decode::decode_map(cursor) {
        Err(err) => return Err(format!("@ERR DECODING INDIVIDUAL MAP {0}", err)),
        Ok(size) => map_size = size
    }

    // writeln!(stderr(), "@MAP LEN {0}", map_size);

    for i in 0..map_size {
        let mut key: Vec<u8> = Vec::default();
        let mut resources: Vec<Resource> = Vec::new();

        match decode::decode_string(cursor, &mut key) {
            Err(err) => return Err(format!("@ERR DECODING INDIVIDUAL URI {0}", err)),
            Ok(_) => {}
        }
        // writeln!(stderr(), "@RESOURCE KEY {0}", std::str::from_utf8(&key[..]).unwrap()).unwrap();
        
        let mut res_size: u64;
        match decode::decode_array(cursor) {
            Ok(rs) => res_size = rs,
            Err(err) => return Err(format!("@ERR DECODING RESOURCES ARRAY {0}", err))
        }

        // writeln!(stderr(), "@RESOURCE ARRAY LEN {0}", res_size);
        for j in 0.. res_size {
            let mut objtype: decode::Type;
            match decode::decode_type(cursor) {
                Ok(t) => objtype = t,
                Err(err) => return Err(format!("@ERR DECODING RESOURCE TYPE {0}", err))
            }

            match objtype {
                decode::Type::ArrayObj => {
                    let res_arr_size = decode::decode_array(cursor).unwrap();
                    // writeln!(stderr(), "@DECODE RES ARR 2").unwrap();
                    let mut res_type: u64;
                    match decode::decode_uint(cursor) {
                        Ok(rt) => res_type = rt,
                        Err(err) => return Err(format!("@ERR DECODING RESOURCE TYPE {0}", err))
                    }
                    // writeln!(stderr(), "@RES TYPE {0}", res_type);
                    if res_arr_size == 2 {
                        if res_type == ResourceType::Datetime as u64 {
                            let mut datetime: u64;
                            match decode::decode_uint(cursor) {
                                Ok(dt) => datetime = dt,
                                Err(err) => return Err(format!("@ERR DECODING DATETIME {0}", err))
                            }
                            // writeln!(stderr(), "@DATETIME {0}", datetime);
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
                                decode::Type::StrObj => 
                                    decode::decode_string(cursor, &mut resource.str_data).unwrap(),
                                decode::Type::NilObj => {},
                                _ => return Err("@UNKNOWN TYPE IN STRING RESOURCE".to_string())
                            }
                            resource.lang = Lang::LangNone;
                            // writeln!(stderr(), "@STR DATA {0}", std::str::from_utf8(
                                    // &resource.str_data[..]).unwrap()).unwrap();
                            resources.push(resource);
                        } else {
                            return Err("@UNKNOWN RESOURCE TYPE".to_string());
                        }
                    } else if res_arr_size == 3 {
                        // writeln!(stderr(), "@DECODE RES ARR 3").unwrap();
                        if res_type == ResourceType::Decimal as u64 {
                            let mut resource = Resource::new();
                            
                            let mut decode_type: decode::Type;  
                            match decode::decode_type(cursor) {
                                Ok(dt) => decode_type = dt,
                                Err(err) => return Err(format!("@ERR DECODEING MANTISSA TYPE {0}", err))
                            }

                            match decode_type {
                                decode::Type::UintObj => {
                                    resource.decimal_mantissa_data = decode::decode_uint(cursor).unwrap() as i64;
                                },
                                decode::Type::IntObj => {
                                    resource.decimal_mantissa_data = decode::decode_int(cursor).unwrap();
                                },
                                _ => return Err("@ERR UNSUPPORTED MANTISSA TYPE".to_string())
                            }
  
                            match decode::decode_type(cursor) {
                                Ok(dt) => decode_type = dt,
                                Err(err) => return Err(format!("@ERR DECODEING MANTISSA TYPE {0}", err))
                            }

                            match decode_type {
                                decode::Type::UintObj => {
                                    resource.decimal_exponent_data = decode::decode_uint(cursor).unwrap() as i64;
                                },
                                decode::Type::IntObj => {
                                    resource.decimal_exponent_data = decode::decode_int(cursor).unwrap();
                                },
                                _ => return Err("@ERR UNSUPPORTED EXPONENT TYPE".to_string())
                            }

                            resource.res_type = ResourceType::Decimal;
                            resources.push(resource);
                        } else if res_type == ResourceType::Str as u64 {
                            let mut resource = Resource::new();

                            let mut decode_type: decode::Type;
                            match decode::decode_type(cursor) {
                                Ok(dt) => decode_type = dt,
                                Err(err) => return Err(format!("@ERR DECODING STRING RES TYPE {0}", err))
                            }

                            match decode_type {
                                decode::Type::StrObj => 
                                    decode::decode_string(cursor, &mut resource.str_data).unwrap(),
                                decode::Type::NilObj => {},
                                _ => return Err("@UNKNOWN TYPE IN STRING RESOURCE".to_string())
                            }

                            match decode::decode_uint(cursor) {
                                Ok(l) => resource.lang = Lang::from_u64(l),
                                Err(err) => return Err(format!("@ERR DECODING LEN {0}", err))
                            }
                            resource.res_type = ResourceType::Str;
                            resources.push(resource);
                        }                     
                    }
                }
                decode::Type::StrObj => {
                    // writeln!(stderr(), "@DECODE STROBJ RESOURCE").unwrap();
                    let mut resource = Resource::new();
                    decode::decode_string(cursor, &mut resource.str_data).unwrap();
                    resource.res_type = ResourceType::Uri;
                    resources.push(resource);
                }
                decode::Type::UintObj => {
                    // writeln!(stderr(), "@DECODE UINTOBJ RESOURCE").unwrap();
                    let mut resource = Resource::new();
                    resource.long_data = decode::decode_uint(cursor).unwrap() as i64;
                    resource.res_type = ResourceType::Integer;
                    resources.push(resource);
                }
                decode::Type::IntObj => {
                    // writeln!(stderr(), "@DECODE INTOBJ RESOURCE");
                    let mut resource = Resource::new();
                    resource.long_data = decode::decode_int(cursor).unwrap();
                    resource.res_type = ResourceType::Integer;
                    resources.push(resource);
                }
                decode::Type::BoolObj => {
                    // writeln!(stderr(), "@DECODE BOOLOBJ RESOURCE");
                    let mut resource = Resource::new();
                    resource.bool_data = decode::decode_bool(cursor).unwrap();
                    resource.res_type = ResourceType::Boolean;
                    resources.push(resource);
                }
               _ => return Err("@UNSUPPORTED RESOURCE TYPE".to_string())
            }
        }

        individual.resources.insert(std::str::from_utf8(key.as_ref()).unwrap().to_string(), resources);
    }
    return Ok(());
}

pub fn get_rdf_types(uri: &Vec<u8>, rdf_types: &mut Vec<Vec<u8>>, conn: &super::TarantoolConnection) 
    -> Result<(), String> {
    writeln!(stderr(), "@TRY GET RDF TYPES");
    let mut request = Vec::new();

    encode::encode_array(&mut request, 1);
    writeln!(stderr(), "@REQ LEN {0}", request.len()).unwrap();
    encode::encode_string(&mut request, &std::str::from_utf8(uri).unwrap());
    writeln!(stderr(), "@REQ LEN1 {0}", request.len()).unwrap();
    unsafe {
        let request_len = request.len() as isize;
        let key_ptr_start = request[..].as_ptr() as *const i8;
        let key_ptr_end = key_ptr_start.offset(request_len);

        let mut get_result: *mut BoxTuple = null_mut();
        let get_code = box_index_get(conn.rdf_types_space_id, conn.rdf_types_index_id,
           key_ptr_start, key_ptr_end, &mut get_result as *mut *mut BoxTuple);
       
        if get_code < 0 {
            writeln!(stderr(), "{0}",
                CStr::from_ptr(box_error_message(box_error_last())).to_str().unwrap().to_string());
            return Err("@ERR READING RDF TYPES".to_string());
        } else if get_result != null_mut() {
            writeln!(stderr(), "@GET RDF TYPES");
            let tuple_size = box_tuple_bsize(get_result);
            let mut tuple_buf: Vec<u8> = vec![0; tuple_size];
            box_tuple_to_buf(get_result, tuple_buf.as_mut_ptr() as *mut c_char, tuple_size);
            let mut uri: Vec<u8> = Vec::default();
            let mut cursor: Cursor<&[u8]> = Cursor::new(&tuple_buf[..]);
            let arr_size = decode::decode_array(&mut cursor).unwrap();
            decode::decode_string(&mut cursor, &mut uri).unwrap();
            writeln!(stderr(), "@RDF TYPE URI {0}", std::str::from_utf8(&uri[..]).unwrap());
            for i in 1 .. arr_size {
                let mut buf: Vec<u8> = Vec::default();
                decode::decode_string(&mut cursor, &mut buf);
                rdf_types.push(buf);
            }
            
        }
    }

    writeln!(stderr(), "@RETURN RDF TYPES");
    return Ok(());
}

pub fn put_rdf_types(uri: &Vec<u8>, rdf_types: &Vec<Resource>, conn: &super::TarantoolConnection) {
    let mut request = Vec::new();
    encode::encode_array(&mut request, rdf_types.len() as u32 + 1);
    writeln!(stderr(), "@ENCODE URI {0}", std::str::from_utf8(uri.as_ref()).unwrap());
    encode::encode_string_bytes(&mut request, &uri);
    for i in 0 .. rdf_types.len() {
        encode::encode_string_bytes(&mut request, &rdf_types[i].str_data);
        writeln!(stderr(), "@ENCODE RDF TYPE {0}", std::str::from_utf8(&rdf_types[i].str_data.as_ref()).unwrap());
    }

    unsafe {
        let request_len = request.len() as isize;
        writeln!(stderr(), "@REPLACE REQ LEN {0}", request_len);
        let key_ptr_start = request[..].as_ptr() as *const i8;
        let key_ptr_end = key_ptr_start.offset(request_len);
        writeln!(stderr(), "@TRY REPLACE RDF TYPES");
        let replace_code = box_replace(conn.rdf_types_space_id, key_ptr_start, key_ptr_end, 
            &mut null_mut() as *mut *mut BoxTuple);
        if replace_code < 0 {
            writeln!(stderr(), "{0}",
                CStr::from_ptr(box_error_message(box_error_last())).to_str().unwrap().to_string());
        }
        writeln!(stderr(), "@REPLACE CODE {0}", replace_code);
    }
}