// Veda application Presenter

veda.Module(function (veda) { "use strict";

  // Route to resource ttl view on Ctrl + Alt + Click
  $("body").on("click", "[resource][typeof], [about]", function (e) {
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
  var appLoadIndicator = $("#app-load-indicator");
  veda.on("init:progress", function (progress) {
    if (progress !== 100) {
      appLoadIndicator.removeClass("hidden");
    } else {
      appLoadIndicator.addClass("hidden");
    }
  });

  // Triggered in veda.start()
  veda.one("started", function () {
    var welcome;
    if (veda.user.hasValue("v-s:origin", "External User")) {
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
    if (veda.user.hasValue("v-s:origin", "External User")) {
      layout = (new veda.IndividualModel("cfg:LayoutExternal"))["rdf:value"][0];
    } else {
      layout = (new veda.IndividualModel("cfg:Layout"))["rdf:value"][0];
    }
    layout.present("#app");
    riot.route(location.hash);
  });

  // Load ontology
  veda.init();

});
