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
]
