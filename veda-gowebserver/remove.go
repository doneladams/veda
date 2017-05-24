package main

import (
	"encoding/json"
	"log"
	"time"

	"github.com/valyala/fasthttp"
)

func removeIndividual(ctx *fasthttp.RequestCtx) {
	var prepareEvents bool
	var ticketKey, eventID string
	var ticket ticket

	var jsonData map[string]interface{}
	err := json.Unmarshal(ctx.Request.Body(), &jsonData)
	if err != nil {
		log.Println("@ERR PUT_INDIVIDUAL: DECODING JSON REQUEST ", err)
		ctx.Response.SetStatusCode(int(InternalServerError))
		return
	}

	ticketKey = jsonData["ticket"].(string)
	prepareEvents = jsonData["prepare_events"].(bool)
	eventID = jsonData["event_id"].(string)

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

	modifyIndividual("remove", ticketKey, "uri", jsonData["uri"].(string),
		prepareEvents, eventID, time.Now().Unix(), ctx)
}
