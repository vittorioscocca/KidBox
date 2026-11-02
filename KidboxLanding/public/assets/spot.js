// Spot video nella prima schermata della landing.
// Il file si scarica solo quando il telefono col video entra nello schermo,
// parte muto (i browser non avviano l'audio da soli) e si ferma quando esce.
// Con «riduci movimento» non parte da solo: si avvia toccandolo.
(function () {
  var reduce = window.matchMedia && matchMedia('(prefers-reduced-motion: reduce)').matches;
  document.querySelectorAll('.spot').forEach(function (box) {
    var v = box.querySelector('video');
    var btn = box.querySelector('.spot-audio');
    if (!v) return;
    function load() { if (!v.src) { v.src = v.dataset.src; } }
    function play() { load(); var p = v.play(); if (p && p.catch) p.catch(function () {}); }
    function setAudio(on) {
      v.muted = !on;
      btn.setAttribute('aria-pressed', on ? 'true' : 'false');
      btn.setAttribute('aria-label', on ? btn.dataset.off : btn.dataset.on);
      btn.classList.toggle('on', on);
    }
    btn.addEventListener('click', function (e) {
      e.stopPropagation();
      setAudio(v.muted);
      if (!v.muted) { if (v.ended || v.currentTime > v.duration - 1) v.currentTime = 0; play(); }
    });
    v.addEventListener('click', function () { if (v.paused) play(); else v.pause(); });
    if (reduce || !('IntersectionObserver' in window)) return;
    new IntersectionObserver(function (es) {
      es.forEach(function (e) {
        if (e.isIntersecting) play();
        else if (!v.paused) v.pause();
      });
    }, { threshold: 0.25 }).observe(box);
  });
})();
