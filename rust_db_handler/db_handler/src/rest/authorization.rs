extern crate core;
extern crate rmp_bind;

use std;
use std::collections::HashMap;
use std::io::{ Cursor, Write, stderr };
use std::os::raw::c_char;
use std::ptr::null_mut;
use rmp_bind:: { decode, encode };

include!("../../module.rs");

pub static ACCESS_CAN_CREATE: u8 = 1 << 0;
pub static ACCESS_CAN_READ: u8 = 1 << 1;
pub static ACCESS_CAN_UPDATE: u8 = 1 << 2;
pub static ACCESS_CAN_DELETE: u8 = 1 << 3;
pub static ACCESS_CAN_NOT_CREATE: u8 = 1 << 4;
pub static ACCESS_CAN_NOT_READ: u8 = 1 << 5;
pub static ACCESS_CAN_NOT_UPDATE: u8 = 1 << 6;
pub static ACCESS_CAN_NOT_DELETE: u8 = 1 << 7;
pub static DEFAULT_ACCESS: u8 = 15;

struct Group {
    id: String,
    parent: i32,
    buf: Vec<u8>,
    position: u64,
    i: u64,
    nelems: u64,
    access: u8
}

impl Group {
    fn new() -> Group {
        return Group { id: "".to_string(), parent: -1, buf: Vec::new(), position: 0, i: 0,  
            nelems: 0, access: DEFAULT_ACCESS };
    }
}

fn get_tuple(key: &str, buf: &mut Vec<u8>, space_id: u32, index_id: u32){
    let mut request = Vec::new();
    encode::encode_array(&mut request, 1);
    encode::encode_string(&mut request, key);

    unsafe {
        let request_len = request.len() as isize;
        let key_ptr_start = request[..].as_ptr() as *const i8;
        let key_ptr_end = key_ptr_start.offset(request_len);

        let mut get_result: *mut BoxTuple = null_mut();
        let get_code = box_index_get(space_id, index_id, key_ptr_start, key_ptr_end, 
            &mut get_result as *mut *mut BoxTuple);
        
        if get_result == null_mut() {
            return;
        }
        
        let tuple_size = box_tuple_bsize(get_result);
        *buf = vec![0; tuple_size];
        box_tuple_to_buf(get_result, buf.as_mut_ptr() as *mut c_char, tuple_size);
    }
}

fn get_groups(uri: &str, groups: &mut Vec<Group>, conn: &super::TarantoolConnection) {
    let mut curr: i32 = 0;
    let mut gone_previous = false;
    
    groups.push(Group::new());
    groups[0].id = uri.to_string();
    get_tuple(uri, &mut groups[curr as usize].buf, conn.memberships_space_id, conn.memberships_index_id);
    // writeln!(stderr(), "@FIRST URI {0}", uri);
    if groups[curr as usize].buf.len() == 0 {  
        // writeln!(stderr(), "@ZERO BUF");
        return;
    }

    while curr != -1{
        let mut got_next = false;
        // writeln!(stderr(), "@RESET POSITION");
        let mut postion: u64 = groups[curr as usize].position;
        // writeln!(stderr(), "@CURR {0}", curr);
        if !gone_previous {
            // writeln!(stderr(), "@ASSIGN I");
            groups[curr as usize].i = 1;
            // writeln!(stderr(), "@GET NELEMS");
            groups[curr as usize].nelems = {
                let mut cursor: Cursor<&[u8]> = Cursor::new(&groups[curr as usize].buf[..]);
                let arr_size = decode::decode_array(&mut cursor).unwrap();
                postion = cursor.position();
                arr_size
            };
            // writeln!(stderr(), "@GROUP NELEMS {0}", groups[curr as usize].nelems);
            groups[curr as usize].id = {
                let mut tmp: Vec<u8> = Vec::default();
                let mut cursor: Cursor<&[u8]> = Cursor::new(&groups[curr as usize].buf[..]);
                cursor.set_position(postion);
                let mut tmp: Vec<u8> = Vec::default();
                decode::decode_string(&mut cursor, &mut tmp).unwrap();
                postion = cursor.position();                
                std::str::from_utf8(&tmp[..]).unwrap().to_string()
            };
        
            // writeln!(stderr(), "@GROUP URI {0}", groups[curr as usize].id);
        }

        gone_previous = false;
        // writeln!(stderr(), "@START {0}", curr);
        // writeln!(stderr(), "@{0} FROM {1}", groups[curr as usize].i, groups[curr as usize].nelems);
        while groups[curr as usize].i < groups[curr as usize].nelems {
            groups[curr as usize].i += 2;
            // writeln!(stderr(), "\t@BECAME {0} FROM {1}", groups[curr as usize].i, groups[curr as usize].nelems);

            let mut next_group = Group::new();
            let next = groups.len();
            let id = {
                let mut tmp: Vec<u8> = Vec::default();
                let mut cursor: Cursor<&[u8]> = Cursor::new(&groups[curr as usize].buf[..]);
                cursor.set_position(postion);
                let mut tmp: Vec<u8> = Vec::default();
                decode::decode_string(&mut cursor, &mut tmp).unwrap();
                postion = cursor.position();                
                std::str::from_utf8(&tmp[..]).unwrap().to_string()
            };
            next_group.access = {
                let mut cursor: Cursor<&[u8]> = Cursor::new(&groups[curr as usize].buf[..]);
                cursor.set_position(postion);
                let mut tmp = decode::decode_uint(&mut cursor).unwrap();
                postion = cursor.position();  
                tmp as u8
            };
            // writeln!(stderr(), "\t@NEXT GROUP ID {0} ACCESS {1}", next_group.id, next_group.access);
            next_group.access &= groups[curr as usize].access;
            let mut found = false;
            for i in 0 .. groups.len() {
                if groups[i].id == next_group.id {
                    found = true;
                    break;
                }
            }
            // writeln!(stderr(), "\t@FINISH CYCLE FIND AND FOUND {0}", found);
            if found {
                continue;
            }

            next_group.parent = curr;
            get_tuple(&id, &mut next_group.buf, conn.memberships_space_id, conn.memberships_index_id);
            groups.push(next_group);
            groups[curr as usize].position = postion;
            if groups[next as usize].buf.len() == 0 {
                groups[next as usize].id = id;
                continue;
            }
            curr = groups.len() as i32 - 1;
            

            got_next = true;
            break;
        }

        if !got_next {
            // writeln!(stderr(), "\t@NO NEXT FOR {0}", curr);            
            curr = groups[curr as usize].parent;
            // writeln!(stderr(), "\t@NEW CURR {0}", curr);
            gone_previous = true;
            if curr != -1 {
                // writeln!(stderr(), "@GO BACK TO {0} {1}", groups[curr as usize].id, curr);
            }
        }
    }
}

