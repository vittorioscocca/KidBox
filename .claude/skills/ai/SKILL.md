---
name: ai
description: Le funzioni AI di KidBox — purpose, modello, unità scalate, quote e le trappole già pagate. Usare quando si aggiunge o si modifica una funzione AI (assistente, piani, cartella clinica, viaggi, analisi documenti, chat della landing), quando si cambia modello o max_tokens, o quando l'utente dice «l'AI non applica le modifiche», «costa troppo», «i Free ci arrivano?».
---

Tutto passa dalla callable **`askAI`** (`functions/index.js`), discriminata dal
`purpose`. Fuori da lì: `generateTravelPlan` (callable sua), Document
Intelligence (immagini), la chat della landing (`landingChat`, funzione HTTP
separata, senza login) e le **Notizie** (`functions/news/`: Sonnet 5.5 con la
ricerca web, costo in dollari convertito in messaggi sullo stesso contatore →
`/notizie`).

`purpose` noti: `clinicalRecord`, `mealPlan`, `fitnessPlan`, `fitnessAdjust`,
`fitnessCopilot`, `familyAgent` (l'assistente unico, dal 02/10/2026: serve
**solo** a riconoscerlo in log e analytics, modello e unità sono quelli della
chat). Le build vecchie e la compattazione non ne passano nessuno.

## Due assi indipendenti, da non confondere

Il codice lo dice, ma è la cosa che si sbaglia per prima:

- **`sonnetGeneration`** = `clinicalRecord || fitnessPlan || fitnessAssist` →
  `claude-sonnet-5`. Tutto il resto gira su `claude-haiku-4-5-20251001`.
  **Il piano alimentare resta su Haiku**: è scrittura, costa ~3× meno ed è più
  veloce. *(Nota: il commento a ~riga 2424 dice il contrario ed è rimasto
  indietro — vale il codice.)*
- **`oneShotGeneration`** = `clinicalRecord || mealPlan || fitnessPlan` →
  niente prompt caching: una chiamata mai riletta pagherebbe solo il write a
  1,25× senza nessun read successivo.

**Il modello dipende dal `purpose`, mai dal piano.** Un Pro e un Free che usano
la stessa funzione parlano con lo stesso modello: cambia quanto possono usarla.

## Unità scalate (non è «un messaggio = una chiamata»)

| Caso | Unità |
|---|---|
| chat normale | dalla dimensione del payload |
| `clinicalRecord` | `max(3, payload)` |
| `mealPlan` | `max(5, payload)` |
| `fitnessPlan` | **`3 × max(5, payload)`** = 15 di norma |
| `fitnessAdjust` / `fitnessCopilot` | **`3 × payload`** = 3 |
| itinerario viaggio | 2 ogni 3 giorni |
| ogni immagine (Document Intelligence) | 1 unità (`AI_IMAGE_CHAR_EQUIVALENT`) |

Il Pro ha 30 messaggi al giorno: **al massimo due generazioni del piano fitness
al giorno**. Se cambi un moltiplicatore, va cambiato in **tre posti** —
`functions/index.js`, `AIAskAIPayload` su iOS, `FITNESS_UNITS_MULTIPLIER` su
Android — più il testo «Costa 3 messaggi AI» in xcstrings, nei quattro
`strings.xml` e in `translations.js`. `isLargeContext` del copilota resta sul
payload, **non** sulle unità moltiplicate.

## Quote e gate

`resolveAIQuota`: **Free → `lifetime`**, pro/max → `daily` (30 / 100). È questa
la differenza che discrimina il piano, non `isAIAccessible`.

**Tetto mensile (dal 05/10/2026): Pro 100, Max 200 per famiglia** nel mese di
calendario (Europe/Rome), oltre al giornaliero: `aiMonthlyLimit` nel listino,
`ai_usage/family_{id}/monthly/{YYYY-MM}`, controllato **prima** del giornaliero
(se il mese è finito «riprova domani» sarebbe falso), errore con
`reason: "monthly-limit"`, rimborsato da `refundAIUsage` come il giorno. **Vale
anche per la prova Pro** (tetto del piano provato, stesso contatore del mese:
chi si abbona a metà mese parte da quanto ha usato nella prova); il Free no. Il conto: col solo giornaliero un Pro poteva
consumare 900 messaggi al mese, a 2-2,5 ¢ l'uno nel caso peggiore contro un
netto di 2,86 € (Apple 30% e IVA); a 100 resta un margine anche lì.

