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
    individuals_space_id: u32,
    individuals_index_id: u32,
    rdf_types_space_id: u32,
    rdf_types_index_id: u32,
    permissions_space_id: u32,
    permissions_index_id: u32,
    memberships_space_id: u32,
    memberships_index_id: u32
}

fn connect_to_tarantool() -> Result<TarantoolConnection, String> {
    let mut conn: TarantoolConnection = Default::default();
    unsafe {
        conn.individuals_space_id = box_space_id_by_name(CString::new("individuals").unwrap().as_ptr(), 
            "individuals".len() as u32);
        if conn.individuals_space_id == BOX_ID_NIL {
            return Err("@ERR NO SPACE individuals".to_string());
        }
        
        conn.individuals_index_id = box_index_id_by_name(conn.individuals_space_id, 
            CString::new("primary").unwrap().as_ptr(), 
            "primary".len() as u32);
        if conn.individuals_index_id == BOX_ID_NIL {
            return Err("@ERR NO INDEX primary IN individuals".to_string());
        }

        conn.rdf_types_space_id = box_space_id_by_name(CString::new("rdf_types").unwrap().as_ptr(), 
            "rdf_types".len() as u32);
        if conn.rdf_types_space_id == BOX_ID_NIL {
            return Err("@ERR NO SPACE rdf_types".to_string());
        }
        
        conn.rdf_types_index_id = box_index_id_by_name(conn.rdf_types_space_id, 
            CString::new("primary").unwrap().as_ptr(), "primary".len() as u32);
        if conn.rdf_types_index_id == BOX_ID_NIL {
            return Err("@ERR NO INDEX primary IN rdf_types".to_string());
        }

        conn.permissions_space_id = box_space_id_by_name(CString::new("permissions").unwrap().as_ptr(), 
            "permissions".len() as u32);
        if conn.permissions_space_id == BOX_ID_NIL {
            return Err("@ERR NO SPACE permissions".to_string());
        }
        
        conn.permissions_index_id = box_index_id_by_name(conn.permissions_space_id, 
            CString::new("primary").unwrap().as_ptr(), "primary".len() as u32);
        if conn.permissions_index_id == BOX_ID_NIL {
            return Err("@ERR NO INDEX primary IN permissions".to_string());
        }

        conn.memberships_space_id = box_space_id_by_name(CString::new("memberships").unwrap().as_ptr(), 
            "memberships".len() as u32);
        if conn.memberships_space_id == BOX_ID_NIL {
            return Err("@ERR NO SPACE memberships".to_string());
        }
        
        conn.memberships_index_id = box_index_id_by_name(conn.memberships_space_id, 
            CString::new("primary").unwrap().as_ptr(), "primary".len() as u32);
        if conn.memberships_index_id == BOX_ID_NIL {
            return Err("@ERR NO INDEX primary IN memberships".to_string());
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
    writeln!(stderr(), "@DECODE USER ID");
    match decode::decode_string(cursor, &mut user_id_buf) {
        Err(err) => return super::fail(resp_msg, Codes::InternalServerError, err),
        Ok(_) => {user_id = std::str::from_utf8(&user_id_buf).unwrap()}
    }
    writeln!(stderr(), "@DECODED USER ID");
    

    encode::encode_array(resp_msg, (arr_size - 3 + 1) as u32);
    encode::encode_uint(resp_msg, Codes::Ok as u64);

    for i in 3 .. arr_size {
        let mut individual_msgpack_buf = Vec::default();    
        let individual_msgpack: &str;
        
        writeln!(stderr(), "@DECODE INDIVIDUAL MSGPACK").unwrap();
        match decode::decode_string(cursor, &mut individual_msgpack_buf) {
            Err(err) => {
                writeln!(stderr(), "@ERR DECODING INDIVIDUAL MSGPACK {0}", err);
                encode::encode_uint(resp_msg, Codes::InternalServerError as u64);
                return;
            }
            Ok(_) => {}
        }
        writeln!(stderr(), "@DECODED INDIVIDUAL").unwrap();

        writeln!(stderr(), "@INDIVIDUAL TO MSGPACK").unwrap();
        let mut individual = put_routine::Individual::new();
        match put_routine::msgpack_to_individual(&mut Cursor::new(&individual_msgpack_buf[..]), &mut individual) {
            Ok(_) => {}
            Err(err) => {
                writeln!(stderr(), "@ERR DECODING INDIVIDUAL {0}", err);
                encode::encode_uint(resp_msg, Codes::InternalServerError as u64);
                return;
            }
        }
        writeln!(stderr(), "@INDIVIDUAL TO MSGPACK DONE").unwrap();
        
        let mut new_state_res: &Vec<put_routine::Resource>;
        match individual.resources.get(&"new_state".to_string()) {
            Some(res) => new_state_res = res,
            _ => {
                writeln!(stderr(), "@NO NEW_STATE FOUND");
                encode::encode_uint(resp_msg, Codes::BadRequest as u64);
                return;
            }
        }

        writeln!(stderr(), "@CONTAINS NEW_STATE");
        let mut new_state = put_routine::Individual::new();
        match put_routine::msgpack_to_individual(&mut Cursor::new(&new_state_res[0].str_data[..]), 
            &mut new_state) {
            Ok(_) => {}
            Err(err) => {
                writeln!(stderr(), "@ERR DECODING NEW STATE {0}", err);
                encode::encode_uint(resp_msg, Codes::InternalServerError as u64);
                return;
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
                return;
            }
        }

        writeln!(stderr(), "@TNT RDF:TYPE LEN {0}", tnt_rdf_types.len());
        let mut is_update: bool = true;
        if (tnt_rdf_types.len() > 0 && need_auth) {
            for i in 0 .. rdf_types.len() {
                writeln!(stderr(), "@TRY TO FIND {0}", 
                    std::str::from_utf8(rdf_types[i].str_data.as_ref()).unwrap());
                match tnt_rdf_types.iter().find(|&rdf_type| rdf_type.as_slice() == 
                    rdf_types[i].str_data.as_slice()) {
                        None => {
                            writeln!(stderr(), "@NOT FOUND").unwrap();
                            is_update = false;
                            let auth_result = authorization::compute_access(user_id, 
                                std::str::from_utf8(&rdf_types[i].str_data[..]).unwrap(), &conn);
                            let mut auth_result: u8;
                            match authorization::compute_access(user_id, 
                                std::str::from_utf8(&rdf_types[i].str_data[..]).unwrap(), &conn) {
                                Err(err) => {
                                    writeln!(stderr(), "@ERR UN UPDATE AUTH {0}", err).unwrap();
                                    encode::encode_uint(resp_msg, Codes::InternalServerError as u64);
                                    return;
                                }
                                Ok(ac) => auth_result = ac
                            }
                            if (auth_result & authorization::ACCESS_CAN_CREATE) == 0 {
                                encode::encode_uint(resp_msg, Codes::NotAuthorized as u64);
                                return;
                            } 
                        }
                        Some(_) => {}
                    }
            }
        } else {
            is_update = false;
        }
        writeln!(stderr(), "@IS UPDATE {0}", is_update);
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
      
        unsafe {
            writeln!(stderr(), "@REPLACE NEW STATE IN TARANTOOL").unwrap();
            let request_len = new_state_res[0].str_data[..].len() as isize;
            writeln!(stderr(), "@REPLACE NEW STATE LEN {0}", request_len);
            let key_ptr_start = new_state_res[0].str_data[..].as_ptr() as *const i8;
            let key_ptr_end = key_ptr_start.offset(request_len);
            writeln!(stderr(), "@TRY REPLACE NEW STATE");
            let replace_code = box_replace(conn.individuals_space_id, key_ptr_start, key_ptr_end, 
                &mut null_mut() as *mut *mut BoxTuple);
            if replace_code < 0 {
                writeln!(stderr(), "{0}",
                    CStr::from_ptr(box_error_message(box_error_last())).to_str().unwrap().to_string());
            }
        }

        let mut prev_state_res: &Vec<put_routine::Resource>;
        let mut prev_state = put_routine::Individual::new();
        match individual.resources.get(&"prev_state".to_string()) {
            Some(res) => {
                prev_state_res = res;
                writeln!(stderr(), "@CONTAINS PREV_STATE");
                match put_routine::msgpack_to_individual(&mut Cursor::new(&prev_state_res[0].str_data[..]), 
                    &mut prev_state) {
                    Ok(_) => {}
                    Err(err) => {
                        writeln!(stderr(), "@ERR DECODING PREV_STATE {0}", err);
                        encode::encode_uint(resp_msg, Codes::InternalServerError as u64);
                        return;
                    }
                }
            }
            _ => {}
        }

        writeln!(stderr(), "@RDF TYPE {0}", std::str::from_utf8(&rdf_types[0].str_data[..]).unwrap()).unwrap();
        match std::str::from_utf8(&rdf_types[0].str_data[..]).unwrap() {
            "v-s:PermissionStatement" => {
                writeln!(stderr(), "@PERMISSION");
                match put_routine::prepare_right_set(&prev_state, &new_state, "v-s:permissionObject", 
                    "v-s:permissionSubject", conn.permissions_space_id, conn.permissions_index_id) {
                    Err(err) => {
                        writeln!(stderr(), "@ERR PREPARE PEMISSION {0}", err);
                        encode::encode_uint(resp_msg, Codes::InternalServerError as u64);
                        return;
                    }
                    _ => {}
                }
            }
            "v-s:Membership" => {
                writeln!(stderr(), "@MEMBERSHIP");
                match put_routine::prepare_right_set(&prev_state, &new_state, "v-s:resource", 
                    "v-s:memberOf", conn.memberships_space_id, conn.memberships_index_id) {
                    Err(err) => {
                        writeln!(stderr(), "@ERR PREPARE PEMISSION {0}", err);
                        encode::encode_uint(resp_msg, Codes::InternalServerError as u64);
                        return;
                    }
                    _ => {}
                }
            }
            _ => {}
        }
        
        encode::encode_uint(resp_msg, Codes::Ok as u64)
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
            let key_ptr_start = request[..].as_ptr() as *const i8;
            let key_ptr_end = key_ptr_start.offset(request_len);
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
                writeln!(stderr(), "@TRY GET INDIVIDUAL").unwrap();
                let mut get_result: *mut BoxTuple = null_mut();
                let get_code = box_index_get(conn.individuals_space_id, conn.individuals_index_id,
                     key_ptr_start, key_ptr_end, &mut get_result as *mut *mut BoxTuple);
            
                if get_code < 0 {
                    writeln!(stderr(), "@ERR GET FROM TARANTOOL {0}",
                        CStr::from_ptr(box_error_message(box_error_last())).to_str().unwrap().to_string());
                }
                let tuple_size = box_tuple_bsize(get_result);
                let mut tuple_buf: Vec<u8> = vec![0; tuple_size];
                box_tuple_to_buf(get_result, tuple_buf.as_mut_ptr() as *mut c_char, tuple_size);
                
                encode::encode_uint(resp_msg, Codes::Ok as u64);
                encode::encode_string_bytes(resp_msg, &tuple_buf);
                writeln!(stderr(), "@GOT INDIVIDUAL");
                // encode::encode_uint(resp_msg, Codes::NotFound as u64);
                // encode::encode_nil(resp_msg);
            } else if count == 0 {
                writeln!(stderr(), "@NOT FOUND");
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
    writeln!(stderr(), "@AUTH").unwrap();
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
            let key_ptr_start = request[..].as_ptr() as *const i8;
            let key_ptr_end = key_ptr_start.offset(request_len);
            let count = box_index_count(conn.individuals_space_id, conn.individuals_index_id,
                IteratorType::EQ as i32, key_ptr_start, key_ptr_end);
            if count == 0 {
                encode::encode_uint(resp_msg, Codes::NotFound as u64);
                encode::encode_uint(resp_msg, 0);
                return;
            }
        }

        let auth_result = authorization::compute_access(user_id, res_uri, &conn);
        match auth_result {
            Ok(access) => {
                encode::encode_uint(resp_msg, Codes::Ok as u64);
                encode::encode_uint(resp_msg, access as u64);
            }
            Err(err) => {
                writeln!(stderr(), "@ERR ON COMPUTING ACCESS {0} {1} {2}", user_id, 
                    res_uri, err);
                encode::encode_uint(resp_msg, Codes::InternalServerError as u64);
                encode::encode_uint(resp_msg, 0);
            }
        }
    }
}

pub fn remove(cursor: &mut Cursor<&[u8]>, arr_size: u64, need_auth:bool, resp_msg: &mut Vec<u8>) {
    writeln!(stderr(), "@REMOVE");
    let mut conn: TarantoolConnection;

    match connect_to_tarantool() {
        Err(err) => return super::fail(resp_msg, Codes::InternalServerError, err),
        Ok(c) => conn = c
    }

    let mut user_id_buf = Vec::default();
    let mut user_id: &str;
    writeln!(stderr(), "@DECODE USER ID");
    match decode::decode_string(cursor, &mut user_id_buf) {
        Err(err) => return super::fail(resp_msg, Codes::InternalServerError, err),
        Ok(_) => {user_id = std::str::from_utf8(&user_id_buf).unwrap()}
    }
    writeln!(stderr(), "@DECODED USER ID");
    

    encode::encode_array(resp_msg, (arr_size - 3 + 1) as u32);
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
            let key_ptr_start = request[..].as_ptr() as *const i8;
            let key_ptr_end = key_ptr_start.offset(request_len);

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

                if (access & authorization::ACCESS_CAN_DELETE) == 0 {
                    encode::encode_uint(resp_msg, Codes::NotAuthorized as u64);
                    encode::encode_nil(resp_msg);
                    continue;
                }
            }

            

            let mut delete_code = box_delete(conn.individuals_space_id, conn.individuals_index_id, 
                key_ptr_start, key_ptr_end, &mut null_mut() as *mut *mut BoxTuple);
            if delete_code < 0 {
                writeln!(stderr(), "@ERR DELETE INDIVIDUAL {0}",
                    CStr::from_ptr(box_error_message(box_error_last())).to_str().unwrap().to_string());
            }

            let mut delete_code = box_delete(conn.rdf_types_space_id, conn.rdf_types_index_id, 
                key_ptr_start, key_ptr_end, &mut null_mut() as *mut *mut BoxTuple);
            if delete_code < 0 {
                writeln!(stderr(), "@ERR DELETE RDF TYPES {0}",
                    CStr::from_ptr(box_error_message(box_error_last())).to_str().unwrap().to_string());
            }

            let mut delete_code = box_delete(conn.permissions_space_id, conn.permissions_index_id, 
                key_ptr_start, key_ptr_end, &mut null_mut() as *mut *mut BoxTuple);
            if delete_code < 0 {
                writeln!(stderr(), "@ERR DELETE PERMISSION {0}",
                    CStr::from_ptr(box_error_message(box_error_last())).to_str().unwrap().to_string());
            }

            let mut delete_code = box_delete(conn.memberships_space_id, conn.memberships_space_id, 
                key_ptr_start, key_ptr_end, &mut null_mut() as *mut *mut BoxTuple);
            if delete_code < 0 {
                writeln!(stderr(), "@ERR DELETE INDIVIDUAL {0}",
                    CStr::from_ptr(box_error_message(box_error_last())).to_str().unwrap().to_string());
            }
        }
        encode::encode_uint(resp_msg, Codes::Ok as u64);        
    }
}