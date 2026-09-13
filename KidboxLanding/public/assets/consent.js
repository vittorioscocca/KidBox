/*
 * Consenso per statistiche (Google Analytics 4) e pubblicità (Meta Pixel)
 * sulla landing.
 *
 * Niente parte finché il visitatore non ha scelto: il default è «non deciso»,
 * che equivale a spento — nessuno script di Google o di Meta caricato.
 * Le due finalità hanno una chiave ciascuna in localStorage:
 *   kidbox:analyticsConsent  → GA4. È la stessa chiave del banner di /join,
 *                              sullo stesso dominio e con lo stesso significato
 *                              (statistiche), quindi le due scelte coincidono.
 *   kidbox:marketingConsent  → Meta Pixel.
 * Il banner compare finché una delle due non è decisa. Tre risposte di pari
 * peso visivo — Rifiuta, Solo statistiche, Accetta tutto — come nel banner
 * della web app: un «rifiuta» sbiadito accanto a un «accetta» colorato non è
 * una scelta.
 *
 * GA4 è la stessa proprietà della web app (G-0PG65CW2VF), con il linker verso
 * app.kidboxapp.com: chi arriva dalla landing e si registra resta una sessione
 * sola, se ha acconsentito su entrambi i siti. I segnali pubblicitari di Google
 * restano negati (Consent Mode): GA qui misura, non profila.
 *
 * Eventi: page_view automatico, `store_click` sui link ad App Store, Google
 * Play e web app (store: ios | android | web).
 *
 * Uso: <script src="/assets/consent.js" defer></script>
 *   data-no-banner  → niente banner (pagine che reindirizzano subito, come
 *                     /scarica): parte solo ciò a cui si è già detto sì.
 * Qualunque elemento con `data-consent-open` riapre il banner, per cambiare idea.
 */
