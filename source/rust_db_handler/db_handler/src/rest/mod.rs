/// This module gives functions to handle put, get, remove, auth requests,

extern crate core;
extern crate rmp_bind;
extern crate chrono;

mod authorization;
mod put_routine;

use std;
use std::ffi::{ CString };
use std::io::{ Write, stderr, Cursor };
use std::os::raw::c_char;
use std::ptr::null_mut;
use rmp_bind::{ encode, decode };
use self::chrono::prelude::*;

///includes defeinitions for tarantool functions
include!("../../module.rs");

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

#[derive(Default)]
///Struct with ids of all spaces and its primary indexes
pub struct TarantoolConnection {
    individuals_space_id: u32,
    individuals_index_id: u32,
    rdf_types_space_id: u32,
    rdf_types_index_id: u32,
    permissions_space_id: u32,
    permissions_index_id: u32,
    memberships_space_id: u32,
    memberships_index_id: u32,
    logins_space_id: u32,
    logins_index_id: u32,
    tickets_space_id: u32,
    tickets_index_id: u32,
}


///Get ids for TarantoolConnection to all spaces
fn connect_to_tarantool() -> Result<TarantoolConnection, String> {
    let mut conn: TarantoolConnection = Default::default();
    unsafe {
        conn.individuals_space_id = box_space_id_by_name(CString::new("individuals").unwrap().as_ptr(), 
            "individuals".len() as u32);
        if conn.individuals_space_id == BOX_ID_NIL {
            return Err("@ERR NO SPACE individuals".to_string());
        }
        
        conn.individuals_index_id = box_index_id_by_name(conn.individuals_space_id, 
            CString::new("primary").unwrap().as_ptr(), 
            "primary".len() as u32);
        if conn.individuals_index_id == BOX_ID_NIL {
            return Err("@ERR NO INDEX primary IN individuals".to_string());
        }

        conn.rdf_types_space_id = box_space_id_by_name(CString::new("rdf_types").unwrap().as_ptr(), 
            "rdf_types".len() as u32);
        if conn.rdf_types_space_id == BOX_ID_NIL {
            return Err("@ERR NO SPACE rdf_types".to_string());
        }
        
        conn.rdf_types_index_id = box_index_id_by_name(conn.rdf_types_space_id, 
            CString::new("primary").unwrap().as_ptr(), "primary".len() as u32);
        if conn.rdf_types_index_id == BOX_ID_NIL {
            return Err("@ERR NO INDEX primary IN rdf_types".to_string());
        }

        conn.permissions_space_id = box_space_id_by_name(CString::new("permissions").unwrap().as_ptr(), 
            "permissions".len() as u32);
        if conn.permissions_space_id == BOX_ID_NIL {
            return Err("@ERR NO SPACE permissions".to_string());
        }
        
        conn.permissions_index_id = box_index_id_by_name(conn.permissions_space_id, 
            CString::new("primary").unwrap().as_ptr(), "primary".len() as u32);
        if conn.permissions_index_id == BOX_ID_NIL {
            return Err("@ERR NO INDEX primary IN permissions".to_string());
        }

        conn.memberships_space_id = box_space_id_by_name(CString::new("memberships").unwrap().as_ptr(), 
            "memberships".len() as u32);
        if conn.memberships_space_id == BOX_ID_NIL {
            return Err("@ERR NO SPACE memberships".to_string());
        }
        
        conn.memberships_index_id = box_index_id_by_name(conn.memberships_space_id, 
            CString::new("primary").unwrap().as_ptr(), "primary".len() as u32);
        if conn.memberships_index_id == BOX_ID_NIL {
            return Err("@ERR NO INDEX primary IN memberships".to_string());
        }

        conn.logins_space_id = box_space_id_by_name(CString::new("logins").unwrap().as_ptr(), 
            "logins".len() as u32);
        if conn.logins_space_id == BOX_ID_NIL {
            return Err("@ERR NO SPACE logins".to_string());
        }
        
        conn.logins_index_id = box_index_id_by_name(conn.logins_space_id, 
            CString::new("primary").unwrap().as_ptr(), "primary".len() as u32);
        if conn.memberships_index_id == BOX_ID_NIL {
            return Err("@ERR NO INDEX primary IN logins".to_string());
        }

        conn.tickets_space_id = box_space_id_by_name(CString::new("tickets").unwrap().as_ptr(), 
            "tickets".len() as u32);
        if conn.tickets_space_id == BOX_ID_NIL {
            return Err("@ERR NO SPACE tickets".to_string());
        }
        
        conn.tickets_index_id = box_index_id_by_name(conn.tickets_space_id, 
            CString::new("primary").unwrap().as_ptr(), "primary".len() as u32);
        if conn.memberships_index_id == BOX_ID_NIL {
            return Err("@ERR NO INDEX primary IN tickets".to_string());
        }

        return Ok(conn);
    }
}

