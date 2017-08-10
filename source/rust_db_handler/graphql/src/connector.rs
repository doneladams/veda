extern crate rmp_bind;

use self::rmp_bind::{ decode, encode };
use std::net::TcpStream;
use std::io::stderr;
use std::io::Write;
use std::io::Read;
use std::io::Cursor;
use std::thread;
use std::time;
use std::default;

static MAX_PACKET_SIZE: u32 = 1024 * 1024 * 10;

#[derive(PartialEq, Eq)]
pub enum ResultCode {
    Ok = 200,
    NoContent = 204,
    BadRequest = 400,
    TicketExpired = 471,
    NotAuthorized = 472,
    NotFound = 404,
    InternalServerError = 500,
    UnprocessableEntity = 422
}

pub enum Operation {
	Put             = 1,
	Get             = 2,
	GetTicket       = 3,
	Authorize       = 8,
	GetRightsOrigin = 9,
	GetMembership   = 10,
	Remove          = 51
}

pub struct RequestResponse {
    pub common_rc: ResultCode,
	pub op_rc: Vec<ResultCode>,
    pub data: Vec<Vec<u8>>,
    pub rights: Vec<u8>
}

impl ResultCode {
	pub fn from_uint(rc: u64) -> ResultCode {
		match rc {
			200 => return ResultCode::Ok,
			204 => return ResultCode::NoContent,
			400 => return ResultCode::BadRequest,
			471 => return ResultCode::TicketExpired,
			472 => return ResultCode::NotAuthorized,
			404 => return ResultCode::NotFound,
			500 => return ResultCode::InternalServerError,
			422 => return ResultCode::UnprocessableEntity,
			_ => {}
		}

		ResultCode::UnprocessableEntity
	}

	pub fn as_uint(code: &ResultCode) -> u64 {
		/*
		  Ok = 200,
    NoContent = 204,
    BadRequest = 400,
    TicketExpired = 471,
    NotAuthorized = 472,
    NotFound = 404,
    InternalServerError = 500,
    UnprocessableEntity = 422
		*/
		match *code {
			ResultCode::BadRequest => return 400,
			ResultCode::InternalServerError => return 500,
			ResultCode::NoContent => return 204,
			ResultCode::NotAuthorized => return 472,
			ResultCode::NotFound => return 404,
			ResultCode::Ok => return 200,
			ResultCode::TicketExpired => return 471,
			ResultCode::UnprocessableEntity => return 422,
		}

		422
	}
}

impl RequestResponse {
    pub fn new() -> RequestResponse {
        RequestResponse { common_rc: ResultCode::Ok, op_rc: Vec::default(), 
			data: Vec::default(), rights: Vec::default() }
    }
}

pub struct Connector {
    pub address: String,
    pub stream: Option<TcpStream>
}

impl Connector {
    pub fn new(address: String) -> Connector {
        Connector { address: address, stream: None }
    }
    pub fn connect(&mut self) {
        loop {
            match TcpStream::connect(&self.address) {
                Ok(s) => {
                    self.stream = Some(s);
                    return;
                }
                Err(e) => {
                    writeln!(stderr(), "@ERR ON CONNECTION TO TARANTOOL: {0}: RETRY", e);
                    thread::sleep_ms(3000);
                }
            }
        }
    }

