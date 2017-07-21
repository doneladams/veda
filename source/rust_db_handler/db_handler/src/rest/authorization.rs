/// This module gives function to check access of user to individual

extern crate core;
extern crate rmp_bind;
extern crate serde_json;

use std;
use std::collections::HashMap;
use std::io::{ Cursor, Write, stderr };
use std::os::raw::c_char;
use std::ptr::null_mut;
use rmp_bind:: { decode, encode };

include!("../../module.rs");

const MAX_VECTOR_SIZE: usize = 150;

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

/// Get tuple with key form Tarantool if exists
fn get_tuple(key: &str, buf: &mut Vec<u8>, space_id: u32, index_id: u32){
    let mut request = Vec::new();
    encode::encode_array(&mut request, 1);
    encode::encode_string(&mut request, key);

    unsafe {
        let request_len = request.len() as isize;
        let key_ptr_start = request[..].as_ptr() as *const i8;
        let key_ptr_end = key_ptr_start.offset(request_len);

        let mut get_result: *mut BoxTuple = null_mut();
        box_index_get(space_id, index_id, key_ptr_start, key_ptr_end, 
            &mut get_result as *mut *mut BoxTuple);
        
        if get_result == null_mut() {
            return;
        }
        
        let tuple_size = box_tuple_bsize(get_result);
        *buf = vec![0; tuple_size];
        box_tuple_to_buf(get_result, buf.as_mut_ptr() as *mut c_char, tuple_size);
    }
}

fn access_to_string(access: u8) -> String {
    format!("{0} {1} {2} {3}",
        if access & ACCESS_CAN_CREATE > 0 {"C"} else {""},
        if access & ACCESS_CAN_READ > 0 {"R"} else {""},
        if access & ACCESS_CAN_UPDATE > 0 {"U"} else {""},
        if access & ACCESS_CAN_DELETE > 0 {"D"} else {""})
}

/// Finds tree of groups for uri (object or subject)
fn get_groups(uri: &str, groups: &mut Vec<Group>, conn: &super::TarantoolConnection, 
    str_number: &mut  u32, trace: bool) {
    let mut curr: i32 = 0;
    let mut gone_previous = false;

    let mut indent = "\t".to_string();
    let mut level = 0;
    
    /// Creates root group and saves it
    groups.push(Group::new());
    groups[0].id = uri.to_string();
    get_tuple(uri, &mut groups[curr as usize].buf, conn.memberships_space_id, conn.memberships_index_id);
    if groups[curr as usize].buf.len() == 0 {  
        /// If no child nodes than return
        return;
    }

    /// Iterative computation of tree while is not out of root
    while curr != -1 {
        let mut got_next = false;
        /// Restores position of reader in msgpack buffer
        /// and check if found a new root
        let mut postion: u64 = groups[curr as usize].position;
        if !gone_previous {
            groups[curr as usize].i = 1;
            groups[curr as usize].nelems = {
                let mut cursor: Cursor<&[u8]> = Cursor::new(&groups[curr as usize].buf[..]);
                let arr_size = decode::decode_array(&mut cursor).unwrap();
                postion = cursor.position();
                arr_size
            };
            groups[curr as usize].id = {
                let mut tmp: Vec<u8> = Vec::default();
                let mut cursor: Cursor<&[u8]> = Cursor::new(&groups[curr as usize].buf[..]);
                cursor.set_position(postion);
                decode::decode_string(&mut cursor, &mut tmp).unwrap();
                postion = cursor.position();                
                std::str::from_utf8(&tmp[..]).unwrap().to_string()
            };
        }

        gone_previous = false;
        while groups[curr as usize].i < groups[curr as usize].nelems {
            groups[curr as usize].i += 2;

            /// Creates new group and decodes its id
            let mut next_group = Group::new();
            let next = groups.len();
            let id = {
                let mut tmp: Vec<u8> = Vec::default();
                let mut cursor: Cursor<&[u8]> = Cursor::new(&groups[curr as usize].buf[..]);
                cursor.set_position(postion);
                decode::decode_string(&mut cursor, &mut tmp).unwrap();
                postion = cursor.position();                
                std::str::from_utf8(&tmp[..]).unwrap().to_string()
            };
            next_group.access = {
                /// Decodes right set access and computes group access according to parent node
                let mut cursor: Cursor<&[u8]> = Cursor::new(&groups[curr as usize].buf[..]);
                cursor.set_position(postion);
                let tmp = decode::decode_uint(&mut cursor).unwrap();
                postion = cursor.position();  
                tmp as u8 & groups[curr as usize].access
            };

            let mut found = false;
            /// Checks for cycle in tree with new node
            for i in 0 .. groups.len() {
                if next_group.access ==  groups[i].access && id == groups[i].id {
                    found = true;
                    if (trace) {
                        writeln!(stderr(), "{0} {1}({2})GROUP [{3}].access={4} SKIP, ALREADY ADDED",
                            str_number, indent, level, id, 
                            access_to_string(next_group.access)).unwrap();
                        *str_number += 1;
                    }
                    break;
                }
            }

            if found {
                continue;
            }

            next_group.parent = curr;
            /// Get msgpack buffer if exists and save to vector or just continue
            get_tuple(&id, &mut next_group.buf, conn.memberships_space_id, conn.memberships_index_id);
            if (trace) {
                writeln!(stderr(), "{0} {1}({2})GROUP[{3}] {4} -> {5}", str_number, indent, level,
                    id, access_to_string(groups[curr as usize].access), 
                    access_to_string(next_group.access)).unwrap();
                *str_number += 1;
            }
            groups.push(next_group);
            groups[curr as usize].position = postion;
            if groups[next as usize].buf.len() == 0 {
                groups[next as usize].id = id;
                continue;
            }

            curr = groups.len() as i32 - 1;
            got_next = true;
            if trace {
                level += 1;
                indent = indent.to_string() + "\t";
            }
            break;
        }

        if !got_next {
            curr = groups[curr as usize].parent;
            gone_previous = true;
            
            if trace {
                indent = std::str::from_utf8(&indent.as_bytes()[..level]).unwrap().to_string();
                level -= 1;
            }
        }
    }
}

