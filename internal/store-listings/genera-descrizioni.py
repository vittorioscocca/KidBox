"""Genera le descrizioni App Store (iOS e Mac) in quattro lingue da un'unica struttura.

Uso: python3 genera-descrizioni.py  → appstore-ios-<lingua>.txt e appstore-mac-<lingua>.txt
Differenze Mac: niente lente «Cerca in KidBox» né scorciatoia fotocamera (non ci sono sul Mac),
righe legali con «EULA». Limite App Store: 4000 caratteri per lingua.
"""
L = {}

L["it"] = dict(
 open="""«Chi prende Marco giovedì?» Con KidBox la famiglia si organizza in un tocco: chiedi, e chi può risponde «Ci penso io», anche se non ha l'app.

{{Altre app ricordano te. KidBox ricorda la famiglia: calendario||KidBox è l'agente della tua famiglia: calendario}}, to-do, spesa, spese, documenti e salute in un posto solo, con un assistente che conosce {{tutto quello che ci metti e si accorge di quello che resta scoperto. Un solo||tutto quello che ci metti. Un solo}} abbonamento per tutta la famiglia, senza limite di membri.""",
 blocks=[
 ("CHIEDI ALLA FAMIGLIA", "Dall'editor del to-do chiedi a uno o più familiari, oppure a chi non ha KidBox (nonni, babysitter) con un link da aprire nel browser. Il primo che risponde «Ci penso io» si prende il compito e nasce il to-do, con il suo nome."),
 ("SI ACCORGE PRIMA DI TE (PRO E MAX)", "Se un to-do sta per scadere e nessuno l'ha preso, o una dose di oggi non risulta registrata, KidBox ti avvisa. Dalla notifica, senza aprire l'app: «Ci penso io» o «Chiedi agli altri» per il to-do, «Presa» per la dose. Accendi «Chiedi agli altri al posto mio»: se 12 ore prima nessuno ha preso un tuo to-do, KidBox manda la richiesta da solo e ti dice chi se ne occupa. Riepilogo serale e orari di silenzio a scelta; gli avvisi non usano messaggi AI.", "ios"),
 ("ASSISTENTE AI", "Chiedi: «quando è la prossima visita di Marco?», {{«cosa manca nella lista della spesa?». Conosce||«cosa manca nella lista della spesa?», «ricordami di chiamare il pediatra domani». Conosce}} il calendario, i to-do, la spesa, le note, le spese, i documenti e la salute di tutti, e risponde con link che aprono la voce giusta. Crea eventi, to-do, note, voci della spesa e promemoria. Ogni mattina alle 8:00 un riepilogo degli impegni del giorno e delle dosi da somministrare."),
 ("CALENDARIO E TO-DO", "Calendario condiviso con ricorrenze e promemoria, e i calendari del telefono accanto a quelli della famiglia (in sola lettura). To-do assegnabili a ciascuno; un promemoria urgente suona come una sveglia."),
 ("CERCA IN KIDBOX", "Una lente in Home cerca in tutta l'app direttamente sul telefono, senza AI e senza costi: spese, documenti, note, calendario, to-do, salute e altro.", "ios"),
 ("SALUTE", "Visite, esami, vaccini e cure di bambini e adulti, con promemoria per le scadenze e lo storico sanitario sempre a portata di mano."),
 ("SPESA E SPESE", "Lista della spesa condivisa e aggiornata in tempo reale: quando uno la spunta, l'altro lo vede subito. Detti spesa e to-do ad Alexa: «Alexa, chiedi a mio box di aggiungere il latte». Spese per categoria, con scontrini e foto allegati."),
 ("{{DOCUMENTI CHE SI SISTEMANO DA SOLI||DOCUMENTI}}", "{{Fotografa una bolletta, un referto o una ricetta e dalla all'assistente con il «+»: KidBox capisce cos'è e la mette al posto giusto. La bolletta diventa una scadenza di Casa, il referto una visita con le parole del medico, le analisi un esame con i valori, la ricetta una cura. Il file resta allegato e tu confermi con un tocco. Tutto in un archivio cifrato con una chiave che resta alla famiglia.||Referti, ricette, certificati e foto in un archivio cifrato con una chiave che resta alla famiglia. Importa una fattura, una ricetta o un referto: KidBox lo legge e propone le azioni giuste (aggiungere la spesa, creare l'evento, registrare la visita, impostare il promemoria). Tu scegli cosa confermare, con un tocco.}}"),
 ("NOTIZIE (PRO E MAX)", "Ogni giorno le notizie utili alla tua famiglia, dal paese alla tua città, ciascuna con la sua fonte. Gli eventi vicini si aggiungono al calendario con un tocco."),
 ("E ANCORA", "Password di famiglia cifrate, con autocompilazione e codici OTP · Wallet per biglietti, tessere e carte · Posizione in tempo reale · Animali domestici · Casa e garage con scadenze e storico interventi · Viaggi con itinerario AI · Visibilità selettiva: tutta la famiglia, alcuni membri o solo tu · Più famiglie in un'unica app.\\n§Apri la fotocamera di KidBox dal Centro di Controllo senza aprire l'app.§ios"),
 ],
 plans="""PIANI
- Free: calendario, to-do, spesa, spese, documenti e salute, 200 MB, 5 messaggi AI di prova (una tantum)
- Pro (€4,99/mese o €39,99/anno): 5 GB, 30 messaggi AI al giorno (100/mese), piani pasti e fitness, viaggi con AI, {{Notizie, avvisi proattivi||Notizie}}
- Max (€9,99/mese o €79,99/anno): 20 GB, 100 messaggi AI al giorno (200/mese)
Puoi provare il Pro per 14 giorni dall'app. Un solo abbonamento per tutta la famiglia, senza limite di membri. Si rinnova automaticamente; si gestisce e annulla dall'ID Apple.""",
 legal_ios="Privacy: https://kidboxapp.com/privacy.html\nTermini: https://kidboxapp.com/terms.html",
 legal_mac="Termini d'uso (EULA): https://kidboxapp.com/terms.html\nPrivacy: https://kidboxapp.com/privacy.html",
)

