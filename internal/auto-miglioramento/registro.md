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


### 8. Richieste di famiglia («Chi prende Marco giovedì?»)
- **Cambio**: «Chiedi a qualcuno…» nei to-do, con link per chi non ha l'app (`kidboxapp.com/r`) che porta l'invito alla famiglia, sollecito e azione AI. Server e web live dal 01/10/2026; iOS 2.3.9 (144) e Android 2.4.5 con le note del 01/10; l'utente conferma il 21/10 che è tutto pubblicato (la memoria lo dava già pubblicato al 05/10). Disegno: `internal/richieste-disegno.md`, skill `/richieste`.
- **I link esterni sono due**, e il report oggi guarda solo il primo: `/join` (l'invito a una famiglia, contatore `inviteLandingPing`) e `/r` (la richiesta legata a un to-do, che nel frammento porta anche l'invito: «Entra nella famiglia» costruisce il `/join`). Chi entra da `/r` non compare tra le viste di `/join` finché non preme quel bottone.
- **Previsione**: nei 28 giorni dopo l'uscita sugli store, **≥ 10 richieste con link esterno** (`external` non nullo) e **≥ 2 famiglie passate a 2+ membri** entrando da un invito nato da una richiesta (`external.inviteId` con `invites.usedAt`).
- **Misura**: collection group `requests` (esclusi `config/internalUsers` e le famiglie `ZZZ-…`): conteggio per `createdAt` con `external`; per gli ingressi, gli `inviteId` di quelle richieste incrociati con `invites.usedAt` e i membri nuovi della famiglia. Le richieste misurano se stesse anche a metà: `external.openedAt` e `answeredAt`. Il report giornaliero **non** legge `requests`: va fatto a mano (ricetta in `/richieste`).
- **Data**: **02/11/2026** (28 giorni dal 05/10, il limite più tardo di uscita; le note sono del 01/10, quindi la finestra vera scade al più tardi qualche giorno prima: se l'utente ricorda il giorno esatto, correggere qui).
- **Stato al 21/10/2026** (lettura diretta di Firestore): 6 richieste in tutto. 4 sono di prova (famiglie `ZZZ-…`, di cui 3 con link). Le 2 «vere» sono del 01/10, senza link, nella stessa famiglia (una ritirata, una presa). **0 richieste con link esterno da famiglie vere in 20 giorni.** Al ritmo attuale la previsione (≥ 10) è lontanissima e la soglia di falsificazione (< 5) è già quasi certa. Non è ancora un verdetto: la finestra chiude il 02/11. Se a quella data i conteggi sono questi, la scommessa è smentita; nel frattempo si può chiedere se c'è stata qualche spinta (note «Novità», comunicazioni) che faccia conoscere la funzione.
- **Se smentita** (meno di 5 richieste con link): le famiglie continuano a chiedere direttamente su WhatsApp e il problema non era il motivo dell'invito; prima di altro lavoro sulle richieste, chiedere a 2-3 famiglie vere come si sono organizzate l'ultima volta che serviva qualcuno.

### 10. Campagna Google per app, solo Android, ottimizzata su «famiglia creata»
- **Cambio**: prima campagna Google Ads dell'account 868-406-1522, dopo le tre campagne Meta (ferme dal 03/10, 601,82 € spesi in tutto). GA4 collegato a Google Ads il 15/10/2026; conversione importata `family_created` Android, categoria «Registrazione». Una sola campagna: tipo app, Android, Italia, 10 € al giorno (150 € previsti; con la fine prorogata al 07/11, fino a 230 €), messaggio unico «chi prende Marco giovedì?». Niente Meta in parallelo.
- **Previsione** (scritta il 15/10/2026, prima di spendere; le soglie sono stime mie dai dati di Meta, non concordate):
  - **(a)** costo per `family_created` **sotto 5 €**;
  - **(b)** almeno **1 famiglia su 12** tra quelle create dalla campagna arriva a 2+ membri entro 14 giorni dalla creazione.
- **Misura**:
  - (a) spesa e conversioni dell'account Google Ads; controllo incrociato con `family_created` Android di GA4 nelle stesse date;
  - (b) `node scripts/console-daily-report.js --cohorts-from <lunedì della settimana d'avvio>` sulle coorti dell'avvio. Il conteggio delle famiglie 2+ è su tutta la settimana: non si attribuisce alla sola campagna, e va detto.
- **Data**: **21/11/2026**, cioè 14 giorni dopo la fine programmata (07/11), perché le famiglie con 2+ membri maturano dopo.
- **Avvio**: pubblicata il 16/10/2026 con inizio il 16/10 e fine il 30/10; l'utente ha spostato la fine al 07/11 il 19/10 perché per 4 giorni la campagna non ha mostrato annunci. I giorni senza spesa non costano: il tetto resta 10 € al giorno, quindi fino a 230 €.
- **Stato al 19/10**: stato «Idoneo», 0 impressioni, 0 clic. Diagnostica pulita su account, asset, budget, obiettivi e indicatori: Google la dà «in programma». Ipotesi: la conversione `family_created` è nata il 15/10 e senza storia l'ottimizzazione consegna poco. Piano: attendere fino al 21/10; se ancora 0 impressioni, passare **temporaneamente** a «Volume di installazioni» per qualche giorno e tornare alle azioni in-app. Una deviazione così va scritta qui con data, perché per quei giorni si misurano installazioni e non famiglie create.
- **Deviazione, 21/10/2026**: la campagna è già passata a «Volume di installazioni (Tutti gli utenti)» (dichiarato dall'utente il 21/10, screenshot delle impostazioni; il passaggio è di pochi giorni prima, data esatta non registrata). Dal 14 al 20/10 risultano 0 impression, 0 clic, 0 € (Google: impression e installazioni «in programma»), e GA4 non vede costo, clic né sessioni `cpc` negli ultimi 14 giorni. Finché dura questa fase si misurano installazioni, non `family_created`: (a) non è valutabile. Se dopo 48 ore dal passaggio le impression restano a 0, controllare lo stato delle risorse, la fatturazione e la scheda dell'app su Play.
- **Non misurabile se**: meno di 100 € spesi, o meno di 30 `family_created` dalla campagna.
- **Decisione, scritta ora**:
  - (a) e (b) confermate → seconda tornata di 15 giorni, sempre su Android; poi valutare Apple Search Ads per l'iPhone;
  - (a) confermata e (b) smentita → la pubblicità porta famiglie che non invitano: si lavora sull'invito e si pausa;
  - (a) smentita → niente aumento di spesa; si rivedono messaggio e parole, e Google non si riprova prima di aver cambiato l'invito.
- **Se smentita**: (a) la nostra offerta non converte nemmeno su un canale basato sull'intento di chi cerca; (b) il problema non è il canale ma il passaggio da 1 a 2 membri.
- **Limite noto**: 150 € sono pochi per l'ottimizzazione automatica di Google, che di solito vuole decine di conversioni a settimana: i primi giorni sono apprendimento e i dati possono essere rumorosi.

---

### 11. Avvisi proattivi: aiutano o disturbano?
- **Cambio**: motore di regole sul telefono, solo Pro e Max (iOS, commit da `ccc364b8` a quello di questa riga, non ancora pubblicato). Avvisa quando un to-do che scade non l'ha preso nessuno e quando manca la registrazione di una dose, con azioni rapide e preferenze. Disegno nel documento «KidBox — Assistente AI Familiare Proattivo e Multicanale».
- **Previsione** (soglie proposte e confermate dall'utente il 23/10/2026, prima dell'uscita):
  - **(a)** `insight_acted` ÷ `insight_shown` **≥ 30%**: almeno un avviso su tre porta qualcuno a prendere il to-do o registrare la dose;
  - **(b)** `insight_dismissed` ÷ `insight_shown` **≤ 20%**;
  - **(c)** utenti unici con `insight_prefs_changed` e `delivery = off` ÷ utenti unici con `insight_shown` **≤ 10%**.
- **Misura**: `node scripts/ga4-daily-report.js --insights-from <data uscita>`, sezione «Avvisi proattivi — scommessa 11»: stampa i tre rapporti con le soglie e il controllo «non misurabile».
- **Prerequisito, prima dell'uscita**: registrare in GA4 (Amministrazione → Definizioni personalizzate, ambito evento) i parametri `delivery`, `type` e `via` come dimensioni personalizzate. GA4 le applica solo ai dati raccolti dopo: senza `delivery` il rapporto (c) resta non calcolabile per tutta la finestra. Il service account del report è solo Visualizzatore e non può farlo.
- **Data**: **uscita della versione iOS con gli avvisi + 28 giorni**. Il giorno della pubblicazione si scrive qui la data esatta; finché non c'è, la scommessa non conta come aperta.
- **Non misurabile se**: meno di 100 `insight_shown` o meno di 20 utenti unici che ne hanno ricevuto uno.
- **Decisione, scritta ora**:
  - (a), (b) e (c) confermate → porting su Android (passo 9) e regole nuove (passo 10);
  - (a) smentita con (b) e (c) confermate → gli avvisi non disturbano ma non servono: si rivedono regole e orari, non si porta su Android;
  - (b) o (c) smentita → troppo invadenti: il default passa al riepilogo serale prima di qualunque altro lavoro.
- **Se smentita**: un genitore che non ha preso un to-do lo sapeva già (le regole segnalano cose ovvie), oppure il momento dell'avviso è sbagliato.

## Chiuse
- **DEVIAZIONE (20/10/2026): da «Azioni in-app» a «Volume di installazioni», senza costo target.** Dopo 5 giorni a zero impressioni e diagnostica pulita, l'utente ha cambiato l'obiettivo di offerta, con un giorno di anticipo sul piano. Stesso budget (10 €/giorno), Italia, italiano, fine 07/11.
- **Conseguenza per la misura:** finché resta su «Volume di installazioni» la campagna ottimizza le installazioni, non le famiglie create: la previsione (a) sul costo per `family_created` si legge comunque dal conteggio di GA4 (`family_created` Android nelle stesse date), ma non è più ciò che la campagna cerca. Piano: dopo circa 7 giorni e qualche famiglia creata come storia, tornare a «Azioni in-app» e scrivere qui la data. I giorni in «installazioni» vanno dichiarati nel verdetto del 21/11.
### 1. Wizard di onboarding a 2 pagine
- **Cambio**: iOS 2.3.0 / Android 2.2.9 (53), in revisione dal 19/09/2026. Nome, cognome e famiglia in una schermata sola (`setup`), poi `invite` o `join_family`.
- **Previsione**: iniziato → completato passa dal **56% al 75%** per utenti unici sui 28 giorni.
- **Misura**: tabella «Funnel per UTENTI unici» di `ga4-daily-report.js` — utenti con `onboarding_step_shown` contro utenti con `onboarding_completed`.
- **Data**: 15/10/2026 (serve che la release sia in store e adottata: 1-2 settimane).
- **Se smentita**: l'abbandono non era nella lunghezza del wizard; il 4 su 10 che se ne va lo fa per un motivo che non abbiamo ancora misurato, e va cercato parlando con le persone invece che nei numeri.
- **VERDETTO (19/10/2026): smentita per due punti, con la direzione giusta.** Persone uniche GA4, onboarding iniziato → completato: **54%** prima (19/08-18/09, 54 su 100) e **73%** dopo (26/09-18/10, 37 su 51), contro il 75% previsto. Il 56% di partenza scritto qui era leggermente più alto di quello misurato oggi sulla stessa finestra.
- **Cosa impariamo:** accorciare il wizard ha fatto salire il completamento di 19 punti, quindi la lunghezza contava. Resta fuori circa un quarto di chi inizia: il motivo sta altrove. Nessun effetto sul login: chi tenta l'accesso dopo aver visto la schermata era il 41% con le tre schermate illustrative PRIMA del login e il 40% senza. Quindi le schermate illustrative non spostano il login, e rimetterle (o metterle prima del login) non è un'idea da riprovare senza un motivo nuovo.
- **Limiti:** 51 persone nella finestra «dopo», e per una parte di quei giorni convivevano ancora le versioni vecchie del wizard. La differenza di due punti dal 75% è dentro il rumore.


### 9. Il costo per famiglia vera è sceso davvero (decisione sulla pubblicità)
- **Cambio**: nessuna modifica nuova. Si verifica se il calo della settimana del 21/09 è reale. I numeri:
  - fino al 14/09: 538 € di Meta per 10 famiglie vere, cioè 54 € l'una;
  - settimana del 21/09: 38,28 € per 6, cioè 6,38 €.

  Il calo verrebbe dalle modifiche del 19-23/09: wizard a 2 pagine, invito a 7 giorni, invito che sopravvive all'installazione. Condizione: spesa Meta intorno ai 5 € al giorno (Android 2 €, Apple 3 €), stesse campagne a installazioni. Scritta il 02/10/2026, prima della prima coorte misurata (05/10). Contesto: la conversazione sul business del 02/10.
- **Previsione**:
  - **(a)** sulle coorti delle settimane del **05/10, 12/10 e 19/10/2026**, il costo per famiglia vera è **≤ 10 €**;
  - **(b)** almeno **1** famiglia vera con 2+ membri **passa a pagamento** dopo la prova Pro.
- **Misura**: il **02/11/2026** eseguire `node scripts/console-daily-report.js --day 2026-11-01 --cohorts-from 2026-10-05`.
  - **(a)**: riga «Settimane complete dal 2026-10-05 al 2026-10-25 … € per famiglia vera», cioè spesa Meta delle tre settimane ÷ famiglie nate in quelle settimane che hanno 2+ membri.
  - **(b)**: riga «Prova Pro nelle famiglie vere con 2+ membri: finite N · convertite M», con M ≥ 1.
- **Data**: 02/11/2026.
- **Non misurabile se**: per (a), la spesa delle tre settimane è sotto 60 € oppure nascono meno di 40 famiglie vere; per (b), le prove finite in famiglie con 2+ membri sono meno di 3.
- **Decisione, scritta ora**:
  - (a) e (b) confermate → test pubblicitario a 15 € al giorno per 4 settimane, con lo stesso messaggio (le richieste di famiglia) e la stessa misura.
  - (a) confermata e (b) smentita → la spesa resta intorno ai 5 € al giorno e il lavoro va sul valore del Pro per le famiglie con 2+ membri, non sull'acquisizione.
  - (a) smentita → niente aumenti di spesa; prima si rivedono messaggio, pubblico e posizionamenti degli annunci.
- **Se smentita**: (a) il 21/09 era fortuna, e le modifiche all'invito non hanno cambiato quanto costa una famiglia vera; (b) le famiglie che contano non pagano per quello che il Pro offre oggi, come diceva la diagnosi del 28/09 sull'AI che usano in pochi.
- **VERDETTO (09/10/2026): non misurabile.** Le tre campagne Meta sono in pausa dal 03/10, per scelta dell'utente: la spesa delle settimane del 05/10, 12/10 e 19/10 è quasi zero, sotto i 60 € richiesti. A spesa quasi zero le famiglie nuove sono 1-4 a settimana, quindi non si calcola nessun costo. Non è una smentita né una conferma: il costo del 21/09 (6,38 €) resta un dato di una settimana, fortuna compresa.
- **Cosa resta valido:** il comando di misura (`--cohorts-from`) e la decisione per esito. Se le campagne ripartono, si riapre come riga nuova con una data nuova.
- **Chiusa prima della data (02/11) su richiesta dell'utente.** L'utente passa a studiare cosa fanno gli utenti già attivi con le analytics.


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
