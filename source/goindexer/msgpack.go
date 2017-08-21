package main

import (
	"log"
	"reflect"
	"strings"

	"gopkg.in/vmihailenco/msgpack.v2"
)

type DataType uint8

const (
	Uri      DataType = 1
	String   DataType = 2
	Integer  DataType = 4
	Datetime DataType = 8
	Decimal  DataType = 32
	Boolean  DataType = 64
	Unknown  DataType = 0
)

type Lang uint8

const (
	LangNone Lang = 0
	LangRu   Lang = 1
	LangEn   Lang = 2
)

type Resource struct {
	ResType             DataType
	Lang                Lang
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

func MsgpackToIndividual(msgpackStr string) *Individual {
	individual := Individual{Resources: make(map[string][]Resource)}
	decoder := msgpack.NewDecoder(strings.NewReader(msgpackStr))
	decoder.DecodeArrayLen()

	// log.Printf("@MSGPACK %v\n", msgpackStr)

	individual.Uri, _ = decoder.DecodeString()
	resMapI, _ := decoder.DecodeMap()
	resMap := resMapI.(map[interface{}]interface{})
	// log.Println("@URI ", individual["@"])
	for keyI, resArrI := range resMap {
		// log.Printf("\t@PREDICATE %v\n", keyI)
		predicate := keyI.(string)
		// log.Println("\t", predicate, resArrI)
		resArr := resArrI.([]interface{})
		resources := make([]Resource, 0, len(resArr))

		for i := 0; i < len(resArr); i++ {
			resI := resArr[i]
			var resource Resource
			// log.Printf("\t\t@RES %v : %v\n", resI, reflect.TypeOf(resI))
			switch resI.(type) {
			case []interface{}:
				resArrI := resI.([]interface{})
				if len(resArrI) == 2 {
					resType := DataType(resArrI[0].(uint64))
					if resType == Datetime {
						switch resArrI[1].(type) {
						case int64:
							resource.LongData = resArrI[1].(int64)
						case uint64:
							resource.LongData = int64(resArrI[1].(uint64))
						default:
							log.Printf("@ERR SIZE 2! NOT INT/UINT IN DATETIME: %s\n",
								reflect.TypeOf(resArrI[1]))
							return nil
						}
						resource.ResType = Datetime
					} else if resType == String {
						// fmt.Println("TRY TO DECODE STR")
						switch resArrI[1].(type) {
						case string:
							resource.StrData = resArrI[1].(string)
						case nil:
							resource.StrData = ""
						default:
							log.Printf("@ERR SIZE 2! NOT STRING: %s\n",
								reflect.TypeOf(resArrI[1]))
							return nil
						}
						resource.ResType = String
						resource.Lang = LangNone
					}
				} else if len(resArrI) == 3 {
					resType := DataType(resArrI[0].(uint64))

					if resType == Decimal {
						var mantissa, exponent int64

						switch resArrI[1].(type) {
						case int64:
							mantissa = resArrI[1].(int64)
						case uint64:
							mantissa = int64(resArrI[1].(uint64))
						default:
							log.Println("@ERR SIZE 3! NOT INT/UINT IN MANTISSA: %s\n",
								reflect.TypeOf(resArrI[1]))
							return nil
						}

						switch resArrI[2].(type) {
						case int64:
							exponent = resArrI[2].(int64)
						case uint64:
							exponent = int64(resArrI[2].(uint64))
						default:
							log.Println("@ERR SIZE 3! NOT INT/UINT IN MANTISSA: %s",
								reflect.TypeOf(resArrI[1]))
							return nil
						}
						resource.ResType = Decimal
						resource.DecimalExponentData = exponent
						resource.DecimalMantissaData = mantissa
					} else if resType == String {
						switch resArrI[1].(type) {
						case string:
							resource.StrData = resArrI[1].(string)
						case nil:
							resource.StrData = ""
						default:
							log.Printf("@ERR SIZE 3! NOT STRING: %s\n",
								reflect.TypeOf(resArrI[1]))
							return nil
						}

						resource.ResType = String
						resource.Lang = Lang(resArrI[2].(uint64))
					}
				}

			case string:
				resource.ResType = Uri
				resource.StrData = resI.(string)
			case int64:
				resource.ResType = Integer
				resource.LongData = resI.(int64)
			case uint64:
				resource.ResType = Integer
				resource.LongData = int64(resI.(uint64))
			case bool:
				resource.ResType = Boolean
				resource.BoolData = resI.(bool)
			default:
				log.Printf("@ERR! UNSUPPORTED TYPE %s\n", reflect.TypeOf(resI))
				return nil
			}
			resources = append(resources, resource)
		}
		individual.Resources[predicate] = resources
	}

	return &individual
}
