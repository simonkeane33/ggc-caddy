// ClubCaddy — marketing site interactions
(function () {
  "use strict";

  // Year in footer
  var yearEl = document.getElementById("year");
  if (yearEl) yearEl.textContent = new Date().getFullYear();

  // Sticky nav shadow on scroll
  var nav = document.getElementById("nav");
  var onScroll = function () {
    if (!nav) return;
    nav.classList.toggle("scrolled", window.scrollY > 8);
  };
  window.addEventListener("scroll", onScroll, { passive: true });
  onScroll();

  // Mobile menu
  var toggle = document.getElementById("navToggle");
  var menu = document.getElementById("mobileMenu");
  if (toggle && menu) {
    toggle.addEventListener("click", function () {
      var open = toggle.getAttribute("aria-expanded") === "true";
      toggle.setAttribute("aria-expanded", String(!open));
      if (open) { menu.hidden = true; }
      else { menu.hidden = false; }
    });
    // Close after tapping a link
    menu.querySelectorAll("a").forEach(function (a) {
      a.addEventListener("click", function () {
        menu.hidden = true;
        toggle.setAttribute("aria-expanded", "false");
      });
    });
  }

  // Pricing billing toggle (annual / monthly)
  var billingButtons = document.querySelectorAll(".billing-btn");
  var amounts = document.querySelectorAll(".price-amount");
  var periods = document.querySelectorAll(".price-period");
  var notes = document.querySelectorAll(".price-note");

  function setBilling(mode) {
    billingButtons.forEach(function (btn) {
      var active = btn.dataset.billing === mode;
      btn.classList.toggle("is-active", active);
      btn.setAttribute("aria-selected", String(active));
    });
    amounts.forEach(function (el) {
      el.textContent = el.dataset[mode === "annual" ? "annual" : "monthly"];
    });
    periods.forEach(function (el) {
      el.textContent = el.dataset[mode === "annual" ? "annual" : "monthly"];
    });
    notes.forEach(function (el) {
      el.textContent = el.dataset[mode === "annual" ? "annual" : "monthly"];
    });
  }

  billingButtons.forEach(function (btn) {
    btn.addEventListener("click", function () {
      setBilling(btn.dataset.billing);
    });
  });
})();