L["en-GB"] = dict(
 open="""“Who picks Marco up on Thursday?” With KidBox the family organises itself in a tap: ask, and whoever can says “I'll do it”, even without the app.

{{Other apps remember you. KidBox remembers the family: calendar||KidBox is the agent for your family: calendar}}, to-dos, shopping, expenses, documents and health in one place, with an assistant that knows {{everything you keep in it and notices what's been left uncovered. One||everything you keep in it. One}} subscription for the whole family, with no member limit.""",
 blocks=[
 ("ASK THE FAMILY", "From the to-do editor, ask one or more family members, or someone without KidBox (grandparents, a babysitter) with a link that opens in the browser. The first to reply “I'll do it” takes the task, and the to-do is created with their name."),
 ("IT NOTICES BEFORE YOU DO (PRO AND MAX)", "If a to-do is about to fall due and nobody has taken it, or today's dose hasn't been recorded, KidBox lets you know. From the notification, without opening the app: “I'll do it” or “Ask the others” for the to-do, “Taken” for the dose. Turn on “Ask the others for me”: if nobody has taken one of your to-dos 12 hours before it's due, KidBox sends the request itself and tells you who's on it. Evening summary and quiet hours as you like; alerts don't use AI messages.", "ios"),
 ("AI ASSISTANT", "Ask: “when is Marco's next check-up?”, {{“what's missing from the shopping list?”. It knows||“what's missing from the shopping list?”, “remind me to call the paediatrician tomorrow”. It knows}} everyone's calendar, to-dos, shopping, notes, expenses, documents and health, and answers with links that open the right item. It creates events, to-dos, notes, shopping items and reminders. Every morning at 8:00, a summary of the day's commitments and medication doses."),
 ("CALENDAR AND TO-DOS", "A shared calendar with recurring events and reminders, with your phone's calendars alongside the family's (read-only). To-dos you can assign to anyone; an urgent reminder rings like an alarm."),
 ("SEARCH KIDBOX", "A magnifier on Home searches the whole app right on your phone, with no AI and no cost: expenses, documents, notes, calendar, to-dos, health and more.", "ios"),
 ("HEALTH", "Appointments, tests, vaccines and treatments for children and adults, with reminders for deadlines and the full health history always at hand."),
 ("SHOPPING AND EXPENSES", "A shared shopping list updated in real time: when one person ticks an item, the other sees it at once. Dictate shopping and to-dos to Alexa: “Alexa, ask mio box to add milk”. Expenses by category, with receipts and photos attached."),
 ("{{DOCUMENTS THAT FILE THEMSELVES||DOCUMENTS}}", "{{Snap a bill, a medical report or a prescription and hand it to the assistant with the “+”: KidBox works out what it is and puts it in the right place. The bill becomes a Home due date, the report a visit with the doctor's words, lab results a test with the values, the prescription a treatment. The file stays attached and you confirm with a tap. All in an encrypted archive with a key that stays with the family.||Medical reports, prescriptions, certificates and photos in an encrypted archive with a key that stays with the family. Import an invoice, a prescription or a report: KidBox reads it and suggests the right actions (add the expense, create the event, log the visit, set the reminder). You choose what to confirm, with a tap.}}"),
 ("NEWS (PRO AND MAX)", "Every day, the news that matters to your family, from your country down to your town, each with its source. Nearby events go into the calendar with a tap."),
 ("AND MORE", "Encrypted family passwords with autofill and OTP codes · Wallet for tickets, cards and payment cards · Real-time location · Pets · Home and garage with deadlines and service history · Trips with an AI itinerary · Selective visibility: the whole family, some members or just you · Multiple families in one app.\\n§Open the KidBox camera from Control Centre without opening the app.§ios"),
 ],
 plans="""PLANS
- Free: calendar, to-dos, shopping, expenses, documents and health, 200 MB, 5 trial AI messages (one time)
- Pro (€4.99/month or €39.99/year): 5 GB, 30 AI messages per day (100/month), meal and fitness plans, AI travel, {{News, proactive alerts||News}}
- Max (€9.99/month or €79.99/year): 20 GB, 100 AI messages per day (200/month)
You can try Pro for 14 days from the app. One subscription for the whole family, with no member limit. It renews automatically; manage or cancel it in your Apple ID settings.""",
 legal_ios="Privacy: https://kidboxapp.com/privacy.html\nTerms: https://kidboxapp.com/terms.html",
 legal_mac="Terms of Use (EULA): https://kidboxapp.com/terms.html\nPrivacy Policy: https://kidboxapp.com/privacy.html",
)

