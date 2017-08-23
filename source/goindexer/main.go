package main

import (
	"crypto/md5"
	"database/sql"
	"fmt"
	"log"
	"strings"
	"time"

	_ "github.com/go-sql-driver/mysql"
)

var configCommon = `
indexer
{
	mem_limit		= 1024M
}

searchd
{
	listen			= 9312
	listen			= 9306:mysql41

	log			= logs/searchd.log

	query_log		= logs/searchd_query.log
	read_timeout		= 5

	client_timeout		= 300

	max_children		= 30

	persistent_connections_limit	= 30

	pid_file		= data/searchd.pid

	seamless_rotate		= 1

	preopen_indexes		= 1

	unlink_old		= 1

	mva_updates_pool	= 1M

	max_packet_size		= 8M

	max_filters		= 256

	max_filter_values	= 4096

	max_batch_queries	= 32

	workers			= threads

	binlog_path = data/
}
`

var conn Connector

type Names map[string]bool

var systicket ticket

func main() {
	var rc ResultCode
	conn.Connect("127.0.0.1:9999")

	rc, systicket = getTicket("systicket")
	if rc != Ok {
		log.Fatal("@ERR GETTING SYSTICKET ", rc)
	}

	onto := NewOnto()
	onto.Load()

	createSphinxConfig(&onto)

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
				hashStr := md5.Sum([]byte(strings.Replace(strings.Replace(rdfType, ":", "_", -1), "-", "_", -1)))
				//  	INSERT INTO e66c69899d879f63e8ae29efa74f10df (id, uri, uri_attr) VALUES (2, 'avc', 'avc');

				query := fmt.Sprintf("SELECT MAX(id) FROM i%x;", hashStr)
				rows, err := dbConn.Query(query)
				if err != nil && err != sql.ErrNoRows {
					log.Printf("@ERR ON SELECTING MAX ID FOR i%x(%s): %v\n", hashStr, rdfType, err)
					log.Fatal("\t ", query)
					continue
				}

				maxId := 0
				if rows.Next() {
					err = rows.Scan(&maxId)
					if err != nil {
						log.Fatalln("@ERR READING MAX ID: ", err)
						continue
					}
					maxId++
				}

				query = fmt.Sprintf("INSERT INTO i%x (id, uri, uri_attr) VALUES (%d, '%v', '%v')", hashStr, maxId, individual.Uri,
					individual.Uri)
				_, err = dbConn.Exec(query)
				if err != nil {
					log.Println("@ERR ON EXECUTING QUERY: ", err)
					log.Fatal("\t ", query)
				}

				log.Println(query)
			} else {
				log.Println("@UNKNOWN RDF:TYPE ", rdfType)
			}
		}

		main_cs.sync()
	}
}
