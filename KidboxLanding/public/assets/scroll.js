// Barra trasparente sopra la foto finché si è in cima (poi torna piena), e
// freccia laterale che riporta all'inizio della pagina. Senza script la barra
// resta piena e la freccia non c'è: niente si rompe.
(function () {
  var nav = document.querySelector('nav');
  var labels = { it: 'Torna su', en: 'Back to top', es: 'Volver arriba', fr: 'Haut de page' };
  var lang = (document.documentElement.lang || 'it').slice(0, 2);

  var btn = document.createElement('button');
  btn.type = 'button';
  btn.className = 'to-top';
  btn.setAttribute('aria-label', labels[lang] || labels.it);
  btn.title = labels[lang] || labels.it;
  btn.innerHTML = '<svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M12 19V5M5 12l7-7 7 7"/></svg>';
  btn.addEventListener('click', function () {
    var reduce = window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches;
    window.scrollTo({ top: 0, behavior: reduce ? 'auto' : 'smooth' });
  });
  document.body.appendChild(btn);

  var ticking = false;
  function update() {
    ticking = false;
    var y = window.scrollY || 0;
    if (nav) nav.classList.toggle('at-top', y < 8);
    btn.classList.toggle('show', y > window.innerHeight * 0.9);
  }
  window.addEventListener('scroll', function () {
    if (!ticking) { ticking = true; requestAnimationFrame(update); }
  }, { passive: true });
  window.addEventListener('resize', update);
  update();
})();
