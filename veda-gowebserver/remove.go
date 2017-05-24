package main

import (
	"encoding/json"
	"log"
	"time"

	"github.com/valyala/fasthttp"
)

func removeFromIndividual(ctx *fasthttp.RequestCtx) {
	var jsonData map[string]interface{}
	err := json.Unmarshal(ctx.Request.Body(), &jsonData)
	if err != nil {
		log.Println("@ERR REMOVE_FROM_INDIVIDUAL: DECODING JSON REQUEST ", err)
		ctx.Response.SetStatusCode(int(InternalServerError))
		return
	}

	log.Println("@REMOVE FROM INDIVIDUAL JSON ", jsonData)
}

func removeIndividual(ctx *fasthttp.RequestCtx) {
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

	rc, _ := getTicket(ticketKey)
	if rc != Ok {
		ctx.Response.SetStatusCode(int(rc))
		return
	}

	modifyIndividual("remove", ticketKey, "uri", jsonData["uri"].(string),
		prepareEvents, eventID, time.Now().Unix(), ctx)
}
