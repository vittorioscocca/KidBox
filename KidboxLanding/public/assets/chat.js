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
 * cambia dalla console, e la scrive il server (`action: "price"`) leggendo il
 * documento vivo, senza modello.
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
   * la risposta la scrive il server dal listino vivo (`action: "price"`).
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
        { id: "invite", q: "Come invito l'altro genitore?", triggers: ["invit", "altro genitore", "partner", "mio marito", "mia moglie", "compagn"],
          a: "Dall'app crei la famiglia e condividi un **link di invito** (per esempio su WhatsApp) oppure fai inquadrare un **codice QR**. Chi apre il link entra nella famiglia e da quel momento vede calendario, spesa, salute e tutto quello che condividete. **Non c'è limite di membri** su nessun piano, anche su quello gratuito." },
        { id: "privacy", q: "I miei dati sono al sicuro?", triggers: ["sicur", "privacy", "cifrat", "crittograf", "end to end"],
          a: "I contenuti più delicati — **documenti, note, password, wallet, chat, foto e video** — sono cifrati con una chiave che hanno solo i membri della tua famiglia: sul server restano illeggibili. La chat è cifrata end-to-end. I dati non vengono venduti. Tutti i dettagli nella [privacy](" + PAGES.privacy + ")." },
        { id: "ai_free", q: "L'assistente AI è incluso gratis?", triggers: ["ai gratis", "ai gratuit", "intelligenza artificiale", "messaggi ai", "assistente ai", "incluso", "chatgpt"],
          a: "Sul piano gratuito hai **alcuni messaggi AI di prova, una tantum**, per vedere come funziona. Con **Pro e Max** i messaggi si rinnovano **ogni giorno** e si sbloccano anche Piano Alimentare, Piano Fitness e i viaggi pianificati dall'AI. Il contatore è unico per tutta la famiglia." },
        { id: "separated", q: "Va bene per genitori separati?", triggers: ["separat", "divorzi", "affido", "ex marito", "ex moglie"],
          a: "Sì, è uno dei casi per cui KidBox è nata: calendario dei figli, **visite e documenti sanitari**, spese e cose da fare condivisi in un posto neutro, senza passare dalle chat. Con la **visibilità selettiva** scegli per note, liste, calendario, documenti e wallet chi vede cosa. Ne parliamo anche nel [blog](/blog/genitori-separati)." },
        { id: "support", q: "Ho già l'app e ho un problema", triggers: ["non riesco", "errore", "bug", "non funziona", "non mi fa", "accedere", "login", "rimborso"],
          a: "Mi dispiace! Nell'app c'è un **supporto con un assistente AI dedicato**, gratuito anche sul piano Free: vai in **Impostazioni → Supporto**, descrivi il problema e allega fino a 5 screenshot; se serve apre un ticket al team. Se non riesci proprio a entrare nell'app, scrivi a **passboxcontact@gmail.com**." },
        { id: "health", q: "Cosa registro per la salute dei figli?", triggers: ["salute", "vaccin", "visite", "pediatra", "farmac", "refert"],
          a: "Per ogni figlio (e per gli adulti) registri **visite, esami, vaccini e farmaci in corso**, con referti allegati in PDF o foto, e ricevi promemoria per le scadenze e le dosi. L'AI genera una **cartella clinica** riepilogativa da mostrare al medico e spiega esami e referti in linguaggio semplice (informativa: non sostituisce il pediatra). Su iPhone legge anche Apple Salute, su Android Health Connect." },
        { id: "ai_what", q: "Cosa fa l'assistente AI?", triggers: ["cosa fa l", "come funziona l ai", "come funziona l assistente", "cosa sa fare", "cosa puo fare", "assistente ai"],
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
        { id: "kids_use", q: "La usano anche i bambini?", triggers: ["usano", "bambini", "per i figli", "eta minima", "profilo del figlio"],
          a: "No: KidBox la usano i **genitori e gli adulti** della famiglia (anche nonni o baby-sitter, se li inviti). I figli hanno un **profilo** con salute, documenti, calendario e tutto quello che li riguarda, ma non un accesso. Non è un'app di controllo parentale." },
        { id: "calendar", q: "C'è un calendario condiviso?", triggers: ["calendario", "agenda", "appuntament", "eventi"],
          a: "Sì: un **calendario di famiglia** con viste mese, settimana e giorno, e eventi con luogo, partecipanti, promemoria e ripetizioni. Le visite mediche registrate in Salute compaiono da sole anche in calendario, e l'assistente AI può creare eventi per te a parole." },
        { id: "todo", q: "Posso assegnare cose da fare all'altro genitore?", triggers: ["to do", "todo", "cose da fare", "assegn", "incaric", "compiti"],
          a: "Sì. Le **liste di cose da fare** sono condivise con la famiglia e ogni attività si può **assegnare a un membro**, che riceve una notifica, con scadenza e promemoria. In italiano le puoi dettare anche ad Alexa." },
        { id: "shopping", q: "Come funziona la lista della spesa?", triggers: ["lista della spesa", "spesa condivisa", "supermercato", "fare la spesa"],
          a: "È condivisa e aggiornata **in tempo reale**: quando uno aggiunge o spunta un articolo, l'altro lo vede subito, e si vede chi l'ha aggiunto e quando. In italiano si può dettare ad Alexa («Alexa, chiedi a mio box di aggiungere il latte») e l'assistente AI può aggiungere articoli a parole." },
        { id: "expenses", q: "Posso tenere traccia delle spese?", triggers: ["spese", "budget", "bilancio", "quanto abbiamo speso", "contabilit"],
          a: "Sì: spese di famiglia **per categoria**, con scontrini e foto allegati e riepiloghi per mese. Alcune nascono da sole: se in un'altra sezione inserisci un costo (una visita, un tagliando dell'auto, una bolletta di casa), KidBox crea la voce in Spese senza doverla scrivere due volte. All'AI puoi chiedere «quanto abbiamo speso a maggio?»." },
        { id: "documents", q: "Dove archivio i documenti?", triggers: ["documenti", "archivio", "certificat", "contratt", "pdf"],
          a: "In **Documenti**: un archivio cifrato con cartelle e categorie per referti, ricette, certificati, contratti e ricevute, con import di PDF e foto. Gli allegati delle altre sezioni (visite, veicoli, casa, animali) finiscono lì automaticamente. Sul server restano illeggibili: la chiave ce l'ha solo la tua famiglia." },
        { id: "wallet", q: "Cos'è il Wallet?", triggers: ["wallet", "bigliett", "carte fedelta", "carta fedelta", "codice a barre", "carta d identita"],
          a: "Il posto per **biglietti** (treni, aerei, concerti), abbonamenti, documenti d'identità e **carte fedeltà** con codice a barre, condivisi con la famiglia e cifrati. L'AI può leggere i campi di un biglietto o di un documento al posto tuo (usa i messaggi AI del piano)." },
        { id: "passwords", q: "C'è un gestore di password?", triggers: ["password", "credenzial", "otp", "autocompilazione", "autofill"],
          a: "Sì, cifrato: credenziali **condivise o personali**, codici OTP, generatore di password, controllo delle password violate e **autocompilazione** su iPhone (AutoFill, anche in Safari). Le password sono tra i contenuti cifrati con la chiave della famiglia: il server non può leggerle." },
        { id: "photos", q: "Posso condividere foto e video?", triggers: ["foto", "video", "album", "fotocamera", "immagini"],
          a: "Sì: **album di famiglia** condivisi e cifrati, per foto e video. Su iPhone c'è una scorciatoia per aprire la fotocamera di KidBox dal Centro di Controllo. Foto e video si possono aggiungere anche a un viaggio." },
        { id: "chat", q: "C'è una chat di famiglia?", triggers: ["chat", "messagg", "whatsapp", "vocal"],
          a: "Sì, una chat di famiglia **cifrata end-to-end**, con messaggi vocali, foto, documenti e galleria dei media. Per questo le notifiche non mostrano l'anteprima del contenuto: nemmeno il server può leggerlo." },
        { id: "home", q: "Posso gestire le scadenze di casa?", triggers: ["casa", "bollett", "elettrodomestic", "garanzia", "manutenzion", "tasse"],
          a: "Sì, nella sezione **Casa**: elettrodomestici e impianti con garanzia e manutenzione, più le scadenze e i pagamenti di casa — bollette, tasse, contratti. Una bolletta inserita qui diventa da sola una voce in Spese." },
        { id: "garage", q: "Mi ricorda bollo, assicurazione e revisione?", triggers: ["auto", "macchina", "veicol", "bollo", "assicurazion", "revision", "tagliando", "garage"],
          a: "Sì, nel **Garage**: una scheda per ogni veicolo con le scadenze di **bollo, assicurazione e revisione** e lo storico degli interventi (tagliando, gomme, riparazioni) con costo e ricevuta. Arriva una notifica prima di ogni scadenza, e un intervento con un costo finisce da solo in Spese." },
        { id: "pets", q: "Posso registrare anche gli animali?", triggers: ["animal", "cane", "gatto", "veterinari", "toelettatura"],
          a: "Sì: una scheda per ogni animale con dati anagrafici ed eventi sanitari — **vaccini, visite veterinarie, farmaci, toelettatura** — con promemoria. Anche l'assistente AI conosce i dati degli animali." },
        { id: "trips", q: "Come funziona la pianificazione dei viaggi?", triggers: ["viagg", "vacanz", "itinerari", "destinazion"],
          a: "Con **Pro e Max**: definisci lo stile di viaggio e l'AI suggerisce la destinazione, oppure pianifichi con una procedura guidata (luoghi, date, trasporti, chi viene, budget, alloggio). L'AI crea un **itinerario giorno per giorno** — mattina, pomeriggio, sera — con alloggi, ristoranti e tappe collegati a foto, recensioni e mappa, più una sezione «Storia e territorio». Dal viaggio aggiungi foto, note, to-do e spese." },
        { id: "meal_plan", q: "Cos'è il Piano Alimentare?", triggers: ["piano alimentare", "alimentazion", "dieta", "menu", "ricette", "pasti", "allergi"],
          a: "Un **menù settimanale** creato dall'AI in base a età, peso, obiettivi, referti e allergie di chi lo segue. È incluso nei piani **Pro e Max**; sul piano gratuito non è disponibile. Le risposte sono informative e non sostituiscono il medico o il nutrizionista." },
        { id: "fitness", q: "Cos'è il Piano Fitness?", triggers: ["fitness", "allenament", "palestra", "sport", "esercizi"],
          a: "Un **programma di allenamento** creato dall'AI, con calendario, promemoria, storico e report settimanale; le sedute si chiudono da sole leggendo Apple Salute o Health Connect. È incluso nei piani **Pro e Max**; sul piano gratuito non è disponibile." },
        { id: "monthly_analysis", q: "Cos'è l'analisi mensile?", triggers: ["analisi mensile", "pattern", "ricorren", "ogni mese"],
          a: "Ogni mese l'AI **rilegge la storia sanitaria dei figli** cercando pattern difficili da notare: ricorrenze stagionali, esami mai eseguiti, antibiotici troppo frequenti. È una funzione dei piani **Pro e Max**, informativa: non sostituisce il pediatra." },
        { id: "medical_record", q: "Cos'è la cartella clinica?", triggers: ["cartella clinica", "riepilogo sanitario", "storia sanitaria", "da mostrare al medico"],
          a: "Un **documento riepilogativo** generato dall'AI a partire da visite, esami, vaccini e farmaci registrati, da mostrare al medico. Le operazioni lunghe come questa possono contare più di un messaggio AI. Non è una cartella clinica ufficiale e l'AI non fa diagnosi." },
        { id: "health_sync", q: "Si collega ad Apple Salute o Health Connect?", triggers: ["apple salute", "health connect", "apple health", "passi", "battito", "smartwatch", "apple watch"],
          a: "Sì: su iPhone legge **Apple Salute**, su Android **Health Connect** — passi, battito, pressione, saturazione, calorie attive, allenamenti e distanza. Il Piano Fitness li usa per chiudere da solo le sedute completate. I dati di salute non vengono condivisi con terzi per pubblicità." },
        { id: "ai_proactive", q: "L'AI mi avvisa da sola?", triggers: ["briefing", "ogni mattina", "proattiv", "da sola", "riepilogo settimanale"],
          a: "Sì: una **mente proattiva** lavora senza che tu chieda nulla. Ogni mattina prepara un **briefing** con gli impegni del giorno e le dosi da somministrare, a fine settimana un riepilogo, e ogni mese (Pro e Max) un'analisi della storia sanitaria dei figli." },
        { id: "visibility", q: "Posso nascondere alcune cose all'altro genitore?", triggers: ["nasconder", "alcune cose", "non veda", "visibilit", "solo io", "privat", "chi vede"],
          a: "Sì, con la **visibilità selettiva**: per note, liste, calendario, documenti e wallet scegli chi vede ogni contenuto — tutta la famiglia, alcuni membri o solo tu. Le password possono essere condivise o personali." },
        { id: "signup", q: "Come mi registro?", triggers: ["registrarmi", "mi registro", "registrazione", "iscri", "creare l account", "creare un account", "accedi con apple", "accedi con google"],
          a: "Con **Apple, Google oppure email e password**. Con l'email devi confermare l'indirizzo dal link che arriva per posta prima di entrare; «Accedi con Apple» ti permette di tenere privata la tua email. Al primo accesso un breve percorso guidato ti fa creare la famiglia (o entrare in una esistente con un invito) e invitare l'altro genitore." },
        { id: "delete_account", q: "Posso cancellare l'account e i dati?", triggers: ["cancellare l account", "eliminare l account", "cancellare i dati", "eliminare i dati", "diritto all oblio"],
          a: "Sì, dall'app: in **Impostazioni** elimini l'account con tutti i dati personali. Le istruzioni passo passo sono su [kidboxapp.com/data-deletion](https://kidboxapp.com/data-deletion)." },
        { id: "languages", q: "In che lingue è disponibile?", triggers: ["lingu", "inglese", "spagnolo", "francese", "tradott"],
          a: "L'app è in **italiano, inglese, spagnolo e francese**, e l'assistente AI risponde nella lingua dell'utente. Solo Alexa funziona esclusivamente in italiano." },
        { id: "who_made", q: "Chi c'è dietro KidBox?", triggers: ["chi siete", "chi l ha fatta", "chi ha fatto", "chi c e dietro", "azienda", "italiana"],
          a: "KidBox è un prodotto **italiano**, fatto in Italia da un **piccolo team indipendente**. Per scriverci: passboxcontact@gmail.com, oppure dall'app in Impostazioni → Supporto." },
        { id: "web_subscription", q: "Posso abbonarmi dalla web app?", triggers: ["abbonarmi dal", "dalla web app", "pagare dal", "acquistare dal", "dal browser", "dal sito"],
          a: "No: gli abbonamenti si acquistano **solo dalle app**, con l'App Store su iPhone, iPad e Mac o con Google Play su Android. Il piano attivato vale poi per tutta la famiglia, anche sulla web app." },
        { id: "annual", q: "C'è un piano annuale o uno sconto?", triggers: ["annual", "annuo", "sconto", "promozion", "codice sconto", "coupon"],
          a: "Al momento no: i prezzi sono quelli **mensili**, senza piano annuale né sconti pubblicati. L'abbonamento si rinnova ogni mese e si annulla quando vuoi. Il piano Free, gratuito per sempre, include tutte le sezioni tranne Piano Alimentare, Piano Fitness e itinerari di viaggio con l'AI." },
        { id: "integrations", q: "Si collega alla scuola o alla banca?", triggers: ["registro elettronico", "scuola", "banca", "fascicolo sanitario", "conto corrente"],
          a: "No: KidBox **non si collega** al registro elettronico della scuola, alle banche né al Fascicolo Sanitario Elettronico. I dati li inserisci tu, anche importando documenti e foto che l'AI legge e trasforma in azioni." },
        { id: "grandparents", q: "Posso invitare i nonni o la baby-sitter?", triggers: ["nonn", "baby sitter", "babysitter", "tata", " zia ", " zio ", "zii"],
          a: "Sì: una famiglia può includere **chiunque inviti** — nonni, baby-sitter, altri adulti — senza limite di membri, su nessun piano. Con la visibilità selettiva decidi cosa vede ognuno." },
        { id: "widgets", q: "Ci sono widget per iPhone?", triggers: ["widget", "widget per iphone", "centro di controllo", "schermata di blocco", "estension", "condividi con"],
          a: "Sì: **widget**, controlli per il Centro di Controllo e la schermata di blocco, AutoFill delle password, e un'**estensione di condivisione** per mandare file a KidBox da altre app." },
        { id: "ai_privacy", q: "L'AI legge tutti i miei dati?", triggers: ["l ai legge", "l ai vede", "l ai accede", "dati all ai", "manda i dati"],
          a: "No: le funzioni AI inviano al server **solo i dati necessari a rispondere**, e **solo quando le usi**. I contenuti cifrati con la chiave della famiglia restano illeggibili sul server, e i dati non vengono venduti né condivisi con terzi per pubblicità. Tutti i dettagli nella [privacy](" + PAGES.privacy + ")." },
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
        { id: "invite", q: "How do I invite the other parent?", triggers: ["invit", "other parent", "partner", "my husband", "my wife"],
          a: "In the app you create your family and share an **invite link** (on WhatsApp, for example) or let them scan a **QR code**. Whoever opens the link joins the family and from then on sees the calendar, shopping list, health records and everything you share. There's **no member limit** on any plan, including the free one." },
        { id: "privacy", q: "Is my data safe?", triggers: ["safe", "secure", "security", "privacy", "encrypt", "end to end"],
          a: "The most sensitive content — **documents, notes, passwords, wallet, chat, photos and videos** — is encrypted with a key only your family members have: on the server it stays unreadable. The chat is end-to-end encrypted. Your data is never sold. Full details in the [privacy policy](" + PAGES.privacy + ")." },
        { id: "ai_free", q: "Is the AI assistant included for free?", triggers: ["ai free", "free ai", "artificial intelligence", "ai messages", "ai assistant", "included", "chatgpt"],
          a: "On the free plan you get **a few trial AI messages, one time only**, to see how it works. With **Pro and Max** messages renew **every day**, and you also unlock the Meal Plan, the Fitness Plan and AI-planned trips. The counter is shared by the whole family." },
        { id: "separated", q: "Does it work for separated parents?", triggers: ["separated", "divorce", "co parent", "coparent", "custody", "my ex"],
          a: "Yes, it's one of the reasons KidBox exists: the kids' calendar, **medical visits and documents**, expenses and to-dos shared in a neutral place, away from chat threads. With **selective visibility** you choose who sees each note, list, event, document or wallet item." },
        { id: "support", q: "I already have the app and something's wrong", triggers: ["can t log", "cannot log", "error", "bug", "not working", "doesn t work", "login", "sign in", "refund"],
          a: "Sorry about that! The app has a **support chat with a dedicated AI assistant**, free on every plan: go to **Settings → Help & Support**, describe the problem and attach up to 5 screenshots; if needed it opens a ticket with the team. If you can't get into the app at all, write to **passboxcontact@gmail.com**." },
        { id: "health", q: "What can I track about my kids' health?", triggers: ["health", "vaccin", "doctor", "pediatric", "medic", "prescription"],
          a: "For each child (and each adult) you record **visits, tests, vaccinations and ongoing medications**, with reports attached as PDF or photo, and get reminders for due dates and doses. The AI builds a summary **medical record** to show your doctor and explains tests and reports in plain language (informational: it doesn't replace your pediatrician). On iPhone it also reads Apple Health, on Android Health Connect." },
        { id: "ai_what", q: "What does the AI assistant do?", triggers: ["what does the", "how does the ai", "how does the assistant", "what can the ai", "what can the assistant", "ai assistant"],
          a: "It's a chat that knows your family's data — calendar, to-dos, shopping list, expenses, health, trips, home, cars, pets — and answers questions like \"when is Mark's next appointment?\" or \"how much did we spend in May?\". It can also **act**: create events, to-dos, shopping items and expenses. Every morning it prepares a **briefing** with the day's commitments and the doses to give." },
        { id: "docintel", q: "Can I import invoices and medical reports?", triggers: ["invoice", "receipt", "import", "scan", "photograph"],
          a: "Yes: import an invoice, a prescription, a medical report or any document (PDF or photo) and the AI reads it and **suggests the right actions** — add the expense, create the calendar event, log the visit, set the vaccine reminder. You choose what to confirm. The document lands in the encrypted archive, with folders and categories." },
        { id: "location", q: "Can I see where my family members are?", triggers: ["location", "where is", "where are", "where my", "tracking", "gps", "geofenc"],
          a: "Yes, if they choose to share it: **real-time location** is only on for those who opt in, never hidden. You can create **zones** (home, school, gym) with arrival and departure alerts, and temporary shares that expire on their own." },
        { id: "offline", q: "Does it work offline?", triggers: ["offline", "no connection", "without internet", "no internet", "no signal"],
          a: "The iPhone, iPad, Mac and Android apps keep the data on the device too: whatever has already synced can be read **offline**. Sending and receiving updates from the family needs a connection. The web app only works online." },
        { id: "cancel", q: "Can I cancel anytime?", triggers: ["cancel", "unsubscribe", "renew", "commitment"],
          a: "Yes. The subscription is bought in the app (App Store or Google Play), renews monthly and can be **cancelled at any time** from your Apple or Google Play account settings: it stays active until the end of the month you've already paid. It's **per family**: one subscription covers every member. The Free plan never expires." },
        { id: "multi_family", q: "Can I belong to more than one family?", triggers: ["more than one family", "two families", "second family", "multiple families", "switch famil"],
          a: "Yes. One account can belong to **several families** — say, the family you grew up in and your current household — and switch between them. Each family has its own children, data, trips and settings, completely separate." },
        { id: "kids_use", q: "Do the kids use it too?", triggers: ["kids use", "children use", "for kids", "for children", "minimum age", "child profile"],
          a: "No: KidBox is used by the **parents and adults** of the family (grandparents or babysitters too, if you invite them). Children have a **profile** with their health, documents, calendar and everything about them, but no login. It's not a parental-control app." },
        { id: "calendar", q: "Is there a shared calendar?", triggers: ["calendar", "agenda", "appointment", "events", "schedule"],
          a: "Yes: a **family calendar** with month, week and day views, and events with place, participants, reminders and repeats. Medical visits logged in Health show up in the calendar on their own, and the AI assistant can create events for you from plain words." },
        { id: "todo", q: "Can I assign tasks to the other parent?", triggers: ["to do", "todo", "task", "assign", "chores"],
          a: "Yes. **To-do lists** are shared with the family and every task can be **assigned to a member**, who gets a notification, with a due date and a reminder." },
        { id: "shopping", q: "How does the shopping list work?", triggers: ["shopping list", "grocer", "groceries", "supermarket"],
          a: "It's shared and updated **in real time**: when one of you adds or ticks off an item, the other sees it right away, along with who added it and when. The AI assistant can add items for you from plain words." },
        { id: "expenses", q: "Can I track family expenses?", triggers: ["expense", "spending", "budget", "how much did we spend", "bookkeeping"],
          a: "Yes: family expenses **by category**, with receipts and photos attached and monthly summaries. Some are created for you: if you enter a cost in another section (a medical visit, a car service, a home bill), KidBox creates the expense without you typing it twice. You can ask the AI \"how much did we spend in May?\"." },
        { id: "documents", q: "Where do I store documents?", triggers: ["document", "archive", "certificate", "contract", "pdf"],
          a: "In **Documents**: an encrypted archive with folders and categories for medical reports, prescriptions, certificates, contracts and receipts, with PDF and photo import. Attachments from other sections (visits, vehicles, home, pets) land there automatically. On the server they stay unreadable: only your family has the key." },
        { id: "wallet", q: "What is the Wallet?", triggers: ["wallet", "ticket", "loyalty", "barcode", "id card", "boarding pass"],
          a: "The place for **tickets** (trains, flights, concerts), subscriptions, ID documents and **loyalty cards** with barcode, shared with the family and encrypted. The AI can read the fields of a ticket or a document for you (it uses the plan's AI messages)." },
        { id: "passwords", q: "Is there a password manager?", triggers: ["password", "credential", "otp", "autofill", "2fa"],
          a: "Yes, encrypted: **shared or personal** credentials, OTP codes, a password generator, breached-password checks and **AutoFill** on iPhone (in Safari too). Passwords are among the content encrypted with the family key: the server can't read them." },
        { id: "photos", q: "Can I share photos and videos?", triggers: ["photo", "video", "album", "camera", "pictures"],
          a: "Yes: shared, encrypted **family albums** for photos and videos. On iPhone there's a shortcut to open KidBox's camera from Control Center. Photos and videos can also be added to a trip." },
        { id: "chat", q: "Is there a family chat?", triggers: ["chat", "messag", "whatsapp", "voice note"],
          a: "Yes, a family chat that's **end-to-end encrypted**, with voice messages, photos, documents and a media gallery. That's why notifications don't show a preview of the content: not even the server can read it." },
        { id: "home", q: "Can I manage home deadlines and bills?", triggers: ["home", "house", "bill", "appliance", "warranty", "maintenance", "taxes"],
          a: "Yes, in the **Home** section: appliances and systems with warranty and maintenance, plus the home's deadlines and payments — bills, taxes, contracts. A bill entered here becomes an expense on its own." },
        { id: "garage", q: "Does it remind me about car insurance and inspections?", triggers: ["car", "vehicle", "insurance", "inspection", "mot", "service", "garage", "tyres", "tires"],
          a: "Yes, in the **Garage**: a card for each vehicle with **tax, insurance and inspection** deadlines and the history of work done (servicing, tyres, repairs) with cost and receipt. You get a notification before each deadline, and any work with a cost lands in Expenses on its own." },
        { id: "pets", q: "Can I keep track of pets too?", triggers: ["pet", "dog", "cat", "vet", "grooming"],
          a: "Yes: a card for each pet with basic details and health events — **vaccinations, vet visits, medications, grooming** — with reminders. The AI assistant knows the pets' data too." },
        { id: "trips", q: "How does trip planning work?", triggers: ["trip", "travel", "holiday", "vacation", "itinerar", "destination"],
          a: "With **Pro and Max**: describe your travel style and the AI suggests a destination, or plan step by step (places, dates, transport, who's coming, budget, accommodation). The AI builds a **day-by-day itinerary** — morning, afternoon, evening — with stays, restaurants and stops linked to photos, reviews and a map, plus a \"History and territory\" section. From the trip you add photos, notes, to-dos and expenses." },
        { id: "meal_plan", q: "What is the Meal Plan?", triggers: ["meal plan", "diet", "menu", "recipes", "meals", "allerg", "nutrition"],
          a: "A **weekly menu** created by the AI based on the age, weight, goals, medical reports and allergies of the person following it. It's included in the **Pro and Max** plans; it's not available on the free plan. The answers are informational and don't replace a doctor or nutritionist." },
        { id: "fitness", q: "What is the Fitness Plan?", triggers: ["fitness", "workout", "training", "gym", "exercise"],
          a: "A **training programme** created by the AI, with calendar, reminders, history and a weekly report; sessions complete on their own by reading Apple Health or Health Connect. It's included in the **Pro and Max** plans; it's not available on the free plan." },
        { id: "monthly_analysis", q: "What is the monthly analysis?", triggers: ["monthly analysis", "pattern", "recurr", "every month"],
          a: "Every month the AI **re-reads your kids' health history** looking for patterns that are hard to spot: seasonal recurrences, tests never done, antibiotics taken too often. It's a **Pro and Max** feature, informational: it doesn't replace the pediatrician." },
        { id: "medical_record", q: "What is the medical record?", triggers: ["medical record", "record", "health summary", "health history", "show the doctor"],
          a: "A **summary document** generated by the AI from the visits, tests, vaccinations and medications you've logged, to show your doctor. Long operations like this one can count as more than one AI message. It's not an official medical record and the AI doesn't diagnose." },
        { id: "health_sync", q: "Does it connect to Apple Health or Health Connect?", triggers: ["apple health", "health connect", "steps", "heart rate", "smartwatch", "apple watch", "fitbit"],
          a: "Yes: on iPhone it reads **Apple Health**, on Android **Health Connect** — steps, heart rate, blood pressure, oxygen saturation, active calories, workouts and distance. The Fitness Plan uses them to complete sessions on its own. Health data is never shared with third parties for advertising." },
        { id: "ai_proactive", q: "Does the AI alert me on its own?", triggers: ["briefing", "every morning", "proactive", "on its own", "weekly summary"],
          a: "Yes: a **proactive mind** works without you asking. Every morning it prepares a **briefing** with the day's commitments and the doses to give, at the end of the week a summary, and every month (Pro and Max) an analysis of your kids' health history." },
        { id: "visibility", q: "Can I hide some things from the other parent?", triggers: ["hide", "some things", "visibility", "only me", "private", "who sees", "who can see"],
          a: "Yes, with **selective visibility**: for notes, lists, calendar, documents and wallet you choose who sees each item — the whole family, some members or only you. Passwords can be shared or personal." },
        { id: "signup", q: "How do I sign up?", triggers: ["sign up", "signup", "register", "create an account", "sign in with apple", "sign in with google"],
          a: "With **Apple, Google or email and password**. With email you confirm the address from the link you receive before getting in; \"Sign in with Apple\" lets you keep your email private. On first launch a short guided setup has you create the family (or join an existing one with an invite) and invite the other parent." },
        { id: "delete_account", q: "Can I delete my account and data?", triggers: ["delete my account", "delete account", "delete my data", "delete data", "remove my account"],
          a: "Yes, from the app: in **Settings** you delete the account with all personal data. Step-by-step instructions are at [kidboxapp.com/data-deletion](https://kidboxapp.com/data-deletion)." },
        { id: "languages", q: "Which languages is it available in?", triggers: ["language", "italian", "spanish", "french", "translat"],
          a: "The app is in **English, Italian, Spanish and French**, and the AI assistant answers in your language. Only Alexa works exclusively in Italian." },
        { id: "who_made", q: "Who is behind KidBox?", triggers: ["who are you", "who made", "who built", "who is behind", "company"],
          a: "KidBox is an **Italian** product, made in Italy by a **small independent team**. To reach us: passboxcontact@gmail.com, or from the app in Settings → Help & Support." },
        { id: "web_subscription", q: "Can I subscribe from the web app?", triggers: ["subscribe from", "from the web app", "pay from", "buy from", "from the browser", "from the website"],
          a: "No: subscriptions are bought **only in the apps**, via the App Store on iPhone, iPad and Mac or Google Play on Android. The plan then applies to the whole family, on the web app too." },
        { id: "annual", q: "Is there an annual plan or a discount?", triggers: ["annual", "yearly", "discount", "promo", "coupon", "offer"],
          a: "Not at the moment: prices are **monthly**, with no annual plan or published discounts. The subscription renews monthly and can be cancelled whenever you like. The Free plan, free forever, includes every section except the Meal Plan, the Fitness Plan and AI trip itineraries." },
        { id: "integrations", q: "Does it connect to school or bank accounts?", triggers: ["school", "bank", "health record", "bank account", "integrat"],
          a: "No: KidBox **doesn't connect** to school portals, banks or national electronic health records. You enter the data yourself, including by importing documents and photos the AI reads and turns into actions." },
        { id: "grandparents", q: "Can I invite grandparents or the babysitter?", triggers: ["grandparent", "grandma", "grandpa", "babysitter", "baby sitter", "nanny", "aunt", "uncle"],
          a: "Yes: a family can include **anyone you invite** — grandparents, babysitters, other adults — with no member limit on any plan. With selective visibility you decide what each person sees." },
        { id: "widgets", q: "Are there iPhone widgets?", triggers: ["widget", "iphone widget", "control center", "lock screen", "extension", "share sheet"],
          a: "Yes: **widgets**, Control Center and Lock Screen controls, password AutoFill, and a **share extension** to send files to KidBox from other apps." },
        { id: "ai_privacy", q: "Does the AI read all my data?", triggers: ["ai read", "ai see", "ai access", "data to the ai", "send my data"],
          a: "No: the AI features send the server **only the data needed to answer**, and **only when you use them**. Content encrypted with the family key stays unreadable on the server, and your data is never sold or shared with third parties for advertising. Full details in the [privacy policy](" + PAGES.privacy + ")." },
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
        { id: "invite", q: "¿Cómo invito al otro progenitor?", triggers: ["invit", "otro progenitor", "pareja", "mi marido", "mi mujer"],
          a: "En la app creas tu familia y compartes un **enlace de invitación** (por WhatsApp, por ejemplo) o dejas que escaneen un **código QR**. Quien abre el enlace entra en la familia y desde entonces ve el calendario, la compra, la salud y todo lo que compartís. **No hay límite de miembros** en ningún plan, tampoco en el gratuito." },
        { id: "privacy", q: "¿Mis datos están seguros?", triggers: ["segur", "privacidad", "cifrad", "encriptad", "end to end"],
          a: "El contenido más delicado — **documentos, notas, contraseñas, wallet, chat, fotos y vídeos** — se cifra con una clave que solo tienen los miembros de tu familia: en el servidor es ilegible. El chat está cifrado de extremo a extremo. Tus datos no se venden. Todos los detalles en la [privacidad](" + PAGES.privacy + ")." },
        { id: "ai_free", q: "¿El asistente de IA está incluido gratis?", triggers: ["ia gratis", "inteligencia artificial", "mensajes de ia", "asistente de ia", "incluido", "chatgpt"],
          a: "En el plan gratuito tienes **algunos mensajes de IA de prueba, una sola vez**, para ver cómo funciona. Con **Pro y Max** los mensajes se renuevan **cada día** y además se desbloquean el Plan de Alimentación, el Plan de Fitness y los viajes planificados con IA. El contador es único para toda la familia." },
        { id: "separated", q: "¿Sirve para padres separados?", triggers: ["separad", "divorci", "custodia", "mi ex"],
          a: "Sí, es uno de los motivos por los que existe KidBox: el calendario de los hijos, **visitas y documentos médicos**, gastos y tareas compartidos en un lugar neutral, fuera de los chats. Con la **visibilidad selectiva** eliges quién ve cada nota, lista, evento, documento o elemento del wallet." },
        { id: "support", q: "Ya tengo la app y tengo un problema", triggers: ["no puedo", "error", "bug", "no funciona", "iniciar sesion", "acceder", "reembolso"],
          a: "¡Lo siento! La app tiene un **soporte con un asistente de IA dedicado**, gratis en todos los planes: ve a **Ajustes → Ayuda y soporte**, describe el problema y adjunta hasta 5 capturas; si hace falta abre un ticket al equipo. Si no consigues entrar en la app, escribe a **passboxcontact@gmail.com**." },
        { id: "health", q: "¿Qué puedo registrar sobre la salud de mis hijos?", triggers: ["salud", "vacun", "pediatra", "medic", "receta"],
          a: "Para cada hijo (y cada adulto) registras **visitas, pruebas, vacunas y medicamentos en curso**, con informes adjuntos en PDF o foto, y recibes recordatorios de citas y dosis. La IA genera un **historial clínico** resumido para enseñar al médico y explica pruebas e informes en lenguaje sencillo (informativo: no sustituye al pediatra). En iPhone lee también Apple Salud, en Android Health Connect." },
        { id: "ai_what", q: "¿Qué hace el asistente de IA?", triggers: ["que hace", "como funciona la ia", "como funciona el asistente", "que puede hacer", "que sabe hacer", "asistente de ia"],
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
        { id: "kids_use", q: "¿La usan también los niños?", triggers: ["usan", "ninos", "para los hijos", "edad minima", "perfil del hijo"],
          a: "No: KidBox la usan los **padres y los adultos** de la familia (también abuelos o canguros, si los invitas). Los hijos tienen un **perfil** con su salud, documentos, calendario y todo lo que les concierne, pero no un acceso. No es una app de control parental." },
        { id: "calendar", q: "¿Hay un calendario compartido?", triggers: ["calendario", "agenda", "cita", "eventos"],
          a: "Sí: un **calendario familiar** con vistas de mes, semana y día, y eventos con lugar, participantes, recordatorios y repeticiones. Las visitas médicas registradas en Salud aparecen solas también en el calendario, y el asistente de IA puede crear eventos por ti con palabras." },
        { id: "todo", q: "¿Puedo asignar tareas al otro progenitor?", triggers: ["tareas", "pendientes", "asignar", "encargar", "to do"],
          a: "Sí. Las **listas de tareas** se comparten con la familia y cada tarea se puede **asignar a un miembro**, que recibe una notificación, con fecha límite y recordatorio." },
        { id: "shopping", q: "¿Cómo funciona la lista de la compra?", triggers: ["lista de la compra", "compra compartida", "supermercado", "hacer la compra"],
          a: "Es compartida y se actualiza **en tiempo real**: cuando uno añade o marca un artículo, el otro lo ve al momento, y se ve quién lo añadió y cuándo. El asistente de IA puede añadir artículos por ti con palabras." },
        { id: "expenses", q: "¿Puedo controlar los gastos de la familia?", triggers: ["gastos", "presupuesto", "cuanto hemos gastado", "cuentas"],
          a: "Sí: gastos familiares **por categoría**, con tickets y fotos adjuntos y resúmenes por mes. Algunos se crean solos: si en otra sección introduces un coste (una visita, una revisión del coche, una factura de casa), KidBox crea el gasto sin que lo escribas dos veces. A la IA puedes preguntarle «¿cuánto gastamos en mayo?»." },
        { id: "documents", q: "¿Dónde guardo los documentos?", triggers: ["documentos", "archivo", "certificad", "contrato", "pdf"],
          a: "En **Documentos**: un archivo cifrado con carpetas y categorías para informes, recetas, certificados, contratos y recibos, con importación de PDF y fotos. Los adjuntos de las otras secciones (visitas, vehículos, casa, mascotas) van allí automáticamente. En el servidor son ilegibles: la clave solo la tiene tu familia." },
        { id: "wallet", q: "¿Qué es el Wallet?", triggers: ["wallet", "billete", "entrada", "tarjeta de fidelidad", "codigo de barras", "dni"],
          a: "El lugar para **billetes y entradas** (trenes, vuelos, conciertos), suscripciones, documentos de identidad y **tarjetas de fidelidad** con código de barras, compartidos con la familia y cifrados. La IA puede leer los campos de un billete o un documento por ti (usa los mensajes de IA del plan)." },
        { id: "passwords", q: "¿Hay un gestor de contraseñas?", triggers: ["contrasena", "credencial", "otp", "autocompletar", "autofill"],
          a: "Sí, cifrado: credenciales **compartidas o personales**, códigos OTP, generador de contraseñas, comprobación de contraseñas filtradas y **autocompletado** en iPhone (también en Safari). Las contraseñas están entre el contenido cifrado con la clave de la familia: el servidor no puede leerlas." },
        { id: "photos", q: "¿Puedo compartir fotos y vídeos?", triggers: ["foto", "video", "album", "camara", "imagenes"],
          a: "Sí: **álbumes familiares** compartidos y cifrados, para fotos y vídeos. En iPhone hay un acceso directo para abrir la cámara de KidBox desde el Centro de control. Las fotos y los vídeos también se pueden añadir a un viaje." },
        { id: "chat", q: "¿Hay un chat familiar?", triggers: ["chat", "mensaje", "whatsapp", "nota de voz"],
          a: "Sí, un chat familiar **cifrado de extremo a extremo**, con mensajes de voz, fotos, documentos y galería de medios. Por eso las notificaciones no muestran una vista previa del contenido: ni siquiera el servidor puede leerlo." },
        { id: "home", q: "¿Puedo gestionar los vencimientos de casa?", triggers: ["casa", "factura", "electrodomestic", "garantia", "mantenimiento", "impuestos"],
          a: "Sí, en la sección **Casa**: electrodomésticos e instalaciones con garantía y mantenimiento, más los vencimientos y pagos de la casa — facturas, impuestos, contratos. Una factura introducida aquí se convierte sola en un gasto." },
        { id: "garage", q: "¿Me recuerda el seguro y la ITV del coche?", triggers: ["coche", "vehiculo", "seguro del coche", "asegur", "itv", "revision", "taller", "garaje", "neumatic"],
          a: "Sí, en el **Garaje**: una ficha por vehículo con los vencimientos de **impuesto, seguro e ITV** y el historial de intervenciones (revisiones, neumáticos, reparaciones) con coste y recibo. Recibes una notificación antes de cada vencimiento, y una intervención con coste va sola a Gastos." },
        { id: "pets", q: "¿Puedo registrar también a las mascotas?", triggers: ["mascota", "perro", "gato", "veterinari", "peluqueria canina"],
          a: "Sí: una ficha por mascota con sus datos y eventos de salud — **vacunas, visitas al veterinario, medicamentos, peluquería** — con recordatorios. El asistente de IA también conoce los datos de las mascotas." },
        { id: "trips", q: "¿Cómo funciona la planificación de viajes?", triggers: ["viaje", "vacaciones", "itinerario", "destino"],
          a: "Con **Pro y Max**: defines tu estilo de viaje y la IA sugiere el destino, o planificas paso a paso (lugares, fechas, transporte, quién viene, presupuesto, alojamiento). La IA crea un **itinerario día a día** — mañana, tarde y noche — con alojamientos, restaurantes y paradas enlazados a fotos, reseñas y mapa, más una sección «Historia y territorio». Desde el viaje añades fotos, notas, tareas y gastos." },
        { id: "meal_plan", q: "¿Qué es el Plan de Alimentación?", triggers: ["plan de alimentacion", "alimentacion", "dieta", "menu", "recetas", "comidas", "alergi"],
          a: "Un **menú semanal** creado por la IA según la edad, el peso, los objetivos, los informes médicos y las alergias de quien lo sigue. Está incluido en los planes **Pro y Max**; en el plan gratuito no está disponible. Las respuestas son informativas y no sustituyen al médico ni al nutricionista." },
        { id: "fitness", q: "¿Qué es el Plan de Fitness?", triggers: ["fitness", "entrenamiento", "gimnasio", "deporte", "ejercicio"],
          a: "Un **programa de entrenamiento** creado por la IA, con calendario, recordatorios, historial e informe semanal; las sesiones se cierran solas leyendo Apple Salud o Health Connect. Está incluido en los planes **Pro y Max**; en el plan gratuito no está disponible." },
        { id: "monthly_analysis", q: "¿Qué es el análisis mensual?", triggers: ["analisis mensual", "patron", "recurren", "cada mes"],
          a: "Cada mes la IA **relee el historial de salud de los hijos** buscando patrones difíciles de notar: recurrencias estacionales, pruebas nunca hechas, antibióticos demasiado frecuentes. Es una función de los planes **Pro y Max**, informativa: no sustituye al pediatra." },
        { id: "medical_record", q: "¿Qué es el historial clínico?", triggers: ["historial clinico", "resumen de salud", "historial de salud", "ensenar al medico"],
          a: "Un **documento resumen** generado por la IA a partir de las visitas, pruebas, vacunas y medicamentos registrados, para enseñar al médico. Las operaciones largas como esta pueden contar más de un mensaje de IA. No es un historial clínico oficial y la IA no hace diagnósticos." },
        { id: "health_sync", q: "¿Se conecta con Apple Salud o Health Connect?", triggers: ["apple salud", "health connect", "apple health", "pasos", "pulso", "smartwatch", "apple watch"],
          a: "Sí: en iPhone lee **Apple Salud**, en Android **Health Connect** — pasos, pulso, presión, saturación, calorías activas, entrenamientos y distancia. El Plan de Fitness los usa para cerrar solo las sesiones completadas. Los datos de salud no se comparten con terceros para publicidad." },
        { id: "ai_proactive", q: "¿La IA me avisa por sí sola?", triggers: ["resumen matutino", "cada manana", "proactiv", "por si sola", "resumen semanal"],
          a: "Sí: una **mente proactiva** trabaja sin que pidas nada. Cada mañana prepara un **resumen** con los compromisos del día y las dosis que hay que dar, al final de la semana un repaso, y cada mes (Pro y Max) un análisis del historial de salud de los hijos." },
        { id: "visibility", q: "¿Puedo ocultar algunas cosas al otro progenitor?", triggers: ["ocultar", "esconder", "algunas cosas", "visibilidad", "solo yo", "privad", "quien ve"],
          a: "Sí, con la **visibilidad selectiva**: en notas, listas, calendario, documentos y wallet eliges quién ve cada contenido — toda la familia, algunos miembros o solo tú. Las contraseñas pueden ser compartidas o personales." },
        { id: "signup", q: "¿Cómo me registro?", triggers: ["registrarme", "me registro", "registrarse", "crear una cuenta", "crear cuenta", "iniciar sesion con apple", "iniciar sesion con google"],
          a: "Con **Apple, Google o correo y contraseña**. Con el correo debes confirmar la dirección desde el enlace que recibes antes de entrar; «Iniciar sesión con Apple» te permite mantener privado tu correo. En el primer acceso, un breve recorrido guiado te hace crear la familia (o entrar en una existente con una invitación) e invitar al otro progenitor." },
        { id: "delete_account", q: "¿Puedo eliminar la cuenta y los datos?", triggers: ["eliminar la cuenta", "borrar la cuenta", "eliminar mis datos", "borrar mis datos", "darme de baja de la app"],
          a: "Sí, desde la app: en **Ajustes** eliminas la cuenta con todos los datos personales. Las instrucciones paso a paso están en [kidboxapp.com/data-deletion](https://kidboxapp.com/data-deletion)." },
        { id: "languages", q: "¿En qué idiomas está disponible?", triggers: ["idioma", "ingles", "italiano", "frances", "traduc"],
          a: "La app está en **español, inglés, italiano y francés**, y el asistente de IA responde en tu idioma. Solo Alexa funciona exclusivamente en italiano." },
        { id: "who_made", q: "¿Quién está detrás de KidBox?", triggers: ["quienes sois", "quien la ha hecho", "quien ha hecho", "quien esta detras", "empresa", "italiana"],
          a: "KidBox es un producto **italiano**, hecho en Italia por un **pequeño equipo independiente**. Para escribirnos: passboxcontact@gmail.com, o desde la app en Ajustes → Ayuda y soporte." },
        { id: "web_subscription", q: "¿Puedo suscribirme desde la web app?", triggers: ["suscribirme desde", "desde la web app", "pagar desde", "comprar desde", "desde el navegador"],
          a: "No: las suscripciones se compran **solo desde las apps**, con el App Store en iPhone, iPad y Mac o con Google Play en Android. El plan activado vale después para toda la familia, también en la web app." },
        { id: "annual", q: "¿Hay un plan anual o algún descuento?", triggers: ["anual", "descuento", "promocion", "cupon", "oferta"],
          a: "De momento no: los precios son **mensuales**, sin plan anual ni descuentos publicados. La suscripción se renueva cada mes y se cancela cuando quieras. El plan gratuito, gratis para siempre, incluye todas las secciones salvo el Plan de Alimentación, el Plan de Fitness y los itinerarios de viaje con IA." },
        { id: "integrations", q: "¿Se conecta con el colegio o el banco?", triggers: ["colegio", "escuela", "banco", "historia clinica electronica", "cuenta bancaria"],
          a: "No: KidBox **no se conecta** a la plataforma del colegio, a los bancos ni a la historia clínica electrónica. Los datos los introduces tú, también importando documentos y fotos que la IA lee y convierte en acciones." },
        { id: "grandparents", q: "¿Puedo invitar a los abuelos o a la canguro?", triggers: ["abuel", "canguro", "ninera", " tia ", " tio ", "tios"],
          a: "Sí: una familia puede incluir a **quien tú invites** — abuelos, canguros, otros adultos — sin límite de miembros en ningún plan. Con la visibilidad selectiva decides qué ve cada uno." },
        { id: "widgets", q: "¿Hay widgets para iPhone?", triggers: ["widget", "widgets para", "centro de control", "pantalla de bloqueo", "extension", "compartir con"],
          a: "Sí: **widgets**, controles para el Centro de control y la pantalla de bloqueo, autocompletado de contraseñas y una **extensión de compartir** para enviar archivos a KidBox desde otras apps." },
        { id: "ai_privacy", q: "¿La IA lee todos mis datos?", triggers: ["la ia lee", "la ia ve", "la ia accede", "datos a la ia", "envia mis datos"],
          a: "No: las funciones de IA envían al servidor **solo los datos necesarios para responder**, y **solo cuando las usas**. El contenido cifrado con la clave de la familia sigue siendo ilegible en el servidor, y tus datos no se venden ni se comparten con terceros para publicidad. Todos los detalles en la [privacidad](" + PAGES.privacy + ")." },
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
        { id: "invite", q: "Comment inviter l'autre parent ?", triggers: ["invit", "autre parent", "conjoint", "mon mari", "ma femme"],
          a: "Dans l'app, vous créez votre famille et partagez un **lien d'invitation** (sur WhatsApp, par exemple) ou faites scanner un **code QR**. La personne qui ouvre le lien rejoint la famille et voit dès lors le calendrier, les courses, la santé et tout ce que vous partagez. **Aucune limite de membres**, sur aucune offre, même la gratuite." },
        { id: "privacy", q: "Mes données sont-elles en sécurité ?", triggers: ["securit", "confidentialit", "chiffr", "crypt", "end to end", "de bout en bout"],
          a: "Les contenus les plus sensibles — **documents, notes, mots de passe, wallet, chat, photos et vidéos** — sont chiffrés avec une clé que seuls les membres de votre famille possèdent : sur le serveur, ils restent illisibles. Le chat est chiffré de bout en bout. Vos données ne sont pas vendues. Tous les détails dans la [politique de confidentialité](" + PAGES.privacy + ")." },
        { id: "ai_free", q: "L'assistant IA est-il inclus gratuitement ?", triggers: ["ia gratuit", "intelligence artificielle", "messages ia", "assistant ia", "inclus", "chatgpt"],
          a: "Avec l'offre gratuite, vous avez **quelques messages IA d'essai, une seule fois**, pour voir comment ça marche. Avec **Pro et Max**, les messages se renouvellent **chaque jour** et vous débloquez aussi le Plan alimentaire, le Plan fitness et les voyages planifiés par l'IA. Le compteur est commun à toute la famille." },
        { id: "separated", q: "Ça convient aux parents séparés ?", triggers: ["separe", "divorc", "garde alternee", "mon ex"],
          a: "Oui, c'est l'une des raisons d'être de KidBox : le calendrier des enfants, **les rendez-vous et documents médicaux**, les dépenses et les tâches partagés dans un espace neutre, loin des fils de discussion. Avec la **visibilité sélective**, vous choisissez qui voit chaque note, liste, événement, document ou élément du wallet." },
        { id: "support", q: "J'ai déjà l'app et j'ai un problème", triggers: ["je n arrive pas", "erreur", "bug", "ne marche pas", "ne fonctionne pas", "probleme de connexion", "se connecter", "rembours"],
          a: "Désolé ! L'app propose une **assistance avec un assistant IA dédié**, gratuite sur toutes les offres : allez dans **Réglages → Aide et assistance**, décrivez le problème et joignez jusqu'à 5 captures d'écran ; si besoin, il ouvre un ticket auprès de l'équipe. Si vous n'arrivez pas du tout à entrer dans l'app, écrivez à **passboxcontact@gmail.com**." },
        { id: "health", q: "Que puis-je enregistrer sur la santé des enfants ?", triggers: ["sante", "vaccin", "pediatre", "medic", "ordonnance", "compte rendu"],
          a: "Pour chaque enfant (et chaque adulte), vous enregistrez **rendez-vous, examens, vaccins et traitements en cours**, avec les comptes rendus joints en PDF ou en photo, et recevez des rappels pour les échéances et les doses. L'IA génère un **dossier médical** récapitulatif à montrer au médecin et explique examens et résultats en langage simple (informatif : il ne remplace pas le pédiatre). Sur iPhone, elle lit aussi Apple Santé ; sur Android, Health Connect." },
        { id: "ai_what", q: "Que fait l'assistant IA ?", triggers: ["que fait l", "comment marche l ia", "comment marche l assistant", "comment fonctionne l ia", "que peut faire", "assistant ia"],
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
        { id: "calendar", q: "Y a-t-il un calendrier partagé ?", triggers: ["calendrier", "agenda", "rendez vous", "evenements"],
          a: "Oui : un **calendrier familial** avec vues mois, semaine et jour, et des événements avec lieu, participants, rappels et répétitions. Les rendez-vous médicaux enregistrés dans Santé apparaissent d'eux-mêmes dans le calendrier, et l'assistant IA peut créer des événements pour vous à partir de simples mots." },
        { id: "todo", q: "Puis-je confier des tâches à l'autre parent ?", triggers: ["tache", "to do", "todo", "assign", "confier", "corvee"],
          a: "Oui. Les **listes de tâches** sont partagées avec la famille et chaque tâche peut être **attribuée à un membre**, qui reçoit une notification, avec une échéance et un rappel." },
        { id: "shopping", q: "Comment marche la liste de courses ?", triggers: ["liste de courses", "courses partagee", "supermarche", "faire les courses"],
          a: "Elle est partagée et mise à jour **en temps réel** : quand l'un ajoute ou coche un article, l'autre le voit aussitôt, et l'on voit qui l'a ajouté et quand. L'assistant IA peut ajouter des articles pour vous à partir de simples mots." },
        { id: "expenses", q: "Puis-je suivre les dépenses de la famille ?", triggers: ["depense", "budget", "combien avons nous depense", "les comptes", "comptabilite"],
          a: "Oui : les dépenses de la famille **par catégorie**, avec tickets et photos joints et des récapitulatifs par mois. Certaines se créent seules : si vous saisissez un coût dans une autre section (un rendez-vous médical, une révision de voiture, une facture de la maison), KidBox crée la dépense sans la saisir deux fois. Vous pouvez demander à l'IA « combien avons-nous dépensé en mai ? »." },
        { id: "documents", q: "Où ranger les documents ?", triggers: ["document", "archive", "certificat", "contrat", "pdf"],
          a: "Dans **Documents** : une archive chiffrée avec dossiers et catégories pour comptes rendus, ordonnances, certificats, contrats et reçus, avec import de PDF et de photos. Les pièces jointes des autres sections (rendez-vous, véhicules, maison, animaux) y arrivent automatiquement. Sur le serveur, elles restent illisibles : seule votre famille a la clé." },
        { id: "wallet", q: "Qu'est-ce que le Wallet ?", triggers: ["wallet", "billet", "carte de fidelite", "code barre", "piece d identite", "carte d identite"],
          a: "L'endroit pour les **billets** (trains, avions, concerts), abonnements, pièces d'identité et **cartes de fidélité** avec code-barres, partagés avec la famille et chiffrés. L'IA peut lire les champs d'un billet ou d'un document à votre place (elle utilise les messages IA de l'offre)." },
        { id: "passwords", q: "Y a-t-il un gestionnaire de mots de passe ?", triggers: ["mot de passe", "mots de passe", "identifiant", "otp", "remplissage automatique", "autofill"],
          a: "Oui, chiffré : identifiants **partagés ou personnels**, codes OTP, générateur de mots de passe, contrôle des mots de passe compromis et **remplissage automatique** sur iPhone (dans Safari aussi). Les mots de passe font partie des contenus chiffrés avec la clé de la famille : le serveur ne peut pas les lire." },
        { id: "photos", q: "Puis-je partager photos et vidéos ?", triggers: ["photo", "video", "album", "appareil photo", "images"],
          a: "Oui : des **albums familiaux** partagés et chiffrés, pour les photos et les vidéos. Sur iPhone, un raccourci ouvre l'appareil photo de KidBox depuis le Centre de contrôle. Photos et vidéos peuvent aussi être ajoutées à un voyage." },
        { id: "chat", q: "Y a-t-il une messagerie familiale ?", triggers: ["chat", "messagerie", "message", "whatsapp", "vocal"],
          a: "Oui, un chat familial **chiffré de bout en bout**, avec messages vocaux, photos, documents et galerie des médias. C'est pourquoi les notifications n'affichent pas d'aperçu du contenu : même le serveur ne peut pas le lire." },
        { id: "home", q: "Puis-je gérer les échéances de la maison ?", triggers: ["maison", "facture", "electromenager", "garantie", "entretien", "impots", "taxe"],
          a: "Oui, dans la section **Maison** : électroménager et équipements avec garantie et entretien, plus les échéances et paiements de la maison — factures, impôts, contrats. Une facture saisie ici devient d'elle-même une dépense." },
        { id: "garage", q: "Me rappelle-t-elle l'assurance et le contrôle technique ?", triggers: ["voiture", "vehicule", "assurance", "controle technique", "revision", "garage", "pneus"],
          a: "Oui, dans le **Garage** : une fiche par véhicule avec les échéances de **taxe, assurance et contrôle technique** et l'historique des interventions (révision, pneus, réparations) avec coût et reçu. Une notification arrive avant chaque échéance, et une intervention avec un coût rejoint d'elle-même les Dépenses." },
        { id: "pets", q: "Puis-je aussi enregistrer les animaux ?", triggers: ["animal", "animaux", "chien", "chat de", "veterinaire", "toilettage"],
          a: "Oui : une fiche par animal avec ses données et ses événements de santé — **vaccins, visites chez le vétérinaire, médicaments, toilettage** — avec rappels. L'assistant IA connaît aussi les données des animaux." },
        { id: "trips", q: "Comment marche la planification des voyages ?", triggers: ["voyage", "vacances", "itineraire", "destination"],
          a: "Avec **Pro et Max** : vous définissez votre style de voyage et l'IA suggère la destination, ou vous planifiez pas à pas (lieux, dates, transports, qui vient, budget, hébergement). L'IA crée un **itinéraire jour par jour** — matin, après-midi, soir — avec hébergements, restaurants et étapes reliés à des photos, des avis et une carte, plus une section « Histoire et territoire ». Depuis le voyage, vous ajoutez photos, notes, tâches et dépenses." },
        { id: "meal_plan", q: "Qu'est-ce que le Plan alimentaire ?", triggers: ["plan alimentaire", "alimentation", "regime", "menu", "recettes", "repas", "allergi"],
          a: "Un **menu hebdomadaire** créé par l'IA selon l'âge, le poids, les objectifs, les comptes rendus médicaux et les allergies de la personne qui le suit. Il est inclus dans les offres **Pro et Max** ; il n'est pas disponible avec l'offre gratuite. Les réponses sont informatives et ne remplacent pas le médecin ou le nutritionniste." },
        { id: "fitness", q: "Qu'est-ce que le Plan fitness ?", triggers: ["fitness", "entrainement", "salle de sport", "sport", "exercice"],
          a: "Un **programme d'entraînement** créé par l'IA, avec calendrier, rappels, historique et rapport hebdomadaire ; les séances se clôturent d'elles-mêmes en lisant Apple Santé ou Health Connect. Il est inclus dans les offres **Pro et Max** ; il n'est pas disponible avec l'offre gratuite." },
        { id: "monthly_analysis", q: "Qu'est-ce que l'analyse mensuelle ?", triggers: ["analyse mensuelle", "schema", "recurren", "chaque mois"],
          a: "Chaque mois, l'IA **relit l'historique de santé des enfants** à la recherche de schémas difficiles à remarquer : récurrences saisonnières, examens jamais faits, antibiotiques trop fréquents. C'est une fonction des offres **Pro et Max**, informative : elle ne remplace pas le pédiatre." },
        { id: "medical_record", q: "Qu'est-ce que le dossier médical ?", triggers: ["dossier medical", "dossier", "resume de sante", "historique de sante", "montrer au medecin"],
          a: "Un **document récapitulatif** généré par l'IA à partir des rendez-vous, examens, vaccins et traitements enregistrés, à montrer au médecin. Les opérations longues comme celle-ci peuvent compter pour plus d'un message IA. Ce n'est pas un dossier médical officiel et l'IA ne pose pas de diagnostic." },
        { id: "health_sync", q: "Se connecte-t-elle à Apple Santé ou Health Connect ?", triggers: ["apple sante", "health connect", "apple health", "nombre de pas", "podometre", "rythme cardiaque", "montre connectee", "apple watch"],
          a: "Oui : sur iPhone elle lit **Apple Santé**, sur Android **Health Connect** — pas, rythme cardiaque, tension, saturation, calories actives, entraînements et distance. Le Plan fitness s'en sert pour clôturer seul les séances terminées. Les données de santé ne sont jamais partagées avec des tiers à des fins publicitaires." },
        { id: "ai_proactive", q: "L'IA me prévient-elle toute seule ?", triggers: ["briefing", "chaque matin", "proactiv", "toute seule", "resume hebdomadaire"],
          a: "Oui : un **esprit proactif** travaille sans que vous demandiez rien. Chaque matin, il prépare un **briefing** avec les engagements du jour et les doses à donner, en fin de semaine un récapitulatif, et chaque mois (Pro et Max) une analyse de l'historique de santé des enfants." },
        { id: "visibility", q: "Puis-je cacher certaines choses à l'autre parent ?", triggers: ["cacher", "masquer", "certaines choses", "visibilite", "moi seul", "prive", "qui voit"],
          a: "Oui, avec la **visibilité sélective** : pour les notes, listes, calendrier, documents et wallet, vous choisissez qui voit chaque contenu — toute la famille, certains membres ou vous seul. Les mots de passe peuvent être partagés ou personnels." },
        { id: "signup", q: "Comment s'inscrire ?", triggers: ["inscri", "creer un compte", "creer mon compte", "connexion avec apple", "connexion avec google"],
          a: "Avec **Apple, Google ou e-mail et mot de passe**. Avec l'e-mail, vous confirmez l'adresse depuis le lien reçu avant d'entrer ; « Se connecter avec Apple » vous permet de garder votre e-mail privé. À la première connexion, un court parcours guidé vous fait créer la famille (ou rejoindre une famille existante avec une invitation) et inviter l'autre parent." },
        { id: "delete_account", q: "Puis-je supprimer mon compte et mes données ?", triggers: ["supprimer mon compte", "supprimer le compte", "supprimer mes donnees", "effacer mes donnees", "fermer mon compte"],
          a: "Oui, depuis l'app : dans **Réglages**, vous supprimez le compte avec toutes les données personnelles. Les instructions pas à pas sont sur [kidboxapp.com/data-deletion](https://kidboxapp.com/data-deletion)." },
        { id: "languages", q: "En quelles langues est-elle disponible ?", triggers: ["langue", "anglais", "italien", "espagnol", "tradui"],
          a: "L'app est en **français, anglais, italien et espagnol**, et l'assistant IA répond dans votre langue. Seule Alexa fonctionne exclusivement en italien." },
        { id: "who_made", q: "Qui est derrière KidBox ?", triggers: ["qui etes vous", "qui l a faite", "qui a fait", "qui est derriere", "entreprise", "italienne"],
          a: "KidBox est un produit **italien**, fait en Italie par une **petite équipe indépendante**. Pour nous écrire : passboxcontact@gmail.com, ou depuis l'app dans Réglages → Aide et assistance." },
        { id: "web_subscription", q: "Puis-je m'abonner depuis la web app ?", triggers: ["m abonner depuis", "depuis la web app", "payer depuis", "acheter depuis", "depuis le navigateur", "depuis le site"],
          a: "Non : les abonnements s'achètent **uniquement dans les apps**, via l'App Store sur iPhone, iPad et Mac ou Google Play sur Android. L'offre activée vaut ensuite pour toute la famille, web app comprise." },
        { id: "annual", q: "Y a-t-il une offre annuelle ou une réduction ?", triggers: ["annuel", "reduction", "promo", "code promo", "coupon", "remise"],
          a: "Pas pour le moment : les prix sont **mensuels**, sans offre annuelle ni réduction publiée. L'abonnement se renouvelle chaque mois et se résilie quand vous voulez. L'offre gratuite, gratuite pour toujours, inclut toutes les sections sauf le Plan alimentaire, le Plan fitness et les itinéraires de voyage par l'IA." },
        { id: "integrations", q: "Se connecte-t-elle à l'école ou à la banque ?", triggers: ["ecole", "pronote", "banque", "dossier medical partage", "compte bancaire"],
          a: "Non : KidBox **ne se connecte pas** à l'espace numérique de l'école, aux banques ni au dossier médical partagé. Les données, c'est vous qui les saisissez, y compris en important des documents et des photos que l'IA lit et transforme en actions." },
        { id: "grandparents", q: "Puis-je inviter les grands-parents ou la baby-sitter ?", triggers: ["grand mere", "grand pere", "grands parents", "baby sitter", "babysitter", "nounou", "tante", "oncle"],
          a: "Oui : une famille peut inclure **toutes les personnes que vous invitez** — grands-parents, baby-sitters, autres adultes — sans limite de membres, sur aucune offre. Avec la visibilité sélective, vous décidez ce que chacun voit." },
        { id: "widgets", q: "Y a-t-il des widgets pour iPhone ?", triggers: ["widget", "widgets pour", "centre de controle", "ecran verrouille", "extension", "partager avec"],
          a: "Oui : des **widgets**, des commandes pour le Centre de contrôle et l'écran verrouillé, le remplissage automatique des mots de passe et une **extension de partage** pour envoyer des fichiers à KidBox depuis d'autres apps." },
        { id: "ai_privacy", q: "L'IA lit-elle toutes mes données ?", triggers: ["l ia lit", "l ia voit", "l ia accede", "donnees a l ia", "envoie mes donnees"],
          a: "Non : les fonctions IA n'envoient au serveur **que les données nécessaires pour répondre**, et **seulement quand vous les utilisez**. Les contenus chiffrés avec la clé de la famille restent illisibles sur le serveur, et vos données ne sont ni vendues ni partagées avec des tiers à des fins publicitaires. Tous les détails dans la [politique de confidentialité](" + PAGES.privacy + ")." },
      ],
    },
  };
  var T = I18N[lang];

  // ── Stato ────────────────────────────────────────────────────────────────

  // `asked`: id delle domande suggerite già fatte. Non si ricava dai messaggi,
  // che sono tagliati a 20: dopo dieci domande le prime tornerebbero tra i chip.
  var state = load() || { sessionId: newSessionId(), messages: [], asked: [] };
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
      if (parsed && parsed.sessionId && Array.isArray(parsed.messages)) {
        if (!Array.isArray(parsed.asked)) parsed.asked = [];
        return parsed;
      }
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
    // `padding:0` esplicito: il pannello è una <section>, e la landing dà a
    // ogni section 80px sopra e sotto (56 sul telefono): la chat nasceva con
    // una fascia bianca vuota sopra la testata e sotto il campo di testo.
    ".kbc-panel{position:fixed;right:20px;bottom:20px;z-index:9001;width:min(400px,calc(100vw - 32px));height:min(620px,calc(100dvh - 40px));padding:0;display:flex;flex-direction:column;border:1px solid var(--border,var(--c-border,rgba(180,120,60,.14)));border-radius:22px;background:var(--surface,var(--c-surface,#fff));color:var(--text,var(--c-text,#1c1008));box-shadow:0 24px 70px rgba(0,0,0,.25);overflow:hidden;font-family:inherit}" +
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
    state = { sessionId: state.sessionId, messages: [], asked: [] };
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
    var left = T.faq.filter(function (f) { return state.asked.indexOf(f.id) < 0; }).slice(0, CHIPS_SHOWN);
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
    if (state.asked.indexOf(faq.id) < 0) state.asked.push(faq.id);
    if (faq.ask) {
      // I prezzi li scrive il server dal listino vivo, senza modello.
      askPrice(faq, typed);
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

  function askPrice(faq, typed) {
    push("user", typed || faq.q);
    busy = true;
    sendBtn.disabled = true;
    renderLog();
    var body = { action: "price" };
    if (typed) { body.match = true; body.question = typed; }
    post(body).then(function (res) {
      if (res && res.answer) {
        push("assistant", res.answer);
        track("landing_chat_question", { source: typed ? "faq_match" : "faq_chip", faq_id: faq.id });
      } else {
        push("assistant", T.unavailable);
        track("landing_chat_question", { source: "fallback_error" });
      }
    }).catch(function () {
      push("assistant", T.unavailable);
    }).then(function () {
      busy = false;
      sendBtn.disabled = false;
      renderLog();
    });
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
