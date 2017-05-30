package main

import (
	"bytes"
	"log"
	"os"
	"strconv"
	"time"

	"github.com/muller95/lmdb-go/lmdb"
	msgpack "gopkg.in/vmihailenco/msgpack.v2"
)

func lmdbFindTicket(key string, ticket *ticket) ResultCode {
	var ticketMsgpack []byte

	lmdbEnv, err := lmdb.NewEnv()
	if err != nil {
		log.Println("@ERR CREATING LMDB ENV")
		return InternalServerError
	}

	err = lmdbEnv.SetMaxDBs(1)
	if err != nil {
		log.Println("@ERR SETTING MAX DBS ", err)
		return InternalServerError
	}
	lmdbEnv.Open(lmdbTicketsDBPath, 0, os.ModePerm)

	err = lmdbEnv.View(func(txn *lmdb.Txn) (err error) {
		dbi, err := txn.OpenDBI("", 0)
		if err != nil {
			return err
		}

		ticketMsgpack, err = txn.Get(dbi, []byte(key[:]))
		if err != nil {
			return err
		}
		return nil
	})
	if lmdb.IsNotFound(err) {
		return NotFound
	}
	if err != nil {
		log.Println("@ERR ON VIEW ", err)
		return InternalServerError
	}

	decoder := msgpack.NewDecoder(bytes.NewReader(ticketMsgpack))
	decoder.DecodeArrayLen()
	ticket.Id, _ = decoder.DecodeString()
	resMapI, _ := decoder.DecodeMap()
	resMap := resMapI.(map[interface{}]interface{})
	for mapKeyI, mapValI := range resMap {
		mapKey := mapKeyI.(string)

		switch mapKey {
		case "ticket:accessor":
			ticket.UserURI = mapValI.([]interface{})[0].([]interface{})[1].(string)

		case "ticket:when":
			startTime, _ := time.Parse("2006-01-02T15:04:05.0000000", mapValI.([]interface{})[0].([]interface{})[1].(string))
			ticket.StartTime = startTime.Unix()

		case "ticket:duration":
			duration, _ := strconv.ParseInt(mapValI.([]interface{})[0].([]interface{})[1].(string), 10, 64)
			ticket.EndTime = ticket.StartTime + duration
		}
	}

	return Ok
}

func getTicket(ticketKey string) (ResultCode, ticket) {
	var ticket ticket

	if ticketKey == "" || ticketKey == "systicket" {
		ticketKey = "guest"
	}

	rc := InternalServerError
	if ticketCache[ticketKey].Id != "" {
		ticket = ticketCache[ticketKey]
		rc = Ok
	} else {
		rc = lmdbFindTicket(ticketKey, &ticket)
		if rc == Ok {
			ticketCache[ticketKey] = ticket
		}
	}

	if rc != Ok {
		return rc, ticket
	}

	if time.Now().Unix() > ticket.EndTime {
		delete(ticketCache, ticketKey)
		log.Printf("@TICKET %v FROM USER %v expired\n", ticket.Id, ticket.UserURI)
		return TicketExpired, ticket
	}

	return Ok, ticket
}
