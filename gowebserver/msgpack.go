package main

import (
	"strings"

	"gopkg.in/vmihailenco/msgpack.v2"
)

func MsgpackToJson(msgpackStr string) map[string]interface{} {
	individual := make(map[string]interface{})
	decoder := msgpack.NewDecoder(strings.NewReader(msgpackStr))
	decoder.DecodeArrayLen()

	individual["@"], _ = decoder.DecodeString()
	resMapI, _ := decoder.DecodeMap()
	resMap := resMapI.(map[interface{}]interface{})

	for keyI, resArrI := range resMap {
		/*var resource Resource

		predicate := keyI.(string)
		resArr := resArrI.([]interface{})
		individual.resources[predicate] = make(Resources, len(resArr))

		for i := 0; i < len(resArr); i++ {
			resI := resArr[0]
			switch resI.(type) {
			case []interface{}:
				resArrI := resI.([]interface{})
				if len(resArrI) == 2 {
					resType := DataType(resArrI[0].(uint64))

					if resType == Datetime {
						switch resArrI[1].(type) {
						case int:
							resource.data = resArrI[1]
						case uint:
							resource.data = resArrI[1]
						default:
							return fmt.Errorf("@ERR SIZE 2! NOT INT/UINT IN DATETIME: %s",
								reflect.TypeOf(resArrI[1]))
						}
						resource._type = Datetime
					} else if resType == String {
						// fmt.Println("TRY TO DECODE STR")
						switch resArrI[1].(type) {
						case string:
							resource.data = resArrI[1]
						case nil:
							resource.data = ""
						default:
							return fmt.Errorf("@ERR SIZE 2! NOT STRING: %s",
								reflect.TypeOf(resArrI[1]))
						}
						resource._type = String
						resource.lang = LANG_NONE
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
							return fmt.Errorf("@ERR SIZE 3! NOT INT/UINT IN MANTISSA: %s",
								reflect.TypeOf(resArrI[1]))
						}

						switch resArrI[2].(type) {
						case int64:
							exponent = resArrI[2].(int64)
						case uint64:
							exponent = int64(resArrI[2].(uint64))
						default:
							return fmt.Errorf("@ERR SIZE 3! NOT INT/UINT IN MANTISSA: %s",
								reflect.TypeOf(resArrI[1]))
						}

						resource._type = Decimal
						resource.data = NewCustomDecimal(mantissa, exponent)
					} else if resType == String {
						switch resArrI[1].(type) {
						case string:
							resource.data = resArrI[1]
						case nil:
							resource.data = ""
						default:
							return fmt.Errorf("@ERR SIZE 3! NOT STRING: %s",
								reflect.TypeOf(resArrI[1]))
						}

						resource._type = String
						resource.lang = LANG(resArrI[2].(uint64))
					}
				}

			case string:
				resource._type = Uri
				resource.data = resI
			case int64:
				resource.data = resI
				resource._type = Integer
			case uint64:
				resource.data = resI
				resource._type = Integer
			case bool:
				resource.data = resI
				resource._type = Boolean
			default:
				return fmt.Errorf("@ERR! UNSUPPORTED TYPE %s", reflect.TypeOf(resI))
			}

			individual.resources[predicate][i] = resource
		}*/
	}

	return individual
}
