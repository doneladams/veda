package main

import (
	"encoding/json"
	"log"
	"time"

	"github.com/valyala/fasthttp"
)

func removeFromIndividual(ctx *fasthttp.RequestCtx) {
	timestamp := time.Now().Unix()

	var prepareEvents bool
	var ticketKey, eventID string
	// var ticket ticket

	var jsonData map[string]interface{}
	err := json.Unmarshal(ctx.Request.Body(), &jsonData)
	if err != nil {
		log.Println("@ERR REMOVE_FROM_INDIVIDUAL: DECODING JSON REQUEST ", err)
		ctx.Response.SetStatusCode(int(InternalServerError))
		return
	}

	ticketKey = jsonData["ticket"].(string)
	prepareEvents = jsonData["prepare_events"].(bool)
	eventID = jsonData["event_id"].(string)

	rc, ticket := getTicket(ticketKey)
	if rc != Ok {
		ctx.Response.SetStatusCode(int(rc))
		trail(ticket.Id, ticket.UserURI, "remove_from", jsonData, "", rc, timestamp)
		return
	}

	rc = modifyIndividual("remove_from", &ticket, "individuals", []map[string]interface{}{jsonData["individual"].(map[string]interface{})},
		prepareEvents, eventID, time.Now().Unix(), ctx)
	trail(ticket.Id, ticket.UserURI, "remove_from", jsonData, "", rc, timestamp)
}

func removeIndividual(ctx *fasthttp.RequestCtx) {
	timestamp := time.Now().Unix()

	var prepareEvents bool
	var ticketKey, eventID string
	// var ticket ticket

	var jsonData map[string]interface{}
	err := json.Unmarshal(ctx.Request.Body(), &jsonData)
	if err != nil {
		log.Println("@ERR REMOVE_INDIVIDUAL: DECODING JSON REQUEST ", err)
		ctx.Response.SetStatusCode(int(InternalServerError))
		return
	}

	ticketKey = jsonData["ticket"].(string)
	prepareEvents = jsonData["prepare_events"].(bool)
	eventID = jsonData["event_id"].(string)

	rc, ticket := getTicket(ticketKey)
	if rc != Ok {
		ctx.Response.SetStatusCode(int(rc))
		trail(ticket.Id, ticket.UserURI, "remove_individual", jsonData, "", rc, timestamp)

		return
	}

	log.Println("@REMOVE ", jsonData["uri"])

	rc = modifyIndividual("remove", &ticket, "uri", jsonData["uri"].(string),
		prepareEvents, eventID, time.Now().Unix(), ctx)
	trail(ticket.Id, ticket.UserURI, "remove_individual", jsonData, "", rc, timestamp)
}
