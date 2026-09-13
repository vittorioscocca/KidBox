# -*- coding: utf-8 -*-
"""
Contenuti del Blog della landing, in italiano e in inglese. Il generatore
(`scripts/build_blog.py`) li trasforma nelle pagine sotto `public/blog/` e
`public/en/blog/`.

Gli articoli sono ORIGINALI: gli argomenti seguono quelli tipici dei blog degli
organizer di famiglia, i testi sono scritti attorno a quello che KidBox fa
davvero (vedi ../FEATURES.md). Non copiare testi altrui qui dentro.

Struttura:
  CATEGORIES  slug → {it/en: (titolo breve per la card, titolo lungo della
              sezione, descrizione)}; l'ordine è quello della pagina indice.
  ARTICLES    una voce per articolo:
    slug      parte finale dell'URL (uguale nelle due lingue)
    category  slug della categoria
    date      ISO, data di pubblicazione/aggiornamento
    tools     slug degli Strumenti collegati (public/strumenti/<slug>)
    related   slug di altri articoli da linkare in fondo
    it / en   title, desc (meta + card), body

Il body usa un markdown minimo, convertito dal generatore:
  ## Titolo        → h2          ### Titolo → h3
  - voce           → elenco puntato      1. voce → elenco numerato
  > testo          → riquadro in evidenza
  **grassetto**, [testo](url); i link relativi al sito partono da "/"
  Un paragrafo per blocco, separati da una riga vuota.
"""

CATEGORIES = {
    "casa-e-faccende": {
        "it": ("Casa e faccende", "Casa e faccende: la guida completa",
               "Dividere i compiti senza discussioni, tenere dietro alle scadenze di casa e far girare la routine domestica con tutta la famiglia a bordo."),
        "en": ("Home and chores", "Home and chores: the complete guide",
               "Splitting tasks without arguments, keeping up with household deadlines and running the home routine with the whole family on board."),
    },
    "genitori-separati": {
        "it": ("Genitori separati", "Co-genitorialità: organizzarsi in due case senza attriti",
               "Calendario dei turni, spese condivise, documenti dei figli e comunicazione che non degenera: la logistica della separazione, fatta bene."),
        "en": ("Co-parenting", "Co-parenting: running two homes without friction",
               "Custody calendar, shared expenses, the kids' documents and communication that stays civil: the logistics of separation, done right."),
    },
    "confronti": {
        "it": ("Confronti tra app", "Confronti: quale app di famiglia scegliere",
               "Cosa guardare davvero quando scegli un organizer di famiglia, e perché calendario condiviso, chat e note sparse non bastano."),
        "en": ("App comparisons", "Comparisons: which family app to choose",
               "What actually matters when picking a family organiser, and why a shared calendar, a chat and scattered notes aren't enough."),
    },
    "organizzazione-familiare": {
        "it": ("Organizzazione familiare", "Organizzazione familiare: la guida completa a una casa che funziona",
               "Documenti, salute, scadenze, password e ricordi di tutta la famiglia in un posto solo, accessibile a tutti e due i genitori."),
        "en": ("Family organisation", "Family organisation: the complete guide to a home that works",
               "Documents, health, deadlines, passwords and memories of the whole family in one place, reachable by both parents."),
    },
    "pasti-e-spesa": {
        "it": ("Pasti e spesa", "Pasti e spesa: pianificare senza impazzire",
               "Lista della spesa condivisa, menù della settimana e un frigo che non si svuota mai a sorpresa."),
        "en": ("Meals and groceries", "Meals and groceries: planning without losing your mind",
               "A shared grocery list, the week's menu and a fridge that never runs empty by surprise."),
    },
    "produttivita-in-casa": {
        "it": ("Produttività in casa", "Organizzarsi in casa: routine, tempo e lucidità per i genitori",
               "Routine che reggono, promemoria che arrivano al momento giusto e meno carico mentale per chi tiene insieme la famiglia."),
        "en": ("Productivity at home", "Getting organised at home: routines, time and clarity for parents",
               "Routines that hold, reminders that land at the right moment and less mental load for whoever keeps the family together."),
    },
}