///Parses and handles msgpack put request according to docs
pub fn put(cursor: &mut Cursor<&[u8]>, arr_size: u64, need_auth:bool, resp_msg: &mut Vec<u8>) {
    let conn: TarantoolConnection;

    ///Connects to tarantool
    match connect_to_tarantool() {
        Err(err) => return super::fail(resp_msg, Codes::InternalServerError, err),
        Ok(c) => conn = c
    }

    let mut user_id_buf = Vec::default();
    let user_id: &str;
    ///First put decodes user_id
    match decode::decode_string(cursor, &mut user_id_buf) {
        Err(err) => return super::fail(resp_msg, Codes::InternalServerError, err),
        Ok(_) => {user_id = std::str::from_utf8(&user_id_buf).unwrap()}
    }
    
    encode::encode_array(resp_msg, (arr_size - 3 + 1) as u32);
    ///For all responses firs is common operation result
    encode::encode_uint(resp_msg, Codes::Ok as u64);

    ///Cycle handles separate requests from user and encodes results in response
    for _ in 3 .. arr_size {
        let mut individual_msgpack_buf = Vec::default();    
        
        match decode::decode_string(cursor, &mut individual_msgpack_buf) {
            Err(err) => {
                writeln!(stderr(), "@ERR DECODING INDIVIDUAL MSGPACK {0}", err).unwrap();
                encode::encode_uint(resp_msg, Codes::InternalServerError as u64);
                return;
            }
            Ok(_) => {}
        }

        let mut individual = put_routine::Individual::new();
        ///Decoding msgpack to individual structure
        match put_routine::msgpack_to_individual(&mut Cursor::new(&individual_msgpack_buf[..]), &mut individual) {
            Ok(_) => {}
            Err(err) => {
                writeln!(stderr(), "@ERR DECODING INDIVIDUAL {0}", err).unwrap();
                encode::encode_uint(resp_msg, Codes::InternalServerError as u64);
                return;
            }
        }
        
        let new_state_res: &Vec<put_routine::Resource>;
        ///Decoding the state of individual to store in base
        match individual.resources.get(&"new_state".to_string()) {
            Some(res) => new_state_res = res,
            _ => {
                ///New state must be in all individs, 
                ///if new state wasn't found BadRequest is returned to client
                writeln!(stderr(), "@NO NEW_STATE FOUND").unwrap();
                encode::encode_uint(resp_msg, Codes::BadRequest as u64);
                return;
            }
        }

        let mut new_state = put_routine::Individual::new();
        ///Decoding individuals fron new state
        match put_routine::msgpack_to_individual(&mut Cursor::new(&new_state_res[0].str_data[..]), 
            &mut new_state) {
            Ok(_) => {}
            Err(err) => {
                ///If new state individual can not be decoded InternalServerError code is returned to cleint
                writeln!(stderr(), "@ERR DECODING NEW STATE {0}", err).unwrap();
                encode::encode_uint(resp_msg, Codes::InternalServerError as u64);
                return;
            }
        }

        if std::str::from_utf8(&new_state.uri[..]).unwrap() == "d:membership_owl__cfg_OntologyGroup" ||
            std::str::from_utf8(&new_state.uri[..]).unwrap() == "d:membership_owl__cfg_TTLResourcesGroup" {
                writeln!(stderr(), "FOUND INDIVIDUAL {0}", 
                    std::str::from_utf8(&new_state.uri[..]).unwrap());
        }
        
        let rdf_types: &Vec<put_routine::Resource>;
        ///Getting rdf:type resource
        match new_state.resources.get(&"rdf:type".to_string()) {
            Some(res) => rdf_types = res,
            _ => {
                ///Each individual must have rdf:type, if rdf:type not found BadRequest code is returned to client
                writeln!(stderr(), "@ERR NO RDF_TYPE_FOUND FOUND {0}", 
                    std::str::from_utf8(&new_state.uri[..]).unwrap()).unwrap();
                encode::encode_uint(resp_msg, Codes::BadRequest as u64);
                return;
            }
        }

        

        let mut tnt_rdf_types: Vec<Vec<u8>> = Vec::with_capacity(MAX_VECTOR_SIZE);
        ///Get saved rdf:types from tarantool if they already exist
        put_routine::get_rdf_types(&new_state.uri, &mut tnt_rdf_types, &conn);

        ///Compare rdf:type stored in Tarantool and in new_state
        ///If new_state contatins new rdf:type authorization computes on this rdf:type
        let mut is_update: bool = true;
       
        if tnt_rdf_types.len() > 0 && need_auth {
             ///Check if put operation is update or create
            ///Create: there are no rdf:types in tarantool, 
            ///or they are the different in tarantool and newstate.
            ///Update: rdf:types already exist in tarantool and same to new state
            for i in 0 .. rdf_types.len() {
                match tnt_rdf_types.iter().find(|&rdf_type| rdf_type.as_slice() == 
                    rdf_types[i].str_data.as_slice()) {
                    None => {
                        is_update = false;
                        let auth_result = authorization::compute_access(user_id, 
                            std::str::from_utf8(&rdf_types[i].str_data[..]).unwrap(), &conn, 
                                false, false, false).0;
                        
                        if (auth_result & authorization::ACCESS_CAN_CREATE) == 0 {
                            ///Is operation is create, user must be authorized for each new class,
                            // if authorization needed
                            encode::encode_uint(resp_msg, Codes::NotAuthorized as u64);
                            return;
                        } 
                    }
                    Some(_) => {}
                }
            }
        } else {
            is_update = false;
        }

        if is_update && need_auth {
            ///Is operation is update, user must be authorized for individual uri, if authorization needed
            let auth_result = authorization::compute_access(user_id, 
                &std::str::from_utf8(&new_state.uri[..]).unwrap(), &conn, false, false, false).0;

            if auth_result & authorization::ACCESS_CAN_UPDATE == 0 {
                encode::encode_uint(resp_msg, Codes::NotAuthorized as u64);
            }
        }

        if !is_update {
            ///If operation is create rdf:types stored to tarantool, or update if changed            
            put_routine::put_rdf_types(&new_state.uri, rdf_types, &conn);
        }

        ///Checks if one of rdf:types os account and stores account data into accounts space        
        for j in 0 .. rdf_types.len() {
            if std::str::from_utf8(&rdf_types[j].str_data[..]).unwrap() == "v-s:Account" {
                if std::str::from_utf8(&new_state.uri[..]).unwrap() == "cfg:GuestAccount" {
                    ///Do not need to save guest account
                    break;
                }
                let mut request = Vec::new();

                encode::encode_array(&mut request,2);
                let account_str;
                ///Get user login
                match new_state.resources.get("v-s:login") {
                    Some(vsl) => account_str = &vsl[0].str_data,
                    None => {
                        ///if login was not found BadRequest code returned to client
                        writeln!(stderr(), "@NO v-s:login FOUND IN INDIVIDUAL, ID=[{0}] ", 
                            std::str::from_utf8(&new_state.uri[..]).unwrap());
                        encode::encode_uint(resp_msg, Codes::BadRequest as u64);
                        return;
                    }
                }

                ///Encoding account into msgpack and store into tarantool
                encode::encode_string_bytes(&mut request, account_str);
                encode::encode_string_bytes(&mut request, &new_state.uri);
                unsafe {
                    let request_len = request.len() as isize;
                    let key_ptr_start = request.as_ptr() as *const i8;
                    let key_ptr_end = key_ptr_start.offset(request_len);
                    box_replace(conn.logins_space_id, key_ptr_start, key_ptr_end, 
                            &mut null_mut() as *mut *mut BoxTuple);
                }

                break;
            }
        }

        /// Unsafe call to tarantool function to store new_state or ticket
        unsafe {
            let request_len = new_state_res[0].str_data[..].len() as isize;
            let key_ptr_start = new_state_res[0].str_data[..].as_ptr() as *const i8;
            let key_ptr_end = key_ptr_start.offset(request_len);


            if std::str::from_utf8(&rdf_types[0].str_data[..]).unwrap() == "ticket:Ticket" {
                ///if individuals is ticket, if is ticket than store it into tickets space,
                ///else stroe in into individuals space
                box_replace(conn.tickets_space_id, key_ptr_start, key_ptr_end, 
                    &mut null_mut() as *mut *mut BoxTuple);
                /*writeln!(stderr(), "@STORE TICKET {0}", 
                    std::str::from_utf8(&new_state.uri[..]).unwrap()).unwrap();*/
                encode::encode_uint(resp_msg, Codes::Ok as u64);
                return
            } else {
                box_replace(conn.individuals_space_id, key_ptr_start, key_ptr_end, 
                    &mut null_mut() as *mut *mut BoxTuple);
            }
        }

        let prev_state_res: &Vec<put_routine::Resource>;
        let mut prev_state = put_routine::Individual::new();
        /// Gets prev_state if exists
        match individual.resources.get(&"prev_state".to_string()) {
            Some(res) => {
                prev_state_res = res;
                match put_routine::msgpack_to_individual(&mut Cursor::new(&prev_state_res[0].str_data[..]), 
                    &mut prev_state) {
                    Ok(_) => {}
                    Err(err) => {
                        writeln!(stderr(), "@ERR DECODING PREV_STATE {0}", err).unwrap();
                        encode::encode_uint(resp_msg, Codes::InternalServerError as u64);
                        return;
                    }
                }
            }
            _ => {}
        }

        /// Check if new_state is v-s:PermissionStatement of v-s:Membership
        /// and stores to appropriate state
        match std::str::from_utf8(&rdf_types[0].str_data[..]).unwrap() {
            "v-s:PermissionStatement" => {
                match put_routine::prepare_right_set(&prev_state, &new_state, "v-s:permissionObject", 
                    "v-s:permissionSubject", conn.permissions_space_id, conn.permissions_index_id) {
                    Err(err) => {
                        writeln!(stderr(), "@ERR PREPARE PEMISSION {0}: ", err).unwrap();
                        encode::encode_uint(resp_msg, Codes::InternalServerError as u64);
                        return;
                    }
                    _ => {}
                }
            }
            "v-s:Membership" => {
                match put_routine::prepare_right_set(&prev_state, &new_state, "v-s:resource", 
                    "v-s:memberOf", conn.memberships_space_id, conn.memberships_index_id) {
                    Err(err) => {
                        writeln!(stderr(), "@ERR PREPARE PEMISSION {0}: ", err).unwrap();
                        encode::encode_uint(resp_msg, Codes::InternalServerError as u64);
                        return;
                    }
                    _ => {}
                }
            }
            _ => {}
        }
        
        encode::encode_uint(resp_msg, Codes::Ok as u64)
    }
}

