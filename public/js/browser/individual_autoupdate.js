/**

Autoupdate displayed individuals on client when they change on server

 */
/*
veda.Module(function IndividualAutoupdate(veda) { "use strict";

	var socket,
		address = "ws://" + location.hostname + ":8088/ccus";
		//address = "ws://echo.websocket.org";

	try {
		socket = new WebSocket(address);
	} catch (ex) {
		return socket = null;
	}

	socket.onopen = function (event) {
		socket.send("ccus=" + veda.ticket);
	};

	socket.onclose = function (event) {
		veda.off("individual:loaded", updateWatch);
	};

	socket.onmessage = function (event) {
		try {
			var msg = event.data,
				uris = msg.split(",");
			for (var i = 0, uri; (uri = uris[i] && uris[i].split("=")[0]); i++) {
				var ind = new veda.IndividualModel(uri);
				ind.reset();
			}
			//console.log("ccus received:", msg);
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
				var displayCounter = counter[uri] ? ++counter[uri].displayCounter : 1 ;
				var updateCounter = (new veda.IndividualModel(uri))["v-s:updateCounter"][0] ;
				counter[uri] = {
					displayCounter: displayCounter,
					updateCounter: updateCounter
				}
			},
			remove: function (uri) {
				if ( !counter[uri] ) {
					return;
				} else if ( counter[uri].displayCounter === 1) {
					delete counter[uri];
				} else {
					--counter[uri].displayCounter;
				}
			},
			subscribe: function () {
				setTimeout( function () {
					if (socket.readyState === 1) {
						var msg = Object.keys(counter)
							.map(function (uri) {
								return uri + "=" + counter[uri].updateCounter;
							})
							.join(",");
						socket.send(msg);
						//console.log("ccus sent:", msg);
					}
				}, 1000);
			}
		}
	})(socket);
});

*/

// New protocol

veda.Module(function IndividualAutoupdate(veda) { "use strict";

	var socket,
		address = "ws://" + location.hostname + ":8088/ccus";
		//address = "ws://echo.websocket.org";

	try {
		socket = new WebSocket(address);
	} catch (ex) {
		return socket = null;
	}

	socket.onopen = function (event) {
		socket.send("ccus=" + veda.ticket);
	};

	socket.onclose = function (event) {
		veda.off("individual:loaded", updateWatch);
	};

	socket.onmessage = function (event) {
		try {
			var msg = event.data,
					uris = msg.split(",");
			for (var i = 0, uri; (uri = uris[i] && uris[i].split("=")[0]); i++) {
				var ind = new veda.IndividualModel(uri);
				ind.reset();
			}
			//console.log("ccus received:", msg);
		} catch (e) {
			console.log("individual update failed");
		}
	};

//	socket.onmessage = function (event) { console.log("ccus received:", event.data); };

	veda.on("individual:loaded", watch);

	function watch(individual) {
		individual.one("individual:templateReady", displayedHandler);
	}

	function displayedHandler(template) {
		var individual = this;
		subscribeList.subscribe(individual.id);

		template.one("remove", function () {
			subscribeList.unsubscribe(individual.id);
		});
	}

	var subscribeList = (function (socket) {
		var list = {};
		return {
			get: function (uri) {
				return list;
			},
			syncronize: function() {
				var msg = "=";
			},
			subscribe: function(uri) {
				setTimeout(function () {
					if (socket.readyState !== 1 || !uri) { return; }
					var displayCounter = list[uri] ? ++list[uri].displayCounter : 1 ;
					var updateCounter = (new veda.IndividualModel(uri))["v-s:updateCounter"][0] ;
					list[uri] = {
						displayCounter: displayCounter,
						updateCounter: updateCounter
					}
					var msg = "+" + uri;
					socket.send(msg);

					console.log("subscribe", msg, list);

				}, 1000);
			},
			unsubscribe: function (uri) {
				if (socket.readyState !== 1) { return };
				if (uri === "*") {
					list = {};
				} else {
					if ( !list[uri] ) {
						return;
					} else if ( list[uri].displayCounter === 1 ) {
						delete list[uri];
						var msg = "-" + uri;
						socket.send(msg);

						console.log("unsubscribe", msg, list);

					} else {
						--list[uri].displayCounter;
						return;
					}
				}
			},
		}
	})(socket);
});


