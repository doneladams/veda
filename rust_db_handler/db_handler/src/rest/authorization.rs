

pub static ACCESS_CAN_CREATE: u8 = 1 << 0;
pub static ACCESS_CAN_READ: u8 = 1 << 1;
pub static ACCESS_CAN_UPDATE: u8 = 1 << 2;
pub static ACCESS_CAN_DELETE: u8 = 1 << 3;
pub static ACCESS_CAN_NOT_CREATE: u8 = 1 << 4;
pub static ACCESS_CAN_NOT_READ: u8 = 1 << 5;
pub static ACCESS_CAN_NOT_UPDATE: u8 = 1 << 6;
pub static ACCESS_CAN_NOT_DELETE: u8 = 1 << 7;

#[allow(dead_code)]
pub fn compute_access(user_id: &str, res_uri: &str, acl_space_id: u32, acl_index_id: u32) -> 
    Result<u8, String> {
    return Ok(15);
}