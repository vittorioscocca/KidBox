# KidBox

**L'app che tiene insieme tutto quello che riguarda una famiglia.**
Salute, documenti, scadenze, spese, posizione, password e viaggi in un posto
solo — condivisi fra i membri, cifrati, con agenti AI che lavorano anche ad app
chiusa.

Pubblicata su App Store e Google Play, con web app su
[app.kidboxapp.com](https://app.kidboxapp.com).

> 🗺️ **Cosa fa KidBox, funzione per funzione: [FEATURES.md](FEATURES.md).**
> È la mappa funzionale — cosa esiste, su quali client, con quale piano. Questo
> README dice perché esiste e com'è fatto; per la struttura tecnica di ogni
> progetto ci sono gli `ARCHITECTURE.md`.

---

## Visione

Rendere visibile, condiviso e neutro il carico mentale di una famiglia, così che
nessuno debba essere l'unico a ricordare.

Il progetto è nato attorno ai figli piccoli — routine, impegni, dimenticanze — e
si è allargato a tutto ciò che una famiglia gestisce insieme: la salute di
grandi e piccoli, la casa, le auto, gli animali, i soldi, i viaggi. Il centro non
è più solo il bambino: è **il nucleo**, e ogni dato appartiene alla famiglia
prima che a chi l'ha inserito.

## Principi

- **Condiviso per default** — un dato inserito da uno è di tutti; l'attribuzione
  serve a sapere chi e quando, non a limitare l'accesso.
- **Local-first** — l'app funziona offline e sincronizza quando può.
- **Cifrato dove conta** — documenti, note, password, wallet, chat e foto
  viaggiano cifrati con la chiave di famiglia: il backend vede byte, non
  contenuti.
- **L'AI agisce, non conversa** — gli agenti creano eventi, spese e promemoria
  veri; una risposta che resta nella chat è una risposta a metà.
- **Bassa frizione** — meno parole, meno passaggi, niente punteggi né giudizi.
- **Parità fra i client** — iOS, Android e web condividono lo stesso schema
  Firestore. Quando una funzione manca su un client, mancano UI e sync, mai i
  dati.

## Superfici

| Cartella | Cos'è |
|---|---|
| `KidBox/` | App iOS — SwiftUI, SwiftData, più le estensioni (AutoFill, condivisione, Widget, Controls, Notification Service) |
| `KidBoxAndroid/` | App Android — Compose, Room, Hilt |
| `KidboxWebApp/` | Web app React |
| `functions/` | Backend Firebase — callable, trigger Firestore e scheduler in `europe-west1` |
| `KidboxConsole/` | Console admin — piani, broadcast, casi di supporto, analytics |
| `KidboxLanding/` | Sito vetrina e pagine legali |
| `firestore.rules`, `firestore-tests/` | Regole di sicurezza e loro test |
| `internal/` | Note di lavoro non pubblicate |
| `docs/` | Pagine legali pubblicate (privacy, termini, supporto, eliminazione dati) |

## Come sta insieme

- **Dati**: Firestore, tutto sotto `families/{familyId}/…`. Un utente può stare
  in più famiglie; quella attiva vive su `users/{uid}.activeFamilyId`.
- **Persistenza locale**: SwiftData su iOS, Room su Android — l'app legge dal
  locale e i listener realtime riconciliano.
- **Conflitti**: last-write-wins sulle entità semplici.
- **Auth**: Sign in with Apple, Google, email e password. Facebook è
  implementato ma spento dietro un flag remoto.
- **Abbonamenti**: Free, Pro e Max, per famiglia. Acquisto da App Store o Google
  Play, ricevute validate lato server; la definizione dei piani sta su
  `config/plans` ed è modificabile dalla console.
- **AI**: una sola callable con un `purpose` per funzione, due modelli Claude
  (Sonnet dove serve ragionare, Haiku dove basta), consumo contato in messaggi
  condivisi dalla famiglia.
- **Protezione**: App Check su tutti e quattro i client, regole Firestore in
  default-deny.

## Cosa KidBox non vuole essere

- Un'app di messaggistica: la chat serve a parlare **di** quello che c'è nella
  box, non a sostituire WhatsApp.
- Uno strumento per dispute legali sull'affidamento.
- Una fonte di consigli medici o genitoriali: gli agenti AI riassumono e
  organizzano i dati della famiglia, e lo dichiarano ogni volta.
- Un gioco a punti sulle responsabilità di casa.

## Stato

In produzione su App Store, Google Play e web. Repo privato.
