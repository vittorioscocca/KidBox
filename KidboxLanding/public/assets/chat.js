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

  /** Domande suggerite non ancora fatte in questa conversazione. */
  function chipsFor(container) {
    var asked = {};
    state.messages.forEach(function (m) { if (m.role === "user") asked[m.content] = true; });
    var left = T.faq.filter(function (f) { return !asked[f.q]; });
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
