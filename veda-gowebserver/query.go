package main

import (
	"log"
	"net"

	"fmt"

	"github.com/valyala/fasthttp"
)

func query(ctx *fasthttp.RequestCtx) {

	socket, err := net.Dial("tcp", "127.0.0.1:11112")
	if err != nil {
		log.Println("@ERR QUERY: ERR ON DIAL ", err)
		ctx.Response.SetStatusCode(int(InternalServerError))
		return
	}

	log.Println("@CONNECTED TO FT_QUERY", socket)

	ticketKey := string(ctx.QueryArgs().Peek("ticket")[:])
	query := string(ctx.QueryArgs().Peek("query")[:])
	sort := string(ctx.QueryArgs().Peek("sort")[:])
	databases := string(ctx.QueryArgs().Peek("databases")[:])
	reopen := ctx.QueryArgs().GetBool("reopen")
	top, _ := ctx.QueryArgs().GetUint("top")
	limit, _ := ctx.QueryArgs().GetUint("limit")
	from, _ := ctx.QueryArgs().GetUint("from")

	request := fmt.Sprintf("%v|%v|%v|%v|%v|%v|%v|%v", ticketKey, query, sort, databases, reopen,
		top, limit, from)

	requestSize := uint32(len(request))
	buf := make([]byte, 4)
	buf[0] = byte((requestSize >> 24) & 0xFF)
	buf[1] = byte((requestSize >> 16) & 0xFF)
	buf[2] = byte((requestSize >> 8) & 0xFF)
	buf[3] = byte(requestSize & 0xFF)

	n, err := socket.Write(buf)
	if n < 4 || err != nil {
		log.Println("@ERR QUERY: ERR SENDING REQUEST SIZE ", err)
		ctx.Response.SetStatusCode(int(InternalServerError))
		return
	}

	n, err = socket.Write([]byte(request))
	if uint32(n) < requestSize || err != nil {
		log.Println("@ERR QUERY: ERR SENDING REQUEST ", err)
		ctx.Response.SetStatusCode(int(InternalServerError))
		return
	}

	n, err = socket.Read(buf)
	if n < 4 || err != nil {
		log.Println("@ERR QUERY: ERR READING RESPONSE SIZE ", err)
		ctx.Response.SetStatusCode(int(InternalServerError))
		return
	}
	responseSize := uint32(0)
	for i := 0; i < 4; i++ {
		responseSize = (responseSize << 8) + uint32(buf[i])
	}

	response := make([]byte, responseSize)
	n, err = socket.Read(response)
	if uint32(n) < responseSize || err != nil {
		log.Println("@ERR QUERY: ERR READING RESPONSE ", err)
		ctx.Response.SetStatusCode(int(InternalServerError))
		return
	}

	socket.Close()

	log.Println("@QUERY RESPONSE ", string(response))
	ctx.Response.SetStatusCode(int(Ok))
	ctx.Write(response)
}