    fn do_request(&mut self, need_auth: bool, user_uri: &String, data: &Vec<String>, 
		trace: bool, trace_auth: bool, op: u64) -> (ResultCode, Vec<u8>) {
		let mut request = Vec::with_capacity(4096);
		let mut response;
		if op == Operation::GetRightsOrigin as u64 || op == Operation::Authorize as u64 || 
			op == Operation::GetMembership as u64 {
			encode::encode_array(&mut request, data.len() as u32 + 4)
		} else {
			encode::encode_array(&mut request, data.len() as u32 + 3);
		}

		encode::encode_uint(&mut request, op);
		encode::encode_bool(&mut request, need_auth);
		if op == Operation::GetRightsOrigin as u64 || op == Operation::Authorize as u64 || 
			op == Operation::GetMembership as u64 {
			encode::encode_bool(&mut request, trace_auth);
		}

		encode::encode_string(&mut request, &user_uri);
		for i in 0 .. data.len() {
			encode::encode_string(&mut request, &data[i]);
		}

		if trace {
			writeln!(stderr(), "@CONNECTOR OP {0} DATA SIZE {1}", op, request.len());
		}

		let request_size = request.len() as u32;
		let mut buf: Vec<u8> = Vec::with_capacity(4 + request_size as usize);
		buf.push(((request_size >> 24) & 0xFF) as u8);
		buf.push(((request_size >> 16) & 0xFF) as u8);
		buf.push(((request_size >> 8) & 0xFF) as u8);
		buf.push((request_size & 0xFF) as u8);
		buf.append(&mut request);

		loop {
			let mut errored = false;

			let mut written = 0;
			while written < buf.len() {
				match self.stream {
					Some(ref mut s) => {
						match s.write(&buf[written..]) {
							Ok(nbytes) => {
								written += nbytes;
								if trace {
									writeln!(stderr(), "@SENT {0} BYTES", nbytes).unwrap();
								}
							}
							Err(e) => {
								writeln!(stderr(), "@ERR ON SENDING REQUEST FOR OP {0}: {1}", op, e).unwrap();
								errored = true;
								break;
							}
						}
					}
					_ => {
						errored = true;
						break;
					}
				}	
			}

			if errored {
				self.connect();
				continue;
			}

			let mut read = 0;
			buf = vec![0; 4];
			while read < 4 {
				match self.stream {
					Some(ref mut s) => {
						match s.read(&mut buf[read..]) {
							Ok(nbytes) => {
								read += nbytes;
								if trace {
									writeln!(stderr(), "@READ {0} RESPONSE SIZE BYTES", nbytes).unwrap();
								}
							}
							Err(e) => {
								writeln!(stderr(), "@ERR ON READING RESPONSE SIZE FOR OP {0}: {1}", op, e).unwrap();
								errored = true;
								break;
							}
						}
					}
					_ => {
						errored = true;
						break;
					}
				}
			}

			if errored {
				self.connect();
				continue;
			}

			let mut response_size: u32 = 0;
			for i in 0 .. 4 {
				response_size = (response_size << 8) + buf[i] as u32;
			}

			if trace {
				writeln!(stderr(), "@CONNECTOR OP {0}: RESPONSE SIZE {1}", op, response_size).unwrap();
			}

			if response_size > MAX_PACKET_SIZE {
				writeln!(stderr(), "@ERR OP {0}: RESPONSE IS TOO LARGE {1}", op, response_size).unwrap();
			}

			response = vec![0; response_size as usize];
			read = 0;
			while (read as u32) < response_size {
				match self.stream {
					Some(ref mut s) => {
						match s.read(&mut response[read..]) {
							Ok(nbytes) => {
								read += nbytes;
								if trace {
									writeln!(stderr(), "@READ {0} RESPONSE BYTES", nbytes).unwrap();
								}
							}
							Err(e) => {
								writeln!(stderr(), "@ERR ON READING RESPONSE OP {0}: {1}", op, e).unwrap();
								errored = true;
								break;
							}
						}
					}
					_ => { 
						errored = true;
						break;
					}
				}
			}

			if errored {
				self.connect();
				continue;
			}

			if trace {
				writeln!(stderr(), "@CONNECTOR OP {0}: RECEIVED RESPONSE", op).unwrap();
			}

			break;
		}

		(ResultCode::Ok, response)
    }

