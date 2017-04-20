extern crate core;
extern crate rmp_bind;

use std::ffi::{ CString, CStr };
use std::io::{ Write, stderr, Cursor };
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
struct TarantoolConnection {
    acl_space_id: u32,
    acl_index_id: u32,
    individuals_space_id: u32,
    individuals_index_id: u32
}

fn connect_to_tarantool() -> Result<TarantoolConnection, String> {
    let mut conn: TarantoolConnection = Default::default();
    unsafe {
        conn.acl_space_id = box_space_id_by_name(CString::new("acl").unwrap().as_ptr(), "acl".len() as u32);
        if conn.acl_space_id == BOX_ID_NIL {
            return Err("@ERR NO SPACE acl".to_string());
        }
        
        conn.acl_index_id = box_index_id_by_name(conn.acl_space_id, CString::new("primary").unwrap().as_ptr(), 
            "primary".len() as u32);
        if conn.acl_index_id == BOX_ID_NIL {
            return Err("@ERR NO INDEX primary IN acl".to_string());
        }

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

        return Ok(conn);
    }
}


pub fn put(cursor: &mut Cursor<&[u8]>, arr_size: u64, need_auth:bool, resp_msg: &mut Vec<u8>) {
    writeln!(stderr(), "@ERR PUT IS NOT IMPLEMENTED").unwrap();
    encode::encode_array(resp_msg, 1);
    encode::encode_uint(resp_msg, Codes::NotFound as u64);
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
        Ok(s) => user_id = s
    }

    encode::encode_array(resp_msg, ((arr_size - 3) * 2 + 1) as u32);
    encode::encode_uint(resp_msg, Codes::Ok as u64);
    for i in 3 .. arr_size {
        let mut res_uri_buf = Vec::default();    
        let res_uri: &str;
        let mut request = Vec::new();


        match decode::decode_string(cursor, &mut res_uri_buf) {
            Err(err) => { super::fail(resp_msg, Codes::InternalServerError, err); continue; },
            Ok(s) => res_uri = s
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
            writeln!(stderr(), "@COUNT {0}", count);
        }

        encode::encode_uint(resp_msg, Codes::NotFound as u64);
        encode::encode_nil(resp_msg);
    }
}

pub fn auth(cursor: &mut Cursor<&[u8]>, arr_size: u64, need_auth:bool, resp_msg: &mut Vec<u8>) {
  /*  let acl_space_id: u32;
    let acl_index_id: u32;
    unsafe {
        acl_space_id = box_space_id_by_name(CString::new("acl").unwrap().as_ptr(), "acl".len() as u32);
        acl_index_id = box_index_id_by_name(acl_space_id, CString::new("primary").unwrap().as_ptr(), 
            "primary".len() as u32);
    }*/
    writeln!(stderr(), "@ERR AUTH IS NOT IMPLEMENTED").unwrap();
    encode::encode_array(resp_msg, 1);
    encode::encode_uint(resp_msg, Codes::NotFound as u64);
}

pub fn remove(cursor: &mut Cursor<&[u8]>, arr_size: u64, need_auth:bool, resp_msg: &mut Vec<u8>) {
    writeln!(stderr(), "@ERR REMOVE IS NOT IMPLEMENTED").unwrap();
    encode::encode_array(resp_msg, 1);
    encode::encode_uint(resp_msg, Codes::NotFound as u64);
}