I **5 messaggi bonus del Free sono una tantum e non si ricaricano mai**: esauriti,
l'app torna esattamente com'era prima del bonus. Il contatore è doppio —
`ai_usage/family_{familyId}/lifetime/free` e `ai_usage/user_{uid}/lifetime/free`
— e blocca sul **più alto dei due**, perché senza il contatore per-uid bastava
creare una famiglia nuova per rigenerare il bonus. Effetto collaterale accettato:
chi ha finito i suoi 5 resta bloccato anche entrando in una famiglia col bonus
intatto.

**Il gate di piano va PRIMA di `checkAndIncrementAIUsage`**, così un tentativo
negato non consuma il bonus. I tre presidi (server, service, view) sono in
`/gating-pro`; su iOS il set è `paidOnlyPurposes` in `AIService.swift`
(`mealPlan`, `fitnessPlan`, `fitnessAdjust`, `fitnessCopilot`).

L'incremento resta **prima** della chiamata ad Anthropic (serve a non far
passare due richieste in parallelo oltre quota), quindi un guasto nostro
brucerebbe comunque l'unità: dal 23/09/2026 `refundAIUsage` la restituisce su
ogni fallimento dopo l'incremento — sovraccarico, errore Anthropic, risposta
vuota, rete — su `askAI`, `generateTravelPlan` e `suggestTravelDestinations`.
Rimborsa in transazione col pavimento a zero (mai `increment(-n)` cieco: dopo un
cambio giorno regalerebbe quota) e non solleva mai, per non coprire l'errore
vero. **Se aggiungi una callable AI, il rimborso va messo nel suo catch**,
altrimenti un 500 costa un messaggio a vita a un utente Free.

## Le trappole già pagate

1. **Modifiche annunciate e non applicate (copilota fitness).** Il client toglie
   il blocco `KIDBOX_FITNESS_ACTIONS` dal messaggio salvato: il modello rilegge
   le proprie risposte **senza** il blocco e dopo qualche scambio smette di
   allegarlo — dice «fatto» e il piano non cambia, **senza avviso**. Mitigato
   con regole nel system prompt (non imitare la cronologia, l'elenco sedute è lo
   stato reale), un parser che legge tutti i blocchi e segnala quelli troncati,
   `max_tokens` 8192 e timeout client 240 s. Se aggiungi un formato di azione,
   chiediti che cosa rilegge il modello al giro dopo.
2. **`max_tokens` troppo bassi troncano prima del marcatore di chiusura**, e una
   risposta troncata non è un errore: è una modifica che non avviene. Chat e
   cartella clinica 4096, piano alimentare, fitness e copilota 8192.
3. **La cache si raffredda in silenzio.** Haiku cacha solo da **4.096 token**: il
   prefisso della chat landing è stato misurato a 4.862, quindi accorciare
   `knowledge.md` **spegne la cache senza dirlo** e ogni domanda costa 4-5 volte
   di più (0,17¢ → 0,75¢). Nel report giornaliero si legge il **tasso di cache
   hit** per modello.
4. **Il modello inventa link e procedure.** Nei test Haiku ha prodotto un link
   Play con un package inesistente e una procedura di login mai esistita: per
   questo i link agli store stanno nella base di conoscenza, il client scarta
   store diversi da KidBox, e la regola vieta di descrivere schermate non
   presenti nella KB.
5. **Il numero vero dei costi è quello di Anthropic**, non la stima interna
   `ai_costs` (che serve solo a controllare la calibrazione). E i test dello
   sviluppatore dominano: un giorno con cache write alto e pochi utenti attivi
   è quasi sempre lui. → `/report-giornaliero`, regola 12.
6. **Uno storico che finisce con l'assistente è un prefill, non un contesto.**
   L'API considera l'ultimo messaggio `assistant` una risposta da *continuare*:
   se quel turno è già concluso il modello non ha niente da aggiungere e
   risponde **200 con `content: []`** — non un errore, una risposta vuota. A
   valle diventa «risposta Anthropic senza testo», un 500 in faccia all'utente e
   un messaggio di quota bruciato (23/09/2026). I 500 muti del 01/09 e del
   04/09, dati per non ricostruibili, sono quasi certamente lo stesso caso:
   stessa firma — ~0,9 s di latenza, nessun log applicativo, tutti da Android
   (`okhttp`) — ma senza prova diretta, perché il log della risposta vuota è
   stato aggiunto dopo.
   La **compattazione lo fa di proposito** — `compactIfNeeded` su iOS e
   `summarizeConversation` sul web mandano la conversazione intera con
   l'istruzione nel system prompt — quindi il server **normalizza invece di
   rifiutare**: `messagesEndingWithUserTurn` chiude il turno con una riga utente
   («Procedi.») e logga un `warn` con `purpose` e `msgCount`. Un
   `invalid-argument` secco avrebbe rotto la compattazione su tutte le build già
   installate: se un giorno la tentazione torna, è questo il motivo per cui non
   si fa.
