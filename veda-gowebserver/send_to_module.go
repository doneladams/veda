package main

import (
	"encoding/json"
	"log"

	"github.com/valyala/fasthttp"
)

func sendToModule(ctx *fasthttp.RequestCtx) {
	log.Println("@SEND TO MODULE")
	log.Println("@QUERY ", string(ctx.QueryArgs().QueryString()))

	moduleId, _ := ctx.QueryArgs().GetUint("module_id")
	msg := string(ctx.QueryArgs().Peek("msg")[:])

	request := make(map[string]interface{})
	request["function"] = "send_to_module"
	request["module_id"] = moduleId
	request["msg"] = msg

	jsonRequest, err := json.Marshal(request)
	if err != nil {
		log.Printf("@ERR SEND_TO_MODULE: ENCODE JSON REQUEST: %v\n", err)
		ctx.Response.SetStatusCode(int(InternalServerError))
		return
	}

	log.Println(string(jsonRequest))
	socket.Send(jsonRequest, 0)
	responseBuf, _ := socket.Recv(0)

	responseJSON := make(map[string]interface{})
	err = json.Unmarshal(responseBuf[:len(responseBuf)-1], &responseJSON)
	if err != nil {
		log.Printf("@ERR SEND_TO_MODULE: DECODE JSON RESPONSE: %v\n", err)
		ctx.Response.SetStatusCode(int(InternalServerError))
		return
	}
	log.Println(responseJSON)
	ctx.Response.SetStatusCode(int(responseJSON["result"].(float64)))
}
