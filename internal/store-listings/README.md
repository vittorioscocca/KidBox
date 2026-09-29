# Testi delle schede store

Copia dei testi pubblicati su App Store Connect e Google Play, così le
descrizioni stanno sotto controllo di versione e si diffano. Limite: 4000
caratteri per descrizione (entrambi gli store), 80 per la breve di Play,
55 per la descrizione di un abbonamento su App Store.

| File | Dove | Stato (15/09/2026) |
|---|---|---|
| `appstore-ios-*.txt` | App Store, versione iOS | applicati alla 2.2.8 «Waiting for Review» |
| `appstore-mac-*.txt` | App Store, versione macOS | **da applicare alla prossima versione Mac**: 2.2.8 era in revisione e 2.2.4 live, entrambe bloccate |
| `play-*.txt` | Google Play, scheda per lingua | applicati (it-IT aggiornata; en-US, fr-FR, es-ES create) |

Le versioni Mac differiscono dalle iOS solo in coda (righe EULA/Privacy) e
per l'assenza della frase Alexa in italiano.

Descrizioni brevi Play (dal 29/09/2026: «insieme» al posto di «in un'unica
app», perché l'app vale quando entra il secondo familiare; niente prezzi né
promozioni come «gratis» o la prova Pro, che le regole di Play sui testi
della scheda non ammettono):
- `it-IT`: Organizza la famiglia insieme: agenda, spesa, salute, spese e documenti
- `en-US`: Organize your family together: shared calendar, shopping, health and documents
- `fr-FR`: Organisez la famille ensemble : agenda, courses, santé et documents partagés
- `es-ES`: Organiza la familia juntos: agenda, compra, salud, gastos y documentos

Prima: «KidBox: salute, agenda, spese e documenti della tua famiglia in un'unica
app.» (e traduzioni). Il commit dell'edit Play va fatto con un corpo vuoto
esplicito (`Content-Length: 0`): senza, la risposta arriva vuota e l'edit si
perde.

Per applicare via API: script usa-e-getta di questa sessione (`asc-apply.js`),
autenticazione come `scripts/appstore-daily-report.js` (chiave nel Portachiavi)
e, per Play, il service account `play-purchase-validator` impersonato con scope
`androidpublisher` (ha il permesso di gestire la scheda dal 15/09/2026).
Una descrizione si può modificare solo su una versione in «Prepare for
Submission» o «Waiting for Review»; le localizzazioni degli abbonamenti già
approvate (ACTIVE) non si toccano via API.

## Note «Novità» (whatsNew) per versione

Testi per versione in `appstore-whatsnew-<versione>.txt` (iOS) e
`appstore-mac-whatsnew-<versione>.txt` (Mac, che cumula quando una versione iOS
è saltata su Mac), più `play-whatsnew-<versione>.txt` per Google Play (limite
500 caratteri per lingua, formato `<it-IT>…</it-IT>` da incollare nella console).

Su App Store Connect si applicano con lo script riutilizzabile:

    node scripts/asc-whatsnew.js --platform IOS --version 2.3.1 \
         --file internal/store-listings/appstore-whatsnew-2.3.1.txt --apply

(senza `--apply` mostra attuale/nuovo e non scrive). Stessa autenticazione del
report giornaliero. Applicate il 20/09/2026 su iOS 2.3.1 e Mac 2.3.1, entrambe
in «Prepare for Submission».