///Parses and handles get request according to docs
pub fn get(cursor: &mut Cursor<&[u8]>, arr_size: u64, need_auth:bool, resp_msg: &mut Vec<u8>) {
    let conn: TarantoolConnection;

    match connect_to_tarantool() {
        Err(err) => return super::fail(resp_msg, Codes::InternalServerError, err),
        Ok(c) => conn = c
    }

    let mut user_id_buf = Vec::default();
    let user_id: &str;
    /// Decodes user_id  from msgpack
    match decode::decode_string(cursor, &mut user_id_buf) {
        Err(err) => return super::fail(resp_msg, Codes::InternalServerError, err),
        Ok(_) => user_id = std::str::from_utf8(&user_id_buf).unwrap()
    }

    /// Encodes response array
    encode::encode_array(resp_msg, ((arr_size - 3) * 2 + 1) as u32);
    encode::encode_uint(resp_msg, Codes::Ok as u64);
    
    /// For each resource uri in array tries to get data from Tarantool
    for _ in 3 .. arr_size {
        let mut res_uri_buf = Vec::default();    
        let res_uri: &str;
        let mut request = Vec::new();

        match decode::decode_string(cursor, &mut res_uri_buf) {
            Err(err) => { super::fail(resp_msg, Codes::InternalServerError, err); continue; },
            Ok(_) => res_uri = std::str::from_utf8(&res_uri_buf).unwrap()
        }

        // writeln!(stderr(), "@GET user: {0} / res: {1}", user_id, res_uri);
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
        }

        
    }
}

