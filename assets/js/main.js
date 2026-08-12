/* CureComp Technology — site behaviour */
(function () {
  "use strict";

  /* ---- Theme ---- */
  var root = document.documentElement;
  var stored = null;
  try { stored = localStorage.getItem("cc-theme"); } catch (e) {}
  if (stored) root.setAttribute("data-theme", stored);

  document.addEventListener("click", function (e) {
    var t = e.target.closest("[data-theme-toggle]");
    if (!t) return;
    var next = root.getAttribute("data-theme") === "light" ? "dark" : "light";
    root.setAttribute("data-theme", next);
    try { localStorage.setItem("cc-theme", next); } catch (err) {}
  });

  /* ---- Mobile nav ---- */
  var burger = document.querySelector("[data-burger]");
  var nav = document.getElementById("nav");
  if (burger && nav) {
    burger.addEventListener("click", function () {
      var open = nav.classList.toggle("is-open");
      burger.setAttribute("aria-expanded", String(open));
      document.body.style.overflow = open ? "hidden" : "";
    });
    nav.addEventListener("click", function (e) {
      if (e.target.tagName !== "A") return;
      nav.classList.remove("is-open");
      burger.setAttribute("aria-expanded", "false");
      document.body.style.overflow = "";
    });
    window.addEventListener("keydown", function (e) {
      if (e.key === "Escape" && nav.classList.contains("is-open")) burger.click();
    });
  }

  /* ---- Sticky header shadow ---- */
  var hdr = document.querySelector(".hdr");
  if (hdr) {
    var onScroll = function () { hdr.classList.toggle("is-stuck", window.scrollY > 8); };
    onScroll();
    window.addEventListener("scroll", onScroll, { passive: true });
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

    /* Failsafe: if the observer never delivers (non-compositing renderer,
       prerender, odd webview), show everything rather than leave it blank. */
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
     The site is static, so the form composes a pre-filled message and
     hands it to WhatsApp or the visitor's mail client. Nothing is stored. */
  var form = document.querySelector("[data-enquiry]");
  if (form) {
    var compose = function () {
      var d = new FormData(form);
      var get = function (k) { return (d.get(k) || "").toString().trim(); };
      var lines = [
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
      ];
      return lines.join("\n");
    };

    var validate = function () {
      if (!form.reportValidity()) return false;
      return true;
    };

    form.addEventListener("submit", function (e) { e.preventDefault(); });

    var waBtn = form.querySelector("[data-send-wa]");
    if (waBtn) waBtn.addEventListener("click", function () {
      if (!validate()) return;
      window.open("https://wa.me/60178774376?text=" + encodeURIComponent(compose()), "_blank", "noopener");
    });

    var mailBtn = form.querySelector("[data-send-mail]");
    if (mailBtn) mailBtn.addEventListener("click", function () {
      if (!validate()) return;
      var subject = "Enquiry: " + ((new FormData(form)).get("topic") || "General");
      window.location.href = "mailto:curecomp@outlook.com?subject=" +
        encodeURIComponent(subject) + "&body=" + encodeURIComponent(compose());
    });
  }
})();
