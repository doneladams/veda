package main

import (
	"bytes"
	"log"
	"net"
	"time"

	"bufio"

	"gopkg.in/vmihailenco/msgpack.v2"
)

//Connector represents struct for connection to tarantool
type Connector struct {
	//Tcp connection to tarantool
	conn net.Conn
	//Address of tarantool database
	addr string
}

//RequestResponse represents structure for tarantool request response
type RequestResponse struct {
	//ResultCode for request
	CommonRC ResultCode
	//ResultCode for each uri in request
	OpRC []ResultCode
	//Response data
	Data []string
	//Returned rights for auth requests
	Rights []uint8
}

//MaxPacketSize is critical value for request/response packets,
//if size is bigger than error is returned
const MaxPacketSize = 1024 * 1024 * 10

const (
	//Put is request code for tarantool put
	Put = 1
	//Get is request code for tarantool get
	Get = 2
	//GetTicket is request code for tarantool get_ticket
	GetTicket = 3
	//Authorize is request code for tarantool authorize
	Authorize = 8
	//GetRightsOrigin is request code for get_rights_origin (authorize with aggregation)
	GetRightsOrigin = 9
	//GetMembership is request code for get_membership (authorize with aggregation)
	GetMembership = 10
	//Remove is request code for tarantool remove
	Remove = 51
)

//Connect tries to connect to socket in tarantool while connection is not established
func (conn *Connector) Connect(addr string) {
	var err error
	conn.addr = addr
	conn.conn, err = net.Dial("tcp", addr)

	for err != nil {
		time.Sleep(3000 * time.Millisecond)
		conn.conn, err = net.Dial("tcp", addr)
		log.Println("@TRY CONNECT")
	}
}

//doRequest encodes request  and sends it to tarantool, after that it reading and decoding response
func doRequest(needAuth bool, userUri string, data []string, trace, traceAuth bool, op uint) (ResultCode, []byte) {
	var request bytes.Buffer
	var response []byte

	writer := bufio.NewWriter(&request)
	encoder := msgpack.NewEncoder(writer)

	//for GetRightsOrigin, Authorize and GetMembership array
	//for requset size is bigget because of trace param
	if op == GetRightsOrigin || op == Authorize || op == GetMembership {
		encoder.EncodeArrayLen(len(data) + 4)
	} else {
		encoder.EncodeArrayLen(len(data) + 3)
	}
	// encoder.EncodeArrayLen(len(data) + 3)

	//Encoding operation code, needAuth flag, trace if needed and userUri
	encoder.EncodeUint(op)
	encoder.EncodeBool(needAuth)
	if op == GetRightsOrigin || op == Authorize || op == GetMembership {
		encoder.EncodeBool(traceAuth)
	}
	encoder.EncodeString(userUri)

	//Encode request data
	for i := 0; i < len(data); i++ {
		encoder.EncodeString(data[i])
	}

	writer.Flush()
	if trace {
		log.Println("@CONNECTOR GET DATA SIZE ", request.Len())
	}

	//Encoding request size for sending via socket
	requestSize := uint32(request.Len())
	buf := make([]byte, 4)
	buf[0] = byte((requestSize >> 24) & 0xFF)
	buf[1] = byte((requestSize >> 16) & 0xFF)
	buf[2] = byte((requestSize >> 8) & 0xFF)
	buf[3] = byte(requestSize & 0xFF)
	buf = append(buf, request.Bytes()...)

	//Retry sending until not successed
	//If error occured on some step try to reconnect and restart sending
	for {
		var responseSize uint32
		var n int
		var err error

		n, err = 0, nil
		//Writing until whole buffer is sent
		for n < len(buf) {
			var sent int
			sent, err = conn.conn.Write(buf[n:])
			if err != nil {
				break
			}
			n += sent
		}

		if err != nil {
			log.Printf("@ERR ON SEND OP %v: REQUEST %v\n", op, err)
			time.Sleep(3000 * time.Millisecond)
			conn.conn, err = net.Dial("tcp", conn.addr)
			log.Printf("@RECONNECT %v REQUEST\n", op)
			continue
		}

		if trace {
			log.Printf("@CONNECTOR OP %v: SEND %v", op, n)
		}

		buf = make([]byte, 4)
		n, err = 0, nil
		//Reading response size
		for n < 4 {
			var read int
			read, err = conn.conn.Read(buf[n:])
			if err != nil {
				break
			}
			n += read
		}

		if err != nil {
			log.Printf("@ERR OP %v: RECEIVING RESPONSE SIZE BUF %v\n", op, err)
			time.Sleep(3000 * time.Millisecond)
			conn.conn, err = net.Dial("tcp", conn.addr)
			log.Printf("@RECONNECT %v REQUEST\n", op)
			continue
		}

		if err != nil {
			log.Printf("@ERR OP %v: RECEIVING RESPONSE SIZE BUF %v\n", op, err)
		}

		//decoding response size
		for i := 0; i < 4; i++ {
			responseSize = (responseSize << 8) + uint32(buf[i])
		}

		if trace {
			log.Printf("@CONNECTOR OP %v: RESPONSE SIZE %v\n", op, responseSize)
		}

		//If response size is bigger than packet size than return SizeTooLarge to client
		if responseSize > MaxPacketSize {
			log.Printf("@ERR OP %v: RESPONSE IS TOO LARGE %v\n", op, data)
			return SizeTooLarge, nil
		}

		//Reading response until whole buffer is read
		response = make([]byte, responseSize)
		n, err = 0, nil
		for n < int(responseSize) {
			var read int
			read, err = conn.conn.Read(response[n:])
			if err != nil {
				break
			}
			n += read
		}

		if err != nil {
			log.Printf("@ERR ON READING RESPONSE OP %v: %v", op, err)
			time.Sleep(3000 * time.Millisecond)
			conn.conn, err = net.Dial("tcp", conn.addr)
			log.Printf("@RECONNECT %v REQUEST\n", op)
			continue
		}

		if trace {
			log.Printf("@CONNECTOR OP %v: RECEIVE RESPONSE %v\n", op, n)
		}

		if err != nil {
			log.Printf("@ERR RECEIVING OP %v: RESPONSE %v\n", op, err)
		}

		if trace {
			log.Printf("@CONNECTOR %v RECEIVED RESPONSE %v\n", op, string(response))
		}

		//If there are no errors than break cycle and return Ok code and response
		break
	}
	return Ok, response
}

