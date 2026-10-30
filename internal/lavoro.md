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

## Gating (tre presidi)
- Server: `askAI` rifiuta il purpose `workDoc` se `quota.period === "lifetime"` (mai il bonus Free).
- Service: `AIService.strictlyPaidPurposes` con `currentPlan != .free`.
- View: `WorkHomeView` mostra l'invito ai piani sui Free.
Il listino (`config/plans`, console admin) non cita ancora Lavoro: `/piani`.

## Cosa manca
Android e web; link `apri:lavoro` (richiede `Kind` in `AgentLinks` e `KBSearchIndex`); lettura dal «+» dell'assistente; modifica di un documento già salvato (oggi si elimina e si ricarica).
