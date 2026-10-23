/*
 * «Mi piace l'idea»: il cuore nella barra in alto della home, con sotto il
 * numero di like.
 *
 * Conta `/api/like` (rewrite di Hosting sulla function `landingLike`): un like
 * per indirizzo IP, e la function ricorda chi l'ha già messo. Qui niente
 * cookie né localStorage: se il like c'è già, lo dice la risposta di «get».
 * Finché la risposta non arriva il numero resta vuoto; se la chiamata fallisce
 * il cuore resta lì senza numero.
 */
(function () {
  var box = document.getElementById("lk");
  if (!box) return;
  var btn = box.querySelector("button");
  var out = box.querySelector(".like-n");
  var lang = document.documentElement.lang || "it";
  var count = null;

  function fmt(c) {
    try { return new Intl.NumberFormat(lang).format(c); } catch (e) { return String(c); }
  }
  function show(d) {
    if (!d || typeof d.count !== "number") return;
    count = d.count;
    out.textContent = fmt(count);
    btn.setAttribute("aria-pressed", d.liked ? "true" : "false");
  }
  function call(action) {
    return fetch("/api/like", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ action: action }),
    }).then(function (r) { return r.ok ? r.json() : null; });
  }

  call("get").then(show).catch(function () {});

  btn.addEventListener("click", function () {
    if (btn.getAttribute("aria-pressed") === "true") return;
    // Subito pieno: la risposta corregge il numero, o lo riporta indietro.
    var before = { count: count, liked: false };
    btn.setAttribute("aria-pressed", "true");
    btn.classList.remove("pop");
    void btn.offsetWidth;
    btn.classList.add("pop");
    if (count !== null) out.textContent = fmt(count + 1);
    call("like").then(function (d) { show(d || before); }).catch(function () { show(before); });
  });
})();
