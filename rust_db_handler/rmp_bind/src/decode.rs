extern crate rmp;

use std::result;
use self::rmp::decode;

/*pub fn read_uint(mut msg: &[u8]) -> u64 {
    let val: u64 = 0;
    match rmp::decode::read_marker(mut msg: &[u8]) {
        rmp::Marker::U8 => println!("u8"),
        rmp::Marker::U16 => println!("u16"),
        rmp::Marker::U32 => println!("u32"),
        rmp::Marker::U64 => println!("u64")
    }
    return 0;
}*/

pub fn decode_array(mut buf: &[u8]) -> Result<u64, String> {
    match decode::read_array_len(&mut &buf[..]) {
        Ok(arr_size) => Ok(arr_size as u64),
        Err(err) => Err(format!("@ERR DECODING ARRAY {0}", err))
    }
}

pub fn test_fn() {
    println!("here i am");
}