package main

var ontologyRdfType = map[string]bool{
	"rdfs:Class":           true,
	"rdf:Property":         true,
	"owl:Class":            true,
	"owl:ObjectProperty":   true,
	"owl:DatatypeProperty": true,
}

func tryStoreInOntologyCache(uri string, rdfType []interface{}, data []byte) {
	for i := 0; i < len(rdfType); i++ {
		if ontologyRdfType[rdfType[i].(map[string]interface{})["data"].(string)] {
			ontologyCache[uri] = data
			return
		}
	}
}
