package main

import (
	"log"
	"unicode/utf8"

	"github.com/valyala/fasthttp"
)

func uploadFile(ctx *fasthttp.RequestCtx) {
	log.Println("@UPLOAD")
	// log.Println("@CONTENT", string(ctx.Request.Body()))
	form, err := ctx.Request.MultipartForm()
	if err != nil {
		log.Println("@ERR REDING FORM: UPLOAD FILE: ", err)
		ctx.Response.SetStatusCode(int(InternalServerError))
		return
	}

	path := form.Value["path"][0]
	uri := form.Value["uri"][0]
	log.Printf("path %s uri %s\n", path, uri)

	// formFile, err := ctx.FormFile()
	log.Println("@FORM FILES ", form.File["file"][0].Filename)
	/*if err != nil {
		log.Println("@ERR REDING FORM FILE: UPLOAD FILE: ", err)
		ctx.Response.SetStatusCode(int(InternalServerError))
		return
	}*/
	// log.Println("@FILE ", formFile.Filename)
}

func files(ctx *fasthttp.RequestCtx, routeParts []string) {
	ticketKey := string(ctx.Request.Header.Cookie("ticket"))

	uri := ""
	if len(routeParts) > 2 {
		uri = routeParts[2]
	} else {
		uploadFile(ctx)
		return
	}

	if utf8.RuneCountInString(uri) > 3 && ticketKey != "" {
		rc, ticket := getTicket(ticketKey)
		if rc != Ok {
			ctx.Response.SetStatusCode(int(rc))
			return
		}

		rr := conn.Get(true, ticket.UserURI, []string{uri}, false)
		if rr.CommonRC != Ok {
			log.Println("@ERR COMMON FILES: GET INDIVIDUAL")
			ctx.Response.SetStatusCode(int(rr.CommonRC))
			return
		} else if rr.OpRC[0] != Ok {
			ctx.Response.SetStatusCode(int(rr.OpRC[0]))
			return
		}

		fileInfo := MsgpackToMap(rr.Data[0])
		filePath := fileInfo["v-s:filePath"].([]interface{})[0].(map[string]interface{})
		fileURI := fileInfo["v-s:fileUri"].([]interface{})[0].(map[string]interface{})

		log.Printf("uri=%v path=%v", fileURI, filePath)
	}

}
