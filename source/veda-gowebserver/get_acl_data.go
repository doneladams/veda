package main

import (
	"log"

	"github.com/valyala/fasthttp"
)

func getAclData(ctx *fasthttp.RequestCtx, operation uint) {
	var uri string
	var ticketKey string
	var ticket ticket

	ticketKey = string(ctx.QueryArgs().Peek("ticket")[:])
	uri = string(ctx.QueryArgs().Peek("uri")[:])

	if len(uri) == 0 {
		log.Println("@ERR GET_INDIVIDUAL: ZERO LENGTH TICKET OR URI")
		ctx.Response.SetStatusCode(int(BadRequest))
		return
	}

	rc, ticket := getTicket(ticketKey)
	if rc != Ok {
		ctx.Response.SetStatusCode(int(rc))
		return
	}

	rr := conn.Authorize(true, ticket.UserURI, []string{uri}, operation, false, true)
	if rr.CommonRC != Ok {
		log.Printf("@ERR GET_ACL_DATA %v: AUTH %v\n", operation, rr.CommonRC)
		ctx.Response.SetStatusCode(int(rr.CommonRC))
		return
	}

	ctx.Write([]byte(rr.Data[0]))
	ctx.Response.SetStatusCode(int(Ok))
}
