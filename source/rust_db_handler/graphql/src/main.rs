#[macro_use] extern crate juniper;
#[macro_use] extern crate serde_json;
extern crate rmp_bind;
extern crate iron;
extern crate chrono;

use rmp_bind::{ decode, encode };
use std::collections::HashMap;
use std::io::stderr;
use std::io::Write;
use std::io::Read;
use std::io::Cursor;
use juniper::Context;
use iron::prelude::*;
use iron::*;
use iron::request::*;
use serde_json::{Value, Error};
use chrono::prelude::*;
use chrono::*;

mod connector;

const MAX_VECTOR_SIZE: usize = 150;

#[derive(PartialEq, Eq, Copy)]
enum ResourceType {
    Uri = 1,
    Str = 2,
    Integer = 4,
    Datetime = 8,
    Decimal = 32,
    Boolean = 64
}

impl ResourceType {
    pub fn to_string(&self) -> String {
        match *self {
            ResourceType::Uri => return "Uri".to_string(),
            ResourceType::Str => return "String".to_string(),
            ResourceType::Integer => return "Integer".to_string(),
            ResourceType::Datetime => return "Datetime".to_string(),
            ResourceType::Decimal => return "Decimal".to_string(),
            ResourceType::Boolean => return "Boolean".to_string()
        }
    }
}

#[derive(PartialEq, Eq, Copy)]
enum Lang {
    LangNone = 0,
    LangRu  = 1,
    LangEn   = 2
}

#[derive(PartialEq, Eq)]
pub struct Resource {
    res_type: ResourceType,
    lang: Lang,
    pub str_data: Vec<u8>,
    bool_data: bool,
    pub long_data: i64,
    decimal_mantissa_data: i64,
    decimal_exponent_data: i64,
}

impl Clone for ResourceType {
    fn clone(&self) -> ResourceType {
        *self
    }
}

impl Clone for Lang {
    fn clone(&self) -> Lang {
        *self
    }
}

pub struct Individual {
    pub uri: Vec<u8>,
    pub resources: HashMap<String, Vec<Resource>>    
}

impl Resource {
    pub fn new() -> Resource {
        return Resource { res_type: ResourceType::Uri, lang: Lang::LangNone, str_data: Vec::default(),
            bool_data: false, long_data: 0, decimal_mantissa_data: 0, decimal_exponent_data: 0};
    }

    fn clone(&self) -> Resource {
        return Resource { res_type: self.res_type, lang: self.lang, str_data: self.str_data.clone(),
            bool_data: self.bool_data, long_data: self.long_data, 
            decimal_mantissa_data: self.decimal_mantissa_data, decimal_exponent_data: 
            self.decimal_exponent_data};
    }
}

impl Individual {
    pub fn new() -> Individual {
        return Individual { uri: Vec::default(), resources: HashMap::new() };
    }
}

impl Lang {
    fn from_u64(val: u64) -> Lang {
        match val {
            1 => Lang::LangRu,
            2 => Lang::LangEn,
            _ => Lang::LangNone
        }
    }

    fn to_string(&self) -> String {
        match *self {
            Lang::LangRu => return "RU".to_string(),
            Lang::LangEn => return "EN".to_string(),
            Lang::LangNone => return "NONE".to_string()
        }
    } 
}

pub struct IndividualDatabase {
    individuals: HashMap<String, Individual>
}

