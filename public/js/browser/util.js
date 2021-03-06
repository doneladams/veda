"use strict";

// Veda browser utility functions

veda.Module(function (veda) { "use strict";

  veda.Util = veda.Util || {};

  veda.Util.decimalDatetimeReviver = function (key, value) {
    return key === "data" && this.type === "Datetime" ? new Date(value) : key === "data" && this.type === "Decimal" ? parseFloat(value) : value ;
  };

  veda.Util.mergeMutualChanges = function (high, low, base) {
    var key, merged = {};
    for (key in base) {
      merged[key] = base[key];
    }
    var highBaseDiff = veda.Util.diff(high, base);
    var lowBaseDiff = veda.Util.diff(low, base);
    var highLowDiff = veda.Util.diff(high, low);
    var lowHighDiff = veda.Util.diff(low, high);
    for (key in lowBaseDiff.missing) {
      delete merged[key];
    }
    for (key in highBaseDiff.missing) {
      delete merged[key];
    }
    for (key in lowBaseDiff.added) {
      merged[key] = lowBaseDiff.added[key];
    }
    for (key in highBaseDiff.added) {
      merged[key] = highBaseDiff.added[key];
    }
    for (key in lowBaseDiff.differ) {
      merged[key] = lowBaseDiff.differ[key];
    }
    for (key in highBaseDiff.diff) {
      merged[key] = highBaseDiff.differ[key];
    }
    return {
      merged: merged,
      conflicts: {
        high: highLowDiff.differ,
        low: lowHighDiff.differ
      }
    };
  };

  veda.Util.diff = function (changed, base) {
    var delta = {
      added: {},
      missing: {},
      differ: {}
    }
    var key, values, value, length, i, hasValue;
    for (key in base) {
      if ( !(key in changed) ) {
        delta.missing[key] = base[key];
      } else {
        if (key === "@") {
          if (changed[key] !== base[key]) {
            delta.differ[key] = changed[key];
          }
          continue;
        }
        values = base[key];
        length = values.length;
        hasValue = true;
        for (i = 0; i < length && hasValue; i++) {
          value = values[i];
          hasValue = hasValue && veda.Util.hasValue(changed, key, value);
        }
        if ( !hasValue ) {
          delta.differ[key] = changed[key];
        }
      }
    }
    for (key in changed) {
      if ( !(key in base) ) {
        delta.added[key] = changed[key];
      }
    }
    return delta;
  };

  // Уcтанавливает cookie
  // name - Название cookie
  // value - Значение cookie (строка)
  // props - Объект с дополнительными свойствами для установки cookie:
  //   expires - Время истечения cookie. Интерпретируется по-разному, в зависимости от типа:
  //     Если число - количество миллисекунд до истечения.
  //     Если объект типа Date - точная дата истечения.
  //     Если expires в прошлом, то cookie будет удалено.
  //     Если expires отсутствует или равно 0, то cookie будет установлено как сессионное и исчезнет при закрытии браузера.
  //   path - Путь для cookie.
  //   domain - Домен для cookie.
  //   secure - Пересылать cookie только по защищенному соединению.

  veda.Util.setCookie = function (name, value, props) {
    props = props || {};
    var exp = props.expires;
    if (typeof exp === "number" && exp) {
      var d = new Date();
      d.setTime(d.getTime() + exp);
      exp = props.expires = d;
    }
    if (exp && exp.toUTCString) { props.expires = exp.toUTCString(); }
    value = encodeURIComponent(value);
    var updatedCookie = name + "=" + value;
    for(var propName in props) {
      updatedCookie += "; " + propName;
      var propValue = props[propName];
      if (propValue !== true) { updatedCookie += "=" + propValue; }
    }
    document.cookie = updatedCookie;
  };

  veda.Util.delCookie = function (name) {
    veda.Util.setCookie(name, null, { expires: -1 });
  };

  // Escape function for css (jQuery) selectors
  veda.Util.escape4$ = function (str) {
    if (str) return str.replace(/([ #;?%&,.+*~\':"!^$[\]()=>|\/@])/g,'\\$1');
    return str;
  };

  veda.Util.toTTL = function (individualList, callback) {
    var ontologies = query(veda.ticket, "'rdf:type'=='owl:Ontology'").result,
        all_prefixes = {},
        prefixes = {},
        triples = [],
        writer = N3.Writer();

    all_prefixes["dc"] = "http://purl.org/dc/elements/1.1/";
    all_prefixes["grddl"] = "http://www.w3.org/2003/g/data-view#";
    ontologies.map( function (ontology_uri) {
      var ontology = new veda.IndividualModel(ontology_uri);
      var prefix = ontology_uri.slice(0, -1);
      if (ontology.hasValue("v-s:fullUrl")) {
        all_prefixes[prefix] = ontology["v-s:fullUrl"][0].toString();
      }
    });

    function prefixer(uri) {
      try {
        var colonIndex = uri.indexOf(":"),
            prefix = uri.substring(0, colonIndex);
        if ( !prefixes[prefix] ) {
          prefixes[prefix] = all_prefixes[prefix];
        }
        if ( colonIndex === uri.length-1 ) {
          return prefixes[prefix];
        } else {
          return N3.Util.expandPrefixedName(uri, prefixes);
        }
      } catch (error) {
        var notify = veda.Notify ? new veda.Notify() : function () {};
        notify("danger", error);
        return uri;
      }
    }

    individualList.each(function (individual) {
      var subject = prefixer(individual.id);
      // Type first
      individual.properties["rdf:type"].map(function (value) {
        var type_triple = {};
        type_triple.subject = subject;
        type_triple.predicate = prefixer("rdf:type");
        type_triple.object = prefixer(value.data);
        triples.push(type_triple);
      });
      // Other properties
      Object.getOwnPropertyNames(individual.properties).sort().map(function (property_uri) {
        if (property_uri === "@" || property_uri === "rdf:type") { return; }
        individual.properties[property_uri].map(function (item) {
          var triple = {};
          triple.subject = subject;
          triple.predicate = prefixer(property_uri);
          var value = item.data,
              type = item.type,
              lang = item.lang;
          switch (type) {
            case 4:
            case "Integer":
              triple.object = '"' + value + '"^^' + prefixer("xsd:integer");
              break;
            case 32:
            case "Decimal":
              triple.object = '"' + value + '"^^' + prefixer("xsd:decimal");
              break;
            case 64:
            case "Boolean":
              triple.object = '"' + value + '"^^' + prefixer("xsd:boolean");
              break;
            case 2:
            case "String":
              triple.object = lang && lang !== "NONE" ? '"' + value + '"@' + lang.toLowerCase() : '"' + value + '"^^' + prefixer("xsd:string");
              break;
            case 8:
            case "Datetime":
              triple.object = '"' + ( value instanceof Date ? value.toISOString() : value ) + '"^^' + prefixer("xsd:dateTime");
              break;
            case 1:
            case "Uri":
              triple.object = prefixer(value);
              break;
          }
          triples.push(triple);
        });
      });
    });
    writer.addPrefixes(prefixes);
    writer.addTriples(triples);
    writer.end(callback);
  };

  veda.Util.exportTTL = function (individualList) {
    veda.Util.toTTL(individualList, function (error, result) {
      var blob = new Blob([result], {type: "text/plain;charset=utf-8"});
      saveAs(blob, "exported_graph.ttl");
    });
  };

  /**
   * Event `createReport` handler:
   *  - Find available reports or use report specified by `reportId` parameter.
   *  - Let user to choice report (if more then one founded)
   *  - Redirect to report
   */
  veda.Util.createReport = function (report, params) {
    if (typeof report === "string" || report instanceof String) {
      report = new veda.IndividualModel(report);
    }
    var jasperServer = new veda.IndividualModel('cfg:jasperServerAddress');
    var jasperServerAddress = jasperServer['rdf:value'][0];

    var form = document.createElement("form");
    form.setAttribute("method", "post");
    form.setAttribute("action", jasperServerAddress + "flow.html?_flowId=viewReportFlow&j_username=joeuser&j_password=joeuser&reportUnit=" + encodeURIComponent(report["v-s:reportPath"][0]) + "&output=" + encodeURIComponent(report["v-s:reportFormat"][0]) + "&documentId=" + encodeURIComponent(params.id) + "&ticket=" + veda.ticket);
    form.setAttribute("target", "Report");

    Object.getOwnPropertyNames(params.properties).forEach(function (key) {
      if ( key !== "@" && params.hasValue(key) ) {
        var hiddenField = document.createElement("input");
        hiddenField.setAttribute("type", "hidden");
        hiddenField.setAttribute("name", key.replace(":", "_"));
        var value = params.get(key).map(function (item) {
          return item instanceof veda.IndividualModel ? item.id :
                 item instanceof Date ? item.toISOString() :
                 item;
        }).join(",");
        hiddenField.setAttribute("value", value);
        form.appendChild(hiddenField);
      }
    });
    // Set client timezone parameter
    var tz = (new Date()).getTimezoneOffset();
    var tzField = document.createElement("input");
    tzField.setAttribute("type", "hidden");
    tzField.setAttribute("name", "timezone");
    tzField.setAttribute("value", tz);
    form.appendChild(tzField);
    document.body.appendChild(form);
    window.open("", "Report");
    form.submit();
  };

  veda.Util.transform = function (individual, template, transformId) {
    var startForm = veda.Util.buildStartFormByTransformation(individual, new veda.IndividualModel(transformId));
    riot.route("#/" + startForm.id + "///edit");
  };

  /**
   * Event `send` handler:
   *  - Find transformation to start form or use transformation specified by `transformId` parameter
   *  - Apply transformation and redirect to start form.
   */
  veda.Util.send = function (individual, template, transformId, modal, startFormId) {
    if ( transformId ) {
      template.trigger("save");
      var transform = new veda.IndividualModel(transformId);
      var startForm = veda.Util.buildStartFormByTransformation(individual, transform);
      veda.Util.showModal(startForm, startFormId, "edit");
    } else {
      individual["v-wf:hasStatusWorkflow"] = [ new veda.IndividualModel("v-wf:ToBeSent") ];
      template.trigger("save");
      template.closest(".modal").modal("hide").remove();
      var notify = veda.Notify ? new veda.Notify() : function () {};
      notify("success", {name: "Успешно отправлено / Successfully sent"});
    }
  };

  /**
   * Event `showRights` handler:
   *  - Find available reports
   *  - Let user to choice report (if more then one founded)
   *  - Redirect to report
   */
  veda.Util.showRights = function (individual) {
    var modalTmpl = $("#individual-modal-template").html();
    var modal = $(modalTmpl);
    var modalBody = $(".modal-body", modal);
    modal.one("remove", function (e) {
      modal.modal("hide");
    });
    modal.modal();
    $("#main").append(modal);

    var rights = individual['rights'];
    var holder = $("<div>");
    rights.present(holder, "v-ui:PermissionStatementInlineTemplate");
    holder.appendTo(modalBody);

    var origin = individual['rightsOrigin'];
    origin.forEach(function (rightRecord) {
      var holder = $("<div>");
      rightRecord.present(holder, "v-ui:PermissionStatementInlineTemplate");
      holder.appendTo(modalBody);
    });
  };

  veda.Util.showModal = function (individual, template, mode) {
    var modal = $( $("#notification-modal-template").html() );
    modal.modal();
    $("body").append(modal);
    var container = $(".modal-body", modal);
    individual.present(container, template, mode);
    $(".action#cancel", modal).click(function () {
      modal.modal("hide");
    });
    modal.on("hidden.bs.modal", function () {
      modal.remove();
    });
    return modal;
  };

  veda.Util.showSmallModal = function (individual, template, mode) {
    var modal = $( $("#minimal-modal-template").html() );
    modal.modal();
    $("body").append(modal);
    var container = $(".modal-body", modal);
    individual.present(container, template, mode);
    $(".action#cancel", modal).click(function () {
      modal.modal("hide");
    });
    modal.on("hidden.bs.modal", function () {
      modal.remove();
    });
    return modal;
  };

  veda.Util.confirm = function (individual, template, mode) {
    var modal = $( $("#confirm-modal-template").html() );
    modal.modal();
    $("body").append(modal);
    var container = $(".modal-body", modal);
    individual.present(container, template, mode);
    modal.on("hidden.bs.modal", function () {
      modal.remove();
    });
    return new Promise(function (resolve, reject) {
      $(".modal-footer > .ok", modal).click(function () { resolve(true); });
      $(".modal-footer > .cancel", modal).click(function () { resolve(false); });
    });
  };
});
