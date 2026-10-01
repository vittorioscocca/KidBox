/**
 * Richieste di famiglia: «Chi prende Marco giovedì?».
 *
 * Chi chiede sceglie i membri da avvisare e, se vuole, manda un link a chi non
 * ha l'app; la prima risposta «Ci penso io» chiude la richiesta e fa nascere il
 * to-do assegnato, visibile a tutta la famiglia.
 *
 * Il client CREA la richiesta e può solo ritirarla finché è aperta (le rules
 * non gli permettono altro). Le risposte passano dalla callable
 * `respondToRequest`, che decide «il primo Io vince» in una transazione e crea
 * il to-do lato server. Gemello di `FamilyRequestService` (iOS) e
 * `FamilyRequestRemoteStore` (Android); disegno in internal/richieste-disegno.md.
 */
import {
  collection,
  doc,
  onSnapshot,
  query,
  serverTimestamp,
  setDoc,
  Timestamp,
  updateDoc,
  where,
} from "firebase/firestore";
import { httpsCallable } from "firebase/functions";
import { db, functions } from "../firebase";
import { createInvite } from "./family";
import { expandEvents } from "../calendarUtils";
import { isVisibleTo } from "../visibility";

export const REQUEST_LINK_BASE_URL = "https://kidboxapp.com/r";
/** Senza scadenza la richiesta resta aperta due giorni. */
const DEFAULT_TTL_MS = 48 * 3600 * 1000;
/** Le rules accettano al massimo 7 giorni (più un'ora di margine). */
const MAX_TTL_MS = 7 * 24 * 3600 * 1000 - 600_000;
const TITLE_MAX = 200;
const LINKS_KEY = "kidbox:familyRequestLinks";

const requestsCol = (familyId) => collection(db, "families", familyId, "requests");

export const emptyDraft = () => ({
  recipients: [],
  askOutside: false,
  // Come chi chiede chiama la persona fuori dall'app («Nonna»).
  outsideLabel: "",
  // Il link porta anche l'invito alla famiglia: sì di default.
  includeInvite: true,
});

export const draftIsEmpty = (d) => !d || (d.recipients.length === 0 && !d.askOutside);

/**
 * Fine della richiesta: alla scadenza del to-do (dopo non ha senso), al
 * massimo 7 giorni; senza scadenza 48 ore. `null` se la scadenza è già passata.
 * Sul web la scadenza ha sempre l'orario.
 */
export function requestExpiresAt(dueAt, now = Date.now()) {
  if (!dueAt) return new Date(now + DEFAULT_TTL_MS);
  const due = dueAt.getTime();
  if (due <= now + 5 * 60_000) return null;
  return new Date(Math.min(due, now + MAX_TTL_MS));
}

