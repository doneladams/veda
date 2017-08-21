package main

import (
	"encoding/json"
	"fmt"
	"log"
)

type Bdathe struct {
	ElToSuperEls map[string]Names
	ElToSubEls   map[string]Names
	Orphans      Names
	Els          Names
}

type Onto struct {
	reloadCount int
	individuals map[string]*Individual
	class       Bdathe
	property    Bdathe
}

func NewBdathe() Bdathe {
	return Bdathe{ElToSuperEls: make(map[string]Names), ElToSubEls: make(map[string]Names),
		Orphans: make(Names), Els: make(Names)}
}

func NewOnto() Onto {
	return Onto{reloadCount: 0, individuals: make(map[string]*Individual), class: NewBdathe(), property: NewBdathe()}
}

func (o *Onto) Load() {
	o.reloadCount++

	request := fmt.Sprintf("%v�'rdf:type' === 'rdfs:Class' || 'rdf:type' === 'rdf:Property' || 'rdf:type' === 'owl:Class' || 'rdf:type' === 'owl:ObjectProperty' || 'rdf:type' === 'owl:DatatypeProperty'���false�0�10000�0", systicket.Id)
	rc, queryBytes := query(request)

	if rc != Ok {
		log.Println("@ERR ON QUERY ONTOLOGY ", rc)
	}

	var jsonData map[string]interface{}
	err := json.Unmarshal(queryBytes, &jsonData)
	if err != nil {
		log.Println("@ERR ON DECODING QUERY RESPONSE JSON: ", err)
		return
	}

	urisI := jsonData["result"].([]interface{})
	uris := make([]string, len(urisI))
	for i := 0; i < len(urisI); i++ {
		uris[i] = urisI[i].(string)
	}

	rr := conn.Get(false, "cfg:VedaSystem", uris, false)

	if rr.CommonRC != Ok {
		log.Println("@ERR COMMON ON GET ONTOLOGY ", rr.CommonRC)
		return
	}

	for i := 0; i < len(rr.Data); i++ {
		indv := MsgpackToIndividual(rr.Data[i])
		o.individuals[indv.Uri] = indv
	}

	for _, indv := range o.individuals {
		o.updateOntoHierarchy(indv, false)
	}
}

func (o *Onto) updateOntoHierarchy(indv *Individual, replace bool) {
	typeUri := indv.Uri
	// icl := make(Names)
	isClass := false
	isProp := false

	isDeleted := false
	if indv.Resources["v-s:deleted"] != nil {
		isDeleted = indv.Resources["v-s:deleted"][0].BoolData
	}

	if isDeleted {
		delete(o.individuals, typeUri)

		for _, i := range o.individuals {
			o.updateOntoHierarchy(i, false)
		}

		return
	}

	rdfTypes := indv.Resources["rdf:type"]
	for i := 0; i < len(rdfTypes); i++ {
		rdfType := rdfTypes[i].StrData
		if rdfType == "rdf:Property" || rdfType == "owl:ObjectProperty" || rdfType == "owl:DatatypeProperty" {

			ok := false
			if replace {
				o.individuals[typeUri] = indv
			} else {
				_, ok = o.property.ElToSuperEls[typeUri]
			}

			if !ok {
				o.updateElement(typeUri, o.property, "rdfs:subPropertyOf")
			}

			o.property.Els[typeUri] = true
			isProp = true
		} else if rdfType == "owl:Class" || rdfType == "rdfs:Class" {
			ok := false
			if replace {
				o.individuals[typeUri] = indv
			} else {
				_, ok = o.property.ElToSuperEls[typeUri]
			}

			if !ok {
				o.updateElement(typeUri, o.property, "rdfs:subPropertyOf")
			}

			isClass = true
		}
	}

	if isClass {
		_, ok := o.class.Orphans[typeUri]
		if ok {
			nuscs, ok := o.class.ElToSubEls[typeUri]
			if ok {
				for k, _ := range nuscs {
					o.updateElement(k, o.class, "rdfs:subClassOf")
					o.class.Orphans[k] = false
				}
			}
		}
	} else if isProp {
		_, ok := o.class.Orphans[typeUri]
		if ok {
			nuscs, ok := o.class.ElToSubEls[typeUri]
			if ok {
				for k, _ := range nuscs {
					o.updateElement(k, o.class, "rdfs:subPropertyOf")
					o.property.Orphans[k] = false
				}
			}
		}
	}
}

func (o *Onto) updateElement(typeUri string, elh Bdathe, parentPredicate string) {
	superElements := make(Names)
	o.prepareSuperElements(parentPredicate, elh, &superElements, &o.individuals, typeUri, 0)
	elh.ElToSuperEls[typeUri] = superElements

	for k, _ := range superElements {
		_, ok := o.individuals[k]
		if !ok {
			elh.Orphans[k] = true
			delete(elh.Els, k)
		}

		elh.ElToSubEls[k][typeUri] = true
	}
}

func (o *Onto) prepareSuperElements(parentPredicate string, elh Bdathe, superElements *Names,
	elements *map[string]*Individual, lookCl string, level int) {
	i, ok := (*elements)[lookCl]
	if !ok {
		return
	}

	resources, ok := i.Resources[parentPredicate]
	for i := 0; i < len(resources); i++ {
		if resources[i].ResType != Uri {
			continue
		}

		if resources[i].StrData == lookCl {
			o.prepareSuperElements(parentPredicate, elh, superElements, elements, resources[i].StrData, level+1)
		}
	}
}
