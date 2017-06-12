package main

import (
	"encoding/json"
	"log"

	"github.com/valyala/fasthttp"
)

func authenticate(ctx *fasthttp.RequestCtx) {
	request := make(map[string]interface{})

	request["function"] = "authenticate"
	request["login"] = string(ctx.QueryArgs().Peek("login")[:])
	request["password"] = string(ctx.QueryArgs().Peek("password")[:])

	jsonRequest, err := json.Marshal(request)
	if err != nil {
		log.Printf("@ERR AUTHENTICATE: ENCODE JSON REQUEST: %v\n", err)
		ctx.Response.SetStatusCode(int(InternalServerError))
		return
	}

	socket.Send(jsonRequest, 0)
	responseBuf, _ := socket.Recv(0)
	responseJSON := make(map[string]interface{})
	err = json.Unmarshal(responseBuf[:len(responseBuf)-1], &responseJSON)
	if err != nil {
		log.Printf("@ERR MODIFY AUTHENTICATE: DECODE JSON RESPONSE: %v\n", err)
		ctx.Response.SetStatusCode(int(InternalServerError))
		return
	}

	authResponse := make(map[string]interface{})
	authResponse["end_time"] = responseJSON["end_time"]
	authResponse["id"] = responseJSON["id"]
	authResponse["user_uri"] = responseJSON["user_uri"]
	authResponse["result"] = responseJSON["result"]

	authResponseBuf, err := json.Marshal(authResponse)
	if err != nil {
		log.Printf("@ERR AUTHENTICATE: ENCODE JSON AUTH RESPONSE: %v\n", err)
		ctx.Response.SetStatusCode(int(InternalServerError))
		return
	}

	ctx.SetStatusCode(int(Ok))
	ctx.Write(authResponseBuf)
}
