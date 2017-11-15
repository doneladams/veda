use lmdb_rs::{DbHandle};
use std;
use std::io::{ Write, stderr, Cursor };
use rmp_bind::{ encode, decode };

const MAX_VECTOR_SIZE: usize = 150;

/// REST return codes
pub enum Codes {
    Ok = 200,
    BadRequest = 400,
    TicketExpired = 471,
    NotAuthorized = 472,
    NotFound = 404,
    InternalServerError = 500,
    UnprocessableEntity = 422
}

pub fn get(cursor: &mut Cursor<&[u8]>, arr_size: u64, need_auth:bool, resp_msg: &mut Vec<u8>, db: &DbHandle) {
    let mut user_id_buf = Vec::default();
    let user_id: &str;
    match decode::decode_string(cursor, &mut user_id_buf) {
        Err(err) => return super::fail(resp_msg, Codes::InternalServerError, err),
        Ok(_) => user_id = std::str::from_utf8(&user_id_buf).unwrap()
    }

    encode::encode_array(resp_msg, ((arr_size - 3) * 2 + 1) as u32);
    encode::encode_uint(resp_msg, Codes::Ok as u64);
    
    for _ in 3 .. arr_size {        
        let mut res_uri_buf = Vec::default();    
        let res_uri: &str;

        match decode::decode_string(cursor, &mut res_uri_buf) {
            Err(err) => { super::fail(resp_msg, Codes::InternalServerError, err); continue; },
            Ok(_) => res_uri = std::str::from_utf8(&res_uri_buf).unwrap()
        }

  /*      // writeln!(stderr(), "@GET user: {0} / res: {1}", user_id, res_uri);
        encode::encode_array(&mut request, 1);
        encode::encode_string(&mut request, res_uri);
        /// Unsafe calls to tarantool
        unsafe {
            let request_len = request.len() as isize;
            let key_ptr_start = request[..].as_ptr() as *const i8;
            let key_ptr_end = key_ptr_start.offset(request_len);
            /// Checks if individual exists
            let count = box_index_count(conn.individuals_space_id, conn.individuals_index_id,
                IteratorType::EQ as i32, key_ptr_start, key_ptr_end);
            
            if count > 0 {
                if need_auth {
                    /// If exists and authorization is needed
                    /// computes and checks rights for user
                    let auth_result = authorization::compute_access(user_id, res_uri, &conn, false, 
                        false, false).0;

                    if (auth_result & authorization::ACCESS_CAN_READ) == 0 {
                        encode::encode_uint(resp_msg, Codes::NotAuthorized as u64);
                        encode::encode_nil(resp_msg);
                        continue;
                    }
                }

                let mut get_result: *mut BoxTuple = null_mut();
                /// Get tuple from tarantool if found it
                box_index_get(conn.individuals_space_id, conn.individuals_index_id,
                     key_ptr_start, key_ptr_end, &mut get_result as *mut *mut BoxTuple);
                
                let tuple_size = box_tuple_bsize(get_result);
                let mut tuple_buf: Vec<u8> = vec![0; tuple_size];
                box_tuple_to_buf(get_result, tuple_buf.as_mut_ptr() as *mut c_char, tuple_size);
                

                ///If everything is ok, Ok code and individual's msgpack are returned to user
                encode::encode_uint(resp_msg, Codes::Ok as u64);
                encode::encode_string_bytes(resp_msg, &tuple_buf);
            } else if count == 0 {
                ///If not fount, then UnpocessableEntity code and nil are returned to user and 
                encode::encode_uint(resp_msg, Codes::UnprocessableEntity as u64);
                encode::encode_nil(resp_msg);
            } else if count < 0 {
                ///If error occured than InternalServerError code returned to user
                writeln!(stderr(), "@ERR ON COUNT {0}", res_uri).unwrap();
                encode::encode_uint(resp_msg, Codes::InternalServerError as u64);
                encode::encode_nil(resp_msg);
            }
        }*/

        
    }
}