/// Converts msgpach to individual structure
pub fn msgpack_to_individual(cursor: &mut Cursor<&[u8]>, individual: &mut Individual) -> Result<(), String> {
    let arr_size: u64;
    /// Decodes main array
    match decode::decode_array(cursor) {
        Err(err) => return Err(format!("@ERR DECODING INDIVIDUAL MSGPACK ARRAY {0}", err)),
        Ok(size) => arr_size = size
    }

    if arr_size != 2 {
        /// Array at least must have len 2, uri and map     
        return Err("@ERR INVALID INDIVIDUAL MSGPACK SIZE".to_string());    
    }

    /// Decodes individual uri
    match decode::decode_string(cursor, &mut individual.uri) {
        Err(err) => return Err(format!("@ERR DECODING INDIVIDUAL URI {0}", err)),
        Ok(_) => {}
    }

    let map_size: u64;
    /// Decodes map with resources
    match decode::decode_map(cursor) {
        Err(err) => return Err(format!("@ERR DECODING INDIVIDUAL MAP {0}", err)),
        Ok(size) => map_size = size
    }

    /// For each pair in map performs convertion to resource
    for _ in 0..map_size {
        let mut key: Vec<u8> = Vec::default();
        let mut resources: Vec<Resource> = Vec::with_capacity(MAX_VECTOR_SIZE);

        /// Map key is resource
        match decode::decode_string(cursor, &mut key) {
            Err(err) => return Err(format!("@ERR DECODING RESOURCE URI {0}", err)),
            Ok(_) => {}
        }
        
        let res_size: u64;
        /// Decodes resource's array
        match decode::decode_array(cursor) {
            Ok(rs) => res_size = rs,
            Err(err) => return Err(format!("@ERR DECODING RESOURCES ARRAY {0}", err))
        }

        /// For each element in resource array checks it type
        for _ in 0.. res_size {
            let objtype: decode::Type;
            match decode::decode_type(cursor) {
                Ok(t) => objtype = t,
                Err(err) => return Err(format!("@ERR DECODING RESOURCE TYPE {0}", err))
            }

            match objtype {

                /// Arrays can have len 2 or 3
                decode::Type::ArrayObj => {
                    let res_arr_size = decode::decode_array(cursor).unwrap();
                    let res_type: u64;
                    /// Frist element of oall array is resource tyoe
                    match decode::decode_uint(cursor) {
                        Ok(rt) => res_type = rt,
                        Err(err) => return Err(format!("@ERR DECODING RESOURCE TYPE {0}", err))
                    }
                    if res_arr_size == 2 {
                        if res_type == ResourceType::Datetime as u64 {
                            /// Arrays with len 2 can be datetime, datetime can be int or uint in msgpack                            
                            let mut datetime: i64 = 0;
                            let decode_type: decode::Type;                   
                            match decode::decode_type(cursor) {
                                Ok(dt) => decode_type = dt,
                                Err(err) => return Err(format!("@ERR DECODING STRING RES TYPE {0}", err))
                            }

                            match decode_type {
                                decode::Type::UintObj => {
                                    match decode::decode_uint(cursor) {
                                        Ok(dt) => datetime = dt as i64,
                                        Err(err) => return Err(format!("@ERR DECODING DATETIME {0}", err))
                                    }
                                }

                                decode::Type::IntObj => {
                                    match decode::decode_int(cursor) {
                                        Ok(dt) => datetime = dt,
                                        Err(err) => return Err(format!("@ERR DECODING DATETIME {0}", err))
                                    }
                                }

                                _ => {}
                            }
                            let mut resource = Resource::new();
                            resource.res_type = ResourceType::Datetime;
                            resource.long_data = datetime;
                            resources.push(resource);
                        } else if res_type == ResourceType::Str as u64 {
                            /// Arrays with len 2 can be str without language
                            let mut resource = Resource::new();
                            
                            let decode_type: decode::Type;
                            match decode::decode_type(cursor) {
                                Ok(dt) => decode_type = dt,
                                Err(err) => return Err(format!("@ERR DECODING STRING RES TYPE {0}", err))
                            }

                            match decode_type {
                                decode::Type::StrObj => 
                                    decode::decode_string(cursor, &mut resource.str_data).unwrap(),
                                decode::Type::NilObj => decode::decode_nil(cursor).unwrap(),
                                _ => return Err("@UNKNOWN TYPE IN STRING RESOURCE".to_string())
                            }
                            resource.lang = Lang::LangNone;
                            resources.push(resource);
                        } else {
                            return Err("@UNKNOWN RESOURCE TYPE".to_string());
                        }
                    } else if res_arr_size == 3 {
                        if res_type == ResourceType::Decimal as u64 {
                            /// Arrays with len 3 can be decimal
                            /// Decimal contains two elements of int or uint type
                            /// Mantissa and exponent
                            let mut resource = Resource::new();
                            
                            let mut decode_type: decode::Type;  
                            match decode::decode_type(cursor) {
                                Ok(dt) => decode_type = dt,
                                Err(err) => return Err(format!("@ERR DECODEING MANTISSA TYPE {0}", err))
                            }

                            match decode_type {
                                decode::Type::UintObj => {
                                    resource.decimal_mantissa_data = decode::decode_uint(cursor).unwrap() as i64;
                                },
                                decode::Type::IntObj => {
                                    resource.decimal_mantissa_data = decode::decode_int(cursor).unwrap();
                                },
                                _ => return Err("@ERR UNSUPPORTED MANTISSA TYPE".to_string())
                            }
  
                            match decode::decode_type(cursor) {
                                Ok(dt) => decode_type = dt,
                                Err(err) => return Err(format!("@ERR DECODEING MANTISSA TYPE {0}", err))
                            }

                            match decode_type {
                                decode::Type::UintObj => {
                                    resource.decimal_exponent_data = decode::decode_uint(cursor).unwrap() as i64;
                                },
                                decode::Type::IntObj => {
                                    resource.decimal_exponent_data = decode::decode_int(cursor).unwrap();
                                },
                                _ => return Err("@ERR UNSUPPORTED EXPONENT TYPE".to_string())
                            }

                            resource.res_type = ResourceType::Decimal;
                            resources.push(resource);
                        } else if res_type == ResourceType::Str as u64 {
                            /// Arrays with lan 3 can be str with languate
                            let mut resource = Resource::new();

                            let decode_type: decode::Type;
                            match decode::decode_type(cursor) {
                                Ok(dt) => decode_type = dt,
                                Err(err) => return Err(format!("@ERR DECODING STRING RES TYPE {0}", err))
                            }

                            match decode_type {
                                decode::Type::StrObj => 
                                    decode::decode_string(cursor, &mut resource.str_data).unwrap(),
                                decode::Type::NilObj => decode::decode_nil(cursor).unwrap(),
                                _ => return Err("@UNKNOWN TYPE IN STRING RESOURCE".to_string())
                            }

                            match decode::decode_uint(cursor) {
                                Ok(l) => resource.lang = Lang::from_u64(l),
                                Err(err) => return Err(format!("@ERR DECODING LEN {0}", err))
                            }
                            resource.res_type = ResourceType::Str;
                            resources.push(resource);
                        }                     
                    }
                }

                decode::Type::StrObj => {
                    let mut resource = Resource::new();
                    decode::decode_string(cursor, &mut resource.str_data).unwrap();
                    resource.res_type = ResourceType::Uri;
                    resources.push(resource);
                }
                decode::Type::UintObj => {
                    let mut resource = Resource::new();
                    resource.long_data = decode::decode_uint(cursor).unwrap() as i64;
                    resource.res_type = ResourceType::Integer;
                    resources.push(resource);
                }
                decode::Type::IntObj => {
                    let mut resource = Resource::new();
                    resource.long_data = decode::decode_int(cursor).unwrap();
                    resource.res_type = ResourceType::Integer;
                    resources.push(resource);
                }
                decode::Type::BoolObj => {
                    let mut resource = Resource::new();
                    resource.bool_data = decode::decode_bool(cursor).unwrap();
                    resource.res_type = ResourceType::Boolean;
                    resources.push(resource);
                }
               _ => return Err(format!("@UNSUPPORTED RESOURCE TYPE {0} :{1}", objtype as u64, 
                std::str::from_utf8(&key[..]).unwrap()))
            }
        }

        individual.resources.insert(std::str::from_utf8(key.as_ref()).unwrap().to_string(), resources);
    }
    return Ok(());
}

