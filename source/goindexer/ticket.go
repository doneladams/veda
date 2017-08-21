package main

import (
	"bytes"
	"log"
	"strconv"
	"time"

	msgpack "gopkg.in/vmihailenco/msgpack.v2"
)

type ticket struct {
	Id        string
	UserURI   string
	result    ResultCode
	StartTime int64
	EndTime   int64
}

func getTicket(ticketKey string) (ResultCode, ticket) {
	var ticket ticket

	rr := conn.GetTicket([]string{ticketKey}, false)
	if rr.CommonRC != Ok {
		log.Println("@ERR ON GET TICKET FROM TARANTOOL")
		return InternalServerError, ticket
	}

	if rr.OpRC[0] != Ok {
		return rr.OpRC[0], ticket
	}

	decoder := msgpack.NewDecoder(bytes.NewReader([]byte(rr.Data[0])))
	decoder.DecodeArrayLen()

	var duration int64

	ticket.Id, _ = decoder.DecodeString()
	resMapI, _ := decoder.DecodeMap()
	resMap := resMapI.(map[interface{}]interface{})
	for mapKeyI, mapValI := range resMap {
		mapKey := mapKeyI.(string)

		switch mapKey {
		case "ticket:accessor":
			ticket.UserURI = mapValI.([]interface{})[0].([]interface{})[1].(string)

		case "ticket:when":
			tt := mapValI.([]interface{})[0].([]interface{})[1].(string)
			mask := "2006-01-02T15:04:05.00000000"
			startTime, _ := time.Parse(mask[0:len(tt)], tt)
			ticket.StartTime = startTime.Unix()

		case "ticket:duration":
			duration, _ = strconv.ParseInt(mapValI.([]interface{})[0].([]interface{})[1].(string), 10, 64)
		}
	}
	ticket.EndTime = ticket.StartTime + duration

	return Ok, ticket
}
