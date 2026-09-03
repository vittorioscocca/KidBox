/* eslint-env serviceworker */
/**
 * Service worker delle notifiche push.
 *
 * Deve stare nella radice del sito e con questo nome esatto: è il file che
 * l'SDK Firebase Messaging registra da solo, e da qualsiasi altro percorso le
 * push in background non arriverebbero.
 *
 * Usa gli script `compat` da gstatic invece del pacchetto npm: un service
 * worker non passa dal bundle dell'app, quindi non può usare gli import del
 * progetto. La configurazione è la stessa di `src/firebase.js` — sono chiavi
 * pubbliche, quelle che il client espone comunque nel bundle.
 */
importScripts("https://www.gstatic.com/firebasejs/12.18.0/firebase-app-compat.js");
importScripts("https://www.gstatic.com/firebasejs/12.18.0/firebase-messaging-compat.js");

firebase.initializeApp({
  apiKey: "AIzaSyC7mDpJ1LadjvhhcoospAp2f0xuawCOOFk",
  authDomain: "kidbox-42cd7.firebaseapp.com",
  projectId: "kidbox-42cd7",
  storageBucket: "kidbox-42cd7-eu",
  messagingSenderId: "52613538008",
  appId: "1:52613538008:web:c5417674e80de0303df7ad",
});

const messaging = firebase.messaging();

/**
 * Sezione da aprire al clic, dedotta dal `type` che le Cloud Functions mettono
 * dentro `data`. Le stesse rotte che usa la sidebar: una push che riporta alla
 * home costringerebbe a ritrovare a mano la cosa di cui parla.
 */
const ROUTES = {
  text: "/chat",
  todo_assigned: "/todo",
  todo_due_changed: "/todo",
  new_calendar_event: "/calendario",
  new_document: "/documenti",
  new_expense: "/spese",
  new_grocery_item: "/spesa",
  new_note: "/note",
  new_wallet_ticket: "/wallet",
  new_loyalty_card: "/wallet",
  wallet_ticket_reminder: "/wallet",
  geofenceEvent: "/posizione",
};

const routeFor = (data) => ROUTES[data?.type] || "/";

/**
 * Messaggi in background.
 *
 * Il payload del server porta già `notification`, quindi il browser mostrerebbe
 * la push da solo; la si costruisce comunque qui per allegare `data` alla
 * notifica, che è ciò che serve al clic per sapere dove andare.
 */
messaging.onBackgroundMessage((payload) => {
  const data = payload.data || {};
  const title = data.title || payload.notification?.title || "KidBox";
  self.registration.showNotification(title, {
    body: data.body || payload.notification?.body || "",
    icon: "/favicon-192.png",
    badge: "/favicon-192.png",
    tag: data.type || "kidbox",
    data: { url: routeFor(data) },
  });
});

self.addEventListener("notificationclick", (event) => {
  event.notification.close();
  const url = event.notification.data?.url || "/";

  // Se una scheda del sito è già aperta si porta avanti quella e la si naviga:
  // aprirne una nuova a ogni notifica lascerebbe una fila di schede identiche.
  event.waitUntil(
    clients.matchAll({ type: "window", includeUncontrolled: true }).then((list) => {
      for (const client of list) {
        if (new URL(client.url).origin === self.location.origin) {
          client.navigate(url);
          return client.focus();
        }
      }
      return clients.openWindow(url);
    })
  );
});
