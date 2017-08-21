package main

import (
	"log"
	"net"
)

func query(request string) (ResultCode, []byte) {
	socket, err := net.Dial("tcp", "127.0.0.1:11112")
	if err != nil {
		log.Println("@ERR QUERY: ERR ON DIAL ", err)
		return InternalServerError, []byte(""[:])
	}

	requestSize := uint32(len(request))
	buf := make([]byte, 4)
	buf[0] = byte((requestSize >> 24) & 0xFF)
	buf[1] = byte((requestSize >> 16) & 0xFF)
	buf[2] = byte((requestSize >> 8) & 0xFF)
	buf[3] = byte(requestSize & 0xFF)

	n, err := socket.Write(buf)
	if n < 4 || err != nil {
		log.Println("@ERR QUERY: ERR SENDING REQUEST SIZE ", err)
		return InternalServerError, []byte(""[:])
	}

	n, err = socket.Write([]byte(request))
	if uint32(n) < requestSize || err != nil {
		log.Println("@ERR QUERY: ERR SENDING REQUEST ", err)
		return InternalServerError, []byte(""[:])
	}

	n, err = socket.Read(buf)
	if n < 4 || err != nil {
		log.Println("@ERR QUERY: ERR READING RESPONSE SIZE ", err)
		return InternalServerError, []byte(""[:])

	}
	responseSize := uint32(0)
	for i := 0; i < 4; i++ {
		responseSize = (responseSize << 8) + uint32(buf[i])
	}

	response := make([]byte, responseSize)
	n, err = socket.Read(response)
	if uint32(n) < responseSize || err != nil {
		log.Println("@ERR QUERY: ERR READING RESPONSE ", err)
		return InternalServerError, []byte(""[:])
	}

	socket.Close()

	return Ok, response
}
