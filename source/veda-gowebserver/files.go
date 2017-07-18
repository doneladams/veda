package main

import (
	"io"
	"log"
	"unicode/utf8"

	"strings"

	"os"

	"github.com/valyala/fasthttp"
)

func uploadFile(ctx *fasthttp.RequestCtx) {
	form, err := ctx.Request.MultipartForm()
	if err != nil {
		log.Println("@ERR REDING FORM: UPLOAD FILE: ", err)
		ctx.Response.SetStatusCode(int(InternalServerError))
		return
	}

	pathParts := strings.Split(form.Value["path"][0], "/")
	attachmentsPathCurr := attachmentsPath
	for i := 1; i < len(pathParts); i++ {
		attachmentsPathCurr += "/" + pathParts[i]
		os.Mkdir(attachmentsPathCurr, os.ModePerm)
	}

	destFile, err := os.OpenFile(attachmentsPathCurr+"/"+form.Value["uri"][0], os.O_WRONLY|os.O_CREATE, 0666)
	if err != nil {
		log.Println("@ERR CREATING DESTIONTION FILE ON UPLOAD: ", err)
		ctx.Response.SetStatusCode(int(InternalServerError))
		return
	}

	defer destFile.Close()
	srcFile, err := form.File["file"][0].Open()
	if err != nil {
		log.Println("@ERR OPENING FORM FILE ON UPLOAD: ", err)
		ctx.Response.SetStatusCode(int(InternalServerError))
		return
	}
	defer srcFile.Close()
	_, err = io.Copy(destFile, srcFile)
	if err != nil {
		log.Println("@ERR ON COPYING FILE ON UPLOAD: ", err)
		ctx.Response.SetStatusCode(int(InternalServerError))
		return
	}

	ctx.Response.SetStatusCode(int(Ok))
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
		log.Println("@DOWNLOAD")
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
		log.Println(fileInfo)
		filePath := fileInfo["v-s:filePath"].([]interface{})[0].(map[string]interface{})
		fileURI := fileInfo["v-s:fileUri"].([]interface{})[0].(map[string]interface{})
		fileName := fileInfo["v-s:fileName"].([]interface{})[0].(map[string]interface{})

		filePathStr := attachmentsPath + filePath["data"].(string) + "/" + fileURI["data"].(string)

		_, err := os.Stat(filePathStr)
		if os.IsNotExist(err) {
			ctx.Response.SetStatusCode(int(NotFound))
			return
		} else if err != nil {
			log.Println("@ERR ON CHECK FILE EXISTANCE: ", err)
			ctx.Response.SetStatusCode(int(InternalServerError))
			return
		}
		ctx.Response.Header.Set("Content-Disposition", "attachment; filename="+fileName["data"].(string))
		ctx.SendFile(filePathStr)
	}
}
