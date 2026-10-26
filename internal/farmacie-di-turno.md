# Farmacie di turno (Pro e Max)

Avviata il 26/10/2026. Backend in `functions/pharmacies/`, client da fare
(riquadro in Salute + scorciatoia in Home, solo Pro/Max; i Free vedono la scheda
che spiega il servizio).

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

## Trappole già incontrate

- `node-fetch` v3 dà il corpo come stream Node: per leggere a pezzi con
  `getReader()` serve il `fetch` globale di Node 22.
- La ricerca web di Claude restituisce soprattutto aggregatori: l'URL scelto
  deve essere fra i risultati veri (come per le Notizie) e va marcato
  `official: false` se non è dell'ente.
- Il provare l'AI richiede la chiave `ANTHROPIC_API_KEY`: in emulatore non c'è,
  quindi `findPharmacySource` e la generazione della regola si provano solo dopo
  il deploy, con un account Pro.