7. **Il testo si legge da tutti i blocchi `text`, non da `content[0]`.**
   `anthropicReplyText` concatena. Leggere solo il primo blocco regge finché
   `SONNET_THINKING` è `disabled`: riaccendendo il ragionamento, `content[0]` è
   un blocco `thinking` e **cartella clinica e piano fitness fallirebbero tutte**
   con la risposta buona in mano. Vale anche per un blocco tool davanti.

## Azioni dell'assistente (`KIDBOX_ACTIONS`)

Il prompt di ogni client contiene la sezione azioni
(`PlanningAIActionBlock` su iOS e Android, `aiActions.js` sul web) e il client
esegue il blocco **subito, senza conferma**, poi riassume cosa ha scritto.
Tipi: `grocery_add`, `todo_add`, `event_add`, `note_add`, `health_reminder`,
`request_add` (richieste di famiglia, vedi `/richieste`). **Non esiste
`expense_add`**: le spese le propone Document Intelligence.

8. **Le date senza fuso.** Fino al 01/10/2026 la sezione chiedeva «ISO8601
   UTC» senza dire dove fosse l'utente: il modello scriveva l'ora italiana con
   la Z (un evento delle 16:30 finiva alle 18:30) e sbagliava il giorno della
   settimana («sabato» → il 4 invece del 3). Ora la sezione apre con
   `dateHeader` / `actionsDateHeader`: fuso, offset attuale, oggi e i prossimi
   7 giorni, e chiede date con l'offset. Android legge gli offset
   (`OffsetDateTime`, non solo `Instant.parse`). Se aggiungi un'azione con una
   data, passa da lì.
9. **Le regole di prompt si provano sul modello, non a intuito.** Script
   usa-e-getta nello scratchpad che legge la sezione vera dal sorgente web,
   chiama Haiku con la chiave di Secret Manager
   (`gcloud secrets versions access latest --secret=ANTHROPIC_API_KEY`, mai
   stampata) e stampa testo e blocco per 4-5 frasi tipiche, ripetendo i casi
   ambigui. Il 01/10/2026 così si sono visti il fuso sbagliato e «riceverà una
   notifica» detto a chi è fuori dall'app. Costa centesimi; i test li fa lo
   sviluppatore, quindi pesano nel report dei costi (regola 12).

## L'assistente unico (`familyAgent`)

Un solo assistente — Home, pulsante flottante del web, pulsanti AI di Salute —
con la memoria di tutta l'app. Disegno completo in `internal/assistente-unico.md`;
codice in `AgentMemoryBook.swift` / `AgentMemoryBook.kt` / `memoryBook.js` e nei
`PlanningAIChatViewModel` (sul web `Assistente.jsx`).

- **Il contesto è un quaderno di schede** markdown (`<indice>` + una `<scheda>`
  per sezione), costruito **sul dispositivo** a ogni domanda dai dati locali,
  senza chiamate AI. Le schede salute riusano il builder della chat Salute con
  lo scopo `agentMemory` (solo dati, niente ruolo né azioni). Mai nel quaderno:
  password, numeri e codici dei documenti d'identità (il loro testo OCR non
  entra mai), carte fedeltà, posizione. Le voci «solo per me» degli altri no.
- **Il focus va in cima e in fondo al prompt.** Provato su Haiku: solo in fondo,
  «cosa devo fare adesso?» aperto da una visita tornava 2 volte su 4 con le cose
  della famiglia; in cima e in fondo, 4 su 4. La riga ha esempi di domande senza
  soggetto: scritta solo come regola, Haiku la ignorava.
- **Il modello non fa i conti.** Regola «oggi è X, domani è Y» (sbagliava
  «domani»), età e prossimo compleanno precalcolati in `famiglia.md` («compie 1
  anno» a una bambina di tre), «domani» calcolato col calendario e non +24 ore.
- **Le regole del prompt sono lo stesso testo sulle tre piattaforme**: chi ne
  cambia una le cambia tutte e tre, insieme alle finestre (7 giorni indietro e
  60 avanti di calendario, 90 giorni di spese, 30 messaggi di chat…).
