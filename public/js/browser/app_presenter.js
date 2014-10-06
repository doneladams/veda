// Veda application Presenter

Veda(function AppPresenter(veda) { "use strict";

/*	$(function () {
		localize($("nav"), veda.user.language);
	});*/

	// Router function
	riot.route( function (hash) {
		var hash_tokens = hash.slice(2).split("/");
		var page = hash_tokens[0];
		var params = hash_tokens.slice(1);
		
		// Important: avoid routing if not started yet!
		if (veda.started) {
			if (page != "") {
				$("#menu > li").removeClass("active");
				$("#menu > li#" + page).addClass("active");
				veda.load(page, params);
			} else {
				$("#menu > li").removeClass("active");
				$("#main").html( $("#wellcome-template").html() );
			}
		}
	});
	
	veda.on("language:changed", function () {
		localize($("nav"), Object.keys(veda.user.language));
		// Refresh 'page'
		riot.route(location.hash, true);
	});
	
	// Listen to a link click and call router
	$("body").on("click", "[href^='#/']", function (e) {
		e.preventDefault();
		var link = $(this);
		return riot.route($(this).attr("href"));
	});
	
	// Prevent empty links routing
	$("body").on("click", "[href='']", function (e) {
		e.preventDefault();
	});

	// Toggle tracing
	$("#set-trace").on("click", function (e) {
		var $el = $(this);
		if ($el.hasClass("active")) { 
			set_trace(0, false);
			$el.removeClass("active");
			return;
		}
		set_trace(0, true);
		$el.addClass("active");
	});

	// Listen to logout click
	$("#logout").on("click", function (e) {
		$("#current-user").html("");
		veda.quit();
		location.reload();
	});

	// Listen to user loaded event
	veda.on("app:started", function (user_uri, ticket, end_time) {
		setCookie("user_uri", user_uri, { path: "/", expires: new Date(parseInt(end_time)) });
		setCookie("ticket", ticket, { path: "/", expires: new Date(parseInt(end_time)) });
		setCookie("end_time", end_time, { path: "/", expires: new Date(parseInt(end_time)) });
		setTimeout( function () {
			riot.route(location.hash, true);
		}, 0);
	});

	// Listen to quit && authentication failure events
	veda.on("auth:quit", function () {
		delCookie("user_uri");
		delCookie("ticket");
		delCookie("end_time");
		
		//Show login form
		var template = $("#login-template").html();
		var container = $("#main");
		container.html(template);

		$("#submit", container).on("click", function (e) {
			e.preventDefault();
			veda.authenticate( $("#login", container).val(), Sha256.hash( $("#password", container).val() ) );
		});
	});

	if (!getCookie("ticket") || !getCookie("user_uri") || !getCookie("end_time") || !is_ticket_valid(getCookie("ticket"))) return veda.trigger("auth:quit");
	veda.ticket = getCookie("ticket");
	veda.user_uri = getCookie("user_uri");
	veda.end_time = getCookie("end_time");
	veda.trigger("auth:success", veda.user_uri, veda.ticket, veda.end_time);
		
});
