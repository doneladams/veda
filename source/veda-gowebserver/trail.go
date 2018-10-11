package main

import (
	"encoding/json"
	"log"
	"strconv"
	"time"
)

//	"github.com/google/uuid"
//	"github.com/muller95/traildb-go"

//trail stores data about request in traildb
func trail(ticketId, userId, action string, args map[string]interface{}, result string, resultCode ResultCode, startTime int64) {
	if !isTrail {
		return
	}

	timestamp := time.Now().Unix()
	jsonArgs, _ := json.Marshal(args)
	log.Printf("TRAIL:time=%s;ticket=%s;user=%s;action=%s;\nargs=%s;\nres=%s;\ncode=%s\n\n", strconv.FormatInt(timestamp-startTime, 10), ticketId, userId, action, string(jsonArgs), result,
		string(codeToJsonException(resultCode)))

	/*
		if cons == nil {
			var err error
			cons, err = tdb.NewTrailDBConstructor(tdbPath+"rest_trails_"+time.Now().Format("2006-01-02T15:04:05Z")+"_"+webserverPort,
				"ticket", "user_id", "action", "args", "result", "result_code", "duration")
			if err != nil {
				log.Println("ERR! OPENING TRAILS: ", err)
				return
			}
		}

		u, err := uuid.NewRandom()
		if err != nil {
			log.Println("ERR! ON CREATING TRAIL UUID: ", err)
			return
		}

		jsonArgs, _ := json.Marshal(args)

		cons.Add(u.String(), timestamp, []string{ticketId, userId, action, string(jsonArgs), result,
			string(codeToJsonException(resultCode)), strconv.FormatInt(timestamp-startTime, 10)})
		countTrails++

		if countTrails > 1000 {
			log.Println("flush trail db")
			err = cons.Finalize()
			if err != nil {
				log.Println("ERR! FINALIZING TRAILS: ", err)
			}
			cons = nil
			countTrails = 0
		}
	*/
}
