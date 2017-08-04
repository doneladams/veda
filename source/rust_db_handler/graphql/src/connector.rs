extern crate rmp_bind;

use self::rmp_bind::{ decode, encode };
use std::net::TcpStream;
use std::io::stderr;
use std::io::Write;
use std::io::Read;
use std::thread;
use std::time;
use std::default;


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
    pub result_code: ResultCode,
    pub data: Vec<Vec<u8>>,
    pub rights: Vec<u8>
}

impl RequestResponse {
    pub fn new() -> RequestResponse {
        RequestResponse { result_code: ResultCode::Ok, data: Vec::new(), rights: Vec::new() }
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

    fn do_request(&mut self, need_auth: bool, user_uri: String, data: Vec<String>, trace: bool, trace_auth: bool, op: u64) {
		let mut request = Vec::with_capacity(4096);
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
			// let resp_size;
			let mut errored = false;

			let mut written = 0;
			while written < buf.len() {
				match self.stream {
					Some(ref mut s) => {
						match s.write(&buf[written..]) {
							Ok(nbytes) => {
								written += nbytes;
								if trace {
									writeln!(stderr(), "@SENT {0} BYTES", nbytes);
								}
							}
							Err(e) => {
								writeln!(stderr(), "@ERR ON SENDING REQUEST FOR OP {0}: {1}", op, e);
								errored = true;
								break;
							}
						}
					}
					_ => {}
				}	
			}

			if errored {
				self.connect();
				continue;
			}

			let mut read = 0;
			while read < 4 {
				buf = Vec::with_capacity(4);
				match self.stream {
					Some(ref mut s) => {
						match s.read(&mut buf) {
							Ok(nbytes) => {
								read += nbytes;
								if trace {
									writeln!(stderr(), "@READ {0} BYTES", nbytes);
								}
							}
							Err(e) => {
								writeln!(stderr(), "@ERR ON READING RESPONSE SIZE FOR OP {0}: {1}", op, e);
								errored = true;
								break;
							}
						}
					}
					_ => {}
				}
			}

			


/*		buf = make([]byte, 4)
		n, err = conn.conn.Read(buf)
		if trace {
			log.Printf("@CONNECTOR OP %v: RESPONSE SIZE BUF %v\n", op, n)
		}

		if err != nil {
			log.Printf("@ERR OP %v: RECEIVING RESPONSE SIZE BUF %v\n", op, err)
		}

		for i := 0; i < 4; i++ {
			responseSize = (responseSize << 8) + uint32(buf[i])
		}

		if trace {
			log.Printf("@CONNECTOR OP %v: RESPONSE SIZE %v\n", op, responseSize)
		}

		if responseSize > MaxPacketSize {
			log.Printf("@ERR OP %v: RESPONSE IS TOO LARGE %v\n", op, data)
			return SizeTooLarge, nil
		}

		response = make([]byte, responseSize)
		n, err = conn.conn.Read(response)

		if trace {
			log.Printf("@CONNECTOR OP %v: RECEIVE RESPONSE %v\n", op, n)
		}

		if err != nil {
			log.Printf("@ERR RECEIVING OP %v: RESPONSE %v\n", op, err)
		}

		if uint32(n) < responseSize || err != nil {
			time.Sleep(3000 * time.Millisecond)
			conn.conn, err = net.Dial("tcp", conn.addr)
			log.Printf("@RECONNECT %v REQUEST\n", op)
		}

		if trace {
			log.Printf("@CONNECTOR %v RECEIVED RESPONSE %v\n", op, string(response))
		}
		break*/

		}
        /*



	for {
	}
	return Ok, response
        */
    }

    pub fn get(need_auth: bool, user_uri: String, uris: Vec<String>, trace: bool) -> RequestResponse {
        let mut rr = RequestResponse::new();
        if user_uri.len() < 3 {
            rr.result_code = ResultCode::NotAuthorized;
            writeln!(stderr(), "@ERR CONNECTOR GET: SHORT USER URI {0}", user_uri);
            return rr;
        }

        if uris.len() == 0{
            rr.result_code = ResultCode::NoContent;
            return rr;
        }

        if trace {
            writeln!(stderr(), "@CONNECTOR GET: PACK REQUEST need_auth={0}, user_uri=[{1}]",
                need_auth, user_uri);
        }
/*


	rcRequest, response := doRequest(needAuth, userUri, uris, trace, false, Get)
	if rcRequest != Ok {
		rr.CommonRC = rcRequest
		return rr
	}
	decoder := msgpack.NewDecoder(bytes.NewReader(response))
	arrLen, _ := decoder.DecodeArrayLen()
	rc, _ := decoder.DecodeUint()
	rr.CommonRC = ResultCode(rc)

	if trace {
		log.Println("@CONNECTOR GET: COMMON RC ", rr.CommonRC)
	}

	rr.Data = make([]string, 0)
	rr.OpRC = make([]ResultCode, len(uris))

	for i, j := 1, 0; i < arrLen; i, j = i+2, j+1 {
		rc, _ = decoder.DecodeUint()
		rr.OpRC[j] = ResultCode(rc)
		if trace {
			log.Println("@CONNECTOR GET: OP CODE ", rr.OpRC[j])
		}

		if rr.OpRC[j] == Ok {
			tmp, _ := decoder.DecodeString()
			rr.Data = append(rr.Data, tmp)
		} else {
			decoder.DecodeNil()
		}
	}

	return rr*/

        return rr;
    }
}