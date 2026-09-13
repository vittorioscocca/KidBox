# -*- coding: utf-8 -*-
"""Articoli della categoria «Organizzazione familiare». Vedi blog_data.py per il formato."""

ARTICLES = [
    {
        "slug": "documenti-di-famiglia-in-ordine",
        "category": "organizzazione-familiare", "date": "2026-09-12",
        "tools": ["documenti", "wallet", "password"], "related": ["scadenze-di-casa-bollette-garanzie", "documenti-dei-figli-in-due-case", "storia-sanitaria-dei-figli"],
        "it": {
            "title": "I documenti di famiglia in ordine, una volta per tutte",
            "desc": "Un metodo in tre livelli — cartelle, schede, wallet — per non cercare mai più un documento, e perché la cifratura non è un dettaglio.",
            "body": """
Ogni famiglia ha il cassetto. Quello con i contratti, le garanzie, i certificati, le buste mai aperte e la fattura che serviva l'anno scorso. Il cassetto non è disordine: è il risultato naturale di documenti che arrivano da dieci fonti diverse e non hanno un posto.

Il metodo qui sotto sostituisce il cassetto con tre livelli, e si monta in un pomeriggio.

## Il principio: un documento sta dove serve

L'errore classico è organizzare i documenti per **tipo**: una cartella «fatture», una «certificati», una «contratti». Sembra logico, ma quando serve un documento non lo cerchi per tipo: lo cerchi per **cosa riguarda**. La fattura del gommista serve quando pensi all'auto, non quando pensi alle fatture.

Quindi i documenti vanno agganciati alla cosa a cui si riferiscono. Il resto viene da sé.

## Livello 1: le schede

In KidBox, quasi ogni scheda accetta allegati: la visita medica, l'esame, l'auto, l'intervento in officina, l'elettrodomestico, la scadenza di casa, l'animale. Il documento si carica **lì**, e l'app lo mette automaticamente anche nell'archivio Documenti con un riferimento alla scheda di origine.

Questo vuol dire che:

- il referto sta sulla visita, e lo trovi dalla [scheda Salute](/strumenti/salute) di quel figlio
- la fattura del tagliando sta sull'intervento, nella [scheda Veicoli](/strumenti/veicoli)
- la garanzia sta sulla lavatrice, nella [scheda Casa](/strumenti/casa)

E in tutti i casi lo stesso file è anche in [Documenti](/strumenti/documenti), in una vista unica. Un file solo, due strade per arrivarci.

## Livello 2: le cartelle

Per quello che non ha una scheda — contratti, atti, certificati, comunicazioni — servono le cartelle. Poche, e per **soggetto**:

- Una per **ogni persona** (identità, scuola, lavoro)
- Una per la **casa** (contratti, atti, condominio)
- Una per il **denaro** (banca, assicurazioni, tasse)

Tre-cinque cartelle bastano. Se ne servono dieci, alcune sono in realtà schede che non avete ancora usato.

## Livello 3: il wallet

Alcuni documenti non si archiviano: si **mostrano**. Tessera sanitaria, carta d'identità, tessera del supermercato, biglietto del treno, abbonamento della palestra. Nel [Wallet](/strumenti/wallet) stanno come carte, con il codice a barre leggibile in cassa e la scadenza visibile. E i biglietti in PDF vengono letti dall'app, che ne estrae data, orario e posto senza che tu debba riscriverli.

## La regola dell'ingresso

Il sistema regge se ogni documento nuovo trova il suo posto **quando arriva**, non «quando avrò tempo». Trenta secondi al momento giusto valgono un'ora a fine anno.

- Referto → si allega alla visita
- Fattura → si allega alla scadenza o all'intervento (e la spesa nasce da sola)
- Contratto → in cartella
- Tessera → nel Wallet

Su iPhone l'estensione di condivisione permette di mandare un PDF dalla mail direttamente in KidBox, senza passare dai file del telefono.

## Perché la cifratura non è un dettaglio

I documenti di una famiglia sono la cosa più sensibile che la famiglia possiede: identità, salute, denaro, minori. Metterli in un servizio che li può leggere significa fidarsi per sempre delle sue scelte future.

In KidBox i documenti sono cifrati con una **chiave di famiglia** che sta solo sui dispositivi dei membri. Il servizio conserva byte, non contenuti. La conseguenza pratica è che nessuno — noi compresi — può aprire il referto di tuo figlio. È il motivo per cui le notifiche non mostrano l'anteprima di un documento: non possiamo generarla.

## Le password sono documenti

Un'ultima categoria che di solito manca dall'archivio: le credenziali. Registro elettronico, portale della mensa, banca, utenze, Wi-Fi. Sono documenti a tutti gli effetti, e devono essere condivisi tra i genitori e cifrati. La [scheda Password](/strumenti/password) fa esattamente questo, con l'AutoFill sul telefono e un controllo di sicurezza sulle password deboli o riusate.

## Il pomeriggio

Concretamente:

1. **Svuota il cassetto** e dividi in tre mucchi: da buttare, da fotografare, da conservare in originale.
2. **Fotografa** il secondo mucchio, un documento alla volta, direttamente nella scheda giusta.
3. **Crea le cartelle** per il resto.
4. **Aggiungi le scadenze** che hai scoperto lungo la strada.
5. Il terzo mucchio torna in un cassetto — molto più piccolo.

Da quel giorno il cassetto non cresce più, perché i documenti nuovi hanno un posto dove andare.
""",
        },
        "en": {
            "title": "Family documents in order, once and for all",
            "desc": "A three-level method — folders, records, wallet — to never search for a document again, and why encryption isn't a detail.",
            "body": """
Every family has the drawer. The one with the contracts, warranties, certificates, never-opened envelopes and the invoice you needed last year. The drawer isn't mess: it's the natural result of documents arriving from ten different sources with nowhere to go.

The method below replaces the drawer with three levels, and takes an afternoon to set up.

## The principle: a document lives where it's needed

The classic mistake is organising documents by **type**: an "invoices" folder, a "certificates" one, a "contracts" one. It sounds logical, but when you need a document you don't look for it by type: you look for it by **what it's about**. The tyre shop invoice matters when you're thinking about the car, not when you're thinking about invoices.

So documents should be attached to the thing they refer to. The rest follows.

## Level 1: records

In KidBox, almost every record accepts attachments: the medical visit, the test, the car, the garage service, the appliance, the household deadline, the pet. The document gets uploaded **there**, and the app automatically puts it in the Documents archive too, with a reference to the record it came from.

That means:

- the result sits on the visit, and you find it from that child's [Health section](/en/tools/salute)
- the service invoice sits on the service, in the [Vehicles section](/en/tools/veicoli)
- the warranty sits on the washing machine, in the [Home section](/en/tools/casa)

And in every case the same file is also in [Documents](/en/tools/documenti), in a single view. One file, two ways to reach it.

## Level 2: folders

For what has no record — contracts, deeds, certificates, notices — you need folders. Few, and by **subject**:

- One for **each person** (identity, school, work)
- One for the **home** (contracts, deeds, building)
- One for **money** (bank, insurance, taxes)

Three to five folders are enough. If you need ten, some are really records you haven't used yet.

## Level 3: the wallet

Some documents aren't archived: they're **shown**. Health card, ID card, supermarket loyalty card, train ticket, gym membership. In the [Wallet](/en/tools/wallet) they're cards, with the barcode readable at the till and the expiry visible. And PDF tickets are read by the app, which extracts date, time and seat so you don't have to retype them.

## The entry rule

The system holds if every new document finds its place **when it arrives**, not "when I have time". Thirty seconds at the right moment are worth an hour at year's end.

- Result → attached to the visit
- Invoice → attached to the deadline or service (and the expense is created on its own)
- Contract → in a folder
- Card → in the Wallet

On iPhone the share extension lets you send a PDF from your mail straight into KidBox, without going through the phone's files.

## Why encryption isn't a detail

A family's documents are the most sensitive thing the family owns: identity, health, money, minors. Putting them in a service that can read them means trusting its future choices forever.

In KidBox, documents are encrypted with a **family key** that lives only on the members' devices. The service stores bytes, not content. The practical consequence is that nobody — us included — can open your child's test result. It's why notifications don't show a document preview: we can't generate one.

## Passwords are documents

One last category usually missing from the archive: credentials. School portal, canteen portal, bank, utilities, Wi-Fi. They're documents in every sense, and they need to be shared between parents and encrypted. The [Passwords section](/en/tools/password) does exactly that, with AutoFill on the phone and a security check on weak or reused passwords.

## The afternoon

Concretely:

1. **Empty the drawer** and split into three piles: to throw away, to photograph, to keep as originals.
2. **Photograph** the second pile, one document at a time, straight into the right record.
3. **Create folders** for the rest.
4. **Add the deadlines** you discovered along the way.
5. The third pile goes back into a drawer — a much smaller one.

From that day the drawer stops growing, because new documents have somewhere to go.
""",
        },
    },
    {
        "slug": "storia-sanitaria-dei-figli",
        "category": "organizzazione-familiare", "date": "2026-09-04",
        "tools": ["salute", "documenti"], "related": ["documenti-di-famiglia-in-ordine", "documenti-dei-figli-in-due-case"],
        "it": {
            "title": "La storia sanitaria dei figli: cosa tenere, dove, e perché serve al medico",
            "desc": "Vaccini, visite, esami, cure: come costruire uno storico clinico dei figli che qualunque genitore possa mostrare a qualunque medico, in un tocco.",
            "body": """
«Quando ha fatto l'ultimo richiamo?» «Quanti episodi di otite ha avuto?» «Che antibiotico gli avevate dato l'altra volta?» Sono domande che ogni pediatra fa, e a cui la maggior parte dei genitori risponde «mi pare… dovrei controllare». Non per trascuratezza: perché la storia sanitaria di un bambino è sparsa tra il libretto, i referti in un cassetto, le foto sul telefono e la memoria della madre.

Questo articolo spiega cosa vale la pena tenere, come organizzarlo e perché uno storico ben fatto cambia la qualità delle visite.

## Cosa tenere

Non tutto. Le cose che un medico chiede davvero:

- **Vaccini**: quali, quando, eventuali reazioni
- **Visite**: data, medico, motivo, cosa ha detto, cosa ha prescritto
- **Esami**: analisi, ecografie, radiografie — con il referto
- **Cure in corso e passate**: farmaco, dose, durata, esito
- **Allergie e intolleranze**: la prima cosa che chiede chiunque
- **Crescita**: peso e altezza alle visite di controllo
- **Ricoveri e pronto soccorso**: quando, perché, cosa hanno fatto

Per un bambino sano sono poche righe l'anno. Per uno con una condizione cronica, sono la differenza tra una visita di cinque minuti e una da venti.

## Dove tenerlo

Il libretto cartaceo ha un pregio — è ufficiale — e tre difetti: sta in un posto solo, non contiene i referti, e non ce l'ha mai il genitore che è dal medico quel giorno.

In KidBox la [scheda Salute](/strumenti/salute) è per persona: ogni figlio ha il suo storico di visite, esami, vaccini e cure, con i referti allegati. Tutti e due i genitori lo vedono uguale, sul telefono, sempre. Il libretto cartaceo resta a casa; la sua copia è nella scheda.

## La regola del «subito dopo»

Lo storico si costruisce in un momento preciso: **uscendo dallo studio**. Due minuti in sala d'attesa o in macchina: data, cosa ha detto il medico, la foto della prescrizione. Rimandare a stasera vuol dire dimenticare metà delle cose; rimandare a domani vuol dire non farlo.

Il referto, quando arriva (spesso via email, giorni dopo), si allega alla visita. Da quel momento è nella scheda del figlio e nell'archivio [Documenti](/strumenti/documenti), cifrato.

## La cartella clinica riassuntiva

Il momento in cui lo storico serve di più è quando il medico è **nuovo**: una guardia medica, il pronto soccorso, uno specialista, il pediatra in vacanza. Raccontare tutto da capo è impreciso e lento.

KidBox genera dallo storico una **cartella clinica** riassuntiva: allergie, vaccini, cure in corso, visite recenti, in una pagina da mostrare o condividere. Non sostituisce il medico curante: gli dà, in trenta secondi, quello che altrimenti gli dareste in dieci minuti di ricordi approssimativi.

## I dati dal telefono e dall'orologio

Per i figli più grandi — e per i genitori — l'app legge, se lo volete, i dati di Apple Health e Health Connect: passi, battito, allenamenti. Servono per il [Piano Fitness](/strumenti/salute) e per avere un quadro più ampio, ma è un'aggiunta: lo storico clinico funziona senza.

## Cosa non fare

- **Non mettere i referti in chat.** Sono dati sanitari di un minore: vanno cifrati, non in un backup in chiaro.
- **Non tenere lo storico su un solo telefono.** Se è di famiglia, lo vedono entrambi i genitori. Se è personale, il giorno che serve all'altro non c'è.
- **Non aspettare la condizione cronica per iniziare.** Lo storico di un bambino sano è quello che rende evidente quando qualcosa cambia.

## Il beneficio nascosto

Oltre alle visite migliori, uno storico ben tenuto ha un effetto sul genitore: toglie l'ansia del «me lo ricorderò?». Le informazioni sono lì, complete, ordinate per data, con i documenti. La memoria può occuparsi d'altro.
""",
        },
        "en": {
            "title": "Your kids' health history: what to keep, where, and why the doctor needs it",
            "desc": "Vaccinations, visits, tests, treatments: how to build a clinical history of your kids that either parent can show any doctor, in one tap.",
            "body": """
"When was the last booster?" "How many ear infections has she had?" "Which antibiotic did you give him last time?" Every paediatrician asks these, and most parents answer "I think… I'd have to check". Not out of carelessness: because a child's health history is scattered across the booklet, results in a drawer, photos on a phone and the mother's memory.

This article covers what's worth keeping, how to organise it and why a well-kept history changes the quality of visits.

## What to keep

Not everything. The things a doctor actually asks about:

- **Vaccinations**: which, when, any reactions
- **Visits**: date, doctor, reason, what was said, what was prescribed
- **Tests**: blood work, ultrasounds, X-rays — with the report
- **Current and past treatments**: drug, dose, duration, outcome
- **Allergies and intolerances**: the first thing anyone asks
- **Growth**: weight and height at check-ups
- **Hospital stays and A&E**: when, why, what was done

For a healthy child it's a few lines a year. For one with a chronic condition, it's the difference between a five-minute visit and a twenty-minute one.

## Where to keep it

The paper booklet has one merit — it's official — and three flaws: it lives in one place, it doesn't contain the reports, and the parent at the doctor's that day never has it.

In KidBox the [Health section](/en/tools/salute) is per person: each child has their own history of visits, tests, vaccinations and treatments, with reports attached. Both parents see the same thing, on their phone, always. The paper booklet stays home; its copy is in the record.

## The "right after" rule

The history gets built at one precise moment: **leaving the office**. Two minutes in the waiting room or the car: date, what the doctor said, a photo of the prescription. Postponing to tonight means forgetting half; postponing to tomorrow means not doing it.

The report, when it arrives (often by email, days later), gets attached to the visit. From then on it's in the child's record and in the [Documents](/en/tools/documenti) archive, encrypted.

## The summary medical record

The moment the history matters most is when the doctor is **new**: an out-of-hours doctor, A&E, a specialist, the paediatrician's holiday cover. Telling it all from scratch is imprecise and slow.

KidBox generates a summary **medical record** from the history: allergies, vaccinations, current treatments, recent visits, on one page to show or share. It doesn't replace the regular doctor: it gives them, in thirty seconds, what you'd otherwise give in ten minutes of approximate memories.

## Data from the phone and the watch

For older kids — and for parents — the app can read, if you want, Apple Health and Health Connect data: steps, heart rate, workouts. They feed the [Fitness Plan](/en/tools/salute) and give a wider picture, but they're an extra: the clinical history works without them.

## What not to do

- **Don't put reports in chat.** They're a minor's health data: they belong encrypted, not in a plain-text backup.
- **Don't keep the history on one phone only.** If it's the family's, both parents see it. If it's personal, the day the other needs it, it isn't there.
- **Don't wait for a chronic condition to start.** A healthy child's history is what makes it obvious when something changes.

## The hidden benefit

Beyond better visits, a well-kept history has an effect on the parent: it removes the anxiety of "will I remember?". The information is there, complete, sorted by date, with documents. Memory can go and do something else.
""",
        },
    },
    {
        "slug": "posizione-famiglia-senza-controllo",
        "category": "organizzazione-familiare", "date": "2026-08-30",
        "tools": ["posizione", "chat"], "related": ["calendario-genitori-separati", "routine-della-sera-in-famiglia"],
        "it": {
            "title": "Condividere la posizione in famiglia senza che sembri controllo",
            "desc": "Sapere che il figlio è arrivato a scuola senza chiamarlo, e senza trasformarlo in sorveglianza: regole, avvisi automatici e condivisioni a tempo.",
            "body": """
La condivisione della posizione in famiglia divide: per alcuni è tranquillità, per altri — spesso i figli adolescenti — è sorveglianza. Hanno ragione tutti e due, e la differenza sta in **come** si usa. Questa guida propone un modo che riduce le telefonate senza trasformare i genitori in un pannello di controllo.

## Il problema che risolve davvero

Non è «sapere dov'è mio figlio in ogni istante». È eliminare le domande di routine: «Sei arrivato?», «Dove siete?», «A che ora torni?». Ognuna è una chiamata o un messaggio, spesso a un ragazzino che sta facendo altro e non risponde, e un genitore che aspetta la risposta con un'ansia sproporzionata.

La condivisione della posizione ben impostata risponde a queste domande **da sola**, senza che nessuno debba chiedere.

## Gli avvisi al posto della mappa

L'errore di chi inizia è tenere la mappa aperta. La mappa invita a guardare, e guardare diventa controllare.

L'alternativa sono gli **avvisi automatici sui luoghi**: scuola, casa, casa dei nonni, palestra. Quando un membro della famiglia arriva o parte, gli altri ricevono una notifica. Nient'altro. Non c'è bisogno di aprire la mappa, perché l'informazione che serviva — «è arrivato» — è già arrivata.

In KidBox la [scheda Posizione](/strumenti/posizione) permette di definire questi luoghi e di scegliere, per ciascuno, chi avvisare all'arrivo e alla partenza.

## Le regole di famiglia

La tecnologia è la parte facile. Le regole sono quello che rende la cosa accettabile per tutti:

1. **Vale per tutti, genitori compresi.** Se i figli condividono, condividono anche i genitori. La reciprocità cambia completamente la percezione.
2. **Gli avvisi, non la mappa.** Il genitore si impegna a non aprire la mappa senza motivo. La regola vale finché non c'è un motivo vero (un ritardo grosso, un'emergenza).
3. **Si può spegnere, e si dice.** A un adolescente va data la possibilità di sospendere la condivisione — dicendo che lo fa. La fiducia sta nel «dicendo».
4. **Non si usa per litigare.** «Vedo che eri al centro commerciale invece che in biblioteca» è il modo più rapido per far spegnere la condivisione per sempre.

## Le condivisioni a tempo

Ci sono situazioni in cui serve la posizione precisa per un po': il figlio in gita, il partner che torna di notte da un viaggio, il nonno che va da solo in una città nuova. Per questi casi esiste la **condivisione temporanea**: la posizione in tempo reale per un'ora, tre ore, fino a stasera — poi si spegne da sola.

È l'opposto della sorveglianza: la persona sceglie di farsi seguire per un motivo e per un tempo, e sa quando finisce.

## Con due case

Per i genitori separati la posizione ha un uso in più: i giorni dei passaggi. L'avviso «è arrivato a casa di papà» chiude una domanda che altrimenti passerebbe per un messaggio all'ex — e ogni messaggio in meno, in quel contesto, è un vantaggio. Ne parliamo nell'articolo sul [calendario per genitori separati](/blog/calendario-genitori-separati).

## Quando non usarla

- **Sotto i 10-11 anni** raramente ha senso: il bambino non ha un telefono o è sempre con un adulto.
- **Come sostituto della fiducia.** Se il rapporto con un adolescente è già in crisi, la posizione peggiora le cose. Prima si ricostruisce il rapporto, poi si parla di app.
- **Senza dirlo.** Mai attivare la condivisione sul telefono di qualcuno senza che lo sappia. Oltre a essere sbagliato, è il modo per perdere la fiducia per sempre quando si scopre.

## La misura del successo

Dopo un mese, contate le telefonate «dove sei?». Se sono sparite e nessuno in famiglia ha la sensazione di essere seguito, l'avete impostata bene. Se le telefonate sono sparite ma qualcuno si sente sorvegliato, rileggete le regole — probabilmente la mappa è rimasta aperta troppo.
""",
        },
        "en": {
            "title": "Sharing location as a family without it feeling like surveillance",
            "desc": "Knowing your child got to school without calling, and without turning it into monitoring: rules, automatic alerts and time-limited sharing.",
            "body": """
Location sharing in families divides people: for some it's peace of mind, for others — often teenagers — it's surveillance. Both are right, and the difference is in **how** it's used. This guide proposes a way that cuts the phone calls without turning parents into a control panel.

## The problem it really solves

It isn't "knowing where my child is at every instant". It's removing the routine questions: "Did you get there?", "Where are you?", "What time are you back?". Each is a call or a message, often to a kid busy doing something else who doesn't answer, and a parent waiting for the reply with disproportionate anxiety.

Well-configured location sharing answers those questions **on its own**, without anyone having to ask.

## Alerts instead of the map

The beginner's mistake is keeping the map open. The map invites looking, and looking becomes checking.

The alternative is **automatic place alerts**: school, home, the grandparents' house, the gym. When a family member arrives or leaves, the others get a notification. Nothing else. No need to open the map, because the information that was needed — "he's arrived" — has already arrived.

In KidBox the [Location section](/en/tools/posizione) lets you define these places and choose, for each, who gets alerted on arrival and departure.

## The family rules

Technology is the easy part. The rules are what makes it acceptable to everyone:

1. **It applies to everyone, parents included.** If the kids share, the parents share too. Reciprocity completely changes the perception.
2. **Alerts, not the map.** The parent commits to not opening the map without reason. The rule holds until there's a real reason (a big delay, an emergency).
3. **It can be turned off, and you say so.** A teenager should be able to pause sharing — while saying they're doing it. The trust is in the "saying".
4. **It's never used to argue.** "I see you were at the mall instead of the library" is the fastest way to get sharing switched off for good.

## Time-limited sharing

There are situations where precise location is needed for a while: a child on a school trip, a partner driving back at night, a grandparent alone in a new city. For those there's **temporary sharing**: real-time location for one hour, three hours, until tonight — then it switches off by itself.

It's the opposite of surveillance: the person chooses to be followed for a reason and for a time, and knows when it ends.

## With two homes

For separated parents, location has one extra use: handover days. The alert "arrived at dad's" closes a question that would otherwise go through a message to the ex — and every message fewer, in that context, is a win. We cover it in the article on the [co-parenting calendar](/en/blog/calendario-genitori-separati).

## When not to use it

- **Under 10-11** it rarely makes sense: the child has no phone or is always with an adult.
- **As a substitute for trust.** If the relationship with a teenager is already in crisis, location makes it worse. Rebuild the relationship first, then talk about apps.
- **Without saying so.** Never enable sharing on someone's phone without them knowing. Besides being wrong, it's how you lose trust forever when it comes out.

## The measure of success

After a month, count the "where are you?" calls. If they've gone and nobody in the family feels followed, you've set it up right. If the calls have gone but someone feels watched, reread the rules — the map has probably stayed open too much.
""",
        },
    },
    # ── Organizzazione familiare · secondo lotto ───────────────────────
    {
        "slug": "orari-dopo-scuola-genitori-che-lavorano",
        "category": "organizzazione-familiare", "date": "2026-09-13",
        "tools": ["calendario", "to-do", "posizione"], "related": ["routine-della-sera-in-famiglia", "promemoria-che-funzionano", "posizione-famiglia-senza-controllo"],
        "it": {
            "title": "Il dopo scuola quando lavorate entrambi: orari, uscite e chi va a prendere chi",
            "desc": "Uscita alle 16:10, nuoto alle 17, il grande in piscina e il piccolo dalla nonna. Come organizzare il pomeriggio dei figli quando nessuno dei due è libero alle quattro.",
            "body": """
Per due genitori che lavorano, il problema della giornata non è la mattina: sono le quattro del pomeriggio. La scuola esce, l'ufficio no. In mezzo ci sono sport, catechismo, logopedista, compleanni, i nonni che coprono il martedì ma non il giovedì, la babysitter che il venerdì ha l'esame.

È un incastro che cambia ogni settimana, e si regge quasi sempre sulla memoria di un genitore. Ecco come tirarlo fuori dalla testa.

## 1. La settimana tipo, scritta una volta

Prima di tutto, disegnate la **settimana tipo** del periodo scolastico: per ogni giorno, ogni figlio, dall'uscita da scuola a cena.

- a che ora esce
- dove deve andare dopo (casa, sport, nonni, doposcuola)
- **chi lo porta e chi lo va a prendere**
- a che ora torna a casa

Il risultato di solito sorprende: ci sono due o tre «buchi» che si coprono ogni settimana improvvisando. Sono lì che nascono le telefonate in riunione.

## 2. Tutto nel calendario, con il figlio indicato

La settimana tipo va nel [calendario di famiglia](/strumenti/calendario), non su un foglio: uscite, attività, visite, ciascuna con il figlio a cui si riferisce e un promemoria. La vista **settimana** con la griglia oraria è quella giusta, perché mostra i sovrapposti — il nuoto del grande che finisce quando inizia il calcio del piccolo.

L'evento aggiunto da un genitore compare subito sul telefono dell'altro, e sul computer di chi organizza dall'ufficio.

## 3. Chi va a prendere è una cosa da fare

L'orario dell'uscita è un evento. **Andare a prendere** è un compito, e ha un responsabile. Scriverlo come [cosa da fare](/strumenti/to-do) assegnata — «prendere Giulia a nuoto, 18:15» — con il promemoria che arriva a quella persona e a nessun altro, elimina la domanda più frequente del pomeriggio: «ci vai tu o ci vado io?».

Se un giorno cambia, si riassegna la voce: l'altro lo vede senza bisogno di messaggi.

## 4. Il piano B, prima che serva

Il pomeriggio salta sempre per le stesse ragioni: una riunione che si allunga, un figlio con la febbre, lo sciopero dei mezzi. Decidete prima il piano B per ogni giorno:

- chi è il **primo sostituto** (nonni, un altro genitore della squadra, la babysitter)
- come lo si avvisa, e con quanto anticipo
- dove sono i **contatti** e le deleghe firmate per la scuola

Mettete tutto in una nota condivisa. Nel momento dell'emergenza non c'è tempo per cercare il numero dell'allenatore.

## 5. Sapere che sono arrivati, senza chiamare

Con i figli che iniziano a muoversi da soli — la fermata dell'autobus, il tragitto fino in palestra — la domanda diventa: sono arrivati? La [condivisione della posizione](/strumenti/posizione) di KidBox permette di creare un luogo, come la scuola o la piscina, e ricevere un avviso all'arrivo e alla partenza. È una condivisione che ognuno può accendere e spegnere: ne parliamo in [posizione della famiglia senza controllo](/blog/posizione-famiglia-senza-controllo).

## 6. La riunione della domenica

Dieci minuti la domenica sera: si guarda la settimana, si confermano chi porta e chi prende, si segnano le eccezioni — la gita, la festa, la riunione di classe. È la differenza tra organizzare la settimana e subirla.

## 7. Settembre e giugno

Gli orari cambiano due volte l'anno, a inizio e fine scuola, più ogni volta che parte un'attività nuova. Il momento giusto per rifare la settimana tipo è **prima** del primo giorno, non dopo la prima settimana di caos.

## In sintesi

Una settimana tipo scritta, gli orari nel calendario, il ritiro come cosa da fare con un responsabile, un piano B deciso prima e dieci minuti la domenica. Le quattro del pomeriggio restano un incastro — ma un incastro che conoscete entrambi.
""",
        },
        "en": {
            "title": "After school when you both work: times, pick-ups and who collects whom",
            "desc": "School out at 4:10, swimming at 5, the eldest at the pool and the youngest at grandma's. How to organise the children's afternoons when neither of you is free at four.",
            "body": """
For two working parents, the hard part of the day isn't the morning: it's four in the afternoon. School lets out, the office doesn't. In between there's sport, music lessons, speech therapy, birthday parties, grandparents who cover Tuesday but not Thursday, the babysitter who has an exam on Friday.

It's a puzzle that changes every week, and it almost always rests on one parent's memory. Here's how to get it out of their head.

## 1. The typical week, written once

First, sketch the **typical week** for the school term: for every day and every child, from school pick-up to dinner.

- what time school finishes
- where they go next (home, sport, grandparents, after-school club)
- **who drops them off and who collects them**
- what time they get home

The result is usually surprising: there are two or three "gaps" that get covered every week by improvising. That's where the phone calls in meetings come from.

## 2. Everything in the calendar, with the child named

The typical week goes in the [family calendar](/en/tools/calendario), not on a sheet of paper: pick-ups, activities, appointments, each with the child it concerns and a reminder. The **week** view with the hourly grid is the right one, because it shows overlaps — the eldest's swimming ending just as the youngest's football starts.

An event added by one parent appears immediately on the other's phone, and on the computer of whoever organises from the office.

## 3. Collecting is a to-do

The pick-up time is an event. **Going to collect** is a task, and it has an owner. Writing it as an assigned [to-do](/en/tools/to-do) — "collect Julia from swimming, 6:15" — with the reminder going to that person and nobody else removes the afternoon's most common question: "are you going or am I?".

If a day changes, reassign the item: the other parent sees it without any messages.

## 4. Plan B, before you need it

Afternoons fall apart for the same reasons: a meeting that runs over, a child with a fever, a transport strike. Decide plan B for each day in advance:

- who's the **first substitute** (grandparents, another parent from the team, the babysitter)
- how you tell them, and how far ahead
- where the **contacts** and signed pick-up authorisations for school are

Put it all in a shared note. In the middle of an emergency there's no time to hunt for the coach's number.

## 5. Knowing they've arrived, without calling

Once children start moving on their own — the bus stop, the walk to the gym — the question becomes: have they arrived? KidBox's [location sharing](/en/tools/posizione) lets you create a place, such as school or the pool, and get an alert on arrival and departure. It's sharing each person can switch on and off: more in [family location without surveillance](/en/blog/posizione-famiglia-senza-controllo).

## 6. The Sunday meeting

Ten minutes on Sunday evening: look at the week, confirm who drops off and who collects, note the exceptions — the school trip, the party, the parents' meeting. It's the difference between organising the week and enduring it.

## 7. September and June

Times change twice a year, at the start and end of the school year, plus every time a new activity begins. The right moment to redo the typical week is **before** the first day, not after the first week of chaos.

## In short

A written typical week, times in the calendar, collection as a to-do with an owner, plan B decided in advance and ten minutes on Sunday. Four in the afternoon is still a puzzle — but one you both know.
""",
        },
    },
    {
        "slug": "primo-anno-da-neogenitori",
        "category": "organizzazione-familiare", "date": "2026-09-13",
        "tools": ["salute", "documenti", "calendario", "foto-e-video"], "related": ["storia-sanitaria-dei-figli", "documenti-di-famiglia-in-ordine", "carico-mentale-dei-genitori"],
        "it": {
            "title": "Il primo anno da neogenitori: cosa organizzare, e cosa lasciar perdere",
            "desc": "Visite, vaccini, documenti, bonus, turni di notte e mille foto. Cosa conviene sistemare nelle prime settimane per non doverci pensare mentre si dorme tre ore.",
            "body": """
Nel primo anno di vita di un figlio si dorme poco, si decide tanto e si ricorda pochissimo. Non è il momento di diventare organizzati: è il momento di organizzare **il minimo indispensabile**, così che il resto possa andare come va.

Questa guida separa le cose che conviene sistemare subito da quelle che possono aspettare.

## Cosa sistemare nelle prime settimane

### I documenti del neonato

Nelle prime settimane arrivano, uno dopo l'altro, documenti che serviranno per anni: l'atto di nascita, il codice fiscale, la tessera sanitaria, la scelta del pediatra, le pratiche per i bonus e le detrazioni. Arrivano quando nessuno dei due ha la testa per archiviarli.

La soluzione è una sola cartella, condivisa, in cui **chiunque dei due** li mette appena arrivano: una foto o una scansione basta. In KidBox la scheda [documenti](/strumenti/documenti) è cifrata con la chiave di famiglia, e la tessera sanitaria può stare anche nel wallet, a portata di mano in farmacia.

### Le visite e i vaccini

Il primo anno è fitto: controlli dal pediatra, vaccinazioni, eventuali visite specialistiche. Due regole:

- **ogni appuntamento nel [calendario](/strumenti/calendario) di famiglia**, con promemoria, così lo vede anche chi non ha preso la telefonata
- **ogni visita registrata dopo**, con data, peso, note del pediatra e referto allegato

La seconda sembra una fatica in più. È quella che vi farà rispondere in trenta secondi quando, tra due anni, un medico chiederà «quando ha fatto il richiamo?». Nella scheda [salute](/strumenti/salute) di ogni figlio visite, esami e vaccini restano in ordine, e la cartella clinica riepilogativa si apre in studio.

### Chi fa cosa, di notte e di giorno

Il carico del primo anno tende a finire tutto su un genitore, soprattutto se l'altro rientra al lavoro. Parlatene prima che succeda: turni di notte, chi si occupa delle visite, chi della spesa e delle pratiche. Scritto in una lista condivisa, l'accordo resiste meglio alla stanchezza.

## Cosa può aspettare

- **Il diario perfetto** di poppate, pannolini e sonnellini. Se il pediatra vi chiede di monitorare qualcosa, fatelo; altrimenti non è un obbligo, e una nota con l'essenziale basta. KidBox non ha un diario delle poppate, e per molte famiglie non serve.
- **L'album fotografico ordinato.** Le foto si fanno comunque; ordinarle può aspettare. Basta che finiscano in un posto solo, condiviso tra i due genitori, invece che sparse su due telefoni.
- **L'organizzazione della casa** come prima. Per qualche mese la casa sarà meno in ordine. Va bene.

## Le foto, in un posto solo

Nel primo anno si scattano migliaia di foto, metà sul telefono di un genitore e metà su quello dell'altro, più quelle mandate in chat e compresse. Un [album condiviso](/strumenti/foto-e-video) di famiglia, in qualità piena e cifrato, risolve il problema a monte: tutti e due caricate lì, e il primo anno esiste intero in un posto.

## La rete intorno

Nonni, zii, amici che si offrono di aiutare: l'aiuto funziona quando è **concreto e programmato**. Una spesa da fare il giovedì, un pomeriggio di sonno il sabato. Scriverlo nel calendario lo trasforma da offerta generica in aiuto vero.

## In sintesi

Nelle prime settimane: una cartella per i documenti, ogni visita nel calendario e registrata dopo, un accordo scritto su chi fa cosa, le foto in un album comune. Il resto può aspettare. Il primo anno non va ottimizzato: va attraversato, possibilmente senza dover ricordare dove avete messo il codice fiscale.
""",
        },
        "en": {
            "title": "The first year as new parents: what to organise, and what to let go",
            "desc": "Check-ups, vaccinations, documents, benefits, night shifts and a thousand photos. What to sort out in the first weeks so you don't have to think about it on three hours' sleep.",
            "body": """
In a child's first year you sleep little, decide a lot and remember almost nothing. It isn't the moment to become organised: it's the moment to organise **the bare minimum**, so everything else can go however it goes.

This guide separates what's worth sorting out straight away from what can wait.

## What to sort out in the first weeks

### The baby's documents

In the first weeks, one after another, documents arrive that you'll need for years: the birth certificate, tax and health registration, the choice of paediatrician, the paperwork for benefits. They arrive when neither of you has the headspace to file them.

There's one solution: a single shared folder where **either of you** puts them as they arrive — a photo or scan is enough. In KidBox the [documents](/en/tools/documenti) section is encrypted with the family key, and the health card can also live in the wallet, handy at the pharmacy.

### Check-ups and vaccinations

The first year is busy: paediatric check-ups, vaccinations, perhaps specialist visits. Two rules:

- **every appointment in the family [calendar](/en/tools/calendario)**, with a reminder, so whoever didn't take the call sees it too
- **every visit recorded afterwards**, with date, weight, the paediatrician's notes and the report attached

The second one looks like extra effort. It's what lets you answer in thirty seconds when, two years from now, a doctor asks "when was the booster?". In each child's [health](/en/tools/salute) section visits, tests and vaccinations stay in order, and the summary record opens right there in the surgery.

### Who does what, night and day

The first-year load tends to fall entirely on one parent, especially once the other goes back to work. Talk about it before it happens: night shifts, who handles appointments, who handles groceries and paperwork. Written in a shared list, the agreement survives tiredness better.

## What can wait

- **The perfect log** of feeds, nappies and naps. If the paediatrician asks you to monitor something, do it; otherwise it isn't compulsory, and a note with the essentials is enough. KidBox doesn't have a feeding log, and many families don't need one.
- **The tidy photo album.** Photos get taken anyway; sorting them can wait. As long as they end up in one shared place, instead of scattered across two phones.
- **Running the house** like before. For a few months the house will be less tidy. That's fine.

## Photos, in one place

In the first year you take thousands of photos, half on one parent's phone and half on the other's, plus the compressed ones sent in chat. A shared family [album](/en/tools/foto-e-video), in full quality and encrypted, solves the problem at the source: you both upload there, and the first year exists in full in one place.

## The support network

Grandparents, aunts and uncles, friends offering to help: help works when it's **concrete and scheduled**. A grocery run on Thursday, an afternoon nap on Saturday. Putting it in the calendar turns a generic offer into real help.

## In short

In the first weeks: one folder for documents, every appointment in the calendar and recorded afterwards, a written agreement on who does what, photos in a shared album. The rest can wait. The first year isn't something to optimise: it's something to get through, ideally without having to remember where you put the birth certificate.
""",
        },
    },
    {
        "slug": "assistenza-a-un-familiare-turni",
        "category": "organizzazione-familiare", "date": "2026-09-13",
        "tools": ["calendario", "to-do", "documenti", "spese"], "related": ["documenti-di-famiglia-in-ordine", "promemoria-che-funzionano", "carico-mentale-dei-genitori"],
        "it": {
            "title": "Assistere un genitore anziano tra fratelli: turni, visite, documenti e spese",
            "desc": "Quando un genitore ha bisogno di aiuto, i figli si ritrovano a coordinarsi come non facevano da anni. Come dividere turni e informazioni senza che tutto ricada su uno.",
            "body": """
Succede quasi sempre all'improvviso: una caduta, una diagnosi, un ricovero. Un genitore che fino a ieri faceva da sé ha bisogno di qualcuno che lo accompagni alle visite, gli faccia la spesa, controlli le medicine, parli con il medico. E i figli adulti — ognuno con il suo lavoro, i suoi figli, la sua città — si ritrovano a doversi coordinare.

Il rischio è noto: l'assistenza ricade sul figlio che abita più vicino, o su quello che «ha più tempo», e gli altri aiutano quando possono. Qualche mese dopo, quel figlio è esausto e gli altri non capiscono perché.

Questa guida riguarda la parte organizzativa. Per le scelte di cura, i servizi sociali e le pratiche di invalidità o assistenza, i riferimenti sono il medico di base e gli uffici competenti.

## 1. Fare l'inventario dell'assistenza

Prima di dividere, bisogna vedere. Mettete per iscritto tutto quello che serve in una settimana:

- **visite ed esami**: chi accompagna, chi parla con il medico
- **farmaci**: chi li compra, chi controlla che vengano presi, chi rinnova le ricette
- **spesa e pasti**
- **casa**: pulizie, bollette, piccole riparazioni
- **pratiche**: pensione, esenzioni, domande di assistenza
- **compagnia**: le visite che non hanno uno scopo pratico, e che contano quanto le altre

Come per le faccende di casa, il lavoro più pesante è quello invisibile: accorgersi, ricordare, telefonare.

## 2. Un calendario per l'assistenza

Visite, turni di presenza, consegne della spesa: tutto in un [calendario](/strumenti/calendario) condiviso tra i fratelli, con promemoria. In KidBox si può creare una famiglia apposita per l'assistenza e farne parte insieme alla propria, passando dall'una all'altra dalle Impostazioni: così i turni per il genitore non si mescolano con gli impegni dei vostri figli. Il piano gratuito copre due persone: se i fratelli sono di più, i dettagli sono nella [sezione piani](/index.html#prezzi).

Chi abita lontano vede tutto e capisce quando serve la sua presenza, invece di scoprirlo da una telefonata stanca.

## 3. Ogni compito ha un nome

«Qualcuno deve rinnovare la ricetta» significa che nessuno lo farà. Ogni voce diventa una [cosa da fare](/strumenti/to-do) assegnata a un fratello preciso, con un promemoria. Anche chi abita lontano può prendersi compiti veri: le pratiche online, le telefonate con l'ufficio, la prenotazione degli esami.

## 4. I documenti in un posto solo

Referti, lettere di dimissione, piani terapeutici, tessera sanitaria, deleghe: nel momento del bisogno servono subito, e di solito sono nel cassetto di chi c'era l'ultima volta. Una cartella condivisa di [documenti](/strumenti/documenti), cifrata, in cui ogni fratello carica quello che riceve, evita di rifare la stessa domanda al medico tre volte.

Tenete anche una nota condivisa con l'essenziale: farmaci e dosaggi, allergie, numeri del medico e della farmacia.

## 5. Le spese, senza conti in sospeso

L'assistenza costa: farmaci, visite private, una badante per qualche ora, i taxi per l'ospedale. Se ognuno paga quello che capita e nessuno lo scrive, dopo sei mesi nascono i sospetti. Registrare ogni spesa nelle [spese](/strumenti/spese) condivise, con chi ha pagato, rende i conti trasparenti — e una conversazione sui soldi possibile.

## 6. Proteggere chi fa di più

Ci sarà sempre un fratello che fa di più, per vicinanza o per carattere. Il calendario condiviso rende visibile quanto: usatelo per ridistribuire, non per misurare. E prevedete **pause vere** per chi è presente ogni giorno, programmate come si programmano le visite.

## In sintesi

Un inventario di tutto quello che serve, un calendario comune per turni e visite, ogni compito con un nome, i documenti in un posto solo e le spese scritte. L'assistenza a un genitore resta pesante — ma pesa molto meno quando non la porta una persona sola.
""",
        },
        "en": {
            "title": "Caring for an elderly parent among siblings: turns, appointments, documents and costs",
            "desc": "When a parent needs help, adult children find themselves coordinating as they haven't in years. How to share turns and information without everything landing on one person.",
            "body": """
It almost always happens suddenly: a fall, a diagnosis, a hospital stay. A parent who managed alone until yesterday now needs someone to take them to appointments, do their shopping, check their medicines, talk to the doctor. And the adult children — each with their own job, children and city — find themselves having to coordinate.

The risk is well known: care falls on the child who lives closest, or the one who "has more time", and the others help when they can. A few months later, that child is exhausted and the others don't understand why.

This guide covers the organisational side. For care decisions, social services and disability or care applications, the right reference is the family doctor and the relevant offices.

## 1. Take an inventory of the care

Before dividing, you have to see. Write down everything needed in a week:

- **appointments and tests**: who accompanies, who talks to the doctor
- **medicines**: who buys them, who checks they're taken, who renews prescriptions
- **shopping and meals**
- **the home**: cleaning, bills, small repairs
- **paperwork**: pension, exemptions, care applications
- **company**: visits with no practical purpose, which matter as much as the others

As with household chores, the heaviest work is the invisible kind: noticing, remembering, phoning.

## 2. A calendar for care

Appointments, turns being present, grocery deliveries: all in a [calendar](/en/tools/calendario) shared between siblings, with reminders. In KidBox you can create a family specifically for the care and belong to it alongside your own, switching between them from Settings: so the turns for your parent don't mix with your children's commitments. The free plan covers two people: if there are more siblings, details are in the [plans section](/index-en.html#prezzi).

Whoever lives far away sees everything and understands when they're needed, instead of finding out from a tired phone call.

## 3. Every task has a name

"Someone needs to renew the prescription" means nobody will. Every item becomes a [to-do](/en/tools/to-do) assigned to a specific sibling, with a reminder. Even those who live far away can take on real tasks: online paperwork, calls with the office, booking tests.

## 4. Documents in one place

Medical reports, discharge letters, treatment plans, health card, authorisations: when they're needed they're needed now, and they're usually in the drawer of whoever was there last. A shared, encrypted [documents](/en/tools/documenti) folder where each sibling uploads what they receive avoids asking the doctor the same question three times.

Keep a shared note with the essentials too: medicines and doses, allergies, the doctor's and pharmacy's numbers.

## 5. Costs, without unsettled accounts

Care costs money: medicines, private appointments, a carer for a few hours, taxis to the hospital. If everyone pays whatever comes up and nobody writes it down, suspicion sets in after six months. Recording every cost in shared [expenses](/en/tools/spese), with who paid, keeps the accounts transparent — and makes a conversation about money possible.

## 6. Protect whoever does the most

There will always be a sibling who does more, through proximity or temperament. The shared calendar shows how much: use it to redistribute, not to keep score. And plan **real breaks** for whoever is there every day, scheduled the way appointments are.

## In short

An inventory of everything needed, a common calendar for turns and appointments, every task with a name, documents in one place and costs written down. Caring for a parent stays heavy — but it weighs far less when one person isn't carrying it alone.
""",
        },
    },
]
