# KidBox — guida per Claude Code

App per famiglie (iOS, Android, web) con backend Firebase. Repo unico per
tutto tranne Android: `KidBoxAndroid/` è un repo separato (remote
`vittorioscocca/KidBoxAndroid`) che da qui compare come cartella non tracciata;
i suoi commit si vedono solo con `git -C KidBoxAndroid`.

## Mappa

- `KidBox/` iOS (SwiftUI, String Catalog con sorgente IT — le chiavi sono i letterali italiani)
- `KidBoxAndroid/` Android (Compose; JDK: usare il JBR di Android Studio via `JAVA_HOME`)
- `KidboxWebApp/` web app (`app.kidboxapp.com`) · `KidboxLanding/` sito e blog · `KidboxConsole/` console admin
- `functions/` Cloud Functions (`ARCHITECTURE.md` dentro) · `firestore.rules` (+ `.next`, `firestore-tests/`)
- `scripts/` report analytics e utilità · `internal/` procedure e diagnosi · `FEATURES.md` mappa funzionale

**Prima di cercare col grep, leggere `FEATURES.md`**: il README descrive l'MVP
2025 ed è superato.

## Skill di progetto (`.claude/skills/`)

- `/deploy-functions` — controlli, deploy scopato, verifica, commit per path
- `/report-giornaliero` — routine analytics (GA4, console, store, costi); accessi in `internal/analytics-accessi.md`
- `/gating-pro` — feature Pro/Max: i tre presidi server/service/view
- `/auto-miglioramento` — giro di miglioramento: chiude le scommesse scadute,
  propone tre candidati con previsione falsificabile, si ferma; registro in
  `internal/auto-miglioramento/registro.md`
- `/localizzazione` — stringhe in it/en/fr/es sulle quattro superfici e le trappole che rendono il buco invisibile
- `/porting-android` — portare una funzione da iOS o correggere un bug Android senza ripagare le trappole note
- `/release-client` — note «Novità» in quattro lingue, schede store, dichiarazioni Play; build e versione restano dell'utente
- `/triage-ticket` — ticket nuovi da Firestore, causa e file; solo report (il task pianificato rimanda qui)
- `/qa-device` — giro di test del giorno su quattro superfici; piano in `internal/qa/PIANO-TEST.md`
- `/rules-change` — regole Firestore: i due file, la suite, la verifica differenziale, cosa guardare dopo
- `/piani` — riallineamento del listino dopo una modifica dalla console admin
- `/notifiche` — push, locali, promemoria, lingua e deep link: tre strade diverse con trappole diverse
- `/letture-firestore` — misurare letture e costi prima di ottimizzare; i tranelli della metrica
- `/landing-blog` — articoli, generatori, footer e sitemap della landing; regole editoriali
- `/alexa` — accoppiamento, nome di invocazione (sei punti), gate di lingua; il backend non si tocca
- `/cifratura` — la chiave di famiglia: dove vive, come arriva a un membro, cosa il server non può fare
- `/ai` — purpose, modello, unità scalate e quote; le trappole di copilota, cache e max_tokens

## Divisione del lavoro

- Claude deploya **e committa** functions, rules, console, landing e web app;
  il `git push` è sempre dell'utente (da qui non funziona).
- iOS e Android: Claude scrive e compila, l'utente committa e pubblica. Non
  toccare mai build number e versione, nemmeno per «rimetterli a posto».
- Commit per path, mai `git add -A` (l'albero contiene lavoro dell'utente).
  Messaggi in italiano, imperativi; **mai** `Co-Authored-By`.
- Cancellazioni Firestore: comando pronto per l'utente, non eseguirlo.
- Routine di analisi (ticket, analytics): solo report, nessun fix automatico.

## Segreti

Nessun segreto nel repo. Portachiavi macOS (account `kidbox`) o impersonazione
di service account con `gcloud`: la mappa completa è in
`internal/analytics-accessi.md`.
