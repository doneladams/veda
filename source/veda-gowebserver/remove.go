package main

import (
	"encoding/json"
	"log"
	"time"

	"github.com/valyala/fasthttp"
)

//removeFromIndividual function handler remove_from_individual request
func removeFromIndividual(ctx *fasthttp.RequestCtx) {
	timestamp := time.Now().Unix()

	var prepareEvents bool
	var ticketKey, eventID string
	// var ticket ticket

	//Reading request data from context
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

	//Check if ticket is valid, if not then return fail code to client
	rc, ticket := getTicket(ticketKey)
	if rc != Ok {
		ctx.Response.SetStatusCode(int(rc))
		trail(ticket.Id, ticket.UserURI, "remove_from", jsonData, "", rc, timestamp)
		return
	}

	//Send modify request to veda server
	rc = modifyIndividual("remove_from", &ticket, "individuals", []map[string]interface{}{jsonData["individual"].(map[string]interface{})},
		prepareEvents, eventID, time.Now().Unix(), ctx)
	trail(ticket.Id, ticket.UserURI, "remove_from", jsonData, "", rc, timestamp)
}

//removeIndividual handles remove_individual request
func removeIndividual(ctx *fasthttp.RequestCtx) {
	timestamp := time.Now().Unix()

	var prepareEvents bool
	var ticketKey, eventID string
	// var ticket ticket

	//Reading request data from context
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

	//Check if ticket is valid, if not then return fail code to client
	rc, ticket := getTicket(ticketKey)
	if rc != Ok {
		ctx.Response.SetStatusCode(int(rc))
		trail(ticket.Id, ticket.UserURI, "remove_individual", jsonData, "", rc, timestamp)

		return
	}

	//log.Println("@REMOVE ", jsonData["uri"])

	//Send modify request to veda-server
	rc = modifyIndividual("remove", &ticket, "uri", jsonData["uri"].(string),
		prepareEvents, eventID, time.Now().Unix(), ctx)
	trail(ticket.Id, ticket.UserURI, "remove_individual", jsonData, "", rc, timestamp)
}
