# Assistente unico — disegno

> Decisioni dell'utente del 02/10/2026: **un solo assistente**, quello del
> pulsante in Home (invariato). Le chat AI di Salute (salute della persona,
> visite, singola visita, esami) **non spariscono**: i loro pulsanti aprono lo
> stesso assistente già centrato su quella persona, visita o esame. Sul web il
> pulsante flottante resta in tutte le sezioni e apre sempre l'assistente unico.
> La logica della chat Salute (builder dei referti, Apple Health, scelta
> «accurata / ridotta») **si riusa, non si riscrive**.

## Cosa risolve

Prima c'erano due cervelli: l'Assistente della Home sapeva un po' di tutto ma
dei documenti vedeva solo i titoli, della salute solo i figli, del calendario 14
giorni senza le ripetizioni e delle note 200 caratteri; la chat Salute sapeva
leggere i referti ma una persona alla volta, in una conversazione a parte.
A nessuno dei due si poteva chiedere «quanto abbiamo speso di veterinario
quest'anno e quando scade il vaccino di Fido?».

## La memoria: una scheda per sezione

Il contesto è un **quaderno di schede markdown**, una per sezione dell'app,
costruito **sul dispositivo** a ogni domanda dai dati locali: nessuna chiamata AI
per costruirlo, i dati cifrati non escono decifrati verso il server se non dentro
la domanda stessa (come prima). Nel prompt ogni scheda è un blocco

```
<scheda file="calendario.md" titolo="Calendario">
…markdown…
</scheda>
```

preceduto da un `<indice>` con una riga per scheda (cosa contiene, quanti
elementi, se qualche testo è stato accorciato).

| File | Contenuto |
|---|---|
| `famiglia.md` | membri e ruoli, figli con età, chi sta scrivendo |
| `ricordi.md` | i fatti appresi dalle conversazioni (`memoryFacts`, max 25) |
| `oggi.md` | eventi di oggi, to-do urgenti o scaduti, dosi, routine non fatte |
| `calendario.md` | eventi da 7 giorni fa a 60 giorni avanti, **ricorrenze espanse** |
| `todo.md` | aperti (scaduti, con data, senza data) e fatti negli ultimi 7 giorni |
| `spesa.md` | da comprare e comprati negli ultimi 7 giorni |
| `note.md` | note visibili all'utente, corpo fino a 1.500 caratteri ciascuna |
| `spese.md` | voci degli ultimi 90 giorni, totali per mese (12 mesi) e per categoria |
| `salute-<nome>.md` | **una per persona** (figli e adulti): profilo + lo stesso builder della chat Salute (cure, vaccini, visite, esami, referti letti, Apple Health) |
| `documenti.md` | indice di tutti i documenti + testo letto di quelli non allegati ad altre schede |
| `wallet.md` | biglietti, documenti d'identità (tipo, intestatario, scadenza — **mai il numero**), carte fedeltà (solo il negozio) |
| `casa.md` | oggetti, garanzie, manutenzioni, scadenze e pagamenti, testo degli allegati |
| `veicoli.md` | veicoli, scadenze (bollo, assicurazione, revisione), interventi, allegati |
| `animali.md` | animali, eventi veterinari, allegati |
| `viaggi.md` | viaggi futuri e recenti con tappe e giorni |
| `chat.md` | ultimi 30 messaggi di testo della chat di famiglia |

**Mai nel contesto:** password, numeri e codici dei documenti d'identità,
numeri delle carte fedeltà, posizione in tempo reale. **Visibilità rispettata:**
eventi, note, documenti e wallet «solo per me» di un altro membro non entrano.

## Il testo dei documenti e il costo

Un messaggio AI = 50.000 caratteri di payload (`AI_STANDARD_PAYLOAD_CHARS`).
Misura del 02/10/2026 sulle famiglie vere: tutte tranne 3 stanno sotto i 25.000
caratteri di testo letto dai documenti; la più grande ne ha 190.000 (88
documenti, 58 letti).

Si costruisce il quaderno in due forme:

- **completa** — ogni testo letto per intero;
- **ridotta** — tiene la parte strutturata e distribuisce il resto del budget
  di 1 messaggio fra i testi letti, in quest'ordine: documenti pertinenti alla
  domanda o al focus (fino a 4.000 caratteri, come lo standard della chat
  Salute), poi gli altri dal più recente (fino a 1.500); quelli che non entrano
  restano nell'indice con «testo non incluso».

Se la completa sta in 1 messaggio si manda quella e basta (quasi sempre). Se no
vale la **stessa preferenza della chat Salute** (`healthContextSendPreference`,
sincronizzata in `users/{uid}.aiPrefs`, nelle impostazioni «Memoria
dell'assistente»): «Chiedi ogni volta» mostra il dialogo
*Massima accuratezza (N messaggi) / Contesto ridotto (M messaggi)*,
«Massima accuratezza» manda la completa, «Contesto ridotto» la ridotta. Nella
ridotta non serve un riassunto AI: niente costo di preparazione.

**La ridotta non sempre costa 1.** Misura del 02/10/2026 su «Scocca Limato»
(30 esami coi risultati, 88 documenti di cui 70 letti): completa 280.644
caratteri (6 messaggi), **scheletro senza un rigo di testo letto 50.449** —
già oltre un messaggio. La ridotta allora paga i messaggi che servono allo
scheletro (qui 2) e li riempie di testi nell'ordine sopra; se sfora (le righe
degli allegati di Casa e Veicoli sono indentate una per una, e il contorno
stimato di 150 caratteri a documento non basta) toglie lo sforamento dal budget
e ridistribuisce, al massimo 3 giri. Se la ridotta costerebbe quanto la
completa, il dialogo non compare e parte la completa.