impl IndividualDatabase {
    fn get_individuals(&self, uris: &Vec<String>, conn: &mut connector::Connector, user_uri: &String) -> 
        connector::RequestResponse {
        conn.get(true, user_uri, uris, false)
    }
}

fn decimal_to_string(mantissa: i64, exponent: i64) -> String {
    let mut m = mantissa;
    let mut e = exponent;
    let mut res = "".to_string();

    let mut negative = false;
    if mantissa < 0 {
        negative = true;
        m = -m;
    }

    if e > 0 {
        for i in 0 .. e {
            res = res + "0";
        }
    } else if e < 0 {
        e = -e;
        if res.len() as i64 > e {
            let len = res.len();
            res.insert(len - e as usize + 1, '.');
        } else {
            for i in 1 .. e {
                res = "0".to_string() + &res;
            }
            res = ".".to_string() + &res;            
        }        
    }

    if negative {
        res = "-".to_string() + &res;            
    }    

    res
}

fn individual_to_json(individual: &Individual) -> serde_json::Value {
    let mut individual_json = json!({
        "@": std::str::from_utf8(&individual.uri[..]).unwrap()
    });

    for (k, v) in &individual.resources {
        let mut resources: Vec<serde_json::Value> = Vec::with_capacity(v.len());

        for i in 0 .. v.len() {
            match v[i].res_type {
                ResourceType::Boolean => {
                    resources.push(json!({
                        "type": v[i].res_type.to_string(),
                        "data": v[i].bool_data
                    }));
                }

                ResourceType::Datetime => {
                    let utc: DateTime<Utc> = DateTime::<Utc>::from_utc(
                            NaiveDateTime::from_timestamp(v[i].long_data, 0), Utc);

                    resources.push(json!({
                       "type": v[i].res_type.to_string(),
                       "data": format!("{0}-{1}-{2}T{3}:{4}:{5}Z", utc.year(), utc.month(), utc.day(),
                            utc.hour(), utc.minute(), utc.second())
                    }));
                }

                ResourceType::Decimal => {
                    resources.push(json!({
                        "type": v[i].res_type.to_string(),
                        "data": decimal_to_string(v[i].decimal_mantissa_data, v[i].decimal_exponent_data)
                    }));
                }

                ResourceType::Integer => {
                    resources.push(json!({
                        "type": v[i].res_type.to_string(),
                        "data": v[i].long_data
                    }));
                }

                ResourceType::Str => {
                    resources.push(json!({
                        "type": v[i].res_type.to_string(),
                        "data": std::str::from_utf8(&v[i].str_data[..]).unwrap(),
                        "lang": v[i].lang.to_string()
                    }));
                }

                ResourceType::Uri => {
                    resources.push(json!({
                        "type": v[i].res_type.to_string(),
                        "data": std::str::from_utf8(&v[i].str_data[..]).unwrap()
                    }));
                }
            }
        }
        individual_json[k] = serde_json::to_value(resources).unwrap();
    }

    individual_json
}

