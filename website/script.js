// ClubCaddy - marketing site interactions
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

  // Per-member pricing calculator
  var memberInput = document.getElementById("memberCount");
  var memberPriceEl = document.getElementById("memberPrice");
  var memberDetailEl = document.getElementById("memberDetail");
  var decrBtn = document.querySelector(".stepper-decr");
  var incrBtn = document.querySelector(".stepper-incr");

  function updateMemberPrice() {
    if (!memberInput || !memberPriceEl || !memberDetailEl) return;
    var count = parseInt(memberInput.value, 10) || 0;
    if (count < 1) count = 1;
    var raw = count * 3.50;
    var price = Math.max(350, Math.min(1200, raw));
    var formatted = price.toLocaleString("en-IE", { style: "currency", currency: "EUR", maximumFractionDigits: 0 });
    memberPriceEl.innerHTML = formatted.replace("EUR", "€") + '<span class="member-result-period">/yr</span>';
    if (price === 350) {
      memberDetailEl.textContent = "€3.50 × " + count + " members — minimum applies";
    } else if (price === 1200) {
      memberDetailEl.textContent = "€3.50 × " + count + " members — cap applies";
    } else {
      memberDetailEl.textContent = "€3.50 × " + count + " members";
    }
  }

  function changeMemberCount(delta) {
    if (!memberInput) return;
    var count = parseInt(memberInput.value, 10) || 0;
    count = Math.max(1, Math.min(10000, count + delta));
    memberInput.value = count;
    updateMemberPrice();
  }

  if (memberInput) {
    memberInput.addEventListener("input", updateMemberPrice);
    updateMemberPrice();
  }
  if (decrBtn) {
    decrBtn.addEventListener("click", function () { changeMemberCount(-1); });
  }
  if (incrBtn) {
    incrBtn.addEventListener("click", function () { changeMemberCount(1); });
  }
})();