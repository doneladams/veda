package main

import (
	"encoding/json"
	"log"
	"strconv"
	//"strings"
	"github.com/valyala/fasthttp"
	"time"
)

//getTicket handles get_ticket request
//it requests ticket from tarantool by the given id
//and checks its validity
func getTicket(ticketKey string) (ResultCode, ticket) {
	var ticket ticket

	//if no ticket id or systicket passed then change it to guest
	if ticketKey == "" || ticketKey == "systicket" {
		ticketKey = "guest"
		ticket.Id = "guest"
		ticket.UserURI = "cfg:Guest"
		ticket.result = Ok
		return Ok, ticket
	}

	//Look for ticket in cache
	ticketCacheMutex.RLock()
	tk := ticketCache[ticketKey]
	ticketCacheMutex.RUnlock()

	if tk.Id != "" {
		//If found check expiration time
		ticket = tk
		if time.Now().Unix() > ticket.EndTime {
			//If expired, delete and return
			ticketCacheMutex.Lock()
			delete(ticketCache, ticketKey)
			ticketCacheMutex.Unlock()

			log.Printf("@TICKET %v FROM USER %v EXPIRED: START %v END %v NOW %v\n", ticket.Id, ticket.UserURI,
				ticket.StartTime, ticket.EndTime, time.Now().Unix())
			return TicketExpired, ticket
		}
	} else {

		//If not found, request it from storage
		rr := conn.GetTicket([]string{ticketKey}, false)
		//If common response code is not Ok return fail code
		if rr.CommonRC != Ok {
			log.Println("ERR! ON GET TICKET")
			return InternalServerError, ticket
		}

		//If operation code is not Ok return fail code
		if rr.OpRC[0] != Ok {
			return rr.OpRC[0], ticket
		}

		individual := rr.GetIndv(0)

		var duration int64

		ticket.UserURI, _ = getFirstString(individual, "ticket:accessor")
		tt, _ := getFirstString(individual, "ticket:when")
		mask := "2006-01-02T15:04:05.00000000"
		startTime, _ := time.Parse(mask[0:len(tt)], tt)
		ticket.StartTime = startTime.Unix()
		dd, _ := getFirstString(individual, "ticket:duration")
		duration, _ = strconv.ParseInt(dd, 10, 64)

		ticket.Id = ticketKey
		ticket.EndTime = ticket.StartTime + duration

		if areExternalUsers {
			//If external users feature is enabled
			log.Printf("getTicket::check external user (%s)\n", ticket.UserURI)
			//If ticket not found then get user from tarantool and decode it
			rr := conn.Get(false, "cfg:VedaSystem", []string{ticket.UserURI}, false, false)
			user := rr.GetIndv(0)
			//Check its field v-s:origin

			origin, ok := getFirstString(user, "v-s:origin")
			if !ok || (ok && origin != "External User") {
				//If this field not found or it contains false then return error code
				log.Printf("ERR! user (%s) is not external\n", ticket.UserURI)
				ticket.Id = "?"
				ticket.result = NotAuthorized
			} else if ok && origin == "External User" {
				//Else store ticket to cache
				log.Printf("user is external (%s)\n", ticket.UserURI)
			}

		}

		//Save ticket in the cache
		ticketCacheMutex.Lock()
		ticketCache[ticketKey] = ticket
		ticketCacheMutex.Unlock()

	}

	return Ok, ticket
}

//isTicketValid handles is_ticket_valid request
func isTicketValid(ctx *fasthttp.RequestCtx) {
	var ticketKey string
	//Decode parametrs from requestn context
	ticketKey = string(ctx.QueryArgs().Peek("ticket")[:])
	//Get ticket with the given id from tarantool
	rc, _ := getTicket(ticketKey)
	//If errored but NotTicketExpired return error to client
	if rc != Ok && rc != TicketExpired {
		ctx.Write(codeToJsonException(rc))
		ctx.Response.SetStatusCode(int(rc))
		return
	} else if rc == TicketExpired {
		//If TicketExpired then return false
		ctx.Write([]byte("false"))
		ctx.Response.SetStatusCode(int(rc))
		return
	}

	//If ticket with Ok rc, return true
	ctx.Write([]byte("true"))
	ctx.Response.SetStatusCode(int(Ok))
}

//getTicketTrusted handles get_ticket_trusted request
func getTicketTrusted(ctx *fasthttp.RequestCtx) {
	log.Println("@GET TICKET TRUSTED")
	var ticketKey, login string

	//Read params from request context
	ticketKey = string(ctx.QueryArgs().Peek("ticket")[:])
	login = string(ctx.QueryArgs().Peek("login")[:])

	//Prepare request to veda server with function get_ticket_trusted
	request := make(map[string]interface{})
	request["function"] = "get_ticket_trusted"
	request["ticket"] = ticketKey
	request["login"] = login

	//Marshal json request
	jsonRequest, err := json.Marshal(request)
	if err != nil {
		log.Printf("ERR! GET_TICKET_TRUSTED: ENCODE JSON REQUEST: %v\n", err)
		ctx.Response.SetStatusCode(int(InternalServerError))
		return
	}

	//Send request to veda server and read response
	NmCSend(g_mstorage_ch, jsonRequest, 0)
	responseBuf, _ := g_mstorage_ch.Recv(0)
	responseJSON := make(map[string]interface{})
	err = json.Unmarshal(responseBuf, &responseJSON)
	if err != nil {
		log.Printf("ERR! GET_TICKET_TRUSTED: DECODE JSON RESPONSE: %v\n", err)
		ctx.Response.SetStatusCode(int(InternalServerError))
		return
	}

	//Decoding resoinse
	getTicketResponse := make(map[string]interface{})
	getTicketResponse["end_time"] = responseJSON["end_time"]
	getTicketResponse["id"] = responseJSON["id"]
	getTicketResponse["user_uri"] = responseJSON["user_uri"]
	getTicketResponse["result"] = responseJSON["result"]

	//Encoding json response and retiurn to client
	getTicketResponseBuf, err := json.Marshal(getTicketResponse)
	if err != nil {
		log.Printf("ERR! GET_TICKET_TRUSTED: ENCODE JSON RESPONSE: %v\n", err)
		ctx.Response.SetStatusCode(int(InternalServerError))
		return
	}

	ctx.SetStatusCode(int(responseJSON["result"].(float64)))
	ctx.Write(getTicketResponseBuf)
}
