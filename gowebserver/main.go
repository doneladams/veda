package main

import (
	"fmt"
	"log"

	"github.com/valyala/fasthttp"
)

func getIndividual(ticket string, uri string, reopen bool, ctx *fasthttp.RequestCtx) {
	log.Println("@GET INDIVIDUAL")
	if len(uri) == 0 || ticket == "" {
		return
	}

}

func requestHandler(ctx *fasthttp.RequestCtx) {
	log.Println("@METHOD ", string(ctx.Method()[:]))
	log.Println("@PATH ", string(ctx.Path()[:]))
	switch string(ctx.Path()[:]) {
	case "/get_individual":
		log.Println("@QUERY ", string(ctx.QueryArgs().QueryString()[:]))
		ticket := string(ctx.QueryArgs().Peek("ticket")[:])
		if ticket == "" {
			ticket = string(ctx.Request.Header.Cookie("ticket")[:])
		}
		log.Println("@TICKET ", ticket)
		reopen := ctx.QueryArgs().GetBool("reopen")
		log.Println("@REOPEN ", reopen)
		uri := string(ctx.QueryArgs().Peek("uri")[:])
		log.Println("@URI ", uri)
		getIndividual(ticket, uri, reopen, ctx)
	case "/get_individuals":
		log.Println("@QUERY ", string(ctx.QueryArgs().QueryString()[:]))
		fmt.Println("get_individuals")
	case "/authenticate":
		fmt.Println("authenticate")
	case "/tests":
		ctx.SendFile("public/tests.html")
	default:
		fasthttp.FSHandler("public/", 0)(ctx)
	}
}

func main() {
	if err := fasthttp.ListenAndServe("0.0.0.0:8101", requestHandler); err != nil {
		log.Fatal("@ERR ON STARTUP WEBSERVER ", err)
	}
}
