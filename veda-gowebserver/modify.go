package main

import (
	"encoding/json"
	"log"

	"github.com/valyala/fasthttp"
)

func modifyIndividual(cmd, ticketKey string, individualsJSON []map[string]interface{}, prepareEvents bool,
	eventID string, startTime int64, ctx *fasthttp.RequestCtx) {
	request := make(map[string]interface{})

	request["function"] = cmd
	request["ticket"] = ticketKey
	request["individuals"] = individualsJSON
	request["prepare_events"] = prepareEvents
	request["event_id"] = eventID

	jsonRequest, err := json.Marshal(request)
	if err != nil {
		log.Printf("@ERR MODIFY INDIVIDUAL CMD %v: ENCODE JSON REQUEST: %v\n", cmd, err)
		ctx.Response.SetStatusCode(int(InternalServerError))
		return
	}

	socket.Send(jsonRequest, 0)
	log.Println("@WAIT FOR ANSWER")
	responseBuf, _ := socket.Recv(0)
	responseJSON := make(map[string]interface{})
	err = json.Unmarshal(responseBuf[:len(responseBuf)-1], &responseJSON)
	if err != nil {
		log.Printf("@ERR MODIFY INDIVIDUAL CMD %v: DECODE JSON RESPONSE: %v\n", cmd, err)
		ctx.Response.SetStatusCode(int(InternalServerError))
		return
	}
	data := responseJSON["data"].([]interface{})[0].(map[string]interface{})
	ctx.Response.SetStatusCode(int(data["result"].(float64)))
	dataJSON, _ := json.Marshal(data)
	ctx.Write(dataJSON)
}
