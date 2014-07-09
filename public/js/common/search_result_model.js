// Search result Model

"use strict";

function SearchResultModel(veda, uri, container) {
	var self = riot.observable(this);
	
	self.on("individual:loaded", function() {
		veda.trigger("search_result:loaded", self, container);
	});
	
	// Inherit from IndividualModel
	IndividualModel.call(self, veda, uri);
	
	return self;
};
