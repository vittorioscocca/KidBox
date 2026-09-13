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
| `blog/` + `en/blog/` | Blog KidBox | **Generate**: indice per categorie, una pagina per categoria e una per articolo (testo, box «scarica l'app», strumenti citati, articoli collegati, JSON-LD `Article`). Sorgente in `tools/blog_data.py` + `tools/blog_*.py` (un modulo per categoria, markdown minimo), generatore `scripts/build_blog.py`; non modificare l'HTML a mano. Gli articoli sono originali: mai copiare testi altrui |

- **`public/screenshots/`** — screenshot dell'app per sezione (Home, Note, Calendario, Password, Chat, Wallet, Animali, Documenti, Posizione, Garage, To-Do, Foto e Video, Spese, Casa, Wizard, …). Catturati da iPhone 17 Pro. Usati in `index.html`/`guide.html`.
- **`public/icon.png`** — logo/app icon.
- **`public/assets/consent.js`** — banner di consenso e caricamento di **Google Analytics 4** (stessa proprietà della web app, `G-0PG65CW2VF`, evento `store_click`) e del **Meta Pixel**: ognuno parte solo dopo il consenso alla sua finalità (`kidbox:analyticsConsent`, condivisa con `/join`, e `kidbox:marketingConsent`). Ogni pagina lo include nello `<head>` (i generatori lo aggiungono da soli); `data-no-banner` su `scarica.html`, che reindirizza subito. Mai rimettere `gtag`/`fbq` direttamente in una pagina. Il link «Preferenze cookie» (`data-consent-open`) riapre il banner; l'informativa è la sezione `#cookie` di `privacy.html`/`privacy-en.html`.
- **`public/sitemap.xml` + `robots.txt`** — generati da `scripts/build_sitemap.py` (lanciato anche dagli altri due generatori); una pagina statica nuova va aggiunta a `STATIC`.
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

- Nessun framework / nessun bundler: modifica diretta dell'HTML, niente `npm`/build. Eccezione: le sezioni Strumenti e Blog si rigenerano con `python3 scripts/build_tools.py` e `python3 scripts/build_blog.py` (prendono stile, nav, store e footer da `index.html`/`index-en.html`, quindi vanno rilanciati entrambi anche dopo un ritocco a quelli).
- `cleanUrls` è attivo: `/strumenti/calendario` serve `calendario.html`, e gli URL con `.html` reindirizzano a quelli puliti.
- Nuovi screenshot → metti i PNG in `public/screenshots/<Sezione>/` e referenziali nell'HTML (beneficiano della cache immutabile).
- Cambi a privacy/termini/data-deletion → aggiorna sia `public/*.html` sia `../docs/*/index.html` per non far divergere le due copie pubblicate.
