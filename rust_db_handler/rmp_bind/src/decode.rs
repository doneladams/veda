extern crate rmp;

use std::io::Cursor;
use std::result;
use std::fmt;
use self::rmp::decode;
use std::io::{Write, stderr};

fn decode_uint8(cursor: &mut Cursor<&[u8]>) -> u64 {
    return decode::read_u8(cursor).unwrap() as u64;
}

fn decode_uint16(cursor: &mut Cursor<&[u8]>) -> u64 {
    // writeln!(&mut stderr(), "marker = {:?}", marker); 
    return decode::read_u16(cursor).unwrap() as u64;
}

fn decode_uint32(cursor: &mut Cursor<&[u8]>) -> u64 {
    return decode::read_u32(cursor).unwrap() as u64;
}

fn decode_uint64(cursor: &mut Cursor<&[u8]>) -> u64 {
    return decode::read_u64(cursor).unwrap();
}

fn decode_pfix(cursor: &mut Cursor<&[u8]>, size: u8) -> u64 {
    let mut val: u64 = 0;
    writeln!(stderr(), "DECODE PFIX {0}", size);
    for i in 0 .. size {
        writeln!(stderr(), "DECODE BYTE {0}", size);
        let byte = decode::read_pfix(cursor).unwrap();
        val <<= 8;
        val |= byte as u64;
    }
    return val;   
}

pub fn decode_uint(cursor: &mut Cursor<&[u8]>) -> Result<u64, String> {
    let val: u64 = 0;
    let curr_position = cursor.position();
    // return Ok(decode::read_pfix(cursor).unwrap() as u64);
     
    let marker = decode::read_marker(cursor).unwrap();
    cursor.set_position(curr_position);
    // writeln!(&mut stderr(), "marker = {:?}", marker); 
    // rmp::Marker::FixPos();
    match marker {
        rmp::Marker::U8  => Ok(decode_uint8(cursor)),
        rmp::Marker::U16  => Ok(decode_uint16(cursor)),
        rmp::Marker::U32 => Ok(decode_uint32(cursor)),
        rmp::Marker::U64  => Ok(decode_uint64(cursor)),
        _ => match decode::read_pfix(cursor) {
            Ok(v)  => Ok(v as u64),
            Err(err) => Err(format!("@ERR IS NOT UINT {:?}", marker))
        }
    }
}

pub fn decode_bool(cursor: &mut Cursor<&[u8]>) -> Result<bool, String> {
    match decode::read_bool(cursor) {
        Ok(v) => Ok(v),
        Err(err) => Err(format!("@ERR IS NOT BOOL"))
    }
}

pub fn decode_array(cursor: &mut Cursor<&[u8]>) -> Result<u64, String> {
    match decode::read_array_len(cursor) {
        Ok(arr_size) => Ok(arr_size as u64),
        Err(err) => Err(format!("@ERR DECODING ARRAY {0}", err))
    }
}