function hex(buffer) {
  return [...new Uint8Array(buffer)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

function base64url(bytes) {
  let s = "";
  bytes.forEach((b) => (s += String.fromCharCode(b)));
  return btoa(s).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

/** Un'ora prima e un'ora dopo la scadenza. */
const AVAILABILITY_MARGIN_MS = 3600 * 1000;

/**
 * «Chi è libero a quell'ora» nella vista «Chiedi a…».
 *
 * Gli eventi del calendario non dicono chi partecipa, quindi non si
 * attribuiscono a nessuno: si mostrano come contesto. Gli unici impegni davvero
 * di una persona sono i to-do assegnati a lei. Gemello di
 * `FamilyRequestAvailability` su iOS e Android.
 * @return {{around: Date, events: object[], busy: Object<string, object[]>}|null}
 */
export function requestAvailability({ around, todos, events, uid }) {
  if (!around || Number.isNaN(around.getTime())) return null;
  const from = new Date(around.getTime() - AVAILABILITY_MARGIN_MS);
  const to = new Date(around.getTime() + AVAILABILITY_MARGIN_MS);

  const eventItems = expandEvents(
    events.filter((e) => !e.isDeleted && isVisibleTo(e, uid)),
    from,
    to
  )
    .map((e) => ({
      id: `${e.id}|${e.startDate.toMillis()}`,
      title: e.title || "",
      start: e.startDate.toDate(),
      end: e.endDate?.toDate?.() ?? e.startDate.toDate(),
      isAllDay: Boolean(e.isAllDay),
    }))
    .sort((a, b) => (a.isAllDay === b.isAllDay ? a.start - b.start : a.isAllDay ? -1 : 1))
    .slice(0, 4);

  const busy = {};
  todos.forEach((t) => {
    // Un to-do «tutto il giorno» non è un impegno a un'ora precisa.
    if (t.isDone || t.isDeleted || t.dueHasTime === false || !t.assignedTo) return;
    const due = t.dueAt?.toDate?.();
    if (!due || due < from || due > to || !isVisibleTo(t, uid)) return;
    (busy[t.assignedTo] ||= []).push({ id: t.id, title: t.title || "", start: due });
  });
  Object.values(busy).forEach((list) => list.sort((a, b) => a.start - b.start));
  return { around, events: eventItems, busy };
}

/** Dal documento Firestore a un oggetto comodo per le view. */
export function parseRequest(snap, familyId) {
  const d = snap.data();
  if (!d || typeof d.title !== "string" || !d.createdBy) return null;
  const responses = Object.entries(d.responses || {})
    .filter(([, v]) => v && typeof v.answer === "string")
    .map(([key, v]) => ({
      key,
      answer: v.answer,
      name: v.name || "",
      isExternal: v.type === "external",
      isYes: v.answer === "yes",
    }))
    .sort((a, b) => a.name.localeCompare(b.name));
  const expiresAt = d.expiresAt?.toDate?.() ?? null;
  const status = ["claimed", "expired", "cancelled"].includes(d.status) ? d.status : "open";
  return {
    id: snap.id,
    familyId,
    title: d.title,
    notes: (d.notes || "").trim() || null,
    dueAt: d.dueAt?.toDate?.() ?? null,
    dueHasTime: d.dueHasTime !== false,
    listId: d.listId || "",
    childId: d.childId || "",
    createdBy: d.createdBy,
    recipients: Array.isArray(d.recipients) ? d.recipients : [],
    status,
    expiresAt,
    // Lo scheduler la chiude entro 15 minuti dalla scadenza: nel frattempo
    // non va offerta come aperta.
    isOpen: status === "open" && (!expiresAt || expiresAt.getTime() > Date.now()),
    responses,
    claimedByUid: d.claimedBy?.uid || null,
    claimedByName: d.claimedBy?.name || null,
    claimedByExternal: d.claimedBy?.type === "external",
    todoId: d.todoId || null,
    hasExternalLink: Boolean(d.external),
  };
}

export function requestWhen(date, hasTime, locale) {
  const opts = { weekday: "short", day: "numeric", month: "short" };
  if (hasTime) Object.assign(opts, { hour: "2-digit", minute: "2-digit" });
  try {
    return new Intl.DateTimeFormat(locale, opts).format(date);
  } catch {
    return date.toLocaleString();
  }
}

/**
 * Crea la richiesta. Se si chiede fuori dall'app prepara anche il link, con il
 * token nel frammento (il server ne vede solo l'impronta) e, se scelto,
 * l'invito alla famiglia: lo stesso `createInvite` della pagina Famiglia,
 * monouso e valido 7 giorni.
 */
export async function createRequest({
  familyId,
  childId,
  listId,
  uid,
  title,
  notes,
  isUrgent,
  dueAt,
  draft,
  familyName,
  inviterDisplayName,
}) {
  const expires = requestExpiresAt(dueAt);
  if (!expires) throw new Error("DUE_IN_PAST");

  const requestId = crypto.randomUUID().toUpperCase();
  const cleanTitle = title.slice(0, TITLE_MAX);
  const recipients = [...new Set(draft.recipients.filter((r) => r !== uid))].sort().slice(0, 20);

  let external = null;
  let shareLink = null;
  if (draft.askOutside) {
    const token = base64url(crypto.getRandomValues(new Uint8Array(32)));
    const tokenHash = hex(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(token)));
    external = { label: draft.outsideLabel.trim(), tokenHash };
    let fragment = `t=${token}`;
    if (draft.includeInvite) {
      const invite = await createInvite({ familyId, familyName, inviterDisplayName, uid });
      external.inviteId = invite.inviteId;
      fragment += `&k=${invite.secret}`;
    }
    shareLink = `${REQUEST_LINK_BASE_URL}?f=${familyId}&r=${requestId}#${fragment}`;
  }

  await setDoc(doc(requestsCol(familyId), requestId), {
    kind: "todo",
    title: cleanTitle,
    notes: notes || null,
    priority: isUrgent ? 1 : 0,
    dueAt: dueAt ? Timestamp.fromDate(dueAt) : null,
    dueHasTime: true,
    listId,
    childId: childId || "",
    createdBy: uid,
    createdVia: "app",
    recipients,
    expiresAt: Timestamp.fromDate(expires),
    status: "open",
    external,
    createdAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
  });
  if (shareLink) saveShareLink(requestId, shareLink);
  return { requestId, shareLink, notifiedCount: recipients.length };
}

/**
 * «Ci penso io» o «Non posso». Il server decide chi vince e crea il to-do.
 * Restituisce `claimedByMe` | `claimedBy` (con `name`) | `declined` | `closed`.
 */
export async function respondToRequest({ familyId, requestId, yes }) {
  try {
    const res = await httpsCallable(functions, "respondToRequest")({
      familyId,
      requestId,
      answer: yes ? "yes" : "no",
    });
    const d = res.data || {};
    if (d.outcome === "declined") return { kind: "declined" };
    if (d.status === "claimed") {
      if (d.mine) return { kind: "claimedByMe" };
      return { kind: "claimedBy", name: d.claimedBy?.name || "" };
    }
    return { kind: "closed" };
  } catch (err) {
    // Richiesta sparita o propria: per l'utente è «non più disponibile».
    const reason = err?.details?.reason;
    if (reason === "not_found" || reason === "own_request") return { kind: "closed" };
    throw err;
  }
}

/** Le rules lo permettono solo a chi l'ha fatta e solo finché è aperta. */
export async function cancelRequest({ familyId, requestId }) {
  await updateDoc(doc(requestsCol(familyId), requestId), {
    status: "cancelled",
    cancelledAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
  });
  forgetShareLink(requestId);
}

/** Richieste aperte della famiglia, ordinate per scadenza. */
export function listenOpenRequests(familyId, onChange) {
  const q = query(requestsCol(familyId), where("status", "==", "open"));
  return onSnapshot(
    q,
    (snap) =>
      onChange(
        snap.docs
          .map((d) => parseRequest(d, familyId))
          .filter((r) => r && r.isOpen)
          .sort((a, b) => (a.dueAt?.getTime() ?? Infinity) - (b.dueAt?.getTime() ?? Infinity))
      ),
    () => onChange([])
  );
}

/** Una richiesta sola, anche chiusa. `null` se non esiste o non è leggibile. */
export function listenRequest(familyId, requestId, onChange) {
  return onSnapshot(
    doc(requestsCol(familyId), requestId),
    (snap) => onChange(snap.exists() ? parseRequest(snap, familyId) : null),
    () => onChange(null)
  );
}

// Il token esiste solo nel link: il server ne ha l'impronta. Per poterlo
// rimandare («Invia di nuovo il link») lo si tiene in questo browser.
function readLinks() {
  try {
    return JSON.parse(localStorage.getItem(LINKS_KEY) || "{}");
  } catch {
    return {};
  }
}

export function savedShareLink(requestId) {
  return readLinks()[requestId] || null;
}

function saveShareLink(requestId, link) {
  try {
    const all = readLinks();
    all[requestId] = link;
    const keys = Object.keys(all);
    keys.slice(0, Math.max(0, keys.length - 30)).forEach((k) => delete all[k]);
    localStorage.setItem(LINKS_KEY, JSON.stringify(all));
  } catch {
    /* archivio del browser non disponibile: si perde solo il «rimanda» */
  }
}

function forgetShareLink(requestId) {
  try {
    const all = readLinks();
    delete all[requestId];
    localStorage.setItem(LINKS_KEY, JSON.stringify(all));
  } catch {
    /* idem */
  }
}
