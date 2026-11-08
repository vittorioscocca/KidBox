# -*- coding: utf-8 -*-
"""Articoli su KidBox nei dispositivi Apple: widget e Handoff (categoria
«Produttività in casa»). Vedi blog_data.py per il formato.

Fatti verificati nel codice l'08/11/2026:
- widget: KidBoxControlsExtension/Widgets (tre misure, sei contenuti, pulsanti
  che spuntano to-do, spesa e dosi, scorciatoie e «Aggiorna» nel grande);
- Handoff: KidBox/App/Core/KBHandoff.swift (posto + bozza, un minuto, niente
  server KidBox, Password e Wallet esclusi).
"""

ARTICLES = [
    {
        "slug": "widget-kidbox-schermata-home",
        "category": "produttivita-in-casa", "date": "2026-11-08",
        "tools": ["calendario", "to-do", "lista-della-spesa"],
        "related": ["handoff-iphone-ipad-mac", "lista-della-spesa-condivisa", "promemoria-che-funzionano"],
        "it": {
            "title": "I widget di KidBox: la giornata della famiglia sulla schermata Home",
            "desc": "Calendario, to-do, spesa, cure, foto e piano fitness sulla schermata Home di iPhone e iPad, in tre misure. Si spunta direttamente dal widget, senza aprire l'app.",
            "body": """
La maggior parte delle volte che apri un'app di famiglia vuoi sapere una cosa sola: cosa c'è oggi, cosa manca da comprare, se la dose della sera è stata data. Per questo KidBox ha i **widget** per la schermata Home di iPhone e iPad: la risposta è lì quando sblocchi il telefono, e per le cose più piccole non serve nemmeno aprire l'app.

![I widget di KidBox sulla schermata Home: to-do e calendario con le scorciatoie](/assets/app/it/widgets.webp)

## Cosa può mostrare un widget

Ogni widget mostra una sezione, e la scegli tu tenendo premuto il widget e toccando «Modifica widget»:

- **Calendario**: gli impegni di oggi e dei prossimi giorni, con i colori degli eventi
- **To-do**: le cose da fare, quelle di una lista precisa se vuoi; quelle in scadenza vengono prima
- **Spesa**: quello che manca da comprare
- **Cure**: le dosi di oggi di una persona della famiglia
- **Foto**: un album di famiglia
- **Piano Fitness**: gli allenamenti della persona che scegli

Si possono mettere più widget uno accanto all'altro, anche della stessa sezione: per esempio il calendario e, sotto, la spesa.

## Tre misure

- **Piccolo**: il numero e la prima cosa da sapere, per esempio quanti to-do restano
- **Medio**: le prime voci per intero, da leggere a colpo d'occhio
- **Grande**: la sezione con più spazio e, sotto, **fino a sei scorciatoie** alle sezioni che scegli tu (to-do, spesa, foto, salute, chat, note…). In fondo c'è l'ora dell'ultimo aggiornamento e il pulsante per aggiornare subito

## Si spunta dal widget

I widget non sono solo da guardare. Con un tocco sul cerchio accanto alla voce:

- un **to-do** diventa fatto
- un prodotto della **spesa** diventa preso
- una **dose** delle cure diventa data

La modifica arriva a tutta la famiglia come se l'avessi fatta dall'app. Al supermercato, con il carrello in una mano, è il modo più veloce per tenere la [lista della spesa](/strumenti/lista-della-spesa) aggiornata.

## Come si aggiunge

1. Tieni premuto su uno spazio vuoto della schermata Home e tocca **Modifica**, poi **Aggiungi widget**
2. Cerca **KidBox** e scegli la misura
3. Tieni premuto il widget appena messo, tocca **Modifica widget** e scegli la sezione (e, dove serve, la lista, la persona o l'album)

## Cosa vedono gli altri

Il widget mostra quello che vedi tu nell'app, niente di più. Le cose private restano private, e i contenuti cifrati della famiglia restano sul dispositivo. Il widget si aggiorna da solo quando apri l'app o quando qualcuno cambia qualcosa; il pulsante in fondo al grande serve quando vuoi essere sicuro di avere l'ultima versione.

## Un consiglio

Mettete il widget del calendario sulla prima pagina del telefono di **tutti e due** i genitori. Non serve ricordarsi di aprire l'app: basta sbloccare il telefono per vedere che giovedì c'è il pediatra, e chi lo porta. È lo stesso principio dei [promemoria che funzionano](/blog/promemoria-che-funzionano): l'informazione arriva dove già guardi.

I widget ci sono in tutti i piani, su iPhone e iPad. Se lavori anche dal Mac, leggi come [continuare da un dispositivo all'altro con Handoff](/blog/handoff-iphone-ipad-mac).
""",
        },
        "en": {
            "title": "KidBox widgets: the family's day on your Home Screen",
            "desc": "Calendar, to-dos, groceries, treatments, photos and fitness plan on the iPhone and iPad Home Screen, in three sizes. Tick things off straight from the widget, without opening the app.",
            "body": """
Most of the time you open a family app you want to know one thing: what's on today, what's left to buy, whether the evening dose has been given. That's why KidBox has **widgets** for the iPhone and iPad Home Screen: the answer is there when you unlock your phone, and for the small things you don't even need to open the app.

![KidBox widgets on the Home Screen: to-dos and calendar with shortcuts](/assets/app/en/widgets.webp)

## What a widget can show

Each widget shows one section, and you choose it by holding the widget and tapping "Edit Widget":

- **Calendar**: today's plans and the next few days, in the events' colours
- **To-do**: things to do, from a specific list if you like; the ones due soon come first
- **Groceries**: what's still to buy
- **Treatments**: today's doses for one person in the family
- **Photos**: a family album
- **Fitness plan**: the workouts of the person you choose

You can place several widgets side by side, even of the same section: say, the calendar and the grocery list below it.

## Three sizes

- **Small**: the number and the first thing to know, for instance how many to-dos are left
- **Medium**: the first items in full, readable at a glance
- **Large**: the section with more room and, below it, **up to six shortcuts** to the sections you pick (to-dos, groceries, photos, health, chat, notes…). At the bottom you see when it was last updated, with a button to refresh right away

## Tick things off from the widget

Widgets aren't just for looking. One tap on the circle next to an item and:

- a **to-do** is done
- a **grocery** item is bought
- a treatment **dose** is given

The change reaches the whole family as if you'd made it in the app. At the supermarket, trolley in one hand, it's the quickest way to keep the [grocery list](/en/tools/lista-della-spesa) up to date.

## How to add one

1. Hold an empty spot on the Home Screen, tap **Edit**, then **Add Widget**
2. Search for **KidBox** and pick the size
3. Hold the new widget, tap **Edit Widget** and choose the section (and, where needed, the list, the person or the album)

## What others see

The widget shows what you see in the app, nothing more. Private things stay private, and the family's encrypted content stays on the device. The widget updates on its own when you open the app or when someone changes something; the button at the bottom of the large one is for when you want to be sure you have the latest version.

## A tip

Put the calendar widget on the first page of **both** parents' phones. Nobody has to remember to open the app: unlocking the phone is enough to see that the paediatrician is on Thursday, and who's taking them. It's the same principle as [reminders that work](/en/blog/promemoria-che-funzionano): the information lands where you already look.

Widgets are included in every plan, on iPhone and iPad. If you also work from a Mac, read how to [pick up where you left off with Handoff](/en/blog/handoff-iphone-ipad-mac).
""",
        },
    },
    {
        "slug": "handoff-iphone-ipad-mac",
        "category": "produttivita-in-casa", "date": "2026-11-08",
        "tools": ["to-do", "calendario", "salute"],
        "related": ["widget-kidbox-schermata-home", "promemoria-che-funzionano", "carico-mentale-dei-genitori"],
        "it": {
            "title": "Handoff in KidBox: cominci sull'iPhone, finisci sul Mac",
            "desc": "Il to-do, l'evento o la visita che stai scrivendo passa dall'iPhone all'iPad o al Mac già compilato, al punto in cui eri. Come funziona e cosa porta con sé.",
            "body": """
Succede di continuo: cominci a scrivere qualcosa sul telefono e ti accorgi che sarebbe più comodo finirlo al computer. La riunione di classe con l'orario e l'indirizzo, la visita dal pediatra con la diagnosi da ricopiare, la lista della spesa lunga del sabato. Con **Handoff** in KidBox non riparti da capo: apri l'app sull'altro dispositivo e trovi quello che stavi facendo, già scritto.

## Cosa passa da un dispositivo all'altro

**Il posto dove sei.** Se sull'iPhone sei nel calendario, il Mac apre il calendario. Vale anche dentro le sezioni: la stessa lista dei to-do, lo stesso album di foto, la stessa persona e la stessa pagina in Salute (la scheda, le visite, una visita precisa, i vaccini, le cure).

**Quello che stai scrivendo.** Le bozze che passano già compilate:

- un **to-do** o una voce della **spesa**, con la nota e la quantità
- un **evento** del calendario, con data, ora e luogo
- un **messaggio** della chat di famiglia
- una **visita**, un **esame** o una **cura** in Salute, allo stesso passo della scheda
- una **spesa** in Spese, con titolo, importo, data, categoria e note
- la domanda che stai scrivendo all'**assistente**

Se stai guardando qualcosa che esiste già, come una nota o un to-do, l'altro dispositivo apre proprio quello.

## Come si usa

1. Sull'iPhone apri KidBox e comincia a scrivere
2. Sul **Mac** compare l'icona di KidBox nel Dock con il simbolo del telefono; sull'**iPad** nel Dock in basso a destra o nel selettore delle app
3. Toccala o cliccala: KidBox si apre lì, al punto in cui eri

Funziona in tutte le direzioni: dal Mac all'iPhone, dall'iPad al Mac, e così via.

## Cosa serve

- KidBox installato sui dispositivi, con la stessa famiglia
- lo **stesso account Apple** su tutti, con Handoff attivo (Impostazioni › Generali › AirPlay e Continuity sull'iPhone, Impostazioni di Sistema › Generali › AirDrop e Handoff sul Mac)
- i dispositivi vicini, con Bluetooth e Wi‑Fi accesi

Handoff è di Apple: lavora fra i **tuoi** dispositivi, non fra quelli di due persone. Per passare un compito al partner ci sono i to-do assegnati e le [richieste di famiglia](/blog/chiedere-aiuto-in-famiglia).

## Cosa non passa, e perché

- **Gli allegati**: foto e documenti restano sul dispositivo dove li hai aggiunti. Il testo arriva, il file no
- **Password e Wallet**: sono le sezioni più delicate, e restano fuori da Handoff di proposito
- **Le bozze vecchie**: una bozza non ripresa entro un minuto si scarta, così non ti ritrovi a sorpresa un evento a metà di ieri

La bozza viaggia direttamente fra i tuoi dispositivi con Handoff, **senza passare dai server di KidBox**. E se per sbaglio salvi lo stesso to-do o la stessa voce della spesa su tutti e due i dispositivi, resta una voce sola.

## Quando serve davvero

Il caso tipico è la sera: qualcuno ti scrive l'orario della recita, cominci l'evento sul telefono dal divano e lo finisci al Mac, dove copiare l'indirizzo e le note è più comodo. Oppure al contrario: prepari la spesa al computer e, uscendo, la ritrovi sul telefono senza cercarla.

Handoff c'è in tutti i piani, fra iPhone, iPad e Mac. Sulla schermata Home, invece, ci sono [i widget di KidBox](/blog/widget-kidbox-schermata-home).
""",
        },
        "en": {
            "title": "Handoff in KidBox: start on iPhone, finish on Mac",
            "desc": "The to-do, event or doctor's visit you're writing moves from iPhone to iPad or Mac already filled in, right where you were. How it works and what it carries.",
            "body": """
It happens all the time: you start writing something on your phone and realise it would be easier to finish at the computer. The class meeting with the time and address, the paediatrician's visit with the diagnosis to copy out, the long Saturday grocery list. With **Handoff** in KidBox you don't start over: you open the app on the other device and find what you were doing, already written.

## What moves from one device to the other

**Where you are.** If you're in the calendar on your iPhone, the Mac opens the calendar. It works inside sections too: the same to-do list, the same photo album, the same person and the same page in Health (the profile, the visits, a specific visit, vaccinations, treatments).

**What you're writing.** The drafts that arrive already filled in:

- a **to-do** or a **grocery** item, with its note and quantity
- a calendar **event**, with date, time and place
- a family chat **message**
- a **visit**, a **test** or a **treatment** in Health, at the same step of the form
- an **expense**, with title, amount, date, category and notes
- the question you're typing to the **assistant**

If you're looking at something that already exists, like a note or a to-do, the other device opens exactly that.

## How to use it

1. On your iPhone, open KidBox and start writing
2. On the **Mac**, the KidBox icon appears in the Dock with a phone badge; on the **iPad**, at the right end of the Dock or in the app switcher
3. Tap or click it: KidBox opens there, right where you were

It works in every direction: Mac to iPhone, iPad to Mac, and so on.

## What you need

- KidBox installed on the devices, in the same family
- the **same Apple Account** on all of them, with Handoff turned on (Settings › General › AirPlay & Continuity on iPhone, System Settings › General › AirDrop & Handoff on Mac)
- the devices close to each other, with Bluetooth and Wi‑Fi on

Handoff is Apple's: it works between **your** devices, not between two people's. To pass a task to your partner there are assigned to-dos and [family requests](/en/blog/chiedere-aiuto-in-famiglia).

## What doesn't move, and why

- **Attachments**: photos and documents stay on the device where you added them. The text arrives, the file doesn't
- **Passwords and Wallet**: they're the most sensitive sections, and they're kept out of Handoff on purpose
- **Old drafts**: a draft that isn't picked up within a minute is discarded, so you don't find yesterday's half-written event by surprise

The draft travels directly between your devices with Handoff, **without going through KidBox's servers**. And if you accidentally save the same to-do or grocery item on both devices, it stays a single item.

## When it really helps

The typical case is the evening: someone texts you the time of the school play, you start the event on your phone from the sofa and finish it on the Mac, where copying the address and notes is easier. Or the other way round: you prepare the shopping on the computer and, on your way out, find it on your phone without looking for it.

Handoff is included in every plan, between iPhone, iPad and Mac. On the Home Screen, meanwhile, there are [KidBox widgets](/en/blog/widget-kidbox-schermata-home).
""",
        },
    },
]
