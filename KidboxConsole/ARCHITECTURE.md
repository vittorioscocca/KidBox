# ARCHITECTURE — KidBox Admin Console

> Dashboard di amministrazione interna di KidBox. Single-page HTML standalone.
> Uso personale dell'owner, non destinata agli utenti finali.

---

## 1. Cosa è

- **`public/index.html`** (~2350 righe) — **l'unica console**: HTML + CSS + JS inline,
  nessun build step, nessun framework. È sia il sorgente sia il file deployato.
- **`public/404.html`** — pagina di errore hosting.
- **Firebase Web SDK 11.0.1** importato via ESM da `gstatic.com` (`firebase-app`,
  `firebase-auth`, `firebase-firestore`).
- **`Comandi.rtf`** — note: per girare in locale basta un web server statico.

```bash
# Locale (da KidboxConsole/)
python3 -m http.server 8080
# → http://localhost:8080/public/index.html
```

> **Storico (lug 2026)**: esisteva anche `kidbox-admin.html` alla root, presentato
> come "il sorgente" da riallineare a mano su `public/index.html`. I due file erano
> divergenti — la copia alla root era ferma indietro di quattro sezioni (Gestione
> Piani, Tutti gli utenti, Ticket & Bug Report, Ticket Supporto Chat) e delle stat
> iOS/Android — quindi *"allinea `public/index.html`"* significava **cancellare
> feature vive**. Il duplicato è stato rimosso: unica fonte di verità è
> `public/index.html`. Se serve, è recuperabile con
> `git show 59e0fb8f:KidboxConsole/kidbox-admin.html`.

---

## 2. Auth & accesso dati

- **Login**: `signInWithPopup` con `GoogleAuthProvider`. Nessun service account — usa
  le credenziali Firebase dell'utente. Le rules limitano l'accesso all'admin UID
  `efw85HN41nb1rmslevC3wkFpVUo1` (`ADMIN_UIDS` in `functions/index.js`).
- **Config Firebase**: inserita a runtime nel form (API Key + Project ID + Auth Domain
  auto), poi `initializeApp(cfg, 'kidbox-admin')`. Non hardcoded.
- **Prevalentemente in lettura**, ma **non più read-only**: la console scrive
  (`updateDoc` / `deleteDoc` su ticket e cases) e chiama Cloud Functions via `fetch`
  con l'ID token — non usa il pacchetto `firebase-functions`.

### Collezioni lette
| Collezione | Uso |
|---|---|
| `users` | elenco utenti, conteggi, piattaforma iOS/Android |
| `families` | elenco famiglie, stats per famiglia, override piano |
| `ai_costs/{monthKey}` + `/families/{fid}` | costi AI mensili aggregati e per famiglia |
| `metrics/{YYYY-MM-DD}` | rollup utenti attivi — DAU/WAU/MAU, famiglie, feature |
| `cases` | ticket & bug report |
| `crash_reports` | crash |
| `support_tickets` | chat di supporto |

### Cloud Functions chiamate
| Function | Uso |
|---|---|
| `initStorageUsageAdmin` | ricalcolo storage di tutte le famiglie |
| `runAnalyticsRollup` | ricalcolo rollup utenti attivi (oggi + ieri) |

> `ai_usage` e `ai_costs` sono popolati da `askAI`; `metrics` da
> `analyticsRollupDaily`. Vedi `functions/ARCHITECTURE.md` e
> `docs/analytics-active-users.md`.

---

## 3. Deploy

`firebase.json` fa hosting della cartella `public/`. Non c'è build: il file editato è
il file servito.

```bash
# da KidboxConsole/
firebase deploy --only hosting
```

---

## 4. Quando modifichi qui

- **Un solo file**: `public/index.html`. Non ricreare copie "sorgente" fuori da
  `public/` — è esattamente ciò che ha prodotto la divergenza del luglio 2026.
- Nuove metriche → di solito basta una nuova lettura Firestore; se il dato non esiste
  ancora, va prima calcolato e scritto da una Cloud Function. Per gli aggregati
  costosi, il pattern è: la function scrive un rollup, la console legge **solo** il
  rollup (vedi `metrics/`), così il costo di lettura resta costante.
- Per esporre una callable: `fetch` su
  `https://europe-west1-${cfg.projectId}.cloudfunctions.net/<nome>` con
  `Authorization: Bearer <idToken>` e body `{ data: {...} }`; la function verifica
  `ADMIN_UIDS`. È il pattern già usato da `resetStorageAll` e `runRollup`.
