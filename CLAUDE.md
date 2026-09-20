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
