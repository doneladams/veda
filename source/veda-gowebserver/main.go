package main

import (
	"log"
	"time"

	"encoding/json"

	"strings"

	"github.com/op/go-nanomsg"
	"github.com/valyala/fasthttp"
)

type ResultCode uint32

const (
	Ok                  ResultCode = 200
	BadRequest          ResultCode = 400
	NotAuthorized       ResultCode = 472
	NotFound            ResultCode = 404
	InternalServerError ResultCode = 500
	TicketExpired       ResultCode = 471
	NoContent           ResultCode = 204
	SizeTooLarge        ResultCode = 1118
)

type ticket struct {
	Id        string
	UserURI   string
	result    ResultCode
	StartTime int64
	EndTime   int64
}

const (
	lmdbTicketsDBPath = "./data/lmdb-tickets"
)

var ticketCache map[string]ticket
var ontologyCache map[string]map[string]interface{}
var mifCache map[int]*ModuleInfoFile
var conn Connector
var socket *nanomsg.Socket
var endpoint *nanomsg.Endpoint
var vedaServerURL = "tcp://127.0.0.1:9112"
var attachmentsPath = "./data/files/"

func codeToJsonException(code ResultCode) []byte {
	exception := make(map[string]interface{})

	switch code {
	case Ok:
		exception["statusMessage"] = "Ok"
	case BadRequest:
		exception["statusMessage"] = "BadRequest"
	case NotAuthorized:
		exception["statusMessage"] = "NotAuthorized"
	case NotFound:
		exception["statusMessage"] = "NotFound"
	case InternalServerError:
		exception["statusMessage"] = "InternalServerError"
	case TicketExpired:
		exception["statusMessage"] = "TicketExpired"
	case NoContent:
		exception["statusMessage"] = "NoContent"
	case SizeTooLarge:
		exception["statusMessage"] = "SizeToLarge"
	default:
		exception["statusMessage"] = "UnknownError"
	}

	exceptionJSON, _ := json.Marshal(exception)
	return exceptionJSON
}

func requestHandler(ctx *fasthttp.RequestCtx) {
	routeParts := strings.Split(string(ctx.Path()[:]), "/")
	if len(routeParts) >= 2 && routeParts[1] == "files" {
		log.Printf("len=%v arr=%v\n", len(routeParts), routeParts)
		files(ctx, routeParts)
		return
	}

	switch string(ctx.Path()[:]) {
	case "/get_individual":
		getIndividual(ctx)
	case "/get_individuals":
		getIndividuals(ctx)

	case "/put_individual":
		putIndividual(ctx)
	case "/put_individuals":
		putIndividuals(ctx)

	case "/remove_individual":
		removeIndividual(ctx)
	case "/remove_from_individual":
		removeFromIndividual(ctx)

	case "/set_in_individual":
		setInIndividual(ctx)

	case "/add_to_individual":
		addToIndividual(ctx)

	case "/authenticate":
		authenticate(ctx)

	case "/get_rights":
		getRights(ctx)
	case "/get_rights_origin":
		getAclData(ctx, GetRightsOrigin)
	case "/get_membership":
		getAclData(ctx, GetMembership)

	case "/get_ticket_trusted":
		getTicketTrusted(ctx)
	case "/is_ticket_valid":
		isTicketValid(ctx)

	case "/query":
		query(ctx)

	case "/send_to_module":
		sendToModule(ctx)

	case "/get_operation_state":
		getOperationState(ctx)
	case "/flush":
		break

	case "/tests":
		ctx.SendFile("public/tests.html")
	default:
		fasthttp.FSHandler("public/", 0)(ctx)
	}
}

func main() {
	var err error
	socket, err = nanomsg.NewSocket(nanomsg.AF_SP, nanomsg.REQ)
	if err != nil {
		log.Fatal("@ERR ON CREATING SOCKET")
	}

	endpoint, err = socket.Connect(vedaServerURL)
	for err != nil {
		endpoint, err = socket.Connect(vedaServerURL)
		time.Sleep(3000 * time.Millisecond)
	}
	conn.Connect("127.0.0.1:9999")

	ticketCache = make(map[string]ticket)
	ontologyCache = make(map[string]map[string]interface{})
	mifCache = make(map[int]*ModuleInfoFile)

	err = fasthttp.ListenAndServe("0.0.0.0:8080", requestHandler)
	if err != nil {
		log.Fatal("@ERR ON STARTUP WEBSERVER ", err)
	}
}
