package main

import (
	"bytes"
	"log"
	"net"
	"time"

	"bufio"

	"gopkg.in/vmihailenco/msgpack.v2"
)

type Connector struct {
	conn net.Conn
	addr string
}

type RequestResponse struct {
	CommonRC ResultCode
	OpRC     []ResultCode
	Msgpaks  []string
	rithgs   []uint8
}

const MaxPacketSize = 1024 * 1024 * 10

const (
	Put       = 1
	Get       = 2
	Authorize = 8
	Remove    = 51
)

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

func (conn *Connector) Get(needAuth bool, userUri string, uris []string, trace bool) RequestResponse {
	var rr RequestResponse
	var request bytes.Buffer
	var response []byte

	if len(userUri) < 3 {
		rr.CommonRC = NotAuthorized
		log.Println("@ERR CONNECTOR GET ", uris)
		return rr
	}

	if len(uris) == 0 {
		rr.CommonRC = NoContent
		return rr
	}

	if trace {
		log.Printf("@CONNECTOR GET PACK GET REQUEST need_auth=%v, user_uri=%v, uris=%v \n",
			needAuth, userUri, uris)
	}

	writer := bufio.NewWriter(&request)
	encoder := msgpack.NewEncoder(writer)
	encoder.EncodeArrayLen(len(uris) + 3)
	encoder.EncodeUint(Get)
	encoder.EncodeBool(needAuth)
	encoder.EncodeString(userUri)

	for i := 0; i < len(uris); i++ {
		encoder.EncodeString(uris[i])
	}

	writer.Flush()
	if trace {
		log.Println("@CONNECTOR GET DATA SIZE ", request.Len())
	}

	requestSize := uint32(request.Len())
	buf := make([]byte, 4)
	buf[0] = byte((requestSize >> 24) & 0xFF)
	buf[1] = byte((requestSize >> 16) & 0xFF)
	buf[2] = byte((requestSize >> 8) & 0xFF)
	buf[3] = byte(requestSize & 0xFF)
	buf = append(buf, request.Bytes()...)

	for {
		var responseSize uint32

		n, err := conn.conn.Write(buf)
		if err != nil {
			log.Println("@ERR ON SEND GET REQUEST ", err)
		}

		if trace {
			log.Println("@CONNECTOR GET SEND ", n)
		}

		buf = make([]byte, 4)
		n, err = conn.conn.Read(buf)
		if trace {
			log.Println("@CONNECTOR GET RESPONSE SIZE BUF", n)
		}

		if err != nil {
			log.Println("@ERR RECEIVING RESPONSE SIZE BUF ", err)
		}

		for i := 0; i < 4; i++ {
			responseSize = (responseSize << 8) + uint32(buf[i])
		}

		if trace {
			log.Println("@CONNECTOR GET RESPONSE SIZE ", responseSize)
		}

		if responseSize > MaxPacketSize {
			log.Println("@ERR RESPONSE IS TOO LARGE ", uris)
			rr.CommonRC = SizeTooLarge
			return rr
		}

		response = make([]byte, responseSize)
		n, err = conn.conn.Read(response)

		if trace {
			log.Println("@CONNECTOR GET RECEIVE RESPONSE ", n)
		}

		if err != nil {
			log.Println("@ERR RECEIVING GET RESPONSE ", err)
		}

		if uint32(n) < responseSize || err != nil {
			time.Sleep(3000 * time.Millisecond)
			conn.conn, err = net.Dial("tcp", conn.addr)
			log.Println("@RECONNECT GET REQUEST")
		}

		if trace {
			log.Println("@CONNECTOR GET RECEIVED RESPONSE ", string(response))
		}
		break
	}

	decoder := msgpack.NewDecoder(bytes.NewReader(response))
	arrLen, _ := decoder.DecodeArrayLen()
	log.Println("@ARR LEN ", arrLen)
	rc, _ := decoder.DecodeUint()
	rr.CommonRC = ResultCode(rc)

	if trace {
		log.Println("@CONNECTOR GET COMMON RC ", rr.CommonRC)
	}

	rr.Msgpaks = make([]string, len(uris))
	rr.OpRC = make([]ResultCode, len(uris))

	for i, j := 1, 0; i < arrLen; i, j = i+2, j+1 {
		rc, _ = decoder.DecodeUint()
		rr.OpRC[j] = ResultCode(rc)
		if trace {
			log.Println("@CONNECTOR GET OP CODE ", rr.OpRC[j])
		}

		if rr.OpRC[j] == Ok {
			rr.Msgpaks[j], _ = decoder.DecodeString()
		}
	}

	return rr
}