    pub fn get(&mut self, need_auth: bool, user_uri: &String, uris: &Vec<String>, trace: bool) -> RequestResponse {
        let mut rr = RequestResponse::new();
        if user_uri.len() < 3 {
            rr.common_rc = ResultCode::NotAuthorized;
            writeln!(stderr(), "@ERR CONNECTOR GET: SHORT USER URI {0}", user_uri).unwrap();
            return rr;
        }

        if uris.len() == 0{
            rr.common_rc = ResultCode::NoContent;
            return rr;
        }

        if trace {
            writeln!(stderr(), "@CONNECTOR GET: PACK REQUEST need_auth={0}, user_uri=[{1}]",
                need_auth, user_uri).unwrap();
			writeln!(stderr(), "@URIS: {{").unwrap();
			for i in 0 .. uris.len() {
				writeln!(stderr(), "\t[ {0} ]", uris[i]).unwrap();
			}

			writeln!(stderr(), "}}").unwrap();
        }

		let rr_tuple = self.do_request(need_auth, &user_uri, &uris, trace, false, Operation::Get as u64);
		if rr_tuple.0 != ResultCode::Ok {
			rr.common_rc = rr_tuple.0;
			return rr;
		}

		let cursor = &mut Cursor::new(&rr_tuple.1[..]);
		let arr_len = decode::decode_array(cursor).unwrap();

		let mut common_rc = decode::decode_uint(cursor).unwrap();		
		rr.common_rc = ResultCode::from_uint(common_rc);

		if trace {
			writeln!(stderr(), "@CONNECTOR GET: COMMON RC {0}", common_rc);
		}

		rr.data = Vec::with_capacity(uris.len());
		rr.op_rc = Vec::with_capacity(uris.len());

		let mut i = 1;
		while i < arr_len {
			let op_rc = decode::decode_uint(cursor).unwrap();
			rr.op_rc.push(ResultCode::from_uint(op_rc));

			if trace {
				writeln!(stderr(), "@CONNECTOR GET: OP CODE: {0}", op_rc);
			}

			if op_rc == ResultCode::Ok as u64 {
				let mut data = Vec::new();
				decode::decode_string(cursor, &mut data).unwrap();
				rr.data.push(data);
			} else {
				decode::decode_nil(cursor);
			}
			i += 2;
		}

        return rr;
    }

	pub fn get_ticket(&mut self, ticket_ids: &Vec<String>, trace: bool) -> RequestResponse {
		let mut rr = RequestResponse::new();

        if ticket_ids.len() == 0{
            rr.common_rc = ResultCode::NoContent;
            return rr;
        }

        if trace {
            writeln!(stderr(), "@CONNECTOR GET_TICKET: PACK REQUEST").unwrap();
			writeln!(stderr(), "@TICKET IDS: {{").unwrap();
			for i in 0 .. ticket_ids.len() {
				writeln!(stderr(), "\t[ {0} ]", ticket_ids[i]).unwrap();
			}

			writeln!(stderr(), "}}").unwrap();
        }

		let rr_tuple = self.do_request(false, &"cfg:VedaSystem".to_string(), &ticket_ids, trace, false, 
			Operation::GetTicket as u64);
		if rr_tuple.0 != ResultCode::Ok {
			rr.common_rc = rr_tuple.0;
			return rr;
		}

		let cursor = &mut Cursor::new(&rr_tuple.1[..]);
		let arr_len = decode::decode_array(cursor).unwrap();

		let mut common_rc = decode::decode_uint(cursor).unwrap();		
		rr.common_rc = ResultCode::from_uint(common_rc);

		if trace {
			writeln!(stderr(), "@CONNECTOR GET_TICKET: COMMON RC {0}", common_rc);
		}

		rr.data = Vec::with_capacity(ticket_ids.len());
		rr.op_rc = Vec::with_capacity(ticket_ids.len());

		let mut i = 1;
		while i < arr_len {
			let op_rc = decode::decode_uint(cursor).unwrap();
			rr.op_rc.push(ResultCode::from_uint(op_rc));

			if trace {
				writeln!(stderr(), "@CONNECTOR GET: OP CODE: {0}", op_rc);
			}

			if op_rc == ResultCode::Ok as u64 {
				let mut data = Vec::new();
				decode::decode_string(cursor, &mut data).unwrap();
				rr.data.push(data);
			} else {
				decode::decode_nil(cursor);
			}
			i += 2;
		}

        return rr;
	}
}