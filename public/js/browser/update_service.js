/**
  Update service for individuals that were changed on server
  NB: Access has to be configured via haproxy or the like
*/


veda.Module(function (veda) { "use strict";

  veda.UpdateService = function () {

    var notify = veda.Notify ? new veda.Notify() : function () {};

    // Singleton pattern
    if (veda.UpdateService.prototype._singletonInstance) {
      return veda.UpdateService.prototype._singletonInstance;
    }
    veda.UpdateService.prototype._singletonInstance = this;

    var self = riot.observable(this);

    var protocol = location.protocol === "http:" ? "ws:" : "wss:",
        address0 = protocol + "//" + location.host + "/ccus",
        address1 = protocol + "//" + location.hostname + ":8088/ccus",
        socket,
        msgTimeout,
        msgDelay = 1000,
        connectTimeout,
        connectTries = 0,
        initialDelay = Math.round(1000 + 4000 * Math.random()),
        connectDelay = 10000,
        maxConnectDelay = 60000,
        list = {},
        delta = {};

    var address = address0;

    this.list = function () {
      return list;
    };

    this.synchronize = function() {
      if (msgTimeout) {
        msgTimeout = clearTimeout(msgTimeout);
      }
      list = {};
      delta = {};
      if (socket && socket.readyState === 1) {
        socket.send("=");
        //console.log("client -> server: =");
      }
    };

    this.subscribe = function(uri) {
      if (!uri) { return; }
      if (list[uri]) {
        ++list[uri].subscribeCounter;
        return;
      }
      var individual = new veda.IndividualModel(uri);
      var updateCounter = individual.hasValue("v-s:updateCounter") ? individual.get("v-s:updateCounter")[0] : 0;
      list[uri] = {
        subscribeCounter: 1,
        updateCounter: updateCounter
      };
      delta[uri] = {
        operation: "+",
        updateCounter: updateCounter
      };
      if (!msgTimeout) {
        msgTimeout = setTimeout(pushDelta, msgDelay);
      }
    };

    this.unsubscribe = function (uri) {
      if (uri === "*" || !uri) {
        if (msgTimeout) {
          msgTimeout = clearTimeout(msgTimeout);
        }
        list = {};
        delta = {};
        if (socket && socket.readyState === 1) {
          socket.send("-*");
          //console.log("client -> server: -*");
        }
      } else {
        if ( !list[uri] ) {
          return;
        } else if ( list[uri].subscribeCounter === 1 ) {
          delete list[uri];
          delta[uri] = {
            operation: "-"
          };
          if (!msgTimeout) {
            msgTimeout = setTimeout(pushDelta, msgDelay);
          }
        } else {
          --list[uri].subscribeCounter;
          return;
        }
      }
    };

    function pushDelta() {
      var subscribe = [],
          unsubscribe = [],
          subscribeMsg,
          unsubscribeMsg;
      for (var uri in delta) {
        if (delta[uri].operation === "+") {
          subscribe.push("+" + uri + "=" + delta[uri].updateCounter);
        } else {
          unsubscribe.push("-" + uri);
        }
      }
      unsubscribeMsg = unsubscribe.join(",");
      subscribeMsg = subscribe.join(",");
      if (socket && socket.readyState === 1 && unsubscribeMsg) {
        socket.send(unsubscribeMsg);
        //console.log("client -> server:", unsubscribeMsg);
      }
      if (socket && socket.readyState === 1 && subscribeMsg) {
        socket.send(subscribeMsg);
        //console.log("client -> server:", subscribeMsg);
      }
      delta = {};
      msgTimeout = undefined;
    }

    socket = initSocket();

    return this;

    function initSocket () {
      var socket = new WebSocket(address);
      socket.onopen = openedHandler;
      socket.onclose = closedHandler;
      socket.onerror = errorHandler;
      socket.onmessage = messageHandler;
      return socket;
    }

    function openedHandler(event) {
      //if (connectTries >= 0) { notify("success", {name: "WS: Соединение восстановлено"}) }
      console.log("client: websocket opened");
      connectTries = 0;
      var msg = "ccus=" + veda.ticket;
      if (socket && socket.readyState === 1) {
        //Handshake
        socket.send(msg);
        //console.log("client -> server:", msg);
      }
      var uris = Object.keys(list);
      self.synchronize();
      uris.map(self.subscribe);
    }

    function closedHandler(event) {
      var delay = initialDelay + connectDelay * connectTries;
      if (delay < maxConnectDelay) { connectTries++; }
      //notify("danger", {name: "WS: Соединение прервано"});
      console.log("client: websocket closed,", "re-connect in", Math.round( delay / 1000 ), "secs" );
      connectTimeout = setTimeout(function () {
        if (address == address0) {
          address = address1;
        } else {
          address = address0;
        }
        socket = initSocket();
      }, delay);
    }

    function errorHandler(event) {
      //notify("danger", {name: "WS: Ошибка соединения"});
      //console.log("client: websocket error");
    }

    function messageHandler(event) {
      var msg = event.data,
          uris;
      //console.log("server -> client:", msg);
      if (msg.indexOf("=") === 0) {
        uris = msg.substr(1);
      } else {
        uris = msg;
      }
      if (uris.length === 0) {
        return;
      }
      uris = uris.split(",");
      for (var i = 0; i < uris.length; i++) {
        try {
          var tmp = uris[i].split("="),
              uri = tmp[0],
              updateCounter = parseInt(tmp[1]),
              individual = new veda.IndividualModel(uri),
              list = self.list();
          if ( individual.hasValue("v-s:updateCounter", updateCounter) || individual.isDraft() ) { continue; }
          if (list[uri]) {
            list[uri].updateCounter = updateCounter;
          }
          individual.reset(); // Reset to DB
        } catch (error) {
          console.log("error: individual update service failed", error);
        }
      }
    }

  };

});
