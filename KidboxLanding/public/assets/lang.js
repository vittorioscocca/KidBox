/*
 * Menu delle lingue della landing.
 *
 * - Un clic su una lingua la salva in localStorage (`kidbox_lang`): da quel
 *   momento la home non sceglie più la lingua in automatico (vedi il router in
 *   index.html e /assets/geo.js).
 * - La tendina (<details class="lang-menu">) si chiude cliccando fuori o con Esc.
 */
(function () {
  document.addEventListener("click", function (e) {
    var t = e.target;
    var link = t.closest && t.closest(".lang-menu a[data-lang]");
    if (link) {
      try { localStorage.setItem("kidbox_lang", link.getAttribute("data-lang")); } catch (err) {}
      return;
    }
    document.querySelectorAll(".lang-menu[open]").forEach(function (d) {
      if (!d.contains(t)) d.removeAttribute("open");
    });
  });
  document.addEventListener("keydown", function (e) {
    if (e.key !== "Escape") return;
    document.querySelectorAll(".lang-menu[open]").forEach(function (d) { d.removeAttribute("open"); });
  });
  // Anche i link di lingua nel footer ricordano la scelta.
  document.addEventListener("click", function (e) {
    var a = e.target.closest && e.target.closest("footer a[data-lang-alt]");
    if (a) { try { localStorage.setItem("kidbox_lang", a.getAttribute("data-lang-alt")); } catch (err) {} }
  });
})();
