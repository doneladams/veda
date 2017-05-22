package main

import (
	"log"
	"reflect"
	"strings"
	"time"

	"strconv"

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
)

type Lang uint8

const (
	LangNone Lang = 0
	LangRu   Lang = 1
	LangEn   Lang = 2
)

func dataTypeToString(dataType DataType) string {
	switch dataType {
	case Uri:
		return "Uri"
	case String:
		return "String"
	case Integer:
		return "Integer"
	case Datetime:
		return "Datetime"
	case Decimal:
		return "Decimal"
	case Boolean:
		return "Boolean"
	}

	log.Println("@ERR UNKNOWN DATA TYPE")
	return ""
}

func langToString(lang Lang) string {
	switch lang {
	case LangRu:
		return "RU"
	case LangEn:
		return "EN"
	default:
		return "NONE"
	}
}

func decimalToString(mantissa, exponent int64) string {
	negative := false
	res := make([]rune, 0)
	if mantissa < 0 {
		negative = true
		mantissa = -mantissa
	}

	res = []rune(strconv.FormatInt(mantissa, 10))
	if exponent >= 0 {
		zeros := make([]rune, exponent)
		for i := 0; i < int(exponent); i++ {
			zeros[i] = '0'
		}

		res = append(res, zeros...)
	} else {
		exponent = -exponent
		if len(res) > int(exponent) {
			tmp := make([]rune, 0, len(res)+1)
			tmp = append(tmp, res[:len(res)-int(exponent)]...)
			tmp = append(tmp, '.')
			tmp = append(tmp, res[len(res)-int(exponent):]...)
			res = tmp
		} else {
			zeros := make([]rune, exponent)
			zeros[0] = '.'
			for i := 1; i < int(exponent); i++ {
				zeros[i] = '0'
			}
			res = append(zeros, res...)
		}
	}

	if negative {
		return "-" + string(res)
	}

	return string(res)
}

func MsgpackToMap(msgpackStr string) map[string]interface{} {
	individual := make(map[string]interface{})
	decoder := msgpack.NewDecoder(strings.NewReader(msgpackStr))
	decoder.DecodeArrayLen()

	individual["@"], _ = decoder.DecodeString()
	resMapI, _ := decoder.DecodeMap()
	resMap := resMapI.(map[interface{}]interface{})

	for keyI, resArrI := range resMap {
		predicate := keyI.(string)
		resArr := resArrI.([]interface{})
		resources := make([]interface{}, 0, len(resArr))

		for i := 0; i < len(resArr); i++ {
			resI := resArr[i]
			resource := make(map[string]interface{})
			switch resI.(type) {
			case []interface{}:
				resArrI := resI.([]interface{})
				if len(resArrI) == 2 {
					resType := DataType(resArrI[0].(uint64))
					if resType == Datetime {
						switch resArrI[1].(type) {
						case int64:
							resource["data"] = time.Unix(resArrI[1].(int64), 0).Format("2006-01-02T15:04:05Z")
						case uint64:
							resource["data"] = time.Unix(int64(resArrI[1].(uint64)), 0).Format("2006-01-02T15:04:05Z")
						default:
							log.Printf("@ERR SIZE 2! NOT INT/UINT IN DATETIME: %s\n",
								reflect.TypeOf(resArrI[1]))
							return nil
						}
						resource["type"] = dataTypeToString(Datetime)
					} else if resType == String {
						// fmt.Println("TRY TO DECODE STR")
						switch resArrI[1].(type) {
						case string:
							resource["data"] = resArrI[1]
						case nil:
							resource["data"] = ""
						default:
							log.Printf("@ERR SIZE 2! NOT STRING: %s\n",
								reflect.TypeOf(resArrI[1]))
							return individual
						}
						resource["type"] = dataTypeToString(String)
						resource["lang"] = langToString(LangNone)
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
						resource["type"] = dataTypeToString(Decimal)
						resource["data"] = decimalToString(mantissa, exponent)
					} else if resType == String {
						switch resArrI[1].(type) {
						case string:
							resource["data"] = resArrI[1]
						case nil:
							resource["data"] = ""
						default:
							log.Printf("@ERR SIZE 3! NOT STRING: %s\n",
								reflect.TypeOf(resArrI[1]))
							return nil
						}

						resource["type"] = dataTypeToString(String)
						resource["lang"] = langToString(Lang(resArrI[2].(uint64)))
					}
				}

			case string:
				resource["type"] = dataTypeToString(Uri)
				resource["data"] = resI
			case int64:
				resource["type"] = dataTypeToString(Integer)
				resource["data"] = resI
			case uint64:
				resource["type"] = dataTypeToString(Integer)
				resource["data"] = resI
			case bool:
				resource["type"] = dataTypeToString(Boolean)
				resource["data"] = resI
			default:
				log.Printf("@ERR! UNSUPPORTED TYPE %s\n", reflect.TypeOf(resI))
				return nil
			}
			resources = append(resources, resource)
		}
		individual[predicate] = resources
	}

	return individual
}
