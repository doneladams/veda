package main

import (
	"encoding/json"
	"log"

	"github.com/valyala/fasthttp"
)

func getIndividual(ctx *fasthttp.RequestCtx) {
	var uri string
	var ticketKey string
	var ticket ticket
	ticketKey = string(ctx.QueryArgs().Peek("ticket")[:])
	uri = string(ctx.QueryArgs().Peek("uri")[:])

	log.Println("\t@getIndividual: ticket=", ticketKey, ", uri=", uri)

	if len(uri) == 0 {
		log.Println("@ERR GET_INDIVIDUAL: ZERO LENGTH TICKET OR URI")
		log.Println("\t@REQUEST QUERY STRING ", string(ctx.QueryArgs().QueryString()))
		ctx.Response.SetStatusCode(int(BadRequest))
		return
	}


	rc, ticket := getTicket(ticketKey)
	if rc != Ok {
		log.Println("@ERR GET TICKET GET_INDIVIDUAL ", rc)
		log.Println("\t@REQUEST BODY ", string(ctx.Request.Body()))
		ctx.Response.SetStatusCode(int(rc))
		return
	}

	log.Println("\t@2")
	individual, ok := ontologyCache[uri]
	if ok {
		individualJSON, err := json.Marshal(individual)
		if err != nil {
			log.Println("@ERR GET_INDIVIDUAL: ENCODING INDIVIDUAL TO JSON ", err)
			ctx.Response.SetStatusCode(int(InternalServerError))
			return
		}

		ctx.Write(individualJSON)
		ctx.Response.SetStatusCode(int(Ok))
		return
	}
	log.Println("\t@3")

	uris := make([]string, 1)
	uris[0] = uri
	rr := conn.Get(true, ticket.UserURI, uris, false)

	log.Println("\t@4 rr=", rr)

	if rr.CommonRC != Ok {
	log.Println("\t@5")
		log.Println("@ERR GET_INDIVIDUAL: GET INDIVIDUAL COMMON ", rr.CommonRC)
		ctx.Response.SetStatusCode(int(rr.CommonRC))
		return
	} else if rr.OpRC[0] != Ok {
	log.Println("\t@6")
		ctx.Response.SetStatusCode(int(rr.OpRC[0]))
		return
	} else {

	log.Println("\t@7")
		individual = MsgpackToMap(rr.Data[0])
		if individual == nil {
			log.Println("@ERR GET_INDIVIDUAL: DECODING INDIVIDUAL")
			ctx.Response.SetStatusCode(int(InternalServerError))
			return
		}
	log.Println("\t@8")

		individualJSON, err := json.Marshal(individual)
		if err != nil {
			log.Println("@ERR GET_INDIVIDUAL: ENCODING INDIVIDUAL TO JSON ", err)
			ctx.Response.SetStatusCode(int(InternalServerError))
			return
		}
	log.Println("\t@9")

		tryStoreInOntologyCache(individual)
		ctx.Write(individualJSON)
	}

	log.Println("\t@e")

	ctx.Response.SetStatusCode(int(Ok))
	return
}

func getIndividuals(ctx *fasthttp.RequestCtx) {
	var jsonData map[string]interface{}
	var uris []string
	var ticketKey string
	var ticket ticket

	err := json.Unmarshal(ctx.Request.Body(), &jsonData)
	if err != nil {
		log.Println("@ERR GET_INDIVIDUALS: DECODING JSON REQUEST ", err)
		ctx.Response.SetStatusCode(int(InternalServerError))
		return
	}

	ticketKey = jsonData["ticket"].(string)

	rc, ticket := getTicket(ticketKey)
	if rc != Ok {
		ctx.Response.SetStatusCode(int(rc))
		return
	}

	uris = make([]string, len(jsonData["uris"].([]interface{})))
	for i := 0; i < len(jsonData["uris"].([]interface{})); i++ {
		uris[i] = jsonData["uris"].([]interface{})[i].(string)
	}

	if len(uris) == 0 {
		log.Println("@ERR GET_INDIVIDUALS: ZERO LENGTH TICKET OR URI")
		log.Println("\t@REQUEST BODY ", string(ctx.Request.Body()))
		ctx.Response.SetStatusCode(int(BadRequest))
		return
	}

	individuals := make([]map[string]interface{}, 0, len(uris))
	urisToGet := make([]string, 0, len(uris))
	for i := 0; i < len(uris); i++ {
		individual, ok := ontologyCache[uris[i]]
		if ok {
			individuals = append(individuals, individual)
		} else {
			urisToGet = append(urisToGet, uris[i])
		}
	}

	/*if len(urisToGet) > 0 {
		for i := 0; i < len
		rr := conn.Get(true, ticket.UserURI, urisToGet, false)
		if rr.CommonRC != Ok {
			log.Println("@ERR GET_INDIVIDUALS: GET COMMON ", rr.CommonRC)
			ctx.Response.SetStatusCode(int(rr.CommonRC))
			return
		}

		for i := 0; i < len(rr.Data); i++ {

			// log.Println("i=", i)
			// log.Println("rr.Data[i]=", rr.Data[i])
			// log.Println("rr.OpRC[i]=", rr.OpRC[i])
			if rr.OpRC[i] == Ok {
				individual := MsgpackToMap(rr.Data[i])
				if individual == nil {
					log.Println("@ERR GET_INDIVIDUALS: DECODING INDIVIDUAL")
					ctx.Response.SetStatusCode(int(InternalServerError))
					return
				}

				tryStoreInOntologyCache(individual)
				individuals = append(individuals, individual)
			}

			if err != nil {
				log.Println("@ERR ENCODING INDIVIDUAL TO JSON ", err)
				ctx.Response.SetStatusCode(int(InternalServerError))
				return
			}

		}
	}*/

	for i := 0; i < len(urisToGet); i++ {
		rr := conn.Get(true, ticket.UserURI, []string{urisToGet[i]}, false)
		if rr.CommonRC != Ok {
			log.Println("@ERR GET_INDIVIDUALS: GET COMMON ", rr.CommonRC)
			ctx.Response.SetStatusCode(int(rr.CommonRC))
			continue
		}

		if rr.OpRC[0] == Ok {
			individual := MsgpackToMap(rr.Data[0])
			if individual == nil {
				log.Println("@ERR GET_INDIVIDUALS: DECODING INDIVIDUAL")
				ctx.Response.SetStatusCode(int(InternalServerError))
				return
			}

			tryStoreInOntologyCache(individual)
			individuals = append(individuals, individual)
		}

		if err != nil {
			log.Println("@ERR ENCODING INDIVIDUAL TO JSON ", err)
			ctx.Response.SetStatusCode(int(InternalServerError))
			return
		}
	}
	individualsJSON, err := json.Marshal(individuals)
	if err != nil {
		log.Println("@ERR GET_INDIVIDUALS: ENCODING INDIVIDUALS JSON ", err)
	}

	ctx.Write(individualsJSON)
	ctx.Response.SetStatusCode(int(Ok))
}