///Parses and handles msgpack auth request according to docs
pub fn auth(cursor: &mut Cursor<&[u8]>, arr_size: u64, resp_msg: &mut Vec<u8>, aggregate_rights: bool, 
    aggregate_groups: bool) {
    let conn: TarantoolConnection;
    match connect_to_tarantool() {
        Err(err) => return super::fail(resp_msg, Codes::InternalServerError, err),
        Ok(c) => conn = c
    }

    let trace: bool;
    ///Decodes trace_auth prametr
    ///Trace param forces computing function to gather authorization process information to string
    match decode::decode_bool(cursor) {
        Err(err) => return super::fail(resp_msg, Codes::InternalServerError, err),
        Ok(t) => trace = t
    }

    let mut user_id_buf = Vec::default();
    let user_id: &str;
    ///Decodes user_id to authorization
    match decode::decode_string(cursor, &mut user_id_buf) {
        Err(err) => return super::fail(resp_msg, Codes::InternalServerError, err),
        Ok(_) => user_id = std::str::from_utf8(&user_id_buf).unwrap()
    }

    ///Encodes answer's msgpack array
    encode::encode_array(resp_msg, ((arr_size - 4) * 3 + 1) as u32);
    encode::encode_uint(resp_msg, Codes::Ok as u64);

    ///For each resource's uri performs authorization
    for _ in 4 .. arr_size {
     let mut res_uri_buf = Vec::default();    
        let res_uri: &str;
        let mut request = Vec::new();

        ///Decodes resource uri
        match decode::decode_string(cursor, &mut res_uri_buf) {
            Err(err) => { super::fail(resp_msg, Codes::InternalServerError, err); continue; },
            Ok(_) => res_uri = std::str::from_utf8(&res_uri_buf).unwrap()
        }

        encode::encode_array(&mut request, 1);
        encode::encode_string(&mut request, res_uri);
        ///Unsafe call to count to check if resource exists
        unsafe {
            let request_len = request.len() as isize;
            let key_ptr_start = request[..].as_ptr() as *const i8;
            let key_ptr_end = key_ptr_start.offset(request_len);
            let count = box_index_count(conn.individuals_space_id, conn.individuals_index_id,
                IteratorType::EQ as i32, key_ptr_start, key_ptr_end);
            if count == 0 {
                ///If resource wasn't found than NotFound code returned to user
                encode::encode_uint(resp_msg, Codes::NotFound as u64);
                encode::encode_uint(resp_msg, 0);
                encode::encode_nil(resp_msg);
                continue;
            }
        }

        /// Computes access
        let auth_result = authorization::compute_access(user_id, res_uri, &conn, aggregate_rights, 
            aggregate_groups, trace);
        /// Encode access into msgpack response
        encode::encode_uint(resp_msg, Codes::Ok as u64);
        encode::encode_uint(resp_msg, auth_result.0 as u64);
        
        if !(aggregate_rights || aggregate_groups) {
            ///If no aggregation needed, then encode nil
            encode::encode_nil(resp_msg);
        } else {
            /// If some aggregating function is needed, then encode aggregation response        
            encode::encode_string(resp_msg, &auth_result.1);
        }
    }
}