L["es-ES"] = dict(
 open="""«¿Quién recoge a Marco el jueves?» Con KidBox la familia se organiza con un toque: pregunta, y quien pueda responde «Me encargo yo», aunque no tenga la app.

{{Otras apps te recuerdan a ti. KidBox recuerda a la familia: calendario||KidBox es el agente de tu familia: calendario}}, tareas, compra, gastos, documentos y salud en un solo lugar, con un asistente que conoce {{todo lo que guardas y se da cuenta de lo que queda sin cubrir. Una||todo lo que guardas. Una}} sola suscripción para toda la familia, sin límite de miembros.""",
 blocks=[
 ("PREGUNTA A LA FAMILIA", "Desde el editor de tareas pregunta a uno o varios familiares, o a quien no tiene KidBox (abuelos, canguro) con un enlace que se abre en el navegador. El primero que responde «Me encargo yo» se queda con la tarea y nace la tarea con su nombre."),
 ("SE DA CUENTA ANTES QUE TÚ (PRO Y MAX)", "Si una tarea está a punto de vencer y nadie la ha cogido, o la dosis de hoy no está registrada, KidBox te avisa. Desde la notificación, sin abrir la app: «Me encargo yo» o «Pregunta a los demás» para la tarea, «Tomada» para la dosis. Activa «Pregunta a los demás por mí»: si 12 horas antes nadie ha cogido una de tus tareas, KidBox envía la solicitud solo y te dice quién se encarga. Resumen de la tarde y horas de silencio a tu gusto; los avisos no usan mensajes de IA.", "ios"),
 ("ASISTENTE DE IA", "Pregunta: «¿cuándo es la próxima visita de Marco?», {{«¿qué falta en la lista de la compra?». Conoce||«¿qué falta en la lista de la compra?», «recuérdame llamar al pediatra mañana». Conoce}} el calendario, las tareas, la compra, las notas, los gastos, los documentos y la salud de todos, y responde con enlaces que abren el elemento correcto. Crea eventos, tareas, notas, artículos de la compra y recordatorios. Cada mañana a las 8:00, un resumen de los compromisos del día y de las dosis de medicación."),
 ("CALENDARIO Y TAREAS", "Calendario compartido con eventos recurrentes y recordatorios, y los calendarios del teléfono junto a los de la familia (solo lectura). Tareas que se asignan a cada uno; un recordatorio urgente suena como una alarma."),
 ("BUSCAR EN KIDBOX", "Una lupa en Inicio busca en toda la app directamente en el teléfono, sin IA y sin coste: gastos, documentos, notas, calendario, tareas, salud y más.", "ios"),
 ("SALUD", "Visitas, pruebas, vacunas y tratamientos de niños y adultos, con recordatorios de plazos y el historial de salud siempre a mano."),
 ("COMPRA Y GASTOS", "Lista de la compra compartida y actualizada en tiempo real: cuando uno la tacha, el otro lo ve al instante. Dicta compra y tareas a Alexa: «Alexa, pídele a mio box que añada leche». Gastos por categoría, con tickets y fotos adjuntos."),
 ("{{DOCUMENTOS EN SU SITIO||DOCUMENTOS}}", "{{Dale al asistente, con el «+», la foto de una factura, un informe o una receta: KidBox la guarda donde va. La factura pasa a Casa, el informe a una visita, los análisis a una prueba, la receta a un tratamiento, con el archivo adjunto. Tú confirmas. Todo cifrado con una clave de la familia.||Informes médicos, recetas, certificados y fotos en un archivo cifrado con una clave que se queda en la familia. Importa una factura, una receta o un informe: KidBox lo lee y propone las acciones adecuadas (añadir el gasto, crear el evento, registrar la visita, programar el recordatorio). Tú eliges qué confirmar, con un toque.}}"),
 ("NOTICIAS (PRO Y MAX)", "Cada día, las noticias útiles para tu familia, de tu país a tu ciudad, cada una con su fuente. Los eventos cercanos se añaden al calendario con un toque."),
 ("Y MÁS", "Contraseñas de familia cifradas, con autorrelleno y códigos OTP · Wallet para entradas, tarjetas y tarjetas de pago · Ubicación en tiempo real · Mascotas · Casa y garaje con plazos e historial de intervenciones · Viajes con itinerario de IA · Visibilidad selectiva: toda la familia, algunos miembros o solo tú · Varias familias en una sola app.\\n§Abre la cámara de KidBox desde el Centro de control sin abrir la app.§ios"),
 ],
 plans="""PLANES
- Free: calendario, tareas, compra, gastos, documentos y salud, 200 MB, 5 mensajes de IA de prueba (una sola vez)
- Pro (4,99 €/mes o 39,99 €/año): 5 GB, 30 mensajes de IA al día (100/mes), planes de comidas y fitness, viajes con IA, {{Noticias, avisos proactivos||Noticias}}
- Max (9,99 €/mes o 79,99 €/año): 20 GB, 100 mensajes de IA al día (200/mes)
Puedes probar el Pro durante 14 días desde la app. Una sola suscripción para toda la familia, sin límite de miembros. Se renueva automáticamente; se gestiona y cancela desde tu ID de Apple.""",
 legal_ios="Privacidad: https://kidboxapp.com/privacy.html\nTérminos: https://kidboxapp.com/terms.html",
 legal_mac="Términos de uso (EULA): https://kidboxapp.com/terms.html\nPolítica de privacidad: https://kidboxapp.com/privacy.html",
)

