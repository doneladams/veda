package main

import (
	"encoding/json"
	"log"
	"time"

	"github.com/valyala/fasthttp"
)

func modifyIndividual(cmd string, ticket *ticket, dataKey string, dataJSON interface{}, prepareEvents bool,
	eventID string, startTime int64, ctx *fasthttp.RequestCtx) ResultCode {
	timestamp := time.Now().Unix()
	request := make(map[string]interface{})

	request["function"] = cmd
	request["ticket"] = ticket.Id
	request[dataKey] = dataJSON
	request["prepare_events"] = prepareEvents
	request["event_id"] = eventID

	jsonRequest, err := json.Marshal(request)
	if err != nil {
		log.Printf("@ERR MODIFY INDIVIDUAL CMD %v: ENCODE JSON REQUEST: %v\n", cmd, err)
		ctx.Response.SetStatusCode(int(InternalServerError))
		return InternalServerError
	}

	socket.Send(jsonRequest, 0)
	responseBuf, _ := socket.Recv(0)
	responseJSON := make(map[string]interface{})
	err = json.Unmarshal(responseBuf[:len(responseBuf)-1], &responseJSON)
	if err != nil {
		log.Printf("@ERR MODIFY INDIVIDUAL CMD %v: DECODE JSON RESPONSE: %v\n", cmd, err)
		ctx.Response.SetStatusCode(int(InternalServerError))
		trail(ticket.Id, ticket.UserURI, cmd, request, "{}", InternalServerError, timestamp)
		return InternalServerError
	}

	responseData := responseJSON["data"].([]interface{})[0].(map[string]interface{})
	ctx.Response.SetStatusCode(int(responseData["result"].(float64)))
	responseDataJSON, _ := json.Marshal(responseData)
	log.Println(string(responseDataJSON))
	ctx.Write(responseDataJSON)

	trail(ticket.Id, ticket.UserURI, cmd, request, string(responseDataJSON),
		ResultCode(responseData["result"].(float64)), timestamp)
	return ResultCode(responseData["result"].(float64))
}
