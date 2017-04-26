extern crate core;
extern crate rmp_bind;

mod authorization;
mod put_routine;

use std;
use std::ffi::{ CString, CStr };
use std::io::{ Write, stderr, Cursor };
use std::os::raw::c_char;
use std::ptr::null_mut;
use rmp_bind::{ encode, decode };

include!("../../module.rs");

pub enum Codes {
    Ok = 200,
    BadRequest = 400,
    NotAuthorized = 472,
    NotFound = 404,
    InternalServerError = 500
}

#[derive(Default)]
pub struct TarantoolConnection {
    acl_space_id: u32,
    acl_index_id: u32,
    individuals_space_id: u32,
    individuals_index_id: u32,
    rdf_types_space_id: u32,
    rdf_types_index_id: u32
}

fn connect_to_tarantool() -> Result<TarantoolConnection, String> {
    let mut conn: TarantoolConnection = Default::default();
    unsafe {
        conn.individuals_space_id = box_space_id_by_name(CString::new("individuals").unwrap().as_ptr(), 
            "individuals".len() as u32);
        if conn.acl_space_id == BOX_ID_NIL {
            return Err("@ERR NO SPACE individuals".to_string());
        }
        
        conn.individuals_index_id = box_index_id_by_name(conn.individuals_space_id, 
            CString::new("primary").unwrap().as_ptr(), 
            "primary".len() as u32);
        if conn.acl_index_id == BOX_ID_NIL {
            return Err("@ERR NO INDEX primary IN individuals".to_string());
        }

        conn.acl_space_id = box_space_id_by_name(CString::new("acl").unwrap().as_ptr(), "acl".len() as u32);
        if conn.acl_space_id == BOX_ID_NIL {
            return Err("@ERR NO SPACE acl".to_string());
        }
        
        conn.acl_index_id = box_index_id_by_name(conn.acl_space_id, CString::new("primary").unwrap().as_ptr(), 
            "primary".len() as u32);
        if conn.acl_index_id == BOX_ID_NIL {
            return Err("@ERR NO INDEX primary IN acl".to_string());
        }

        conn.rdf_types_space_id = box_space_id_by_name(CString::new("rdf_types").unwrap().as_ptr(), 
            "rdf_types".len() as u32);
        if conn.acl_space_id == BOX_ID_NIL {
            return Err("@ERR NO SPACE rdf_types".to_string());
        }
        
        conn.rdf_types_index_id = box_index_id_by_name(conn.rdf_types_space_id, 
            CString::new("primary").unwrap().as_ptr(), "primary".len() as u32);
        if conn.acl_index_id == BOX_ID_NIL {
            return Err("@ERR NO INDEX primary IN rdf_types".to_string());
        }

        return Ok(conn);
    }
}

