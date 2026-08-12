/* CureComp Technology — site behaviour
	Bootstrap handles the navbar collapse and accordions; this covers the rest. */
(function () {
	"use strict";

	/* ---- Sticky navbar border ---- */
	var nav = document.querySelector(".navbar");
	if (nav) {
		var onScroll = function () { nav.classList.toggle("is-stuck", window.scrollY > 8); };
		onScroll();
		window.addEventListener("scroll", onScroll, { passive: true });
	}

	/* ---- Close the mobile menu after tapping a link ---- */
	var collapseEl = document.getElementById("ccNav");
	if (collapseEl && window.bootstrap) {
		collapseEl.addEventListener("click", function (e) {
			if (e.target.tagName !== "A" || !collapseEl.classList.contains("show")) return;
			bootstrap.Collapse.getOrCreateInstance(collapseEl).hide();
		});
	}

	/* ---- Reveal on scroll ---- */
	var revealables = document.querySelectorAll(".rv");
	var revealAll = function () {
		revealables.forEach(function (el) { el.classList.add("in"); });
	};

	if (!("IntersectionObserver" in window) || matchMedia("(prefers-reduced-motion: reduce)").matches) {
		revealAll();
	} else {
		var io = new IntersectionObserver(function (entries) {
			entries.forEach(function (entry, i) {
				if (!entry.isIntersecting) return;
				var el = entry.target;
				var delay = parseInt(el.getAttribute("data-delay") || (i * 60), 10);
				setTimeout(function () { el.classList.add("in"); }, delay);
				io.unobserve(el);
			});
		}, { rootMargin: "0px 0px -8% 0px", threshold: 0.08 });
		revealables.forEach(function (el) { io.observe(el); });

		/* Failsafe: if the observer never delivers (prerender, odd webview),
			show everything rather than leave the page blank. */
		setTimeout(revealAll, 3000);
	}

	/* ---- Animated counters ---- */
	var counters = document.querySelectorAll("[data-count]");
	if (counters.length && "IntersectionObserver" in window) {
		var co = new IntersectionObserver(function (entries) {
			entries.forEach(function (entry) {
				if (!entry.isIntersecting) return;
				var el = entry.target;
				var target = parseFloat(el.getAttribute("data-count"));
				var suffix = el.getAttribute("data-suffix") || "";
				var prefix = el.getAttribute("data-prefix") || "";
				var dur = 1100, t0 = performance.now();
				var tick = function (now) {
					var p = Math.min((now - t0) / dur, 1);
					var eased = 1 - Math.pow(1 - p, 3);
					var val = target % 1 === 0 ? Math.round(target * eased) : (target * eased).toFixed(1);
					el.textContent = prefix + val + suffix;
					if (p < 1) requestAnimationFrame(tick);
				};
				requestAnimationFrame(tick);
				co.unobserve(el);
			});
		}, { threshold: 0.4 });
		counters.forEach(function (el) { co.observe(el); });
	}

	/* ---- Year ---- */
	document.querySelectorAll("[data-year]").forEach(function (el) {
		el.textContent = new Date().getFullYear();
	});

	/* ---- Enquiry form → WhatsApp / e-mail ----
		The site is static, so the form composes a pre-filled message and hands it
		to WhatsApp or the visitor's mail client. Nothing is posted or stored. */
	var form = document.querySelector("[data-enquiry]");
	if (form) {
		/* Preselect the subject from ?topic=<slug> so a CTA elsewhere on the site
			lands the visitor on the right enquiry. Slugs live in each option's
			data-topic attribute; an unknown slug is simply ignored. */
		(function preselectTopic() {
			var select = form.querySelector("#f-topic");
			if (!select || !window.location.search) return;

			var slug = null;
			var pairs = window.location.search.replace(/^\?/, "").split("&");
			for (var i = 0; i < pairs.length; i++) {
				var kv = pairs[i].split("=");
				if (decodeURIComponent(kv[0]) === "topic") {
					slug = decodeURIComponent((kv[1] || "").replace(/\+/g, " ")).trim().toLowerCase();
					break;
				}
			}
			if (!slug) return;

			for (var j = 0; j < select.options.length; j++) {
				if (select.options[j].getAttribute("data-topic") === slug) {
					select.selectedIndex = j;
					select.dispatchEvent(new Event("change", { bubbles: true }));
					return;
				}
			}
		})();

		var compose = function () {
			var d = new FormData(form);
			var get = function (k) { return (d.get(k) || "").toString().trim(); };
			return [
				"New enquiry from the CureComp website",
				"",
				"Name: " + (get("name") || "-"),
				"Company: " + (get("company") || "-"),
				"Phone: " + (get("phone") || "-"),
				"Email: " + (get("email") || "-"),
				"Interested in: " + (get("topic") || "-"),
				"",
				"Message:",
				get("message") || "-"
			].join("\n");
		};

		form.addEventListener("submit", function (e) { e.preventDefault(); });

		var waBtn = form.querySelector("[data-send-wa]");
		if (waBtn) waBtn.addEventListener("click", function () {
			if (!form.reportValidity()) return;
			window.open("https://wa.me/60178774376?text=" + encodeURIComponent(compose()), "_blank", "noopener");
		});

		var mailBtn = form.querySelector("[data-send-mail]");
		if (mailBtn) mailBtn.addEventListener("click", function () {
			if (!form.reportValidity()) return;
			var subject = "Enquiry: " + ((new FormData(form)).get("topic") || "General");
			window.location.href = "mailto:curecomp@outlook.com?subject=" +
				encodeURIComponent(subject) + "&body=" + encodeURIComponent(compose());
		});
	}
})();