///Parses and handles msgpack put request according to docs
pub fn remove(cursor: &mut Cursor<&[u8]>, arr_size: u64, need_auth:bool, resp_msg: &mut Vec<u8>) {
    let conn: TarantoolConnection;

    match connect_to_tarantool() {
        Err(err) => return super::fail(resp_msg, Codes::InternalServerError, err),
        Ok(c) => conn = c
    }

    /// Decodes user_id
    let mut user_id_buf = Vec::default();
    let user_id: &str;
    match decode::decode_string(cursor, &mut user_id_buf) {
        Err(err) => return super::fail(resp_msg, Codes::InternalServerError, err),
        Ok(_) => {user_id = std::str::from_utf8(&user_id_buf).unwrap()}
    }

    /// Encodes response's array
    encode::encode_array(resp_msg, (arr_size - 3 + 1) as u32);
    encode::encode_uint(resp_msg, Codes::Ok as u64);

    /// Performs remove for each resource in array
    for _ in 3 .. arr_size {
        let mut res_uri_buf = Vec::default();    
        let res_uri: &str;
        let mut request = Vec::new();

        /// Decodes resource's uri
        match decode::decode_string(cursor, &mut res_uri_buf) {
            Err(err) => { super::fail(resp_msg, Codes::InternalServerError, err); continue; },
            Ok(_) => res_uri = std::str::from_utf8(&res_uri_buf).unwrap()
        }

        writeln!(stderr(), "@REMOVE {0}", res_uri);

        encode::encode_array(&mut request, 1);
        encode::encode_string(&mut request, res_uri);
        /// Unsafe call to delete in Tarantool
        unsafe {
            let request_len = request.len() as isize;
            let key_ptr_start = request[..].as_ptr() as *const i8;
            let key_ptr_end = key_ptr_start.offset(request_len);

            if need_auth {
                /// Does authorization if needed
                let auth_result = authorization::compute_access(user_id, res_uri, &conn, false, 
                false, false).0;

                if (auth_result & authorization::ACCESS_CAN_DELETE) == 0 {
                    writeln!(stderr(), "@NOT AUTH");
                    encode::encode_uint(resp_msg, Codes::NotAuthorized as u64);
                    encode::encode_nil(resp_msg);
                    continue;
                }
            }

            ///Removes individual, rdf:type, permission and membership from spaces
            box_delete(conn.individuals_space_id, conn.individuals_index_id, 
                key_ptr_start, key_ptr_end, &mut null_mut() as *mut *mut BoxTuple);
            box_delete(conn.rdf_types_space_id, conn.rdf_types_index_id, 
                key_ptr_start, key_ptr_end, &mut null_mut() as *mut *mut BoxTuple);
            box_delete(conn.permissions_space_id, conn.permissions_index_id, 
                key_ptr_start, key_ptr_end, &mut null_mut() as *mut *mut BoxTuple);
            box_delete(conn.memberships_space_id, conn.memberships_index_id, 
                key_ptr_start, key_ptr_end, &mut null_mut() as *mut *mut BoxTuple);
        }

        writeln!(stderr(), "@OK");
        encode::encode_uint(resp_msg, Codes::Ok as u64);        
    }
}