- **Budget.** Completo = ogni testo letto per intero. Se supera un messaggio
  vale la preferenza `healthContextSendPreference` («Memoria dell'assistente»
  nelle impostazioni): chiedi / massima accuratezza / contesto ridotto. Il
  ridotto non fa riassunti AI: misura lo **scheletro** (tutti i testi a zero) e
  divide lo spazio fra i testi — allegati del focus fino a 12.000, pertinenti
  alla domanda fino a 4.000, gli altri fino a 1.500 — poi un secondo giro col
  resto.
  **Trappola del 02/10/2026:** in una famiglia vera (30 esami, 88 documenti) lo
  scheletro da solo era 50.449 caratteri, oltre un messaggio, e il ridotto
  costava 2 messaggi pur promettendone 1. Ora il ridotto paga i messaggi che
  servono allo scheletro e li riempie di testi; se sfora (righe degli allegati
  indentate una per una) toglie lo sforamento dal budget e riprova, al massimo
  3 giri; un ridotto che costa quanto il completo non si propone.
  **Cache (dal 05/10/2026).** Il prompt parte in tre pezzi: `systemPromptStable`
  (regole, indice senza i conteggi delle schede che cambiano, schede stabili),
  `systemPrompt` (focus, oggi/calendario/to-do/spesa/chat, azioni, focus) e
  `systemPromptTail` (`domanda.md`, senza cache). Nel ridotto i testi hanno
  nelle schede una **base** che dipende solo dai dati (dal più recente, metà
  dello spazio dopo una riserva di 20.000) e i testi scelti per la domanda
  vanno nell'appendice in coda. Con un blocco solo ogni dato nuovo azzerava la
  cache e il write a 1,25× costava più di non averla; col budget diviso per
  domanda il ridotto non la usava mai. Misurato su Haiku: seguiti 83% (completo)
  e 69-83% (ridotto). **Non** rimettere nella parte stabile niente che cambi con
  la domanda, il focus o un dato frequente: la cache si spegne senza errori.
  **Ridotto automatico:** sul Free (quota `lifetime`) sempre, e altrove quando il
  completo supera i messaggi rimasti (il server lo rifiuterebbe per intero):
  niente dialogo, qualunque sia la preferenza. La quota la leggono i client con
  `getAIUsage` all'apertura.
- **Una conversazione sola per famiglia** (`planning-agent-{familyId}`): il
  focus cambia il contesto, non lo storico. Per questo i suggerimenti a tema non
  possono stare solo nella schermata vuota, che non si vede quasi mai.
- **Analytics:** `ai_message_sent` con `agent_type` = `salute` se aperto con un
  focus, `assistente` altrimenti, così la serie resta confrontabile con le
  vecchie chat Salute.
- **Prove di prompt:** script nello scratchpad che carica `memoryBook.js` con
  Vite (`createServer` + `ssrLoadModule`, con `globalThis.self = globalThis`
  prima dell'import), costruisce il quaderno da dati finti e chiama Haiku con la
  chiave di Secret Manager (mai stampata), come al punto 9. Per misurare una
  famiglia vera senza chiamare il modello: nella web app in locale, da console,
  `loadMemorySnapshot` + `planContext` (solo letture).

## Casi particolari

- **Document Intelligence**: opt-in esplicito (default off), massimo 3 pagine PDF
  per documento, ogni immagine è un'unità. Propone solo azioni di un elenco
  chiuso: spesa, evento, to-do, nota, intervento veicolo, visita, vaccino,
  promemoria salute, rinomina documento.
- **Chat della landing**: nessun login e nessun App Check, quindi **il tetto
  vero è il budget** (1 $/giorno). Chi ha già l'app va rimandato al supporto
  in-app. Le domande con fonte `llm` che si ripetono sono candidate a diventare
  risposte scritte; se la risposta dipende da dati vivi (il listino) si scrive
  **lato server** (`action: "price"`, che legge `config/plans`), non in `chat.js`.

## Aggiungere un purpose nuovo

1. Decidi i due assi: Sonnet o Haiku? one-shot o conversazione (cache)?
2. `max_tokens` che regga la risposta **completa**, marcatore di chiusura incluso.
3. Unità: quanto deve costare in messaggi, e riportalo su iOS e Android.
4. Se è a pagamento: gate server **prima** dell'incremento, più service e view
   sui tre client → `/gating-pro`.
5. Il testo del costo e dell'errore in quattro lingue, su tre superfici →
   `/localizzazione`.
