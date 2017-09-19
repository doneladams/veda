package main

//ontologyRdfType is map with rdf:types included to ontology
var ontologyRdfType = map[string]bool{
	"rdfs:Class":           true,
	"rdf:Property":         true,
	"owl:Class":            true,
	"owl:ObjectProperty":   true,
	"owl:DatatypeProperty": true,
}

//tryStoreToOntologyCache checks rdf:type of individual, if its ontology class
//then it is stored to cache with individual's uri used as key
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