(function () {
  var A_KEY = "kidbox:analyticsConsent";
  var M_KEY = "kidbox:marketingConsent";
  var GA_ID = "G-0PG65CW2VF";
  var PIXEL_ID = "1335685042033994";
  var script = document.currentScript;
  var noBanner = script && script.hasAttribute("data-no-banner");
  var en = (document.documentElement.lang || "it").slice(0, 2) === "en";

  var T = en
    ? {
        title: "Cookies: statistics and advertising",
        body: "We use Google Analytics to count visits and see which pages help, and the Meta Pixel to measure our ads. Both set cookies, and neither runs until you choose.",
        more: "Learn more",
        href: "/privacy-en#cookie",
        none: "Decline",
        stats: "Statistics only",
        all: "Accept all",
      }
    : {
        title: "Cookie: statistiche e pubblicità",
        body: "Usiamo Google Analytics per contare le visite e capire quali pagine servono, e il Meta Pixel per misurare le nostre pubblicità. Entrambi impostano cookie, e nessuno dei due parte finché non scegli.",
        more: "Maggiori informazioni",
        href: "/privacy#cookie",
        none: "Rifiuta",
        stats: "Solo statistiche",
        all: "Accetta tutto",
      };

  function read(key) {
    try {
      var v = localStorage.getItem(key);
      return v === "granted" || v === "denied" ? v : null;
    } catch (e) {
      // Senza storage la scelta non si può ricordare: si resta sul rifiuto,
      // senza un banner che ricomparirebbe a ogni pagina.
      return "denied";
    }
  }

  function write(key, value) {
    try { localStorage.setItem(key, value); } catch (e) {}
  }

  function loadAnalytics() {
    if (window.__kbGaLoaded) return;
    window.__kbGaLoaded = true;
    window.dataLayer = window.dataLayer || [];
    window.gtag = function () { window.dataLayer.push(arguments); };
    window.gtag("consent", "default", {
      analytics_storage: "granted",
      ad_storage: "denied",
      ad_user_data: "denied",
      ad_personalization: "denied",
    });
    var s = document.createElement("script");
    s.async = true;
    s.src = "https://www.googletagmanager.com/gtag/js?id=" + GA_ID;
    document.head.appendChild(s);
    window.gtag("js", new Date());
    window.gtag("config", GA_ID, {
      allow_google_signals: false,
      linker: { domains: ["kidboxapp.com", "app.kidboxapp.com"] },
    });
  }

  function loadPixel() {
    if (window.fbq) return;
    /* eslint-disable */
    !function(f,b,e,v,n,t,s){if(f.fbq)return;n=f.fbq=function(){n.callMethod?
    n.callMethod.apply(n,arguments):n.queue.push(arguments)};if(!f._fbq)f._fbq=n;
    n.push=n;n.loaded=!0;n.version='2.0';n.queue=[];t=b.createElement(e);t.async=!0;
    t.src=v;s=b.getElementsByTagName(e)[0];s.parentNode.insertBefore(t,s)}(window,
    document,'script','https://connect.facebook.net/en_US/fbevents.js');
    /* eslint-enable */
    window.fbq("init", PIXEL_ID);
    window.fbq("track", "PageView");
  }

  /** Toglie i cookie di GA quando il consenso viene ritirato. */
  function clearGaCookies() {
    var host = location.hostname;
    var domains = ["", host, "." + host, "." + host.split(".").slice(-2).join(".")];
    document.cookie.split(";").forEach(function (c) {
      var name = c.split("=")[0].trim();
      if (name === "_ga" || name.indexOf("_ga_") === 0 || name === "_gid") {
        domains.forEach(function (d) {
          document.cookie = name + "=; expires=Thu, 01 Jan 1970 00:00:00 GMT; path=/" + (d ? "; domain=" + d : "");
        });
      }
    });
  }

  function apply() {
    if (read(A_KEY) === "granted") loadAnalytics();
    if (read(M_KEY) === "granted") loadPixel();
  }

  var CSS =
    ".kb-consent{position:fixed;left:16px;right:16px;bottom:16px;z-index:9999;max-width:680px;margin:0 auto;display:flex;flex-wrap:wrap;align-items:center;gap:14px;padding:16px 18px;border:1px solid var(--border,var(--c-border,rgba(0,0,0,.12)));border-radius:16px;background:var(--surface,var(--c-surface,#fff));color:var(--text,var(--c-text,#1c1008));box-shadow:0 8px 30px rgba(0,0,0,.18);font-family:inherit;text-align:left}" +
    ".kb-consent[hidden]{display:none}" +
    ".kb-consent-text{flex:1 1 260px;min-width:220px}" +
    ".kb-consent-text strong{display:block;font-size:.95rem;margin-bottom:4px}" +
    ".kb-consent-text p{font-size:.83rem;line-height:1.45;margin:0;color:var(--muted,var(--c-muted,#6b5d52))}" +
    ".kb-consent-text a{color:inherit;text-decoration:underline}" +
    ".kb-consent-actions{display:flex;flex-wrap:wrap;gap:8px;margin-left:auto}" +
    ".kb-consent-actions button{border:1px solid var(--border,var(--c-border,rgba(0,0,0,.12)));background:transparent;color:inherit;border-radius:10px;padding:9px 16px;font:inherit;font-size:.88rem;font-weight:600;cursor:pointer;white-space:nowrap}" +
    ".kb-consent-actions button:hover{background:var(--border,var(--c-border,rgba(0,0,0,.08)))}";

  var banner = null;

  function choose(analytics, marketing) {
    var hadGa = !!window.__kbGaLoaded, hadPixel = !!window.fbq;
    write(A_KEY, analytics);
    write(M_KEY, marketing);
    if (banner) banner.hidden = true;
    if (analytics === "denied") {
      window["ga-disable-" + GA_ID] = true;
      clearGaCookies();
    }
    // Uno script già caricato non si «spegne» in pagina: se un sì viene
    // ritirato si ricarica, così da qui in avanti non parte più.
    if ((hadGa && analytics === "denied") || (hadPixel && marketing === "denied")) {
      location.reload();
      return;
    }
    apply();
  }

  function open() {
    if (!banner) {
      var style = document.createElement("style");
      style.textContent = CSS;
      document.head.appendChild(style);
      banner = document.createElement("div");
      banner.className = "kb-consent";
      banner.setAttribute("role", "dialog");
      banner.setAttribute("aria-label", T.title);
      banner.innerHTML =
        '<div class="kb-consent-text"><strong></strong><p><span></span> <a></a></p></div>' +
        '<div class="kb-consent-actions">' +
        '<button type="button" data-a="denied" data-m="denied"></button>' +
        '<button type="button" data-a="granted" data-m="denied"></button>' +
        '<button type="button" data-a="granted" data-m="granted"></button>' +
        "</div>";
      banner.querySelector("strong").textContent = T.title;
      banner.querySelector("span").textContent = T.body;
      var a = banner.querySelector("a");
      a.textContent = T.more;
      a.href = T.href;
      var buttons = banner.querySelectorAll("button");
      buttons[0].textContent = T.none;
      buttons[1].textContent = T.stats;
      buttons[2].textContent = T.all;
      for (var i = 0; i < buttons.length; i++) {
        buttons[i].onclick = function () {
          choose(this.getAttribute("data-a"), this.getAttribute("data-m"));
        };
      }
      document.body.appendChild(banner);
    }
    banner.hidden = false;
  }

  function storeOf(href) {
    if (/apps\.apple\.com/.test(href)) return "ios";
    if (/play\.google\.com/.test(href)) return "android";
    if (/\/\/app\.kidboxapp\.com/.test(href)) return "web";
    return null;
  }

  function init() {
    document.addEventListener("click", function (e) {
      if (!e.target.closest) return;
      var el = e.target.closest("[data-consent-open]");
      if (el) { e.preventDefault(); open(); return; }
      var link = e.target.closest("a[href]");
      var store = link && storeOf(link.href);
      if (store && window.__kbGaLoaded) {
        window.gtag("event", "store_click", { store: store, page_path: location.pathname });
      }
    });
    // Anche all'avvio: gtag può riscrivere un cookie mentre la pagina si
    // ricarica dopo il ritiro del consenso.
    if (read(A_KEY) === "denied") clearGaCookies();
    apply();
    if (!noBanner && (read(A_KEY) === null || read(M_KEY) === null)) open();
  }

  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", init);
  else init();
})();
