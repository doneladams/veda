extern crate rmp;

use std::result;
use self::rmp::encode;

pub fn encode_array(buf: &mut Vec<u8>, len: u32) {
    encode::write_array_len(buf, len).unwrap();
}

pub fn encode_uint(buf: &mut Vec<u8>, val: u64) {
    encode::write_u64(buf, val).unwrap();
}

pub fn encode_nil(buf: &mut Vec<u8>) {
    encode::write_nil(buf).unwrap();
}

pub fn encode_string(buf: &mut Vec<u8>, val: &str) {
    encode::write_str(buf, val);
}

pub fn encode_bin(buf: &mut Vec<u8>, val: &Vec<u8>) {
    encode::write_bin(buf, val);
}