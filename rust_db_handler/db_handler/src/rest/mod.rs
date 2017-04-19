use std::io::{ Write, stderr };

pub enum Codes {
    Ok = 200,
    BadRequest = 400,
    NotAuthorized = 472,
    NotFound = 404,
    InternalServerError = 500
}

pub fn put(mut msg: &[u8], arr_size: u32, need_auth:bool, resp_msg: &mut Vec<u8>) {
   /* writeln!(stderr(), "@ERR PUT IS NOT IMPLEMENTED").unwrap();
    write_array_len(resp_msg, 1).unwrap();
    write_u64(resp_msg, Codes::InternalServerError as u64).unwrap();
    super::rmp_bind::*/
}
