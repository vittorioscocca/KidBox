/**
 * Testi delle notifiche push, per lingua.
 *
 * Il server non può usare i cataloghi dei client: la push viaggia con il testo
 * già renderizzato (`notification.title`/`body`), perché è il sistema operativo
 * a mostrarla quando l'app è killed, senza eseguire codice nostro. Quindi la
 * traduzione va fatta qui, sulla lingua che l'utente ha scelto in app e che il
 * client scrive su `users/{uid}.notificationLanguage`.
 *
 * Non tutto è traducibile: il corpo di un messaggio di chat, il nome di un
 * documento o il titolo di una spesa sono contenuti dell'utente e restano
 * com'erano. Qui c'è solo la cornice.
 */

const SUPPORTED_LANGS = ["it", "en", "fr", "es"];
const DEFAULT_LANG = "it";

/** Locale completa per Intl, per lingua. @type {Object<string,string>} */
const INTL_LOCALES = {
  it: "it-IT",
  en: "en-GB",
  fr: "fr-FR",
  es: "es-ES",
};

/**
 * Riduce un valore arbitrario a una delle lingue supportate.
 *
 * Accetta sia `en` sia `en-US`/`en_GB`: i client possono scrivere l'identifier
 * completo della locale. Qualsiasi cosa non riconosciuta torna all'italiano,
 * che è la lingua storica di tutte le notifiche.
 *
 * @param {*} raw valore letto da Firestore
 * @return {string} una delle `SUPPORTED_LANGS`
 */
function normalizeLang(raw) {
  if (typeof raw !== "string") return DEFAULT_LANG;
  const code = raw.trim().toLowerCase().split(/[-_]/)[0];
  return SUPPORTED_LANGS.includes(code) ? code : DEFAULT_LANG;
}

