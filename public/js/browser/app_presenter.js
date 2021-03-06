// Veda application Presenter

veda.Module(function (veda) { "use strict";

  // View resource using special templates:
  // "v-ui:ttl" on Ctrl + Alt + Click
  // "v-ui:json" on Alt + Shift + Click
  // "v-ui:generic" on Ctrl + Alt + Shift + Click
  $("body").on("click", "[resource], [about]", function (e) {
    var uri = $(this).attr("resource") || $(this).attr("about");
    var hash = "#/" + uri;
    if (e.altKey && e.ctrlKey && e.shiftKey) {
      e.preventDefault();
      e.stopPropagation();
      setTimeout(function () {
        riot.route(hash +  "//v-ui:generic");
      });
    } else if (e.altKey && e.ctrlKey) {
      e.preventDefault();
      e.stopPropagation();
      setTimeout(function () {
        riot.route(hash +  "//v-ui:ttl");
      });
    } else if (e.altKey && e.shiftKey) {
      e.preventDefault();
      e.stopPropagation();
      setTimeout(function () {
        riot.route(hash +  "//v-ui:json");
      });
    }
  });
  // Outline resource containers to switch view to special templates
  var outlined = [];
  $(document)
    .on("keydown", function (e) {
      if (e.altKey && e.shiftKey || e.altKey && e.ctrlKey || e.altKey && e.ctrlKey && e.shiftKey) {
        $("body").on("mouseover", "[resource], [about]", outline);
      }
    })
    .on("keyup", removeOutline);
  function outline(e) {
    if (e.altKey && e.shiftKey || e.altKey && e.ctrlKey || e.altKey && e.ctrlKey && e.shiftKey) {
      e.stopPropagation();
      outlined.forEach(function (item) { item.removeAttr("title").removeClass("gray-outline") });
      var $this = $(this);
      $this.addClass("gray-outline").attr("title", $this.attr("resource") || $this.attr("about"));
      outlined = [ $this ];
    } else {
      removeOutline(e);
    }
  }
  function removeOutline(e) {
    $("body").off("mouseover", outline);
    outlined.forEach(function (item) { item.removeAttr("title").removeClass("gray-outline") });
    outlined = [];
  }

  // Localize resources on language change
  veda.on("language:changed", function () {
    var resourcesNodes = $("[resource], [about]");
    var resources = resourcesNodes.map(function () {
      var $this = $(this);
      return $this.attr("about") || $this.attr("resource");
    }).get();
    resources = veda.Util.unique(resources);
    resources.forEach(function (resource_uri) {
      var resource = new veda.IndividualModel(resource_uri);
      for (var property_uri in resource.properties) {
        if (property_uri === "@") { continue; }
        if ( resource.properties[property_uri] && resource.properties[property_uri].length && resource.properties[property_uri][0].type === "String" ) {
          resource.trigger("propertyModified", property_uri, resource.get(property_uri));
          resource.trigger(property_uri, resource.get(property_uri));
        }
      }
    });
  });

  // Prevent empty links routing
  $("body").on("click", "[href='']", function (e) {
    e.preventDefault();
  });

  // Route on link click (IE mandatory!)
  $("body").on("click", "[href^='#/']", function (e) {
    e.preventDefault();
    var hash = $(this).attr("href");
    return ( hash === location.hash ? false : riot.route(hash) );
  });

  // App loading indicator
  var loadIndicator = $("#load-indicator");
  veda.on("starting", function () {
    loadIndicator.show();
  }).on("started", function () {
    loadIndicator.hide();
  });

  // Triggered in veda.start()
  veda.one("started", function () {
    var welcome;
    if (veda.user.hasValue("v-s:origin", "ExternalUser")) {
      welcome = (new veda.IndividualModel("cfg:WelcomeExternal"))["rdf:value"][0];
    } else {
      welcome = (new veda.IndividualModel("cfg:Welcome"))["rdf:value"][0];
    }
    // Router function
    riot.route( function (hash) {
      if ( !hash ) {
        return riot.route("#/" + welcome.id);
      }
      if ( hash.indexOf("#/") < 0 ) { return; }
      var tokens = decodeURI(hash).slice(2).split("/"),
          uri = tokens[0],
          container = tokens[1],
          template = tokens[2],
          mode = tokens[3],
          extra = tokens[4];
      if (extra) {
        extra = extra.split("&").reduce(function (acc, pair) {
          var split = pair.split("="),
              name  = split[0] || "",
              value = split[1] || "";
          acc[name] = acc[name] || [];
          acc[name].push( parse(value) );
          return acc;
        }, {});
      }
      if (uri === "drafts") {
        return veda.trigger("load:drafts");
      }
      if (uri) {
        var individual = new veda.IndividualModel(uri);
        individual.present(container, template, mode, extra);
      } else {
        riot.route("#/" + welcome.id);
      }
    });
  });
  function parse (value) {
    if ( !isNaN( value.split(" ").join("").split(",").join(".") ) ) {
      return parseFloat( value.split(" ").join("").split(",").join(".") );
    } else if ( !isNaN( Date.parse(value) ) ) {
      return new Date(value);
    } else if ( value === "true" ) {
      return true;
    } else if ( value === "false" ) {
      return false;
    } else {
      var individ = new veda.IndividualModel(value);
      if ( individ.isSync() && !individ.isNew() ) { return individ; }
    }
    return value || null;
  }

  veda.on("started", function () {
    var layout;
    if (veda.user.hasValue("v-s:origin", "ExternalUser")) {
      layout = (new veda.IndividualModel("cfg:LayoutExternal"))["rdf:value"][0];
    } else {
      layout = (new veda.IndividualModel("cfg:Layout"))["rdf:value"][0];
    }
    layout.present("#app");
    riot.route(location.hash);
  });

  // Listen to client notifications
  veda.on("started", function () {
    var updateService = new veda.UpdateService();
    var clientNotification = new veda.IndividualModel("cfg:ClientNotification");
    updateService.subscribe(clientNotification.id);
    clientNotification.on("afterReset", checkNotification);
    checkNotification();
    function checkNotification() {
      var browserNotificationList;
      try {
        browserNotificationList = JSON.parse(localStorage.clientNotification);
      } catch (error) {
        browserNotificationList = [];
      }
      var serverNotificationList = clientNotification["rdf:value"].map(function (item) { return item.id; });
      if ( !veda.Util.areEqual(browserNotificationList, serverNotificationList) && serverNotificationList.length ) {
        for (var i = 0, exit = false, notification, notification_uri; (notification_uri = serverNotificationList[i]) && !exit; i++) {
          if (browserNotificationList.indexOf(notification_uri) >= 0) { continue; }
          notification = new veda.IndividualModel(notification_uri);
          if ( notification.hasValue("v-s:newsAudience") ) {
            notification.properties["v-s:newsAudience"].forEach(function (audience) {
              audience = audience.data;
              if ( veda.user.isMemberOf(audience) ) {
                veda.Util.confirm(notification).then(function (confirmed) {
                  if ( confirmed ) {
                    localStorage.clientNotification = JSON.stringify(serverNotificationList);
                    if (notification.hasValue("v-s:script")) {
                      var script = notification["v-s:script"][0].toString();
                      eval(script);
                    }
                  }
                });
                exit = true;
              }
            });
          }
        }
      } else {
        localStorage.clientNotification = JSON.stringify(serverNotificationList);
      }
    }
  });

  // Load ontology
  veda.init();

});
