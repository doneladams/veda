package main

import (
	"bufio"
	"encoding/binary"
	"errors"
	"fmt"
	"reflect"
	"strings"
	"unsafe"

	"gopkg.in/vmihailenco/msgpack.v2"
)

// #define MP_SOURCE 1
// #include "msgpuck.h"
// import "C"

type CustomDecimal struct {
	Mantissa int64
	Exponent int64
}

func NewCustomDecimal(mantissa int64, exponent int64) CustomDecimal {
	var res CustomDecimal

	res.Mantissa = mantissa
	res.Exponent = exponent

	return res
}

func ulong_to_buff(_buff []uint8, pos int, data uint64) {
	_buff[pos+0] = uint8((data & 0x00000000000000FF))
	_buff[pos+1] = uint8((data & 0x000000000000FF00) >> 8)
	_buff[pos+2] = uint8((data & 0x0000000000FF0000) >> 16)
	_buff[pos+3] = uint8((data & 0x00000000FF000000) >> 24)
	_buff[pos+4] = uint8((data & 0x000000FF00000000) >> 32)
	_buff[pos+5] = uint8((data & 0x0000FF0000000000) >> 40)
	_buff[pos+6] = uint8((data & 0x00FF000000000000) >> 48)
	_buff[pos+7] = uint8((data & 0xFF00000000000000) >> 56)
}

func uint_to_buff(_buff []uint8, pos int, data uint32) {
	_buff[pos+0] = uint8((data & 0x000000FF))
	_buff[pos+1] = uint8((data & 0x0000FF00) >> 8)
	_buff[pos+2] = uint8((data & 0x00FF0000) >> 16)
	_buff[pos+3] = uint8((data & 0xFF000000) >> 24)
}

func uint_from_buff(buff []uint8, pos int) uint32 {
	num := binary.LittleEndian.Uint32(buff[pos : pos+8])
	return uint32(num)
}

func ulong_from_buff(buff []uint8, pos int) uint64 {
	num := binary.LittleEndian.Uint64(buff[pos : pos+8])
	return num
}

// Readln returns a single line (without the ending \n)
// from the input buffered reader.
// An error is returned iff there is an error with the
// buffered reader.
func Readln(r *bufio.Reader) (string, error) {
	var (
		isPrefix bool  = true
		err      error = nil
		line, ln []byte
	)
	for isPrefix && err == nil {
		line, isPrefix, err = r.ReadLine()
		ln = append(ln, line...)
	}
	return string(ln), err
}

func CopyString(s string) string {
	var b []byte
	h := (*reflect.SliceHeader)(unsafe.Pointer(&b))
	h.Data = (*reflect.StringHeader)(unsafe.Pointer(&s)).Data
	h.Len = len(s)
	h.Cap = len(s)
	return string(b)
}

func msgpack2individual(individual *Individual, str string) error {
	decoder := msgpack.NewDecoder(strings.NewReader(str))
	arrLen, err := decoder.DecodeArrayLen()
	if err != nil {
		return err
	} else if arrLen != 2 {
		return errors.New("@ERR! INVALID INDIVID %s")
	}

	individual.uri, err = decoder.DecodeString()
	resMapI, err := decoder.DecodeMap()
	resMap := resMapI.(map[interface{}]interface{})

	for keyI, resArrI := range resMap {
		var resource Resource

		predicate := keyI.(string)
		resArr := resArrI.([]interface{})
		individual.resources[predicate] = make(Resources, len(resArr))

		for i := 0; i < len(resArr); i++ {
			resI := resArr[i]
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
		}
	}

	return nil
}
