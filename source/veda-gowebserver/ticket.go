package main

import (
	"bytes"
	"encoding/json"
	"log"
	"strconv"
	"time"

	msgpack "gopkg.in/vmihailenco/msgpack.v2"

	"github.com/valyala/fasthttp"
)

func getTicket(ticketKey string) (ResultCode, ticket) {
	var ticket ticket

	if ticketKey == "" || ticketKey == "systicket" {
		ticketKey = "guest"
	}

	if ticketCache[ticketKey].Id != "" {
		ticket = ticketCache[ticketKey]
		if time.Now().Unix() > ticket.EndTime {
			delete(ticketCache, ticketKey)
			log.Printf("@TICKET %v FROM USER %v EXPIRED: START %v END %v NOW %v\n", ticket.Id, ticket.UserURI,
				ticket.StartTime, ticket.EndTime, time.Now().Unix())
			return TicketExpired, ticket
		}
	} else {
		rr := conn.GetTicket([]string{ticketKey}, false)
		if rr.CommonRC != Ok {
			log.Println("@ERR ON GET TICKET FROM TARANTOOL")
			return InternalServerError, ticket
		}

		if rr.OpRC[0] != Ok {
			return rr.OpRC[0], ticket
		}

		decoder := msgpack.NewDecoder(bytes.NewReader([]byte(rr.Data[0])))
		decoder.DecodeArrayLen()

		var duration int64

		ticket.Id, _ = decoder.DecodeString()
		resMapI, _ := decoder.DecodeMap()
		resMap := resMapI.(map[interface{}]interface{})
		for mapKeyI, mapValI := range resMap {
			mapKey := mapKeyI.(string)

			switch mapKey {
			case "ticket:accessor":
				ticket.UserURI = mapValI.([]interface{})[0].([]interface{})[1].(string)

			case "ticket:when":
				tt := mapValI.([]interface{})[0].([]interface{})[1].(string)
				mask := "2006-01-02T15:04:05.00000000"
				startTime, _ := time.Parse(mask[0:len(tt)], tt)
				ticket.StartTime = startTime.Unix()

			case "ticket:duration":
				duration, _ = strconv.ParseInt(mapValI.([]interface{})[0].([]interface{})[1].(string), 10, 64)
			}
		}
		ticket.EndTime = ticket.StartTime + duration

		ticketCache[ticketKey] = ticket
	}

	if areExternalUsers {
		log.Printf("check external user (%s)\n", ticket.UserURI)
		_, ok := externalUsersTicketId[ticket.Id]
		if !ok {
			rr := conn.Get(false, "cfg:VedaSystem", []string{ticket.UserURI}, false)
			user := MsgpackToMap(rr.Data[0])
			data, ok := user["v-s:origin"]
			if !ok || (ok && !data.(map[string]interface{})["data"].(bool)) {
				log.Printf("ERR! user (%s) is not external\n", ticket.UserURI)
				ticket.Id = "?"
				ticket.result = NotAuthorized
			} else if ok && data.(map[string]interface{})["data"].(bool) {
				log.Printf("user is external (%s)\n", ticket.UserURI)
				externalUsersTicketId[ticket.UserURI] = true
			}
		}
	}

	return Ok, ticket
}

func isTicketValid(ctx *fasthttp.RequestCtx) {
	var ticketKey string
	ticketKey = string(ctx.QueryArgs().Peek("ticket")[:])
	rc, _ := getTicket(ticketKey)
	if rc != Ok && rc != TicketExpired {
		ctx.Write(codeToJsonException(rc))
		ctx.Response.SetStatusCode(int(rc))
		return
	} else if rc == TicketExpired {
		ctx.Write([]byte("false"))
		ctx.Response.SetStatusCode(int(rc))
		return
	}

	ctx.Write([]byte("true"))
	ctx.Response.SetStatusCode(int(Ok))
}

func getTicketTrusted(ctx *fasthttp.RequestCtx) {
	log.Println("@GET TICKET TRUSTED")
	var ticketKey, login string

	ticketKey = string(ctx.QueryArgs().Peek("ticket")[:])
	login = string(ctx.QueryArgs().Peek("login")[:])

	request := make(map[string]interface{})
	request["function"] = "get_ticket_trusted"
	request["ticket"] = ticketKey
	request["login"] = login

	jsonRequest, err := json.Marshal(request)
	if err != nil {
		log.Printf("@ERR GET_TICKET_TRUSTED: ENCODE JSON REQUEST: %v\n", err)
		ctx.Response.SetStatusCode(int(InternalServerError))
		return
	}

	socket.Send(jsonRequest, 0)
	responseBuf, _ := socket.Recv(0)
	responseJSON := make(map[string]interface{})
	err = json.Unmarshal(responseBuf[:len(responseBuf)-1], &responseJSON)
	if err != nil {
		log.Printf("@ERR GET_TICKET_TRUSTED: DECODE JSON RESPONSE: %v\n", err)
		ctx.Response.SetStatusCode(int(InternalServerError))
		return
	}

	getTicketResponse := make(map[string]interface{})
	getTicketResponse["end_time"] = responseJSON["end_time"]
	getTicketResponse["id"] = responseJSON["id"]
	getTicketResponse["user_uri"] = responseJSON["user_uri"]
	getTicketResponse["result"] = responseJSON["result"]

	if err != nil {
		log.Printf("@ERR GET_TICKET_TRUSTED: ENCODE JSON RESPONSE: %v\n", err)
		ctx.Response.SetStatusCode(int(InternalServerError))
		return
	}
	getTicketResponseBuf, err := json.Marshal(getTicketResponse)

	ctx.SetStatusCode(int(responseJSON["result"].(float64)))
	ctx.Write(getTicketResponseBuf)
}