#[allow(dead_code)]
pub fn compute_access(user_id: &str, res_uri: &str, conn: &super::TarantoolConnection) -> u8{
    let mut result_access:u8 = 0;
    let mut object_groups: Vec<Group> = Vec::default();
    let mut subject_groups: Vec<Group> = Vec::default();
    let access_arr: [u8; 4] = [ ACCESS_CAN_CREATE, ACCESS_CAN_READ, ACCESS_CAN_UPDATE, 
	    ACCESS_CAN_DELETE ];

    // writeln!(stderr(), "@COMPUTE ACCESS");
    get_groups(user_id, &mut subject_groups, &conn);
    get_groups(res_uri, &mut object_groups, &conn);

    
    let mut extra_group = Group::new();
    extra_group.id = "v-s:AllResourcesGroup".to_string();
    object_groups.push(extra_group);

/*    writeln!(stderr(), "@OBJECT-------------------------------------------------");
    for i in 0 .. object_groups.len() {
        writeln!(stderr(), "\t {0} {1}", object_groups[i].id, object_groups[i].access);
    }    
    writeln!(stderr(), "--------------------------------------------------------");

    writeln!(stderr(), "@SUBJECT-------------------------------------------------");
    for i in 0 .. subject_groups.len() {
        writeln!(stderr(), "\t {0} {1}", subject_groups[i].id, subject_groups[i].access);
    }    
    writeln!(stderr(), "--------------------------------------------------------");
*/
    // writeln!(stderr(), "!!!@PERMISSIONS");
    for i in 0 .. object_groups.len() {
        let mut perm_buf: Vec<u8> = Vec::default();
        let object_access = object_groups[i].access;
        get_tuple(&object_groups[i].id, &mut perm_buf, conn.permissions_space_id, conn.permissions_index_id);
        if perm_buf.len() == 0 {
            continue;
        }
        let mut cursor:Cursor<&[u8]> = Cursor::new(&perm_buf[..]);
        let nperms = decode::decode_array(&mut cursor).unwrap();
        // writeln!(stderr(), "@NPERMS {0} FOR {1}", nperms, object_groups[i].id);
        decode::decode_string(&mut cursor, &mut Vec::default());
        let mut j = 1;
        while j < nperms {
            j += 2;
            let perm_uri = {
                let mut tmp: Vec<u8> = Vec::default();
                decode::decode_string(&mut cursor, &mut tmp);
                std::str::from_utf8(&tmp[..]).unwrap().to_string()
            };

            let mut perm_access = decode::decode_uint(&mut cursor).unwrap() as u8;
            // writeln!(stderr(), "\t@PERM {0} WITH ACCESS {1}", perm_uri, perm_access);
            perm_access = (((perm_access & 0xF0) >> 4) ^ 0x0F) & perm_access;
            let mut idx = 0;
            while idx < subject_groups.len() {
                if (perm_uri == subject_groups[idx].id) {
                    break;
                }
                idx += 1;
            }

            if idx < subject_groups.len() {
                // writeln!(stderr(), "\t\t@FOUND {0}", perm_uri);
                for k in 0 .. 4 {
                    if (access_arr[k] & object_access) > 0 {
                        result_access |= access_arr[k] & perm_access;
                    }
                }
            }
        }
    }

    // writeln!(stderr(), "@RESULT ACCESS {0} USER {1} RES {2}", result_access, user_id, res_uri);
    return result_access;
}