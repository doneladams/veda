package main

import (
	"encoding/json"
	"log"

	"github.com/valyala/fasthttp"
)

//authenticate checks validity of login and password and gives user new ticket
func authenticate(ctx *fasthttp.RequestCtx) {
	request := make(map[string]interface{})

	//fill request to veda-server
	request["function"] = "authenticate"
	request["login"] = string(ctx.QueryArgs().Peek("login")[:])
	request["password"] = string(ctx.QueryArgs().Peek("password")[:])

	//encode request to json
	jsonRequest, err := json.Marshal(request)
	if err != nil {
		log.Printf("@ERR AUTHENTICATE: ENCODE JSON REQUEST: %v\n", err)
		ctx.Response.SetStatusCode(int(InternalServerError))
		return
	}

	//send request via nanomsg socket and reading response
	socket.Send(jsonRequest, 0)
	responseBuf, _ := socket.Recv(0)
	//decoding authenticate response json
	responseJSON := make(map[string]interface{})
	err = json.Unmarshal(responseBuf[:len(responseBuf)-1], &responseJSON)
	if err != nil {
		log.Printf("@ERR MODIFY AUTHENTICATE: DECODE JSON RESPONSE: %v\n", err)
		ctx.Response.SetStatusCode(int(InternalServerError))
		return
	}

	//fill and encode json response	to client
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

	//check if external users feature is enabled
	if areExternalUsers {
		//loging about external user authentication checl
		log.Printf("authenticate:check external user (%v)\n", authResponse["user_uri"])
		//sending get request to tarantool
		rr := conn.Get(false, "cfg:VedaSystem", []string{authResponse["user_uri"].(string)}, false)
		//decoding msgpack to individual map
		user := BinobjToMap(rr.Data[0])
		data, ok := user["v-s:origin"]
		if !ok || (ok && !data.(map[string]interface{})["data"].(bool)) {
			//if v-s:origin not found or value is false than return NotAuthorized
			log.Printf("ERR! user (%v) is not external\n", authResponse["user_uri"])
			authResponse["end_time"] = 0
			authResponse["id"] = ""
			authResponse["user_uri"] = ""
			authResponse["result"] = NotAuthorized
		} else if ok && data.(map[string]interface{})["data"].(bool) {
			//else set externals users ticket id to true valuse
			externalUsersTicketId[authResponse["user_uri"].(string)] = true
		}
	}

	ctx.SetStatusCode(int(Ok))
	ctx.Write(authResponseBuf)
}