//Put sends put request to tarantool, data here represented with msgpacks of individuals
func (conn *Connector) Put(needAuth bool, userUri string, individuals []string, trace bool) RequestResponse {
	var rr RequestResponse

	//If user uri is too shorth than return not authorized
	if len(userUri) < 3 {
		rr.CommonRC = NotAuthorized
		log.Println("@ERR CONNECTOR PUT: ", individuals)
		return rr
	}

	//If no individuals passed than return NoContent to client
	if len(individuals) == 0 {
		rr.CommonRC = NoContent
		return rr
	}

	if trace {
		log.Printf("@CONNECTOR PUT: PACK PUT REQUEST need_auth=%v, user_uri=%v, uris=%v \n",
			needAuth, userUri, individuals)
	}

	//Send request to tarantool
	rcRequest, response := doRequest(needAuth, userUri, individuals, trace, false, Put)
	//If failed return fail code
	if rcRequest != Ok {
		rr.CommonRC = rcRequest
		return rr
	}

	//Decoding msgpack response
	decoder := msgpack.NewDecoder(bytes.NewReader(response))
	arrLen, _ := decoder.DecodeArrayLen()
	rc, _ := decoder.DecodeUint()
	//Decoding common code for request
	rr.CommonRC = ResultCode(rc)

	if trace {
		log.Println("@CONNECTOR PUT: COMMON RC ", rr.CommonRC)
	}

	rr.OpRC = make([]ResultCode, len(individuals))

	//For put request only operation codes returned
	for i := 1; i < arrLen; i++ {
		rc, _ = decoder.DecodeUint()
		rr.OpRC[i-1] = ResultCode(rc)
		if trace {
			log.Println("@CONNECTOR PUT: OP CODE ", rr.OpRC[i-1])
		}
	}

	return rr
}

//Get sends get request to tarantool, individuals uris passed as data here
func (conn *Connector) Get(needAuth bool, userUri string, uris []string, trace bool) RequestResponse {
	var rr RequestResponse

	//If user uri is too short return NotAuthorized to client
	if len(userUri) < 3 {
		rr.CommonRC = NotAuthorized
		log.Println("@ERR CONNECTOR GET: ", uris)
		return rr
	}

	//If no uris passed than return NoContent to client
	if len(uris) == 0 {
		rr.CommonRC = NoContent
		return rr
	}

	if trace {
		log.Printf("@CONNECTOR GET: PACK GET REQUEST need_auth=%v, user_uri=%v, uris=%v \n",
			needAuth, userUri, uris)
	}

	//Send request to tarantool
	rcRequest, response := doRequest(needAuth, userUri, uris, trace, false, Get)
	if rcRequest != Ok {
		rr.CommonRC = rcRequest
		return rr
	}

	//Decoding request response
	decoder := msgpack.NewDecoder(bytes.NewReader(response))
	arrLen, _ := decoder.DecodeArrayLen()
	rc, _ := decoder.DecodeUint()
	//Decoding common response code for request
	rr.CommonRC = ResultCode(rc)

	if trace {
		log.Println("@CONNECTOR GET: COMMON RC ", rr.CommonRC)
	}

	//Decoding response, response represented with request code and string or nil
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

	return rr
}

