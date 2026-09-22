---
name: release-client
description: Preparare una release iOS o Android di KidBox — note «Novità» nelle quattro lingue, testi delle schede store, dichiarazioni Play, e il confine di cosa non tocco. Usare quando l'utente parla di pubblicare, sottomettere, «note di rilascio», whatsNew, scheda store o versione nuova.
---

## Il confine, prima di tutto

**I client li pubblica l'utente.** Io scrivo i testi, li applico via API dove si
può, e preparo. Non tocco mai:

- `CURRENT_PROJECT_VERSION` e `MARKETING_VERSION` in
  `KidBox.xcodeproj/project.pbxproj` — **nemmeno per rimetterli a posto, nemmeno
  di passaggio**. Sono la moneta con cui l'utente pubblica; non c'è script di
  incremento automatico, quindi ogni cambiamento lì è deliberato. Se dopo un
  `xcodebuild` il pbxproj risulta modificato, controlla la data prima di
  attribuirtelo e in ogni caso non scriverci sopra.
- `versionCode` Android. **Un versionCode caricato non si riusa mai più**, anche
  se la release viene rimossa (il 49 è bruciato così).
- I commit dei due client.

## I testi

Tutto sta in `internal/store-listings/`, sotto controllo di versione apposta per
poterlo diffare:

| File | Cosa | Limite |
|---|---|---|
| `appstore-ios-<lang>.txt` | descrizione App Store iOS | 4000 caratteri |
| `appstore-mac-<lang>.txt` | descrizione App Store macOS | 4000 |
| `play-<lang>.txt` | scheda Google Play | 4000, **80** la breve |
| `appstore-whatsnew-<versione>.txt` | note iOS, blocchi `## <locale>` | 4000 |
| `appstore-mac-whatsnew-<versione>.txt` | note Mac (cumulano le versioni iOS saltate su Mac) | 4000 |
| `play-whatsnew-<versione>.txt` | note Play, formato `<it-IT>…</it-IT>` | **500 per lingua** |

Lingue: `it`, `en-GB`, `es-ES`, `fr-FR` (App Store) / `it-IT`, `en-US`, `fr-FR`,
`es-ES` (Play). Le versioni **Mac** differiscono dalle iOS solo in coda (righe
EULA/Privacy) e per l'assenza della frase su Alexa in italiano.

## Applicare le note su App Store Connect

    node scripts/asc-whatsnew.js --platform IOS --version 2.3.1 \
         --file internal/store-listings/appstore-whatsnew-2.3.1.txt

Senza `--apply` mostra per ogni lingua testo attuale e nuovo e **non scrive**:
fallo sempre prima. Con `--apply` scrive (e crea le localizzazioni mancanti).
Chiave `.p8` nel Portachiavi (voce `asc-api-key`, account `kidbox`), stessa
autenticazione del report giornaliero.

**Un 401 di App Store Connect è quasi sempre transitorio.** Il 20/09/2026 ha
rifiutato token validi su una chiave attiva, con l'orologio allineato: la
diagnosi «chiave revocata, rigenerala» era sbagliata e sarebbe costata una
chiave nuova e due file da modificare. Da quella data entrambi gli script
ritentano una volta da soli con un token fresco. Se il 401 resta anche dopo la
riprova, prima di rigenerare controlla nell'ordine: che la chiave risulti
«Attiva» in App Store Connect, che Key ID e Issuer ID negli script combacino con
quelli mostrati lì, e l'ora della macchina.

Si può scrivere **solo** su una versione in `PREPARE_FOR_SUBMISSION`,
`WAITING_FOR_REVIEW`, `DEVELOPER_REJECTED`, `REJECTED`, `METADATA_REJECTED`.
Le localizzazioni degli abbonamenti già approvate (ACTIVE) non si toccano via
API. Su **Play** le note si incollano a mano nella console: il file è già nel
formato giusto.

## Come si scrivono le note

Tre-quattro righe, cosa cambia per chi usa l'app, non per chi la scrive. Niente
numeri di build, niente nomi di classi, niente «bug fix vari» da solo. Se la
release contiene una scommessa del registro (`/auto-miglioramento`), la nota
deve descrivere **quella** in prima riga: è ciò di cui misurerai l'effetto.
Poi tradurre, non inventare quattro testi diversi.

## Prima di sottomettere — le cose che hanno già fatto respingere una versione

- **Health Connect (Android)**: ogni tipo di dato letto va **dichiarato in Play
  Console e nella privacy per-tipo**, e la UI che lo usa deve restare visibile
  anche senza dato e anche sul piano Free (stato vuoto «—»). La v47 è stata
  respinta perché il permesso era indimostrabile per un revisore su emulatore.
  Serve anche il video demo: lo fa l'utente.
- **Popup di valutazione**: solo le API native (`AppStore.requestReview(in:)`,
  Play In-App Review). Niente prompt custom (Apple 5.6.1) e niente review gating
  (chiedere se piace e mandare allo store solo i contenti) — vietato da entrambi.
  Non si vede in TestFlight né su build Android non installate da Play.
- **Stringhe non tradotte**: una schermata nuova su iOS nasce in italiano senza
  che nulla lo segnali → `/localizzazione` prima di sottomettere.
- **Schede store**: `internal/store-listings/README.md` dice quali testi sono
  già applicati e quali no (le versioni Mac restano spesso indietro).

## Dopo la pubblicazione

Una release è adottata in **1-2 settimane**: fino ad allora i due comportamenti
convivono nei dati e le metriche vanno lette per utenti unici e per versione.
Se la release chiude una scommessa del registro, la data di misura si conta da
quando è **in store**, non da quando è stata sottomessa.
