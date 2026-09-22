---
name: letture-firestore
description: Diagnosticare letture, scritture e costi di Firestore/Functions su KidBox — misurare prima di ottimizzare, i tranelli della metrica e le trappole già trovate. Usare quando l'utente dice «costa troppo», «troppe letture», «troppe chiamate», quando un contatore non torna, o prima di proporre qualunque ottimizzazione di costo.
---

## La premessa da verificare prima di ogni ottimizzazione

Misurato su Cloud Monitoring (118 famiglie): **~580 invocazioni functions al
giorno** (0,9% del free tier), **~20.000 letture Firestore al giorno** (40% del
free tier), **~1.000 scritture** (5%). La spesa del backend è di fatto **zero**.

Quindi «ci sono troppe chiamate, ottimizziamo» è quasi sempre una premessa
falsa: a questi volumi ridurre il numero di invocazioni non fa risparmiare
niente. Quello che paga è **riparare ciò che è rotto** e togliere i limiti di
scala che esplodono più avanti. **Prima di proporre un'ottimizzazione, misura.**

⚠️ La premessa sopra vale per le **invocazioni**, non per le **letture**: sulle
letture una singola callable ha pesato per l'**87%**.

## Come si misura (e come ci si sbaglia)

`gcloud auth print-access-token` +
`monitoring.googleapis.com/v3/projects/kidbox-42cd7/timeSeries`. `gcloud` è già
autenticato sulla macchina; l'**ADC per l'Admin SDK no**.

1. **`firestore.googleapis.com/document/read_count` è di progetto, non di
   dispositivo.** Su una famiglia con più utenti attivi, isolare una finestra
   temporale non attribuisce niente: due misure sono state inquinate da un altro
   membro che usava l'app e da un aggiornamento Android caduto dodici secondi
   dopo l'inizio. Quello che regge è un **gruppo di controllo** (ore con la
   funzione contro ore senza, a pari attività) o il **protocollo sul filo**
   (`adb logcat` con il debug Firestore su Android, `fromCache` /
   `documentChanges` nei log su iOS).
2. **~25 minuti di ritardo di ingestione** prima che la metrica mostri il dato.
   Vale anche per `execution_count` degli scheduler: un punto che appare alle
   01:25 per un job delle 01:00 non è uno scheduler in ritardo.
3. **`alignmentPeriod=86400s` non dà giorni di calendario** ma finestre mobili
   di 24 h ancorate all'ora della query: chiedi `3600s` e somma per data, o
   leggerai «106% del free tier» dove il giorno vero era 48%.
4. Le alert policy sono 6, documentate in **`internal/monitoring.md`**: leggi
   quel file prima di toccarle, e aggiornalo insieme alla policy.

## Le quattro cause già trovate (guardarle prima di cercarne di nuove)

1. **Una callable che scansiona collezioni intere.** `getStorageUsage` faceva
   nove scansioni senza cache, quattro delle quali scaricavano ogni documento
   solo per leggerne `.size`: ~624 letture per chiamata, 2.057 letture/ora
   contro 151/ora di base. Corretto con `count()` sulle quattro di conteggio; le
   cinque che sommano byte restano e vanno sostituite con contatori mantenuti.
2. **Il punto in `set()`.** In `set()` un punto nel nome del campo è
   **letterale**, non un percorso: solo `update()` lo interpreta come
   navigazione. `set({"sections.documents": increment(d)}, {merge:true})` crea un
   campo di primo livello chiamato `"sections.documents"` mentre chi legge
   guarda la mappa `sections`. Nessun errore, nessun log: il documento contiene
   **entrambe** le forme. Ha reso cieco per mesi il contatore dello spazio, ed è
   la causa della scansione al punto 1.
   → Sintomo: «esiste un contatore incrementale ma nessuno si fida e si
   ricalcola tutto». Prima di riscrivere il contatore, **apri il documento vero**
   e guarda i nomi dei campi di primo livello.
3. **`clearPersistence()` a ogni avvio** (Android, corretto): cancellava cache e
   resume token, da ~300 a ~58 letture per avvio. Né iOS né la web app lo
   chiamano.
4. **Uno scan periodico che riscrive tutto.** Il controllo settimanale Have I
   Been Pwned riscriveva **tutte** le password a ogni giro, documento intero con
   `updatedAt`, anche a verdetto invariato: ~150 «aggiornamenti» a settimana con
   0 creazioni, e su ogni altro device la lista si riordinava come se fosse
   stata modificata adesso. Ora si scrive **solo il verdetto e solo se cambia**,
   e `classify()` in `functions/analytics.js` ignora le scritture che toccano
   solo `MACHINE_ONLY_FIELDS`.

## Il limite di scala da tenere d'occhio

`notifyLocationSharingChanged` durante un picco di attività è arrivata al **94%
di tutto il traffico functions**, perché scatta a ogni aggiornamento di
coordinate anche quando `isSharing` non cambia. La cura è separare coordinate e
stato in due documenti (già fatto: `locations/{uid}` è lo stato, `live/current`
le coordinate) — se ricompare, è lì che si guarda.

## Come si scrive una conclusione

Una diagnosi di costo regge solo se dice **quanto** e **contro cosa**: «2.057
letture/ora contro 151/ora di base, misurate su 54 ore contro 47 di pari
attività» è una diagnosi; «sembra che legga troppo» no. Se non hai un gruppo di
controllo o il protocollo sul filo, dillo e chiamala ipotesi.
