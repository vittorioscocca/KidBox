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

Descrizioni brevi Play:
- `it-IT`: KidBox: salute, agenda, spese e documenti della tua famiglia in un'unica app.
- `en-US`: KidBox: your family's health, calendar, expenses and documents in one app.
- `fr-FR`: KidBox : santé, agenda, dépenses et documents de la famille en une seule app.
- `es-ES`: KidBox: salud, agenda, gastos y documentos de tu familia en una sola app.

Per applicare via API: script usa-e-getta di questa sessione (`asc-apply.js`),
autenticazione come `scripts/appstore-daily-report.js` (chiave nel Portachiavi)
e, per Play, il service account `play-purchase-validator` impersonato con scope
`androidpublisher` (ha il permesso di gestire la scheda dal 15/09/2026).
Una descrizione si può modificare solo su una versione in «Prepare for
Submission» o «Waiting for Review»; le localizzazioni degli abbonamenti già
approvate (ACTIVE) non si toccano via API.
