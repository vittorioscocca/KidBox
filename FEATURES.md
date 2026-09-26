# KidBox — mappa funzionale

> **A cosa serve questo file.** Rispondere a «KidBox questa cosa la fa? e dove?»
> senza aprire il codice. È volutamente **ad alto livello**: niente firme di
> funzione, niente numeri di riga, niente struttura dei package — per quelli ci
> sono gli `ARCHITECTURE.md` di ogni progetto, che restano l'autorità tecnica.
>
> Il [README.md](README.md) racconta perché KidBox esiste e com'è fatto; qui
> c'è cosa fa.

---

## 1. Le superfici

| Progetto | Cos'è | Chi lo pubblica |
|---|---|---|
| `KidBox/` | App iOS (SwiftUI, SwiftData) — il client di riferimento | l'utente |
| `KidBoxAndroid/` | App Android (Compose, Room) — porting a parità di funzioni | l'utente |
| `KidboxWebApp/` | Web app React su `app.kidboxapp.com` | Claude |
| `functions/` | Backend Firebase (64 function, `europe-west1`) | Claude |
| `KidboxConsole/` | Console admin (piani, broadcast, casi, analytics) | Claude |
| `KidboxLanding/` | Sito vetrina `kidboxapp.com` + pagine legali | Claude |

Le tre app condividono **lo stesso schema Firestore**: `families/{familyId}/…`.
Nessun client ha un modello dati suo. Quando una funzione «manca» su Android o
sul web, mancano la UI e la sincronizzazione, non i dati.

---

## 2. Le cinque regole trasversali

Spiegano la maggior parte delle domande su «dove va a finire questa cosa».

**1. Un allegato è un documento.** Le schede che accettano allegati (visita,
esame, cura, veicolo, intervento auto, voce di casa, scadenza di casa, animale,
evento animale) non hanno uno storage proprio: caricano un documento in
**Documenti** e lo marcano con un tag nelle note (`vehicleEvent:{id}`,
`visit:{id}`, `housePayment:{id}`…). Lo stesso file si vede da entrambe le
parti, e cancellarlo da una lo toglie da tutte.

**2. Un importo diventa una spesa.** Una scheda con un costo — intervento auto,
scadenza di casa, visita, esame — genera da sé la voce in **Spese famiglia** e
ne conserva l'id. Regola unica, uguale su iOS e Android: importo > 0 la crea,
importo modificato la aggiorna, importo tolto la fa sparire. Non si scrive
l'importo due volte.

**3. Quasi tutto è cifrato con la chiave di famiglia.** Documenti, note,
password, wallet, chat e foto/video viaggiano cifrati: il backend vede byte, non
contenuti. Conseguenza pratica: le notifiche non possono mostrare l'anteprima di
ciò che è cifrato, e nessuna Cloud Function può leggere quei campi.

**4. Il piano non è un flag.** L'accesso alle funzioni a pagamento sta su tre
presidi (client, rules, server) e la fonte di verità dei piani è `config/plans`,
modificabile dalla console admin — `plans.json` è solo il fallback.

**5. La famiglia attiva vive su `users/{uid}.activeFamilyId`.** Un utente può
appartenere a più famiglie; tutte le letture partono da lì.

---

## 3. Mappa funzionale

Legenda piano: **F** = incluso nel Free · **€** = richiede Pro o Max.

### Nucleo familiare
| Funzione | Cosa fa | Piano |
|---|---|---|
| Famiglia e profili | Un profilo per membro e per figlio; più famiglie per utente, una attiva | F |
| Account | Accesso Apple, Google, Facebook o email+password; email non verificata rifiutata ovunque; «Password dimenticata» e, dal profilo, «Cambia password» solo per gli account email (iOS e Android) | F |
| Inviti | Link di invito + QR affiancato; la chiave di famiglia viaggia avvolta nell'invito | F |
| Onboarding | Wizard di creazione famiglia; checklist «Per iniziare» in Home | F |
| Abbonamento | Free / Pro / Max, per famiglia; acquisto da App Store o Play, ricevute validate lato server | — |