fn get_systicket_id(conn: &TarantoolConnection) -> String{
    let mut request = Vec::new();

    encode::encode_array(&mut request, 1);
    encode::encode_string(&mut request, "systicket");
    /// Unsafe calls to tarantool
    unsafe {
        let request_len = request.len() as isize;
        let key_ptr_start = request[..].as_ptr() as *const i8;
        let key_ptr_end = key_ptr_start.offset(request_len);
        
        let mut get_result: *mut BoxTuple = null_mut();
        /// Get tuple from tarantool if found it
        box_index_get(conn.tickets_space_id, conn.tickets_index_id,
                key_ptr_start, key_ptr_end, &mut get_result as *mut *mut BoxTuple);
        if get_result == null_mut() {
            // writeln!(stderr(), "@SYSTICKET NOT FOUND");
            ///If systicket not found return empty string
            return "".to_string();
        }
        
        let tuple_size = box_tuple_bsize(get_result);
        let mut tuple_buf: Vec<u8> = vec![0; tuple_size];
        box_tuple_to_buf(get_result, tuple_buf.as_mut_ptr() as *mut c_char, tuple_size);

        let mut systicket_indiv = put_routine::Individual::new();
        put_routine::msgpack_to_individual(&mut Cursor::new(&tuple_buf[..]), 
            &mut systicket_indiv).unwrap();
        
        /*writeln!(stderr(), "@SYSTICKET {0} FOUND", 
            std::str::from_utf8(&systicket_indiv.resources["ticket:id"][0].str_data[..]).unwrap());*/            
        /// Return string with ticket id
        return std::str::from_utf8(&systicket_indiv.resources["ticket:id"][0].str_data[..]).unwrap().to_string()
    }
}

