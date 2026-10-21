/**
 * Link dell'assistente alle voci dell'app: «trovami la bolletta della luce»
 * → risposta con `[Bolletta luce](apri:spese)` → un clic apre la spesa.
 *
 * Il modello non vede gli id (costerebbero token a ogni domanda e li
 * inventerebbe): scrive il titolo come compare nella scheda e il tipo, con la
 * data se più voci si chiamano uguale. La voce si cerca nello snapshot del
 * quaderno al momento del clic e si apre la sua pagina con `?apri=<id>`
 * (`useOpenParam`); se non c'è più si apre la sezione.
 * Stesso formato e stesse regole su iOS (`AgentLinks.swift`) e Android (`AgentLinks.kt`).
 */
import { NOTES_PREFIX } from "./walletDocuments";

/** La regola del prompt, nelle regole stabili dell'assistente. Stesso testo su iOS e Android. */
export const AGENT_LINK_RULE =
  "- Quando parli di una voce precisa delle schede (una spesa, un documento, una nota, un evento, un to-do, una visita…) " +
  "o l'utente cerca qualcosa («trovami…», «dov'è…», «la bolletta di…»), mettila come link, così si apre con un tocco: " +
  "[titolo esatto come nella scheda](apri:TIPO), oppure [titolo](apri:TIPO/AAAA-MM-GG) con la data della voce se più voci " +
  "hanno lo stesso titolo. TIPO: spese, documento, nota, evento, todo, listaspesa, visita, esame, cura, biglietto, casa, " +
  "veicolo, animale, viaggio. Solo voci che ci sono nelle schede, mai altri indirizzi; non dire «clicca qui»: il link è il titolo.";

const KINDS = ["spese", "documento", "nota", "evento", "todo", "listaspesa", "visita", "esame", "cura", "biglietto", "casa", "veicolo", "animale", "viaggio"];

/** Varianti che il modello scrive anche se la regola ne dà una sola. */
const ALIASES = {
  spesa: "spese", expense: "spese", documenti: "documento", doc: "documento", note: "nota",
  eventi: "evento", calendario: "evento", todos: "todo", promemoria: "todo", lista: "listaspesa",
  grocery: "listaspesa", visite: "visita", esami: "esame", cure: "cura", terapia: "cura",
  wallet: "biglietto", biglietti: "biglietto", veicoli: "veicolo", auto: "veicolo",
  animali: "animale", viaggi: "viaggio",
};

const fold = (text) => (text || "").normalize("NFD").replace(/\p{M}+/gu, "").toLowerCase();

const LINK = /^\s*apri:([A-Za-zÀ-ÿ\- ]+?)(?:\/(\d{4}-\d{2}-\d{2}))?\s*$/;

export const isAgentHref = (href) => /^\s*apri:/i.test(href || "");

/** `[titolo](apri:tipo/data)` → `{ kind, title, day }`; `null` se non è un link dell'assistente. */
export function parseAgentLink(label, href) {
  const m = LINK.exec(href || "");
  if (!m) return null;
  const key = fold(m[1]).replace(/[\s-]/g, "");
  const kind = KINDS.includes(key) ? key : ALIASES[key];
  const title = (label || "").replace(/\*\*/g, "").trim();
  if (!kind || !title) return null;
  return { kind, title, day: m[2] || null };
}

const words = (text) => new Set(text.split(/[^\p{L}\p{N}]+/u).filter((w) => w.length > 2));

/**
 * La voce più simile al titolo: uguale, poi contenuta, poi più di metà delle
 * parole in comune; a parità vince il giorno indicato, poi la più recente.
 */
export function bestMatch(items, link, title, date) {
  const wanted = fold(link.title).trim();
  if (!wanted) return null;
  const wantedWords = words(wanted);
  const day = link.day ? Date.parse(`${link.day}T12:00:00`) : null;
  let best = null;
  let bestScore = 0;
  let bestDistance = Infinity;
  for (const item of items || []) {
    const t = fold(title(item) || "").trim();
    if (!t) continue;
    let score;
    if (t === wanted) score = 1000;
    else if (t.includes(wanted) || wanted.includes(t)) score = 500;
    else {
      let common = 0;
      for (const w of words(t)) if (wantedWords.has(w)) common += 1;
      // «Bolletta gas» per «Bolletta luce»: una parola su due non basta.
      if (common === 0 || common * 2 <= wantedWords.size) continue;
      score = 100 * common;
    }
    const d = date(item) ?? 0;
    const distance = day != null && !Number.isNaN(day) ? Math.abs(d - day) : -d;
    if (score > bestScore || (score === bestScore && distance < bestDistance)) {
      best = item;
      bestScore = score;
      bestDistance = distance;
    }
  }
  return best;
}

const ms = (v) => (v?.toMillis ? v.toMillis() : typeof v === "number" ? v : null);

const open = (path, params) => `${path}?${new URLSearchParams(params).toString()}`;

const health = (modulo, childId, id) => open("/salute", { persona: childId, modulo, apri: id });

/**
 * Dove porta il link: `{ url, found }`. `found` falso = la voce non c'è più
 * e si apre la sezione.
 */
