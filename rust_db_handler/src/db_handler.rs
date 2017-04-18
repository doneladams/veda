use std::ffi::{ CString, CStr };
use std::os::raw::c_char;
use std::io::{ Write, stderr };
use rmp::decode::{ read_array_len };
use rmp::encode::{ write_array_len, write_u64 };

extern crate core;
extern crate rmp;

#[repr(C)]
pub struct Response {
    msg: *const u8,
    size: usize
}

fn unmarshal_request(mut msg: &[u8], arr_size: u32, resp_msg: &mut Vec<u8>) {
    if arr_size < 4 {
        writeln!(&mut stderr(), "@INVALID MSGPACK SIZE < 4");
        return;
    }
    
    writeln!(&mut stderr(), "@UNMARSHAL");
    write_array_len(resp_msg, 1);
    write_u64(resp_msg, 404);
}

#[no_mangle]
pub extern fn handle_request(mut msg: &[u8], msg_size: usize) -> Response {
    unsafe {
        
        let result = read_array_len(&mut &msg[..]);
        let resp_msg = &mut Vec::new();
        // println!("arr_size={0}", arr_size);
        match  result {
            Err(err) => println!("@ERR DECODING ARRAY {0}", err),
            Ok(arr_size) => unmarshal_request   (msg, arr_size, resp_msg),
        }
        // return Response { msg: CString::new("hello").unwrap().as_ptr(), size: 5 } ;
        return Response { msg: &resp_msg[0], size: resp_msg.len() } ;
    }
}