// Veda HTTP server functions
veda.Module(function (veda) { "use strict";

  // Check server health
  var notify = veda.Notify ? new veda.Notify() : function () {};
  var interval;
  function serverWatch() {
    if (interval) { return; }
    var duration = 10000;
    notify("danger", {name: "Connection error"});
    interval = setInterval(function () {
      try {
        var ontoVsn = get_individual(veda.ticket, "cfg:OntoVsn");
        if (ontoVsn) {
          clearInterval(interval);
          interval = undefined;
          notify("success", {name: "Connection restored"});
        } else {
          notify("danger", {name: "Connection error"});
        }
      } catch (ex) {
        notify("danger", {name: "Connection error"});
      }
    }, duration);
  }

  // Server errors
  function BackendError (result) {
    var errorCodes = {
         0: "Server unavailable",
       200: "Ok",
       201: "Created",
       204: "No content",
       400: "Bad request",
       403: "Forbidden",
       404: "Not found",
       422: "Unprocessable entity",
       429: "Too many requests",
       465: "Empty password",
       466: "New password is equal to old",
       467: "Invalid password",
       468: "Invalid secret",
       469: "Password expired",
       470: "Ticket not found",
       471: "Ticket expired",
       472: "Not authorized",
       473: "Authentication failed",
       474: "Not ready",
       475: "Fail open transaction",
       476: "Fail commit",
       477: "Fail store",
       500: "Internal server error",
       501: "Not implemented",
       503: "Service unavailable",
       904: "Invalid identifier",
       999: "Database modified error",
      1021: "Disk full",
      1022: "Duplicate key",
      1118: "Size too large",
      4000: "Connect error"
    };
    this.code = result.status;
    this.name = errorCodes[this.code];
    this.status = result.status;
    this.message = errorCodes[this.code];
    this.stack = (new Error()).stack;
    if (result.status === 0) {
      serverWatch();
    }
    if (result.status === 470 || result.status === 471) {
      veda.trigger("login:failed");
    }
  }
  BackendError.prototype = Object.create(Error.prototype);
  BackendError.prototype.constructor = BackendError;

  // Common server call function
  function call_server(params) {
    var method = params.method,
        url = params.url,
        data = params.data,
        async = params.async || false;
    var xhr = new XMLHttpRequest();
    if (async) {
      return new Promise( function (resolve, reject) {
        xhr.timeout = 120000;
        xhr.onload = function () {
          if (this.status == 200) {
            resolve(
              JSON.parse(
                this.response,
                function (key, value) {
                return key === "data" && this.type === "Datetime" ? new Date(value) :
                       key === "data" && this.type === "Decimal" ? parseFloat(value) : value;
                }
              )
            );
          } else {
            reject( new BackendError(this) );
          }
        };
        xhr.onerror = function () {
          reject( new BackendError(this) );
        };
        if (method === "GET") {
          var params = [];
          for (var name in data) {
            if (typeof data[name] !== "undefined") {
              params.push(name + "=" + encodeURIComponent(data[name]));
            }
          }
          params = params.join("&");
          xhr.open(method, url + "?" + params, async);
          xhr.send();
        } else {
          xhr.open(method, url, async);
          xhr.setRequestHeader("Content-Type", "application/json;charset=UTF-8");
          var payload = JSON.stringify(data, function (key, value) {
            return key === "data" && this.type === "Decimal" ? value.toString() : value;
          });
          xhr.send(payload);
        }
      });
    } else {
      if (method === "GET") {
        var params = [];
        for (var name in data) {
          if (typeof data[name] !== "undefined") {
            params.push(name + "=" + encodeURIComponent(data[name]));
          }
        }
        params = params.join("&");
        xhr.open(method, url + "?" + params, async);
        xhr.send();
      } else {
        xhr.open(method, url, async);
        xhr.setRequestHeader("Content-Type", "application/json;charset=UTF-8");
        var payload = JSON.stringify(data, function (key, value) {
          return key === "data" && this.type === "Decimal" ? value.toString() : value;
        });
        xhr.send(payload);
      }
      if (xhr.status === 200) {
        // Parse with date & decimal reviver
        return JSON.parse(
          xhr.responseText,
          function (key, value) {
            return key === "data" && this.type === "Datetime" ? new Date(value) :
                   key === "data" && (this.type === "Decimal" || this.type === "Decimal") ? parseFloat(value) : value;
          }
        );
      } else {
        throw new BackendError(xhr);
      }
    }
  }

  window.flush = function (module_id, wait_op_id) {
    var arg = arguments[0];
    var isObj = typeof arg === "object";
    var params = {
      method: "GET",
      url: "flush",
      async: isObj ? arg.async : false,
      data: {
        "module_id": isObj ? arg.module_id : module_id,
        "wait_op_id": isObj ? arg.wait_op_id : wait_op_id
      }
    };
    return call_server(params);
  };

  window.get_rights = function (ticket, uri) {
    var arg = arguments[0];
    var isObj = typeof arg === "object";
    var params = {
      method: "GET",
      url: "get_rights",
      async: isObj ? arg.async : false,
      data: {
        "ticket": isObj ? arg.ticket : ticket,
        "uri": isObj ? arg.uri : uri
      }
    };
    return call_server(params);
  };

  window.get_rights_origin = function (ticket, uri) {
    var arg = arguments[0];
    var isObj = typeof arg === "object";
    var params = {
      method: "GET",
      url: "get_rights_origin",
      async: isObj ? arg.async : false,
      data: {
        "ticket": isObj ? arg.ticket : ticket,
        "uri": isObj ? arg.uri : uri
      }
    };
    return call_server(params);
  };

  window.get_membership = function (ticket, uri) {
    var arg = arguments[0];
    var isObj = typeof arg === "object";
    var params = {
      method: "GET",
      url: "get_membership",
      async: isObj ? arg.async : false,
      data: {
        "ticket": isObj ? arg.ticket : ticket,
        "uri": isObj ? arg.uri : uri
      }
    };
    return call_server(params);
  };

  window.authenticate = function (login, password, secret) {
    // TODO: Remove
    if (login == "VedaNTLMFilter")
        login = "cfg:Guest";
    var arg = arguments[0];
    var isObj = typeof arg === "object";
    var params = {
      method: "GET",
      url: "authenticate",
      async: isObj ? arg.async : false,
      data: {
        "login": isObj ? arg.login : login,
        "password": isObj ? arg.password : password,
        "secret": isObj ? arg.secret : secret
      }
    };
    return call_server(params);
  };

  window.get_ticket_trusted = function (ticket, login) {
    var arg = arguments[0];
    var isObj = typeof arg === "object";
    var params = {
      method: "GET",
      url: "get_ticket_trusted",
      async: isObj ? arg.async : false,
      data: {
        "ticket": isObj ? arg.ticket : ticket,
        "login": isObj ? arg.login : login
      }
    };
    return call_server(params);
  };

  window.is_ticket_valid = function (ticket) {
    var arg = arguments[0];
    var isObj = typeof arg === "object";
    var params = {
      method: "GET",
      url: "is_ticket_valid",
      async: isObj ? arg.async : false,
      data: {
        "ticket": isObj ? arg.ticket : ticket
      }
    };
    return call_server(params);
  };

  window.get_operation_state = function (module_id, wait_op_id) {
    var arg = arguments[0];
    var isObj = typeof arg === "object";
    var params = {
      method: "GET",
      url: "get_operation_state",
      async: isObj ? arg.async : false,
      data: {
        "module_id": isObj ? arg.module_id : module_id,
        "wait_op_id": isObj ? arg.wait_op_id : wait_op_id
      }
    };
    return call_server(params);
  };

  window.wait_module = function (module_id, in_op_id) {
    var timeout = 1;
    var op_id_from_module;
    for (var i = 0; i < 100; i++) {
      op_id_from_module = get_operation_state (module_id, in_op_id);
      if (op_id_from_module >= in_op_id) { break; }
      var endtime = new Date().getTime() + timeout;
      while (new Date().getTime() < endtime);
      timeout += 2;
    }
  };

  window.restart = function (ticket) {
    var arg = arguments[0];
    var isObj = typeof arg === "object";
    var params = {
      method: "GET",
      url: "restart",
      async: isObj ? arg.async : false,
      data: {
        "ticket": isObj ? arg.ticket : ticket
      }
    };
    return call_server(params);
  };

  window.backup = function (to_binlog) {
    var arg = arguments[0];
    var isObj = typeof arg === "object";
    var params = {
      method: "GET",
      url: "backup",
      async: isObj ? arg.async : false,
      data: {
        "to_binlog": isObj ? arg.to_binlog : to_binlog
      }
    };
    return call_server(params);
  };

  window.count_individuals = function () {
    var arg = arguments[0];
    var isObj = typeof arg === "object";
    var params = {
      method: "GET",
      url: "count_individuals",
      async: isObj ? arg.async : false,
      data: {}
    };
    return call_server(params);
  };

  window.set_trace = function (idx, state) {
    var arg = arguments[0];
    var isObj = typeof arg === "object";
    var params = {
      method: "GET",
      url: "set_trace",
      async: isObj ? arg.async : false,
      data: {
        "idx": isObj ? arg.idx : idx,
        "state" : isObj ? arg.state : state
      }
    };
    return call_server(params);
  };

  window.query = function (ticket, query, sort, databases, reopen, top, limit, from) {
    var that = this;
    var args = arguments;
    var arg = args[0];
    var isObj = typeof arg === "object";
    var async = isObj ? arg.async : false;
    var params = {
      method: "GET",
      url: "query",
      async: async,
      data: {
        "ticket": isObj ? arg.ticket : ticket,
        "query": isObj ? arg.query : query,
        "sort": (isObj ? arg.sort : sort) || undefined,
        "databases" : (isObj ? arg.databases : databases) || undefined,
        "reopen" : (isObj ? arg.reopen : reopen) || false,
        "top" : (isObj ? arg.top : top) || 0,
        "limit" : (isObj ? arg.limit : limit) || 100000,
        "from"  : (isObj ? arg.from : from) || 0
      }
    };
    if (async) {
      return call_server(params).catch(handleError);
    } else {
      try {
        return call_server(params);
      } catch (backendError) {
        handleError(backendError);
      }
    }
    function handleError(backendError) {
      if (backendError.code === 999) {
        console.log("DB modified during query. Retry.");
        return window.query.apply(that, args);
      } else {
        throw backendError;
      }
    }
  };

  window.get_individual = function (ticket, uri, reopen) {
    var arg = arguments[0];
    var isObj = typeof arg === "object";
    var params = {
      method: "GET",
      url: "get_individual",
      async: isObj ? arg.async : false,
      data: {
        "ticket": isObj ? arg.ticket : ticket,
        "uri": isObj ? arg.uri : uri,
        "reopen" : (isObj ? arg.reopen : reopen) || false
      }
    };
    return call_server(params);
  };

  window.get_individuals = function (ticket, uris) {
    var arg = arguments[0];
    var isObj = typeof arg === "object";
    var params = {
      method: "POST",
      url: "get_individuals",
      async: isObj ? arg.async : false,
      data: {
        "ticket": isObj ? arg.ticket : ticket,
        "uris": isObj ? arg.uris : uris
      },
      contentType: "application/json"
    };
    return call_server(params);
  };

//////////////////////////

  window.remove_individual = function (ticket, uri, assigned_subsystems, event_id, transaction_id) {
    var arg = arguments[0];
    var isObj = typeof arg === "object";
    var params = {
      method: "PUT",
      url: "remove_individual",
      async: isObj ? arg.async : false,
      data: {
        "ticket": isObj ? arg.ticket : ticket,
        "uri": isObj ? arg.uri : uri,
        "assigned_subsystems": (isObj ? arg.assigned_subsystems : assigned_subsystems) || 0,
        "prepare_events": true,
        "event_id": (isObj ? arg.event_id : event_id) || "",
        "transaction_id": (isObj ? arg.transaction_id : transaction_id) || ""
      },
      contentType: "application/json"
    };
    return call_server(params);
  };

  window.put_individual = function (ticket, individual, assigned_subsystems, event_id, transaction_id) {
    var arg = arguments[0];
    var isObj = typeof arg === "object";
    var params = {
      method: "PUT",
      url: "put_individual",
      async: isObj ? arg.async : false,
      data: {
          "ticket": isObj ? arg.ticket : ticket,
          "individual": isObj ? arg.individual : individual,
          "assigned_subsystems" : (isObj ? arg.assigned_subsystems : assigned_subsystems) || 0,
          "prepare_events": true,
          "event_id" : (isObj ? arg.event_id : event_id) || "",
          "transaction_id" : (isObj ? arg.transaction_id : transaction_id) || ""
      },
      contentType: "application/json"
    };
    return call_server(params);
  };

  window.add_to_individual = function (ticket, individual, assigned_subsystems, event_id, transaction_id) {
    var arg = arguments[0];
    var isObj = typeof arg === "object";
    var params = {
      method: "PUT",
      url: "add_to_individual",
      async: isObj ? arg.async : false,
      data: {
        "ticket": isObj ? arg.ticket : ticket,
        "individual": isObj ? arg.individual : individual,
        "assigned_subsystems": (isObj ? arg.assigned_subsystems : assigned_subsystems) || 0,
        "prepare_events": true,
        "event_id": (isObj ? arg.event_id : event_id) || "",
        "transaction_id": (isObj ? arg.transaction_id : transaction_id) || ""
      },
      contentType: "application/json"
    };
    return call_server(params);
  };

  window.set_in_individual = function (ticket, individual, assigned_subsystems, event_id, transaction_id) {
    var arg = arguments[0];
    var isObj = typeof arg === "object";
    var params = {
      method: "PUT",
      url: "set_in_individual",
      async: isObj ? arg.async : false,
      data: {
        "ticket": isObj ? arg.ticket : ticket,
        "individual": isObj ? arg.individual : individual,
        "assigned_subsystems" : (isObj ? arg.assigned_subsystems : assigned_subsystems) || 0,
        "prepare_events": true,
        "event_id" : (isObj ? arg.event_id : event_id) || "",
        "transaction_id" : (isObj ? arg.transaction_id : transaction_id) || ""
      },
      contentType: "application/json"
    };
    return call_server(params);
  };

  window.remove_from_individual = function (ticket, individual, assigned_subsystems, event_id, transaction_id) {
    var arg = arguments[0];
    var isObj = typeof arg === "object";
    var params = {
      method: "PUT",
      url: "remove_from_individual",
      async: isObj ? arg.async : false,
      data: {
        "ticket": isObj ? arg.ticket : ticket,
        "individual": isObj ? arg.individual : individual,
        "assigned_subsystems" : (isObj ? arg.assigned_subsystems : assigned_subsystems) || 0,
        "prepare_events": true,
        "event_id" : (isObj ? arg.event_id : event_id) || "",
        "transaction_id" : (isObj ? arg.transaction_id : transaction_id) || ""
      },
      contentType: "application/json"
    };
    return call_server(params);
  };

  window.put_individuals = function (ticket, individuals, assigned_subsystems, event_id, transaction_id) {
    var arg = arguments[0];
    var isObj = typeof arg === "object";
    var params = {
      method: "PUT",
      url: "put_individuals",
      async: isObj ? arg.async : false,
      data: {
          "ticket": isObj ? arg.ticket : ticket,
          "individuals": isObj ? arg.individuals : individuals,
          "assigned_subsystems" : (isObj ? arg.assigned_subsystems : assigned_subsystems) || 0,
          "prepare_events": true,
          "event_id" : (isObj ? arg.event_id : event_id) || "",
          "transaction_id" : (isObj ? arg.transaction_id : transaction_id) || ""
      },
      contentType: "application/json"
    };
    return call_server(params);
  };

/////////////////////////////////////////

  window.get_property_value = function (ticket, uri, property_uri) {
    var arg = arguments[0];
    var isObj = typeof arg === "object";
    var params = {
      method: "GET",
      url: "get_property_value",
      async: isObj ? arg.async : false,
      data: {
        "ticket": isObj ? arg.ticket : ticket,
        "uri": isObj ? arg.uri : uri,
        "property_uri": isObj ? arg.property_uri : property_uri
      }
    };
    return call_server(params);
  };

  window.execute_script = function (script) {
    var arg = arguments[0];
    var isObj = typeof arg === "object";
    var params = {
      method: "POST",
      url: "execute_script",
      async: isObj ? arg.async : false,
      data: {
        "script": isObj ? arg.script : script
      },
      contentType: "application/json"
    };
    return call_server(params);
  };

});
