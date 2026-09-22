---
name: ai
description: Le funzioni AI di KidBox — purpose, modello, unità scalate, quote e le trappole già pagate. Usare quando si aggiunge o si modifica una funzione AI (assistente, piani, cartella clinica, viaggi, analisi documenti, chat della landing), quando si cambia modello o max_tokens, o quando l'utente dice «l'AI non applica le modifiche», «costa troppo», «i Free ci arrivano?».
---

Tutto passa dalla callable **`askAI`** (`functions/index.js`), discriminata dal
`purpose`. Fuori da lì: `generateTravelPlan` (callable sua), Document
Intelligence (immagini), e la chat della landing (`landingChat`, funzione HTTP
separata, senza login).

`purpose` noti: `clinicalRecord`, `mealPlan`, `fitnessPlan`, `fitnessAdjust`,
`fitnessCopilot` (più l'assistente generico, che non ne passa nessuno).

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
