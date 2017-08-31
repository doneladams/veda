package main

import (
	"encoding/json"
	"log"
	"time"

	"github.com/valyala/fasthttp"
)

func putIndividual(ctx *fasthttp.RequestCtx) {
	timestamp := time.Now().Unix()

	var prepareEvents bool
	var ticketKey, eventID string
	// var ticket ticket

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

	rc, ticket := getTicket(ticketKey)
	if rc != Ok {
		ctx.Response.SetStatusCode(int(rc))
		trail(ticket.Id, ticket.UserURI, "put", jsonData, "", rc, timestamp)
		return
	}

	rc = modifyIndividual("put", &ticket, "individuals", []map[string]interface{}{jsonData["individual"].(map[string]interface{})},
		prepareEvents, eventID, time.Now().Unix(), ctx)
	trail(ticket.Id, ticket.UserURI, "put", jsonData, "", rc, timestamp)

}

func putIndividuals(ctx *fasthttp.RequestCtx) {
	timestamp := time.Now().Unix()

	var prepareEvents bool
	var ticketKey, eventID string
	// var ticket ticket

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

	rc, ticket := getTicket(ticketKey)
	if rc != Ok {
		ctx.Response.SetStatusCode(int(rc))
		trail(ticket.Id, ticket.UserURI, "put", jsonData, "", rc, timestamp)

		return
	}

	individualsI := jsonData["individuals"].([]interface{})
	individuals := make([]map[string]interface{}, len(individualsI))
	for i := 0; i < len(individualsI); i++ {
		individuals[i] = individualsI[i].(map[string]interface{})
	}

	rc = modifyIndividual("put", &ticket, "individuals", individuals,
		prepareEvents, eventID, time.Now().Unix(), ctx)
	trail(ticket.Id, ticket.UserURI, "put", jsonData, "", rc, timestamp)

}
