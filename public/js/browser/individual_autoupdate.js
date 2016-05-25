/**

Autoupdate displayed individuals on client when they change on server

 */

veda.Module(function IndividualAutoupdate(veda) { "use strict";
	
	var socket,	
		address = "ws://" + location.hostname + ":8088/ccus";

	try {
		socket = new WebSocket(address);
	} catch (ex) {
		return socket = null;
	}
	
	socket.onopen = function (event) {
		socket.send("Client individual update subscription");
	};
	
	socket.onclose = function (event) {
		veda.off("individual:loaded", updateWatch);
	};
	
	socket.onmessage = function (event) {
		try {
			var msg = JSON.parse(event.data);
			for (var uri in msg) {
				var ind = new veda.IndividualModel(uri);
				ind.reset();
			}
		} catch (e) {
			"individual update failed";
		}
	};

	veda.on("individual:loaded", updateWatch);

	function updateWatch(individual, container, template, mode) {
		individual.one("individual:templateReady", displayedHandler);
		if (container === "#main") {
			visible.subscribe();
		}
	}
	
	function displayedHandler(template) {
		var individual = this;
		visible.add(individual.id);
		template.one("remove", function () {
			visible.remove(individual.id);
		});
	}	

	var visible = (function (socket) {
		var counter = {};
		return {
			add: function (uri) {
				return counter[uri] ? ++counter[uri] : counter[uri] = 1;
			},
			remove: function (uri) {
				if (typeof counter[uri] === "undefined") return false;
				return ( typeof counter[uri] === "number" && counter[uri] === 1 ? delete counter[uri] : --counter[uri] );
			},
			subscribe: function () {
				setTimeout( function () {
					if (socket.readyState === 1) {
						var msg = JSON.stringify(counter);
						socket.send(msg);
					}
				}, 1000);
			}
		}
	})(socket);
});
