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

	if areExternalUsers {
		log.Printf("authenticate:check external user (%v)\n", authResponse["user_uri"])
		rr := conn.Get(false, "cfg:VedaSystem", []string{authResponse["user_uri"].(string)}, false)
		user := MsgpackToMap(rr.Data[0])
		data, ok := user["v-s:origin"]
		if !ok || (ok && !data.(map[string]interface{})["data"].(bool)) {
			log.Printf("ERR! user (%v) is not external\n", authResponse["user_uri"])
			authResponse["end_time"] = 0
			authResponse["id"] = ""
			authResponse["user_uri"] = ""
			authResponse["result"] = NotAuthorized
		} else if ok && data.(map[string]interface{})["data"].(bool) {
			externalUsersTicketId[authResponse["user_uri"].(string)] = true
		}
	}

	ctx.SetStatusCode(int(Ok))
	ctx.Write(authResponseBuf)
}
