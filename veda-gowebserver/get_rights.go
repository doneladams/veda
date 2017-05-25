package main

import (
	"encoding/json"
	"log"

	"github.com/valyala/fasthttp"
)

const (
	AccessCanCreate    uint8 = 1 << 0
	AccessCanRead      uint8 = 1 << 1
	AccessCanUpdate    uint8 = 1 << 2
	AccessCanDelete    uint8 = 1 << 3
	AccessCanNotCreate uint8 = 1 << 4
	AccessCanNotRead   uint8 = 1 << 5
	AccessCanNotUpdate uint8 = 1 << 6
	AccessCanNotDelete uint8 = 1 << 7
	DefaultAccess      uint8 = 15
)

func getRights(ctx *fasthttp.RequestCtx) {
	log.Println("@GET RIGHTS")
	var uri string
	var ticketKey string
	var ticket ticket

	ticketKey = string(ctx.QueryArgs().Peek("ticket")[:])
	uri = string(ctx.QueryArgs().Peek("uri")[:])

	if len(uri) == 0 || ticketKey == "" {
		log.Println("@ERR GET_INDIVIDUAL: ZERO LENGTH TICKET OR URI")
		ctx.Response.SetStatusCode(int(BadRequest))
		return
	}

	rc, ticket := getTicket(ticketKey)
	if rc != Ok {
		ctx.Response.SetStatusCode(int(rc))
		return
	}

	rr := conn.Authorize(true, ticket.UserURI, []string{uri}, false)
	log.Println("@RR ", rr)

	if rr.CommonRC != Ok {
		log.Println("@ERR GET RIGHS: AUTH ", rr.CommonRC)
		ctx.Response.SetStatusCode(int(rr.CommonRC))
		return
	}
	access := rr.Rights[0]
	canCreate := (access & AccessCanCreate) > 0
	canRead := (access & AccessCanRead) > 0
	canUpdate := (access & AccessCanUpdate) > 0
	canDelete := (access & AccessCanDelete) > 0

	/*individual := map[string]interface{}{
		"@":             "_",
		"rdf:type":      "v-s:PermissionStatement",
		"v-s:canCreate": []interface{}{map[string]interface{}{"type": "Boolean", "data": canCreate}},
		"v-s:canRead":   []interface{}{map[string]interface{}{"type": "Boolean", "data": canRead}},
		"v-s:canUpdate": []interface{}{map[string]interface{}{"type": "Boolean", "data": canUpdate}},
		"v-s:canDelete": []interface{}{map[string]interface{}{"type": "Boolean", "data": canDelete}},
	}*/

	individual := make(map[string]interface{})
	individual["@"] = "_"
	individual["data"] = []interface{}{map[string]interface{}{"type": "Uri", "data": "v-s:PermissionStatement"}}
	if canCreate {
		individual["v-s:canCreate"] = []interface{}{map[string]interface{}{"type": "Boolean", "data": canCreate}}
	}

	if canRead {
		individual["v-s:canRead"] = []interface{}{map[string]interface{}{"type": "Boolean", "data": canRead}}
	}

	if canUpdate {
		individual["v-s:canUpdate"] = []interface{}{map[string]interface{}{"type": "Boolean", "data": canUpdate}}
	}

	if canDelete {
		individual["v-s:canDelete"] = []interface{}{map[string]interface{}{"type": "Boolean", "data": canDelete}}
	}

	individualJSON, err := json.Marshal(individual)
	if err != nil {
		log.Println("@ERR GET_INDIVIDUAL: ENCODING INDIVIDUAL TO JSON ", err)
		ctx.Response.SetStatusCode(int(InternalServerError))
		return
	}

	log.Println("@INDIVIDUAL JSON ", string(individualJSON))
	ctx.Response.SetStatusCode(int(Ok))
	ctx.Write(individualJSON)

	/*@GET RIGHTS JSON {"rdf:type":[{"type":"Uri","data":"v-s:PermissionStatement"}],
	"v-s:canUpdate":[{"type":"Boolean","data":true}],
	"v-s:canDelete":[{"type":"Boolean","data":true}],
	"@":"_",
	"v-s:canRead":[{"type":"Boolean","data":true}],
	"v-s:canCreate":[{"type":"Boolean","data":true}]}*/
}
