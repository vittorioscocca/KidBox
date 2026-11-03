// Caroselli delle sezioni (stile pagine prodotto Apple): più schermate
// dell'app dentro lo stesso telefono, con didascalia, puntini e play/pausa.
// Ogni [data-carousel] è indipendente; i testi dei pulsanti stanno negli
// attributi data-pause / data-play, così lo script non conosce le lingue.
// Parte da solo solo quando è a schermo, e mai con «riduci movimento».
(function () {
  var reduce = window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches;
  var MS = 4500;

  document.querySelectorAll('[data-carousel]').forEach(function (root) {
    var track = root.querySelector('.car-track');
    var slides = root.querySelectorAll('.car-slide');
    var dots = root.querySelectorAll('.car-dot');
    var cap = root.querySelector('.car-cap');
    var btn = root.querySelector('.car-play');
    var i = 0, timer = null, playing = !reduce, visible = false;
    root.style.setProperty('--car-ms', MS + 'ms');

    function go(n) {
      i = (n + slides.length) % slides.length;
      track.style.transform = 'translateX(' + (-100 * i) + '%)';
      slides.forEach(function (s, k) { s.setAttribute('aria-hidden', k === i ? 'false' : 'true'); });
      dots.forEach(function (d, k) {
        d.classList.toggle('on', k === i);
        d.setAttribute('aria-selected', k === i ? 'true' : 'false');
        // Rifà partire il riempimento del puntino attivo.
        if (k === i) { d.classList.remove('run'); void d.offsetWidth; }
      });
      if (cap) cap.textContent = slides[i].dataset.cap || '';
      schedule();
    }
    function schedule() {
      clearTimeout(timer);
      var run = playing && visible;
      root.classList.toggle('paused', !run);
      if (dots[i]) dots[i].classList.toggle('run', run);
      if (run) timer = setTimeout(function () { go(i + 1); }, MS);
    }
    function setPlaying(p) {
      playing = p;
      btn.classList.toggle('is-paused', !p);
      btn.setAttribute('aria-label', p ? btn.dataset.pause : btn.dataset.play);
      schedule();
    }

    dots.forEach(function (d, k) { d.addEventListener('click', function () { go(k); }); });
    btn.addEventListener('click', function () { setPlaying(!playing); });

    // Scorrimento col dito (o trascinando col mouse sul telefono).
    var x0 = null;
    track.addEventListener('pointerdown', function (e) { x0 = e.clientX; });
    track.addEventListener('pointerup', function (e) {
      if (x0 === null) return;
      var dx = e.clientX - x0; x0 = null;
      if (Math.abs(dx) > 40) go(i + (dx < 0 ? 1 : -1));
    });
    track.addEventListener('pointercancel', function () { x0 = null; });

    if ('IntersectionObserver' in window) {
      new IntersectionObserver(function (es) {
        visible = es[0].isIntersecting; schedule();
      }, { threshold: 0.5 }).observe(root);
    } else { visible = true; }
    setPlaying(playing);
    go(0);
  });
})();
