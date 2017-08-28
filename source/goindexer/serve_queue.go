package main

import (
	"crypto/md5"
	"database/sql"
	"encoding/json"
	"fmt"
	"log"
	"math"
	"os"
	"strconv"
	"strings"
	"time"

	"gopkg.in/vmihailenco/msgpack.v2"
)

func generateQuery(individual *Individual, id int64, hashStr [16]byte) string {
	// query = fmt.Sprintf("REPLACE INTO i%x (id, uri, uri_attr) VALUES (%d, '%s', '%s')", hashStr, id,
	// individual.Uri, individual.Uri)
	fieldNames := "(id, uri, uri_attr"
	fieldArgs := fmt.Sprintf("(%d, '%s', '%s'", id, individual.Uri, individual.Uri)

	attrs := classAttrs[individual.Resources["rdf:type"][0].StrData]
	for i := 0; i < len(attrs); i++ {
		resources, ok := individual.Resources[attrs[i].name]
		if !ok {
			continue
		}

		vals := make([]interface{}, len(resources))
		fieldVal := ""
		ru := make([]interface{}, len(resources))
		en := make([]interface{}, len(resources))
		none := make([]interface{}, len(resources))

		j := 0
		jEn, jRu, jNone := 0, 0, 0
		for _, resource := range resources {
			switch resource.ResType {
			case Uri:
				vals[j] = resource.StrData
				fieldVal += strings.Replace(resource.StrData, "'", "\\'", -1) + "|"
			case String:
				vals[j] = resource.StrData
				// vals[i] = map[string]interface{}{"data": resource.StrData, "lang": resource.Lang}
				fieldVal += strings.Replace(resource.StrData, "'", "\\'", -1) + "|"
			case Integer:
				vals[j] = resource.LongData
				fieldVal += strconv.FormatInt(resource.LongData, 10) + "|"
			case Datetime:
				vals[j] = resource.LongData
				switch resource.Lang {
				case LangRu:
					ru[jRu] = resource.StrData
					jRu++
				case LangEn:
					en[jEn] = resource.StrData
					jEn++
				default:
					none[jNone] = resource.StrData
					jNone++
				}
				fieldVal += strconv.FormatInt(resource.LongData, 10) + "|"
			case Decimal:
				decimal := math.Pow(float64(resource.DecimalMantissaData), float64(resource.DecimalExponentData))
				vals[j] = decimal
				fieldVal += strconv.FormatFloat(decimal, 'f', -1, 64)
			case Boolean:
				vals[j] = resource.BoolData
				fieldVal += strconv.FormatBool(resource.BoolData) + "|"
			}
			j++
		}

		// valsMap := make(map[string]interface{})
		// valsMap["data"] = vals
		data, _ := json.Marshal(vals[:j])

		jsonStr := strings.Replace(string(data), "'", "\\'", -1)
		switch resources[0].ResType {
		case Uri:
			if attrs[i].fieldName != "" {
				fieldNames += ", " + attrs[i].fieldName
				fieldArgs = fmt.Sprintf("%s, '%v'", fieldArgs, fieldVal)
			}

			if attrs[i].attrName != "" {
				fieldNames += ", " + attrs[i].attrName
				fieldArgs = fmt.Sprintf("%s, '%v'", fieldArgs, jsonStr)
			}
		case String:
			if attrs[i].fieldName != "" {
				fieldNames += ", " + attrs[i].fieldName
				fieldArgs = fmt.Sprintf("%s, '%v'", fieldArgs, fieldVal)
			}

			if attrs[i].attrName != "" {
				if jRu > 0 {
					fieldNames += ", " + attrs[i].attrName
					// fieldNames += ", " + attrs[i].attrName + langPrefix
					dataRu, _ := json.Marshal(ru[:jRu])
					jsonStrRu := strings.Replace(string(dataRu), "'", "\\'", -1)
					fieldArgs = fmt.Sprintf("%s, '%v'", fieldArgs+"_ru", jsonStrRu)
				}

				if jEn > 0 {
					fieldNames += ", " + attrs[i].attrName
					// fieldNames += ", " + attrs[i].attrName + langPrefix
					dataEn, _ := json.Marshal(ru[:jEn])
					jsonStrEn := strings.Replace(string(dataEn), "'", "\\'", -1)
					fieldArgs = fmt.Sprintf("%s, '%v'", fieldArgs+"_en", jsonStrEn)
				}

				if jNone > 0 {
					fieldNames += ", " + attrs[i].attrName
					// fieldNames += ", " + attrs[i].attrName + langPrefix
					dataNone, _ := json.Marshal(ru[:jNone])
					jsonStrNone := strings.Replace(string(dataNone), "'", "\\'", -1)
					fieldArgs = fmt.Sprintf("%s, '%v'", fieldArgs, jsonStrNone)
				}
			}

			/*if attrs[i].attrName != "" {
				fieldNames += ", " + attrs[i].attrName
				// fieldNames += ", " + attrs[i].attrName + langPrefix
				fieldArgs = fmt.Sprintf("%s, '%v'", fieldArgs, jsonStr)
			}*/
		case Integer:
			if attrs[i].fieldName != "" {
				fieldNames += ", " + attrs[i].fieldName
				fieldArgs = fmt.Sprintf("%s, '%v'", fieldArgs, fieldVal)
			}

			if attrs[i].attrName != "" {
				fieldNames += ", " + attrs[i].attrName
				fieldArgs = fmt.Sprintf("%s, '%v'", fieldArgs, jsonStr)
			}
		case Datetime:
			if attrs[i].fieldName != "" {
				fieldNames += ", " + attrs[i].fieldName
				fieldArgs = fmt.Sprintf("%s, '%v'", fieldArgs, fieldVal)
			}

			if attrs[i].attrName != "" {
				fieldNames += ", " + attrs[i].attrName
				fieldArgs = fmt.Sprintf("%s, '%v'", fieldArgs, jsonStr)
			}
		case Decimal:
			if attrs[i].fieldName != "" {
				fieldNames += ", " + attrs[i].fieldName
				fieldArgs = fmt.Sprintf("%s, '%v'", fieldArgs, fieldVal)
			}

			if attrs[i].attrName != "" {
				fieldNames += ", " + attrs[i].attrName
				fieldArgs = fmt.Sprintf("%s, '%v'", fieldArgs, jsonStr)
			}
		case Boolean:

			if attrs[i].fieldName != "" {
				fieldNames += ", " + attrs[i].fieldName
				fieldArgs = fmt.Sprintf("%s, '%v'", fieldArgs, fieldVal)
			}

			if attrs[i].attrName != "" {
				fieldNames += ", " + attrs[i].attrName
				fieldArgs = fmt.Sprintf("%s, '%v'", fieldArgs, jsonStr)
			}
		}

	}
	fieldNames += ")"
	fieldArgs += ")"

	return fmt.Sprintf("REPLACE INTO i%x %s VALUES %s", hashStr, fieldNames, fieldArgs)
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

	start := int64(0)
	for {
		time.Sleep(300 * time.Millisecond)

		start = time.Now().Unix()
		main_queue.reopen_reader()

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
			indexerInfo.Count++

			rdfType := individual.Resources["rdf:type"][0].StrData

			_, ok := onto.individuals[rdfType]
			if ok {
				hashStr := md5.Sum([]byte(strings.Replace(strings.Replace(rdfType, ":", "_", -1), "-", "_", -1)))
				id, ok := indexerInfo.Ids[individual.Uri]
				if !ok {
					id = indexerInfo.Count
					indexerInfo.Ids[individual.Uri] = id
				}

				query := generateQuery(individual, id, hashStr)
				_, err = dbConn.Exec(query)

				if err != nil {
					log.Printf("@ERR ON EXECUTING QUERY (%s): %v\n", rdfType, err)
					log.Fatal("\t ", query)
				}

				if indexerInfo.Count%10000 == 0 {
					f, err := os.Create("data/indexer-info.data")
					if err != nil {
						log.Println("@ERR CREATING INDEXER INFO FILE: ", err)
						continue
					}

					encoder := msgpack.NewEncoder(f)
					encoder.Encode(indexerInfo)
				}
			}
		}

		main_cs.sync()
		break
	}

	end := time.Now().Unix()
	log.Println(indexerInfo.Count)
	log.Printf("speed %f\n", float64(indexerInfo.Count)/float64(end-start))
	log.Printf("total %v\n", end-start)
}