graphql_object!(IndividualDatabase: IndividualDatabase as "Query" |&self| {
    field individual(uris: Vec<String>, ticket: String) -> String {
        let mut individuals: Vec<serde_json::Value> = Vec::new();
        let mut checked: HashMap<String, bool> = HashMap::new();
        let mut uris_copy = uris.clone();
        let mut conn = connector::Connector::new("127.0.0.1:9999".to_string());        
        let rr_ticket = conn.get_ticket(&vec![ticket; 1], false);
        let user_uri;
        
        if rr_ticket.common_rc == connector::ResultCode::Ok {
            if rr_ticket.op_rc[0] == connector::ResultCode::Ok {
                let mut ticket = Individual::new();
                msgpack_to_individual(&mut Cursor::new(&rr_ticket.data[0][..]), &mut ticket).unwrap();
                user_uri = std::str::from_utf8(&ticket.resources["ticket:accessor"][0].str_data[..]).
                    unwrap().to_string();
            } else {
                return json!({
                    "result": individuals,
                    "code": connector::ResultCode::as_uint(&rr_ticket.op_rc[0])
                }).to_string()
            }
        } else {
            return json!({
                    "result": individuals,
                    "code": connector::ResultCode::as_uint(&rr_ticket.common_rc)
                }).to_string();
        }
        
        loop {
            if uris_copy.len() == 0 || individuals.len() >= 10000 {
                break;
            }

            let rr = self.get_individuals(&uris_copy, &mut conn, &user_uri);
            for i in 0 .. uris_copy.len() {
                checked.insert(uris_copy[i].clone(), false);
            }
    
            uris_copy.clear();
            for i in 0 .. rr.data.len() {
                let mut individual = Individual::new();
                msgpack_to_individual(&mut Cursor::new(&rr.data[i][..]), &mut individual).unwrap();                
                // writeln!(stderr(), "@URI {0}", std::str::from_utf8(&individual.uri[..]).unwrap().to_string());                
                for (k, r) in &individual.resources {
                    // writeln!(stderr(), "\tres {0}", k);
                    for j in 0 .. r.len() {
                        // writeln!(stderr(), "\t\tres type {0}", r[j].res_type as u64);                        
                        if r[j].res_type == ResourceType::Uri {
                            let val = std::str::from_utf8(&r[j].str_data[..]).unwrap();
                            // writeln!(stderr(), "\t\t\tval {0}", val);
                            if !checked.contains_key(val) {
                                uris_copy.push(val.to_string());
                                // writeln!(stderr(), "\t\t\tpush {0}", uris_copy.len());                                   
                            }
                        }
                    }
                }

                let uri = std::str::from_utf8(&individual.uri).unwrap().to_string();
                if checked.contains_key(&uri) {
                    let c = *checked.get(&uri).unwrap();
                    if !c {
                        individuals.push(individual_to_json(&individual));
                        checked.insert(uri, true);
                    }
                } else {
                    checked.insert(uri, true);
                }
            }
        }

        json!({
            "result": individuals,
            "code": connector::ResultCode::as_uint(&connector::ResultCode::Ok)
        }).to_string()
    }
});

impl juniper::Context for IndividualDatabase {}

fn request_handler(req: &mut Request) -> IronResult<Response> {
     let mut body = "".to_string();
     req.body.read_to_string(&mut body);

    writeln!(stderr(), "@BODY {0}", body);
    let v: Value = serde_json::from_str(&body).unwrap();
    let query: String = serde_json::from_value(v["query"].clone()).unwrap();

    writeln!(stderr(), "@REQUEST {0}", query);   
    let db = IndividualDatabase{ individuals: HashMap::new() };    
    let schema = juniper::RootNode::new(&db, juniper::EmptyMutation::<IndividualDatabase>::new());
    let result  = juniper::execute(&query, None, &schema, &juniper::Variables::new(), &db).unwrap();
    // result.0.as_string_value().unwrap();
    // writeln!(stderr(), "RESULT {:?}", result.0);
    let hash_object = result.0.as_object_value().unwrap();
    
    // for (k, v) in hash_object {
        // writeln!(stderr(), "{0} => {1}", k, v.as_string_value().unwrap());
    // }    

    Ok(Response::with((status::Ok, hash_object.get("individual").unwrap().as_string_value().unwrap())))
}

fn main() {
    let _server = Iron::new(request_handler).http("0.0.0.0:8081").unwrap();
}
