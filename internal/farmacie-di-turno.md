# Farmacie di turno (Pro e Max)

Avviata il 26/10/2026. Backend in `functions/pharmacies/`; client iOS
(`Features/Pharmacies/`) e Android (`ui/screens/pharmacies/`) con riquadro in
Salute e scorciatoia in Home (gruppo «Famiglia & Salute»); i Free vedono la
scheda che spiega il servizio. Il comune è quello delle Notizie
(`NewsFamilyStore`), e «Cambia» apre le loro impostazioni. Web app, Mac/iPad
(barra laterale) e testi del listino piani: ancora da fare.

## Principio

Il dato viene da una **fonte ufficiale** (Federfarma, Ordine, ASL, Comune), mai
da un aggregatore presentato come ufficiale. L'AI paga **una volta**: trova la
pagina e scrive una **regola** di lettura; poi il codice rilegge la pagina ogni
poche ore, gratis. Se la regola smette di funzionare il dato si nasconde e resta
il link alla fonte.

**L'utente può sempre indicare a mano il sito**, indipendentemente da cosa ha
trovato l'AI (`setPharmacySource`). Vale solo per la sua famiglia e ha la
precedenza; non diventa mai la fonte condivisa di una zona (un link sbagliato
contaminerebbe tutti). `url: null` torna alla fonte automatica.

## Funzioni (europe-west1)

| Funzione | Cosa fa | Costo |
|---|---|---|
| `getPharmacies` | stato, fonte e turni del comune della famiglia; rilegge subito se i dati hanno > 6 h | 0 |
| `findPharmacySource` | l'AI cerca la pagina ufficiale (ricerca web), poi scrive e prova la regola | stima 15 messaggi, conguagliata (tetto 16) |
| `setPharmacySource` | sito indicato a mano: prima prova le regole già note per quell'host (gratis), poi l'AI | 0 o ≤ 6 messaggi |
| `refreshPharmacyShifts` | ogni ora, rilegge le fonti dovute **lette negli ultimi 7 giorni** | 0 |

Il piano si controlla dalla quota (`period === "lifetime"` = Free →
`permission-denied`), come Notizie: vedi `/gating-pro`. I tentativi AI sono 4 al
giorno per famiglia; tetto globale `dailyBudgetUsd` (3 $) in `pharmacy_usage`.
Parametri in `config/pharmacies` (nessun deploy per cambiarli).

## Dati (solo server, nessuna rule)

- `pharmacy_sources/{key}` fonte, regola, affidabilità, `nextFetchAtMs`, `lastReadAtMs`
- `pharmacy_shifts/{key}` turni letti (da ieri in poi, max 1800 righe)
- `pharmacy_family/{fid}` scelta manuale, tentativi del giorno
- `pharmacy_usage/{giorno}` spesa AI; il mese in `ai_costs/{mese}.pharmacyCostUsd`

`key`: `lombardia`, `torino` (incluse nel codice, `builtin.js`), `IT_regione_comune`
(trovata dall'AI, condivisa), `manual_{familyId}`. La cancellazione di una
famiglia toglie `pharmacy_family` e le due `manual_*`.

## Affidabilità mostrata all'utente

`verified` (scritta da noi) · `ai` (ente ufficiale, confidenza alta, regola
plausibile) · `uncertain` (aggregatore, confidenza bassa, o regola non provata:
va mostrato «verifica») · `manual` (scelta dall'utente). `readable: false` =
solo link alla fonte (PDF, immagine, pagina caricata da script).

## Regole di lettura (`rules.js`)

JSON o HTML con selettori CSS; l'AI le scrive, `sanitizeRule` le ripulisce e
`plausible` le boccia se non producono ≥ 3 righe con indirizzo e almeno una data
nella finestra. Una fonte con 3 letture fallite di fila passa a `error`.
Le date senza anno prendono quello corrente (il successivo se già passate da
> 40 giorni).

## Fonti incluse (pilota del 26/10/2026)

- **Lombardia**: JSON di `farmacia-aperta.eu/ajax/farmacie` (Federfarma
  Lombardia). Solo «oggi». `robots.txt` aperto. Copre la regione.
- **Torino**: HTML di `federfarmatorino.it/farmacie/farmacie-di-turno/`, 5
  giorni. Copre solo i comuni nell'elenco (le circoscrizioni di Torino città
  risultavano senza dati: lì scatta la ricerca AI).
- **Roma**: l'endpoint XML è vietato dal `robots.txt` (`Disallow: /`): serve un
  accordo con Federfarma Roma, nel frattempo ricerca AI o sito a mano.
- **Napoli, Salerno**: pagina dei turni non trovata nel pilota.

**Da fare prima di allargare:** leggere i termini d'uso di Federfarma (il pilota
ha guardato solo `robots.txt`) e chiedere un permesso scritto.

