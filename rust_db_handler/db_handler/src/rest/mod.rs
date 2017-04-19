extern crate core;
extern crate rmp_bind;

use std::ffi::{ CString };
use std::io::{ Write, stderr, Cursor };
use rmp_bind::encode;


include!("../../module.rs");

pub enum Codes {
    Ok = 200,
    BadRequest = 400,
    NotAuthorized = 472,
    NotFound = 404,
    InternalServerError = 500
}

pub fn put(cursor: &mut Cursor<&[u8]>, arr_size: u64, need_auth:bool, resp_msg: &mut Vec<u8>) {
    writeln!(stderr(), "@ERR PUT IS NOT IMPLEMENTED").unwrap();
    encode::encode_array(resp_msg, 1);
    encode::encode_uint(resp_msg, Codes::NotFound as u64);
}


pub fn get(cursor: &mut Cursor<&[u8]>, arr_size: u64, need_auth:bool, resp_msg: &mut Vec<u8>) {
    writeln!(stderr(), "@ERR GET IS NOT IMPLEMENTED").unwrap();
    encode::encode_array(resp_msg, 1);
    encode::encode_uint(resp_msg, Codes::NotFound as u64);
}

pub fn auth(cursor: &mut Cursor<&[u8]>, arr_size: u64, need_auth:bool, resp_msg: &mut Vec<u8>) {
    let acl_space_id: u32;
    let acl_index_id: u32;
    unsafe {
        acl_space_id = box_space_id_by_name(CString::new("acl").unwrap().as_ptr(), "acl".len() as u32);
        acl_index_id = box_index_id_by_name(acl_space_id, CString::new("primary").unwrap().as_ptr(), 
            "primary".len() as u32);
    }
    writeln!(stderr(), "@ERR AUTH IS NOT IMPLEMENTED").unwrap();
    encode::encode_array(resp_msg, 1);
    encode::encode_uint(resp_msg, Codes::NotFound as u64);
}

pub fn remove(cursor: &mut Cursor<&[u8]>, arr_size: u64, need_auth:bool, resp_msg: &mut Vec<u8>) {
    writeln!(stderr(), "@ERR REMOVE IS NOT IMPLEMENTED").unwrap();
    encode::encode_array(resp_msg, 1);
    encode::encode_uint(resp_msg, Codes::NotFound as u64);
}