export function agentLinkDestination(link, s) {
  const h = s.health || { visits: [], exams: [], treatments: [] };
  const hit = (url) => ({ url, found: true });
  const miss = (url) => ({ url, found: false });
  switch (link.kind) {
    case "spese": {
      const e = bestMatch(s.expenses, link, (x) => x.title, (x) => x.when);
      return e ? hit(open("/spese", { apri: e.id })) : miss("/spese");
    }
    case "documento": {
      const d = bestMatch(s.documents, link, (x) => x.title || x.fileName, (x) => x.createdMs || x.updatedMs);
      return d ? hit(documentUrl(d, s, h)) : miss("/documenti");
    }
    case "nota": {
      const n = bestMatch(s.notes || [], link, (x) => x.title, (x) => x.updatedAt);
      return n?.id ? hit(open("/note", { apri: n.id })) : miss("/note");
    }
    case "evento": {
      const e = bestMatch(s.events, link, (x) => x.title, (x) => ms(x.startDate));
      return e ? hit(open("/calendario", { apri: e.id })) : miss("/calendario");
    }
    case "todo": {
      const t = bestMatch(s.todos, link, (x) => x.title, (x) => ms(x.dueAt) ?? ms(x.createdAt));
      return t?.listId ? hit(open("/todo", { lista: t.listId })) : miss("/todo");
    }
    case "listaspesa":
      return hit("/spesa");
    case "visita": {
      const v = bestMatch(h.visits, link, (x) => x.reason || x.doctorName, (x) => x.date);
      return v ? hit(health("visits", v.childId, v.id)) : miss("/salute");
    }
    case "esame": {
      const e = bestMatch(h.exams, link, (x) => x.name, (x) => x.deadline ?? x.createdAt);
      return e ? hit(health("exams", e.childId, e.id)) : miss("/salute");
    }
    case "cura": {
      const t = bestMatch(h.treatments, link, (x) => x.drugName, (x) => x.startDate);
      if (!t) return miss("/salute");
      return hit(t.petId ? open("/animali", { apri: t.petId }) : health("treatments", t.childId, t.id));
    }
    case "biglietto": {
      const t = bestMatch(s.walletTickets, link, (x) => x.title, (x) => x.eventDate);
      return t ? hit(open("/wallet", { tipo: "ticket", apri: t.id })) : miss("/wallet");
    }
    case "casa": {
      const item = bestMatch(s.homeItems, link, (x) => x.name, (x) => ms(x.createdAt));
      if (item) return hit(open("/casa", { tipo: "item", apri: item.id }));
      const p = bestMatch(s.housePayments, link, (x) => x.name, (x) => ms(x.createdAt));
      return p ? hit(open("/casa", { tipo: "payment", apri: p.id })) : miss("/casa");
    }
    case "veicolo": {
      const v = bestMatch(s.vehicles, link, (x) => x.name, (x) => ms(x.createdAt));
      return v ? hit(open("/garage", { apri: v.id })) : miss("/garage");
    }
    case "animale": {
      const p = bestMatch(s.pets, link, (x) => x.name, (x) => ms(x.createdAt));
      return p ? hit(open("/animali", { apri: p.id })) : miss("/animali");
    }
    case "viaggio": {
      const t = bestMatch(s.trips, link, (x) => x.name, (x) => x.startDate);
      return t ? hit(open("/viaggi", { apri: t.id })) : miss("/viaggi");
    }
    default:
      return miss("/");
  }
}

/**
 * Un allegato si apre dove vive (la visita, l'oggetto di casa…), un documento
 * d'identità nel Wallet, gli altri nella loro cartella.
 */
function documentUrl(d, s, h) {
  const tag = d.notes || "";
  if (tag.startsWith(NOTES_PREFIX)) return open("/wallet", { tipo: "doc", apri: d.id });
  const colon = tag.indexOf(":");
  if (colon > 0) {
    const id = tag.slice(colon + 1);
    switch (tag.slice(0, colon)) {
      case "visit": {
        const v = h.visits.find((x) => x.id === id);
        if (v) return health("visits", v.childId, v.id);
        break;
      }
      case "exam": {
        const e = h.exams.find((x) => x.id === id);
        if (e) return health("exams", e.childId, e.id);
        break;
      }
      case "treatment": {
        const t = h.treatments.find((x) => x.id === id && !x.petId);
        if (t) return health("treatments", t.childId, t.id);
        break;
      }
      case "homeItem":
        return open("/casa", { tipo: "item", apri: id });
      case "housePayment":
        return open("/casa", { tipo: "payment", apri: id });
      case "vehicle":
        return open("/garage", { apri: id });
      case "vehicleEvent": {
        const ev = (s.vehicleEvents || []).find((x) => x.id === id);
        if (ev?.vehicleId) return open("/garage", { apri: ev.vehicleId });
        break;
      }
      case "pet":
        return open("/animali", { apri: id });
      case "expense":
        return open("/spese", { apri: id });
      default:
        break;
    }
  }
  return open("/documenti", { apri: d.id });
}