L["fr-FR"] = dict(
 open="""« Qui récupère Marco jeudi ? » Avec KidBox, la famille s'organise d'un appui : vous demandez, et celui qui peut répond « Je m'en occupe », même sans l'app.

{{D'autres apps se souviennent de vous. KidBox se souvient de la famille : calendrier||KidBox est l'agent de votre famille : calendrier}}, tâches, courses, dépenses, documents et santé au même endroit, avec un assistant qui connaît {{tout ce que vous y mettez et remarque ce qui reste sans personne. Un seul||tout ce que vous y mettez. Un seul}} abonnement pour toute la famille, sans limite de membres.""",
 blocks=[
 ("DEMANDEZ À LA FAMILLE", "Depuis l'éditeur de tâches, demandez à un ou plusieurs proches, ou à quelqu'un qui n'a pas KidBox (grands-parents, baby-sitter) avec un lien à ouvrir dans le navigateur. Le premier qui répond « Je m'en occupe » {{prend la tâche, créée à son nom.||prend la tâche, et la tâche est créée à son nom.}}"),
 ("IL S'EN APERÇOIT AVANT VOUS (PRO ET MAX)", "Une tâche bientôt due sans personne, une dose du jour non enregistrée : KidBox vous prévient. Dans la notification : « Je m'en occupe » ou « Demander aux autres » pour la tâche, « Prise » pour la dose. Avec « Demander aux autres à ma place », 12 h avant l'échéance, KidBox demande lui-même et vous dit qui s'en charge. Récap du soir, heures de silence ; sans messages IA.", "ios"),
 ("ASSISTANT IA", "Demandez : « quand est le prochain rendez-vous de Marco ? », {{« que manque-t-il sur la liste de courses ? ». Il connaît||« que manque-t-il sur la liste de courses ? », « rappelle-moi d'appeler le pédiatre demain ». Il connaît}} le calendrier, les tâches, les courses, les notes, les dépenses, les documents et la santé de chacun, {{et répond avec des liens vers le bon élément.||et répond avec des liens qui ouvrent le bon élément.}} {{Il crée événements, tâches, notes, courses et rappels.||Il crée des événements, des tâches, des notes, des articles de courses et des rappels.}} Chaque matin à 8 h, un résumé des engagements du jour et des doses à donner."),
 ("CALENDRIER ET TÂCHES", "{{Calendrier partagé avec récurrences et rappels,||Calendrier partagé avec événements récurrents et rappels,}} et les calendriers du téléphone à côté de ceux de la famille (lecture seule). Des tâches à attribuer à chacun ; un rappel urgent sonne comme un réveil."),
 ("RECHERCHER DANS KIDBOX", "Une loupe dans l'Accueil cherche dans toute l'app, directement sur le téléphone, sans IA et sans coût : dépenses, documents, notes, calendrier, tâches, santé et plus.", "ios"),
 ("SANTÉ", "Rendez-vous, examens, vaccins et traitements des enfants et des adultes, {{avec rappels d'échéances et historique de santé à portée de main.||avec des rappels d'échéances et tout l'historique de santé à portée de main.}}"),
 ("COURSES ET DÉPENSES", "{{Liste de courses partagée en temps réel : quand l'un coche, l'autre le voit aussitôt.||Liste de courses partagée et mise à jour en temps réel : quand l'un la coche, l'autre le voit aussitôt.}} Dictez courses et tâches à Alexa : « Alexa, demande à mio box d'ajouter du lait ». Dépenses par catégorie, avec tickets et photos joints."),
 ("{{DOCUMENTS BIEN RANGÉS||DOCUMENTS}}", "{{Donnez à l'assistant, avec le « + », la photo d'une facture, d'un compte rendu ou d'une ordonnance : KidBox la range à sa place. La facture va dans Maison, le compte rendu dans une consultation, les analyses dans un examen, l'ordonnance dans un traitement, fichier joint. Vous confirmez. Le tout chiffré.||Comptes rendus, ordonnances, certificats et photos dans une archive chiffrée avec une clé qui reste dans la famille. Importez une facture, une ordonnance ou un compte rendu : KidBox le lit et propose les bonnes actions (ajouter la dépense, créer l'événement, enregistrer la visite, programmer le rappel). Vous choisissez ce qu'il faut confirmer, d'un appui.}}"),
 ("ACTUALITÉS (PRO ET MAX)", "Chaque jour, les actualités utiles à votre famille, de votre pays à votre ville, chacune avec sa source. Les événements proches s'ajoutent au calendrier d'un appui."),
 ("ET AUSSI", "Mots de passe de famille chiffrés, avec saisie automatique et codes OTP · Wallet pour billets, cartes et cartes de paiement · Position en temps réel · Animaux · {{Maison et garage avec échéances et interventions||Maison et garage avec échéances et historique des interventions}} · Voyages avec itinéraire IA · Visibilité sélective : toute la famille, certains membres ou vous seul · Plusieurs familles dans une seule app.\\n§Ouvrez l'appareil photo de KidBox depuis le Centre de contrôle sans ouvrir l'app.§ios"),
 ],
 plans="""FORMULES
- Free : calendrier, tâches, courses, dépenses, documents et santé, 200 Mo, 5 messages IA d'essai (une seule fois)
- Pro (4,99 €/mois ou 39,99 €/an) : 5 Go, 30 messages IA par jour (100/mois), plans repas et fitness, voyages avec IA, {{Actualités, alertes proactives||Actualités}}
- Max (9,99 €/mois ou 79,99 €/an) : 20 Go, 100 messages IA par jour (200/mois)
Vous pouvez essayer le Pro pendant 14 jours depuis l'app. Un seul abonnement pour toute la famille, sans limite de membres. Renouvellement automatique ; gestion et résiliation depuis votre identifiant Apple.""",
 legal_ios="Confidentialité : https://kidboxapp.com/privacy.html\nConditions : https://kidboxapp.com/terms.html",
 legal_mac="Conditions (EULA) : https://kidboxapp.com/terms.html\nConfidentialité : https://kidboxapp.com/privacy.html",
)

