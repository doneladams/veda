package main

import (
	"log"
	"net"
	"os"

	"github.com/bmatsuo/lmdb-go/lmdb"
	tarantool "github.com/tarantool/go-tarantool"
)

const (
	Uri      = 1
	Str      = 2
	Integer  = 4
	Datetime = 8
	Decimal  = 32
	Boolean  = 64
)

const (
	LangNone = 0
	LangRu   = 1
	LangEn   = 2
)

type Resource struct {
	Type                uint32
	Lang                uint8
	StrData             string
	BoolData            bool
	LongData            int64
	DecimalMantissaData int64
	DecimalExponentData int64
}

type Individual struct {
	Uri       string
	Resources map[string][]Resource
}

func main() {
	path := os.Args[1]

	log.Println(path)
	if path == "" {
		log.Fatal("Err: need path to individuals folder")
	}

	lmdbEnv, err := lmdb.NewEnv()
	if err != nil {
		log.Fatal("@ERR CREATING LMDB ENV")
	}

	err = lmdbEnv.SetMaxDBs(1)
	if err != nil {
		log.Fatal("@ERR SETTING MAX DBS ", err)
	}

	err = lmdbEnv.Open(path, 0, os.ModePerm)
	if err != nil {
		log.Fatal("Err: can not open lmdb base: ", err)
	}

	err = lmdbEnv.View(func(txn *lmdb.Txn) (err error) {
		dbi, err := txn.OpenDBI("", 0)

		cursor, err := txn.OpenCursor(dbi)
		if err != nil {
			return err
		}
		for {
			k, v, err := cursor.Get(nil, nil, lmdb.Next)
			if lmdb.IsNotFound(err) {
				return nil
			}

			if err != nil {
				return err
			}

			if string(k) == "summ_hash_this_db" {
				continue
			}

			log.Printf("%v -> %v\n", string(k), string(v))
			if string(k) == "systicket" {
				individual := make([]interface{}, 2)
				individual[0] = "systicket"

				resources := make(map[string]interface{})

				rdfType := make([]interface{}, 2)
				rdfType[0] = 2
				rdfType[1] = "ticket:Ticket"
				resources["rdf:type"] = rdfType

				ticketID := make([]interface{}, 2)
				ticketID[0] = 2
				ticketID[1] = string(v)
				resources["ticket:id"] = ticketID

				individual[1] = resources

				opts := tarantool.Opts{User: "guest"}
				conn, err := tarantool.Connect("127.0.0.1:3309", opts)
				// conn, err := tarantool.Connect("/path/to/tarantool.socket", opts)
				if err != nil {
					return err
				}

				_, err = conn.Replace(conn.Schema.Spaces["tickets"].Id, individual)
				if err != nil {
					return err
				}

				continue
			}

			socket, err := net.Dial("tcp", "127.0.0.1:11113")
			if err != nil {
				log.Println("Err on dial to listener: ", err)
			}

			requestSize := len(v)
			buf := make([]byte, 4)
			buf[0] = byte((requestSize >> 24) & 0xFF)
			buf[1] = byte((requestSize >> 16) & 0xFF)
			buf[2] = byte((requestSize >> 8) & 0xFF)
			buf[3] = byte(requestSize & 0xFF)

			n, err := socket.Write(buf)
			if n < 4 || err != nil {
				return err
			}

			n, err = socket.Write([]byte(v))
			if int(n) < requestSize || err != nil {
				return err
			}

			socket.Close()
		}
	})

	if err != nil {
		log.Fatal("Err: iterating over base: ", err)
	}
}