fn prepare_group(groups: &mut Vec<Group>, prepared_groups: &mut Vec<Group>) {
     let mut data: HashMap<String, u8> = HashMap::new();

     for i in 0 .. groups.len() {
         let mut prev_access = 0;
         match data.get(&groups[i].id) {
             Some(a) => prev_access = *a,
             _ => {}
         }

         data.insert(groups[i].id.clone(), prev_access | groups[i].access);
     }

     for (id, access) in &data {
        let mut group = Group::new();
        group.id = id.to_string();
        group.access = *access;
        prepared_groups.push(group);
    }
}

/// Function to compute access
pub fn compute_access(user_id: &str, res_uri: &str, conn: &super::TarantoolConnection, 
    aggregate_rights: bool, aggregate_groups: bool, trace: bool) -> (u8, String) {
    let mut aggregated_value = "".to_string();
    let mut result_access:u8 = 0;
    let mut object_groups_unprepared: Vec<Group> = Vec::with_capacity(MAX_VECTOR_SIZE);
    let mut subject_groups_unprepared: Vec<Group> = Vec::with_capacity(MAX_VECTOR_SIZE);
    let mut object_groups: Vec<Group> = Vec::with_capacity(MAX_VECTOR_SIZE);
    let mut subject_groups: Vec<Group> = Vec::with_capacity(MAX_VECTOR_SIZE);
    let access_arr: [u8; 4] = [ ACCESS_CAN_CREATE, ACCESS_CAN_READ, ACCESS_CAN_UPDATE, 
	    ACCESS_CAN_DELETE ];

    let mut str_number = 2;

    if trace {
        writeln!(stderr(), "0 authorize uri={0}, user={1}, request_access=C R U D", 
            res_uri, user_id).unwrap();
        writeln!(stderr(), "1 user_uri={0}", user_id).unwrap();
    }

    /*get_groups(user_id, &mut subject_groups , &conn);
    get_groups(res_uri, &mut object_groups, &conn);*/
    if trace {
        writeln!(stderr(), "{0} READ OBJECT GROUPS", str_number).unwrap();
        str_number += 1;
    }
    /// Gets groups of subject 
    get_groups(res_uri, &mut object_groups_unprepared, &conn, &mut str_number, trace);
    ///Join repeating object groups with different rights
    prepare_group(&mut object_groups_unprepared, &mut object_groups);
    
    if trace {
        let mut object_groups_string = "object_groups=".to_string();

        for i in 0 .. object_groups.len() {
            object_groups_string = format!("{0}({1}, {2}), ", object_groups_string, 
                object_groups[i].id, access_to_string(object_groups[i].access));
        }

        writeln!(stderr(), "{0} {1}", str_number, object_groups_string).unwrap();
        str_number += 1;

        writeln!(stderr(), "{0}", str_number).unwrap();
        str_number += 1;
        writeln!(stderr(), "{0} READ SUBJECT GROUPS", str_number).unwrap();
        str_number += 1;
    }

    /// Gets groups of object 
    get_groups(user_id, &mut subject_groups_unprepared, &conn, &mut str_number, trace);
    ///Join repeating subject groups with different rights
    prepare_group(&mut subject_groups_unprepared, &mut subject_groups);
    
    if trace {
        let mut subject_groups_string = "subject_groups=".to_string();

        for i in 0 .. subject_groups.len() {
            subject_groups_string = format!("{0}({1}, {2}), ", subject_groups_string, 
                subject_groups[i].id, access_to_string(subject_groups[i].access));
        }

        writeln!(stderr(), "{0} {1}", str_number, subject_groups_string).unwrap();
        str_number += 1;

        writeln!(stderr(), "{0}", str_number).unwrap();
        str_number += 1;
    }

    /// Add extra group which is not stored in space
    let mut extra_group = Group::new();
    extra_group.id = "v-s:AllResourcesGroup".to_string();
    object_groups.push(extra_group);

    /// Computes access in cycle
    let mut triplets: Vec<(String, String, u8)> = Vec::with_capacity(MAX_VECTOR_SIZE); 
    
    for i in 0 .. object_groups.len() {
        let mut perm_buf: Vec<u8> = Vec::default();
        let object_access = object_groups[i].access;
        /// Gets permission right set buffer
        get_tuple(&object_groups[i].id, &mut perm_buf, conn.permissions_space_id, conn.permissions_index_id);
        if perm_buf.len() == 0 {
            continue;
        }
        let mut cursor:Cursor<&[u8]> = Cursor::new(&perm_buf[..]);
        let nperms = decode::decode_array(&mut cursor).unwrap();
        decode::decode_string(&mut cursor, &mut Vec::default()).unwrap();
        let mut j = 1;
        /// For each permission to object tries to find it in subjects
        while j < nperms {
            j += 2;
            let perm_uri = {
                let mut tmp: Vec<u8> = Vec::default();
                decode::decode_string(&mut cursor, &mut tmp).unwrap();
                std::str::from_utf8(&tmp[..]).unwrap().to_string()
            };

            let mut perm_access = decode::decode_uint(&mut cursor).unwrap() as u8;
            perm_access = (((perm_access & 0xF0) >> 4) ^ 0x0F) & perm_access;
            let mut idx = 0;
            while idx < subject_groups.len() {
                if perm_uri == subject_groups[idx].id {
                    break;
                }
                idx += 1;
            }

            if idx < subject_groups.len() {
                // If found, check access of subject in group to object
                for k in 0 .. 4 {
                    if (access_arr[k] & object_access) > 0 {
                        result_access |= access_arr[k] & perm_access;
                        if (access_arr[k] & perm_access) > 0 && aggregate_rights {
                            triplets.push((subject_groups[idx].id.clone(), object_groups[i].id.clone(), 
                                access_arr[k]));
                        }
                    }
                }

                
            }
        }
    }

    if aggregate_rights {
        let mut jsons: Vec<serde_json::Value> = Vec::with_capacity(MAX_VECTOR_SIZE);     
        for i in 0 .. triplets.len() {
            let right_resource: serde_json::Value;

            if triplets[i].2 == ACCESS_CAN_CREATE {
                right_resource = json!({
                    "@":"_",
                    "rdf:type":[{"type":"Uri","data":"v-s:PermissionStatement"}],
                    "v-s:permissionSubject":[{"type":"Uri","data":triplets[i].0}],
                    "v-s:permissionObject":[{"type":"Uri","data":triplets[i].1}],
                    "v-s:canCreate":[{"type":"Boolean","data":true}]
                });
            } else if triplets[i].2 == ACCESS_CAN_READ {
                 right_resource = json!({
                    "@":"_",
                    "rdf:type":[{"type":"Uri","data":"v-s:PermissionStatement"}],
                    "v-s:permissionSubject":[{"type":"Uri","data":triplets[i].0}],
                    "v-s:permissionObject":[{"type":"Uri","data":triplets[i].1}],
                    "v-s:canRead":[{"type":"Boolean","data":true}]
                });
            } else if triplets[i].2 == ACCESS_CAN_UPDATE {
                right_resource = json!({
                    "@":"_",
                    "rdf:type":[{"type":"Uri","data":"v-s:PermissionStatement"}],
                    "v-s:permissionSubject":[{"type":"Uri","data":triplets[i].0}],
                    "v-s:permissionObject":[{"type":"Uri","data":triplets[i].1}],
                    "v-s:canUpdate":[{"type":"Boolean","data":true}]
                });
            } else {
                right_resource = json!({
                    "@":"_",
                    "rdf:type":[{"type":"Uri","data":"v-s:PermissionStatement"}],
                    "v-s:permissionSubject":[{"type":"Uri","data":triplets[i].0}],
                    "v-s:permissionObject":[{"type":"Uri","data":triplets[i].1}],
                    "v-s:canDelete":[{"type":"Boolean","data":true}]
                });
            }
            
            jsons.push(right_resource);
        }

        aggregated_value = json!(jsons.as_slice()).to_string();
    } else if aggregate_groups {
        let mut jsons: Vec<serde_json::Value> = Vec::with_capacity(MAX_VECTOR_SIZE);
        for i in 0 .. object_groups.len() {
            jsons.push(json!({"type":"Uri","data":object_groups[i].id}));
        }

        aggregated_value = json!({
            "@":"_",
            "rdf:type":[{"type":"Uri","data":"v-s:Membership"}],
            "v-s:resource":[{"type":"Uri","data": res_uri}],
            "v-s:memberOf": jsons
        }).to_string();
    }

    if trace {
        // authorize test13:8b78wyvvz543obosoaj4ir6u, request=C R U D , answer=[C R U D ]
        writeln!(stderr(), "{0} authorize {1}, request=C R U D, answer=[{2}]", str_number, res_uri,
            access_to_string(result_access)).unwrap();
    }

    return (result_access, aggregated_value);
}