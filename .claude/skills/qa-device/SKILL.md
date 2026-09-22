---
name: qa-device
description: Giro di test programmato di KidBox su simulatore iOS, emulatore Android, web app e backend — un settore al giorno su rotazione di 14 giorni, due account di test, esito solo report. Usare quando l'utente chiede il giro di test, la QA del giorno, o di provare un settore specifico.
---

> Il piano completo, con la rotazione e il setup, è
> `internal/qa/PIANO-TEST.md`: **aprilo prima di iniziare**, questa skill è
> l'esecuzione, quello è il piano.

**Esito: solo report, nessun fix automatico.** Se il giro trova un bug, finisce
nel report con file e riga; l'utente decide se aprirlo.

## I due livelli

- **Script** (`e2e/`, client SDK Firebase — gira anche senza Mac acceso): login,
  creazione famiglia, invito → join, famiglia attiva, Storage e contatore,
  rules allow/deny, callable (gating AI sui Free, ricevute con dati finti,
  promemoria to-do), notifiche in coda. **Non può leggere i contenuti cifrati**
  (note, chat, documenti): verifica che i blob esistano e che le regole reggano.
- **UI** (simulatore / emulatore / browser, serve il Mac acceso): i flussi veri
  con cifratura, sempre **cross-client** — A crea su iOS, B legge su Android e
  web, e viceversa. Screenshot a ogni passo.

Due account: **A** proprietario della famiglia, **B** invitato. Credenziali in
`e2e/.env` (gitignored), lette **solo come variabili d'ambiente**: non digito
password nelle UI e non le scrivo nel report. Il primo login di ogni superficie
lo fa l'utente, le sessioni restano.

## Il settore del giorno

Rotazione di 14 giorni nella tabella di `internal/qa/PIANO-TEST.md` (1 login e
nucleo · 2 inviti e join · 3 documenti e Wallet · 4 calendario e to-do · 5 spesa,
note e spese · 6 chat e foto · 7 password · 8 salute · 9 casa, veicoli, animali ·
10 fuori casa · 11 AI e gating · 12 abbonamento · 13 backend · 14 web app e
localizzazione). Se l'utente non dice quale, prendi quello che tocca e dillo.

Build: iOS con `xcodebuild` sul simulatore, Android con Gradle e il **JBR di
Android Studio** via `JAVA_HOME` (il JDK di sistema è Java 8 e fallisce in
configurazione). **Non tocco `version` e `build`** e non committo i client.

## Limiti dichiarati (dirli nel report, non farli passare per successi)

- Apple / Google / Facebook: si verifica solo che il flusso **parta** (2FA e
  sandbox non si completano).
- Push reali, Health Connect vero, acquisti in-app, Alexa con un Echo: fuori dal
  simulatore. Si testano i lati server.
- Il piano fitness/alimentare e l'assistente consumano quota AI vera: usali con
  parsimonia e ricorda che i test dello sviluppatore dominano i costi del mese.
- Nel settore 12 **nessun acquisto reale**: il piano si cambia dalla console admin.

## Chiusura

1. Pulizia: i dati creati nel giro si cancellano, così i giorni restano
   indipendenti.
2. Report in `internal/qa/reports/YYYY-MM-DD-<settore>.md`: passi eseguiti,
   esito, screenshot, **letture Firestore consumate**, anomalie con
   `file:riga` sospetto.
3. In chat solo il riassunto e le anomalie. Un'anomalia che si ripete su più
   giri è un candidato per il registro (`/auto-miglioramento`).
