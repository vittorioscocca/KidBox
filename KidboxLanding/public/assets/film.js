// Il film di KidBox: si apre a schermo pieno sopra la pagina, con l'audio,
// da qualunque elemento [data-film] (link nella prima schermata, anteprima
// nella sezione). Il file si scarica solo al primo clic.
(function () {
  var dlg = document.querySelector('.film-dlg');
  if (!dlg) return;
  var v = dlg.querySelector('video');
  function open() {
    if (!v.src) v.src = v.dataset.src;
    if (dlg.showModal) dlg.showModal(); else dlg.setAttribute('open', '');
    document.documentElement.classList.add('film-open');
    v.muted = false;
    var p = v.play(); if (p && p.catch) p.catch(function () {});
  }
  function close() {
    v.pause();
    if (dlg.open && dlg.close) dlg.close(); else dlg.removeAttribute('open');
  }
  document.querySelectorAll('[data-film]').forEach(function (el) {
    el.addEventListener('click', function (e) { e.preventDefault(); open(); });
  });
  dlg.querySelector('.film-close').addEventListener('click', close);
  // Clic sul fondo nero, fuori dal video: chiude.
  dlg.addEventListener('click', function (e) { if (e.target === dlg) close(); });
  dlg.addEventListener('close', function () {
    v.pause();
    document.documentElement.classList.remove('film-open');
  });
  v.addEventListener('ended', close);
})();
