# Registro delle scommesse

Stato della skill `/auto-miglioramento`. Una riga per scommessa. **La previsione
si scrive prima della modifica**, con un numero e una data; il verdetto deve
poterlo calcolare un estraneo leggendo solo questo file e il report del giorno.

Verdetti: **confermata** · **smentita** (è il risultato che vale di più)
· **non misurabile** (il dato non c'è, la release non è adottata, i numeri sono
troppo piccoli — la colpa è della previsione, non del mondo).

Regole: non si sposta una data in avanti per salvare una scommessa (si chiude
«non misurabile» e si riapre come riga nuova); non si cancella una riga chiusa.

---

## Aperte

### 1. Wizard di onboarding a 2 pagine
- **Cambio**: iOS 2.3.0 / Android 2.2.9 (53), in revisione dal 19/09/2026. Nome, cognome e famiglia in una schermata sola (`setup`), poi `invite` o `join_family`.
- **Previsione**: iniziato → completato passa dal **56% al 75%** per utenti unici sui 28 giorni.
- **Misura**: tabella «Funnel per UTENTI unici» di `ga4-daily-report.js` — utenti con `onboarding_step_shown` contro utenti con `onboarding_completed`.
- **Data**: 15/10/2026 (serve che la release sia in store e adottata: 1-2 settimane).
- **Se smentita**: l'abbandono non era nella lunghezza del wizard; il 4 su 10 che se ne va lo fa per un motivo che non abbiamo ancora misurato, e va cercato parlando con le persone invece che nei numeri.

### 2. Link d'invito a 7 giorni
- **Cambio**: stessa release. Il link scadeva in 24 ore.
- **Previsione**: `family_join_failed.reason=expired` scende **sotto il 10%** dei tentativi di join falliti, e il rapporto inviti generati → `/join` visti (contatore `inviteLandingPing`) **sale rispetto alla media di settembre**.
- ⚠️ **Previsione da stringere al prossimo giro**: nel progetto c'era la direzione («cala», «sale»), non il numero di partenza. Al primo giro, misurare la base di settembre e riscrivere qui i due numeri.
- **Misura**: `ga4-daily-report.js` (spaccatura `reason`) + sezione contatore landing di `console-daily-report.js`.
- **Data**: 15/10/2026.
- **Se smentita**: la scadenza non era l'ostacolo; il buco 44 → 15 sta tra il ricevere il link e l'aprirlo, cioè nel messaggio che si manda, non nella meccanica.