//Parses msgpack get_ticket request and handles it according to docs
pub fn get_ticket(cursor: &mut Cursor<&[u8]>, arr_size: u64, resp_msg: &mut Vec<u8>) {
    // writeln!(stderr(), "@GET TICKET");
    let conn: TarantoolConnection;
    let mut user_id_buf = Vec::default();

    match connect_to_tarantool() {
        Err(err) => return super::fail(resp_msg, Codes::InternalServerError, err),
        Ok(c) => conn = c
    }

    /// Encode response array
    encode::encode_array(resp_msg, ((arr_size - 3) * 2 + 1) as u32);
    encode::encode_uint(resp_msg, Codes::Ok as u64);

    decode::decode_string(cursor, &mut user_id_buf).unwrap();
    for _ in 3 .. arr_size {
        /// Decodes ticket_id
        let mut ticket_id_buf = Vec::default();
        let mut ticket_id = "".to_string();
        let mut request = Vec::new();

        ///Decodes requested ticket id
        let ticket_id_type = decode::decode_type(cursor).unwrap();
        // writeln!(stderr(), "@ID TYPE {0}", decode::decode_type(cursor).unwrap() as u64);
        match ticket_id_type {
            decode::Type::StrObj => {
                match decode::decode_string(cursor, &mut ticket_id_buf) {
                    Err(err) => return super::fail(resp_msg, Codes::InternalServerError, err),
                    Ok(_) => ticket_id = std::str::from_utf8(&ticket_id_buf).unwrap().to_string()
                }
            }
            _ => decode::decode_nil(cursor).unwrap()
        }

        // writeln!(stderr(), "@TICKET ID {0}", ticket_id);
        
        if ticket_id == "systicket" {
            ticket_id = get_systicket_id(&conn);
        }

        encode::encode_array(&mut request, 1);
        encode::encode_string(&mut request, &ticket_id);
        /// Unsafe calls to tarantool
        unsafe {
            let request_len = request.len() as isize;
            let key_ptr_start = request[..].as_ptr() as *const i8;
            let key_ptr_end = key_ptr_start.offset(request_len);
            
            let mut get_result: *mut BoxTuple = null_mut();
            /// Get tuple from tarantool if found it
            box_index_get(conn.tickets_space_id, conn.tickets_index_id,
                    key_ptr_start, key_ptr_end, &mut get_result as *mut *mut BoxTuple);
            if get_result == null_mut() {
                encode::encode_uint(resp_msg, Codes::NotFound as u64);
                encode::encode_nil(resp_msg);
                // writeln!(stderr(), "@TICKET [{0}] NOT FOUND", ticket_id);
                continue;
            }
            
            ///If ticket was found in tarantool decodes it
            let tuple_size = box_tuple_bsize(get_result);
            let mut tuple_buf: Vec<u8> = vec![0; tuple_size];
            box_tuple_to_buf(get_result, tuple_buf.as_mut_ptr() as *mut c_char, tuple_size);

            ///Decodes ticket msgpack
            let mut ticket_indiv = put_routine::Individual::new();
            put_routine::msgpack_to_individual(&mut Cursor::new(&tuple_buf[..]), 
                &mut ticket_indiv).unwrap();
            
            // let now = time::get_time().sec;
            ///Check if ticket expired
            ///Parses string with date time
            let now = UTC::now().timestamp();
            let when_str = std::str::from_utf8(
                &ticket_indiv.resources.get("ticket:when").unwrap()[0].str_data[..]).unwrap();
            			
            let when = (when_str.split(".").collect::<Vec<&str>>()[0].to_string() + 
                "Z").parse::<DateTime<UTC>>().unwrap().timestamp();

            /*let ticket_end_time = when + std::str::from_utf8(&ticket_indiv.resources.
                get("ticket:duration").unwrap()[0].str_data[..]).unwrap().parse::<i64>().unwrap();*/
            ///Get ticket duration integer from string
            let duration_str = std::str::from_utf8(&ticket_indiv.resources.
                get("ticket:duration").unwrap()[0].str_data[..]).unwrap();
            // writeln!(stderr(), "@DURATION STR {0}", duration_str);
            let duration = duration_str.parse::<i64>().unwrap();
            // writeln!(stderr(), "@DURATION {0}", duration);
            let ticket_end_time = when + duration;

            // writeln!(stderr(), "@NOW {0} : END {1}", now, ticket_end_time);                            
            
            if now > ticket_end_time {
                ///If ticket is expired delete it from tarantool 
                ///and return TicketExpired code and nil to client    encode::encode_uint(resp_msg, Codes::TicketExpired as u64);
                encode::encode_nil(resp_msg);
                box_delete(conn.tickets_space_id, conn.tickets_index_id, 
                    key_ptr_start, key_ptr_end, &mut null_mut() as *mut *mut BoxTuple);
                // writeln!(stderr(), "@TICKET [{0}] EXPIRED", ticket_id);
                return;
            }
            
            ///If ticket is valid reutrn Ok code and ticket msgpack
            encode::encode_uint(resp_msg, Codes::Ok as u64);
            encode::encode_string_bytes(resp_msg, &tuple_buf);
            // writeln!(stderr(), "@TICKET STR {0}", std::str::from_utf8_unchecked(&tuple_buf[..]));
            // writeln!(stderr(), "@TICKET [{0}] FOUND", ticket_id);            
        }
    }
}