const STRINGS = {
  it: {
    "document.title": "Nuovo documento caricato",
    "document.fallback": "Documento",

    "chat.newMessage": "Nuovo messaggio",
    "chat.photo": "📷 Ha inviato una foto",
    "chat.video": "🎥 Ha inviato un video",
    "chat.audio": "🎤 Ha inviato un messaggio vocale",
    "chat.document": "📎 Ha inviato un documento",
    "chat.mentionTitle": "{name} ti ha menzionato",
    "chat.mentionSubtitle": "Menzione in chat",

    "location.title": "Posizione",
    "location.started": "{name} sta condividendo la posizione",
    "location.stopped": "{name} ha smesso di condividere la posizione",

    "geofence.arriveTitle": "{name} è arrivato",
    "geofence.leaveTitle": "{name} è partito",
    "geofence.arriveBody": "a {place}",
    "geofence.leaveBody": "da {place}",

    "grocery.title": "Lista della spesa 🛒",
    "grocery.body": "{name} ha aggiunto: {item}",
    "grocery.fallback": "Prodotto",

    "note.title": "📝 Nuova nota",
    "note.body": "{name} ha aggiunto una nuova nota",

    "calendar.title": "📅 Calendario",
    "calendar.body": "{name} ha aggiunto: {event} — {date}",
    "calendar.bodyNoDate": "{name} ha aggiunto: {event}",
    "calendar.fallback": "Nuovo evento",

    "expense.title": "💸 Nuova spesa registrata",
    "expense.body": "{title} · {amount}",
    "expense.fallback": "Spesa",

    "wallet.ticketTitle": "🎟️ Nuovo biglietto nel Wallet",
    "wallet.ticketBody": "{who} · {kind}",
    "wallet.ticketBodyWithDate": "{who} · {kind} — {date}",
    "wallet.ticketBodyNoWho": "{kind}",
    "wallet.ticketBodyNoWhoWithDate": "{kind} — {date}",
    "wallet.loyaltyTitle": "Nuova carta fedeltà",
    "wallet.loyaltyFallback": "Carta fedeltà",
    "wallet.reminderBody": "{kind} — {date}",
    "wallet.reminderTomorrow": "⏰ Biglietto domani",
    "wallet.reminder2h": "⏰ Biglietto tra 2 ore",
    "wallet.reminderSoon": "⏰ Biglietto a breve",
    "wallet.reminderInDays": "⏰ Biglietto tra {count} giorni",
    "wallet.reminderInHours": "⏰ Biglietto tra {count} ore",

    "wallet.kind.train": "Treno",
    "wallet.kind.flight": "Volo",
    "wallet.kind.ferry": "Traghetto",
    "wallet.kind.bus": "Autobus",
    "wallet.kind.concert": "Concerto",
    "wallet.kind.cinema": "Cinema",
    "wallet.kind.parking": "Parcheggio",
    "wallet.kind.museum": "Museo",
    "wallet.kind.default": "Biglietto",
  },

  en: {
    "document.title": "New document uploaded",
    "document.fallback": "Document",

    "chat.newMessage": "New message",
    "chat.photo": "📷 Sent a photo",
    "chat.video": "🎥 Sent a video",
    "chat.audio": "🎤 Sent a voice message",
    "chat.document": "📎 Sent a document",
    "chat.mentionTitle": "{name} mentioned you",
    "chat.mentionSubtitle": "Mention in chat",

    "location.title": "Location",
    "location.started": "{name} is sharing their location",
    "location.stopped": "{name} stopped sharing their location",

    "geofence.arriveTitle": "{name} has arrived",
    "geofence.leaveTitle": "{name} has left",
    "geofence.arriveBody": "at {place}",
    "geofence.leaveBody": "from {place}",

    "grocery.title": "Shopping list 🛒",
    "grocery.body": "{name} added: {item}",
    "grocery.fallback": "Item",

    "note.title": "📝 New note",
    "note.body": "{name} added a new note",

    "calendar.title": "📅 Calendar",
    "calendar.body": "{name} added: {event} — {date}",
    "calendar.bodyNoDate": "{name} added: {event}",
    "calendar.fallback": "New event",

    "expense.title": "💸 New expense recorded",
    "expense.body": "{title} · {amount}",
    "expense.fallback": "Expense",

    "wallet.ticketTitle": "🎟️ New ticket in Wallet",
    "wallet.ticketBody": "{who} · {kind}",
    "wallet.ticketBodyWithDate": "{who} · {kind} — {date}",
    "wallet.ticketBodyNoWho": "{kind}",
    "wallet.ticketBodyNoWhoWithDate": "{kind} — {date}",
    "wallet.loyaltyTitle": "New loyalty card",
    "wallet.loyaltyFallback": "Loyalty card",
    "wallet.reminderBody": "{kind} — {date}",
    "wallet.reminderTomorrow": "⏰ Ticket tomorrow",
    "wallet.reminder2h": "⏰ Ticket in 2 hours",
    "wallet.reminderSoon": "⏰ Ticket coming up",
    "wallet.reminderInDays": "⏰ Ticket in {count} days",
    "wallet.reminderInHours": "⏰ Ticket in {count} hours",

    "wallet.kind.train": "Train",
    "wallet.kind.flight": "Flight",
    "wallet.kind.ferry": "Ferry",
    "wallet.kind.bus": "Bus",
    "wallet.kind.concert": "Concert",
    "wallet.kind.cinema": "Cinema",
    "wallet.kind.parking": "Parking",
    "wallet.kind.museum": "Museum",
    "wallet.kind.default": "Ticket",
  },

  fr: {
    "document.title": "Nouveau document ajouté",
    "document.fallback": "Document",

    "chat.newMessage": "Nouveau message",
    "chat.photo": "📷 A envoyé une photo",
    "chat.video": "🎥 A envoyé une vidéo",
    "chat.audio": "🎤 A envoyé un message vocal",
    "chat.document": "📎 A envoyé un document",
    "chat.mentionTitle": "{name} vous a mentionné",
    "chat.mentionSubtitle": "Mention dans le chat",

    "location.title": "Position",
    "location.started": "{name} partage sa position",
    "location.stopped": "{name} a arrêté de partager sa position",

    "geofence.arriveTitle": "{name} est arrivé",
    "geofence.leaveTitle": "{name} est parti",
    "geofence.arriveBody": "à {place}",
    "geofence.leaveBody": "de {place}",

    "grocery.title": "Liste de courses 🛒",
    "grocery.body": "{name} a ajouté : {item}",
    "grocery.fallback": "Article",

    "note.title": "📝 Nouvelle note",
    "note.body": "{name} a ajouté une nouvelle note",

    "calendar.title": "📅 Calendrier",
    "calendar.body": "{name} a ajouté : {event} — {date}",
    "calendar.bodyNoDate": "{name} a ajouté : {event}",
    "calendar.fallback": "Nouvel événement",

    "expense.title": "💸 Nouvelle dépense enregistrée",
    "expense.body": "{title} · {amount}",
    "expense.fallback": "Dépense",

    "wallet.ticketTitle": "🎟️ Nouveau billet dans le Wallet",
    "wallet.ticketBody": "{who} · {kind}",
    "wallet.ticketBodyWithDate": "{who} · {kind} — {date}",
    "wallet.ticketBodyNoWho": "{kind}",
    "wallet.ticketBodyNoWhoWithDate": "{kind} — {date}",
    "wallet.loyaltyTitle": "Nouvelle carte de fidélité",
    "wallet.loyaltyFallback": "Carte de fidélité",
    "wallet.reminderBody": "{kind} — {date}",
    "wallet.reminderTomorrow": "⏰ Billet demain",
    "wallet.reminder2h": "⏰ Billet dans 2 heures",
    "wallet.reminderSoon": "⏰ Billet bientôt",
    "wallet.reminderInDays": "⏰ Billet dans {count} jours",
    "wallet.reminderInHours": "⏰ Billet dans {count} heures",

    "wallet.kind.train": "Train",
    "wallet.kind.flight": "Vol",
    "wallet.kind.ferry": "Ferry",
    "wallet.kind.bus": "Bus",
    "wallet.kind.concert": "Concert",
    "wallet.kind.cinema": "Cinéma",
    "wallet.kind.parking": "Parking",
    "wallet.kind.museum": "Musée",
    "wallet.kind.default": "Billet",
  },

  es: {
    "document.title": "Nuevo documento subido",
    "document.fallback": "Documento",

    "chat.newMessage": "Nuevo mensaje",
    "chat.photo": "📷 Ha enviado una foto",
    "chat.video": "🎥 Ha enviado un vídeo",
    "chat.audio": "🎤 Ha enviado un mensaje de voz",
    "chat.document": "📎 Ha enviado un documento",
    "chat.mentionTitle": "{name} te ha mencionado",
    "chat.mentionSubtitle": "Mención en el chat",

    "location.title": "Ubicación",
    "location.started": "{name} está compartiendo su ubicación",
    "location.stopped": "{name} ha dejado de compartir su ubicación",

    "geofence.arriveTitle": "{name} ha llegado",
    "geofence.leaveTitle": "{name} se ha ido",
    "geofence.arriveBody": "a {place}",
    "geofence.leaveBody": "de {place}",

    "grocery.title": "Lista de la compra 🛒",
    "grocery.body": "{name} ha añadido: {item}",
    "grocery.fallback": "Producto",

    "note.title": "📝 Nueva nota",
    "note.body": "{name} ha añadido una nueva nota",

    "calendar.title": "📅 Calendario",
    "calendar.body": "{name} ha añadido: {event} — {date}",
    "calendar.bodyNoDate": "{name} ha añadido: {event}",
    "calendar.fallback": "Nuevo evento",

    "expense.title": "💸 Nuevo gasto registrado",
    "expense.body": "{title} · {amount}",
    "expense.fallback": "Gasto",

    "wallet.ticketTitle": "🎟️ Nuevo billete en el Wallet",
    "wallet.ticketBody": "{who} · {kind}",
    "wallet.ticketBodyWithDate": "{who} · {kind} — {date}",
    "wallet.ticketBodyNoWho": "{kind}",
    "wallet.ticketBodyNoWhoWithDate": "{kind} — {date}",
    "wallet.loyaltyTitle": "Nueva tarjeta de fidelidad",
    "wallet.loyaltyFallback": "Tarjeta de fidelidad",
    "wallet.reminderBody": "{kind} — {date}",
    "wallet.reminderTomorrow": "⏰ Billete mañana",
    "wallet.reminder2h": "⏰ Billete en 2 horas",
    "wallet.reminderSoon": "⏰ Billete próximamente",
    "wallet.reminderInDays": "⏰ Billete en {count} días",
    "wallet.reminderInHours": "⏰ Billete en {count} horas",

    "wallet.kind.train": "Tren",
    "wallet.kind.flight": "Vuelo",
    "wallet.kind.ferry": "Ferry",
    "wallet.kind.bus": "Autobús",
    "wallet.kind.concert": "Concierto",
    "wallet.kind.cinema": "Cine",
    "wallet.kind.parking": "Aparcamiento",
    "wallet.kind.museum": "Museo",
    "wallet.kind.default": "Billete",
  },
};

