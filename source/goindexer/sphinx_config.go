package main

import (
	"bufio"
	"crypto/md5"
	"encoding/json"
	"fmt"
	"log"
	"os"
	"strings"
)

func createSphinxConfig(onto *Onto) {
	config, err := os.Create("data/sphinx.conf")

	if err != nil {
		log.Fatal("@ERR CREATING CONFIG ", err)
	}

	wr := bufio.NewWriter(config)
	for requestDomainOrig := range onto.individuals {
		requestDomain := requestDomainOrig
		domainAttrs := make([]ClassAttr, 0)

		alreadyHad := make(map[string]bool)
		hashStr := md5.Sum([]byte(strings.Replace(strings.Replace(requestDomain, ":", "_", -1), "-", "_", -1)))
		// wr.WriteString(fmt.Sprintf("index %s {\n", strings.Replace(strings.Replace(requestDomain,
		// ":", "_", -1), "-", "_", -1)))
		wr.WriteString(fmt.Sprintf("index i%x {\n", hashStr))
		wr.WriteString(fmt.Sprintf("\ttype=rt\n"))
		wr.WriteString(fmt.Sprintf("\tpath=data/sphinx-indexes/%s\n", strings.Replace(strings.Replace(requestDomain, ":", "_", -1), "-", "_", -1)))
		// /var/lib/sphinxsearch/data/
		// wr.WriteString(fmt.Sprintf("\tpath=/var/lib/sphinxsearch/data/%s\n", strings.Replace(strings.Replace(requestDomain, ":", "_", -1), "-", "_", -1)))
		wr.WriteString(fmt.Sprintf("\trt_field = uri\n\trt_attr_string=uri_attr\n"))

		for {
			request := fmt.Sprintf("%v�'rdfs:domain'==='%s'���false�0�10000�0", systicket.Id, requestDomain)
			rc, queryBytes := query(request)
			if rc != Ok {
				log.Printf("@ERR ON QUERY RDFS:DOMAIN %v: %v\n", requestDomain, rc)
				break
			}

			var jsonData map[string]interface{}
			err := json.Unmarshal(queryBytes, &jsonData)
			if err != nil {
				log.Printf("@ERR ON DECODING QUERY RDFS:DOMAIN %v RESPONSE JSON: %v\n", requestDomain, err)
				break
			}

			urisI := jsonData["result"].([]interface{})
			uris := make([]string, 0)
			for i := 0; i < len(urisI); i++ {
				if alreadyHad[urisI[i].(string)] {
					continue
				}
				uris = append(uris, urisI[i].(string))
			}

			if len(uris) == 0 {
				break
			}

			rr := conn.Get(false, "cfg:VedaSystem", uris, false)

			if rr.CommonRC != Ok {
				log.Printf("@ERR COMMON ON GET RDFS:DOMAIN %v: %v\n", requestDomain, rr.CommonRC)
				break
			}

			for i := 0; i < len(rr.Data); i++ {
				domain := MsgpackToIndividual(rr.Data[i])
				alreadyHad[domain.Uri] = true
				attr := strings.Replace(strings.Replace(domain.Uri, ":", "_", -1), "-", "_", -1)
				res, ok := domain.Resources["rdfs:range"]
				if !ok {
					wr.WriteString(fmt.Sprintf("\trt_attr_string = %s_attr\n", attr))
					continue
				}
				rdfsRange := res[0].StrData

				switch rdfsRange {
				case "xsd:string", "rdfs:Literal":
					domainAttrs = append(domainAttrs,
						ClassAttr{name: domain.Uri, fieldName: attr, attrName: attr + "_attr"})
					wr.WriteString(fmt.Sprintf("\trt_field = %s\n", attr))
					wr.WriteString(fmt.Sprintf("\trt_attr_string = %s_attr_none\n", attr))
					wr.WriteString(fmt.Sprintf("\trt_attr_string = %s_attr_ru\n", attr))
					wr.WriteString(fmt.Sprintf("\trt_attr_string = %s_attr_en\n", attr))
				case "xsd:dateTime":
					domainAttrs = append(domainAttrs,
						ClassAttr{name: domain.Uri, fieldName: attr, attrName: attr + "_attr"})
					wr.WriteString(fmt.Sprintf("\trt_field = %s\n", attr))
					wr.WriteString(fmt.Sprintf("\trt_attr_bigint = %s_attr\n", attr))
				case "xsd:boolean":
					domainAttrs = append(domainAttrs,
						ClassAttr{name: domain.Uri, fieldName: attr, attrName: attr + "_attr"})
					wr.WriteString(fmt.Sprintf("\trt_field = %s\n", attr))
					wr.WriteString(fmt.Sprintf("\trt_attr_bool = %s_attr\n", attr))
				case "xsd:integer":
					domainAttrs = append(domainAttrs,
						ClassAttr{name: domain.Uri, fieldName: attr, attrName: attr + "_attr"})
					wr.WriteString(fmt.Sprintf("\trt_field = %s\n", attr))
					wr.WriteString(fmt.Sprintf("\trt_attr_bigint = %s_attr\n", attr))
				case "xsd:decimal":
					domainAttrs = append(domainAttrs,
						ClassAttr{name: domain.Uri, fieldName: attr, attrName: attr + "_attr"})
					wr.WriteString(fmt.Sprintf("\trt_field = %s\n", attr))
					wr.WriteString(fmt.Sprintf("\trt_attr_bigint = %s_attr_e\n", attr))
					wr.WriteString(fmt.Sprintf("\trt_attr_bigint = %s_attr_m\n", attr))
				default:
					domainAttrs = append(domainAttrs,
						ClassAttr{name: domain.Uri, fieldName: "", attrName: attr + "_attr"})
					wr.WriteString(fmt.Sprintf("\trt_attr_string = %s_attr\n", attr))
					// log.Printf("@UNKNOWN RDFS:RANGE %v\n", rdfsRange)
				}
			}

			res, ok := onto.individuals[requestDomain].Resources["rdfs:subClassOf"]
			if ok {
				requestDomain = res[0].StrData
				continue
			}

			break
		}

		classAttrs[requestDomainOrig] = domainAttrs
		wr.WriteString("}\n\n")
	}

	wr.WriteString(configCommon)
	wr.Flush()
}
