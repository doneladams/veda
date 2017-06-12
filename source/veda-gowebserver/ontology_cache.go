package main

var ontologyRdfType = map[string]bool{
	"rdfs:Class":           true,
	"rdf:Property":         true,
	"owl:Class":            true,
	"owl:ObjectProperty":   true,
	"owl:DatatypeProperty": true,
}

func tryStoreInOntologyCache(individual map[string]interface{}) {
	uri := individual["@"].(string)
	rdfType := individual["rdf:type"].([]interface{})
	for i := 0; i < len(rdfType); i++ {
		if ontologyRdfType[rdfType[i].(map[string]interface{})["data"].(string)] {
			ontologyCache[uri] = individual
			break
		}
	}
}