//Authorize sends authorize, get membership or get rights origin request to tarantool,
//it depends on parametr operation. Individuals uris passed as data here
func (conn *Connector) Authorize(needAuth bool, userUri string, uris []string, operation uint,
	trace, traceAuth bool) RequestResponse {
	var rr RequestResponse

	//If userUri is too short return NotAuthorized to client
	if len(userUri) < 3 {
		rr.CommonRC = NotAuthorized
		log.Println("@ERR CONNECTOR AUTHORIZE: ", uris)
		return rr
	}

	//If no uris passed than NoContent returned to client.
	if len(uris) == 0 {
		rr.CommonRC = NoContent
		return rr
	}

	if trace {
		log.Printf("@CONNECTOR AUTHORIZE: PACK AUTHORIZE REQUEST need_auth=%v, user_uri=%v, uris=%v \n",
			needAuth, userUri, uris)
	}

	//Send request to tarantool
	rcRequest, response := doRequest(needAuth, userUri, uris, trace, traceAuth, operation)
	if rcRequest != Ok {
		rr.CommonRC = rcRequest
		return rr
	}

	//Decoding msgpack response
	decoder := msgpack.NewDecoder(bytes.NewReader(response))
	arrLen, _ := decoder.DecodeArrayLen()
	//Decoding common request code
	rc, _ := decoder.DecodeUint()
	rr.CommonRC = ResultCode(rc)

	if trace {
		log.Println("@CONNECTOR AUTHORIZE: COMMON RC ", rr.CommonRC)
	}

	//Decoding response data, data represented by operation response code, access rights,
	//nil for authorize and string data fro GetRightsOrigin and GetMembership.
	rr.OpRC = make([]ResultCode, len(uris))
	rr.Rights = make([]uint8, len(uris))
	if operation == GetMembership || operation == GetRightsOrigin {
		rr.Data = make([]string, len(uris))
	}
	for i, j := 1, 0; i < arrLen; i, j = i+3, j+1 {
		rc, _ = decoder.DecodeUint()
		rr.OpRC[j] = ResultCode(rc)
		if trace {
			log.Println("@CONNECTOR GET: OP CODE ", rr.OpRC[j])
		}

		rr.Rights[j], _ = decoder.DecodeUint8()
		if operation == GetRightsOrigin || operation == GetMembership {
			rr.Data[j], _ = decoder.DecodeString()
		} else {
			decoder.DecodeNil()
		}
	}

	return rr
}

//GetTicket sends get ticket request to tarantool, ticket ids here passes as data
func (conn *Connector) GetTicket(ticketIDs []string, trace bool) RequestResponse {
	var rr RequestResponse

	//If no ticket ids passed than NoContent returned to client.
	if len(ticketIDs) == 0 {
		rr.CommonRC = NoContent
		return rr
	}

	if trace {
		log.Printf("@CONNECTOR GET TICKET: PACK GET REQUEST ticket_ids=%v\n", ticketIDs)
	}

	//Send request to tarantool
	rcRequest, response := doRequest(false, "cfg:VedaSystem", ticketIDs, trace, false, GetTicket)
	if rcRequest != Ok {
		rr.CommonRC = rcRequest
		return rr
	}

	//Decoding requset response
	decoder := msgpack.NewDecoder(bytes.NewReader(response))
	arrLen, _ := decoder.DecodeArrayLen()
	//Decoding common request response code
	rc, _ := decoder.DecodeUint()
	rr.CommonRC = ResultCode(rc)

	if trace {
		log.Println("@CONNECTOR GET: COMMON RC ", rr.CommonRC)
	}

	//Decoding request response data, data here represented with operation result code,
	//and ticket individual msgpack
	rr.Data = make([]string, 0)
	rr.OpRC = make([]ResultCode, len(ticketIDs))
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

	return rr
}