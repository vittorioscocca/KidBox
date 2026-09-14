# -*- coding: utf-8 -*-
"""
Contenuti della sezione «Strumenti» della landing: una voce per ogni scheda
di KidBox, in italiano e in inglese. Il generatore (`scripts/build_tools.py`)
li trasforma nelle pagine sotto `public/strumenti/` e `public/en/tools/`.

Per ogni strumento:
  slug        parte finale dell'URL (uguale nelle due lingue)
  icon        emoji della card
  tint        colore dell'icona: accent | green | blue | violet | amber
  shots       cartella in public/screenshots da cui prendere le immagini
              (None = nessuna immagine ancora)
  plan        "free" | "pro"
  related     slug degli strumenti collegati
  it / en     title, short (card), lead (sotto il titolo), steps (come
              funziona: 3 voci titolo+testo), faq (domanda+risposta)
"""

TOOLS = [
    {
        "slug": "calendario",
        "icon": "📅", "tint": "accent", "shots": "Calendario", "plan": "free",
        "related": ["to-do", "posizione", "assistente-ai"],
        "it": {
            "title": "Calendario di famiglia condiviso",
            "short": "Gli impegni di tutti in un calendario solo, con viste mese, settimana e giorno. Chi aggiunge un evento lo vede anche l'altro genitore, subito.",
            "lead": "Un calendario in cui entrano visite, allenamenti, compleanni e riunioni di classe — e che tutta la famiglia vede aggiornato, anche a telefono chiuso.",
            "steps": [
                ("Aggiungi un evento", "Titolo, giorno e ora; se vuoi, a quale figlio si riferisce e un promemoria prima che inizi."),
                ("Tutti lo vedono", "L'evento compare sul telefono dell'altro genitore e sul web nello stesso istante, senza inviti né condivisioni da accettare."),
                ("Scegli la vista", "Mese per la panoramica, settimana e giorno con la griglia oraria per capire dove incastrare la prossima cosa."),
            ],
            "faq": [
                ("Serve che tutti abbiano lo stesso telefono?", "No. KidBox è su iPhone, Android e web: ognuno usa quello che ha, e il calendario è lo stesso per tutti."),
                ("Posso ricevere un promemoria?", "Sì: per ogni evento scegli quanto prima essere avvisato, e la notifica arriva sui dispositivi in cui hai attivato le notifiche."),
                ("L'assistente AI può creare eventi?", "Sì. Scrivendo «segna la pediatra giovedì alle 16» l'assistente crea l'evento nel calendario di famiglia."),
            ],
        },
        "en": {
            "title": "Shared family calendar",
            "short": "Everyone's commitments in one calendar, with month, week and day views. Whoever adds an event, the other parent sees it right away.",
            "lead": "A calendar for check-ups, practice, birthdays and class meetings — that the whole family sees up to date, even with the phone in a pocket.",
            "steps": [
                ("Add an event", "Title, day and time; optionally which child it's about and a reminder before it starts."),
                ("Everyone sees it", "The event shows up on the other parent's phone and on the web at the same moment, no invitations to accept."),
                ("Pick a view", "Month for the overview, week and day with an hourly grid to see where the next thing fits."),
            ],
            "faq": [
                ("Does everyone need the same phone?", "No. KidBox runs on iPhone, Android and the web: everyone uses what they have, and the calendar is the same for all."),
                ("Can I get a reminder?", "Yes: for each event you choose how early to be notified, and the alert reaches the devices where notifications are on."),
                ("Can the AI assistant create events?", "Yes. Writing “put the paediatrician on Thursday at 4pm” makes the assistant create the event in the family calendar."),
            ],
        },
    },
    {
        "slug": "to-do",
        "icon": "✅", "tint": "green", "shots": "To-Do", "plan": "free",
        "related": ["calendario", "lista-della-spesa", "alexa"],
        "it": {
            "title": "Liste di cose da fare per la famiglia",
            "short": "Liste condivise, cose da fare assegnabili a chi le deve fare, promemoria all'ora giusta. Anche dettate ad Alexa.",
            "lead": "Le cose da fare di una famiglia non sono di una persona sola: qui si scrivono una volta, si assegnano e si spuntano da chiunque le abbia fatte.",
            "steps": [
                ("Crea una lista", "«Prima delle vacanze», «Casa», «Scuola»: quante ne servono, condivise con la famiglia."),
                ("Assegna e ricorda", "Ogni cosa da fare può avere un responsabile e un promemoria: la notifica arriva a chi deve farla, quando deve farla."),
                ("Spunta da dove sei", "Dal telefono, dal web o dicendo ad Alexa «aggiungi ritirare le analisi»: la lista è la stessa."),
            ],
            "faq": [
                ("Le liste sono per figlio o per famiglia?", "Per famiglia: tutti i membri vedono tutte le liste. Puoi comunque indicare a quale figlio si riferisce una cosa da fare."),
                ("Il promemoria arriva anche all'altro genitore?", "Arriva a chi è assegnata la cosa da fare. Se non è assegnata a nessuno, la ricevono tutti."),
                ("Funziona senza connessione?", "Sì: le liste restano leggibili e modificabili, e si allineano appena torna la rete."),
            ],
        },
        "en": {
            "title": "Family to-do lists",
            "short": "Shared lists, tasks assigned to whoever has to do them, reminders at the right time. Dictated to Alexa too.",
            "lead": "A family's to-dos don't belong to one person: here they're written once, assigned, and ticked off by whoever got them done.",
            "steps": [
                ("Create a list", "“Before the holidays”, “Home”, “School”: as many as you need, shared with the family."),
                ("Assign and remind", "Every task can have an owner and a reminder: the notification reaches the person who has to do it, when they have to."),
                ("Tick it off anywhere", "From the phone, the web, or by telling Alexa “add pick up the test results”: it's the same list."),
            ],
            "faq": [
                ("Are lists per child or per family?", "Per family: every member sees every list. You can still mark which child a task is about."),
                ("Does the reminder reach the other parent too?", "It reaches whoever the task is assigned to. If it's unassigned, everyone gets it."),
                ("Does it work offline?", "Yes: lists stay readable and editable, and sync as soon as the network is back."),
            ],
        },
    },
    {
        "slug": "lista-della-spesa",
        "icon": "🛒", "tint": "amber", "shots": "Lista della spesa", "plan": "free",
        "related": ["to-do", "spese", "alexa"],
        "it": {
            "title": "Lista della spesa condivisa",
            "short": "Una lista sola per tutta la famiglia, aggiornata in tempo reale: vedi chi ha aggiunto cosa, e spunti mentre riempi il carrello.",
            "lead": "Chi è al supermercato vede quello che gli altri hanno aggiunto un minuto fa. Niente più foto della lista su WhatsApp.",
            "steps": [
                ("Aggiungi da qualsiasi posto", "Dal telefono, dal web, o dicendo ad Alexa «aggiungi il latte»: l'articolo entra nella lista di famiglia."),
                ("Vedi chi e quando", "Ogni riga dice chi l'ha aggiunta e quando, così si capisce se è ancora valida."),
                ("Spunta al carrello", "Gli articoli presi spariscono dalla lista di tutti, in tempo reale."),
            ],
            "faq": [
                ("Posso avere più liste?", "Sì, per esempio supermercato e farmacia. Ognuna è condivisa con la famiglia."),
                ("Come si detta ad Alexa?", "Con la skill KidBox attiva e l'account collegato, basta «Alexa, chiedi a mio box di aggiungere il pane». Disponibile in italiano."),
                ("La spesa fatta finisce nelle Spese?", "Puoi registrarla con un tocco alla fine: importo, negozio e data vanno nelle spese di famiglia."),
            ],
        },
        "en": {
            "title": "Shared grocery list",
            "short": "One list for the whole family, updated in real time: see who added what, and tick items off while you fill the cart.",
            "lead": "Whoever is at the supermarket sees what the others added a minute ago. No more photos of the list on WhatsApp.",
            "steps": [
                ("Add from anywhere", "From the phone, the web, or by telling Alexa “add milk”: the item lands in the family list."),
                ("See who and when", "Every line says who added it and when, so you know whether it still stands."),
                ("Tick off at the cart", "Items you've picked disappear from everyone's list, in real time."),
            ],
            "faq": [
                ("Can I have more than one list?", "Yes, for instance supermarket and pharmacy. Each is shared with the family."),
                ("How do I dictate to Alexa?", "With the KidBox skill enabled and the account linked, just say “Alexa, ask my box to add bread”. Available in Italian."),
                ("Does the shopping end up in Expenses?", "You can log it with one tap at the end: amount, shop and date go into the family expenses."),
            ],
        },
    },
    {
        "slug": "note",
        "icon": "📝", "tint": "violet", "shots": "Note", "plan": "free",
        "related": ["documenti", "chat", "password"],
        "it": {
            "title": "Note di famiglia cifrate",
            "short": "Appunti condivisi con l'altro genitore — il codice del cancello, cosa ha detto la maestra — cifrati e sempre a portata di mano.",
            "lead": "Le note che una famiglia si scambia sono piene di cose private. Qui sono cifrate con una chiave che esiste solo sui vostri dispositivi.",
            "steps": [
                ("Scrivi una nota", "Testo formattato, elenchi, link. Dal telefono o dal web, con la stessa nota aperta da entrambi."),
                ("Condivisa di default", "Ogni nota è della famiglia: l'altro genitore la trova subito, senza inviarla."),
                ("Cifrata davvero", "Il contenuto viaggia e viene salvato cifrato; nemmeno KidBox può leggerlo."),
            ],
            "faq": [
                ("Cosa vuol dire «cifrata»?", "La nota viene cifrata sul tuo dispositivo con la chiave della famiglia, prima di partire. Sui server c'è solo testo illeggibile."),
                ("Posso allegare un file a una nota?", "Per i file c'è la scheda Documenti, cifrata allo stesso modo; dalla nota puoi linkarli."),
                ("Se cambio telefono le note restano?", "Sì: la chiave di famiglia si recupera con l'accesso all'account e le note tornano leggibili."),
            ],
        },
        "en": {
            "title": "Encrypted family notes",
            "short": "Shared notes with the other parent — the gate code, what the teacher said — encrypted and always within reach.",
            "lead": "The notes a family passes around are full of private things. Here they're encrypted with a key that exists only on your devices.",
            "steps": [
                ("Write a note", "Formatted text, lists, links. From the phone or the web, with the same note open on both."),
                ("Shared by default", "Every note belongs to the family: the other parent finds it right away, nothing to send."),
                ("Truly encrypted", "The content travels and is stored encrypted; not even KidBox can read it."),
            ],
            "faq": [
                ("What does “encrypted” mean here?", "The note is encrypted on your device with the family key before it leaves. The servers only hold unreadable text."),
                ("Can I attach a file to a note?", "Files live in Documents, encrypted the same way; you can link them from the note."),
                ("If I change phone, do the notes survive?", "Yes: the family key is recovered when you sign in, and the notes become readable again."),
            ],
        },
    },
    {
        "slug": "spese",
        "icon": "💶", "tint": "green", "shots": "Spese", "plan": "free",
        "related": ["lista-della-spesa", "casa", "veicoli"],
        "it": {
            "title": "Spese di famiglia per categoria",
            "short": "Le spese dei figli e della casa, per categoria e per mese. Molte nascono da sole: una visita, un tagliando, una bolletta.",
            "lead": "Non un'app di contabilità, ma il conto di quanto costa mandare avanti una famiglia — con le voci che arrivano dalle altre schede senza doverle riscrivere.",
            "steps": [
                ("Registra una spesa", "Importo, categoria, chi ha pagato, per quale figlio. Con una foto dello scontrino, se vuoi."),
                ("Le altre schede la creano per te", "Una visita medica, un intervento sull'auto, una bolletta di casa: quando le registri lì, la spesa compare qui."),
                ("Guarda il mese", "Totale per categoria e confronto con i mesi precedenti, per capire dove vanno i soldi."),
            ],
            "faq": [
                ("Posso dividere una spesa tra i genitori?", "Sì: ogni spesa ha chi ha pagato, e il riepilogo mostra quanto ha anticipato ciascuno."),
                ("Esporto i dati?", "Sì, in un file leggibile da fogli di calcolo."),
                ("Le spese sono cifrate?", "Gli importi e le categorie sono dati di famiglia protetti dall'accesso; gli allegati (scontrini, ricevute) sono cifrati come tutti i documenti."),
            ],
        },
        "en": {
            "title": "Family expenses by category",
            "short": "Kids' and household expenses, by category and by month. Many appear on their own: a check-up, a car service, a bill.",
            "lead": "Not an accounting app, but the tally of what running a family costs — with entries flowing in from the other sections without retyping them.",
            "steps": [
                ("Log an expense", "Amount, category, who paid, which child. With a photo of the receipt, if you like."),
                ("Other sections create them for you", "A medical visit, a car repair, a household bill: when you log them there, the expense shows up here."),
                ("Look at the month", "Totals per category and comparison with previous months, to see where the money goes."),
            ],
            "faq": [
                ("Can I split an expense between parents?", "Yes: every expense records who paid, and the summary shows what each has advanced."),
                ("Can I export the data?", "Yes, to a file spreadsheets can open."),
                ("Are expenses encrypted?", "Amounts and categories are family data protected by sign-in; attachments (receipts) are encrypted like every document."),
            ],
        },
    },
    {
        "slug": "wallet",
        "icon": "👛", "tint": "amber", "shots": "Wallet", "plan": "free",
        "related": ["documenti", "password", "viaggi"],
        "it": {
            "title": "Wallet: biglietti, carte fedeltà e documenti",
            "short": "Biglietti del treno e dell'aereo letti dal PDF dall'AI, carte fedeltà con il codice a barre, documenti d'identità dei figli. Condivisi.",
            "lead": "Il portafoglio che un genitore vorrebbe che avesse anche l'altro: la carta del supermercato, il biglietto della gita, la tessera sanitaria del bambino.",
            "steps": [
                ("Importa un biglietto", "Carica il PDF: l'AI legge data, orario, posti e codice, e ti mostra un biglietto pulito da esibire."),
                ("Aggiungi le carte fedeltà", "Inquadra il codice a barre una volta: da lì in poi lo mostra il telefono di chiunque in famiglia."),
                ("Documenti d'identità", "Carta d'identità, tessera sanitaria, passaporto dei figli: cifrati, con la scadenza in evidenza."),
            ],
            "faq": [
                ("Il codice a barre viene letto alla cassa?", "Sì: viene ridisegnato a schermo nello stesso formato dell'originale."),
                ("I documenti d'identità sono al sicuro?", "Sono cifrati sul dispositivo prima di partire, come tutti i documenti di KidBox."),
                ("Che biglietti riconosce l'AI?", "Treni, aerei, eventi e in generale qualsiasi PDF con date, orari e codici; se un campo non si legge, lo correggi a mano."),
            ],
        },
        "en": {
            "title": "Wallet: tickets, loyalty cards and IDs",
            "short": "Train and flight tickets read from the PDF by AI, loyalty cards with their barcode, the kids' identity documents. Shared.",
            "lead": "The wallet one parent wishes the other had too: the supermarket card, the school-trip ticket, the child's health card.",
            "steps": [
                ("Import a ticket", "Upload the PDF: the AI reads date, time, seats and code, and shows you a clean ticket to present."),
                ("Add loyalty cards", "Scan the barcode once: from then on, anyone in the family can show it from their phone."),
                ("Identity documents", "ID card, health card, the kids' passports: encrypted, with the expiry date in plain sight."),
            ],
            "faq": [
                ("Will the barcode scan at the till?", "Yes: it's redrawn on screen in the same format as the original."),
                ("Are identity documents safe?", "They're encrypted on the device before leaving it, like every document in KidBox."),
                ("Which tickets does the AI recognise?", "Trains, flights, events and any PDF with dates, times and codes; if a field isn't read, you fix it by hand."),
            ],
        },
    },
    {
        "slug": "documenti",
        "icon": "📄", "tint": "violet", "shots": "Documenti", "plan": "free",
        "related": ["wallet", "note", "salute"],
        "it": {
            "title": "Documenti di famiglia cifrati",
            "short": "Cartelle e categorie per i file della famiglia — referti, contratti, pagelle — cifrati e raggiungibili da tutte le altre schede.",
            "lead": "Un posto solo per i file che servono a entrambi i genitori, con la cifratura che si aspetta da un referto o da un contratto.",
            "steps": [
                ("Carica un file", "PDF, foto, scansioni: dal telefono, dal web o condividendo da un'altra app."),
                ("Ordina in cartelle", "Cartelle e categorie a piacere; la ricerca trova i file per nome e per tag."),
                ("Ritrovalo dove serve", "Un referto allegato a una visita, una ricevuta a un intervento auto: è lo stesso file, visibile da entrambe le schede."),
            ],
            "faq": [
                ("Quanto spazio ho?", "Dipende dal piano della famiglia; lo spazio si vede in Impostazioni e lo condividono tutti i membri."),
                ("Posso importare un documento e farlo leggere all'AI?", "Sì, con il piano Pro: da una fattura o un referto l'AI propone spesa, evento o scadenza da creare."),
                ("Chi può vedere i miei documenti?", "Solo i membri della famiglia. I file sono cifrati con la chiave di famiglia, che i server non hanno."),
            ],
        },
        "en": {
            "title": "Encrypted family documents",
            "short": "Folders and categories for the family's files — reports, contracts, report cards — encrypted and reachable from every other section.",
            "lead": "One place for the files both parents need, with the encryption you'd expect for a medical report or a contract.",
            "steps": [
                ("Upload a file", "PDFs, photos, scans: from the phone, the web, or by sharing from another app."),
                ("Sort into folders", "Folders and categories as you like; search finds files by name and by tag."),
                ("Find it where it's needed", "A report attached to a visit, a receipt to a car repair: it's the same file, visible from both sections."),
            ],
            "faq": [
                ("How much storage do I have?", "It depends on the family plan; storage shows in Settings and is shared by all members."),
                ("Can I import a document and have the AI read it?", "Yes, on the Pro plan: from an invoice or a report the AI suggests the expense, event or deadline to create."),
                ("Who can see my documents?", "Family members only. Files are encrypted with the family key, which the servers don't hold."),
            ],
        },
    },
    {
        "slug": "password",
        "icon": "🔐", "tint": "violet", "shots": "Password", "plan": "free",
        "related": ["note", "wallet", "documenti"],
        "it": {
            "title": "Password di famiglia con AutoFill",
            "short": "Il Wi-Fi, il registro elettronico, lo SPID del nonno: credenziali di famiglia o personali, cifrate, con AutoFill e controllo di sicurezza.",
            "lead": "Le password che servono a due persone non stanno bene in chat. Qui sono cifrate, si compilano da sole e un audit dice quali sono deboli o già trapelate.",
            "steps": [
                ("Salva una credenziale", "Sito, utente, password, note. Scegli se è di famiglia o solo tua: le personali non le vede nessun altro."),
                ("Compila da sola", "Con AutoFill attivo, su iPhone e Android la password si inserisce nel sito o nell'app senza copiarla."),
                ("Controlla la sicurezza", "L'audit segnala password deboli, riutilizzate o comparse in violazioni note, senza mai inviarle in chiaro."),
            ],
            "faq": [
                ("Come funziona il controllo delle violazioni?", "Con k-anonymity su Have I Been Pwned: viene inviata solo una parte dell'hash, mai la password."),
                ("Posso generare password sicure?", "Sì, il generatore crea password lunghe e casuali, con o senza simboli."),
                ("Le password personali sono cifrate diversamente?", "Sì: usano una chiave derivata dalla tua identità, così nemmeno gli altri membri della famiglia possono leggerle."),
            ],
        },
        "en": {
            "title": "Family passwords with AutoFill",
            "short": "The Wi-Fi, the school portal, grandpa's account: family or personal credentials, encrypted, with AutoFill and a security check.",
            "lead": "Passwords two people need don't belong in a chat. Here they're encrypted, fill themselves in, and an audit says which are weak or already leaked.",
            "steps": [
                ("Save a credential", "Site, username, password, notes. Choose whether it's family-wide or yours only: personal ones are seen by nobody else."),
                ("It fills itself in", "With AutoFill on, on iPhone and Android the password goes into the site or app without copying it."),
                ("Check security", "The audit flags weak, reused or breached passwords, without ever sending them in the clear."),
            ],
            "faq": [
                ("How does the breach check work?", "With k-anonymity on Have I Been Pwned: only part of the hash is sent, never the password."),
                ("Can I generate strong passwords?", "Yes, the generator creates long random passwords, with or without symbols."),
                ("Are personal passwords encrypted differently?", "Yes: they use a key derived from your identity, so not even other family members can read them."),
            ],
        },
    },
    {
        "slug": "foto-e-video",
        "icon": "🖼️", "tint": "violet", "shots": "Foto e Video", "plan": "free",
        "related": ["chat", "documenti", "viaggi"],
        "it": {
            "title": "Album di famiglia privati",
            "short": "Foto e video dei figli in album condivisi con l'altro genitore, cifrati e sincronizzati — senza passare dai social né dalla chat.",
            "lead": "I momenti che valgono stanno in un posto che è solo vostro: album cifrati, nessun algoritmo, nessuna compressione da chat.",
            "steps": [
                ("Crea un album", "«Primo anno», «Estate al mare»: gli album sono della famiglia e li riempite entrambi."),
                ("Carica in qualità piena", "Foto e video restano come sono, cifrati prima di partire dal telefono."),
                ("Rivedi insieme", "Galleria per data, anteprime veloci, download dell'originale quando serve."),
            ],
            "faq": [
                ("Le foto sono cifrate anche sui server?", "Sì: vengono cifrate sul dispositivo con la chiave di famiglia. Sui server ci sono solo file illeggibili."),
                ("Quanto spazio occupano?", "Contano nello spazio della famiglia, che dipende dal piano; il riepilogo è in Impostazioni."),
                ("Posso condividere un album con i nonni?", "Non ancora: gli album sono visibili ai membri della famiglia. Puoi però invitare un membro in più."),
            ],
        },
        "en": {
            "title": "Private family albums",
            "short": "Photos and videos of the kids in albums shared with the other parent, encrypted and synced — no social networks, no chat compression.",
            "lead": "The moments that matter live somewhere that's only yours: encrypted albums, no algorithm, no chat-style compression.",
            "steps": [
                ("Create an album", "“First year”, “Summer at the sea”: albums belong to the family and you both fill them."),
                ("Upload at full quality", "Photos and videos stay as they are, encrypted before they leave the phone."),
                ("Look back together", "Gallery by date, quick previews, download of the original when needed."),
            ],
            "faq": [
                ("Are photos encrypted on the servers too?", "Yes: they're encrypted on the device with the family key. The servers only hold unreadable files."),
                ("How much space do they use?", "They count toward the family storage, which depends on the plan; the summary is in Settings."),
                ("Can I share an album with the grandparents?", "Not yet: albums are visible to family members. You can, however, invite one more member."),
            ],
        },
    },
    {
        "slug": "chat",
        "icon": "💬", "tint": "green", "shots": "Chat", "plan": "free",
        "related": ["note", "foto-e-video", "posizione"],
        "it": {
            "title": "Chat di famiglia cifrata end-to-end",
            "short": "Una chat solo per la famiglia, cifrata end-to-end, con vocali trascritti e una galleria dei media inviati. Senza gruppi da gestire.",
            "lead": "Non un altro gruppo WhatsApp: una chat che sta dentro l'app dove ci sono già calendario, spese e documenti, e che nessuno fuori può leggere.",
            "steps": [
                ("Scrivi o registra", "Messaggi, foto, vocali. I vocali vengono trascritti sul telefono, così li leggi anche in riunione."),
                ("Cifrata end-to-end", "I messaggi si cifrano sul tuo dispositivo e si decifrano su quello dell'altro. Le notifiche vengono decifrate sul telefono."),
                ("Ritrova i media", "Foto e file inviati stanno in una galleria della chat, senza scorrere all'infinito."),
            ],
            "faq": [
                ("Chi c'è nella chat?", "Tutti i membri della famiglia, e nessun altro. Non ci sono gruppi da creare."),
                ("Posso disattivarla?", "Sì, dalle Impostazioni. Gli altri continuano a scriversi e ritrovi i messaggi riattivandola."),
                ("La chat funziona sul web?", "Sì, con gli stessi messaggi e la stessa cifratura del telefono."),
            ],
        },
        "en": {
            "title": "End-to-end encrypted family chat",
            "short": "A chat for the family only, end-to-end encrypted, with transcribed voice notes and a gallery of the media sent. No groups to manage.",
            "lead": "Not another WhatsApp group: a chat inside the app where calendar, expenses and documents already live, that nobody outside can read.",
            "steps": [
                ("Write or record", "Messages, photos, voice notes. Voice notes are transcribed on the phone, so you can read them in a meeting."),
                ("End-to-end encrypted", "Messages are encrypted on your device and decrypted on the other's. Notifications are decrypted on the phone."),
                ("Find the media", "Photos and files sent live in the chat's gallery, no endless scrolling."),
            ],
            "faq": [
                ("Who's in the chat?", "Every family member, and nobody else. There are no groups to create."),
                ("Can I turn it off?", "Yes, from Settings. The others keep chatting and you find the messages again when you turn it back on."),
                ("Does the chat work on the web?", "Yes, with the same messages and the same encryption as the phone."),
            ],
        },
    },
    {
        "slug": "salute",
        "icon": "🩺", "tint": "accent", "shots": None, "plan": "free",
        "related": ["documenti", "calendario", "assistente-ai"],
        "it": {
            "title": "Salute dei figli: visite, vaccini, cartella clinica",
            "short": "Lo storico clinico di ogni membro — visite, esami, vaccini, cure — con i referti allegati e una cartella da mostrare al medico. Con Apple Health e Health Connect.",
            "lead": "Quando il pediatra chiede «quando ha fatto l'ultimo richiamo?», la risposta è qui, con il referto accanto. E i dati del telefono — passi, battito, sonno — entrano da soli.",
            "steps": [
                ("Registra visite ed esami", "Data, medico, esito, referto allegato. Una visita con un costo diventa anche una spesa."),
                ("Tieni i vaccini in ordine", "Il libretto vaccinale di ogni figlio, con i richiami in calendario."),
                ("Mostra la cartella clinica", "Un documento riepilogativo, aggiornato, da aprire in studio o da inviare a un nuovo medico."),
            ],
            "faq": [
                ("I dati di salute sono cifrati?", "Sì: referti e allegati sono cifrati con la chiave di famiglia, e le schede cliniche sono leggibili solo dai membri."),
                ("Cosa arriva da Apple Health / Health Connect?", "Passi, battito, pressione, SpO₂, calorie attive, allenamenti e distanza, solo se dai il permesso."),
                ("Cosa aggiunge il piano Pro?", "Piano alimentare e piano fitness generati dall'AI su misura del profilo, e un'analisi mensile della storia sanitaria."),
            ],
        },
        "en": {
            "title": "Kids' health: visits, vaccines, medical record",
            "short": "Each member's clinical history — visits, tests, vaccines, treatments — with reports attached and a record to show the doctor. With Apple Health and Health Connect.",
            "lead": "When the paediatrician asks “when was the last booster?”, the answer is here, with the report next to it. And the phone's data — steps, heart rate, sleep — comes in on its own.",
            "steps": [
                ("Log visits and tests", "Date, doctor, outcome, attached report. A visit with a cost becomes an expense too."),
                ("Keep vaccines in order", "Each child's vaccination record, with boosters in the calendar."),
                ("Show the medical record", "A summary document, kept up to date, to open at the surgery or send to a new doctor."),
            ],
            "faq": [
                ("Is health data encrypted?", "Yes: reports and attachments are encrypted with the family key, and clinical entries are readable by members only."),
                ("What comes from Apple Health / Health Connect?", "Steps, heart rate, blood pressure, SpO₂, active calories, workouts and distance, only if you grant permission."),
                ("What does the Pro plan add?", "AI-generated meal and fitness plans tailored to the profile, and a monthly analysis of the health history."),
            ],
        },
    },
    {
        "slug": "casa",
        "icon": "🏠", "tint": "amber", "shots": "Casa", "plan": "free",
        "related": ["veicoli", "spese", "documenti"],
        "it": {
            "title": "Casa: garanzie, manutenzioni e scadenze",
            "short": "Elettrodomestici con garanzia e manutenzioni, più le scadenze di casa — bollette, tasse, contratti — con promemoria e ricevute.",
            "lead": "La caldaia, la lavatrice, l'assicurazione casa, la TARI: cose che scadono e che di solito ricorda un genitore solo. Qui le ricordano a tutti e due.",
            "steps": [
                ("Censisci i beni", "Marca, modello, data d'acquisto, garanzia, manuale in PDF. La scadenza della garanzia va in calendario."),
                ("Segna le manutenzioni", "Revisione caldaia, filtri, tagliando del condizionatore: quando è stata fatta e quando tocca."),
                ("Scadenze e pagamenti", "Bollette, tasse e contratti con importo, promemoria e ricevuta allegata; pagati, diventano spese."),
            ],
            "faq": [
                ("Le scadenze avvisano tutti?", "Sì, il promemoria arriva ai membri della famiglia con le notifiche attive."),
                ("Posso allegare la ricevuta?", "Sì: finisce in Documenti, cifrata, collegata alla scadenza."),
                ("Che differenza c'è con Veicoli?", "Veicoli ha le scadenze specifiche dell'auto — bollo, assicurazione, revisione — e gli interventi in officina."),
            ],
        },
        "en": {
            "title": "Home: warranties, maintenance and deadlines",
            "short": "Appliances with warranty and maintenance, plus household deadlines — bills, taxes, contracts — with reminders and receipts.",
            "lead": "The boiler, the washing machine, the home insurance, the waste tax: things that expire and that usually one parent alone remembers. Here they remind both.",
            "steps": [
                ("List your assets", "Brand, model, purchase date, warranty, manual in PDF. The warranty expiry goes in the calendar."),
                ("Log maintenance", "Boiler service, filters, air-con check: when it was done and when it's due."),
                ("Deadlines and payments", "Bills, taxes and contracts with amount, reminder and attached receipt; once paid, they become expenses."),
            ],
            "faq": [
                ("Do deadlines alert everyone?", "Yes, the reminder reaches family members with notifications on."),
                ("Can I attach the receipt?", "Yes: it goes into Documents, encrypted, linked to the deadline."),
                ("How is this different from Vehicles?", "Vehicles has the car-specific deadlines — road tax, insurance, inspection — and the garage jobs."),
            ],
        },
    },
    {
        "slug": "veicoli",
        "icon": "🚗", "tint": "blue", "shots": "Garage", "plan": "free",
        "related": ["casa", "spese", "documenti"],
        "it": {
            "title": "Veicoli: bollo, assicurazione, revisione",
            "short": "Una scheda per ogni auto con le scadenze che contano — bollo, assicurazione, revisione — e gli interventi in officina con costo e ricevuta.",
            "lead": "Le auto di famiglia hanno scadenze che costano care se dimenticate. Qui stanno in una scheda sola, con lo storico degli interventi e quanto sono costati.",
            "steps": [
                ("Aggiungi il veicolo", "Targa, modello, chilometri. Le scadenze di bollo, assicurazione e revisione vanno in calendario con promemoria."),
                ("Registra gli interventi", "Tagliando, gomme, pasticche, riparazioni: data, chilometri, costo e ricevuta allegata."),
                ("Vedi quanto costa", "Ogni intervento con un costo è anche una spesa di famiglia, nella categoria giusta."),
            ],
            "faq": [
                ("Il bollo è un intervento?", "No, è una scadenza della scheda veicolo: la registri una volta e si ripete ogni anno."),
                ("Posso avere più veicoli?", "Sì, una scheda per ciascuno, visibile a tutta la famiglia."),
                ("Le ricevute dove finiscono?", "In Documenti, cifrate, collegate all'intervento."),
            ],
        },
        "en": {
            "title": "Vehicles: road tax, insurance, inspection",
            "short": "A card for every car with the deadlines that matter — road tax, insurance, inspection — and garage jobs with cost and receipt.",
            "lead": "Family cars have deadlines that cost dearly when forgotten. Here they sit in one card, with the service history and what it cost.",
            "steps": [
                ("Add the vehicle", "Plate, model, mileage. Road tax, insurance and inspection deadlines go in the calendar with reminders."),
                ("Log the jobs", "Service, tyres, brake pads, repairs: date, mileage, cost and attached receipt."),
                ("See what it costs", "Every job with a cost is also a family expense, in the right category."),
            ],
            "faq": [
                ("Is road tax a job?", "No, it's a deadline on the vehicle card: log it once and it repeats every year."),
                ("Can I have several vehicles?", "Yes, one card each, visible to the whole family."),
                ("Where do receipts go?", "Into Documents, encrypted, linked to the job."),
            ],
        },
    },
    {
        "slug": "animali",
        "icon": "🐾", "tint": "green", "shots": "Animali", "plan": "free",
        "related": ["salute", "casa", "calendario"],
        "it": {
            "title": "Animali di casa: vaccini e veterinario",
            "short": "Il profilo di ogni animale con le visite dal veterinario, i vaccini, gli antiparassitari e i documenti — libretto e microchip — allegati.",
            "lead": "Il cane e il gatto hanno un libretto come i bambini, e le stesse cose da ricordare: il richiamo, l'antipulci, la visita annuale.",
            "steps": [
                ("Crea il profilo", "Nome, specie, razza, data di nascita, microchip, foto."),
                ("Registra gli eventi", "Vaccini, visite, trattamenti, con la data del prossimo e il promemoria."),
                ("Allega i documenti", "Libretto sanitario, passaporto, certificati: in Documenti, cifrati."),
            ],
            "faq": [
                ("Ci sono promemoria per i richiami?", "Sì, per ogni evento puoi impostare la data del prossimo e ricevere l'avviso."),
                ("Le spese dal veterinario vanno nelle Spese?", "Sì, se indichi un costo l'evento diventa anche una spesa."),
                ("Quanti animali posso aggiungere?", "Quanti ne avete."),
            ],
        },
        "en": {
            "title": "Pets: vaccines and the vet",
            "short": "Each pet's profile with vet visits, vaccines, antiparasitic treatments and documents — health book and microchip — attached.",
            "lead": "The dog and the cat have a health book like the kids, and the same things to remember: the booster, the flea treatment, the yearly check-up.",
            "steps": [
                ("Create the profile", "Name, species, breed, date of birth, microchip, photo."),
                ("Log events", "Vaccines, visits, treatments, with the next due date and a reminder."),
                ("Attach documents", "Health book, passport, certificates: in Documents, encrypted."),
            ],
            "faq": [
                ("Are there reminders for boosters?", "Yes, for every event you can set the next date and get an alert."),
                ("Do vet bills go into Expenses?", "Yes, if you enter a cost the event becomes an expense too."),
                ("How many pets can I add?", "As many as you have."),
            ],
        },
    },
    {
        "slug": "posizione",
        "icon": "📍", "tint": "blue", "shots": "Posizione", "plan": "free",
        "related": ["chat", "calendario", "viaggi"],
        "it": {
            "title": "Posizione della famiglia e geofence",
            "short": "Dove sono tutti, su una mappa sola, con avvisi quando qualcuno arriva o parte da un luogo e condivisioni temporanee per un pomeriggio.",
            "lead": "Non un tracker: una condivisione che ognuno accende e spegne, con gli avvisi che servono davvero — «è arrivato a scuola», «è uscita dal lavoro».",
            "steps": [
                ("Condividi quando vuoi", "Ognuno decide se condividere, per sempre o per un tempo limitato."),
                ("Crea un luogo", "Casa, scuola, nonni: un geofence attorno al posto, con l'avviso all'arrivo e alla partenza."),
                ("Guarda la mappa", "Tutti i membri che condividono, con l'ultimo aggiornamento e la batteria."),
            ],
            "faq": [
                ("Posso spegnere la condivisione?", "Sì, in qualunque momento, e gli altri vengono avvisati che hai smesso."),
                ("La posizione è cifrata?", "Le coordinate in tempo reale sono leggibili solo dai membri della famiglia e non vengono conservate come storico."),
                ("Consuma molta batteria?", "Usa gli aggiornamenti in background del sistema, ottimizzati per il consumo."),
            ],
        },
        "en": {
            "title": "Family location and geofences",
            "short": "Where everyone is, on one map, with alerts when someone arrives at or leaves a place, and temporary sharing for an afternoon.",
            "lead": "Not a tracker: sharing each person turns on and off, with the alerts that actually help — “he's at school”, “she's left work”.",
            "steps": [
                ("Share when you want", "Everyone decides whether to share, permanently or for a limited time."),
                ("Create a place", "Home, school, grandparents: a geofence around the spot, with alerts on arrival and departure."),
                ("Look at the map", "Every member who's sharing, with last update and battery level."),
            ],
            "faq": [
                ("Can I turn sharing off?", "Yes, at any time, and the others are told you've stopped."),
                ("Is location encrypted?", "Live coordinates are readable by family members only and aren't kept as a history."),
                ("Does it drain the battery?", "It uses the system's background updates, optimised for power."),
            ],
        },
    },
    {
        "slug": "viaggi",
        "icon": "✈️", "tint": "amber", "shots": None, "plan": "pro",
        "related": ["wallet", "posizione", "foto-e-video"],
        "it": {
            "title": "Viaggi in famiglia con itinerario AI",
            "short": "Un itinerario giorno per giorno generato dall'AI per la vostra famiglia, con i locali di Google sulla mappa, «Storia e territorio», e foto, spese e to-do del viaggio.",
            "lead": "Dici dove andate, con chi e per quanto: l'AI propone un itinerario a misura di bambini, con i posti veri sulla mappa. Poi il viaggio raccoglie tutto il resto.",
            "steps": [
                ("Descrivi il viaggio", "Destinazione, date, età dei figli, ritmo. L'AI costruisce giorno per giorno cosa fare."),
                ("Esplora sulla mappa", "Ristoranti, parchi e musei da Google, con orari e valutazioni; «Storia e territorio» racconta il posto."),
                ("Vivi il viaggio", "Foto, spese, cose da fare e note del viaggio restano nella sua scheda, condivisa con la famiglia."),
            ],
            "faq": [
                ("L'itinerario si può modificare?", "Sì: sposti, togli e aggiungi tappe; l'AI è un punto di partenza."),
                ("Serve il piano Pro?", "Sì, la generazione dell'itinerario e i contenuti AI richiedono Pro o Max."),
                ("I biglietti dove stanno?", "Nel Wallet, letti dal PDF; dal viaggio li ritrovi con un tocco."),
            ],
        },
        "en": {
            "title": "Family trips with an AI itinerary",
            "short": "A day-by-day itinerary generated by AI for your family, with Google places on the map, “History and territory”, and the trip's photos, expenses and to-dos.",
            "lead": "Say where you're going, with whom and for how long: the AI proposes a kid-friendly itinerary with real places on the map. Then the trip gathers everything else.",
            "steps": [
                ("Describe the trip", "Destination, dates, kids' ages, pace. The AI lays out what to do day by day."),
                ("Explore the map", "Restaurants, parks and museums from Google, with hours and ratings; “History and territory” tells the place's story."),
                ("Live the trip", "Photos, expenses, to-dos and trip notes stay in its card, shared with the family."),
            ],
            "faq": [
                ("Can the itinerary be edited?", "Yes: move, remove and add stops; the AI is a starting point."),
                ("Do I need the Pro plan?", "Yes, itinerary generation and AI content require Pro or Max."),
                ("Where do tickets go?", "In the Wallet, read from the PDF; from the trip you reach them in one tap."),
            ],
        },
    },
    {
        "slug": "assistente-ai",
        "icon": "✨", "tint": "violet", "shots": None, "plan": "pro",
        "related": ["calendario", "documenti", "salute"],
        "it": {
            "title": "Assistente AI di famiglia",
            "short": "Un assistente che conosce calendario, spese, salute e documenti della famiglia, e agisce: crea eventi, to-do e spese, legge i documenti che importi.",
            "lead": "Non una chat generica: un assistente con il contesto della vostra famiglia, che alla domanda «quando ha fatto l'antitetanica?» risponde con la data, e a «segna la spesa di 40 € dal dentista» crea la spesa.",
            "steps": [
                ("Chiedi", "In linguaggio naturale, dal telefono o dal web. L'assistente risponde con i vostri dati, non con quelli di internet."),
                ("Lascia che agisca", "Eventi, cose da fare, spese: le crea per te e te le mostra prima di salvarle."),
                ("Importa un documento", "Una fattura o un referto: l'AI lo legge e propone cosa registrare — spesa, scadenza, visita."),
            ],
            "faq": [
                ("Quali dati vede l'AI?", "Solo quelli che scegli di condividere, richiesta per richiesta; per il contesto Salute puoi scegliere un riassunto o chiedere ogni volta."),
                ("È incluso nel piano Free?", "Il Free ha 5 messaggi di prova una tantum; l'uso continuativo richiede Pro o Max."),
                ("Cos'è la «mente proattiva»?", "Con Pro, l'assistente prepara da solo un briefing al mattino, un recap settimanale e un'analisi mensile."),
            ],
        },
        "en": {
            "title": "Family AI assistant",
            "short": "An assistant that knows the family's calendar, expenses, health and documents, and acts: creates events, to-dos and expenses, reads the documents you import.",
            "lead": "Not a generic chat: an assistant with your family's context, that answers “when was the tetanus shot?” with the date, and turns “log €40 at the dentist” into an expense.",
            "steps": [
                ("Ask", "In plain language, from the phone or the web. The assistant answers with your data, not the internet's."),
                ("Let it act", "Events, to-dos, expenses: it creates them for you and shows them before saving."),
                ("Import a document", "An invoice or a report: the AI reads it and suggests what to record — expense, deadline, visit."),
            ],
            "faq": [
                ("Which data does the AI see?", "Only what you choose to share, request by request; for Health context you can pick a summary or be asked every time."),
                ("Is it in the Free plan?", "Free has 5 one-off trial messages; continued use requires Pro or Max."),
                ("What is the “proactive mind”?", "With Pro, the assistant prepares a morning briefing, a weekly recap and a monthly analysis on its own."),
            ],
        },
    },
    {
        "slug": "alexa",
        "icon": "🔊", "tint": "blue", "shots": None, "plan": "free",
        "related": ["lista-della-spesa", "to-do", "assistente-ai"],
        "it": {
            "title": "Alexa: spesa e promemoria a voce",
            "short": "Detta la spesa e le cose da fare agli Echo di casa: finiscono nella lista di famiglia e nei to-do di KidBox, e gli altri le vedono subito.",
            "lead": "«Alexa, chiedi a mio box di aggiungere le uova». Mentre cucini, con le mani occupate, la lista di famiglia si aggiorna sul telefono di chi farà la spesa.",
            "steps": [
                ("Attiva la skill", "Nell'app Alexa cerca «KidBox» e attivala."),
                ("Collega l'account", "In KidBox, Impostazioni → Alexa: un codice a 6 cifre da dettare una volta sola."),
                ("Parla", "Spesa e promemoria a voce; i promemoria diventano to-do che suonano all'ora detta."),
            ],
            "faq": [
                ("In quali lingue funziona?", "Solo in italiano, per ora."),
                ("Perché «mio box»?", "È il nome di invocazione della skill: Amazon non permette più alle skill di scrivere nella lista della spesa nativa di Alexa."),
                ("Serve il piano Pro?", "No, la skill è inclusa nel Free."),
            ],
        },
        "en": {
            "title": "Alexa: groceries and reminders by voice",
            "short": "Dictate groceries and to-dos to the Echo devices at home: they land in the family list and KidBox to-dos, and the others see them right away.",
            "lead": "“Alexa, ask my box to add eggs.” While you cook, hands busy, the family list updates on the phone of whoever will do the shopping.",
            "steps": [
                ("Enable the skill", "In the Alexa app search for “KidBox” and enable it."),
                ("Link the account", "In KidBox, Settings → Alexa: a 6-digit code to dictate once."),
                ("Speak", "Groceries and reminders by voice; reminders become to-dos that ring at the time you said."),
            ],
            "faq": [
                ("Which languages does it support?", "Italian only, for now."),
                ("Why “my box”?", "It's the skill's invocation name: Amazon no longer lets skills write to Alexa's native shopping list."),
                ("Do I need the Pro plan?", "No, the skill is included in Free."),
            ],
        },
    },
    {
        "slug": "famiglia",
        "icon": "👪", "tint": "accent", "shots": "Wizard", "plan": "free",
        "related": ["chat", "calendario", "password"],
        "it": {
            "title": "Famiglia, profili e inviti",
            "short": "Un profilo per ogni genitore e ogni figlio, un invito con link o QR che porta con sé la chiave di cifratura, e più famiglie per chi ne ha bisogno.",
            "lead": "Tutto in KidBox è «di famiglia»: la famiglia si crea in un minuto, l'altro genitore entra con un link, e da lì in poi vedete le stesse cose.",
            "steps": [
                ("Crea la famiglia", "Nome, primo figlio, il tuo nome: il wizard fa il resto e genera la chiave di cifratura."),
                ("Invita il partner", "Un link da inviare o un QR da inquadrare, validi 24 ore e una volta sola: dentro c'è la chiave, avvolta."),
                ("Aggiungi i figli", "Un profilo per ognuno, con data di nascita e foto; le schede di salute e scuola si agganciano al profilo."),
            ],
            "faq": [
                ("Posso far parte di due famiglie?", "Sì, per esempio famiglia allargata e nonni: si passa dall'una all'altra dalle Impostazioni."),
                ("Cosa succede se perdo il telefono?", "Accedi da un altro dispositivo: la chiave di famiglia si recupera dall'account e i dati tornano leggibili."),
                ("Quante persone possono entrare?", "Dipende dal piano; il Free copre una famiglia di due genitori."),
            ],
        },
        "en": {
            "title": "Family, profiles and invites",
            "short": "A profile for each parent and each child, an invite by link or QR that carries the encryption key, and multiple families for those who need them.",
            "lead": "Everything in KidBox is “family-wide”: the family is created in a minute, the other parent joins with a link, and from then on you see the same things.",
            "steps": [
                ("Create the family", "Name, first child, your name: the wizard does the rest and generates the encryption key."),
                ("Invite your partner", "A link to send or a QR to scan, valid 24 hours and once only: the key travels inside, wrapped."),
                ("Add the kids", "A profile each, with date of birth and photo; health and school entries attach to the profile."),
            ],
            "faq": [
                ("Can I be in two families?", "Yes, say a blended family and the grandparents: switch between them from Settings."),
                ("What if I lose my phone?", "Sign in from another device: the family key is recovered from the account and data becomes readable again."),
                ("How many people can join?", "It depends on the plan; Free covers a family of two parents."),
            ],
        },
    },
]

# Spagnolo e francese (Alexa esclusa: la skill è solo in italiano).
from tools_data_es_fr import ES as _ES, FR as _FR  # noqa: E402

for _t in TOOLS:
    if _t["slug"] in _ES:
        _t["es"] = _ES[_t["slug"]]
    if _t["slug"] in _FR:
        _t["fr"] = _FR[_t["slug"]]
