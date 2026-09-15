/*
 * «Chiedi a KidBox»: la chat sul prodotto della landing.
 *
 * Tre livelli, dal più economico (vedi `functions/landingChat/index.js`):
 *   1. domande suggerite con risposta scritta qui, nelle quattro lingue: zero
 *      token. Il server riceve solo un contatore;
 *   2. una domanda breve scritta a mano che corrisponde con sicurezza a una di
 *      quelle (parole chiave) riceve la stessa risposta scritta: zero token;
 *   3. tutto il resto va a `/api/chat` (rewrite di Hosting sulla function), che
 *      prima prova la sua cache e solo dopo chiama il modello.
 * Le domande sui prezzi non hanno una risposta scritta qui: il listino si
 * cambia dalla console, e il server lo legge vivo. La risposta del server però
 * resta in cache, quindi il chip «Quanto costa?» costa un modello a settimana.
 *
 * Nessun cookie; in sessionStorage restano la conversazione (per ritrovarla
 * cambiando pagina) e un id di sessione casuale, usato solo per il limite di
 * domande. Gli eventi GA4 partono solo se il visitatore ha già acconsentito
 * (`window.__kbGaLoaded`, vedi consent.js).
 *
 * Uso: <script src="/assets/chat.js" defer></script>
 */
(function () {
  "use strict";

  var ENDPOINT = "/api/chat";
  var MAX_CHARS = 300;
  // Domande suggerite visibili per volta: le prime della lista non ancora
  // fatte, così ogni chip toccato lascia il posto al successivo e ne restano
  // sempre cinque finché la lista non si esaurisce. L'ordine della lista è
  // quindi una priorità: prima le domande che si fanno più spesso.
  var CHIPS_SHOWN = 5;
  var STORE_KEY = "kidbox:landingChat";
  var lang = (document.documentElement.lang || "it").slice(0, 2);
  if (["it", "en", "es", "fr"].indexOf(lang) < 0) lang = "en";

  var PAGES = {
    it: { guide: "/guide", support: "/support", privacy: "/privacy" },
    en: { guide: "/guide-en", support: "/support-en", privacy: "/privacy-en" },
    es: { guide: "/guide-es", support: "/support-es", privacy: "/privacy-es" },
    fr: { guide: "/guide-fr", support: "/support-fr", privacy: "/privacy-fr" },
  }[lang];

  /*
   * Testi e risposte scritte. `triggers`: frammenti (minuscoli, senza accenti)
   * che, in una domanda breve, bastano a dire di cosa si parla. `ask: true`:
   * la risposta la dà il server (dati vivi), il chip manda il testo come domanda.
   * Le risposte seguono `functions/landingChat/knowledge.md`: se cambia quello,
   * si rileggono anche queste.
   */
  var I18N = {
    it: {
      fab: "Chiedi a KidBox",
      more: "Altre domande",
      title: "Chiedi a KidBox",
      subtitle: "Risposte automatiche sul prodotto · possono sbagliare",
      hello: "Ciao! Chiedimi qualunque cosa su KidBox: cosa fa, quanto costa, come funziona con l'altro genitore. Oppure parti da qui:",
      placeholder: "Scrivi una domanda…",
      send: "Invia",
      close: "Chiudi",
      reset: "Nuova conversazione",
      thinking: "Sto scrivendo…",
      tooLong: "Massimo " + MAX_CHARS + " caratteri.",
      limit: "Hai fatto parecchie domande! Il modo migliore per scoprire il resto è provarla: è gratuita, [si scarica qui](/scarica) oppure si apre subito dal browser con la [web app](https://app.kidboxapp.com). Se hai già l'app e qualcosa non va, in **Impostazioni → Supporto** trovi un assistente dedicato.",
      unavailable: "In questo momento non riesco a rispondere. Intanto trovi tutto nella [guida](" + PAGES.guide + ") e nella pagina [supporto](" + PAGES.support + "), oppure scrivi a passboxcontact@gmail.com.",
      faq: [
        { id: "what", q: "Cos'è KidBox?", triggers: ["cos e kidbox", "che cos e", "cosa fa kidbox", "a cosa serve"],
          a: "KidBox è l'app che mette in un unico posto l'organizzazione della famiglia: **salute dei figli**, calendario, to-do, lista della spesa, spese, documenti, foto, password, posizione, casa, auto e animali. Tutto è **condiviso in tempo reale** con l'altro genitore e con chi inviti, e un **assistente AI** conosce questi dati e ti aiuta a gestirli. È gratuita: [scaricala qui](/scarica) o provala subito dalla [web app](https://app.kidboxapp.com)." },
        { id: "price", q: "Quanto costa?", ask: true, triggers: ["quanto costa", "prezz", "costo", "abbonament", "e gratis", "gratuit", "pro e max", "piano pro", "piano max"] },
        { id: "platforms", q: "Funziona su Android e dal computer?", triggers: ["android", "iphone", "ipad", "mac", "computer", "browser", "web app", "webapp", "windows"],
          a: "Sì. KidBox c'è per **iPhone, iPad e Mac** sull'App Store, per **Android** su Google Play, e come **web app** che si apre dal browser su qualunque computer: [app.kidboxapp.com](https://app.kidboxapp.com). L'account e i dati sono gli stessi ovunque, sincronizzati in tempo reale. [Scaricala qui](/scarica)." },
        { id: "invite", q: "Come invito l'altro genitore?", triggers: ["invit", "altro genitore", "partner", "mio marito", "mia moglie", "compagn", "nonni"],
          a: "Dall'app crei la famiglia e condividi un **link di invito** (per esempio su WhatsApp) oppure fai inquadrare un **codice QR**. Chi apre il link entra nella famiglia e da quel momento vede calendario, spesa, salute e tutto quello che condividete. **Non c'è limite di membri** su nessun piano, anche su quello gratuito." },
        { id: "privacy", q: "I miei dati sono al sicuro?", triggers: ["sicur", "privacy", "cifrat", "crittograf", "end to end"],
          a: "I contenuti più delicati — **documenti, note, password, wallet, chat, foto e video** — sono cifrati con una chiave che hanno solo i membri della tua famiglia: sul server restano illeggibili. La chat è cifrata end-to-end. I dati non vengono venduti. Tutti i dettagli nella [privacy](" + PAGES.privacy + ")." },
        { id: "ai_free", q: "L'assistente AI è incluso gratis?", triggers: ["ai gratis", "ai gratuit", "intelligenza artificiale", "messaggi ai", "assistente ai", "chatgpt"],
          a: "Sul piano gratuito hai **alcuni messaggi AI di prova, una tantum**, per vedere come funziona. Con **Pro e Max** i messaggi si rinnovano **ogni giorno** e si sbloccano anche Piano Alimentare, Piano Fitness e i viaggi pianificati dall'AI. Il contatore è unico per tutta la famiglia." },
        { id: "separated", q: "Va bene per genitori separati?", triggers: ["separat", "divorzi", "affido", "ex marito", "ex moglie"],
          a: "Sì, è uno dei casi per cui KidBox è nata: calendario dei figli, **visite e documenti sanitari**, spese e cose da fare condivisi in un posto neutro, senza passare dalle chat. Con la **visibilità selettiva** scegli per note, liste, calendario, documenti e wallet chi vede cosa. Ne parliamo anche nel [blog](/blog/genitori-separati)." },
        { id: "support", q: "Ho già l'app e ho un problema", triggers: ["non riesco", "errore", "bug", "non funziona", "non mi fa", "accedere", "login", "rimborso"],
          a: "Mi dispiace! Nell'app c'è un **supporto con un assistente AI dedicato**, gratuito anche sul piano Free: vai in **Impostazioni → Supporto**, descrivi il problema e allega fino a 5 screenshot; se serve apre un ticket al team. Se non riesci proprio a entrare nell'app, scrivi a **passboxcontact@gmail.com**." },
        { id: "health", q: "Cosa registro per la salute dei figli?", triggers: ["salute", "vaccin", "visite", "pediatra", "farmac", "refert"],
          a: "Per ogni figlio (e per gli adulti) registri **visite, esami, vaccini e farmaci in corso**, con referti allegati in PDF o foto, e ricevi promemoria per le scadenze e le dosi. L'AI genera una **cartella clinica** riepilogativa da mostrare al medico e spiega esami e referti in linguaggio semplice (informativa: non sostituisce il pediatra). Su iPhone legge anche Apple Salute, su Android Health Connect." },
        { id: "ai_what", q: "Cosa fa l'assistente AI?", triggers: ["cosa fa l ai", "cosa fa l assistente", "come funziona l ai", "come funziona l assistente", "cosa sa fare", "cosa puo fare"],
          a: "È una chat che conosce i dati della tua famiglia — calendario, to-do, spesa, spese, salute, viaggi, casa, auto, animali — e risponde a domande come «quando è la prossima visita di Marco?» o «quanto abbiamo speso a maggio?». Può anche **agire**: creare eventi, to-do, articoli della spesa e spese. Ogni mattina prepara un **briefing** con gli impegni del giorno e le dosi da somministrare." },
        { id: "docintel", q: "Posso importare fatture e referti?", triggers: ["fattur", "scontrin", "importa", "scansion", "fotografare"],
          a: "Sì: importi una fattura, una ricetta, un referto o qualsiasi documento (PDF o foto) e l'AI lo legge e **propone le azioni giuste** — aggiungere la spesa, creare l'evento in calendario, registrare la visita, impostare il promemoria del vaccino. Tu scegli cosa confermare. Il documento finisce nell'archivio cifrato, con cartelle e categorie." },
        { id: "location", q: "Posso vedere dove sono i miei familiari?", triggers: ["posizion", "dove sono", "dove si trova", "localizz", "gps", "geofenc"],
          a: "Sì, se loro scelgono di condividerla: la **posizione in tempo reale** si attiva solo per chi lo decide, mai di nascosto. Puoi creare **zone** (casa, scuola, palestra) con avvisi di arrivo e uscita, e condivisioni temporanee che scadono da sole." },
        { id: "offline", q: "Funziona senza connessione?", triggers: ["offline", "senza connessione", "senza internet", "senza rete"],
          a: "Le app per iPhone, iPad, Mac e Android conservano i dati anche sul dispositivo: quello che è già stato sincronizzato si consulta anche **offline**. Per ricevere e inviare aggiornamenti alla famiglia serve la rete. La web app, invece, funziona solo con la connessione." },
        { id: "cancel", q: "Posso disdire quando voglio?", triggers: ["disdi", "annull", "disattiv", "rinnov", "vincol"],
          a: "Sì. L'abbonamento si acquista dall'app (App Store o Google Play), si rinnova ogni mese e si **annulla in qualunque momento** dalle impostazioni del tuo account Apple o Google Play: resta attivo fino alla fine del mese già pagato. È **per famiglia**: un solo abbonamento copre tutti i membri. Il piano Free, invece, non scade mai." },
        { id: "multi_family", q: "Posso far parte di più famiglie?", triggers: ["piu famiglie", "due famiglie", "seconda famiglia", "famiglia di origine", "cambiare famiglia"],
          a: "Sì. Un account può appartenere a **più famiglie** — per esempio la famiglia di origine e il tuo nucleo attuale — e passare dall'una all'altra. Ogni famiglia ha i propri bambini, dati, viaggi e impostazioni, completamente separati." },
        { id: "alexa", q: "Funziona con Alexa?", triggers: ["alexa", "echo", "a voce", "dettare", "siri", "google assistant"],
          a: "Sì, in italiano: con la skill Alexa detti la lista della spesa e i to-do agli Echo — «Alexa, chiedi a mio box di aggiungere il latte» — e compaiono subito nell'app di tutta la famiglia. Siri e Google Assistant non sono supportati." },
        { id: "kids_use", q: "La usano anche i bambini?", triggers: ["la usano i bambini", "per i bambini", "per i figli", "eta minima", "profilo del figlio"],
          a: "No: KidBox la usano i **genitori e gli adulti** della famiglia (anche nonni o baby-sitter, se li inviti). I figli hanno un **profilo** con salute, documenti, calendario e tutto quello che li riguarda, ma non un accesso. Non è un'app di controllo parentale." },
      ],
    },
    en: {
      fab: "Ask KidBox",
      more: "More questions",
      title: "Ask KidBox",
      subtitle: "Automatic answers about the app · they can be wrong",
      hello: "Hi! Ask me anything about KidBox: what it does, what it costs, how it works with the other parent. Or start here:",
      placeholder: "Type a question…",
      send: "Send",
      close: "Close",
      reset: "New conversation",
      thinking: "Typing…",
      tooLong: "Up to " + MAX_CHARS + " characters.",
      limit: "That's a lot of questions! The best way to discover the rest is to try it: it's free, [download it here](/scarica) or open it right away in your browser with the [web app](https://app.kidboxapp.com). If you already have the app and something's wrong, **Settings → Help & Support** has a dedicated assistant.",
      unavailable: "I can't answer right now. Meanwhile you'll find everything in the [guide](" + PAGES.guide + ") and on the [support](" + PAGES.support + ") page, or write to passboxcontact@gmail.com.",
      faq: [
        { id: "what", q: "What is KidBox?", triggers: ["what is kidbox", "what does kidbox", "what is it for"],
          a: "KidBox is the app that brings your family's organisation into one place: **kids' health**, calendar, to-dos, shopping list, expenses, documents, photos, passwords, location, home, car and pets. Everything is **shared in real time** with the other parent and anyone you invite, and an **AI assistant** knows this data and helps you manage it. It's free: [download it here](/scarica) or try the [web app](https://app.kidboxapp.com) now." },
        { id: "price", q: "How much does it cost?", ask: true, triggers: ["how much", "price", "pricing", "cost", "subscription", "is it free", "pro plan", "max plan"] },
        { id: "platforms", q: "Does it work on Android and computers?", triggers: ["android", "iphone", "ipad", "mac", "computer", "browser", "web app", "webapp", "windows", "laptop"],
          a: "Yes. KidBox is available for **iPhone, iPad and Mac** on the App Store, for **Android** on Google Play, and as a **web app** you open in any browser: [app.kidboxapp.com](https://app.kidboxapp.com). Same account and same data everywhere, synced in real time. [Download it here](/scarica)." },
        { id: "invite", q: "How do I invite the other parent?", triggers: ["invit", "other parent", "partner", "my husband", "my wife", "grandparents"],
          a: "In the app you create your family and share an **invite link** (on WhatsApp, for example) or let them scan a **QR code**. Whoever opens the link joins the family and from then on sees the calendar, shopping list, health records and everything you share. There's **no member limit** on any plan, including the free one." },
        { id: "privacy", q: "Is my data safe?", triggers: ["safe", "secure", "security", "privacy", "encrypt", "end to end"],
          a: "The most sensitive content — **documents, notes, passwords, wallet, chat, photos and videos** — is encrypted with a key only your family members have: on the server it stays unreadable. The chat is end-to-end encrypted. Your data is never sold. Full details in the [privacy policy](" + PAGES.privacy + ")." },
        { id: "ai_free", q: "Is the AI assistant included for free?", triggers: ["ai free", "free ai", "artificial intelligence", "ai messages", "ai assistant", "chatgpt"],
          a: "On the free plan you get **a few trial AI messages, one time only**, to see how it works. With **Pro and Max** messages renew **every day**, and you also unlock the Meal Plan, the Fitness Plan and AI-planned trips. The counter is shared by the whole family." },
        { id: "separated", q: "Does it work for separated parents?", triggers: ["separated", "divorce", "co parent", "coparent", "custody", "my ex"],
          a: "Yes, it's one of the reasons KidBox exists: the kids' calendar, **medical visits and documents**, expenses and to-dos shared in a neutral place, away from chat threads. With **selective visibility** you choose who sees each note, list, event, document or wallet item." },
        { id: "support", q: "I already have the app and something's wrong", triggers: ["can t log", "cannot log", "error", "bug", "not working", "doesn t work", "login", "sign in", "refund"],
          a: "Sorry about that! The app has a **support chat with a dedicated AI assistant**, free on every plan: go to **Settings → Help & Support**, describe the problem and attach up to 5 screenshots; if needed it opens a ticket with the team. If you can't get into the app at all, write to **passboxcontact@gmail.com**." },
        { id: "health", q: "What can I track about my kids' health?", triggers: ["health", "vaccin", "doctor", "pediatric", "medic", "prescription"],
          a: "For each child (and each adult) you record **visits, tests, vaccinations and ongoing medications**, with reports attached as PDF or photo, and get reminders for due dates and doses. The AI builds a summary **medical record** to show your doctor and explains tests and reports in plain language (informational: it doesn't replace your pediatrician). On iPhone it also reads Apple Health, on Android Health Connect." },
        { id: "ai_what", q: "What does the AI assistant do?", triggers: ["what does the ai", "what does the assistant", "how does the ai", "how does the assistant", "what can the ai", "what can the assistant"],
          a: "It's a chat that knows your family's data — calendar, to-dos, shopping list, expenses, health, trips, home, cars, pets — and answers questions like \"when is Mark's next appointment?\" or \"how much did we spend in May?\". It can also **act**: create events, to-dos, shopping items and expenses. Every morning it prepares a **briefing** with the day's commitments and the doses to give." },
        { id: "docintel", q: "Can I import invoices and medical reports?", triggers: ["invoice", "receipt", "import", "scan", "photograph"],
          a: "Yes: import an invoice, a prescription, a medical report or any document (PDF or photo) and the AI reads it and **suggests the right actions** — add the expense, create the calendar event, log the visit, set the vaccine reminder. You choose what to confirm. The document lands in the encrypted archive, with folders and categories." },
        { id: "location", q: "Can I see where my family members are?", triggers: ["location", "where is", "where are", "track", "gps", "geofenc"],
          a: "Yes, if they choose to share it: **real-time location** is only on for those who opt in, never hidden. You can create **zones** (home, school, gym) with arrival and departure alerts, and temporary shares that expire on their own." },
        { id: "offline", q: "Does it work offline?", triggers: ["offline", "no connection", "without internet", "no internet", "no signal"],
          a: "The iPhone, iPad, Mac and Android apps keep the data on the device too: whatever has already synced can be read **offline**. Sending and receiving updates from the family needs a connection. The web app only works online." },
        { id: "cancel", q: "Can I cancel anytime?", triggers: ["cancel", "unsubscribe", "renew", "commitment", "contract"],
          a: "Yes. The subscription is bought in the app (App Store or Google Play), renews monthly and can be **cancelled at any time** from your Apple or Google Play account settings: it stays active until the end of the month you've already paid. It's **per family**: one subscription covers every member. The Free plan never expires." },
        { id: "multi_family", q: "Can I belong to more than one family?", triggers: ["more than one family", "two families", "second family", "multiple families", "switch famil"],
          a: "Yes. One account can belong to **several families** — say, the family you grew up in and your current household — and switch between them. Each family has its own children, data, trips and settings, completely separate." },
        { id: "kids_use", q: "Do the kids use it too?", triggers: ["kids use", "children use", "for kids", "for children", "minimum age", "child profile"],
          a: "No: KidBox is used by the **parents and adults** of the family (grandparents or babysitters too, if you invite them). Children have a **profile** with their health, documents, calendar and everything about them, but no login. It's not a parental-control app." },
      ],
    },
    es: {
      fab: "Pregunta a KidBox",
      more: "Otras preguntas",
      title: "Pregunta a KidBox",
      subtitle: "Respuestas automáticas sobre la app · pueden equivocarse",
      hello: "¡Hola! Pregúntame lo que quieras sobre KidBox: qué hace, cuánto cuesta, cómo funciona con el otro progenitor. O empieza por aquí:",
      placeholder: "Escribe una pregunta…",
      send: "Enviar",
      close: "Cerrar",
      reset: "Nueva conversación",
      thinking: "Escribiendo…",
      tooLong: "Máximo " + MAX_CHARS + " caracteres.",
      limit: "¡Has hecho muchas preguntas! La mejor forma de descubrir el resto es probarla: es gratis, [descárgala aquí](/scarica) o ábrela ya en el navegador con la [web app](https://app.kidboxapp.com). Si ya tienes la app y algo falla, en **Ajustes → Ayuda y soporte** hay un asistente dedicado.",
      unavailable: "Ahora mismo no puedo responder. Mientras tanto lo tienes todo en la [guía](" + PAGES.guide + ") y en la página de [soporte](" + PAGES.support + "), o escribe a passboxcontact@gmail.com.",
      faq: [
        { id: "what", q: "¿Qué es KidBox?", triggers: ["que es kidbox", "que hace kidbox", "para que sirve"],
          a: "KidBox es la app que reúne en un solo lugar la organización de la familia: **salud de los hijos**, calendario, tareas, lista de la compra, gastos, documentos, fotos, contraseñas, ubicación, casa, coche y mascotas. Todo se **comparte en tiempo real** con el otro progenitor y con quien invites, y un **asistente de IA** conoce estos datos y te ayuda a gestionarlos. Es gratis: [descárgala aquí](/scarica) o pruébala ya con la [web app](https://app.kidboxapp.com)." },
        { id: "price", q: "¿Cuánto cuesta?", ask: true, triggers: ["cuanto cuesta", "precio", "coste", "costo", "suscripcion", "es gratis", "plan pro", "plan max"] },
        { id: "platforms", q: "¿Funciona en Android y en el ordenador?", triggers: ["android", "iphone", "ipad", "mac", "ordenador", "computador", "navegador", "web app", "webapp", "windows"],
          a: "Sí. KidBox está para **iPhone, iPad y Mac** en el App Store, para **Android** en Google Play, y como **web app** que se abre en cualquier navegador: [app.kidboxapp.com](https://app.kidboxapp.com). La misma cuenta y los mismos datos en todas partes, sincronizados en tiempo real. [Descárgala aquí](/scarica)." },
        { id: "invite", q: "¿Cómo invito al otro progenitor?", triggers: ["invit", "otro progenitor", "pareja", "mi marido", "mi mujer", "abuelos"],
          a: "En la app creas tu familia y compartes un **enlace de invitación** (por WhatsApp, por ejemplo) o dejas que escaneen un **código QR**. Quien abre el enlace entra en la familia y desde entonces ve el calendario, la compra, la salud y todo lo que compartís. **No hay límite de miembros** en ningún plan, tampoco en el gratuito." },
        { id: "privacy", q: "¿Mis datos están seguros?", triggers: ["segur", "privacidad", "cifrad", "encriptad", "end to end"],
          a: "El contenido más delicado — **documentos, notas, contraseñas, wallet, chat, fotos y vídeos** — se cifra con una clave que solo tienen los miembros de tu familia: en el servidor es ilegible. El chat está cifrado de extremo a extremo. Tus datos no se venden. Todos los detalles en la [privacidad](" + PAGES.privacy + ")." },
        { id: "ai_free", q: "¿El asistente de IA está incluido gratis?", triggers: ["ia gratis", "inteligencia artificial", "mensajes de ia", "asistente de ia", "chatgpt"],
          a: "En el plan gratuito tienes **algunos mensajes de IA de prueba, una sola vez**, para ver cómo funciona. Con **Pro y Max** los mensajes se renuevan **cada día** y además se desbloquean el Plan de Alimentación, el Plan de Fitness y los viajes planificados con IA. El contador es único para toda la familia." },
        { id: "separated", q: "¿Sirve para padres separados?", triggers: ["separad", "divorci", "custodia", "mi ex"],
          a: "Sí, es uno de los motivos por los que existe KidBox: el calendario de los hijos, **visitas y documentos médicos**, gastos y tareas compartidos en un lugar neutral, fuera de los chats. Con la **visibilidad selectiva** eliges quién ve cada nota, lista, evento, documento o elemento del wallet." },
        { id: "support", q: "Ya tengo la app y tengo un problema", triggers: ["no puedo", "error", "bug", "no funciona", "iniciar sesion", "acceder", "reembolso"],
          a: "¡Lo siento! La app tiene un **soporte con un asistente de IA dedicado**, gratis en todos los planes: ve a **Ajustes → Ayuda y soporte**, describe el problema y adjunta hasta 5 capturas; si hace falta abre un ticket al equipo. Si no consigues entrar en la app, escribe a **passboxcontact@gmail.com**." },
        { id: "health", q: "¿Qué puedo registrar sobre la salud de mis hijos?", triggers: ["salud", "vacun", "pediatra", "medic", "receta", "informe"],
          a: "Para cada hijo (y cada adulto) registras **visitas, pruebas, vacunas y medicamentos en curso**, con informes adjuntos en PDF o foto, y recibes recordatorios de citas y dosis. La IA genera un **historial clínico** resumido para enseñar al médico y explica pruebas e informes en lenguaje sencillo (informativo: no sustituye al pediatra). En iPhone lee también Apple Salud, en Android Health Connect." },
        { id: "ai_what", q: "¿Qué hace el asistente de IA?", triggers: ["que hace la ia", "que hace el asistente", "como funciona la ia", "como funciona el asistente", "que puede hacer", "que sabe hacer"],
          a: "Es un chat que conoce los datos de tu familia — calendario, tareas, compra, gastos, salud, viajes, casa, coches, mascotas — y responde a preguntas como «¿cuándo es la próxima cita de Marcos?» o «¿cuánto gastamos en mayo?». También puede **actuar**: crear eventos, tareas, artículos de la compra y gastos. Cada mañana prepara un **resumen** con los compromisos del día y las dosis que hay que dar." },
        { id: "docintel", q: "¿Puedo importar facturas e informes médicos?", triggers: ["factur", "ticket", "importar", "escanear", "fotografiar"],
          a: "Sí: importas una factura, una receta, un informe médico o cualquier documento (PDF o foto) y la IA lo lee y **propone las acciones adecuadas** — añadir el gasto, crear el evento en el calendario, registrar la visita, poner el recordatorio de la vacuna. Tú eliges qué confirmar. El documento queda en el archivo cifrado, con carpetas y categorías." },
        { id: "location", q: "¿Puedo ver dónde están mis familiares?", triggers: ["ubicacion", "donde esta", "donde estan", "localiz", "gps", "geofenc"],
          a: "Sí, si ellos deciden compartirla: la **ubicación en tiempo real** solo se activa para quien lo elige, nunca a escondidas. Puedes crear **zonas** (casa, colegio, gimnasio) con avisos de llegada y salida, y compartir de forma temporal, con caducidad automática." },
        { id: "offline", q: "¿Funciona sin conexión?", triggers: ["offline", "sin conexion", "sin internet", "sin red", "sin cobertura"],
          a: "Las apps para iPhone, iPad, Mac y Android guardan los datos también en el dispositivo: lo que ya se ha sincronizado se consulta **sin conexión**. Para enviar y recibir actualizaciones de la familia hace falta red. La web app solo funciona con conexión." },
        { id: "cancel", q: "¿Puedo cancelar cuando quiera?", triggers: ["cancel", "darme de baja", "baja", "renov", "permanencia"],
          a: "Sí. La suscripción se compra desde la app (App Store o Google Play), se renueva cada mes y se **cancela en cualquier momento** desde los ajustes de tu cuenta de Apple o de Google Play: sigue activa hasta el final del mes ya pagado. Es **por familia**: una sola suscripción cubre a todos los miembros. El plan gratuito, en cambio, no caduca nunca." },
        { id: "multi_family", q: "¿Puedo pertenecer a más de una familia?", triggers: ["mas de una familia", "dos familias", "segunda familia", "varias familias", "cambiar de familia"],
          a: "Sí. Una cuenta puede pertenecer a **varias familias** — por ejemplo, tu familia de origen y tu hogar actual — y cambiar de una a otra. Cada familia tiene sus propios hijos, datos, viajes y ajustes, completamente separados." },
        { id: "kids_use", q: "¿La usan también los niños?", triggers: ["la usan los ninos", "para los ninos", "para los hijos", "edad minima", "perfil del hijo"],
          a: "No: KidBox la usan los **padres y los adultos** de la familia (también abuelos o canguros, si los invitas). Los hijos tienen un **perfil** con su salud, documentos, calendario y todo lo que les concierne, pero no un acceso. No es una app de control parental." },
      ],
    },
    fr: {
      fab: "Demander à KidBox",
      more: "Autres questions",
      title: "Demander à KidBox",
      subtitle: "Réponses automatiques sur l'app · elles peuvent se tromper",
      hello: "Bonjour ! Posez-moi vos questions sur KidBox : ce qu'elle fait, combien elle coûte, comment elle marche avec l'autre parent. Ou commencez ici :",
      placeholder: "Écrivez une question…",
      send: "Envoyer",
      close: "Fermer",
      reset: "Nouvelle conversation",
      thinking: "En train d'écrire…",
      tooLong: "" + MAX_CHARS + " caractères maximum.",
      limit: "Vous avez posé beaucoup de questions ! Le mieux pour découvrir le reste, c'est d'essayer : c'est gratuit, [téléchargez-la ici](/scarica) ou ouvrez-la tout de suite dans le navigateur avec la [web app](https://app.kidboxapp.com). Si vous avez déjà l'app et que quelque chose ne va pas, **Réglages → Aide et assistance** propose un assistant dédié.",
      unavailable: "Je ne peux pas répondre pour le moment. En attendant, tout est dans le [guide](" + PAGES.guide + ") et sur la page [assistance](" + PAGES.support + "), ou écrivez à passboxcontact@gmail.com.",
      faq: [
        { id: "what", q: "Qu'est-ce que KidBox ?", triggers: ["qu est ce que kidbox", "que fait kidbox", "a quoi sert"],
          a: "KidBox est l'app qui réunit au même endroit l'organisation de la famille : **santé des enfants**, calendrier, tâches, liste de courses, dépenses, documents, photos, mots de passe, localisation, maison, voiture et animaux. Tout est **partagé en temps réel** avec l'autre parent et les personnes que vous invitez, et un **assistant IA** connaît ces données et vous aide à les gérer. Elle est gratuite : [téléchargez-la ici](/scarica) ou essayez tout de suite la [web app](https://app.kidboxapp.com)." },
        { id: "price", q: "Combien ça coûte ?", ask: true, triggers: ["combien", "prix", "tarif", "cout", "abonnement", "c est gratuit", "offre pro", "offre max"] },
        { id: "platforms", q: "Ça marche sur Android et sur ordinateur ?", triggers: ["android", "iphone", "ipad", "mac", "ordinateur", "navigateur", "web app", "webapp", "windows", "pc"],
          a: "Oui. KidBox existe pour **iPhone, iPad et Mac** sur l'App Store, pour **Android** sur Google Play, et en **web app** qui s'ouvre dans n'importe quel navigateur : [app.kidboxapp.com](https://app.kidboxapp.com). Même compte et mêmes données partout, synchronisés en temps réel. [Téléchargez-la ici](/scarica)." },
        { id: "invite", q: "Comment inviter l'autre parent ?", triggers: ["invit", "autre parent", "conjoint", "mon mari", "ma femme", "grands parents"],
          a: "Dans l'app, vous créez votre famille et partagez un **lien d'invitation** (sur WhatsApp, par exemple) ou faites scanner un **code QR**. La personne qui ouvre le lien rejoint la famille et voit dès lors le calendrier, les courses, la santé et tout ce que vous partagez. **Aucune limite de membres**, sur aucune offre, même la gratuite." },
        { id: "privacy", q: "Mes données sont-elles en sécurité ?", triggers: ["securit", "confidentialit", "chiffr", "crypt", "end to end", "de bout en bout"],
          a: "Les contenus les plus sensibles — **documents, notes, mots de passe, wallet, chat, photos et vidéos** — sont chiffrés avec une clé que seuls les membres de votre famille possèdent : sur le serveur, ils restent illisibles. Le chat est chiffré de bout en bout. Vos données ne sont pas vendues. Tous les détails dans la [politique de confidentialité](" + PAGES.privacy + ")." },
        { id: "ai_free", q: "L'assistant IA est-il inclus gratuitement ?", triggers: ["ia gratuit", "intelligence artificielle", "messages ia", "assistant ia", "chatgpt"],
          a: "Avec l'offre gratuite, vous avez **quelques messages IA d'essai, une seule fois**, pour voir comment ça marche. Avec **Pro et Max**, les messages se renouvellent **chaque jour** et vous débloquez aussi le Plan alimentaire, le Plan fitness et les voyages planifiés par l'IA. Le compteur est commun à toute la famille." },
        { id: "separated", q: "Ça convient aux parents séparés ?", triggers: ["separe", "divorc", "garde alternee", "mon ex"],
          a: "Oui, c'est l'une des raisons d'être de KidBox : le calendrier des enfants, **les rendez-vous et documents médicaux**, les dépenses et les tâches partagés dans un espace neutre, loin des fils de discussion. Avec la **visibilité sélective**, vous choisissez qui voit chaque note, liste, événement, document ou élément du wallet." },
        { id: "support", q: "J'ai déjà l'app et j'ai un problème", triggers: ["je n arrive pas", "erreur", "bug", "ne marche pas", "ne fonctionne pas", "connexion", "se connecter", "rembours"],
          a: "Désolé ! L'app propose une **assistance avec un assistant IA dédié**, gratuite sur toutes les offres : allez dans **Réglages → Aide et assistance**, décrivez le problème et joignez jusqu'à 5 captures d'écran ; si besoin, il ouvre un ticket auprès de l'équipe. Si vous n'arrivez pas du tout à entrer dans l'app, écrivez à **passboxcontact@gmail.com**." },
        { id: "health", q: "Que puis-je enregistrer sur la santé des enfants ?", triggers: ["sante", "vaccin", "pediatre", "medic", "ordonnance", "compte rendu"],
          a: "Pour chaque enfant (et chaque adulte), vous enregistrez **rendez-vous, examens, vaccins et traitements en cours**, avec les comptes rendus joints en PDF ou en photo, et recevez des rappels pour les échéances et les doses. L'IA génère un **dossier médical** récapitulatif à montrer au médecin et explique examens et résultats en langage simple (informatif : il ne remplace pas le pédiatre). Sur iPhone, elle lit aussi Apple Santé ; sur Android, Health Connect." },
        { id: "ai_what", q: "Que fait l'assistant IA ?", triggers: ["que fait l ia", "que fait l assistant", "comment marche l ia", "comment marche l assistant", "comment fonctionne l ia", "que peut faire"],
          a: "C'est un chat qui connaît les données de votre famille — calendrier, tâches, courses, dépenses, santé, voyages, maison, voitures, animaux — et répond à des questions comme « quand est le prochain rendez-vous de Marc ? » ou « combien avons-nous dépensé en mai ? ». Il peut aussi **agir** : créer des événements, des tâches, des articles de courses et des dépenses. Chaque matin, il prépare un **briefing** avec les engagements du jour et les doses à donner." },
        { id: "docintel", q: "Puis-je importer des factures et des comptes rendus ?", triggers: ["factur", "ticket de caisse", "importer", "scanner", "photographier"],
          a: "Oui : importez une facture, une ordonnance, un compte rendu ou n'importe quel document (PDF ou photo), l'IA le lit et **propose les bonnes actions** — ajouter la dépense, créer l'événement dans le calendrier, enregistrer le rendez-vous, programmer le rappel du vaccin. Vous choisissez ce que vous confirmez. Le document rejoint l'archive chiffrée, avec dossiers et catégories." },
        { id: "location", q: "Puis-je voir où sont les membres de ma famille ?", triggers: ["localisation", "position", "ou est", "ou sont", "gps", "geofenc"],
          a: "Oui, s'ils choisissent de la partager : la **localisation en temps réel** ne s'active que pour ceux qui le décident, jamais en cachette. Vous pouvez créer des **zones** (maison, école, salle de sport) avec des alertes d'arrivée et de départ, et des partages temporaires qui expirent tout seuls." },
        { id: "offline", q: "Ça marche sans connexion ?", triggers: ["hors ligne", "sans connexion", "sans internet", "sans reseau"],
          a: "Les apps iPhone, iPad, Mac et Android conservent aussi les données sur l'appareil : ce qui a déjà été synchronisé se consulte **hors ligne**. Pour envoyer et recevoir les mises à jour de la famille, il faut le réseau. La web app, elle, ne fonctionne qu'en ligne." },
        { id: "cancel", q: "Puis-je résilier quand je veux ?", triggers: ["resili", "annul", "desabonn", "renouvel", "engagement"],
          a: "Oui. L'abonnement s'achète dans l'app (App Store ou Google Play), se renouvelle chaque mois et se **résilie à tout moment** depuis les réglages de votre compte Apple ou Google Play : il reste actif jusqu'à la fin du mois déjà payé. Il est **par famille** : un seul abonnement couvre tous les membres. L'offre gratuite, elle, n'expire jamais." },
        { id: "multi_family", q: "Puis-je faire partie de plusieurs familles ?", triggers: ["plusieurs familles", "deux familles", "seconde famille", "deuxieme famille", "changer de famille"],
          a: "Oui. Un compte peut appartenir à **plusieurs familles** — par exemple votre famille d'origine et votre foyer actuel — et passer de l'une à l'autre. Chaque famille a ses propres enfants, données, voyages et réglages, complètement séparés." },
        { id: "kids_use", q: "Les enfants l'utilisent aussi ?", triggers: ["les enfants l utilisent", "pour les enfants", "age minimum", "profil de l enfant"],
          a: "Non : KidBox est utilisée par les **parents et les adultes** de la famille (grands-parents ou baby-sitters aussi, si vous les invitez). Les enfants ont un **profil** avec leur santé, leurs documents, leur calendrier et tout ce qui les concerne, mais pas d'accès. Ce n'est pas une app de contrôle parental." },
      ],
    },
  };
  var T = I18N[lang];

  // ── Stato ────────────────────────────────────────────────────────────────

  var state = load() || { sessionId: newSessionId(), messages: [] };
  var busy = false;
  var openedOnce = false;

  function newSessionId() {
    var bytes = new Uint8Array(12);
    (window.crypto || window.msCrypto).getRandomValues(bytes);
    return Array.prototype.map.call(bytes, function (b) {
      return ("0" + b.toString(16)).slice(-2);
    }).join("");
  }

  function load() {
    try {
      var raw = sessionStorage.getItem(STORE_KEY);
      var parsed = raw && JSON.parse(raw);
      if (parsed && parsed.sessionId && Array.isArray(parsed.messages)) return parsed;
    } catch (e) {}
    return null;
  }

  function save() {
    try { sessionStorage.setItem(STORE_KEY, JSON.stringify(state)); } catch (e) {}
  }

  function track(name, params) {
    if (window.__kbGaLoaded && window.gtag) window.gtag("event", name, params || {});
  }

  function post(body, beacon) {
    body.lang = lang;
    var json = JSON.stringify(body);
    if (beacon && navigator.sendBeacon) {
      navigator.sendBeacon(ENDPOINT, new Blob([json], { type: "text/plain" }));
      return Promise.resolve(null);
    }
    return fetch(ENDPOINT, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: json,
    }).then(function (r) {
      return r.status === 204 ? null : r.json();
    });
  }

  // ── Testo ────────────────────────────────────────────────────────────────

  function normalize(s) {
    return String(s).toLowerCase()
      .normalize("NFD").replace(/[̀-ͯ]/g, "")
      .replace(/[^a-z0-9\s]/g, " ")
      .replace(/\s+/g, " ").trim();
  }

  /**
   * FAQ a cui corrisponde con sicurezza una domanda scritta a mano, o null.
   * Solo domande brevi: in una frase lunga una parola chiave dice poco, e una
   * risposta giusta ma fuori tema è peggio di una chiamata al modello. Due FAQ
   * con lo stesso punteggio → nessuna.
   */
  function matchFaq(question) {
    var text = " " + normalize(question) + " ";
    if (text.trim().split(" ").length > 8) return null;
    var best = null, bestScore = 0, tie = false;
    T.faq.forEach(function (f) {
      var score = 0;
      f.triggers.forEach(function (t) { if (text.indexOf(t) >= 0) score++; });
      if (score > bestScore) { best = f; bestScore = score; tie = false; }
      else if (score && score === bestScore) tie = true;
    });
    return bestScore && !tie ? best : null;
  }

  function escapeHtml(s) {
    return String(s).replace(/&/g, "&amp;").replace(/</g, "&lt;")
      .replace(/>/g, "&gt;").replace(/"/g, "&quot;");
  }

  /** Link ammessi nelle risposte: il sito, la web app, la mail di supporto. */
  function safeHref(url) {
    if (/^\/[^/]/.test(url) || url === "/") return url;
    if (/^https:\/\/(www\.|app\.)?kidboxapp\.com(\/|$)/.test(url)) return url;
    // Store: solo le schede di KidBox. Un modello può scrivere un id sbagliato.
    if (/^https:\/\/apps\.apple\.com\/.*id6761055375(\D|$)/.test(url)) return url;
    if (/^https:\/\/play\.google\.com\/store\/apps\/details\?id=it\.vittorioscocca\.kidbox(&|$)/.test(url)) return url;
    return null;
  }

  /** Markdown minimo e sicuro: si esegue l'escape prima di tutto. */
  function render(md) {
    var lines = escapeHtml(md).split(/\n/);
    var html = "", inList = false;
    lines.forEach(function (line) {
      var item = /^\s*[-•]\s+(.*)$/.exec(line);
      if (item) {
        if (!inList) { html += "<ul>"; inList = true; }
        html += "<li>" + inline(item[1]) + "</li>";
        return;
      }
      if (inList) { html += "</ul>"; inList = false; }
      if (line.trim()) html += "<p>" + inline(line) + "</p>";
    });
    if (inList) html += "</ul>";
    return html;
  }

  function inline(s) {
    return s
      .replace(/\*\*(.+?)\*\*/g, "<strong>$1</strong>")
      .replace(/\[([^\]]+)\]\(([^)\s]+)\)/g, function (m, label, url) {
        var href = safeHref(url.replace(/&amp;/g, "&"));
        if (!href) return label;
        // kidboxapp.com resta nella scheda: è lo stesso sito.
        var external = /^https?:/.test(href) && !/^https:\/\/(www\.)?kidboxapp\.com(\/|$)/.test(href);
        return '<a href="' + escapeHtml(href) + '"' +
          (external ? ' target="_blank" rel="noopener"' : "") + ">" + label + "</a>";
      })
      // Indirizzi scritti nudi: diventano link solo se ammessi da safeHref.
      .replace(/(^|[\s(])(https:\/\/[^\s<)]+?)([.,;:!?]?)(?=$|[\s)<])/g, function (m, pre, url, punct) {
        var href = safeHref(url.replace(/&amp;/g, "&"));
        if (!href) return m;
        return pre + '<a href="' + escapeHtml(href) + '" target="_blank" rel="noopener">' + url + "</a>" + punct;
      })
      .replace(/\b(passboxcontact@gmail\.com)\b/g, '<a href="mailto:$1">$1</a>');
  }

  // ── Interfaccia ──────────────────────────────────────────────────────────

  var CSS =
    ".kbc-fab{position:fixed;right:20px;bottom:20px;z-index:9000;display:inline-flex;align-items:center;gap:8px;height:52px;padding:0 20px 0 16px;border:none;border-radius:999px;background:linear-gradient(135deg,var(--accent,var(--c-accent,#e8833a)),var(--accent2,var(--c-accent2,#c96a20)));color:#fff;font:inherit;font-size:.95rem;font-weight:700;cursor:pointer;box-shadow:0 10px 30px rgba(180,90,20,.35);transition:transform .15s ease,box-shadow .15s ease}" +
    ".kbc-fab:hover{transform:translateY(-2px);box-shadow:0 14px 34px rgba(180,90,20,.42)}" +
    ".kbc-fab svg{width:22px;height:22px;flex:none}" +
    "body:has(.kb-consent:not([hidden])) .kbc-fab{display:none}" +
    ".kbc-panel{position:fixed;right:20px;bottom:20px;z-index:9001;width:min(400px,calc(100vw - 32px));height:min(620px,calc(100dvh - 40px));display:flex;flex-direction:column;border:1px solid var(--border,var(--c-border,rgba(180,120,60,.14)));border-radius:22px;background:var(--surface,var(--c-surface,#fff));color:var(--text,var(--c-text,#1c1008));box-shadow:0 24px 70px rgba(0,0,0,.25);overflow:hidden;font-family:inherit}" +
    ".kbc-panel[hidden]{display:none}" +
    ".kbc-head{display:flex;align-items:center;gap:10px;padding:14px 14px 12px 16px;border-bottom:1px solid var(--border,var(--c-border,rgba(180,120,60,.14)))}" +
    ".kbc-head img{width:34px;height:34px;border-radius:9px;flex:none}" +
    ".kbc-head-text{flex:1;min-width:0}" +
    ".kbc-head strong{display:block;font-size:.98rem;line-height:1.2}" +
    ".kbc-head small{display:block;font-size:.72rem;color:var(--muted,var(--c-muted,rgba(28,16,8,.52)));line-height:1.3}" +
    ".kbc-icon{border:none;background:transparent;color:var(--muted,var(--c-muted,rgba(28,16,8,.52)));width:34px;height:34px;border-radius:10px;font-size:1rem;cursor:pointer;flex:none}" +
    ".kbc-icon:hover{background:var(--bg2,var(--c-bg2,rgba(0,0,0,.06)));color:var(--text,var(--c-text,#1c1008))}" +
    ".kbc-log{flex:1;overflow-y:auto;padding:16px;display:flex;flex-direction:column;gap:10px;overscroll-behavior:contain}" +
    ".kbc-msg{max-width:88%;padding:10px 13px;border-radius:16px;font-size:.9rem;line-height:1.5;overflow-wrap:anywhere}" +
    ".kbc-msg p{margin:0}.kbc-msg p+p,.kbc-msg p+ul,.kbc-msg ul+p{margin-top:6px}" +
    ".kbc-msg ul{margin:4px 0 0;padding-left:18px}" +
    ".kbc-msg a{color:inherit;text-decoration:underline;font-weight:600}" +
    ".kbc-bot{align-self:flex-start;background:var(--bg2,var(--c-bg2,#f5ebe0));border-bottom-left-radius:6px}" +
    ".kbc-user{align-self:flex-end;background:var(--accent,var(--c-accent,#e8833a));color:#fff;border-bottom-right-radius:6px}" +
    ".kbc-pending{color:var(--muted,var(--c-muted,rgba(28,16,8,.52)));font-style:italic}" +
    ".kbc-more{align-self:flex-start;max-width:92%;display:flex;flex-direction:column;gap:4px;margin-top:2px}" +
    ".kbc-more>span{font-size:.72rem;font-weight:600;color:var(--muted,var(--c-muted,rgba(28,16,8,.52)));padding-left:2px}" +
    ".kbc-chips{display:flex;flex-wrap:wrap;gap:6px;margin-top:2px}" +
    ".kbc-chip{border:1px solid var(--border,var(--c-border,rgba(180,120,60,.2)));background:var(--surface,var(--c-surface,#fff));color:var(--text,var(--c-text,#1c1008));border-radius:999px;padding:6px 11px;font:inherit;font-size:.8rem;cursor:pointer;text-align:left}" +
    ".kbc-chip:hover{border-color:var(--accent,var(--c-accent,#e8833a));color:var(--accent2,var(--c-accent2,#c96a20))}" +
    ".kbc-form{display:flex;gap:8px;align-items:flex-end;padding:10px 12px 12px;border-top:1px solid var(--border,var(--c-border,rgba(180,120,60,.14)))}" +
    ".kbc-form textarea{flex:1;resize:none;min-height:42px;max-height:110px;padding:10px 12px;border:1px solid var(--border,var(--c-border,rgba(180,120,60,.2)));border-radius:14px;background:var(--bg,var(--c-bg,#fdf7f0));color:var(--text,var(--c-text,#1c1008));font:inherit;font-size:.9rem;line-height:1.35}" +
    ".kbc-form textarea:focus{outline:2px solid var(--accent,var(--c-accent,#e8833a));outline-offset:-1px}" +
    ".kbc-send{height:42px;padding:0 16px;border:none;border-radius:14px;background:var(--accent,var(--c-accent,#e8833a));color:#fff;font:inherit;font-weight:700;font-size:.88rem;cursor:pointer}" +
    ".kbc-send:disabled{opacity:.45;cursor:default}" +
    ".kbc-hint{padding:0 14px 8px;font-size:.72rem;color:#c0392b}" +
    ".kbc-hint[hidden]{display:none}" +
    "@media (max-width:520px){.kbc-fab{right:14px;bottom:14px;height:48px;padding:0 16px 0 13px;font-size:.9rem}" +
    ".kbc-panel{right:0;bottom:0;width:100vw;height:100dvh;border-radius:0;border:none}}";

  var ICON =
    '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">' +
    '<path d="M21 12a8 8 0 0 1-11.6 7.1L4 20.5l1.4-4.9A8 8 0 1 1 21 12Z"/><path d="M9 10.5h.01M12 10.5h.01M15 10.5h.01"/></svg>';

  var fab, panel, log, input, sendBtn, hint;

  function build() {
    var style = document.createElement("style");
    style.textContent = CSS;
    document.head.appendChild(style);

    fab = document.createElement("button");
    fab.type = "button";
    fab.className = "kbc-fab";
    fab.innerHTML = ICON + "<span></span>";
    fab.querySelector("span").textContent = T.fab;
    fab.setAttribute("aria-haspopup", "dialog");
    fab.onclick = openPanel;

    panel = document.createElement("section");
    panel.className = "kbc-panel";
    panel.hidden = true;
    panel.setAttribute("role", "dialog");
    panel.setAttribute("aria-label", T.title);
    panel.innerHTML =
      '<header class="kbc-head"><img src="/icon.png" alt="">' +
      '<div class="kbc-head-text"><strong></strong><small></small></div>' +
      '<button type="button" class="kbc-icon" data-reset>↺</button>' +
      '<button type="button" class="kbc-icon" data-close>✕</button></header>' +
      '<div class="kbc-log" aria-live="polite"></div>' +
      '<p class="kbc-hint" hidden></p>' +
      '<form class="kbc-form"><textarea rows="1"></textarea>' +
      '<button type="submit" class="kbc-send"></button></form>';
    panel.querySelector("strong").textContent = T.title;
    panel.querySelector("small").textContent = T.subtitle;
    var resetBtn = panel.querySelector("[data-reset]");
    resetBtn.title = T.reset;
    resetBtn.setAttribute("aria-label", T.reset);
    resetBtn.onclick = resetConversation;
    var closeBtn = panel.querySelector("[data-close]");
    closeBtn.title = T.close;
    closeBtn.setAttribute("aria-label", T.close);
    closeBtn.onclick = closePanel;
    log = panel.querySelector(".kbc-log");
    hint = panel.querySelector(".kbc-hint");
    input = panel.querySelector("textarea");
    input.placeholder = T.placeholder;
    input.maxLength = MAX_CHARS;
    sendBtn = panel.querySelector(".kbc-send");
    sendBtn.textContent = T.send;

    panel.querySelector("form").onsubmit = function (e) {
      e.preventDefault();
      submitTyped();
    };
    input.addEventListener("keydown", function (e) {
      if (e.key === "Enter" && !e.shiftKey) {
        e.preventDefault();
        submitTyped();
      }
    });
    input.addEventListener("input", function () {
      input.style.height = "auto";
      input.style.height = Math.min(input.scrollHeight, 110) + "px";
      hint.hidden = true;
    });
    document.addEventListener("keydown", function (e) {
      if (e.key === "Escape" && !panel.hidden) closePanel();
    });

    document.body.appendChild(fab);
    document.body.appendChild(panel);
  }

  function openPanel() {
    panel.hidden = false;
    fab.hidden = true;
    renderLog();
    input.focus();
    if (!openedOnce) {
      openedOnce = true;
      post({ action: "open" }, true);
      track("landing_chat_open");
    }
  }

  function closePanel() {
    panel.hidden = true;
    fab.hidden = false;
    fab.focus();
  }

  function resetConversation() {
    state = { sessionId: state.sessionId, messages: [] };
    save();
    renderLog();
    input.focus();
  }

  function bubble(role, html, extraClass) {
    var el = document.createElement("div");
    el.className = "kbc-msg " + (role === "user" ? "kbc-user" : "kbc-bot") + (extraClass ? " " + extraClass : "");
    if (role === "user") el.textContent = html;
    else el.innerHTML = html;
    log.appendChild(el);
    return el;
  }

  /** Le prime CHIPS_SHOWN domande suggerite non ancora fatte in questa conversazione. */
  function chipsFor(container) {
    var asked = {};
    state.messages.forEach(function (m) { if (m.role === "user") asked[m.content] = true; });
    var left = T.faq.filter(function (f) { return !asked[f.q]; }).slice(0, CHIPS_SHOWN);
    if (!left.length) return null;
    var chips = document.createElement("div");
    chips.className = "kbc-chips";
    left.forEach(function (f) {
      var chip = document.createElement("button");
      chip.type = "button";
      chip.className = "kbc-chip";
      chip.textContent = f.q;
      chip.onclick = function () { askFaq(f, null); };
      chips.appendChild(chip);
    });
    container.appendChild(chips);
    return chips;
  }

  function renderLog() {
    log.innerHTML = "";
    var hello = bubble("assistant", render(T.hello));
    if (!state.messages.length) chipsFor(hello);
    var lastQuestion = null;
    state.messages.forEach(function (m) {
      var el = bubble(m.role, m.role === "user" ? m.content : render(m.content));
      if (m.role === "user") lastQuestion = el;
    });
    if (busy) {
      bubble("assistant", escapeHtml(T.thinking), "kbc-pending");
    } else if (state.messages.length && state.messages[state.messages.length - 1].role === "assistant") {
      // Dopo ogni risposta si ripropongono le domande suggerite rimaste: senza,
      // la sola strada visibile è scrivere, cioè il modello, che costa. Chi
      // tocca un chip riceve una risposta scritta, a zero token.
      var more = document.createElement("div");
      more.className = "kbc-more";
      var label = document.createElement("span");
      label.textContent = T.more;
      more.appendChild(label);
      if (chipsFor(more)) log.appendChild(more);
    }
    // Da vuota si legge il saluto; in attesa si va in fondo, dove c'è «Sto
    // scrivendo…». Con la risposta arrivata, invece, si porta in cima l'ultima
    // domanda: la risposta si legge dall'inizio e i chip restano sotto, da
    // scoprire scorrendo, invece di spingerla fuori dalla vista.
    if (!state.messages.length) log.scrollTop = 0;
    else if (busy || !lastQuestion) log.scrollTop = log.scrollHeight;
    else {
      log.scrollTop = log.scrollHeight;
      log.scrollTop += lastQuestion.getBoundingClientRect().top - log.getBoundingClientRect().top - 12;
    }
  }

  function push(role, content) {
    state.messages.push({ role: role, content: content });
    // Nel browser basta la coda: al server ne arrivano comunque due scambi.
    if (state.messages.length > 20) state.messages = state.messages.slice(-20);
    save();
  }

  function submitTyped() {
    var text = input.value.trim();
    if (!text || busy) return;
    if (text.length > MAX_CHARS) {
      hint.textContent = T.tooLong;
      hint.hidden = false;
      return;
    }
    input.value = "";
    input.style.height = "auto";
    // Solo come prima domanda: dopo, una frase breve dipende da ciò che c'è prima.
    var faq = state.messages.length === 0 ? matchFaq(text) : null;
    if (faq) askFaq(faq, text);
    else askServer(text, text);
  }

  /**
   * @param faq   la FAQ
   * @param typed il testo scritto dal visitatore, se è arrivato dalla ricerca
   *              locale; null se ha toccato il chip
   */
  function askFaq(faq, typed) {
    if (busy) return;
    if (faq.ask) {
      // I prezzi li dà il server, che legge il listino vivo. Il chip manda il
      // testo canonico, così tutti i tocchi leggono la stessa voce in cache;
      // una domanda scritta va com'è, perché «costo del viaggio?» non è il listino.
      askServer(typed || faq.q, typed || faq.q);
      return;
    }
    push("user", typed || faq.q);
    push("assistant", faq.a);
    renderLog();
    var body = { action: "faq", id: faq.id };
    if (typed) { body.match = true; body.question = typed; }
    post(body, true);
    track("landing_chat_question", { source: typed ? "faq_match" : "faq_chip", faq_id: faq.id });
  }

  function askServer(shown, sent) {
    var history = state.messages.slice();
    push("user", shown);
    busy = true;
    sendBtn.disabled = true;
    renderLog();
    post({
      action: "ask",
      sessionId: state.sessionId,
      question: sent,
      history: history,
    }).then(function (res) {
      if (res && res.answer) {
        push("assistant", res.answer);
        track("landing_chat_question", { source: res.source || "llm" });
      } else {
        var reason = res && res.fallback;
        push("assistant", reason === "session_limit" || reason === "ip_limit" ? T.limit : T.unavailable);
        track("landing_chat_question", { source: "fallback_" + (reason || "error") });
      }
    }).catch(function () {
      push("assistant", T.unavailable);
    }).then(function () {
      busy = false;
      sendBtn.disabled = false;
      renderLog();
    });
  }

  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", build);
  else build();
})();
