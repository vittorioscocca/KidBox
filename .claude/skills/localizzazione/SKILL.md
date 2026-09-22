---
name: localizzazione
description: Aggiungere o correggere stringhe tradotte in KidBox su iOS (String Catalog), Android (res/values), web app e landing — incluse le trappole che rendono il buco invisibile. Usare quando si scrive UI nuova, quando l'utente dice «è rimasto in italiano», «traduci», «aggiungi la lingua», o prima di chiudere una feature su iOS.
---

## La trappola che rende tutto questo necessario

Su iOS **le chiavi sono i letterali italiani** (`Localizable.xcstrings`,
sourceLanguage `it`). Quindi una schermata nuova **compila, gira e mostra
l'italiano a tutti**: nessun errore, nessun warning, niente che lo segnali. Su
Android una risorsa mancante è un errore di compilazione, per questo i buchi
sono quasi sempre solo su iOS.

Corollario operativo: **una feature iOS non è finita quando compila.** È finita
quando le sue stringhe sono nel catalogo con en/fr/es.

## Le quattro superfici

| Dove | File | Come si aggiunge |
|---|---|---|
| iOS | `KidBox/KidBox/Localizable.xcstrings` (+ `InfoPlist.xcstrings` per i permessi) | chiave = letterale IT, valori it/en/fr/es |
| Android | `KidBoxAndroid/app/src/main/res/values{,-en,-fr,-es}/strings*.xml` | chiave simbolica, quattro file |
| Web app | `KidboxWebApp/src/i18n/translations.js` | 4 blocchi, forma identica |
| Landing | `KidboxLanding/tools/i18n/<page>.json` + `blog_<lang>_<n>.py` | pagine ES/FR **generate**, non scritte |

## Le cinque trappole, in ordine di quanto costano

1. **Mai riscrivere `Localizable.xcstrings` con `json.dump`.** Rimescola
   l'ordine delle chiavi e cambia `{}`: 23 000 righe di diff su una modifica di
   tre stringhe. Solo sostituzioni di testo mirate.
2. **`String` invece di `LocalizedStringKey`.** SwiftUI localizza solo i
   letterali passati come `LocalizedStringKey`: un letterale italiano che entra
   in una view custom con proprietà `String` **non viene nemmeno estratto da
   Xcode** — non compare nel catalogo, quindi non risulta «da tradurre» e sembra
   tutto a posto. Stesso effetto in contesto `String`:
   `Text(x.isEmpty ? "Senza titolo" : x)`, `prezzo + "/mese"`.
   **Se una stringa non si traduce, questa è la prima cosa da controllare.**
3. **`xcodebuild` da CLI non fa il merge nel catalogo** (solo l'IDE lo fa). Per
   estrarre: build, poi aggregare i `.stringsdata` da
   `DerivedData/.../KidBox.build/.../Objects-normal/arm64/*.stringsdata`
   (tabella `Localizable`) e fondere con uno script Python mirato.
4. **Web app: una chiave mancante non dà errore, dà `undefined` a schermo.**
   Dopo ogni generazione confrontare la **forma** dei quattro blocchi (percorso
   + tipo di ogni foglia), non il conteggio. E allargare `LANGUAGES` in
   `src/services/settings.js`, o la lingua esiste e nessuno può sceglierla —
   quella lista guida anche `notificationLanguage`, che il server usa per le push.
5. **Landing: le pagine ES/FR non si editano a mano.** Si generano dalle EN con
   `scripts/translate_html.py build` (testi in `tools/i18n/<page>.json`, liste
   allineate ai segmenti EN); se cambi una pagina EN i segmenti si spostano →
   `i18n_skeleton.py show/save`. Dopo `translate_html.py` **rilanciare
   `build_tools.py`** (footer, menu, canonical, hreflang).

## Regole di lingua

- **Francese**: spazio non separabile (U+00A0) prima di `: ; ? ! »` e dopo `«`.
  Negli script scriverlo come ` `: incollato in un heredoc torna spazio
  normale.
- **Plurali**: in francese **lo zero vuole il singolare** (`n <= 1`), in
  italiano e spagnolo no (`n === 1`). Le funzioni di interpolazione e gli array
  sono **codice**: si riscrivono, non si traducono.
- **Glossario** (già usato, non reinventarlo): Salute→Health/Santé/Salud,
  Viaggi→Travel/Voyages/Viajes, Officina→Repair shop/Garage/Taller,
  Bollo→Road tax/Taxe véhicule/Impuesto de circulación,
  Revisione→Inspection/Contrôle technique/Inspección técnica.
- **Le regole italiane non si traducono, si adattano** (revisione, 730,
  documenti dei minori): tradurle alla lettera produce consigli falsi.

## Non tradurre da zero: c'è già una memoria di traduzione

iOS ha ~2700 voci con la chiave in italiano (lettura diretta IT→FR/ES), Android
altre ~1050 (dalla chiave simbolica si risale all'italiano via `values/`, poi si
legge `values-fr`/`values-es`). Sulla web app questo ha coperto il 59% delle
stringhe gratis. Costruisci il dizionario prima di scrivere una traduzione nuova.

## Cose che si scoprono traducendo, e vanno riportate

Traducendo la landing sono emerse **funzioni inventate** (widget spesa, to-do
ricorrenti, suggerimenti dei prodotti comprati) e una stringa **malformata in
italiano** (`pets.confirmDeletePet`). Quando una frase da tradurre descrive una
funzione, **verificala nel codice**: se non esiste, segnalalo invece di
tradurla fedelmente in quattro lingue.

## Al margine

- **Alexa è solo `it-IT`**: la voce si nasconde fuori dall'italiano, e il gate è
  la **lingua effettiva dell'app**, non `Locale.preferredLanguages` (eccezione
  `en` + regione `IT` → italiano). Nascondendola si nasconde anche lo
  scollegamento: se arriva «non riesco a scollegare Alexa», la causa è questa.
- **Notifiche**: la preferenza è `users/{uid}.notificationLanguage` (dell'utente,
  non del device); su iOS non esiste hook prima di mostrare una notifica locale,
  quindi il testo si **congela alla schedulazione** — vedi
  `internal/notifiche-localizzazione-piano.md` prima di toccarle.
