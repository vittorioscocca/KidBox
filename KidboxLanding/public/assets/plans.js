/**
 * Card dei piani della landing — un solo renderer, due chiamanti.
 *
 *   - `scripts/render-landing-plans.js` lo usa da Node per generare l'HTML
 *     statico dentro i marcatori PLANS:START / PLANS:END (SEO, primo paint,
 *     pagina che funziona anche senza JS);
 *   - la landing stessa lo usa nel browser per riallineare le card al listino
 *     vivo su `config/plans`, che si modifica dalla console admin senza deploy.
 *
 * L'HTML statico resta la base: se Firestore non risponde, se il visitatore ha
 * JS disabilitato o se il documento è più vecchio, la pagina mostra comunque le
 * card generate al deploy. Il fetch corregge, non costruisce.
 *
 * Vedi `internal/plans-source-of-truth.md`.
 */
(function (root, factory) {
  if (typeof module === "object" && module.exports) module.exports = factory();
  else root.KBPlans = factory();
})(typeof self !== "undefined" ? self : this, function () {
  "use strict";

  var PRICE_SUFFIX = {it: "/ mese", en: "/ month", fr: "/ mois", es: "/ mes"};

  function escapeHtml(s) {
    return String(s === null || s === undefined ? "" : s)
        .replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
  }

  /** "200 MB", "5 GB" — unità binarie, come le quote applicate dal backend. */
  function storageLabel(bytes) {
    var gb = bytes / Math.pow(1024, 3);
    if (gb >= 1) return (Number.isInteger(gb) ? gb : gb.toFixed(1)) + " GB";
    var mb = bytes / Math.pow(1024, 2);
    return (Number.isInteger(mb) ? mb : mb.toFixed(1)) + " MB";
  }

  function priceHtml(plan, lang) {
    var amount = new Intl.NumberFormat(lang, {
      minimumFractionDigits: plan.priceMonthly === 0 ? 0 : 2,
    }).format(plan.priceMonthly);
    var price = "€&thinsp;" + amount;
    if (plan.priceMonthly === 0) return price;
    return price + " <small>" + (PRICE_SUFFIX[lang] || PRICE_SUFFIX.en) + "</small>";
  }

  function featureHtml(feature, plan) {
    var text = escapeHtml(
        String(feature.text)
            .replace("{storage}", storageLabel(plan.storageBytes))
            .replace("{aiLimit}", String(plan.aiLimit)),
    );
    var body = feature.strong ? "<b>" + text + "</b>" : text;
    var off = feature.included === false ? ' class="off"' : "";
    return "        <li" + off + "><b>" + escapeHtml(feature.icon) + "</b> " + body + "</li>";
  }

  function planHtml(plan, lang) {
    // Sulla landing il badge lo porta solo il piano in evidenza: le tre card
    // stanno una accanto all'altra e tre stelline si annullerebbero a vicenda.
    var badge = plan.highlighted ? (plan.badge && plan.badge[lang]) || "" : "";
    var features = ((plan.features && (plan.features[lang] || plan.features.en)) || [])
        .map(function (f) { return featureHtml(f, plan); })
        .join("\n");

    return [
      '    <div class="plan' + (plan.highlighted ? " hot" : "") + '">',
      badge ? '      <div class="badge">⭐ ' + escapeHtml(badge) + "</div>" : null,
      '      <div class="pn">' + escapeHtml(plan.displayName) + "</div>" +
        '<div class="pp">' + priceHtml(plan, lang) + "</div>" +
        '<div class="psub">' + escapeHtml((plan.tagline && plan.tagline[lang]) || "") + "</div><hr>",
      "      <ul>",
      features,
      "      </ul>",
      "    </div>",
    ].filter(Boolean).join("\n");
  }

  /**
   * HTML delle tre card, senza il contenitore `.plans`.
   * @param {object} plans - Mappa {planId: spec}.
   * @param {string} lang - Lingua dei testi.
   * @return {string}
   */
  function renderPlanCards(plans, lang) {
    return Object.keys(plans)
        .map(function (k) { return plans[k]; })
        .sort(function (a, b) { return (a.order || 0) - (b.order || 0); })
        .map(function (p) { return planHtml(p, lang); })
        .join("\n");
  }

  return {renderPlanCards: renderPlanCards, storageLabel: storageLabel};
});

// ─────────────────────────────────────────────────────────────────────────────
// Allineamento a runtime (solo browser)
// ─────────────────────────────────────────────────────────────────────────────
if (typeof document !== "undefined") {
  (function () {
    "use strict";

    var PROJECT = "kidbox-42cd7";
    // Chiave web pubblica: identifica il progetto, non autorizza nulla. La
    // lettura di `config/plans` è aperta perché il documento contiene solo
    // listino e testi di marketing — le rules chiudono tutto il resto.
    var API_KEY = "AIzaSyC7mDpJ1LadjvhhcoospAp2f0xuawCOOFk";
    var URL_DOC = "https://firestore.googleapis.com/v1/projects/" + PROJECT +
      "/databases/(default)/documents/config/plans?key=" + API_KEY;
    var CACHE_KEY = "kb_plans_v1";
    var CACHE_TTL_MS = 6 * 60 * 60 * 1000;

    /** Converte i valori tipizzati della REST di Firestore in oggetti normali. */
    function fromFirestore(v) {
      if (!v || typeof v !== "object") return null;
      if ("integerValue" in v) return parseInt(v.integerValue, 10);
      if ("doubleValue" in v) return Number(v.doubleValue);
      if ("stringValue" in v) return v.stringValue;
      if ("booleanValue" in v) return v.booleanValue;
      if ("nullValue" in v) return null;
      if ("mapValue" in v) {
        var out = {};
        var fields = v.mapValue.fields || {};
        for (var k in fields) if (Object.prototype.hasOwnProperty.call(fields, k)) out[k] = fromFirestore(fields[k]);
        return out;
      }
      if ("arrayValue" in v) return (v.arrayValue.values || []).map(fromFirestore);
      return null;
    }

    function cached() {
      try {
        var raw = sessionStorage.getItem(CACHE_KEY);
        if (!raw) return null;
        var box = JSON.parse(raw);
        return Date.now() - box.at < CACHE_TTL_MS ? box.plans : null;
      } catch (e) { return null; }
    }

    function applica(plans) {
      var box = document.querySelector(".plans");
      if (!box || !plans || !plans.free) return;
      var lang = (document.documentElement.lang || "it").slice(0, 2);
      var html = self.KBPlans.renderPlanCards(plans, lang);
      // Solo se cambia davvero: riscrivere identico farebbe ripartire le
      // animazioni delle card per niente.
      if (box.innerHTML.trim() !== html.trim()) box.innerHTML = html;
    }

    function avvia() {
      // La cache serve a dipingere subito, non a evitare la lettura: fermarsi
      // qui significava non vedere per sei ore un listino appena pubblicato.
      var locale = cached();
      if (locale) applica(locale);

      fetch(URL_DOC, {cache: "no-store"})
          .then(function (r) { return r.ok ? r.json() : null; })
          .then(function (doc) {
            if (!doc || !doc.fields || !doc.fields.plans) return;
            var plans = fromFirestore(doc.fields.plans);
            try {
              sessionStorage.setItem(CACHE_KEY, JSON.stringify({at: Date.now(), plans: plans}));
            } catch (e) { /* private browsing: pazienza, si rilegge */ }
            applica(plans);
          })
          .catch(function () { /* restano le card generate al deploy */ });
    }

    if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", avvia);
    else avvia();
  })();
}
