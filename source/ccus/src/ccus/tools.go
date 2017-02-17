package main

import (
	"bufio"
	"encoding/binary"
	"fmt"
	"log"
	"reflect"
	"unsafe"
)

// #define MP_SOURCE 1
// #include "msgpuck.h"
import "C"

type CustomDecimal struct {
	Mantissa int
	Exponent int
}

func NewCustomDecimal(mantissa int, exponent int) CustomDecimal {
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

func msgpack2individual(individual *Individual, msgpack string) {
	var curiLen C.uint32_t

	startPtr := C.CString(msgpack)
	ptr := startPtr
	arrLen := C.mp_decode_array(&ptr)

	if arrLen != 2 {
		log.Fatal("INCORRECT MSGPACK ARR LEN IS NOT 2: ", msgpack)
	}

	curi := C.mp_decode_str(&ptr, &curiLen)
	individual.uri = C.GoStringN(curi, C.int(curiLen))
	// fmt.Println("DECODED MAIN URI")

	cmpLen := int(C.mp_decode_map(&ptr))

	for i := 0; i < cmpLen; i++ {
		var resType DataType
		var resource Resource
		var curiResLen C.uint32_t
		curiRes := C.mp_decode_str(&ptr, &curiResLen)
		predicate := C.GoStringN(curiRes, C.int(curiResLen))
		log.Printf("DECODED predicate %v", predicate)

		resArrLen := int(C.mp_decode_array(&ptr))
		individual.resources[predicate] = make(Resources, int(resArrLen))
		for j := 0; j < resArrLen; j++ {
			switch C.mp_typeof(*ptr) {
			case C.MP_ARRAY:
				cresLen := C.mp_decode_array(&ptr)
				log.Printf("DECODED ARRAY")
				// fmt.Println(cresLen)
				if cresLen == 2 {
					fmt.Println("DECODED ARR 2")
					if C.mp_typeof(*ptr) == C.MP_UINT {
						resType = DataType(C.mp_decode_uint(&ptr))
					} else {
						resType = DataType(C.mp_decode_int(&ptr))
					}

					if resType == Datetime {
						log.Printf("Decoded Datetime")
						if C.mp_typeof(*ptr) == C.MP_UINT {
							resource.data = int(C.mp_decode_uint(&ptr))
						} else {
							resource.data = int(C.mp_decode_int(&ptr))
						}
						resource._type = Datetime
					} else if resType == String {
						// fmt.Println("TRY TO DECODE STR")
						if C.mp_typeof(*ptr) != C.MP_NIL {
							var valLen C.uint32_t
							val := C.mp_decode_str(&ptr, &valLen)
							resource.data = C.GoStringN(val, C.int(valLen))
						} else {
							C.mp_decode_nil(&ptr)
							resource.data = ""
						}
						// fmt.Println("DECODED STR")
					}
				} else if cresLen == 3 {
					// fmt.Println("DECODED ARR 3")
					if C.mp_typeof(*ptr) == C.MP_UINT {
						resType = DataType(C.mp_decode_uint(&ptr))
					} else {
						resType = DataType(C.mp_decode_int(&ptr))
					}

					if resType == Decimal {
						var mantissa, exponent int

						if C.mp_typeof(*ptr) == C.MP_UINT {
							mantissa = int(C.mp_decode_uint(&ptr))
						} else {
							mantissa = int(C.mp_decode_int(&ptr))
						}

						if C.mp_typeof(*ptr) == C.MP_UINT {
							exponent = int(C.mp_decode_uint(&ptr))
						} else {
							exponent = int(C.mp_decode_int(&ptr))
						}

						resource.data = NewCustomDecimal(mantissa, exponent)
					} else if resType == String {
						// fmt.Println("TRY TO DECODE STR")
						if C.mp_typeof(*ptr) != C.MP_NIL {
							var valLen C.uint32_t
							val := C.mp_decode_str(&ptr, &valLen)
							resource.data = C.GoStringN(val, C.int(valLen))
						} else {
							C.mp_decode_nil(&ptr)
							resource.data = ""
						}
						// fmt.Println("DECODED STR")

						if C.mp_typeof(*ptr) == C.MP_UINT {
							resource.lang = LANG(C.mp_decode_uint(&ptr))
						} else {
							resource.lang = LANG(C.mp_decode_int(&ptr))
						}
					}
				}
			case C.MP_STR:
				if C.mp_typeof(*ptr) != C.MP_NIL {
					var valLen C.uint32_t
					val := C.mp_decode_str(&ptr, &valLen)
					resource.data = C.GoStringN(val, C.int(valLen))
				} else {
					C.mp_decode_nil(&ptr)
					resource.data = ""
				}
			case C.MP_INT:
				fallthrough
			case C.MP_UINT:
				if C.mp_typeof(*ptr) == C.MP_UINT {
					resource.data = int(C.mp_decode_uint(&ptr))
				} else {
					resource.data = int(C.mp_decode_int(&ptr))
				}
			case C.MP_BOOL:
				resource.data = bool(C.mp_decode_bool(&ptr))
			}

			// log.Printf("RESULT RESOURCE ", resource)
			individual.resources[predicate][j] = resource
		}
	}
}
