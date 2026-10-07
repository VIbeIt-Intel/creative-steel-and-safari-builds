(function () {
  var STUDIO_API = /localhost|127\.0\.0\.1/.test(location.hostname)
    ? "http://127.0.0.1:8787"
    : "https://creative-steel-studio.vibeit-intel.workers.dev";

  function esc(value) {
    return String(value || "").replace(/[&<>"']/g, function (ch) {
      return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[ch];
    });
  }

  function kindsLine(count) {
    var names = ["", "One", "Two", "Three", "Four", "Five", "Six", "Seven", "Eight", "Nine", "Ten"];
    if (count === 1) return "One kind of steelwork. Open it to see that work.";
    var word = count < names.length ? names[count] : String(count);
    return word + " kinds of steelwork. Open a category to see that work only.";
  }

  function wa(title) {
    return "https://wa.me/27787031151?text=" + encodeURIComponent("Hi, I want to ask about the " + title);
  }

  function render(data) {
    var products = data.products || [];
    if (!products.length) return;
    var root = document.querySelector("[data-rotator]");
    var slides = products.map(function (product, index) {
      return (
        "<figure class=\"slide" + (index === 0 ? " is-on" : "") + "\">" +
        "<img src=\"" + esc(product.cover) + "\" alt=\"" + esc(product.coverAlt || product.name) + "\"" + (index === 0 ? " fetchpriority=\"high\"" : " decoding=\"async\"") + ">" +
        "<figcaption>" + esc(product.wheelLabel || product.name) + "</figcaption></figure>"
      );
    }).join("");
    var dots = products.map(function (product, index) {
      return "<button class=\"dot" + (index === 0 ? " is-on" : "") + "\" type=\"button\" aria-label=\"" + esc(product.wheelLabel || product.name) + "\"></button>";
    }).join("");
    root.innerHTML =
      slides +
      "<button class=\"rot-prev\" type=\"button\" aria-label=\"Previous slide\">‹</button>" +
      "<button class=\"rot-next\" type=\"button\" aria-label=\"Next slide\">›</button>" +
      "<div class=\"dots\" role=\"tablist\" aria-label=\"Product photos\">" + dots + "</div>";

    var makes = document.querySelector(".makes");
    makes.innerHTML = products.map(function (product) {
      return (
        "<li><a class=\"make-card\" href=\"#" + esc(product.id) + "\">" +
        "<img src=\"" + esc(product.cover) + "\" alt=\"" + esc(product.coverAlt || product.name) + "\" loading=\"lazy\" decoding=\"async\">" +
        "<h3>" + esc(product.name) + "</h3><p>" + esc(product.blurb) + "</p></a></li>"
      );
    }).join("");
    var lead = document.getElementById("makes-lead");
    if (lead) lead.textContent = kindsLine(products.length);

    var recent = [];
    products.forEach(function (product) {
      product.builds.forEach(function (build) {
        if (build.recent && build.photos.length) recent.push(Object.assign({ productId: product.id }, build));
      });
    });
    recent.sort(function (a, b) { return a.recentSort - b.recentSort; });
    var workshopBox = document.querySelector(".workshop-photos");
    if (workshopBox && Array.isArray(data.workshop)) {
      workshopBox.innerHTML = data.workshop.map(function (photo) {
        return "<img src=\"" + esc(photo.sm) + "\" alt=\"" + esc(photo.alt || "Workshop") + "\" loading=\"lazy\" decoding=\"async\">";
      }).join("");
    }

    document.querySelector(".recent").innerHTML = recent.map(function (build) {
      var photo = build.photos[0];
      var frames = build.photos.map(function (item) { return item.sm; }).join("|");
      return (
        "<a href=\"#" + esc(build.id) + "\" data-frames=\"" + esc(frames) + "\" data-at=\"0\">" +
        "<span class=\"recent-frame\"><img src=\"" + esc(photo.sm) + "\" alt=\"" + esc(build.title) + "\" loading=\"lazy\" decoding=\"async\"><img class=\"incoming\" alt=\"\"></span>" +
        "<span>" + esc(build.title) + "</span></a>"
      );
    }).join("");
    cycleRecent();

    document.querySelectorAll(".cat-page").forEach(function (page) { page.remove(); });
    var main = document.querySelector("main");
    products.forEach(function (product) {
      var jobs = product.builds.map(function (build) {
        var photos = build.photos.map(function (photo) {
          return "<button class=\"shot\" type=\"button\" data-full=\"" + esc(photo.full) + "\"><img src=\"" + esc(photo.sm) + "\" loading=\"lazy\" decoding=\"async\" alt=\"" + esc(photo.alt || build.title) + "\"></button>";
        }).join("");
        return (
          "<article class=\"job\" id=\"" + esc(build.id) + "\">" +
          "<h3>" + esc(build.title) + "</h3>" +
          "<p class=\"job-note\">" + esc(build.note) + "</p>" +
          "<div class=\"job-photos\">" + photos + "</div>" +
          "<a class=\"cta wa-build\" href=\"" + wa(build.title) + "\">WhatsApp this build</a></article>"
        );
      }).join("");
      var section = document.createElement("section");
      section.id = product.id;
      section.className = "cat-page";
      section.setAttribute("data-cat-page", product.id);
      section.innerHTML =
        "<a class=\"back\" href=\"#top\">← Home</a>" +
        "<h2>" + esc(product.name) + "</h2>" +
        "<p class=\"cat-lead\">" + esc(product.blurb) + "</p>" +
        jobs;
      main.appendChild(section);
    });

    if (window.CSBindRotator) window.CSBindRotator();
    if (window.CSRoute) window.CSRoute();
  }

  function cycleRecent() {
    if (window.CSRecentStop) window.CSRecentStop();
    var cards = Array.prototype.filter.call(document.querySelectorAll(".recent a[data-frames]"), function (card) {
      return card.getAttribute("data-frames").split("|").length > 1;
    });
    if (!cards.length || window.matchMedia("(prefers-reduced-motion: reduce)").matches) return;
    var handles = [];
    var watch = null;
    function step(card) {
      if (document.hidden || !card.isConnected) return;
      var frames = card.getAttribute("data-frames").split("|");
      var at = Number(card.getAttribute("data-at") || "0");
      var next = (at + 1) % frames.length;
      var base = card.querySelector(".recent-frame img");
      var incoming = card.querySelector(".incoming");
      if (!base || !incoming || incoming.classList.contains("show")) return;
      var preload = new Image();
      preload.decoding = "async";
      preload.onload = function () {
        if (!card.isConnected) return;
        incoming.src = frames[next];
        window.requestAnimationFrame(function () {
          window.requestAnimationFrame(function () {
            if (!card.isConnected) return;
            incoming.classList.add("show");
          });
        });
        var finish = function () {
          incoming.removeEventListener("transitionend", finish);
          if (!card.isConnected) return;
          base.src = frames[next];
          card.setAttribute("data-at", String(next));
          incoming.style.transition = "none";
          incoming.classList.remove("show");
          void incoming.offsetWidth;
          incoming.style.transition = "";
        };
        incoming.addEventListener("transitionend", finish);
      };
      preload.src = frames[next];
    }
    function start() {
      if (handles.length) return;
      cards.forEach(function (card, index) {
        handles.push(window.setTimeout(function () {
          step(card);
          handles.push(window.setInterval(function () { step(card); }, 4000));
        }, 500 + index * 320));
      });
    }
    var box = document.querySelector(".recent");
    if (box && "IntersectionObserver" in window) {
      watch = new IntersectionObserver(function (entries) {
        if (!entries.some(function (entry) { return entry.isIntersecting; })) return;
        start();
        if (watch) watch.disconnect();
      }, { rootMargin: "240px" });
      watch.observe(box);
    } else {
      start();
    }
    window.CSRecentStop = function () {
      handles.forEach(function (id) {
        window.clearTimeout(id);
        window.clearInterval(id);
      });
      handles = [];
      if (watch) watch.disconnect();
      watch = null;
    };
  }

  fetch(STUDIO_API + "/api/site", { cache: "no-store" })
    .then(function (res) { return res.ok ? res.json() : null; })
    .then(function (data) { if (data && data.products) render(data); })
    .catch(function () {});
})();
