extern crate core;
extern crate rmp_bind;

mod rest;

use std::io::{ Write, stderr };
use rmp_bind::{ decode, encode };

// use rest::{ Codes, put };
// use rest::rmp_bind;

const PUT: u64 = 1;
const GET: u64 = 2;
const AUTHORIZE: u64 = 8;
const REMOVE: u64 = 51;

#[repr(C)]
pub struct Response {
    msg: *const u8,
    size: usize
}


fn unmarshal_request(mut msg: &[u8], arr_size: u64, resp_msg: &mut Vec<u8>) {
    if arr_size < 4 {
        writeln!(&mut stderr(), "@INVALID MSGPACK SIZE < 4").unwrap();
        return;
    }



    writeln!(&mut stderr(), "@UNMARSHAL").unwrap();
    encode::encode_array(resp_msg, 1);
    encode::encode_uint(resp_msg, rest::Codes::InternalServerError as u64);
    /*let op = read_int(&mut &msg[..]).unwrap();
    writeln!(&mut stderr(), "@op code {0}", op).unwrap();
    let need_auth = read_bool(&mut &msg[..]).unwrap();
    writeln!(&mut stderr(), "@op code {0}", need_auth).unwrap();    
    match op {
        PUT => put(msg, arr_size, need_auth, resp_msg),
        GET => println!("GET"),
        AUTHORIZE => println!("AUTH"),
        REMOVE => println!("REMOVE"),
        _ => fail(resp_msg, format!("@ERR UNKNOWN REQUEST {0}", op))
    }*/
}

fn fail(resp_msg: &mut Vec<u8>, err_msg: String) {
/*    writeln!(&mut stderr(), "{0}", err_msg).unwrap();
    write_array_len(resp_msg, 1).unwrap();
    write_u64(resp_msg, Codes::InternalServerError as u64).unwrap();*/
}

#[no_mangle]
pub extern fn handle_request(mut msg: &[u8]) -> Response {
    unsafe {
        let result = decode::decode_array(msg);
        let resp_msg = &mut Vec::new();
         match  result {
            Err(err) => fail(resp_msg, err),
            Ok(arr_size) => unmarshal_request(msg, arr_size, resp_msg)
        }
        writeln!(&mut stderr(), "ENDING");
        return Response { msg: &resp_msg[0], size: resp_msg.len() } ;
    }
}