pub fn put(cursor: &mut Cursor<&[u8]>, arr_size: u64, need_auth:bool, resp_msg: &mut Vec<u8>) {
    writeln!(stderr(), "@PUT").unwrap();
    let mut conn: TarantoolConnection;

    match connect_to_tarantool() {
        Err(err) => return super::fail(resp_msg, Codes::InternalServerError, err),
        Ok(c) => conn = c
    }

    let mut user_id_buf = Vec::default();
    let mut user_id: &str;
    match decode::decode_string(cursor, &mut user_id_buf) {
        Err(err) => return super::fail(resp_msg, Codes::InternalServerError, err),
        Ok(_) => {}
    }

    encode::encode_array(resp_msg, (arr_size - 3 + 1) as u32);
    encode::encode_uint(resp_msg, Codes::Ok as u64);
    for i in 3 .. arr_size {
        let mut individual_msgpack_buf = Vec::default();    
        let individual_msgpack: &str;

        match decode::decode_string(cursor, &mut individual_msgpack_buf) {
            Err(err) => return super::fail(resp_msg, Codes::InternalServerError, err),
            Ok(_) => user_id = std::str::from_utf8(&user_id_buf).unwrap()
        }

        let mut individual = put_routine::Individual::new();
        match put_routine::msgpack_to_individual(&mut Cursor::new(&individual_msgpack_buf[..]), &mut individual) {
            Ok(_) => {}
            Err(err) => {
                writeln!(stderr(), "@ERR DECODING INDIVIDUAL {0}", err);
                encode::encode_uint(resp_msg, Codes::InternalServerError as u64);
            }
        }
        writeln!(stderr(), "@DECODING DONE");
        let mut new_state_res: &Vec<put_routine::Resource>;
        match individual.resources.get(&"new_state".to_string()) {
            Some(res) => new_state_res = res,
            _ => {
                writeln!(stderr(), "@NO NEW_STATE FOUND");
                encode::encode_uint(resp_msg, Codes::InternalServerError as u64);
                return;
            }
        }

        writeln!(stderr(), "@CONTAINS NEW_STATE");
        let mut new_state = put_routine::Individual::new();
        match put_routine::msgpack_to_individual(&mut Cursor::new(&new_state_res[0].str_data[..]), 
            &mut new_state) {
            Ok(_) => {}
            Err(err) => {
                writeln!(stderr(), "@ERR DECODING INDIVIDUAL {0}", err);
                encode::encode_uint(resp_msg, Codes::BadRequest as u64);
            }
        }
        writeln!(stderr(), "@DECODED NEW STATE");
        let mut rdf_types: &Vec<put_routine::Resource>;
        match new_state.resources.get(&"rdf:type".to_string()) {
            Some(res) => rdf_types = res,
            _ => {
                writeln!(stderr(), "@NO RDF_TYPE_FOUND FOUND");
                encode::encode_uint(resp_msg, Codes::BadRequest as u64);
                return;
            }
        }

        writeln!(stderr(), "@RDF:TYPE FOUND");
        let mut tnt_rdf_types: Vec<Vec<u8>> = Vec::default();
        match put_routine::get_rdf_types(&new_state.uri, &mut tnt_rdf_types, &conn) {
            Ok(_) => {}
            Err(err) => {
                writeln!(stderr(), "@ERR READING RDF:TYPE IN TARANTOOL {0}", err);
                encode::encode_uint(resp_msg, Codes::InternalServerError as u64);
            }
        }

        writeln!(stderr(), "@TNT RDF:TYPE LEN {0}", tnt_rdf_types.len());
        let mut is_update: bool = true;
        if (tnt_rdf_types.len() > 0 && need_auth) {
            /*vector<string>::iterator it;
            for (int i = 0; i < rdf_type.size(); i++) {
                it = find(tnt_rdf_types.begin(), tnt_rdf_types.end(), rdf_type[i].str_data);
                if (it == tnt_rdf_types.end()) {
                    is_update = false;
                    auth_result = db_auth(user_id.ptr, user_id.size, rdf_type[i].str_data.c_str(), 
                        rdf_type[i].str_data.size());
                    if (auth_result < 0) {
                        return INTERNAL_SERVER_ERROR;
                    }
                    if (!(auth_result & ACCESS_CAN_CREATE)) {
                        delete new_state;
                        return NOT_AUTHORIZED;
                    }
                }
            }*/
        } else {
            is_update = false;
        }

        if (is_update && need_auth) {
            let mut auth_result: u8;
            match authorization::compute_access(user_id, 
                &std::str::from_utf8(&new_state.uri[..]).unwrap(), &conn) {
                Err(err) => {
                    writeln!(stderr(), "@ERR UN UPDATE AUTH {0}", err).unwrap();
                    encode::encode_uint(resp_msg, Codes::InternalServerError as u64);
                    return;
                }
                Ok(ac) => auth_result = ac
            }

            if (auth_result & authorization::ACCESS_CAN_UPDATE == 0) {
                writeln!(stderr(), "@NOT AUTH UPDATE");
                encode::encode_uint(resp_msg, Codes::NotAuthorized as u64);
            }
        }

        writeln!(stderr(), "@CHECKED RIGHTS");  
        if (!is_update) {
            put_routine::put_rdf_types(&new_state.uri, rdf_types, &conn);
        }
/*
        if (!is_update)
            put_rdf_types(new_state->uri, rdf_type);
            
        
        if (box_replace(individuals_space_id, tmp_ptr, tmp_ptr + tmp_len, NULL) < 0) {
            delete new_state;
            cerr << "@ERR REST: ERR ON INSERTING MSGPACK" << endl;
            return INTERNAL_SERVER_ERROR;
        }

        */
        encode::encode_uint(resp_msg, Codes::NotAuthorized as u64)
    }
}


