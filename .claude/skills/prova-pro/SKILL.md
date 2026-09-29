---
name: prova-pro
description: La prova Pro gratuita di 14 giorni di KidBox — come viene concessa, interruttore, tetto AI, scadenza e push, regalo alle famiglie esistenti, dove vivono i testi che la annunciano, come leggerla nel report. Usare quando l'utente chiede della prova («come si attiva», «perché non ce l'ho», «accendi/spegni la prova»), prima di cambiarne durata o limiti, o quando si scrive un testo che la cita.
---

## Come funziona (live dal 29/09/2026)

- **Si attiva da sola**, senza pulsante né carta: quando qualcuno crea una famiglia nuova, il trigger `grantProTrialOnFamilyCreated` scrive sulla famiglia `plan: "pro"`, `planSource: "trial"` e `planExpiresAt` fra 14 giorni, e registra `trials/{uid}` del proprietario.
- **Una per PERSONA, non per famiglia.** `trials/{uid}` è solo server (nessuna rule lo apre): aprire un'altra famiglia non dà una seconda prova.
- **Non la ricevono:**
  - chi entra con un invito in una famiglia esistente, perché la prova appartiene al proprietario;
  - le famiglie nate prima del 29/09, salvo il regalo (sotto);
  - chi ha già un piano, abbonato o assegnato dalla console: la prova non sovrascrive mai un piano che vale di più;
  - il Max: la prova dà sempre e solo il Pro.
- **AI:** tetto proprio, 50 messaggi in tutto per la prova (`period: "trial"`, contatore `ai_usage/family_{id}/lifetime/trial`). Il periodo non è `lifetime`, quindi i pianificatori Pro-only restano aperti. Costo massimo circa 0,75 $ a famiglia.
- **Fine:** il job orario `expireProTrials` riporta la famiglia a `plan: "free"` con `planSource: "trial_ended"`, e manda push nella lingua dell'utente due giorni prima e alla fine (type `pro_trial`: iOS apre la sezione Abbonamento, Android i Piani). Il job serve perché le app leggono `families.plan` senza guardare la scadenza.
- **Conversione:** `validatePurchase` segna `trials/{uid}.convertedAt` se la famiglia era in prova o l'aveva appena finita.
- Codice: `functions/proTrial.js`; aggancio in `resolveAIQuota` e `checkAndIncrementAIUsage` in `functions/index.js`.

## Interruttore e parametri

Documento `config/trial`: `enabled` (bool), `days` (1-30), `aiLimit` (0-200), `reminderDaysBefore` (0-7). Cache di 60 secondi. Assente o illeggibile = prova spenta.
- **Spegnerla:** `enabled: false`. Le prove già concesse finiscono comunque alla loro scadenza.
- **Accenderla solo quando i client che la spiegano sono in vendita su ENTRAMBI gli store** (iOS ≥ 2.3.6, Android ≥ 2.4.2). Le app vecchie vedono il Pro sbloccato senza banner, e a fine prova perdono funzioni senza capire perché. Il 29/09 l'utente ha deciso di accenderla prima: è una sua scelta da rispettare, ma va detto il rischio.

## Regalo alle famiglie già esistenti

`node scripts/grant-trial-gift.js`: senza argomenti è una prova a vuoto, che stampa quante famiglie e quali (id corto, membri, ultimo accesso, piattaforma, lingua, senza nomi); `--yes` concede e manda la push «Un regalo per la tua famiglia»; `--no-push` concede senza push.
- **Criteri scelti dall'utente:** almeno un membro attivo negli ultimi 14 giorni, famiglie di qualunque dimensione, esclusi account di prova, piani esistenti e chi ha già avuto la prova. A chi possiede più famiglie tocca quella usata più di recente.
- **Stesse scritture del trigger, in un commit atomico con precondizioni.** Rilanciarlo è innocuo.
- **Sempre prima la prova a vuoto, mostrata all'utente;** `--yes` solo con il suo ok esplicito e con le app nuove in vendita. Al 29/09 si aspettava Android 2.4.2.

## Dove vive il testo che la annuncia (da aggiornare tutto insieme)

| Dove | File |
|---|---|
| Etichetta sulla card Pro della landing (4 lingue) | `KidboxLanding/public/assets/plans.js` → `TRIAL_LINE` |
| Frase in testa alla nota sotto le card | `index.html`, `index-en.html`; ES/FR in `tools/i18n/index.json`, poi `scripts/translate_html.py build` |
| Chat della landing | `functions/landingChat/knowledge.md` (deploy di `functions:landingChat`) |
| Testo promozionale App Store (iPhone e Mac, 4 lingue) | via API sulla versione in vendita e su quella in preparazione |
| Push di promemoria e fine | `functions/notificationsI18n.js`, chiavi `trial.*` |
| App | banner `ProTrialBanner` (iOS/Android), riquadro nel paywall, «In prova» su card e profilo |

**Come si scrive:** la frase deve dire COME si ottiene, non solo che esiste. «14 giorni inclusi per le famiglie nuove» non l'ha capita nessuno; la forma giusta è «Prova Pro gratis per 14 giorni: parte da sola quando crei la tua famiglia, senza carta».
- «Gratis» va bene su landing, chat e app. Nella **descrizione breve di Play NO**: le regole sui testi della scheda vietano prezzi e promozioni. Nell'App Store scrivere «Pro incluso per 14 giorni» e non «prova gratuita dell'abbonamento», che fa pensare alla prova con addebito automatico dello store.

**Se la prova si spegne:** togliere `TRIAL_LINE`, la frase nella nota (4 lingue), la sezione nella knowledge della chat e il testo promozionale App Store. Il banner nelle app si nasconde da solo.

## Leggerla nel report

- **Riga «Prova Pro» della console:** in corso, concesse (ieri), finite, convertite (di cui durante la prova).
- **Le famiglie in prova hanno `plan: "pro"` ma NON sono paganti:** il report e la console le tolgono già dai paganti.
- **La conversione si legge solo sulle prove FINITE,** e sotto le 20 finite come conteggio, non come percentuale.
- **Con `enabled` acceso e famiglie nuove create ma zero concesse:** è un'anomalia, guardare i log di `grantProTrialOnFamilyCreated`.
- **Con `enabled` spento e concesse > 0** (fuori dagli invii dello script regalo, `source: "gift"`): è un'anomalia.
