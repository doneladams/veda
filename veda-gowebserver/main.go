package main

import (
	"fmt"
	"log"
	"os"

	"bytes"

	"strconv"

	"time"

	"github.com/muller95/lmdb-go/lmdb"
	"github.com/op/go-nanomsg"
	"github.com/valyala/fasthttp"
	"gopkg.in/vmihailenco/msgpack.v2"
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

func lmdbFindTicket(key string, ticket *ticket) ResultCode {
	var ticketMsgpack []byte

	if key == "" || key == "systicket" {
		key = "guest"
	}

	lmdbEnv, err := lmdb.NewEnv()
	if err != nil {
		log.Println("@ERR CREATING LMDB ENV")
		return InternalServerError
	}

	err = lmdbEnv.SetMaxDBs(1)
	if err != nil {
		log.Println("@ERR SETTING MAX DBS ", err)
		return InternalServerError
	}
	lmdbEnv.Open(lmdbTicketsDBPath, 0, os.ModePerm)

	err = lmdbEnv.View(func(txn *lmdb.Txn) (err error) {
		dbi, err := txn.OpenDBI("", 0)
		if err != nil {
			return err
		}

		ticketMsgpack, err = txn.Get(dbi, []byte(key[:]))
		if err != nil {
			return err
		}
		return nil
	})
	if lmdb.IsNotFound(err) {
		return NotFound
	}
	if err != nil {
		log.Println("@ERR ON VIEW ", err)
		return InternalServerError
	}

	decoder := msgpack.NewDecoder(bytes.NewReader(ticketMsgpack))
	decoder.DecodeArrayLen()
	ticket.Id, _ = decoder.DecodeString()
	resMapI, _ := decoder.DecodeMap()
	resMap := resMapI.(map[interface{}]interface{})
	for mapKeyI, mapValI := range resMap {
		mapKey := mapKeyI.(string)

		switch mapKey {
		case "ticket:accessor":
			ticket.UserURI = mapValI.([]interface{})[0].([]interface{})[1].(string)

		case "ticket:when":
			startTime, _ := time.Parse("2006-01-02T15:04:05.0000000", mapValI.([]interface{})[0].([]interface{})[1].(string))
			ticket.StartTime = startTime.Unix()

		case "ticket:duration":
			endTime, _ := strconv.ParseInt(mapValI.([]interface{})[0].([]interface{})[1].(string), 10, 64)
			ticket.EndTime = ticket.StartTime + endTime
		}
	}

	return Ok
}

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
