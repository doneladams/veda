package main

import (
	"log"

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

type ClassAttr struct {
	name      string
	fieldName string
	attrName  string
}

var classAttrs map[string][]ClassAttr

func main() {
	var rc ResultCode
	conn.Connect("127.0.0.1:9999")

	rc, systicket = getTicket("systicket")
	if rc != Ok {
		log.Fatal("@ERR GETTING SYSTICKET ", rc)
	}

	onto := NewOnto()
	onto.Load()

	classAttrs = make(map[string][]ClassAttr)
	createSphinxConfig(&onto)

	serveQueue(&onto)
}
