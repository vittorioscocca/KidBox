/*
 * Consenso per il Meta Pixel della landing.
 *
 * Il Pixel non parte finché il visitatore non ha detto sì: il default è «non
 * deciso», che equivale a spento — nessuno script di Meta caricato, nessuna
 * richiesta a facebook.com. La scelta resta in localStorage sotto una chiave
 * sua: quella delle statistiche anonime di /join (`kidbox:analyticsConsent`) è
 * un consenso diverso e non vale per la pubblicità.
 *
 * Le due risposte hanno lo stesso peso visivo, come nel banner della web app:
 * un «rifiuta» sbiadito accanto a un «accetta» colorato non è una scelta.
 *
 * Uso: <script src="/assets/consent.js" defer></script>
 *   data-no-banner  → niente banner (pagine che reindirizzano subito, come
 *                     /scarica): il Pixel parte solo se il sì c'è già.
 * Qualunque elemento con `data-consent-open` riapre il banner, per cambiare idea.
 */
(function () {
  var KEY = "kidbox:marketingConsent";
  var PIXEL_ID = "1335685042033994";
  var script = document.currentScript;
  var noBanner = script && script.hasAttribute("data-no-banner");
  var en = (document.documentElement.lang || "it").slice(0, 2) === "en";

  var T = en
    ? {
        title: "Cookies and advertising",
        body: "May we use the Meta Pixel to measure how our ads perform? It sets cookies and sends Meta the pages you visit on this site. Nothing runs until you say yes.",
        more: "Learn more",
        href: "/privacy-en#cookie",
        accept: "Accept",
        decline: "Decline",
      }
    : {
        title: "Cookie e pubblicità",
        body: "Possiamo usare il Meta Pixel per misurare come vanno le nostre pubblicità? Imposta dei cookie e comunica a Meta le pagine che visiti su questo sito. Finché non dici sì non parte nulla.",
        more: "Maggiori informazioni",
        href: "/privacy#cookie",
        accept: "Accetta",
        decline: "Rifiuta",
      };

  function stored() {
    try {
      var v = localStorage.getItem(KEY);
      return v === "granted" || v === "denied" ? v : null;
    } catch (e) {
      // Senza storage la scelta non si può ricordare: si resta sul rifiuto,
      // senza banner che ricomparirebbe a ogni pagina.
      return "denied";
    }
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

  var CSS =
    ".kb-consent{position:fixed;left:16px;right:16px;bottom:16px;z-index:9999;max-width:640px;margin:0 auto;display:flex;flex-wrap:wrap;align-items:center;gap:14px;padding:16px 18px;border:1px solid var(--border,var(--c-border,rgba(0,0,0,.12)));border-radius:16px;background:var(--surface,var(--c-surface,#fff));color:var(--text,var(--c-text,#1c1008));box-shadow:0 8px 30px rgba(0,0,0,.18);font-family:inherit;text-align:left}" +
    ".kb-consent[hidden]{display:none}" +
    ".kb-consent-text{flex:1;min-width:220px}" +
    ".kb-consent-text strong{display:block;font-size:.95rem;margin-bottom:4px}" +
    ".kb-consent-text p{font-size:.83rem;line-height:1.45;margin:0;color:var(--muted,var(--c-muted,#6b5d52))}" +
    ".kb-consent-text a{color:inherit;text-decoration:underline}" +
    ".kb-consent-actions{display:flex;gap:8px;margin-left:auto}" +
    ".kb-consent-actions button{border:1px solid var(--border,var(--c-border,rgba(0,0,0,.12)));background:transparent;color:inherit;border-radius:10px;padding:9px 18px;font:inherit;font-size:.88rem;font-weight:600;cursor:pointer;white-space:nowrap}" +
    ".kb-consent-actions button:hover{background:var(--border,var(--c-border,rgba(0,0,0,.08)))}";

  var banner = null;

  function choose(value) {
    try { localStorage.setItem(KEY, value); } catch (e) {}
    if (banner) banner.hidden = true;
    if (value === "granted") loadPixel();
    // Un sì già dato e poi ritirato non si può «spegnere» in pagina: lo script
    // di Meta è caricato. Si ricarica, così da qui in avanti non parte più.
    else if (window.fbq) location.reload();
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
        '<div class="kb-consent-actions"><button type="button" data-v="denied"></button><button type="button" data-v="granted"></button></div>';
      banner.querySelector("strong").textContent = T.title;
      banner.querySelector("span").textContent = T.body;
      var a = banner.querySelector("a");
      a.textContent = T.more;
      a.href = T.href;
      var buttons = banner.querySelectorAll("button");
      buttons[0].textContent = T.decline;
      buttons[1].textContent = T.accept;
      for (var i = 0; i < buttons.length; i++) {
        buttons[i].onclick = function () { choose(this.getAttribute("data-v")); };
      }
      document.body.appendChild(banner);
    }
    banner.hidden = false;
  }

  function init() {
    document.addEventListener("click", function (e) {
      var el = e.target.closest && e.target.closest("[data-consent-open]");
      if (el) { e.preventDefault(); open(); }
    });
    var v = stored();
    if (v === "granted") loadPixel();
    else if (v === null && !noBanner) open();
  }

  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", init);
  else init();
})();
