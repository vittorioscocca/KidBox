# ARCHITECTURE — KidBox Admin Console

> Dashboard di amministrazione interna di KidBox. Single-page HTML standalone, **read-only** su Firestore. Uso personale dell'owner, non destinata agli utenti finali.

---

## 1. Cosa è

- **`kidbox-admin.html`** (~750 righe) — l'intera console in un unico file: HTML + CSS + JS inline, nessun build step, nessun framework.
- **Firebase Web SDK 11.0.1** importato via ESM da `gstatic.com` (`firebase-app`, `firebase-auth`, `firebase-firestore`).
- **`public/index.html`** + **`public/404.html`** — versione deployata su Firebase Hosting (`firebase.json` → `public`). `index.html` è la stessa console admin (title `KidBox · Admin`).
- **`Comandi.rtf`** — note: per girare in locale basta un web server statico.

```bash
# Locale (da KidboxConsole/)
python3 -m http.server 8080
# → http://localhost:8080/kidbox-admin.html
```

---

## 2. Auth & accesso dati

- **Login**: `signInWithPopup` con `GoogleAuthProvider`. Nessun service account — usa le credenziali Firebase dell'utente (le rules limitano comunque l'accesso all'admin UID `efw85HN41nb1rmslevC3wkFpVUo1`).
- **Config Firebase**: inserita a runtime nel form (API Key + Project ID + Auth Domain auto), poi `initializeApp(cfg, 'kidbox-admin')`. Non hardcoded.
- **Solo letture**: la console usa esclusivamente `getDoc` / `getDocs` (`getFirestore`). **Nessuna `httpsCallable`, nessuna scrittura.**

### Collezioni lette
| Collezione | Uso |
|---|---|
| `users` | elenco utenti / conteggi |
| `families` | elenco famiglie, stats per famiglia |
| `ai_usage/family_{fid}/daily/{YYYY-MM-DD}` | utilizzo AI giornaliero |
| `ai_costs/{monthKey}` + `ai_costs/{monthKey}/families/{fid}` | costi AI mensili aggregati e per famiglia |

> Nota: `ai_usage` e `ai_costs` sono popolati dalle Cloud Functions (`askAI`). Vedi `functions/ARCHITECTURE.md`.

---

## 3. Deploy

`firebase.json` qui dentro fa hosting della cartella `public/`. La console "vera" usata in dev è `kidbox-admin.html` alla root (non in `public/`), servita in locale.

---

## 4. Quando modifichi qui

- È volutamente **read-only**: per azioni amministrative (es. gestione `cases`, plan override) esistono già callable functions (`takeCase`, `resolveCase`, `setFamilyPlanOverride`, …) — se vuoi esporle dalla console, aggiungi `getFunctions`/`httpsCallable` e verifica le rules admin.
- Nuove metriche → di solito basta una nuova lettura Firestore; se il dato non esiste ancora, va prima calcolato/scritto da una Cloud Function (il client admin non scrive).
- Single-file senza build: modifica diretta di `kidbox-admin.html`, poi allinea `public/index.html` se vuoi ridistribuirla.
