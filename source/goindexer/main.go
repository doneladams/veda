package main

import (
	"encoding/json"
	"fmt"
	"log"
	"strings"
)

var conn Connector

type Names map[string]bool

var systicket ticket

func main() {
	var rc ResultCode
	conn.Connect("127.0.0.1:9999")

	rc, systicket = getTicket("systicket")
	if rc != Ok {
		log.Fatal("@ERR GETTING SYSTICKET ", rc)
	}

	onto := NewOnto()
	onto.Load()
	/*
		ResType             DataType
		Lang                Lang
		StrData             string
		BoolData            bool
		LongData            int64
		DecimalMantissaData int64
		DecimalExponentData int64
	*/
	/*	configCommon := `
			rt_field = uri
			rt_field = res_type
			rt_filed = lang
			rt_field = str_data
			rt_field = bool_data
			rt_field = long_data
			rt_field = decimal_mantissa_data
			rt_field = decimal_exponent_data

			rt_attr_string = uri_attr
			rt_attr_biging = res_type_attr
			rt_attr_bigint = lang_attr
			rt_attr_bool = bool_data_attr
			rt_attr_bigint = long_data_attr
			rt_attr_bigint = decimal_mantissa_data_attr
			rt_attr_bigint = decimal_exponent_data_attr
		}
		`*/

	request := fmt.Sprintf("%v�'rdfs:domain'==='%s'���false�0�10000�0", systicket.Id, "v-s:Person")
	rc, queryBytes := query(request)
	if rc != Ok {
		log.Printf("@ERR ON QUERY RDFS:DOMAIN %v: %v\n", "v-s:Person", rc)
	}

	var jsonData map[string]interface{}
	err := json.Unmarshal(queryBytes, &jsonData)
	if err != nil {
		log.Printf("@ERR ON DECODING QUERY RDFS:DOMAIN %v RESPONSE JSON: %v\n", "v-s:Person", err)
		return
	}

	urisI := jsonData["result"].([]interface{})
	uris := make([]string, len(urisI))
	for i := 0; i < len(urisI); i++ {
		uris[i] = urisI[i].(string)
	}

	rr := conn.Get(false, "cfg:VedaSystem", uris, false)

	if rr.CommonRC != Ok {
		log.Printf("@ERR COMMON ON GET RDFS:DOMAIN %v: %v\n", "v-s:Person", rr.CommonRC)
		return
	}

	fmt.Printf("index %s {\n", "v_s_Person")
	fmt.Printf("\ttype=rt\n")
	fmt.Printf("\tpath=data/sphinx-indexes/%s\n", "v_s_Person")
	fmt.Printf("\trt_field = uri\n\trt_attr_string=uri_attr\n")
	for i := 0; i < len(rr.Data); i++ {
		domain := MsgpackToIndividual(rr.Data[i])
		rdfsRange := domain.Resources["rdfs:range"][0].StrData
		attr := strings.Replace(strings.Replace(domain.Uri, ":", "_", -1), "-", "_", -1)
		fmt.Printf("\trt_field = %s\n", attr)
		switch rdfsRange {
		case "xsd:string":
			fmt.Printf("\trt_attr_string = %s_attr\n", attr)
		case "xsd:dateTime":
			fmt.Printf("\trt_attr_bigint = %s_attr\n", attr)
		default:
			log.Printf("@UNKNOWN RDFS:RANGE %v\n", rdfsRange)
		}
	}

	fmt.Println("}")

	/*for k, i := range onto.individuals {
		if i.Resources["rdf:type"][0].StrData != "v-s:Person" {
			continue
		}
		log.Println(k)
		fmt.Printf("index %s {\n", strings.Replace(i.Resources["rdf:type"][0].StrData, ":", "_", -1))
		fmt.Printf("\ttype=rt\n")
		fmt.Printf("\tpath=data/sphinx-indexes/%s\n", strings.Replace(i.Resources["rdf:type"][0].StrData, ":", "_", -1))
		fmt.Printf("%s", configCommon)
		break
	}*/
}
