package main

import (
	"fmt"
	"log"
	"time"

	"github.com/op/go-nanomsg"
	"github.com/valyala/fasthttp"
)

type ResultCode uint32

const (
	Ok                  ResultCode = 200
	BadRequest          ResultCode = 400
	NotAuthorized       ResultCode = 472
	NotFound            ResultCode = 404
	InternalServerError ResultCode = 50
	TicketExpired       ResultCode = 471
	NoContent           ResultCode = 204
	SizeTooLarge        ResultCode = 1118
)

type ticket struct {
	Id        string
	UserURI   string
	result    ResultCode
	StartTime int64
	EndTime   int64
}

const (
	lmdbTicketsDBPath = "./data/lmdb-tickets"
)

var ticketCache map[string]ticket
var conn Connector
var socket *nanomsg.Socket
var endpoint *nanomsg.Endpoint
var vedaServerURL = "tcp://127.0.0.1:9112"

func requestHandler(ctx *fasthttp.RequestCtx) {
	switch string(ctx.Path()[:]) {
	case "/get_individual":
		getIndividual(ctx)
	case "/get_individuals":
		getIndividuals(ctx)

	case "/put_individual":
		putIndividual(ctx)
	case "/put_individuals":
		putIndividuals(ctx)

	case "/remove_individual":
		removeIndividual(ctx)
	case "/remove_from_individual":
		removeFromIndividual(ctx)

	case "/set_in_individual":
		setInIndividual(ctx)

	case "/add_to_individual":
		addToIndividual(ctx)

	case "/authenticate":
		fmt.Println("authenticate")
	case "/tests":
		ctx.SendFile("public/tests.html")
	default:
		fasthttp.FSHandler("public/", 0)(ctx)
	}
}

func main() {
	var err error
	socket, err = nanomsg.NewSocket(nanomsg.AF_SP, nanomsg.REQ)
	if err != nil {
		log.Fatal("@ERR ON CREATING SOCKET")
	}

	endpoint, err = socket.Connect(vedaServerURL)
	for err != nil {
		endpoint, err = socket.Connect(vedaServerURL)
		time.Sleep(3000 * time.Millisecond)
	}

	conn.Connect("127.0.0.1:9999")
	log.Println("@CONNECTED")
	ticketCache = make(map[string]ticket)
	err = fasthttp.ListenAndServe("0.0.0.0:8101", requestHandler)
	if err != nil {
		log.Fatal("@ERR ON STARTUP WEBSERVER ", err)
	}
}
