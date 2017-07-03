package main

import (
	"log"
	"os"

	"cbor"

	"bytes"

	"github.com/bmatsuo/lmdb-go/lmdb"
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
			_, v, err := cursor.Get(nil, nil, lmdb.Next)
			if lmdb.IsNotFound(err) {
				return nil
			}

			if err != nil {
				return err
			}

			// log.Printf("%v -> %v\n", string(k), string(v))
			// ch.MapType = reflect.TypeOf(map[string]interface{}(nil))
			individual := make(map[string]interface{})
			// codec.NewDecoderBytes(v, new(codec.CborHandle)).MustDecode(&individual)
			decoder := cbor.NewDecoder(bytes.NewReader(v))
			err = decoder.Decode(&individual)
			if err != nil {
				return err
			}
			for k, v := range individual {
				log.Printf("%v->%v", k, v)
			}
			log.Println("-------------------Done---------------")

		}
	})

	if err != nil {
		log.Fatal("Err: iterating over base: ", err)
	}
}
