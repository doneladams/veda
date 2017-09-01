package main

import (
	"log"
	"reflect"
	"strconv"
	"strings"
	"time"

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

func stringToDecimal(str string) (int64, int64) {
	var exponent, mantissa int64

	runes := []rune(str)

	i := 0
	negative := false
	if runes[0] == '-' {
		i++
		negative = true
	}

	j := len(runes) - 1
	for ; j >= i; j-- {
		if runes[j] != '0' {
			break
		}

		exponent += 1
	}

	expStep := int64(0)
	for ; i <= j; i++ {
		if runes[i] == '.' {
			expStep = -1
			continue
		}

		number, _ := strconv.ParseInt(string(runes[i]), 10, 64)
		mantissa = mantissa*10 + number
		exponent += expStep
	}

	if negative {
		mantissa = -mantissa
	}

	return mantissa, exponent
}

func stringToDataType(str string) DataType {
	switch str {
	case "Uri":
		return Uri
	case "String":
		return String
	case "Integer":
		return Integer
	case "Datetime":
		return Datetime
	case "Decimal":
		return Decimal
	case "Boolean":
		return Boolean
	}

	log.Println("@ERR UNKNOWN DATA TYPE STRING")
	return Unknown
}

func stringToLang(str string) Lang {
	switch str {
	case "RU":
		return LangRu
	case "EN":
		return LangEn
	default:
		return LangNone
	}
}

func MapToIndividual(jsonMap map[string]interface{}) *Individual {
	var indiv Individual

	indiv.Uri = jsonMap["@"].(string)
	indiv.Resources = make(map[string][]Resource)
	for k, v := range jsonMap {
		if k == "@" {
			continue
		}

		resourcesJson := v.([]interface{})
		resources := make([]Resource, len(resourcesJson))
		for i := 0; i < len(resourcesJson); i++ {
			var resource Resource
			resourceJson := resourcesJson[i].(map[string]interface{})
			datatype := Unknown
			switch resourceJson["type"].(type) {
			case float64:
				datatype = DataType(resourceJson["type"].(float64))
			case string:
				datatype = stringToDataType(resourceJson["type"].(string))
			}

			resource.ResType = datatype
			switch datatype {
			case Uri:
				resource.StrData = resourceJson["data"].(string)
				resource.Lang = LangNone
			case Integer:
				resource.LongData = int64(resourceJson["data"].(float64))
			case Datetime:
				datetime, _ := time.Parse("2006-01-02T15:04:05.000Z", resourceJson["data"].(string))
				resource.LongData = datetime.Unix()
			case Decimal:
				mantissa, exponent := stringToDecimal(resourceJson["data"].(string))
				resource.DecimalMantissaData, resource.DecimalExponentData = mantissa, exponent
			case Boolean:
				resource.BoolData = resourceJson["data"].(bool)
			case String:
				lang := LangNone
				switch resourceJson["lang"].(type) {
				case float64:
					lang = Lang(resourceJson["lang"].(float64))
				case string:
					lang = stringToLang(resourceJson["lang"].(string))
				}

				resource.Lang = lang
				resource.StrData = resourceJson["data"].(string)
			}

			resources[i] = resource
		}

		indiv.Resources[k] = resources
	}

	return &indiv
}

func MsgpackToIndividual(msgpackStr string) *Individual {
	individual := Individual{Resources: make(map[string][]Resource)}
	decoder := msgpack.NewDecoder(strings.NewReader(msgpackStr))
	decoder.DecodeArrayLen()

	// log.Printf("@MSGPACK %v\n", msgpackStr)

	individual.Uri, _ = decoder.DecodeString()
	resMapI, err := decoder.DecodeMap()
	if err != nil {
		log.Println("@ERR DECODING MAP: ", err)
	}
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
