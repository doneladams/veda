#[macro_use] extern crate juniper;

use std::collections::HashMap;
use std::io::stderr;
use std::io::Write;
use juniper::Context;

mod connector;

#[derive(PartialEq, Eq, Copy)]
enum ResourceType {
    Uri = 1,
    Str = 2,
    Integer = 4,
    Datetime = 8,
    Decimal = 32,
    Boolean = 64
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
}

pub struct IndividualDatabase {
    individuals: HashMap<String, Individual>
}

impl IndividualDatabase {
    fn get_individual(&self, uris: &Vec<String>) -> Option<Individual> {
        let mut conn = connector::Connector::new("127.0.0.1:9999".to_string());
        conn.connect();
        conn.get(true, &"cfg:VedaSystem".to_string(), uris, true);
        Some(Individual::new())
    }
}

graphql_object!(IndividualDatabase: IndividualDatabase as "Query" |&self| {
    field individual(uris: Vec<String>) -> Vec<&str> {
        let mut individuals: Vec<&str> = Vec::new();
        let mut checked: HashMap<String, bool> = HashMap::new();

        let mut uris_copy = uris.clone();

        let mut i = 0;
        self.get_individual(&uris_copy);
       /* loop {
            if i == uris_copy.len() {
                break;
            }
            writeln!(stderr(), "@URI {0}", uris_copy[i]);
            checked.insert(uris_copy[i].clone(), true);
            match self.get_individual(&uris_copy[i]) {
                Some(i) => {
                    individuals.push(std::str::from_utf8(&i.uri[..]).unwrap());
                    for (k, r) in &i.resources {
                        writeln!(stderr(), "\tres {0}", k);
                        for j in 0 .. r.len() {
                            writeln!(stderr(), "\t\tres type {0}", r[j].res_type as u64);                        
                            if r[j].res_type == ResourceType::Uri {
                                let val = std::str::from_utf8(&r[j].str_data[..]).unwrap();
                                writeln!(stderr(), "\t\t\tval {0}", val);
                                if !checked.contains_key(val) {
                                    uris_copy.push(val.to_string());
                                    writeln!(stderr(), "\t\t\tpush {0}", uris_copy.len());                                   
                                }
                            }
                        }
                    }
                    
                }
                None => {}
            }

            i += 1;
        }*/

        // let mut
        
        writeln!(stderr(), "LEN {0}", individuals.len());
        return individuals;
    }
});

impl juniper::Context for IndividualDatabase {}
// impl juniper::GraphQLType for IndividualDatabase {}

fn main() {
    let mut db = IndividualDatabase{ individuals: HashMap::new() };

    let query = r#" 
    { 
        individual(uris: ["cfg:VedaSystem"])
    }"#;

    let schema = juniper::RootNode::new(&db, juniper::EmptyMutation::<IndividualDatabase>::new());
    let result  = juniper::execute(query, None, &schema, &juniper::Variables::new(), &db).unwrap();

    // writeln!(stderr(), "{0}", result.len());
    // juniper::Value::object(result.0);
}
