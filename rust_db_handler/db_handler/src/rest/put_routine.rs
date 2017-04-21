extern crate core;
extern crate rmp_bind;

use std::iter::Map;
use std::cmp::Eq;
use std::io::{ Write, stderr, Cursor };
use rmp_bind:: { decode, encode };

#[derive(PartialEq, Eq)]
enum ResourceType {
    Uri = 1,
    Str = 2,
    Integer = 4,
    Datetime = 8,
    Decimal = 32,
    Boolean = 64
}

#[derive(PartialEq, Eq)]
enum Lang {
    LangNone = 0,
    LangRu  = 1,
    LangEn   = 2
}

#[derive(PartialEq, Eq)]
struct Resource {
    res_type: ResourceType,
    lang: Lang,
    str_data: String,
    bool_data: bool,
    long_data: i64,
    decimal_mantissa_data: i64,
    decimal_exponent_data: i64,
}

struct Individual<'i> {
    uri: &'i str,
    uri_buf: Vec<u8>,
    resources: Map<String, Vec<Resource>>    
}



fn resources_equeal(r1: &Resource, r2: &Resource) -> bool {
    if r1.res_type != r2.res_type {
        return false;
    }

    match r1.res_type {
        ResourceType::Uri => {
            if r1.str_data == r2.str_data { 
                return true; 
            }
        },
        ResourceType::Str => { 
            if r1.str_data == r2.str_data && r1.lang == r2.lang { 
                return true; 
            }
        },
        ResourceType::Integer | ResourceType::Datetime => { 
            if r1.long_data == r2.long_data { 
                return true 
            }
        },
        ResourceType::Decimal => {
            if r1.decimal_exponent_data == r2.decimal_exponent_data &&
                r1.decimal_mantissa_data == r2.decimal_mantissa_data { 
                return true 
            }
        },
        ResourceType::Boolean => { 
            if r1.bool_data == r2.bool_data {
                return true;
            }
        },
    }

   return false;
}