/**
 * Locale completa da passare a `Intl`, con fallback sulla lingua di default.
 * @param {string} lang
 * @return {string}
 */
function intlLocale(lang) {
  return INTL_LOCALES[lang] || INTL_LOCALES[DEFAULT_LANG];
}

/**
 * Testo tradotto, con i segnaposto `{nome}` sostituiti.
 *
 * Una chiave mancante nella lingua richiesta ricade sull'italiano, e se manca
 * anche lì torna la chiave stessa: una notifica con un testo strano è meglio di
 * una notifica non inviata.
 *
 * @param {string} lang lingua già normalizzata
 * @param {string} key chiave del catalogo
 * @param {Object<string, string|number>} [params] valori per i segnaposto
 * @return {string}
 */
function t(lang, key, params = {}) {
  const table = STRINGS[lang] || STRINGS[DEFAULT_LANG];
  const template = table[key] || STRINGS[DEFAULT_LANG][key] || key;
  return template.replace(/\{(\w+)\}/g, (match, name) => {
    const has = Object.prototype.hasOwnProperty.call(params, name);
    return has ? String(params[name]) : match;
  });
}

/**
 * Etichetta del tipo di biglietto Wallet nella lingua del destinatario.
 * @param {string|null|undefined} kindRaw
 * @param {string} lang
 * @return {string}
 */
