package main

import (
	"fmt"
	"log"
	"os"

	"bytes"

	"strconv"

	"time"

	"encoding/json"

	"github.com/bmatsuo/lmdb-go/lmdb"
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

func getRequestData(ctx *fasthttp.RequestCtx) (string, string, bool) {
	var reopen bool
	var uri, ticket string
	if string(ctx.Method()[:]) == "GET" {
		// log.Println("@GET QUERY ARGS")
		// log.Println("@QUERY ", string(ctx.QueryArgs().QueryString()[:]))
		ticket = string(ctx.QueryArgs().Peek("ticket")[:])
		uri = string(ctx.QueryArgs().Peek("uri")[:])
		reopen = ctx.QueryArgs().GetBool("reopen")
	} else if string(ctx.Method()[:]) == "POST"[:] {
		// log.Println("@POST ARGS")
		// log.Println("@ARGS ", string(ctx.PostArgs().QueryString()[:]))
		ticket = string(ctx.PostArgs().Peek("ticket")[:])
		uri = string(ctx.PostArgs().Peek("uri")[:])
		reopen = ctx.PostArgs().GetBool("reopen")
	}

	if ticket == "" {
		ticket = string(ctx.Request.Header.Cookie("ticket")[:])
	}

	return uri, ticket, reopen
}

func getIndividual(ctx *fasthttp.RequestCtx) {
	// var reopen bool
	var uri, ticketKey string
	var ticket ticket

	uri, ticketKey, _ = getRequestData(ctx)
	if len(uri) == 0 || ticketKey == "" {
		ctx.Response.SetStatusCode(int(BadRequest))
		return
	}

	rc := InternalServerError
	if ticketCache[ticketKey].Id != "" {
		ticket = ticketCache[ticketKey]
		rc = Ok
	} else {
		rc = lmdbFindTicket(ticketKey, &ticket)
		if rc == Ok {
			ticketCache[ticketKey] = ticket
		}
	}

	if rc != Ok {
		ctx.Response.SetStatusCode(int(rc))
		return
	}

	if time.Now().Unix() > ticket.EndTime {
		delete(ticketCache, ticketKey)
		ctx.Response.SetStatusCode(int(TicketExpired))
		return
	}

	rr := conn.Get(true, ticket.UserURI, []string{uri}, false)
	if rr.CommonRC != Ok {
		log.Println("@ERR GET INDIVIDUAL COMMON ", rr.CommonRC)
		ctx.Response.SetStatusCode(int(rr.CommonRC))
		return
	} else if rr.OpRC[0] != Ok {
		// log.Println("@ERR GET INDIVIDUAL ", rr.OpRC[0])
		ctx.Response.SetStatusCode(int(rr.OpRC[0]))
		return
	} else {
		individual := MsgpackToJson(rr.Msgpaks[0])
		if individual == nil {
			log.Println("@ERR DECODING INDIVIDUAL")
			ctx.Response.SetStatusCode(int(InternalServerError))
			return
		}

		individualJson, err := json.Marshal(individual)
		if err != nil {
			log.Println("@ERR ENCODING INDIVIDUAL TO JSON ", err)
			ctx.Response.SetStatusCode(int(InternalServerError))
			return
		}
		ctx.Write(individualJson)
	}

	ctx.Response.SetStatusCode(int(Ok))
	return
}

func requestHandler(ctx *fasthttp.RequestCtx) {

	// log.Println("@METHOD ", string(ctx.Method()[:]))
	// log.Println("@PATH ", string(ctx.Path()[:]))
	switch string(ctx.Path()[:]) {
	case "/get_individual":
		getIndividual(ctx)
	case "/get_individuals":
		fmt.Println("get_individuals")
	case "/authenticate":
		fmt.Println("authenticate")
	case "/tests":
		ctx.SendFile("public/tests.html")
	default:
		fasthttp.FSHandler("public/", 0)(ctx)
	}
}

func main() {
	conn.Connect("127.0.0.1:9999")
	log.Println("@CONNECTED")
	ticketCache = make(map[string]ticket)
	err := fasthttp.ListenAndServe("0.0.0.0:8101", requestHandler)
	if err != nil {
		log.Fatal("@ERR ON STARTUP WEBSERVER ", err)
	}
}