ARTICLES = [
    # ── Casa e faccende ─────────────────────────────────────────────────
    {
        "slug": "faccende-per-eta-bambini",
        "category": "casa-e-faccende", "date": "2026-09-10",
        "tools": ["to-do", "casa"], "related": ["dividere-le-faccende-in-coppia", "routine-della-sera-in-famiglia"],
        "it": {
            "title": "Faccende adatte all'età dei bambini, dai 2 ai 17 anni",
            "desc": "Cosa può fare davvero un bambino a ogni età, come assegnarlo senza litigare e come tenerne traccia con una lista di famiglia condivisa.",
            "body": """
I bambini vogliono aiutare molto prima di quanto pensiamo, e smettono di volerlo più o meno nel momento in cui glielo chiediamo come un obbligo. Il trucco non è trovare la faccenda giusta, ma assegnarla nel modo giusto: compiti proporzionati all'età, sempre gli stessi, visibili a tutta la famiglia.

Questa guida elenca cosa può fare un figlio a ogni età e come trasformarlo in una routine che regge, senza tabelle appese al frigo che dopo due settimane nessuno guarda più.

## Perché le faccende contano (più di quanto sembri)

Non è questione di avere una casa pulita. Un bambino che apparecchia ogni sera impara che la famiglia funziona perché ognuno fa la sua parte. Gli studi sui bambini che crescono con piccole responsabilità domestiche mostrano più autonomia, più fiducia in sé e meno conflitti da adolescenti. Il costo è sopportare un tavolo apparecchiato male per qualche mese.

## 2-3 anni: imitare

A questa età aiutare è un gioco. Non aspettarti risultati, aspettati partecipazione.

- Mettere i giocattoli nella cesta
- Portare i vestiti sporchi al cesto
- Buttare la carta nel cestino
- «Aiutare» a spolverare con un panno

Non assegnare nulla: fallo insieme e ringrazia. La faccenda è il tempo passato accanto a te.

## 4-5 anni: piccoli compiti fissi

Qui nascono le prime responsabilità vere, una o due al massimo, sempre le stesse.

- Apparecchiare (posate e tovaglioli)
- Dare da mangiare al cane o al gatto
- Riordinare la camera con un aiuto
- Mettere le scarpe al loro posto

> Una sola regola: la faccenda si fa **sempre alla stessa ora**. «Prima di cena apparecchi» funziona, «quando hai tempo apparecchi» no.

## 6-8 anni: la prima lista

A sei anni un bambino può avere una lista sua. È il momento di smettere di ricordarglielo a voce e di dargli qualcosa da spuntare.

- Rifare il letto
- Svuotare la lavastoviglie (le cose in basso)
- Preparare lo zaino la sera
- Innaffiare le piante
- Portare fuori la spazzatura leggera

In KidBox le [liste di cose da fare](/strumenti/to-do) sono di famiglia e ogni voce si può assegnare a una persona: il bambino vede le sue, tu vedi se le ha spuntate, senza chiedere.

## 9-11 anni: responsabilità con scadenza

Preadolescenti: possono gestire compiti che richiedono più passaggi e un orario.

- Caricare e avviare la lavatrice
- Cucinare qualcosa di semplice con supervisione
- Sistemare la spesa quando arriva
- Tenere in ordine il proprio spazio studio
- Occuparsi dell'animale di casa per intero

Qui i promemoria diventano utili. Una notifica alle 18 «svuota la lavastoviglie» vale più di tre richiami a voce, soprattutto perché non arriva da te.

## 12-14 anni: autonomia

Un tredicenne può fare praticamente qualunque faccenda di casa. Il problema non è la capacità, è la negoziazione.

- Cucinare una cena a settimana
- Fare la spesa piccola con la lista condivisa
- Pulire il bagno
- Gestire il proprio bucato dall'inizio alla fine
- Occuparsi dei fratelli piccoli per brevi periodi

Il consiglio più utile a questa età: lascia scegliere. Metti quattro faccende nella lista e chiedi quali due preferisce. La scelta trasforma un obbligo in un impegno preso.

## 15-17 anni: compiti da adulto

Un adolescente grande dovrebbe già saper mandare avanti la casa per un weekend. Le faccende diventano un allenamento per quando andrà a vivere da solo.

- Pianificare e cucinare pasti interi
- Fare la spesa completa
- Piccole manutenzioni (lampadine, montaggio, riparazioni semplici)
- Gestire una scadenza di famiglia, tipo la revisione dello scooter
- Prendere e riportare i fratelli

Se in casa usate KidBox, dategli accesso alla [scheda Casa](/strumenti/casa) con le scadenze: imparare che la bolletta arriva ogni due mesi e la garanzia della lavatrice finisce a marzo è educazione domestica vera.

## Come assegnare le faccende senza litigare

1. **Poche e fisse.** Meglio due faccende ogni giorno che dieci a rotazione.
2. **Scritte, non dette.** Una lista che il bambino vede da solo toglie il genitore dal ruolo di sorvegliante.
3. **Con un orario.** «Entro le 19» è chiaro; «nel pomeriggio» no.
4. **Tutti e due i genitori la vedono uguale.** La causa più comune di caos è un genitore che assegna e l'altro che non lo sa. Con una lista di famiglia condivisa non succede.
5. **Riconosci, non premiare.** Un «grazie, senza di te non era pronto» dura più di una paghetta.

## E se non le fa?

Succede. La regola che funziona meglio: nessuna discussione, la faccenda resta nella lista e non si passa alla cosa piacevole (schermo, uscita) finché non è spuntata. La lista fa il lavoro sporco al posto tuo, e il litigio non parte perché non c'è nessuno con cui litigare.
""",
        },
        "en": {
            "title": "Age-appropriate chores for kids, from 2 to 17",
            "desc": "What a child can really do at each age, how to assign it without arguments and how to keep track with a shared family list.",
            "body": """
Kids want to help long before we expect it, and stop wanting to roughly when we start asking as an obligation. The trick isn't finding the right chore, it's assigning it the right way: tasks that fit the age, always the same ones, visible to the whole family.

This guide lists what a child can do at each age and how to turn it into a routine that holds — without a chart on the fridge nobody looks at after two weeks.

## Why chores matter (more than it seems)

It's not about a clean house. A child who sets the table every evening learns that the family works because everyone does their part. Studies on children who grow up with small household responsibilities show more independence, more self-confidence and fewer conflicts as teenagers. The cost is putting up with a badly set table for a few months.

## Ages 2-3: copying you

At this age helping is a game. Don't expect results, expect participation.

- Putting toys in the basket
- Carrying dirty clothes to the hamper
- Throwing paper in the bin
- "Helping" dust with a cloth

Don't assign anything: do it together and say thank you. The chore is the time spent next to you.

## Ages 4-5: small fixed tasks

The first real responsibilities start here, one or two at most, always the same.

- Setting the table (cutlery and napkins)
- Feeding the dog or cat
- Tidying the bedroom with help
- Putting shoes where they belong

> One rule: the chore happens **at the same time every day**. "You set the table before dinner" works; "you set the table when you have time" doesn't.

## Ages 6-8: the first list

At six a child can have a list of their own. It's time to stop reminding them out loud and give them something to tick off.

- Making the bed
- Emptying the dishwasher (the bottom rack)
- Packing the school bag in the evening
- Watering the plants
- Taking out the light rubbish

In KidBox, [to-do lists](/en/tools/to-do) belong to the family and every item can be assigned to a person: the child sees theirs, you see whether they've ticked them, without asking.

## Ages 9-11: responsibility with a deadline

Pre-teens can handle tasks with several steps and a time attached.

- Loading and starting the washing machine
- Cooking something simple with supervision
- Putting the groceries away when they arrive
- Keeping their study space in order
- Looking after the family pet entirely

This is where reminders become useful. A notification at 6pm saying "empty the dishwasher" is worth more than three verbal nudges — mostly because it doesn't come from you.

## Ages 12-14: independence

A thirteen-year-old can do practically any household chore. The problem isn't ability, it's negotiation.

- Cooking one dinner a week
- Doing a small shop with the shared list
- Cleaning the bathroom
- Handling their own laundry start to finish
- Watching younger siblings for short stretches

The most useful tip at this age: let them choose. Put four chores in the list and ask which two they'd rather take. Choice turns an obligation into a commitment.

## Ages 15-17: adult-level tasks

An older teenager should be able to run the house for a weekend. Chores become training for living alone.

- Planning and cooking full meals
- Doing the complete grocery shop
- Small maintenance (light bulbs, assembly, simple repairs)
- Owning a family deadline, like the scooter's inspection
- Picking up and dropping off siblings

If your family uses KidBox, give them access to the [Home section](/en/tools/casa) with its deadlines: learning that the bill comes every two months and the washing machine's warranty ends in March is real domestic education.

## How to assign chores without arguments

1. **Few and fixed.** Two chores every day beat ten on rotation.
2. **Written, not spoken.** A list the child can see on their own takes the parent out of the supervisor role.
3. **With a time.** "By 7pm" is clear; "in the afternoon" isn't.
4. **Both parents see the same thing.** The most common cause of chaos is one parent assigning and the other not knowing. A shared family list removes that.
5. **Acknowledge, don't reward.** A "thanks, it wouldn't have been ready without you" lasts longer than pocket money.

## What if they don't do it?

It happens. The rule that works best: no discussion, the chore stays in the list and the nice thing (screen, going out) doesn't happen until it's ticked. The list does the dirty work for you, and the argument never starts because there's nobody to argue with.
""",
        },
    },
    {
        "slug": "dividere-le-faccende-in-coppia",
        "category": "casa-e-faccende", "date": "2026-09-08",
        "tools": ["to-do", "spese"], "related": ["faccende-per-eta-bambini", "lista-condivisa-per-coppie", "carico-mentale-dei-genitori"],
        "it": {
            "title": "Dividere le faccende in coppia senza tenere il conto",
            "desc": "Perché le liti sulle faccende non riguardano le faccende, e un metodo in quattro passi per dividerle in modo che regga nel tempo.",
            "body": """
Quasi nessuna coppia litiga perché il bagno è sporco. Si litiga perché uno dei due ha l'impressione di fare tutto, l'altro ha l'impressione di sentirselo dire di continuo, e nessuno dei due ha un modo per verificarlo. Il problema delle faccende non è la quantità di lavoro: è che il lavoro è invisibile.

## Il lavoro invisibile

Portare fuori la spazzatura è visibile: si vede il sacchetto, si vede chi lo porta. Ricordarsi che la spazzatura va portata fuori il martedì, che i sacchetti stanno finendo e che bisogna comprarli, non si vede. Chi si occupa della seconda parte — di solito sempre la stessa persona — fa il doppio del lavoro e ne riceve metà del riconoscimento.

La prima cosa da fare, quindi, non è dividere le faccende. È **scriverle tutte**, comprese quelle che nessuno considera faccende.

## Passo 1: l'inventario completo

Una sera, insieme, elencate tutto quello che serve per far funzionare la casa in una settimana. Tutto: dalla lavatrice al pensare al regalo per la festa di sabato, dal pagare la bolletta al chiamare il pediatra per il certificato.

Risultato tipico: tra 60 e 90 voci. Ed è quasi sempre una sorpresa per uno dei due.

Fatelo in una [lista condivisa](/strumenti/to-do) invece che su un foglio: la lista poi diventa lo strumento di lavoro, non un esercizio fatto una volta.

## Passo 2: dividere per responsabilità, non per compito

L'errore classico è dividere i compiti: tu la lavatrice, io i piatti. Funziona finché non serve pensare. Dividete invece le **aree**: chi si prende la spesa si prende anche il pensare alla spesa, la lista, gli acquisti mancanti, le offerte. Chi si prende la scuola si prende le comunicazioni, le gite, i moduli, le firme.

Quando un'area è tua per intero, nessuno deve ricordartela. E la persona che ha sempre tenuto tutto in testa può, per la prima volta, smettere di farlo per quell'area.

## Passo 3: equità, non uguaglianza

Non serve che le aree siano identiche in numero. Serve che il carico percepito sia simile. Chi lavora fuori dodici ore non può prendersi la cena tutte le sere; chi lavora da casa non deve per forza prendersi tutto il resto. Rifate i conti ogni pochi mesi, perché la vita cambia.

Un criterio che aiuta: ognuno dovrebbe avere almeno un'area che **gli piace** e una che detesta. Se uno dei due ha solo quelle che detesta, la divisione non reggerà.

## Passo 4: rendere visibile il fatto

Qui entra lo strumento. Il motivo per cui le divisioni verbali falliscono è che dopo tre settimane nessuno ricorda cosa si era deciso, e si ricomincia a tenere il conto a mente — che è il modo peggiore di tenerlo.

Con una lista di famiglia:

- ogni voce ha un responsabile e, se serve, un giorno
- quando è fatta si spunta, e l'altro lo vede senza chiedere
- le cose ricorrenti tornano da sole
- il promemoria arriva dal telefono, non dal partner

L'ultimo punto è quello che cambia davvero il clima in casa. «Hai portato fuori la spazzatura?» chiesto da una persona è un rimprovero; lo stesso messaggio da una notifica è un'informazione.

## Le spese seguono la stessa logica

Le faccende hanno una cugina: i soldi. Chi compra cosa, chi ha anticipato la visita, chi ha pagato l'assicurazione. Anche qui il conto a mente è il nemico. In KidBox le [spese di famiglia](/strumenti/spese) si registrano per categoria e chi ha pagato, e quelle che nascono da una scadenza di casa o da un intervento dell'auto compaiono da sole. A fine mese il quadro è lì, e nessuno deve fare la voce di quello che «paga sempre tutto».

## Tre errori da evitare

1. **Rifare il lavoro dell'altro.** Se il partner stende il bucato in modo diverso dal tuo, il bucato è steso. Ristenderlo è il modo più rapido per fargli smettere di farlo.
2. **Il controllo travestito da aiuto.** «Ti ricordo che domani devi…» è un'intrusione nell'area dell'altro. Lascia che il promemoria lo metta lui.
3. **Non rivedere mai la divisione.** Un figlio nuovo, un lavoro nuovo, un trasloco: ogni cambiamento grosso richiede di rifare l'inventario.

## Il vero obiettivo

Non è una casa perfetta. È che nessuno dei due vada a dormire con la sensazione di essere l'unico a tenere tutto insieme. Quando il lavoro è scritto, assegnato e visibile, quella sensazione sparisce — perché i fatti sono lì, e non serve più discuterli.
""",
        },
        "en": {
            "title": "Splitting chores as a couple without keeping score",
            "desc": "Why arguments about chores are never about chores, and a four-step method to divide them in a way that lasts.",
            "body": """
Almost no couple argues because the bathroom is dirty. They argue because one feels they do everything, the other feels they hear it constantly, and neither has a way to check. The problem with chores isn't the amount of work: it's that the work is invisible.

## The invisible work

Taking out the rubbish is visible: you see the bag, you see who carries it. Remembering that the rubbish goes out on Tuesday, that the bags are running low and that someone needs to buy them — that's not visible. Whoever handles the second part (usually always the same person) does twice the work and gets half the credit.

So the first thing to do isn't dividing the chores. It's **writing them all down**, including the ones nobody thinks of as chores.

## Step 1: the full inventory

One evening, together, list everything it takes to run the house for a week. Everything: from the laundry to thinking about the gift for Saturday's party, from paying the bill to calling the paediatrician for the certificate.

Typical result: between 60 and 90 items. And it's almost always a surprise to one of you.

Do it in a [shared list](/en/tools/to-do) rather than on paper: the list then becomes the working tool, not a one-off exercise.

## Step 2: divide by responsibility, not by task

The classic mistake is dividing tasks: you do the laundry, I do the dishes. It works until thinking is required. Divide **areas** instead: whoever takes groceries also takes thinking about groceries, the list, what's missing, the offers. Whoever takes school takes the communications, the trips, the forms, the signatures.

When an area is entirely yours, nobody has to remind you. And the person who has always kept everything in their head can, for the first time, stop doing it for that area.

## Step 3: fairness, not equality

Areas don't need to be equal in number. The perceived load needs to be similar. Someone working twelve hours outside can't take dinner every night; someone working from home doesn't automatically get everything else. Redo the maths every few months, because life changes.

A criterion that helps: each of you should have at least one area you **like** and one you hate. If one of you only has the ones they hate, the split won't hold.

## Step 4: make what's done visible

This is where the tool comes in. Verbal splits fail because after three weeks nobody remembers what was decided, and you go back to keeping score in your head — the worst place to keep it.

With a family list:

- every item has an owner and, if needed, a day
- when it's done it gets ticked, and the other person sees it without asking
- recurring things come back on their own
- the reminder comes from the phone, not from the partner

That last point is what really changes the mood at home. "Did you take the rubbish out?" from a person is a reproach; the same message from a notification is information.

## Expenses follow the same logic

Chores have a cousin: money. Who bought what, who paid for the check-up, who covered the insurance. Here too, mental accounting is the enemy. In KidBox, [family expenses](/en/tools/spese) are logged by category and by who paid, and the ones that come from a household deadline or a car service show up on their own. At the end of the month the picture is there, and nobody has to play the one who "always pays for everything".

## Three mistakes to avoid

1. **Redoing the other person's work.** If your partner hangs the laundry differently from you, the laundry is hung. Rehanging it is the fastest way to make them stop.
2. **Control disguised as help.** "Just reminding you that tomorrow you have to…" is an intrusion into the other person's area. Let them set their own reminder.
3. **Never reviewing the split.** A new baby, a new job, a move: every big change means redoing the inventory.

## The real goal

It isn't a perfect house. It's that neither of you goes to bed feeling like the only one holding everything together. When the work is written down, assigned and visible, that feeling goes away — because the facts are right there, and there's nothing left to argue about.
""",
        },
    },
    {
        "slug": "scadenze-di-casa-bollette-garanzie",
        "category": "casa-e-faccende", "date": "2026-09-05",
        "tools": ["casa", "veicoli", "documenti"], "related": ["dividere-le-faccende-in-coppia", "documenti-di-famiglia-in-ordine", "promemoria-che-funzionano"],
        "it": {
            "title": "Bollette, garanzie e revisioni: le scadenze di casa che nessuno ricorda",
            "desc": "Le scadenze domestiche costano soldi quando si dimenticano. Come metterle tutte in un posto solo, con i documenti attaccati, e non pensarci più.",
            "body": """
Una casa produce scadenze in continuazione: la bolletta della luce, la rata dell'assicurazione, la garanzia del frigorifero che finisce, la revisione dell'auto, il rinnovo del contratto di affitto, la caldaia da far controllare. Nessuna è difficile. Il problema è che sono trenta, sparse tra email, cassetti e la memoria di una sola persona.

Dimenticarne una costa: una mora, una garanzia persa, una multa. Questa guida spiega come costruire un sistema che le tenga tutte, una volta sola.

## Il censimento: cosa scade in casa tua

Prendete un'ora e fate l'elenco. Le categorie che quasi tutte le famiglie hanno:

- **Utenze**: luce, gas, acqua, internet, telefono. Mensili o bimestrali.
- **Assicurazioni**: auto, casa, vita, sanitaria. Annuali, spesso in date diverse.
- **Tasse e tributi**: rifiuti, bollo auto, imposte sulla casa.
- **Contratti**: affitto, abbonamenti, servizi in rinnovo automatico.
- **Garanzie**: elettrodomestici, telefoni, computer. Si dimenticano sempre.
- **Manutenzioni**: caldaia, condizionatore, revisione auto, tagliando.
- **Documenti**: carta d'identità, passaporto, patente dei genitori e dei figli.

Per ogni voce servono tre cose: **quando** scade, **quanto** costa e **dove** sta il documento. Se anche una manca, la scadenza tornerà a mordere.

## Perché il calendario non basta

La reazione istintiva è mettere tutto sul calendario. Funziona per il *quando*, ma il calendario non sa quanto costa, non conserva la fattura e non collega la scadenza alla cosa a cui si riferisce. Quando la caldaia si rompe, ti serve la ricevuta dell'ultima manutenzione, non la data.

Serve un posto dove la scadenza, il documento e il costo stanno insieme.

## Un posto solo, con tutto attaccato

In KidBox la [scheda Casa](/strumenti/casa) è pensata esattamente per questo. Ogni bene di casa — la lavatrice, la caldaia, il router — ha la sua scheda con garanzia e manutenzioni; ogni scadenza — bolletta, tassa, contratto — ha data, importo e il file allegato.

Tre cose succedono da sole:

1. **Il documento finisce in Documenti.** La fattura allegata alla bolletta è la stessa che trovi nella [cartella Documenti](/strumenti/documenti) della famiglia: un file solo, visibile da tutte e due le parti.
2. **L'importo diventa una spesa.** Quando segni che la bolletta è di 84 euro, la voce compare nelle spese di famiglia. Non la scrivi due volte.
3. **Il promemoria arriva prima.** Scegli quanti giorni prima essere avvisato, e la notifica arriva a tutti e due i genitori.

## L'auto è un caso a parte

I veicoli hanno un ritmo tutto loro: bollo, assicurazione, revisione, tagliando, gomme. In KidBox stanno nella [scheda Veicoli](/strumenti/veicoli): per ogni auto le scadenze ricorrenti e lo storico degli interventi con costo e ricevuta. Quando cambi gomme e segni 320 euro, la spesa nasce da sola e la fattura del gommista è a un tocco.

> Il bollo non è un intervento: è una scadenza. Sembra un dettaglio, ma è il motivo per cui in molte famiglie non si trova mai la ricevuta dell'anno prima.

## La regola dei 30 giorni

Un promemoria il giorno della scadenza serve a poco: la bolletta va pagata, ma la garanzia del frigo che scade *oggi* non ti dà il tempo di chiamare l'assistenza per quel rumore che fa da settimane.

La regola che funziona: **30 giorni prima per tutto ciò che richiede un'azione** (garanzie, contratti da disdire, revisioni da prenotare), **7 giorni prima per i pagamenti**. Due promemoria, non uno.

## Chi se ne occupa

La domanda più importante: chi è il responsabile di ogni scadenza? Se la risposta è «tutti e due», la risposta è «nessuno». Assegnate ogni area a una persona — le utenze a uno, l'auto all'altro — e fate in modo che l'altro **veda comunque tutto**. È la differenza tra dividersi il lavoro e nascondersi le informazioni.

Con una scheda condivisa, chi paga vede la scadenza, chi non paga vede che è stata pagata. E quando una persona è in viaggio, malata o semplicemente stanca, l'altra ha tutto quello che serve senza chiedere «dove hai messo…?».

## Un'ora, una volta

Il sistema si monta in un'ora: censimento, inserimento, un promemoria per voce. Poi si mantiene da solo, perché ogni nuova bolletta si aggiunge in trenta secondi quando arriva. Rispetto ai soldi buttati in more e garanzie perse, è l'ora meglio spesa dell'anno.
""",
        },
        "en": {
            "title": "Bills, warranties and inspections: the household deadlines nobody remembers",
            "desc": "Household deadlines cost money when forgotten. How to put them all in one place, documents attached, and stop thinking about them.",
            "body": """
A home produces deadlines constantly: the electricity bill, the insurance instalment, the fridge warranty running out, the car inspection, the lease renewal, the boiler service. None is hard. The problem is that there are thirty of them, scattered across emails, drawers and one person's memory.

Forgetting one costs: a late fee, a lost warranty, a fine. This guide explains how to build a system that holds all of them, once.

## The census: what expires in your home

Take an hour and make the list. The categories almost every family has:

- **Utilities**: electricity, gas, water, internet, phone. Monthly or bimonthly.
- **Insurance**: car, home, life, health. Yearly, often on different dates.
- **Taxes**: waste, road tax, property taxes.
- **Contracts**: rent, subscriptions, auto-renewing services.
- **Warranties**: appliances, phones, computers. Always forgotten.
- **Maintenance**: boiler, air conditioning, car inspection, service.
- **Documents**: ID cards, passports, driving licences of parents and kids.

For each item you need three things: **when** it expires, **how much** it costs and **where** the document is. If even one is missing, the deadline will come back to bite.

## Why the calendar isn't enough

The instinct is to put everything on the calendar. It works for the *when*, but the calendar doesn't know the cost, doesn't keep the invoice and doesn't link the deadline to the thing it refers to. When the boiler breaks, you need the receipt from the last service, not the date.

You need a place where the deadline, the document and the cost sit together.

## One place, everything attached

In KidBox the [Home section](/en/tools/casa) is built exactly for this. Every household asset — the washing machine, the boiler, the router — has its own card with warranty and services; every deadline — bill, tax, contract — has a date, an amount and the file attached.

Three things happen on their own:

1. **The document lands in Documents.** The invoice attached to the bill is the same file you find in the family's [Documents folder](/en/tools/documenti): one file, visible to both parents.
2. **The amount becomes an expense.** When you note the bill is 84 euros, the entry shows up in family expenses. You don't type it twice.
3. **The reminder arrives early.** Choose how many days ahead to be warned, and the notification reaches both parents.

## The car is a case of its own

Vehicles have their own rhythm: road tax, insurance, inspection, service, tyres. In KidBox they live in the [Vehicles section](/en/tools/veicoli): for each car the recurring deadlines and the service history with cost and receipt. When you change tyres and note 320 euros, the expense is created on its own and the tyre shop's invoice is one tap away.

> Road tax isn't a service: it's a deadline. It sounds like a detail, but it's why so many families can never find last year's receipt.

## The 30-day rule

A reminder on the day itself is of little use: the bill gets paid, but a fridge warranty expiring *today* gives you no time to call support about that noise it's been making for weeks.

The rule that works: **30 days ahead for anything that needs an action** (warranties, contracts to cancel, inspections to book), **7 days ahead for payments**. Two reminders, not one.

## Who owns it

The most important question: who is responsible for each deadline? If the answer is "both of us", the answer is "nobody". Assign each area to one person — utilities to one, the car to the other — and make sure the other **still sees everything**. That's the difference between splitting the work and hiding the information.

With a shared section, whoever pays sees the deadline, whoever doesn't pays sees it's been paid. And when one person is travelling, ill or simply tired, the other has everything they need without asking "where did you put…?".

## One hour, once

The system takes an hour to set up: census, entry, one reminder per item. Then it maintains itself, because every new bill takes thirty seconds to add when it arrives. Compared with the money thrown away on late fees and lost warranties, it's the best-spent hour of the year.
""",
        },
    },
    # ── Casa e faccende · secondo lotto ────────────────────────────────
    {
        "slug": "faccende-e-adhd",
        "category": "casa-e-faccende", "date": "2026-09-13",
        "tools": ["to-do", "calendario", "lista-della-spesa"], "related": ["promemoria-che-funzionano", "carico-mentale-dei-genitori", "dividere-le-faccende-in-coppia"],
        "it": {
            "title": "Faccende di casa e ADHD: cosa aiuta davvero, e perché i sistemi classici no",
            "desc": "Tabelle, turni e buoni propositi funzionano male con un cervello ADHD. Cosa cambia quando le faccende stanno fuori dalla testa, piccole e visibili.",
            "body": """
Chi vive con l'ADHD — da adulto, o accanto a un partner o a un figlio che ce l'ha — conosce la scena: la lavatrice finita da ore e mai stesa, la bolletta vista, capita, e dimenticata trenta secondi dopo. Non è pigrizia e non è mancanza di volontà. È che quasi tutti i sistemi per organizzare la casa sono progettati per un cervello che si ricorda le cose da solo.

Questo articolo non è un consiglio medico: per diagnosi e terapie c'è lo specialista. È una raccolta di accorgimenti pratici che, nella gestione della casa, fanno la differenza.

## Perché la tabella sul frigo non funziona

La tabella delle faccende ha tre difetti, per un cervello ADHD:

- **È statica.** Dopo una settimana diventa parte dell'arredamento e smette di essere vista.
- **È grande.** «Pulire il bagno» è un compito enorme e vago, e i compiti vaghi si rimandano.
- **Non avvisa.** Ricorda solo a chi ci passa davanti nel momento giusto, cioè quasi mai.

Il problema non è la motivazione: è che l'informazione deve arrivare **nel momento in cui si può agire**, non quando qualcuno se ne ricorda.

## 1. Fuori dalla testa, subito

La regola più importante: ogni cosa da fare esce dalla testa nell'istante in cui compare. Non «dopo la scrivo»: dopo non esiste. Serve un posto sempre a portata di mano, dove aggiungere una voce richiede cinque secondi.

Una [lista di cose da fare di famiglia](/strumenti/to-do) sul telefono funziona meglio di un quaderno proprio per questo: il telefono è sempre in tasca. E se c'è un Echo in cucina, dirlo ad [Alexa](/strumenti/alexa) è ancora più rapido — «Alexa, chiedi a mio box di aggiungere comprare le lampadine».

## 2. Compiti piccoli, con un verbo

«Sistemare la cameretta» non si inizia mai. «Mettere i giochi nella cesta» sì. Ogni voce della lista dovrebbe:

- cominciare con un **verbo concreto** (stendere, buttare, chiamare)
- durare **meno di quindici minuti**
- avere una **fine chiara**: si capisce quando è fatta

Spezzare un compito grande in tre piccoli sembra tempo perso. È il contrario: tre compiti da dieci minuti vengono fatti, uno da mezz'ora resta lì per giorni.

## 3. Il promemoria nel momento giusto

Un promemoria alle 9 per «stendere la lavatrice» è inutile se la lavatrice finisce alle 11. Il promemoria va legato al momento in cui l'azione è possibile, e va assegnato a chi la fa. In KidBox ogni cosa da fare può avere un responsabile e un orario: la notifica arriva a quella persona, a quell'ora — non a tutta la famiglia, che la ignorerebbe.

Anche le scadenze vanno trattate così: la bolletta non si ricorda, si mette nel [calendario](/strumenti/calendario) con un avviso qualche giorno prima.

## 4. Visibile, senza diventare controllo

Nelle coppie in cui uno dei due ha l'ADHD, il rischio è che l'altro diventi il «promemoria umano»: chiede, ricorda, controlla. Logora entrambi. Una lista condivisa sposta quel lavoro sullo strumento: chi ha fatto la cosa la spunta, l'altro la vede spuntata senza chiedere. Niente «l'hai fatto?», niente sensazione di essere sorvegliati.

## 5. Ridurre le decisioni

Ogni decisione costa energia. Qualche scorciatoia:

- **Liste fisse** per le cose ricorrenti: la spesa base, la valigia del weekend, la routine del lunedì
- **Un posto per ogni cosa** che si perde sempre: chiavi, documenti, caricabatterie
- **La [lista della spesa](/strumenti/lista-della-spesa) sempre aperta**: quando finisce qualcosa si aggiunge subito, e al supermercato non si deve ricordare niente

## 6. Contare quello che è stato fatto

I sistemi classici mostrano solo quello che manca. Per chi ha l'ADHD, vedere le voci spuntate a fine giornata non è un dettaglio: è la prova che la giornata non è andata persa. Tenete le liste corte, e lasciate che si svuotino.

## In sintesi

Non serve più forza di volontà: serve un sistema che non dipenda dalla memoria. Tutto scritto subito, compiti piccoli, avvisi nel momento giusto a chi deve agire, e una lista condivisa al posto delle domande. È un sistema che aiuta chiunque — ma che per una casa con l'ADHD è la differenza tra rincorrere e respirare.
""",
        },
        "en": {
            "title": "Chores and ADHD: what actually helps, and why standard systems don't",
            "desc": "Charts, rotas and good intentions work badly with an ADHD brain. What changes when chores live outside your head, small and visible.",
            "body": """
Anyone living with ADHD — as an adult, or alongside a partner or child who has it — knows the scene: the washing finished hours ago and never hung out, the bill seen, understood and forgotten thirty seconds later. It isn't laziness and it isn't lack of willpower. Almost every system for running a home is designed for a brain that remembers things on its own.

This article isn't medical advice: for diagnosis and treatment there are specialists. It's a set of practical adjustments that make a real difference to running a home.

## Why the chart on the fridge doesn't work

The chore chart has three flaws for an ADHD brain:

- **It's static.** After a week it becomes part of the furniture and stops being seen.
- **It's big.** "Clean the bathroom" is a huge, vague task, and vague tasks get postponed.
- **It doesn't alert you.** It only reminds whoever walks past it at the right moment, which is almost never.

The problem isn't motivation: the information has to arrive **at the moment you can act**, not when someone happens to remember.

## 1. Out of your head, immediately

The most important rule: every to-do leaves your head the instant it appears. Not "I'll write it down later": later doesn't exist. You need a place that's always within reach, where adding an item takes five seconds.

A [family to-do list](/en/tools/to-do) on your phone works better than a notebook for exactly this reason: the phone is always in your pocket.

## 2. Small tasks, with a verb

"Tidy the kids' room" never gets started. "Put the toys in the basket" does. Every item on the list should:

- start with a **concrete verb** (hang, throw out, call)
- take **less than fifteen minutes**
- have a **clear end**: you can tell when it's done

Splitting a big task into three small ones looks like wasted time. It's the opposite: three ten-minute tasks get done, one half-hour task sits there for days.

## 3. The reminder at the right moment

A 9am reminder to "hang out the washing" is useless if the machine finishes at 11. The reminder has to be tied to the moment the action is possible, and assigned to whoever does it. In KidBox every to-do can have an owner and a time: the notification goes to that person, at that time — not to the whole family, who would ignore it.

Deadlines work the same way: you don't remember the bill, you put it in the [calendar](/en/tools/calendario) with an alert a few days before.

## 4. Visible, without becoming surveillance

In couples where one partner has ADHD, the risk is that the other becomes the "human reminder": asking, reminding, checking. It wears both of you down. A shared list moves that work onto the tool: whoever did the task ticks it, the other sees it ticked without asking. No "did you do it?", no feeling of being watched.

## 5. Fewer decisions

Every decision costs energy. A few shortcuts:

- **Fixed lists** for recurring things: the basic shop, the weekend bag, the Monday routine
- **One place for everything** that always gets lost: keys, documents, chargers
- **The [grocery list](/en/tools/lista-della-spesa) always open**: when something runs out it goes on straight away, and at the supermarket there's nothing to remember

## 6. Count what got done

Standard systems only show what's missing. For someone with ADHD, seeing the ticked items at the end of the day isn't a detail: it's proof the day wasn't lost. Keep lists short, and let them empty.

## In short

You don't need more willpower: you need a system that doesn't depend on memory. Everything written down at once, small tasks, alerts at the right moment to whoever has to act, and a shared list instead of questions. It helps anyone — but for a home with ADHD it's the difference between chasing and breathing.
""",
        },
    },
    {
        "slug": "faccende-tra-adulti",
        "category": "casa-e-faccende", "date": "2026-09-13",
        "tools": ["to-do", "casa", "spese"], "related": ["dividere-le-faccende-in-coppia", "scadenze-di-casa-bollette-garanzie", "carico-mentale-dei-genitori"],
        "it": {
            "title": "Faccende tra adulti: come organizzare la casa senza che uno faccia il capo",
            "desc": "Tra adulti nessuno vuole assegnare compiti né riceverli. Un sistema per aree di responsabilità che regge senza promemoria a voce e senza rancori.",
            "body": """
Con i figli è semplice: i genitori decidono, i bambini fanno. Tra adulti no. Nessuno vuole essere quello che assegna i compiti, e nessuno vuole sentirsi assegnare qualcosa. Il risultato, in molte case, è che uno dei due diventa il capo senza volerlo — quello che nota, ricorda e chiede — e l'altro l'esecutore che «aiuta».

È un equilibrio che regge qualche mese, poi si rompe. Ecco un modo diverso di impostarlo.

## Il problema non è chi pulisce

Contare le ore passate a fare le faccende serve a poco. Il lavoro invisibile è un altro: **accorgersi** che una cosa va fatta, **decidere** quando, **ricordarsi** di controllare. Chi si occupa di questa parte fa un secondo lavoro, anche se materialmente pulisce la metà.

Quindi l'obiettivo non è dividere le azioni. È dividere la **responsabilità**: ognuno si occupa di un'area dall'inizio alla fine, compreso il pensarci.

## 1. Mappare la casa per aree

Sedetevi mezz'ora e scrivete tutto quello che una casa richiede, raggruppato per area:

- **Cucina e pasti**: spesa, cucinare, lavastoviglie, frigo
- **Bucato**: lavare, stendere, piegare, cambiare le lenzuola
- **Pulizie**: bagni, pavimenti, polvere, spazzatura
- **Amministrazione**: bollette, contratti, tasse, garanzie
- **Manutenzione**: caldaia, piccole riparazioni, elettrodomestici
- **Auto**: bollo, assicurazione, revisione, tagliando

La lista sarà più lunga di quanto pensate. È normale: è la prima volta che la vedete per intero.

## 2. Un titolare per area

Ogni area ha un titolare. Titolare significa che **non deve chiedere a nessuno** e che **nessuno deve ricordarglielo**: se la spazzatura è sua, quando il bidone è pieno è un problema suo, non dell'altro.

Distribuite le aree in base a gusti e orari, non a chi «è più bravo». E prevedete una revisione dopo un mese: la prima divisione non è mai quella giusta.

## 3. Scrivere, così nessuno deve ricordare

Un accordo a voce dura finché dura la memoria di entrambi. Scritto in una [lista di cose da fare condivisa](/strumenti/to-do), ogni voce ha un responsabile e — se serve — un promemoria che arriva solo a lui. L'altro vede la lista, ma non riceve notifiche per cose che non sono sue.

È questo che toglie il ruolo di capo: nessuno ricorda niente all'altro, lo fa lo strumento.

## 4. Le scadenze di casa in un posto solo

L'area «amministrazione» è quella che genera più attriti, perché è invisibile finché qualcosa non va storto. Bollette, contratti, garanzie e revisioni vanno raccolti in una sezione unica: in KidBox la scheda [Casa](/strumenti/casa) tiene scadenze e pagamenti, e un importo registrato lì compare da solo nelle [spese di famiglia](/strumenti/spese). Chi è titolare paga; l'altro vede che è stato pagato, senza chiedere.

## 5. Le regole per quando salta

Qualcuno si ammala, qualcuno parte per lavoro. Decidete prima come si fa:

- **Chi è assente avvisa**, e dice cosa resta scoperto
- **Chi copre non «recupera»**: fa il minimo, il resto aspetta
- **Niente conti a fine mese**: si guarda la divisione delle aree, non le singole volte

## 6. Il check-in di dieci minuti

Una volta al mese, dieci minuti: cosa funziona, cosa pesa, quale area va scambiata. Non è un processo, è manutenzione. Le case in cui la divisione regge non sono quelle in cui si litiga meno: sono quelle in cui se ne parla prima che diventi un litigio.

## In sintesi

Tra adulti la casa funziona quando ognuno è titolare di qualcosa, per intero. Aree chiare, un titolare per area, tutto scritto in un posto condiviso e i promemoria che arrivano a chi deve agire. Nessun capo, nessun aiutante: due adulti che si occupano ciascuno della propria parte.
""",
        },
        "en": {
            "title": "Chores between adults: running a home without one person being the boss",
            "desc": "Between adults nobody wants to hand out tasks or receive them. A system based on areas of ownership that holds without verbal reminders or resentment.",
            "body": """
With children it's simple: parents decide, kids do. Between adults it isn't. Nobody wants to be the one handing out tasks, and nobody wants to be handed one. The result, in many homes, is that one partner becomes the boss without meaning to — the one who notices, remembers and asks — and the other becomes the doer who "helps".

It's a balance that lasts a few months, then breaks. Here's a different way to set it up.

## The problem isn't who cleans

Counting hours spent on chores doesn't help much. The invisible work is something else: **noticing** that something needs doing, **deciding** when, **remembering** to check. Whoever handles that part is doing a second job, even if they physically clean half as much.

So the goal isn't to split the actions. It's to split **ownership**: each person handles an area from start to finish, including thinking about it.

## 1. Map the home by area

Sit down for half an hour and write out everything a home needs, grouped by area:

- **Kitchen and meals**: shopping, cooking, dishwasher, fridge
- **Laundry**: washing, hanging, folding, changing the sheets
- **Cleaning**: bathrooms, floors, dusting, rubbish
- **Admin**: bills, contracts, taxes, warranties
- **Maintenance**: boiler, small repairs, appliances
- **Car**: road tax, insurance, inspection, servicing

The list will be longer than you think. That's normal: it's the first time you've seen it in full.

## 2. One owner per area

Each area has an owner. Owner means they **don't have to ask anyone** and **nobody has to remind them**: if the bins are theirs, a full bin is their problem, not the other person's.

Divide areas by taste and schedule, not by who's "better at it". And plan a review after a month: the first split is never the right one.

## 3. Write it down, so nobody has to remember

A verbal agreement lasts as long as both people's memory. Written in a [shared to-do list](/en/tools/to-do), every item has an owner and — if needed — a reminder that goes only to them. The other person sees the list, but gets no notifications for things that aren't theirs.

That's what removes the boss role: nobody reminds anybody, the tool does.

## 4. Household deadlines in one place

The "admin" area causes the most friction, because it's invisible until something goes wrong. Bills, contracts, warranties and inspections belong in a single section: in KidBox the [Home](/en/tools/casa) section holds deadlines and payments, and an amount recorded there shows up on its own in [family expenses](/en/tools/spese). The owner pays; the other sees it's been paid, without asking.

## 5. Rules for when things slip

Someone gets ill, someone travels for work. Decide in advance:

- **Whoever is away says so**, and says what's left uncovered
- **Whoever covers doesn't "catch up"**: they do the minimum, the rest waits
- **No end-of-month tallies**: you look at how areas are split, not individual times

## 6. The ten-minute check-in

Once a month, ten minutes: what's working, what's heavy, which area should be swapped. It isn't a trial, it's maintenance. The homes where the split holds aren't the ones with fewer arguments: they're the ones where things get talked about before they become an argument.

## In short

Between adults a home works when each person fully owns something. Clear areas, one owner per area, everything written in a shared place and reminders going to whoever has to act. No boss, no helper: two adults each taking care of their part.
""",
        },
    },
]

# Le altre categorie vivono in un modulo ciascuna, per tenere i file leggibili.
from blog_genitori_separati import ARTICLES as _GS  # noqa: E402
from blog_confronti import ARTICLES as _CF  # noqa: E402
from blog_organizzazione import ARTICLES as _OR  # noqa: E402
from blog_pasti import ARTICLES as _PA  # noqa: E402
from blog_produttivita import ARTICLES as _PR  # noqa: E402

ARTICLES += _GS + _CF + _OR + _PA + _PR
