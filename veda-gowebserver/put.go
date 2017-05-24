package main

import (
	"encoding/json"
	"log"
	"time"

	"github.com/valyala/fasthttp"
)

func putIndividual(ctx *fasthttp.RequestCtx) {
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

	modifyIndividual("put", ticketKey, "individuals", []map[string]interface{}{jsonData["individual"].(map[string]interface{})},
		prepareEvents, eventID, time.Now().Unix(), ctx)
}

func putIndividuals(ctx *fasthttp.RequestCtx) {
	log.Println("@PUT INDIVIDUALS")
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

	log.Println("@JSON ", jsonData)
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

	individualsI := jsonData["individuals"].([]interface{})
	individuals := make([]map[string]interface{}, len(individualsI))
	for i := 0; i < len(individualsI); i++ {
		individuals[i] = individualsI[i].(map[string]interface{})
	}

	log.Println("@MODIFY")
	modifyIndividual("put", ticketKey, "individuals", individuals,
		prepareEvents, eventID, time.Now().Unix(), ctx)
	log.Println("@DONE")
}
