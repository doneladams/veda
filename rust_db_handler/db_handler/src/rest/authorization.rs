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

fn get_tuple(key: &str, group: &mut Group, space_id: u32, index_id: u32){
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
        group.buf = vec![0; tuple_size];
        box_tuple_to_buf(get_result, group.buf.as_mut_ptr() as *mut c_char, tuple_size);
    }
}

fn get_groups(uri: &str, groups: &mut Vec<Group>, conn: &super::TarantoolConnection) {
    let mut curr: i32 = 0;
    let mut gone_previous = false;
    
    groups.push(Group::new());
    groups[0].id = uri.to_string();
    get_tuple(uri, &mut groups[curr as usize], conn.memberships_space_id, conn.memberships_index_id);
    writeln!(stderr(), "@FIRST URI {0}", uri);
    if groups[curr as usize].buf.len() == 0 {  
        writeln!(stderr(), "@ZERO BUF");
        return;
    }

    while curr != -1{
        let got_next = false;
        let mut postion: u64 = 0;

        // let curr_group = groups.get_mut(curr_uri).unwrap();      
        
        if !gone_previous {
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
                let mut tmp: Vec<u8> = Vec::default();
                decode::decode_string(&mut cursor, &mut tmp);
                postion = cursor.position();                
                std::str::from_utf8(&tmp[..]).unwrap().to_string()
            };
        
            writeln!(stderr(), "@GROUP URI {0} NELEMS {1}", groups[curr as usize].id, 
                groups[curr as usize].nelems);
        }

        gone_previous = false;

        if !got_next {
            curr = groups[curr as usize].parent;
            gone_previous = true;
        }
    }
    /*
	// fprintf(stderr, "REQUEST URI %s\n", uri);
	while (curr != -1) {
		int got_next = 0;
		int i;
		uint32_t len;
		const char *tmp;


		gone_previous = 0;
		
		for (; rights[curr].i < rights[curr].nelems - 1; rights[curr].i += 2) {
			int32_t next;
			uint8_t right_access;

			if (rights_count == MAX_RIGHTS) {
				fprintf(stderr, "@RIGHTS MAX LIMIT REACHED\n");
				return -1;
			}
			next = rights_count++;
			// fprintf(stderr, "\ti=%d nelems=%d\n", rights[curr].i, rights[curr].nelems - 1);
			// fprintf(stderr, "\ttry decode new node\n");
			tmp = mp_decode_str(&rights[curr].buf, &len);
			if (len > MAX_URI_LEN) {
				fprintf(stderr, "@LEN IS GREATER THAN MAX_URI_LEN");
				return -1;
			}
			memcpy(rights[next].id + 1, tmp, len);
			rights[next].id[0] = MEMBERSHIP_PREFIX;
			right_access = mp_decode_uint(&rights[curr].buf);
			// fprintf (stderr, "\tnext uri %s len=%d\n", rights[next].id, len);
			rights[next].access = rights[curr].access & right_access;
			rights[next].id[len + 1] = '\0';
			rights[next].id_len = len + 1;
			/*fprintf (stderr, "\tnext uri %s\n", rights[next].id);
			fprintf (stderr, "\tcurr=%u next=%u right_access=%u\n", rights[curr].access, 
				rights[next].access, right_access);*/
			for (i = 0; i < rights_count - 1; i++)
				if (strcmp(rights[i].id, rights[next].id) == 0)
					break;	

			if (i < rights_count - 1) {
				rights_count--;
				continue;
			}

			rights[next].parent = curr;

			// fprintf (stderr, "\tnew uri %s\n", rights[next].id);
			rights[next].buf = rights[next].buf_start;
			// fprintf(stderr, "REQUEST URI %s\n", rights[next].id);
			get_tuple_res = get_tuple(rights[next].id, rights[next].id_len, 
				(char *)rights[next].buf);
			if (get_tuple_res == 0)
				continue;
			else if (get_tuple_res  < 0)
				return -1;
			
			rights[curr].i += 2;
			curr = next;
			got_next = 1;
			break;
		}
		if (!got_next) {
			curr = rights[curr].parent;
			gone_previous = 1;
		}
	}*/
}

#[allow(dead_code)]
pub fn compute_access(user_id: &str, res_uri: &str, conn: &super::TarantoolConnection) -> 
    Result<u8, String> {
    let mut object_groups: Vec<Group> = Vec::default();
    let mut subject_groups: Vec<Group> = Vec::default();

    writeln!(stderr(), "@COMPUTE ACCESS");
    get_groups(&("M".to_string() + user_id), &mut object_groups, &conn);
    return Ok(15);
}