### Organizzazione
| Funzione | Cosa fa | Piano |
|---|---|---|
| Calendario | Eventi di famiglia e **promemoria** (to-do con scadenza); viste Mese, **Giorno e Settimana** con griglia oraria, vista ricordata fra un'apertura e l'altra; eventi **ricorrenti** (giornaliero/settimanale/mensile/annuale) mostrati in ogni ripetizione, con il promemoria che si riarma per la successiva; su iOS e Android anche i **calendari del telefono** (Google, iCloud, Outlook, Exchange) in sola lettura, con «Copia in KidBox» (`DeviceCalendarStore` su EventKit, `DeviceCalendarRepository` su CalendarContract); non sul web; **calendari iscritti da link** (feed ICS di scuola, squadra, festività, Google Calendar) per tutta la famiglia su iOS, Android e web, scaricati dal server ogni 6 ore (`functions/calendarFeeds.js`); «Collega Google / Outlook» guidato (account aggiunto al telefono, niente OAuth) e «Come trovo il link?» per l'indirizzo iCal | F |
| To-do | Liste e cose da fare **di famiglia**, assegnabili, con promemoria; quelli **urgenti** suonano come una sveglia | F |
| Lista della spesa | Condivisa in tempo reale, con «aggiunto da … e quando»; dettabile ad Alexa | F |
| Note | Note condivise, cifrate | F |
| Spese | Voci per categoria, più quelle che nascono da sole dalle altre schede | F |
| Wallet | Biglietti e documenti d'identità con lettura AI dei campi, carte fedeltà con codice a barre | F (la lettura AI consuma i messaggi del piano: sul Free i 5 una tantum) |
| Documenti | Cartelle e categorie, file cifrati, allegati di tutte le altre schede | F |
| Password | Credenziali di famiglia o personali, cifrate, con AutoFill e audit di sicurezza | F |
| Foto e video | Album condivisi, cifrati | F |
| Chat | Chat di famiglia cifrata end-to-end, con vocali e galleria media | F |

### Salute
| Funzione | Cosa fa | Piano |
|---|---|---|
| Visite, esami, vaccini, cure | Storico clinico per ogni membro, con referti allegati | F |
| Cartella clinica | Documento riepilogativo da mostrare al medico | F |
| Apple Health / Health Connect | Passi, battito, pressione, SpO₂, calorie attive, allenamenti, distanza | F |
| Piano Alimentare | Menù settimanale AI da età, peso, obiettivi, referti, allergie | € |
| Piano Fitness | Allenamenti AI, calendario, promemoria, sedute chiuse da Health, storico e report settimanale | € |
| Analisi mensile | Pattern sulla storia sanitaria dei figli, ad app chiusa | € |

### Casa, veicoli, animali
| Funzione | Cosa fa | Piano |
|---|---|---|
| Casa | Elettrodomestici e beni (garanzia, manutenzione) + **scadenze e pagamenti** (bollette, tasse, contratti) | F |
| Veicoli | Schede auto con scadenze **bollo, assicurazione, revisione** e interventi con costo e ricevuta | F |
| Animali | Profili, eventi veterinari, allegati | F |

### Fuori casa
| Funzione | Cosa fa | Piano |
|---|---|---|
| Posizione | Condivisione posizione di famiglia, geofence, condivisioni temporanee | F |
| Viaggi | Itinerari AI giorno per giorno, locali Google, mappa, «Storia e territorio», con foto, spese, to-do e note del viaggio | € |

### Voce e AI
| Funzione | Cosa fa | Piano |
|---|---|---|
| Alexa | Spesa e to-do dettati agli Echo; **solo `it-IT`** | F |
| Assistente di famiglia | Chat AI che conosce i dati e crea eventi, to-do, spese | € (5 messaggi una tantum sul Free) |
| Document Intelligence | Importi una fattura o un referto: l'AI legge e propone azioni | € |
| Mente proattiva | Briefing mattutino, recap settimanale, analisi mensile | € |
| Chat della landing | «Chiedi a KidBox» su kidboxapp.com: risponde sul prodotto a chi non ha l'app. Risposte scritte nel browser, cache, poi Haiku; tetto 1 $/giorno; base di conoscenza in `functions/landingChat/knowledge.md` | — |

