// Search Model

"use strict";

function SearchModel(veda, q) {
	var self = riot.observable(this);

	// Define Model data setters & getters
	var properties = {q:"", results:{}, results_count:"", selected:{}};
	for (var property in properties) {
		(function(property) {
			Object.defineProperty(self, property, {
				get: function() { return properties[property]; },
				set: function(value) { 
					if (properties[property] == value) return; 
					properties[property] = value; 
					self.trigger("property:changed", property, properties[property]);
				}
   			});
   		})(property);
    }

	self.toggleSelected = function (i) {
		if (!self.results[i]) return;
		if (self.selected[self.results[i].id]) {
			delete self.selected[self.results[i].id];
		} else {
			self.selected[self.results[i].id] = self.results[i];
		}
		self.trigger("search:selected", self.results[i], self.selected);
		return self.selected;
	}

	// Define Model functions
	self.search = function() {
		
		// Clear previous results 
		self.results = {};
		
		query(veda.ticket, self.q, function(data) {
			var results = data;
			for (var i in results) {
				(function(i){
					Object.defineProperty(self.results, i, {
						get: function() { 
							return ( typeof results[i] == 'object' ? results[i] : results[i] = new IndividualModel(veda, results[i]) ); }
					});
				})(i);
			}
			self.results_count = data.length;
			self.trigger("search:complete");
		});
	};

	// Model messages
	self.on("search:loaded", function() {
		if (veda) veda.trigger("search:loaded", self);
	});
	self.on("search:complete", function() {
		if (veda) veda.trigger("search:complete", self);
	});
	self.trigger("search:loaded");
	
	// Search if params given
	self.q = q;
	if (self.q) self.search();
	
	return self;
};
