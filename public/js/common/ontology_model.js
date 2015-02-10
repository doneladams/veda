// Ontology Model

veda.Module(function OntologyModel(veda) { "use strict";

	/* owl:Thing && rdfs:Resource domain properties */
	var stopList = [
		//"rdf:type",
		//"rdfs:comment",
		//"rdfs:label",
		//"v-s:deleted",
		"owl:annotatedProperty",
		"owl:annotatedSource",
		"owl:annotatedTarget",
		"owl:bottomDataProperty",
		"owl:bottomObjectProperty",
		"owl:deprecated",
		"owl:differentFrom",
		"owl:members",
		"owl:sameAs",
		"owl:topObjectProperty",
		"owl:topDataProperty",
		"owl:versionInfo",
		"rdf:value",
		"rdfs:isDefinedBy",
		"rdfs:member",
		"rdfs:seeAlso"
	];

	veda.OntologyModel = function () {

		var self = this;
		
		self.classes = {};
		self.properties = {};
		self.templates = {};
		self.specs = {};
		self.other = {};
		
		var storage = typeof localStorage != 'undefined' ? localStorage : undefined;
		
		var q = /* Classes */ 
				"'rdf:type' == 'rdfs:Class' || " +
				"'rdf:type' == 'owl:Class' || " +
				"'rdf:type' == 'rdfs:Datatype' || " +
				"'rdf:type' == 'owl:Ontology' || " +
				/* Properties */
				"'rdf:type' == 'rdf:Property' || " +
				"'rdf:type' == 'owl:DatatypeProperty' || " +
				"'rdf:type' == 'owl:ObjectProperty' || " +
				"'rdf:type' == 'owl:OntologyProperty' || " +
				"'rdf:type' == 'owl:AnnotationProperty' || " +
				/* Templates */
				"'rdf:type' == 'v-ui:ClassTemplate' || " +
				/* Property specifications */
				"'rdf:type' == 'v-ui:PropertySpecification'";
		
		var q_results = query(veda.ticket, q);
		
		if (storage) {
			var unstored_uris = q_results.reduce( function (acc, item) {
				if ( !storage[item] ) { 
					acc.push(item);
				} else { 
					var individual = new veda.IndividualModel( JSON.parse(storage[item]) );
					self[item] = individual;
				}
				return acc;
			}, []);
			
			var unstored = unstored_uris.length ? get_individuals(veda.ticket, unstored_uris) : [];
			unstored.map( function (item) {
				storage[ item["@"] ] = JSON.stringify(item);
				var individual = new veda.IndividualModel( item );
				self[ item["@"] ] = individual;
			});

		} else {
			get_individuals(veda.ticket, q_results).map( function (item) {
				self[ item["@"] ] = new veda.IndividualModel( item );
			});
		}
		
		q_results.map( function (uri) {
			var individual = self[uri];
			
			// Update localStorage after individual was saved
			individual.on("individual:afterSave", function (data) {
				storage[uri] = data;
			});
			
			switch ( individual["rdf:type"][0].id ) {
				case "rdfs:Class" :
				case "owl:Class" :
					self.classes[individual.id] = individual;
					break
				case "rdf:Property" :
				case "owl:DatatypeProperty" :
				case "owl:ObjectProperty" :
				case "owl:OntologyProperty" :
				case "owl:AnnotationProperty" :
					self.properties[individual.id] = individual;
					break
				case "v-ui:ClassTemplate" :
					self.templates[individual.id] = individual;
					break
				case "v-ui:PropertySpecification" :
					self.specs[individual.id] = individual;
					break
				default :
					self.other[individual.id] = individual;
					break
			}
		});

		Object.keys(self.classes).map( function (uri) {
			var _class = self.classes[uri];
			if (!_class["rdfs:subClassOf"]) return;
			_class["rdfs:subClassOf"].map( function ( item ) {
				item.subClasses = item.subClasses || {};
				item.subClasses[_class.id] = _class;
			});
		});

		Object.keys(self.properties).map( function (uri) {
			if (stopList.indexOf(uri) >= 0) return;
			var property = self.properties[uri];
			if (!property["rdfs:domain"]) return;
			property["rdfs:domain"].map( function ( item ) {
				(function fillDomainProperty (_class) {
					_class.domainProperties = _class.domainProperties || {};
					_class.domainProperties[property.id] = property;
					if (_class.subClasses && Object.keys(_class.subClasses).length) {
						Object.keys(_class.subClasses).map( function (subClass_uri) {
							fillDomainProperty (_class.subClasses[subClass_uri]);
						});
					}
				})(item);
			});
		});

		Object.keys(self.templates).map( function (uri) {
			var template = self.templates[uri];
			if (!template["v-ui:forClass"]) return; 
			template["v-ui:forClass"].map( function ( item ) {
				item.documentTemplate = item.documentTemplate || {};
				item.documentTemplate = template;
			});
		});

		Object.keys(self.specs).map( function (uri) {
			var spec = self.specs[uri];
			if (!spec["v-ui:forClass"]) return;
			spec["v-ui:forClass"].map( function ( item ) {
				item.specsByProps = item.specsByProps || {};
				item.specsByProps[spec["v-ui:forProperty"][0].id] = spec;
			});
		});

		return self;
			
	};

});
