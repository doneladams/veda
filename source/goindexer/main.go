package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"log"
	"net"
	"strconv"
	"time"

	msgpack "gopkg.in/vmihailenco/msgpack.v2"
)

var conn Connector

func getTicket(ticketKey string) (ResultCode, ticket) {
	var ticket ticket

	rr := conn.GetTicket([]string{ticketKey}, true)
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

func query(request string) (ResultCode, []byte) {

	socket, err := net.Dial("tcp", "127.0.0.1:11112")
	if err != nil {
		log.Println("@ERR QUERY: ERR ON DIAL ", err)
		return InternalServerError, []byte(""[:])
	}

	requestSize := uint32(len(request))
	buf := make([]byte, 4)
	buf[0] = byte((requestSize >> 24) & 0xFF)
	buf[1] = byte((requestSize >> 16) & 0xFF)
	buf[2] = byte((requestSize >> 8) & 0xFF)
	buf[3] = byte(requestSize & 0xFF)

	n, err := socket.Write(buf)
	if n < 4 || err != nil {
		log.Println("@ERR QUERY: ERR SENDING REQUEST SIZE ", err)
		return InternalServerError, []byte(""[:])
	}

	n, err = socket.Write([]byte(request))
	if uint32(n) < requestSize || err != nil {
		log.Println("@ERR QUERY: ERR SENDING REQUEST ", err)
		return InternalServerError, []byte(""[:])
	}

	n, err = socket.Read(buf)
	if n < 4 || err != nil {
		log.Println("@ERR QUERY: ERR READING RESPONSE SIZE ", err)
		return InternalServerError, []byte(""[:])

	}
	responseSize := uint32(0)
	for i := 0; i < 4; i++ {
		responseSize = (responseSize << 8) + uint32(buf[i])
	}

	response := make([]byte, responseSize)
	n, err = socket.Read(response)
	if uint32(n) < responseSize || err != nil {
		log.Println("@ERR QUERY: ERR READING RESPONSE ", err)
		return InternalServerError, []byte(""[:])
	}

	socket.Close()

	return Ok, response
}

func loadOntology() {
	rc, ticket := getTicket("systicket")

	if rc != Ok {
		return
	}

	request := fmt.Sprintf("%v�'rdf:type' === 'rdfs:Class' || 'rdf:type' === 'rdf:Property' || 'rdf:type' === 'owl:Class' || 'rdf:type' === 'owl:ObjectProperty' || 'rdf:type' === 'owl:DatatypeProperty'���false�0�10000�0", ticket.Id)
	rc, queryBytes := query(request)

	if rc != Ok {
		log.Println("@ERR ON QUERY ONTOLOGY ", rc)
	}

	var jsonData map[string]interface{}
	err := json.Unmarshal(queryBytes, &jsonData)
	if err != nil {
		log.Println("@ERR ON DECODING QUERY RESPONSE JSON: ", err)
		return
	}

	urisI := jsonData["result"].([]interface{})
	uris := make([]string, len(urisI))
	for i := 0; i < len(urisI); i++ {
		uris[i] = urisI[i].(string)
	}

	rr := conn.Get(false, "cfg:VedaSystem", uris, false)

	if rr.CommonRC != Ok {
		log.Println("@ERR COMMON ON GET ONTOLOGY ", rr.CommonRC)
		return
	}

	log.Printf("%v == %v", len(uris), len(rr.Data))
	for i := 0; i < len(rr.OpRC); i++ {
		if rr.OpRC[i] != Ok {
			log.Println(rr.OpRC[i])
		}
	}
	/*for i := 0; i < len(uris); i++ {
		log.Println(uris[i].(string))
		conn.Get(false, "cfg:VedaSystem", []string{uris[i].(string)}, false)
	}*/
}

func main() {
	conn.Connect("127.0.0.1:9999")
	loadOntology()
}
