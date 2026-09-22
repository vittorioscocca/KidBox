---
name: alexa
description: Skill Alexa di KidBox (lista della spesa) — accoppiamento, nome di invocazione, lingue, e cosa non toccare. Usare quando si lavora su functions/alexa.js, sull'interaction model, sul nome di invocazione, o quando l'utente dice «Alexa non capisce», «non riesco a collegare» o «non riesco a scollegare Alexa».
---

Detta la spesa agli Echo e gli articoli finiscono in
`families/{familyId}/groceries`, la **stessa collezione** di iOS, Android e web:
la skill è un client in più, non ha un modello dati suo, e la push
`notifyNewGroceryItem` scatta come per un articolo aggiunto a mano.
Documentazione e testi di vetrina in `internal/alexa/`.

## Due scelte che sembrano limiti e sono decisioni

1. **Serve dire «chiedi a mio box».** Il 1º luglio 2024 Amazon ha chiuso la List
   Management REST API e le List Skills: da allora «Alexa, aggiungi il latte
   alla lista della spesa» scrive solo nella lista interna di Amazon, che
   nessuno può più leggere. L'unica via rimasta — la stessa di AnyList e Bring —
   è una skill con nome di invocazione proprio. **Non è aggirabile**: chi ci
   prova fa scraping non ufficiale, che si rompe a ogni cambio lato Amazon.
2. **Codice a 6 cifre, non account linking.** L'account linking è OAuth2 e
   vorrebbe un authorization server con pagina di login; i nostri account
   nascono in buona parte da Google e Sign in with Apple, quindi quella pagina
   dovrebbe rifare il giro completo dei due provider dentro la webview di
   Amazon. Il codice salta tutto, perché l'utente **è già autenticato nell'app**.

La skill resta in stage **Development**, non si pubblica: così è già attiva
sugli Echo dell'account dell'utente senza certificazione né revisione privacy.
È questa scelta che rende l'integrazione un lavoro di un giorno.
L'attribuzione passa dalla Personalization: `alexaPersonLinks` lega il
`personId` della voce a un membro, `alexaLinks` resta il legame account→famiglia.

## Cambiare il nome di invocazione: sei punti, non uno

Oggi è `mio box` (prima `kid box`, riconosciuto ~1 volta su 5).

**Su Amazon Developer Console**
1. *Invocation Name* del locale → **Save Model** *e poi* **Build Model**: sono
   due cose distinte, e finché non fai il build Alexa risponde ancora al nome
   vecchio anche se la console mostra già quello nuovo. È la causa numero uno di
   «l'ho cambiato e non funziona».
2. *Distribution → Example Phrases*: Amazon **pretende** che contengano il nome
   di invocazione, o la certificazione le respinge.

**Nel repo**
3. `internal/alexa/interaction-model-<locale>.json` → campo `invocationName`,
   **una riga sola** (le sample utterance non contengono il nome: Amazon lo
   vieta).
4. iOS: `Features/Settings/Alexa/AlexaSettingsView.swift` + le chiavi in
   `Localizable.xcstrings` per en/es/fr.
5. Android: `res/values{,-en,-es,-fr}/strings_settings.xml`, ~6 occorrenze per
   locale.
6. Web app: `KidboxWebApp/src/i18n/translations.js`, ~12 occorrenze — **è la
   superficie che si dimentica**, perché «le app» fa pensare solo a iOS e
   Android.

Più `internal/alexa/README.md` (~21 occorrenze), che è documentazione e va
riallineata per non mentire.

⚠️ **Il JSON locale non serve a portare la modifica in console** e la console non
lo aggiorna mai: non c'è ASK CLI né cartella `.ask`, è una copia manuale a senso
unico. Il pericolo è **ricaricarlo per sbaglio**: incollare nel JSON Editor una
copia rimasta indietro sovrascrive tutto il modello, nome di invocazione
compreso, e riporta in silenzio il nome vecchio. Un file disallineato qui è
un'arma carica, non un backup.

**NON si toccano:** il nome dell'app, il **Public Name** della skill (`KidBox`,
quello dello Store — può divergere dall'invocazione), bundle id, icone. E
soprattutto **il backend**: `functions/alexa.js` non nomina mai l'invocazione
(zero occorrenze), perché Alexa la rimuove prima di chiamare l'endpoint. Nessun
redeploy di functions.

I locale sono indipendenti: si può cambiare solo `it-IT` e lasciare `en-GB`.

## Lingua

La voce Alexa **non compare se l'app non è in italiano**, perché la skill esiste
solo in `it-IT` e mostrare istruzioni per qualcosa di non installabile è offrire
il vuoto. Il segnale è la **lingua effettiva dell'app**, non
`Locale.preferredLanguages`: chi sceglie «Italiano» in-app tiene Alexa anche col
telefono in inglese. Eccezione voluta: `en` + regione `IT` risolve in italiano.
Gate in `AlexaAvailability` su iOS, Android e web.

⚠️ **Nascondendo la voce si nasconde anche lo scollegamento**: chi ha collegato
Alexa e poi cambia lingua non trova più il pulsante (il collegamento resta
valido). Se arriva «non riesco a scollegare Alexa», la causa è questa.

## Se un giorno si va oltre l'inglese

Il costo non sta nelle stringhe: la skill **pensa in italiano**.
`langOf(locale)` è binaria (`startsWith("en") ? en : it`), quindi una richiesta
`es-ES` **riceve risposte in italiano, senza errore e senza log** — fallimento
muto, ed è il primo pezzo da sistemare. `CATEGORY_KEYWORDS` sono 254 parole
italiane: `leche` e `manzanas` non danno categoria, `pan` finisce in «Pane e
Cereali» per collisione fortuita. Il rischio non è che non funzioni, è che
funzioni a caso. Il modello `it-IT` porta ogni comando in forma imperativa **e**
infinitiva perché l'invocazione one-shot passa dall'infinito: è grammatica
italiana, non si traduce meccanicamente.
Solo inglese, invece, è quasi gratis di backend: `SPEECH` ha già `it` ed `en` in
parità, 25 frasi ciascuna.
