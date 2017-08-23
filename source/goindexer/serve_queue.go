package main

import (
	"crypto/md5"
	"database/sql"
	"fmt"
	"log"
	"strings"
	"time"
)

func generateQuery(individual *Individual) {
	// query = fmt.Sprintf("REPLACE INTO i%x (id, uri, uri_attr) VALUES (%d, '%s', '%s')", hashStr, id,
	// individual.Uri, individual.Uri)
	// fieldNames := "(id, uri, uri_attr"
	// fieldArgs := "(%d, '%s', '%s'"

	attrs := classAttrs[individual.Resources["rdf:type"][0].StrData]
	for i := 0; i < len(attrs); i++ {
		// resources, ok := individual.Resources[attrs[i].name]
		// if !ok {
		// continue
		// }
	}
}

func serveQueue(onto *Onto) {
	dbConn, err := sql.Open("mysql", "@tcp(127.0.0.1:9306)/db")
	if err != nil {
		log.Fatal("@ERR CONNECTING TO SPHINX: ", err)
	}

	main_queue_name := "individuals-flow"
	var main_queue *Queue
	var main_cs *Consumer

	main_queue = NewQueue(main_queue_name, R)
	main_queue.open(CURRENT)

	main_cs = NewConsumer(main_queue, "goindexer")
	main_cs.open()

	data := ""
	count := 0

	for {
		time.Sleep(300 * time.Millisecond)

		main_queue.reopen_reader()

		//log.Printf("@start prepare batch, count=%d", count)
		for true {
			data = main_cs.pop()
			if data == "" {
				break
			}

			tmp := MsgpackToIndividual(data)
			if tmp == nil {
				log.Println("@ERR GET_INDIVIDUAL: DECODING INDIVIDUAL")
				continue
			}

			individual := MsgpackToIndividual(tmp.Resources["new_state"][0].StrData)

			main_cs.commit_and_next(false)
			count++

			rdfType := individual.Resources["rdf:type"][0].StrData

			_, ok := onto.individuals[rdfType]
			if ok {
				id := 1
				hashStr := md5.Sum([]byte(strings.Replace(strings.Replace(rdfType, ":", "_", -1), "-", "_", -1)))
				//  	INSERT INTO e66c69899d879f63e8ae29efa74f10df (id, uri, uri_attr) VALUES (2, 'avc', 'avc');

				query := fmt.Sprintf("SELECT id FROM i%x WHERE MATCH('%s');", hashStr, individual.Uri)
				rows, err := dbConn.Query(query)

				if err != nil && err != sql.ErrNoRows {
					log.Printf("@ERR ON SELECTING EXISTING ID FOR i%x(%s): %v\n", hashStr, rdfType, err)
					log.Println("\t ", query)
					continue
				}

				if rows.Next() {
					err = rows.Scan(&id)
					if err != nil {
						log.Println("@ERR READING EXISTING ID: ", err)
						continue
					}

					rows.Close()
				} else {
					query = fmt.Sprintf("SELECT MAX(id) FROM i%x;", hashStr)
					rows, err = dbConn.Query(query)

					if err != nil && err != sql.ErrNoRows {
						log.Printf("@ERR ON SELECTING MAX ID FOR i%x(%s): %v\n", hashStr, rdfType, err)
						log.Println("\t ", query)
						continue
					}

					if rows.Next() {
						err = rows.Scan(&id)
						if err != nil {
							log.Fatalln("@ERR READING MAX ID: ", err)
							continue
						}
						id++
					}

					rows.Close()
				}

				generateQuery(individual)
				query = fmt.Sprintf("REPLACE INTO i%x (id, uri, uri_attr) VALUES (%d, '%s', '%s')", hashStr, id,
					individual.Uri, individual.Uri)
				_, err = dbConn.Exec(query, id, individual.Uri, individual.Uri)

				if err != nil {
					log.Println("@ERR ON EXECUTING QUERY: ", err)
					log.Println("\t ", query)
				}

				log.Println(query)
			} else {
				log.Println("@UNKNOWN RDF:TYPE ", rdfType)
			}
		}

		main_cs.sync()
	}
}