### 3. Foglio d'invito contestuale «Per ora lo vedi solo tu»
- **Cambio**: live dal 16/09/2026 (Android 2.2.8 (52), iOS 2.2.9). Dopo il primo contenuto creato in una famiglia con un solo membro, una volta sola.
- **Previsione**: `invite_prompt_accepted` ÷ `invite_prompt_shown` per utenti unici **sopra il 17%** (la checklist in Home convertiva 13 tap su 77; la push `family_invite` lo 0%).
- **Misura**: `ga4-daily-report.js`. **Nessun giudizio sotto i 20 `shown`**: in quel caso il verdetto è «non misurabile», non «smentita».
- **Data**: 30/09/2026.
- **Se smentita**: il momento giusto non è dopo il primo contenuto, oppure il problema non è quando si chiede ma che si chiede di invitare qualcuno che non ha un motivo per entrare (→ candidato 3 del backlog, «chiedi a chi non ha l'app»).

### 4. Obiettivi Search Console al 15/10
- **Cambio**: property nata il 12/09/2026, blog in 4 lingue, sitemap generata.
- **Previsione** (concordata il 16/09): query «kidbox» in posizione **≤ 3**; **40 impressioni/giorno**; **1 click/giorno**; **40 pagine con impressioni**.
- **Misura**: `search-console-daily-report.js`, sezione «Obiettivi».
- **Data**: 15/10/2026. Caso aperto: Google considera la home un duplicato di `kidbox-landing.web.app/index.html`; se dopo il 15/10 «kidbox» è oltre la 5, serve il redirect 301 dal dominio web.app.
- **Se smentita**: l'indicizzazione non è il collo di bottiglia della scoperta, e il blog non ripaga il tempo che costa.

### 5. Campagna Meta «App Installs Android»
- **Cambio**: dal 17/09/2026 «Traffico Landing» in pausa (3 restati su 68 aperture, tap accidentali da Reels), riattivata «App Installs Android».
- **Previsione**: dopo 7 giorni di spesa piena (~84 €) le **registrazioni Auth superano la base di ≈1 al giorno** e le famiglie create crescono.
- **Misura**: spesa Meta ÷ registrazioni Auth sui 7 giorni (`meta-ads-daily-report.js` + `console-daily-report.js`). **Non** il costo per installazione dichiarato da Meta.
- **Data**: 24/09/2026.
- **Se smentita**: il problema non è il traffico ma l'attivazione, e ogni euro speso prima di aver sistemato onboarding e secondo membro è buttato.

### 7. Le valide su Firestore salgono da sole
- **Cambio**: aggiunta il 20/09/2026 l'impronta SHA-256 della chiave di App Signing (`edb811c0…288099`) al progetto Firebase. Nessuna release, nessuna modifica al codice.
- **Previsione**: le richieste **valide su Firestore superano il 90%** entro il **23/09/2026**, senza pubblicare nulla. Alle 13:12 del 20/09 erano al 31% (erano 13% un'ora prima).
- **Misura**: `node scripts/appcheck-daily-report.js` — quota valide per servizio.
- **Data**: 23/09/2026.
- **Se smentita**: oltre ad Android c'è **un'altra sorgente di `INVALID`** che non abbiamo ancora identificato, e va trovata **prima** di accendere l'enforcement, non dopo. Candidati da guardare in quel caso: build di sviluppo in uso, versioni vecchie ancora installate, la console admin.

---

## Chiuse

### 6. Attestazione App Check su Android
- **Cambio**: nessuno ancora. Il codice App Check è nei quattro client dal 14/08/2026, ma Android non supera l'attestazione (`403 App attestation failed` sul device dal 30/08, mai risolto). Prossimo passo: provare una build **release firmata installata da Play**, seguendo l'ordine di `internal/app-check.md`.
- **Previsione**: entro il **20/10/2026** compare un `app_id` **android tra le VALID** e le richieste valide su Firestore salgono **sopra il 50%** (oggi 13%, con zero giorni sopra soglia).
- **Misura**: `node scripts/appcheck-daily-report.js` — verdetto e serie per giorno.
- **Data**: 20/10/2026.
- **Se smentita**: il problema non è il device di prova ma la configurazione Play Integrity del progetto, e l'enforcement va rimandato oltre la fine dell'anno invece di essere riprovato a tentativi. Il costo di sbagliare qui non è un fastidio: a enforcement acceso l'app smette di funzionare per chi non attesta.
- **Nota**: il cancello per accendere l'enforcement è più alto di questa previsione (≥ 90% per 7 giorni consecutivi **e** tutte e tre le piattaforme tra le VALID). Questa scommessa misura solo se la strada si è sbloccata.
- **VERDETTO (20/09/2026): confermata — ma con 30 giorni di anticipo e per la ragione sbagliata.**
  Android è comparso tra le VALID lo stesso giorno in cui la scommessa è stata scritta. La previsione era giusta, il modello causale no: avevo ipotizzato un problema di device o di distribuzione («provare una build release firmata installata da Play») e la causa era una **configurazione del progetto Firebase** — lo SHA-256 della chiave di App Signing non registrato. La prova su Play è servita solo perché ha prodotto il log che ha rivelato la vera catena.
  **Una previsione giusta per il motivo sbagliato non è una vittoria: è un avviso.** Se l'avessimo contata come successo senza guardare la causa, oggi crederemmo che il problema fosse il device di prova — e la stessa diagnosi sbagliata tornerebbe alla prossima piattaforma che non attesta. Diagnosi completa e regola generalizzabile in `internal/app-check.md`.


---

## Giri

| # | Data | Scommesse chiuse | Confermate | Smentite | Non misurabili | Meta-passo |
|---|---|---|---|---|---|---|
| 0 | 20/09/2026 | — | — | — | — | nascita del registro |
