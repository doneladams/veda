extern crate core;
extern crate rmp_bind;

mod rest;
mod lua;

use std::os::raw::c_char;
use std::io::{ Cursor, Write, stderr };
use rmp_bind::{ decode, encode };
use std::ffi::{ CString, CStr };
use std::net::TcpStream;
use std::os::unix::io::FromRawFd;
use lua::lua_State;


const PUT: u64 = 1;
const GET: u64 = 2;
const AUTHORIZE: u64 = 8;
const REMOVE: u64 = 51;

#[repr(C)]
pub struct Response {
    msg: *const c_char,
    size: usize
}

pub fn fail(resp_msg: &mut Vec<u8>, code: rest::Codes, err_msg: String) {
    writeln!(&mut stderr(), "{0}", err_msg).unwrap();
    encode::encode_array(resp_msg, 1);
    encode::encode_uint(resp_msg, code as u64);
}


fn unmarshal_request(cursor: &mut Cursor<&[u8]>, arr_size: u64, resp_msg: &mut Vec<u8>) {
    if arr_size < 4 {
        fail(resp_msg, rest::Codes::BadRequest, "@INVALID MSGPACK SIZE < 4".to_string());
        return;
    }

    writeln!(&mut stderr(), "@UNMARSHAL").unwrap();
    let mut op_code: u64 = 0;
    match decode::decode_uint(cursor) {
        Err(err) => return fail(resp_msg, rest::Codes::BadRequest, err),
        Ok(op) => (op_code = op)
    }
    writeln!(&mut stderr(), "@op code {0}", op_code).unwrap();
    let mut need_auth: bool = false;
    writeln!(&mut stderr(), "@need_auth {0}", need_auth).unwrap();    
    match decode::decode_bool(cursor) {
        Err(err) => return fail(resp_msg, rest::Codes::BadRequest, err),
        Ok(v) => (need_auth = v)
    }
    match op_code {
        PUT => rest::put(cursor, arr_size, need_auth, resp_msg),
        GET => rest::get(cursor, arr_size, need_auth, resp_msg),
        AUTHORIZE => rest::auth(cursor, arr_size, need_auth, resp_msg),
        REMOVE => rest::remove(cursor, arr_size, need_auth, resp_msg),
        _ => fail(resp_msg, rest::Codes::BadRequest, format!("@ERR UNKNOWN REQUEST {0}", op_code))
    }
    writeln!(stderr(), "@END REQUEST");
}

#[no_mangle]
extern "C" fn db_handle_request(L: *mut lua_State) -> i32 {
    writeln!(stderr(), "@HERE");
    let mut msg_size: i32;
    let mut msg: Vec<u8> = Vec::default();
    lua::tolstring(L, -1, &mut msg);
    writeln!(stderr(), "@MSG LEN {0}", msg.len());
    writeln!(stderr(), "@BEGIN REQUEST");
    let mut cursor = Cursor::new(&msg[..]);
    let mut resp_msg = Vec::new();
    let mut arr_size: u64 = 0;
    writeln!(stderr(), "@DECODE RESPONSE ARRAY REQUEST");       
    // decode::decode_array(&mut cursor).unwrap();
    
    match  decode::decode_array(&mut cursor) {
        Err(err) => fail(&mut resp_msg, rest::Codes::InternalServerError, err),
        Ok(arr_size) => unmarshal_request(&mut cursor, arr_size, &mut resp_msg)
    }
    // encode::encode_array(&mut resp_msg, 1);
    // encode::encode_uint(&mut resp_msg, rest::Codes::InternalServerError as u64);

    lua::pushlstring(L, &resp_msg);
    
    /*let response = Response { msg: resp_msg[..].as_ptr() as *const i8, size: resp_msg.len() };
    writeln!(stderr(), "@FORGET RESPONSE");        
    std::mem::forget(resp_msg);
    writeln!(stderr(), "@RETURN RESPONSE");                
    return  response;*/

    return 1;
}

// const DB_HANDLER_LIB: [(&'static str, Function); 1] = [
//   ("db_handle_request", Some(db_handle_request)),
// ];

#[no_mangle]
pub extern "C" fn luaopen_db_handler(L: *mut lua_State) -> i32 {
    lua::register(L, "db_handle_request", db_handle_request);
    return 0;
}