def pick(text, platform):
    """{{testo iOS||testo Mac}}: le frasi che sul Mac non valgono (avvisi proattivi, 2.4.2)."""
    import re
    return re.sub(r"\{\{(.*?)\|\|(.*?)\}\}", lambda m: m.group(1) if platform == "ios" else m.group(2), text, flags=re.S)


def build(lang, platform):
    d = L[lang]
    parts = [pick(d["open"], platform)]
    for b in d["blocks"]:
        title, body = b[0], b[1]
        only = b[2] if len(b) > 2 else None
        if only == "ios" and platform != "ios":
            continue
        if "§" in body:  # riga facoltativa solo iOS dentro al blocco
            main, extra = body.split("\\n§", 1)
            line, tag = extra.rsplit("§", 1)
            body = main + ("\n" + line if (tag == "ios" and platform == "ios") else "")
        parts.append(pick(f"{title}\n{body}", platform))
    parts.append("— — —\n" + pick(d["plans"], platform))
    parts.append(d["legal_ios"] if platform == "ios" else d["legal_mac"])
    return "\n\n".join(parts) + "\n"

for lang in L:
    for platform in ("ios", "mac"):
        text = build(lang, platform)
        n = len(text.strip())
        assert n <= 4000, (lang, platform, n)
        open(f"appstore-{platform}-{lang}.txt", "w").write(text)
        print(lang, platform, n)
