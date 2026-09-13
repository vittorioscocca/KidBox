# ARCHITECTURE — KidBox Landing (sito web)

> Sito vetrina + pagine legali/supporto di KidBox. Statico puro (HTML/CSS/JS), nessun build step, deployato su Firebase Hosting.

---

## 1. Struttura

Tutto sotto `public/` (root di hosting):

| Pagina | Titolo | Scopo |
|---|---|---|
| `index.html` | KidBox · La famiglia, organizzata | Landing / marketing |
| `guide.html` | Guida KidBox · Come usare l'app | Guida utente |
| `support.html` | Supporto · KidBox | Contatti / FAQ supporto |
| `privacy.html` | Privacy Policy · KidBox | Informativa privacy |
| `terms.html` | Termini di Servizio · KidBox | ToS |
| `data-deletion.html` | Eliminazione Dati · KidBox | Istruzioni cancellazione account/dati (richiesto da App/Play Store) |
| `404.html` | Pagina non trovata | Fallback |
| `strumenti/` + `en/tools/` | Strumenti KidBox | **Generate**: una pagina per scheda dell'app (card + dettaglio con schermate, «come funziona», FAQ, collegati). Sorgente in `tools/tools_data.py`, generatore `scripts/build_tools.py`; non modificare l'HTML a mano |

- **`public/screenshots/`** — screenshot dell'app per sezione (Home, Note, Calendario, Password, Chat, Wallet, Animali, Documenti, Posizione, Garage, To-Do, Foto e Video, Spese, Casa, Wizard, …). Catturati da iPhone 17 Pro. Usati in `index.html`/`guide.html`.
- **`public/icon.png`** — logo/app icon.
- **`public/tools-img/`** — screenshot ridotti in WebP per le pagine Strumenti, generati da `scripts/build_tools.py` a partire da `public/screenshots/`.

> ⚠️ Le pagine legali esistono **anche** in `../docs/{privacy,terms,support,data-deletion}/index.html` (+ `../docs/privacy.md`), servite separatamente (es. GitHub Pages). Se aggiorni una policy, **allinea entrambe le copie**.

---

## 2. Hosting & deploy

- **`firebase.json`**: hosting `target: "landing"`, public `public/`.
  - **Rewrite SPA-style**: `**` → `/index.html`.
  - **Headers**: cache immutabile 1 anno per immagini (`jpg|jpeg|gif|png|svg|webp`); `X-Frame-Options: SAMEORIGIN` + `X-Content-Type-Options: nosniff` su tutto.
- Deploy: `firebase deploy --only hosting:landing` (il target `landing` va mappato in `.firebaserc` con `firebase target:apply hosting landing <site>`).

---

## 3. Quando modifichi qui

- Nessun framework / nessun bundler: modifica diretta dell'HTML, niente `npm`/build. Eccezione: la sezione Strumenti si rigenera con `python3 scripts/build_tools.py` (prende stile, nav, store e footer da `index.html`/`index-en.html`, quindi va rilanciato anche dopo un ritocco a quelli).
- `cleanUrls` è attivo: `/strumenti/calendario` serve `calendario.html`, e gli URL con `.html` reindirizzano a quelli puliti.
- Nuovi screenshot → metti i PNG in `public/screenshots/<Sezione>/` e referenziali nell'HTML (beneficiano della cache immutabile).
- Cambi a privacy/termini/data-deletion → aggiorna sia `public/*.html` sia `../docs/*/index.html` per non far divergere le due copie pubblicate.