pub fn get(cursor: &mut Cursor<&[u8]>, arr_size: u64, need_auth:bool, resp_msg: &mut Vec<u8>) {
    writeln!(stderr(), "@GET").unwrap();
    let mut conn: TarantoolConnection;

    match connect_to_tarantool() {
        Err(err) => return super::fail(resp_msg, Codes::InternalServerError, err),
        Ok(c) => conn = c
    }

    let mut user_id_buf = Vec::default();
    let user_id: &str;
    
    match decode::decode_string(cursor, &mut user_id_buf) {
        Err(err) => return super::fail(resp_msg, Codes::InternalServerError, err),
        Ok(_) => user_id = std::str::from_utf8(&user_id_buf).unwrap()
    }

    writeln!(stderr(), "@USER ID {0}", user_id);
    
    encode::encode_array(resp_msg, ((arr_size - 3) * 2 + 1) as u32);
    encode::encode_uint(resp_msg, Codes::Ok as u64);
    
    for i in 3 .. arr_size {
        let mut res_uri_buf = Vec::default();    
        let res_uri: &str;
        let mut request = Vec::new();


        match decode::decode_string(cursor, &mut res_uri_buf) {
            Err(err) => { super::fail(resp_msg, Codes::InternalServerError, err); continue; },
            Ok(_) => res_uri = std::str::from_utf8(&res_uri_buf).unwrap()
        }

        writeln!(stderr(), "@RES URI {0}", res_uri);

        encode::encode_array(&mut request, 1);
        encode::encode_string(&mut request, res_uri);
        unsafe {
            let request_len = request.len() as isize;
            let key_ptr_start = CString::new(request).unwrap().as_ptr();
            let key_ptr_end = &(*key_ptr_start.offset(request_len));
            let count = box_index_count(conn.individuals_space_id, conn.individuals_index_id,
                IteratorType::EQ as i32, key_ptr_start, key_ptr_end);
            // writeln!(stderr(), "@COUNT {0}", count);

            if count > 0 {
                if need_auth {
                    let auth_result = authorization::compute_access(user_id, res_uri, &conn);
                    let mut access: u8 = 0;
                    match auth_result {
                        Ok(a) => access = a,
                        Err(err) => {
                            writeln!(stderr(), "@ERR ON COMPUTING ACCESS {0} {1} {2}", user_id, 
                                res_uri, err);
                            encode::encode_uint(resp_msg, Codes::InternalServerError as u64);
                            encode::encode_nil(resp_msg);
                            continue;
                        }
                    }

                    if (access & authorization::ACCESS_CAN_READ) == 0 {
                        encode::encode_uint(resp_msg, Codes::NotAuthorized as u64);
                        encode::encode_nil(resp_msg);
                        continue;
                    }
                }

                let mut get_result: *mut BoxTuple = null_mut();
                let get_code = box_index_get(conn.individuals_space_id, conn.individuals_index_id,
                     key_ptr_end, key_ptr_end, &mut get_result as *mut *mut BoxTuple);
                let tuple_size = box_tuple_bsize(get_result);
                let mut tuple_buf: Vec<u8> = vec![0; tuple_size];
                box_tuple_to_buf(get_result, tuple_buf.as_mut_ptr() as *mut c_char, tuple_size);
                encode::encode_uint(resp_msg, Codes::Ok as u64);
                encode::encode_bin(resp_msg, &mut tuple_buf);
            } else if count == 0 {
                encode::encode_uint(resp_msg, Codes::NotFound as u64);
                encode::encode_nil(resp_msg);
            } else if count < 0 {
                writeln!(stderr(), "@ERR ON COUNT {0}", res_uri);
                encode::encode_uint(resp_msg, Codes::InternalServerError as u64);
                encode::encode_nil(resp_msg);
            }
        }

        
    }
}

pub fn auth(cursor: &mut Cursor<&[u8]>, arr_size: u64, need_auth:bool, resp_msg: &mut Vec<u8>) {
    writeln!(stderr(), "@ERR AUTH IS NOT IMPLEMENTED").unwrap();
    encode::encode_array(resp_msg, 1);
    encode::encode_uint(resp_msg, Codes::NotFound as u64);
}

pub fn remove(cursor: &mut Cursor<&[u8]>, arr_size: u64, need_auth:bool, resp_msg: &mut Vec<u8>) {
    writeln!(stderr(), "@ERR REMOVE IS NOT IMPLEMENTED").unwrap();
    encode::encode_array(resp_msg, 1);
    encode::encode_uint(resp_msg, Codes::NotFound as u64);
}