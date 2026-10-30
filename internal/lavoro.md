# Lavoro (iOS, 30/10/2026)

Buste paga e contratti per adulto, letti dall'AI e salvati con i valori estratti.

## Dati
- `families/{fid}/workProfiles/{uid}` (id = uid del proprietario): `visibilityScope` (`private`|`members`), `visibilityMemberIds` (elenco **autorevole**: vuoto = solo il proprietario), `employerEnc`.
- `families/{fid}/workRecords/{id}`: `ownerUid`, `kind` (`payslip`|`contract`), `referenceDate`, `fieldsEnc` (JSON di `WorkFields` cifrato con la chiave di famiglia), `attachmentDocumentId`.
- Il file originale è un `KBDocument` privato nella cartella «Lavoro» (id `work-root-{fid}`), tag `work:{uid}`.

## Perché le rules contano
Il wildcard di famiglia dà lettura e scrittura a ogni membro su ogni sottocollezione. `workProfiles` e `workRecords` sono **escluse** (lettura e scrittura) e hanno una regola loro: il proprietario scrive, un altro adulto legge solo se è in `visibilityMemberIds` (i documenti seguono la scheda con `get()`).
- Le LIST non filtrano: il client usa `array-contains` sul proprio uid per le schede condivise e `ownerUid ==` per i documenti. Una query senza filtro è negata.
- Un errore di permessi dei listener di Lavoro **non** passa da `handleFamilyAccessLost` (espellerebbe dalla famiglia: vedi `/rules-change`, trappola 1).
- Limite onesto: il `KBDocument` con il file sta in `families/{fid}/documents`, leggibile ai membri dal wildcard; è nascosto dalla visibilità (`private`) e cifrato con la chiave di famiglia, ma **non** negato da una regola. Chiudere la cosa chiede una regola su `documents` per il tag `work:`.

## Foglio ferie
`kind = leavePlan`: `fields.leavePeriods` (start, end, label) letti dal PDF; alla conferma il foglio si salva sempre; ogni periodo con `inCalendar` acceso (default in bozza, scelta per periodo) crea un `KBCalendarEvent` tutto-il-giorno con visibilità **famiglia** (fine = 23:59:59 dell'ultimo giorno, come il resto del calendario). Ogni periodo ricorda il suo `eventId` (e `fields.eventIds` li elenca): «Modifica» sposta l'evento se cambiano le date, lo crea se si accende «Aggiungi al calendario», lo cancella se si spegne o si toglie il periodo (`reconcileLeaveEvents`). I fogli salvati prima dell'`eventId` si riallineano per ordine se il numero di eventi coincide coi periodi. Eliminando il documento si cancellano anche gli eventi. Caricarlo due volte duplica gli eventi.

## Il file segue la scheda
Il `KBDocument` allegato nasce con la visibilità della scheda e `WorkAttachmentService.syncVisibility` la riallinea a ogni cambio di condivisione: senza, chi riceve la scheda vedrebbe il documento ma non potrebbe aprirlo.

## Gating (tre presidi)
- Server: `askAI` rifiuta il purpose `workDoc` se `quota.period === "lifetime"` (mai il bonus Free).
- Service: `AIService.strictlyPaidPurposes` con `currentPlan != .free`.
- View: `WorkHomeView` mostra l'invito ai piani sui Free.
Il listino (`config/plans`, console admin) non cita ancora Lavoro: `/piani`.

## Cosa manca
Android e web; link `apri:lavoro` (richiede `Kind` in `AgentLinks` e `KBSearchIndex`); lettura dal «+» dell'assistente; modifica di un documento già salvato (oggi si elimina e si ricarica).