function walletKindLabel(kindRaw, lang) {
  const kind = (kindRaw || "").toLowerCase();
  const known = [
    "train", "flight", "ferry", "bus",
    "concert", "cinema", "parking", "museum",
  ];
  return t(lang, `wallet.kind.${known.includes(kind) ? kind : "default"}`);
}

/**
 * Data lunga ("3 settembre") nella lingua del destinatario.
 *
 * Il fuso resta Europe/Rome: gli eventi sono inseriti nell'ora locale della
 * famiglia, e la lingua scelta non dice nulla su dove si trovi chi legge.
 *
 * @param {Date} date
 * @param {string} lang
 * @return {string}
 */
function formatLongDate(date, lang) {
  try {
    return new Intl.DateTimeFormat(intlLocale(lang), {
      timeZone: "Europe/Rome", day: "numeric", month: "long",
    }).format(date);
  } catch (_) {
    return date.toISOString();
  }
}

/**
 * Data breve con ora ("03/09 18:30") nella lingua del destinatario.
 * @param {Date} date
 * @param {string} lang
 * @return {string}
 */
function formatShortDateTime(date, lang) {
  try {
    return new Intl.DateTimeFormat(intlLocale(lang), {
      day: "2-digit", month: "2-digit",
      hour: "2-digit", minute: "2-digit",
      timeZone: "Europe/Rome",
    }).format(date);
  } catch (_) {
    return date.toISOString();
  }
}

/**
 * Importo in euro secondo le convenzioni della lingua del destinatario
 * (`12,50 €` in italiano, `€12.50` in inglese).
 * @param {number} amount
 * @param {string} lang
 * @return {string}
 */
function formatCurrency(amount, lang) {
  try {
    return new Intl.NumberFormat(intlLocale(lang), {
      style: "currency", currency: "EUR",
    }).format(amount);
  } catch (_) {
    return `${amount.toFixed(2)} €`;
  }
}

module.exports = {
  SUPPORTED_LANGS,
  DEFAULT_LANG,
  normalizeLang,
  t,
  walletKindLabel,
  formatLongDate,
  formatShortDateTime,
  formatCurrency,
};