**Ridotto automatico (dal 02/10/2026).** Qualunque sia la preferenza, parte la
ridotta senza dialogo sul **Free** (quota `lifetime`: 5 messaggi in tutto, una
domanda con la completa poteva costarli tutti) e sugli altri piani quando la
completa costa **più dei messaggi rimasti**: il server la rifiuterebbe per
intero (`current + delta > limit`). I client leggono la quota con `getAIUsage`
all'apertura e la aggiornano a ogni risposta; le impostazioni lo dicono.

Pertinenza = parole della domanda (≥ 4 lettere, senza articoli e preposizioni,
senza accenti) trovate nel titolo, nel nome file, nella cartella o nel testo del
documento, più tutti gli allegati della persona / visita / esame del focus.

## Il focus

Aprire l'assistente da Salute passa un focus: persona, oppure persona + visita,
persona + esame, «visite di», «esami di». Effetti:

1. una riga dopo il quaderno: «L'utente ha aperto l'assistente da: … Le domande
   senza un soggetto esplicito si riferiscono a questo»;
2. gli allegati del focus contano come pertinenti (quelli della visita o
   dell'esame passano per intero anche nella ridotta, fino a 12.000 caratteri);
3. un'etichetta sotto l'intestazione («Salute di Marco ✕») che si può togliere,
   e suggerimenti a tema: nella schermata vuota e, perché la conversazione è
   una sola e quasi mai vuota, anche nella riga sopra il campo (Android li
   mostra sempre; iOS e web dal 02/10 sera).

La conversazione resta **una sola** (`planning-agent-{familyId}`): il focus
cambia il contesto, non lo storico. Le vecchie conversazioni della chat Salute
(`health-overview-v2-…`, `visits-…`, `exam-…`) restano salvate e non si mostrano.

## Server

`askAI` con `purpose: "familyAgent"`: **solo** per riconoscerlo in log e
analytics (`surface`). Modello (Haiku), unità (dal payload), `max_tokens` (4096)
e prompt caching restano quelli della chat. Il quaderno è il system prompt: se i
dati non cambiano fra una domanda e l'altra è identico byte per byte, quindi la
cache lo rilegge a 0,1×.

## Regole di risposta (nel prompt)

Dati solo dalle schede; se un dato manca dirlo, mai inventare date, importi o
valori; se un testo è accorciato e la domanda riguarda proprio quello, dirlo e
proporre la massima accuratezza. Salute: linguaggio semplice, niente diagnosi
né cambi di terapia, il medico per le questioni cliniche. Pianificazione:
titolo, data/ora e chi. Lingua: quella dell'app. Seguono intestazione date e
blocco azioni (`KIDBOX_ACTIONS`) come prima.

## Dove vive il codice

| | Quaderno | Chat |
|---|---|---|
| iOS | `Features/AIAgent/AgentMemoryBook.swift` | `PlanningAIChatViewModel` / `PlanningAIChatView` (`AgentFocus`) |
| Android | `ui/screens/ai/planning/AgentMemoryBook.kt` | `PlanningAIChatViewModel` / `PlanningAIChatScreen` |
| Web | `src/services/memoryBook.js` | `src/pages/Assistente.jsx` (`AssistantFocusContext`) |

## Cifratura delle conversazioni (dal 02/10/2026, a tappe)

Le conversazioni stanno in `users/{uid}/aiConversations` (iOS e web; Android le
tiene solo sul telefono). Testo dei messaggi e riassunto passano a `contentEnc`
e `summaryEnc`, cifrati con la chiave della famiglia della conversazione, nello
stesso formato delle note. Il server non li legge: `deleteAccount` cancella la
collezione e basta.

Stesso schema, stesso interruttore, per i **fatti della memoria di famiglia**
(`families/{id}/memoryFacts`, `contentEnc`): li scrivono iOS, Android e web.
Qui non c'è il rischio di cancellazione (ogni fatto è un documento suo): un
client vecchio semplicemente non vede i fatti cifrati. Nel `.next` i fatti
escono dalle scritture del wildcard di famiglia e hanno una regola loro.

E per il **testo letto dei documenti** (`families/{id}/documents`,
`extractedTextEnc`, compreso l'OCR dei documenti d'identità del Wallet), che
scrivono iOS e Android e il web solo legge. Qui **niente regola**, di proposito:
ogni modifica a un documento (rinomina, spostamento, stato dell'OCR) riscrive
anche il testo dalla copia locale, quindi una regola che rifiutasse il chiaro
impedirebbe alle build vecchie di modificare i documenti. Una build vecchia che
rimette il testo in chiaro viene ricifrata dal primo client nuovo che legge il
documento (senza toccare `updatedAt`); finita la transizione resta cifrato.

| Tappa | Cosa | Stato |
|---|---|---|
| 1 | iOS, Android e web **leggono** entrambi i formati; scrivono in chiaro finché l'interruttore Remote Config `text_encryption_enabled` è spento | web live, iOS e Android nelle prossime build |
| 2 | Build iOS e Android diffuse (criterio di `/rules-change`: GA4 `platform × appVersion` a 7 giorni) | da fare |
| 3 | Accendere `text_encryption_enabled` **e** promuovere `firestore.rules.next` (rifiuta le scritture in chiaro) | da fare, insieme |

Perché non subito: le build iOS installate riscrivono l'array dei messaggi
intero a ogni avvio (`reconcileAIChat`) e scartano quelli che non sanno
leggere, quindi cancellerebbero da Firestore i messaggi cifrati scritti altrove.
Con la regola attiva la loro scrittura viene negata: smettono di sincronizzare
le chat AI, non perdono niente e non caricano niente in chiaro. Dopo
l'accensione i documenti vecchi si ricifrano dai client (iOS alla
riconciliazione, il web appena li legge); senza chiave non si scrive.

