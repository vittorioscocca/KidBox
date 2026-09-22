---
name: auto-miglioramento
description: Ciclo ricorsivo di miglioramento di KidBox — chiude le scommesse scadute, legge i segnali, propone tre candidati ordinati con previsione falsificabile, e ogni 4 giri riscrive le proprie regole. Non modifica niente da sola: espone e si ferma. Usare quando l'utente chiede «cosa faccio adesso», il giro settimanale, di chiudere un esperimento, o dice «auto-miglioramento».
---

> Stato persistente: `internal/auto-miglioramento/registro.md`. **La skill senza
> il registro non vale niente**: il valore non è la lista di idee (quella la
> genera chiunque), è il confronto tra quello che avevi previsto e quello che
> è successo. Se il registro non esiste o è vuoto, il primo giro lo ricostruisce
> dalle scommesse già aperte nel progetto.

Sei l'agente che fa girare il ciclo di miglioramento di KidBox. **Non modifichi
niente in questo giro**: chiudi i conti aperti, guardi i segnali, proponi tre
candidati e ti fermi. Le modifiche partono solo se l'utente ne sceglie una, e
allora vale la divisione del lavoro di `CLAUDE.md` (server e web li fai e
committi tu, iOS e Android li pubblica l'utente).

## Il vincolo che regge tutto

Un ciclo che propone, esegue e poi giudica se stesso produce sempre un verdetto
positivo: è una macchina per razionalizzare. L'unica cosa che lo impedisce è che
**la previsione sia scritta, con un numero e una data, prima di toccare il
codice**. Il verdetto deve poterlo calcolare un estraneo leggendo solo il
registro e il report del giorno. Se per dire se è andata bene serve
interpretare, la previsione era scritta male: verdetto «non misurabile», e la
colpa è della previsione, non del mondo.

## Passo 1 — chiudi le scommesse scadute (sempre per primo)

Apri il registro, prendi le righe **aperte con data di misura ≤ oggi** e per
ognuna scrivi un verdetto:

- **confermata** — il numero previsto è stato raggiunto.
- **smentita** — non è stato raggiunto. Non è un fallimento del ciclo: è
  l'unica cosa che il ciclo produce di valore. Scrivi *perché* pensi sia andata
  così, come ipotesi, e passa oltre.
- **non misurabile** — il dato non c'è, la release non è stata adottata, il
  numero è troppo piccolo per distinguerlo dal rumore. Scrivi cosa mancava.
  Tre «non misurabile» di fila sulla stessa area significano che quell'area non
  è misurabile con questi volumi: smetti di scommetterci sopra e dillo.

Non spostare una data di misura in avanti per salvare una scommessa. Se la
release è in revisione da due settimane, il verdetto è «non misurabile, release
non adottata», e la scommessa si riapre come nuova riga con data nuova.

**Se questo passo non è il primo, il ciclo diventa un generatore di idee che non
impara.** Nessun candidato nuovo prima di aver chiuso i conti.

## Passo 2 — osserva

1. **Numeri**: esegui la skill `/report-giornaliero` (otto script, sola
   lettura) e leggila con le sue 26 regole. Non duplicarle qui.
2. **Debito tecnico e segnali che nessuno legge insieme** (in bash, da
   `/Users/vscocca/KidBox`):
   - crash e ANR freschi + recensioni sotto le 4 stelle → già nel report Play;
   - ticket `new` e `crash_reports` → già nel report console;
   - `git status --short` e `git log --oneline -15` per capire cosa è in volo;
   - `diff firestore.rules firestore.rules.next` — se il `.next` contiene regole
     pronte da settimane, è debito che scade;
   - `gcloud functions logs read --region europe-west1 --limit 50 --min-log-level ERROR`
     se il progetto lo consente, per errori server che nessun report mostra.
3. **Stato delle release**: cosa è in revisione, cosa è in store, da quanto.
   Quasi ogni «non misurabile» del passo 1 viene da qui.

## Passo 3 — tira fuori i candidati (tre fonti, non una)

- **Dai numeri**: il passo del funnel che perde di più in valore assoluto, non
  in percentuale. Con questi volumi «−40%» può essere due persone.
- **Dal debito**: crash ripetuto su più utenti distinti, regola pronta e non
  deployata, ticket che si ripete, costo che cresce verso il free tier.
- **Dal backlog prodotto** (memoria `project_backlog_prodotto`): è già ordinato
  e contiene anche un elenco di cose da **non** fare. Rispettalo: se proponi una
  cosa che sta nel «non fare», devi dire quale dato è cambiato.

## Passo 4 — ordina con il criterio del progetto

> *Fa aprire l'app ogni giorno, o fa entrare il secondo membro?*

Tutto il resto scende sotto, comprese le feature belle. Una correzione di debito
sale sopra il criterio solo se sta perdendo utenti già acquisiti (crash,
espulsioni, notifiche che non arrivano).

## Passo 5 — proponi tre candidati e fermati

Per ognuno, in cinque righe:

    **Candidato** — cosa si cambia, in una riga.
    Perché ora — il dato o il segnale che lo fa salire oggi.
    Previsione — <numero> entro il <data>, misurato con <fonte esatta>.
    Costo — dove si tocca (iOS / Android / functions / web / landing) e chi pubblica.
    Se è smentita — cosa impariamo. Se la risposta è «niente», scarta il candidato.

Poi **fermati e aspetta**. Non implementare, non deployare, non committare, non
aprire file per «preparare il terreno». Questa skill espone, l'utente decide.

## Passo 6 — solo se l'utente sceglie

Esegui nel perimetro di `CLAUDE.md`, con la skill giusta (`/deploy-functions`
per il backend, `/gating-pro` se la feature è Pro/Max), e **prima di tutto**
scrivi la riga nel registro con la previsione. La previsione scritta dopo il
codice non vale: a quel punto la conosci già.

## Passo 7 — il meta-passo, ogni 4 giri (qui sta la ricorsione)

Conta nel registro le scommesse chiuse negli ultimi 4 giri e guarda i rapporti:

- **Zero smentite** → le previsioni sono scritte in modo infalsificabile. È il
  guasto più probabile e il più difficile da vedere: un ciclo che ha sempre
  ragione non sta misurando niente. Riscrivi le previsioni più strette.
- **Molte «non misurabili»** → stai scommettendo su cose che con 2-6 DAU non si
  vedono. Sposta le previsioni su numeri cumulativi (famiglie con 2+ membri) o
  su presenza/assenza, o su risposte di persone vere.
- **Una diagnosi sbagliata ripetuta** → è una regola di lettura mancante:
  aggiungila in fondo all'elenco della skill `report-giornaliero`. Quelle 26
  regole sono nate esattamente così, per incidente; qui si fa apposta.

Cosa può riscrivere il meta-passo: le regole di `report-giornaliero`, questa
skill, i file di memoria del progetto, `FEATURES.md`. **Mai cancellare una
regola**: spostala in fondo sotto «Regole ritirate» con la data e il perché —
una regola tolta senza traccia torna come errore sei mesi dopo. Le modifiche al
meta-passo si presentano all'utente come diff, non si applicano in silenzio.

## Cosa non fa questa skill

- Non modifica codice, non deploya, non committa, non cancella niente su
  Firestore (per le cancellazioni: comando pronto per l'utente, mai eseguito).
- Non tocca build number e versione dei client, nemmeno per «rimetterli a posto».
- Non chiama «trend» una differenza di 2-3 unità, non confonde le tre scale di
  misura (GA4, rollup `metrics`, Auth) e non legge un solo giorno: valgono tutte
  le regole di `report-giornaliero`.
- Non propone più di tre candidati. Una lista di dieci è un modo elegante di non
  decidere.