## Turni in immagine o PDF (ASL Benevento, 26/10/2026)

Molti enti pubblicano ogni mese una tabella come PNG. La regola `vision`
(`{"type":"vision","imageSelector":"…"}`, `vision.js`) fa leggere le immagini
all'AI con la vista **solo quando cambiano**: la fonte conserva l'impronta
(`imageHash`) e ogni 12 ore lo scheduler scarica la pagina e le immagini (circa
120 KB) ma chiama l'AI solo se l'impronta è nuova. Quindi circa una lettura al
mese per fonte, per tutte le famiglie che la usano; costo registrato in
`pharmacy_usage.byKind.vision` e `ai_costs.pharmacyCostUsd`.
L'AI restituisce intervalli («dal 04 ott al 10 ott») che il codice espande in un
turno per giorno, con `service` (`night`, `afternoon`, `holiday`,
`afternoon_holiday`, `h24`). La lettura inline di `getPharmacies` non chiama mai
l'AI: se il mese cambia e l'immagine nuova non è ancora stata letta, resta
«nessun turno aggiornato per oggi» col link, mai un elenco vecchio.
**PDF**: l'AI li legge come documento (anche quelli scansionati). La regola
`vision` ha tre modi di trovare i file: `self` (l'indirizzo stesso è un PDF o
un'immagine), `imageSelector` (immagini nella pagina), `linkSelector` (link a
PDF o immagini nella pagina; allo scheletro che vede l'AI restano solo i link
che portano a un documento). Fino a 3 file per fonte, PDF ≤ 8 MB e ≤ 25 pagine,
immagini ≤ 4 MB.

**Download robusto** (`fetch.js`): il tipo di file si riconosce dai primi byte e
non dall'intestazione (un PDF servito come `application/octet-stream` si legge
lo stesso); codifica del testo letta da `charset` o dal `<meta>` (i siti in
windows-1252 non rompono più gli accenti); le richieste passeggere (rete, 429,
5xx) si ripetono due volte; certificato intermedio mancante recuperato dall'AIA;
motivi distinti per «bloccato» (401/403/406/451), «non trovato», «troppo
grande», «tipo non supportato».

**Il perché all'utente**: `setPharmacySource` e `findPharmacySource` restituiscono
`why` (`outdated` = ho trovato turni ma di un altro periodo, `too-large`,
`too-many-pages`, `blocked`, `not-found`, `unsupported`, `unreachable`, `no-data`)
e i client lo spiegano in parole.

Limiti noti: pagine che caricano i turni con JavaScript (la pagina scaricata è
vuota), PDF dietro un'altra pagina intermedia (due salti), fogli di calcolo e
archivi: cadono in «non riesco a leggere questo sito» col link.

## Trappole già incontrate

- **Certificato intermedio mancante (ASL Benevento, 26/10/2026).** Molti siti
  pubblici inviano solo il certificato del sito: `curl` e i browser recuperano
  l'intermedio dall'indirizzo AIA, Node no (`UNABLE_TO_VERIFY_LEAF_SIGNATURE`) e
  l'utente vedeva un errore generico. `fetch.js` lo recupera da sé e riprova una
  volta; la verifica TLS resta attiva (certificati scaduti, autofirmati o di un
  altro nome vengono rifiutati). Lo stesso errore non è mai «sito spento»: prova
  prima con `curl -v`.
- **Una pagina può non contenere i turni.** La pagina ASL Benevento ha solo
  orari ordinari e una nota (e testo spam nascosto in fondo): la regola non
  esce plausibile e l'utente vede «non riesco a leggere questo sito» col link.

- `node-fetch` v3 dà il corpo come stream Node: per leggere a pezzi con
  `getReader()` serve il `fetch` globale di Node 22.
- La ricerca web di Claude restituisce soprattutto aggregatori: l'URL scelto
  deve essere fra i risultati veri (come per le Notizie) e va marcato
  `official: false` se non è dell'ente.
- Il provare l'AI richiede la chiave `ANTHROPIC_API_KEY`: in emulatore non c'è,
  quindi `findPharmacySource` e la generazione della regola si provano solo dopo
  il deploy, con un account Pro.
