# Piano test programmati KidBox

Obiettivo: un giro di test al giorno su un settore diverso, sulle quattro superfici
(iOS simulatore, Android emulatore, web app, backend), con due account di test
(A = proprietario famiglia, B = invitato). Esito: **solo report**, nessun fix automatico.

## 0. Setup (una volta)

| Cosa | Chi |
|---|---|
| Due account email/password + famiglia di test dedicata («QA KidBox») | utente |
| `e2e/.env` con `QA_A_EMAIL`, `QA_A_PASSWORD`, `QA_B_EMAIL`, `QA_B_PASSWORD` (gitignored; Claude lo legge solo come variabile) | utente |
| Primo login manuale di A su iOS sim, di B su Android emu, di entrambi sulla web app (le sessioni restano; Claude non digita password nelle UI) | utente |
| Cartella `e2e/`: helper client SDK Firebase, suite per settore, runner, report | Claude |
| Build iOS (xcodebuild → simulatore) e Android (gradle con JBR) automatizzate | Claude |
| Verifica che l'app iOS parta nel simulatore con login email/password (nota in memoria: prima non partiva) | Claude, giorno 1 |

## 1. Due livelli

**Script (client SDK, gira anche in cloud):** login email/password, creazione famiglia, invito → join,
famiglia attiva, upload/download su Storage, contatore storage, rules (allow/deny), Functions
callable (askAI gating Free, validazione ricevute con dati finti, promemoria to-do), notifiche in coda.
Non può leggere i contenuti cifrati (note, chat, documenti): verifica solo che i blob esistano e le
regole reggano.

**UI (simulatore/emulatore/browser, serve il Mac acceso):** i flussi veri con cifratura,
sempre **cross-client**: A crea su iOS, B legge su Android e web (e viceversa). Screenshot a ogni passo.

## 2. Rotazione (ciclo 14 giorni)

| G | Settore | Cosa si prova |
|---|---|---|
| 1 | Login e nucleo | email/password su 3 client; Apple/Google/Facebook: solo che il flusso parta; profili, foto profilo, foto famiglia, più famiglie / famiglia attiva |
| 2 | Inviti e join | link + QR, join di B, chiave di famiglia arrivata (B legge una nota cifrata di A), cancellazione famiglia vuota dell'onboarding, uscita e re-join; revoca di B e poi B si rinomina: la famiglia NON gli ricompare; `node scripts/membership-index-audit.js` a zero prima e dopo |
| 3 | Documenti + Wallet | upload PDF/immagine, cartelle, download e apertura su altro client, biglietto con lettura AI, carta fedeltà, contatore storage |
| 4 | Calendario + To-do | eventi mese/giorno/settimana, to-do assegnato a B con promemoria (`remindSentAt` esplicito), deep link notifica Android |
| 5 | Spesa + Note + Spese | tempo reale a due client, «aggiunto da», nota cifrata, spesa da altra scheda |
| 6 | Chat + Foto/video | messaggi E2E, vocale, album, anteprima notifica; Android: scroll di una chat con foto/video/link senza scatti né placeholder al rientro, foto dentro una risposta nitida |
| 7 | Password | credenziali famiglia/personali, AutoFill iOS, audit |
| 8 | Salute | visite/esami/vaccini con referto, cartella clinica, Health (dati simulati dove possibile) |
| 9 | Casa, veicoli, animali | scadenze, pagamenti, interventi con ricevuta, notifiche scadenza |
| 10 | Fuori casa | posizione simulata (sim location), geofence, condivisione temporanea, viaggio AI |
| 11 | AI e gating | assistente (5 msg bonus Free), mealPlan bloccato su Free, Document Intelligence, `isAIAccessible` coerente con `config/plans`; Android: risalire durante una risposta AI non riporta in fondo, inviare sì (chat a lista rovesciata e normale) |
| 12 | Abbonamento | gating Free/Pro/Max cambiando piano da console admin; **nessun acquisto reale** |
| 13 | Backend | `firestore-tests` rules, Functions in emulatore, scheduler (`jobs list`: tutti `ENABLED`), App Check, alert Monitoring silenziosi, DENY delle rules/ora nel riferimento 0-6, audit indice famiglie a zero |
| 14 | Web app + localizzazione | parità con iOS sui settori 1–7, screenshot EN/FR/ES e stringhe non tradotte |

Ogni giorno chiude con pulizia della famiglia di test (dati creati → cancellati), così i giorni sono indipendenti.

## 3. Report

`internal/qa/reports/YYYY-MM-DD-<settore>.md`: passi eseguiti, esito, screenshot, letture Firestore
consumate, anomalie con file:riga sospetto. Inviato in chat; l'utente decide se aprire un fix.

## 4. Limiti dichiarati

- Apple/Google/Facebook: non si completano (2FA, sandbox); si verifica solo l'avvio del flusso.
- Push reali, Health Connect vero, acquisti in-app, Alexa con Echo: fuori dal simulatore; si testano i lati server.
- I test UI richiedono il Mac acceso; in cloud gira solo il livello script.
- Le build le prepara Claude ma non tocca `version`/`build` e non committa i client.

## 5. Schedulazione

Routine locale ogni mattina (ora da decidere) che esegue il settore del giorno; il livello script
anche in cloud, come rete di sicurezza se il Mac è spento.