### Estensioni iOS
Fuori dall'app, e facili da dimenticare perché non stanno in `Features/`:
AutoFill password, estensione di condivisione, Widget, Controls (Control Center
e schermata di blocco) e Notification Service — quest'ultimo serve a decifrare
il contenuto delle notifiche sul dispositivo.

---

## 4. Trappole note

Cose che sembrano esserci e non ci sono, o che funzionano diversamente da come
verrebbe da pensare. Ognuna è costata almeno una volta.

- **Fra gli interventi auto non esiste il tipo «bollo».** Ci sono tagliando,
  filtro olio, filtro GPL, pasticche, riparazione, gomme, revisione, altro. Il
  bollo è una *scadenza* della scheda veicolo, oppure una tassa in Casa.
- **Alexa è italiano-only.** Il gate è la lingua **effettiva dell'app**, non
  quella del telefono; `en` con regione IT resta italiano. Vale anche per
  landing, note di rilascio e descrizione store.
- **La lista della spesa di Amazon non è scrivibile.** Dal luglio 2024 le List
  Skills sono chiuse: serve il nome di invocazione («Alexa, chiedi a mio box…»).
- **I to-do sono di famiglia, non del figlio.** `childId` si scrive ancora ma
  non filtra più le letture.
- **I promemoria dei to-do sono locali al dispositivo** (alarm), tranne quelli
  serviti dallo scheduler ogni 5 minuti. Il sync non arma nessun alarm.
  Vale anche per gli **urgenti**: un promemoria creato dal web o da un altro
  telefono non fa suonare la sveglia qui.
- **«Urgente» non è un colore: è la sveglia.** Un promemoria (to-do o evento)
  segnato urgente suona anche in silenzioso e in full immersion — AlarmKit su
  iOS, `setAlarmClock` + notifica a schermo intero su Android. Dal browser non
  suona niente: la sveglia è del telefono.
- **Il promemoria di un evento non è mai esistito fino al 22/09/2026**:
  l'interruttore scriveva `reminderMinutes` e nessun client lo leggeva. Ora lo
  arma il dispositivo che salva l'evento.
- **Le notifiche si congelano nella lingua della schedulazione**: su iOS non
  c'è un hook alla consegna.
- **La posizione è divisa in due**: `locations/{uid}` è lo stato, le coordinate
  live stanno in `live/current`.
- **La riga «Distanza» del Piano Fitness è dichiarata a Google Play**: deve
  restare visibile anche a zero, altrimenti `READ_DISTANCE` diventa
  indimostrabile. Nel Piano Alimentare invece non deve comparire.

---

## 5. Backend, in breve

- **66 function**, tutte in `europe-west1`. Tre sole HTTP: `alexaSkill`,
  `inviteLandingPing` (contatore anonimo della pagina d'invito `/join`, il
  passaggio del funnel che GA4 non vede perché parte solo dopo il consenso) e
  `landingChat` (la chat «Chiedi a KidBox» della landing, dietro il rewrite
  `/api/chat`); le altre sono callable o trigger Firestore.
- **AI**: una sola callable `askAI` con un `purpose` per funzione
  (`clinicalRecord`, `mealPlan`, `fitnessPlan`, `fitnessAdjust`,
  `fitnessCopilot`, …). Due modelli: Sonnet per il ragionamento, Haiku dove
  basta. Il consumo si conta in «messaggi», contatore condiviso dalla famiglia.
- **Scheduler**: posizioni temporanee scadute e promemoria to-do ogni 5 minuti,
  biglietti in scadenza ogni ora, allineamento piani e garbage collection di
  notte.
- **Notifiche**: un trigger per tipo (documento, chat, foto, visita, evento,
  spesa, to-do assegnato, spesa, articolo spesa, nota, biglietto, carta fedeltà).
- **App Check** su tutti e quattro i client; enforcement ancora spento finché
  l'adozione non è alta.

---

## 6. Tenerlo vivo

Questo file invecchia come il README se nessuno lo tocca. La regola minima:
**quando una funzione nasce, muore o cambia piano, si aggiorna la riga qui** —
non serve altro. I dettagli tecnici continuano a stare negli `ARCHITECTURE.md`,
e le trappole della sezione 4 si aggiungono solo dopo che una cosa è costata
davvero tempo: un elenco di ipotesi non serve a nessuno.
