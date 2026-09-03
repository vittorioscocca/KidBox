/**
 * Contesto famiglia per l'assistente: porta su web il `systemPrompt` che iOS
 * costruisce in `PlanningContextBuilder`.
 *
 * Ruolo e REGOLE sono ricopiati parola per parola dal telefono — l'assistente
 * deve rispondere allo stesso modo sulle due superfici.
 *
 * Le sezioni di dati sono meno di quelle di iOS, e il prompt lo dichiara invece
 * di far finta di niente: un modello che crede di vedere le cure attive e non le
 * riceve risponde «non risulta nulla» con sicurezza, ed è peggio che dire di non
 * avere quella parte. Qui si mandano calendario, to-do, spesa, spese, viaggi,
 * animali, casa e garage — tutti dati in chiaro. Restano fuori note, chat e
 * salute, cifrate o troppo sensibili per finire in un prompt senza una scelta
 * esplicita dell'utente.
 */
import { collection, getDocs, query, where } from "firebase/firestore";
import { db } from "../firebase";
import { ACTIONS_PROMPT } from "./aiActions";
import { loadFacts, memorySection } from "./aiMemory";
import { loadFamilyKey } from "./familyKey";
import { decryptString } from "./noteCrypto";
import { noteHtmlToText } from "./noteHtml";

const DAYS_HORIZON = 14;

const fmtDate = (millis) =>
  new Date(millis).toLocaleDateString("it-IT", {
    day: "2-digit",
    month: "long",
    year: "numeric",
  });

const fmtDateTime = (millis) =>
  new Date(millis).toLocaleString("it-IT", {
    day: "2-digit",
    month: "long",
    hour: "2-digit",
    minute: "2-digit",
  });

const toMillis = (value) => (value?.toMillis ? value.toMillis() : null);

async function readCollection(familyId, name, { onlyActive = true } = {}) {
  const base = collection(db, "families", familyId, name);
  try {
    const snap = await getDocs(onlyActive ? query(base, where("isDeleted", "==", false)) : base);
    return snap.docs.map((d) => ({ id: d.id, ...d.data() }));
  } catch {
    // Una sezione che non si riesce a leggere non deve far fallire l'intera
    // conversazione: si manda il contesto senza di lei.
    return [];
  }
}

/** Righe di una sezione, o niente se la sezione è vuota. */
function section(title, lines) {
  if (!lines.length) return null;
  return `\n## ${title}\n${lines.map((l) => `• ${l}`).join("\n")}`;
}

export async function buildSystemPrompt({ familyId, userId, familyName, members, children }) {
  const now = Date.now();
  const horizon = now + DAYS_HORIZON * 86_400_000;

  const [
    events, todos, groceries, expenses, trips, pets, homeItems, vehicles,
    notes, chatMessages, treatments, visits, exams, vaccines,
  ] = await Promise.all([
    readCollection(familyId, "calendarEvents"),
    readCollection(familyId, "todos"),
    readCollection(familyId, "groceries"),
    readCollection(familyId, "expenses"),
    readCollection(familyId, "trips", { onlyActive: false }),
    readCollection(familyId, "pets"),
    readCollection(familyId, "homeItems"),
    readCollection(familyId, "vehicles"),
    readCollection(familyId, "notes"),
    readCollection(familyId, "chatMessages"),
    readCollection(familyId, "treatments"),
    readCollection(familyId, "medicalVisits"),
    readCollection(familyId, "medicalExams"),
    readCollection(familyId, "vaccines"),
  ]);

  // La chiave serve solo per note e chat. Se manca su questo dispositivo si
  // prosegue senza quelle due sezioni invece di far fallire tutto il contesto.
  const familyKey = await loadFamilyKey({ familyId, userId }).catch(() => null);

  const memberName = (uid) =>
    members.find((m) => m.id === uid || m.userId === uid)?.displayName || null;

  const lines = [];

  lines.push(
    `Sei un assistente di pianificazione familiare integrato nell'app KidBox.\n` +
      `Hai accesso al calendario, ai to-do, alla lista della spesa, alle spese, ai viaggi, ` +
      `agli animali domestici, agli oggetti di casa, al garage, alle note, agli ultimi ` +
      `messaggi della chat di famiglia e ai dati sanitari (cure, visite, esami, vaccini) ` +
      `di ${familyName}.\n\n` +
      `REGOLE IMPORTANTI:\n` +
      `- Aiuta i genitori a pianificare, trovare spazi liberi e non dimenticare scadenze.\n` +
      `- Non dare consigli medici vincolanti; per questioni cliniche invita a sentire il medico.\n` +
      `- Quando proponi di creare un evento o un to-do, specifica sempre titolo, data/ora ` +
      `e (se rilevante) il membro da assegnare.\n` +
      `- Parla sempre in italiano, con un tono caldo e pratico.\n` +
      `- L'orizzonte temporale corrente è ${fmtDate(now)} — ${fmtDate(horizon)} (${DAYS_HORIZON} giorni).\n` +
      `- I dati sanitari che ricevi servono a organizzare, non a diagnosticare.`
  );

  // Subito dopo le regole, prima dei dati: è la posizione che ha su iOS.
  lines.push(memorySection(await loadFacts(familyId)));

  const familyLines = [];
  if (members.length) {
    familyLines.push(
      `Membri: ${members.map((m) => m.displayName || m.name || "—").join(", ")}`
    );
  }
  if (children.length) {
    familyLines.push(
      `Bambini: ${children
        .map((c) => {
          const birth = toMillis(c.birthDate);
          return birth ? `${c.name} (nato il ${fmtDate(birth)})` : c.name;
        })
        .join(", ")}`
    );
  }
  lines.push(section("Famiglia", familyLines));

  lines.push(
    section(
      `Calendario (prossimi ${DAYS_HORIZON} giorni)`,
      events
        .map((e) => ({ ...e, start: toMillis(e.startDate) }))
        .filter((e) => e.start && e.start >= now && e.start <= horizon)
        .sort((a, b) => a.start - b.start)
        .slice(0, 40)
        .map((e) => `${fmtDateTime(e.start)} — ${e.title || "senza titolo"}`)
    )
  );

  lines.push(
    section(
      "To-do aperti",
      todos
        .filter((t) => !t.isDone)
        .slice(0, 40)
        .map((t) => {
          const due = toMillis(t.dueAt);
          const who = memberName(t.assignedTo);
          return [
            t.title || "senza titolo",
            due ? `scadenza ${fmtDate(due)}` : null,
            who ? `assegnato a ${who}` : null,
          ]
            .filter(Boolean)
            .join(" · ");
        })
    )
  );

  lines.push(
    section(
      "Lista della spesa (da comprare)",
      groceries
        .filter((g) => !g.isPurchased)
        .slice(0, 50)
        .map((g) => ((g.quantity ?? 1) > 1 ? `${g.name} ×${g.quantity}` : g.name))
    )
  );

  lines.push(
    section(
      "Spese recenti",
      expenses
        .map((e) => ({ ...e, when: toMillis(e.date) }))
        .filter((e) => e.when)
        .sort((a, b) => b.when - a.when)
        .slice(0, 20)
        .map((e) => `${fmtDate(e.when)} — ${e.title || "spesa"}: ${Number(e.amount || 0).toFixed(2)} €`)
    )
  );

  lines.push(
    section(
      "Viaggi",
      trips
        .map((t) => ({ ...t, start: toMillis(t.startDate), end: toMillis(t.endDate) }))
        .filter((t) => t.end && t.end >= now)
        .sort((a, b) => a.start - b.start)
        .slice(0, 10)
        .map((t) => `${t.name}: dal ${fmtDate(t.start)} al ${fmtDate(t.end)}`)
    )
  );

  lines.push(
    section(
      "Animali domestici",
      pets.slice(0, 10).map((p) => [p.name, p.species, p.breed].filter(Boolean).join(" · "))
    )
  );

  lines.push(
    section(
      "Casa (garanzie e scadenze)",
      homeItems
        .map((h) => ({ ...h, when: toMillis(h.warrantyExpiryDate) }))
        .filter((h) => h.when && h.when >= now && h.when <= horizon + 180 * 86_400_000)
        .slice(0, 15)
        .map((h) => `${h.name}: garanzia fino al ${fmtDate(h.when)}`)
    )
  );

  lines.push(
    section(
      "Garage (scadenze veicoli)",
      vehicles
        .flatMap((v) =>
          [
            ["assicurazione", v.insuranceExpiryDate],
            ["revisione", v.revisionExpiryDate],
            ["bollo", v.taxExpiryDate],
            ["tagliando", v.nextServiceDate],
          ]
            .map(([label, value]) => ({ label, when: toMillis(value), name: v.name }))
            .filter((d) => d.when && d.when >= now && d.when <= horizon + 180 * 86_400_000)
        )
        .sort((a, b) => a.when - b.when)
        .slice(0, 15)
        .map((d) => `${d.name} — ${d.label}: ${fmtDate(d.when)}`)
    )
  );

  const childName = (id) => children.find((c) => c.id === id)?.name || null;
  const withChild = (text, id) => {
    const name = childName(id);
    return name ? `${text} (${name})` : text;
  };

  // ── Note e chat: cifrate, si decifrano solo se la chiave c'è ─────────────
  if (familyKey) {
    const decrypted = await Promise.all(
      notes
        .map((n) => ({ ...n, when: toMillis(n.updatedAt) ?? 0 }))
        .sort((a, b) => b.when - a.when)
        .slice(0, 10)
        .map(async (n) => {
          try {
            const title = (await decryptString(n.titleEnc, familyKey)) || "senza titolo";
            const body = noteHtmlToText(await decryptString(n.bodyEnc, familyKey)) || "";
            // Solo l'inizio del corpo: una nota lunga da sola riempirebbe il
            // contesto e schiaccerebbe tutto il resto.
            const excerpt = body.length > 200 ? `${body.slice(0, 200)}…` : body;
            return excerpt ? `${title}: ${excerpt}` : title;
          } catch {
            return null;
          }
        })
    );
    lines.push(section("Note recenti", decrypted.filter(Boolean)));

    const chat = await Promise.all(
      chatMessages
        .map((m) => ({ ...m, when: toMillis(m.createdAt) ?? 0 }))
        .filter((m) => m.textEnc || m.text)
        .sort((a, b) => a.when - b.when)
        .slice(-20)
        .map(async (m) => {
          try {
            const text = m.textEnc ? await decryptString(m.textEnc, familyKey) : m.text;
            return text ? `${m.senderName || "—"}: ${text}` : null;
          } catch {
            return null;
          }
        })
    );
    lines.push(section("Ultimi messaggi della chat di famiglia", chat.filter(Boolean)));
  }

  // ── Salute ──────────────────────────────────────────────────────────────
  lines.push(
    section(
      "Cure attive",
      treatments
        .filter((t) => t.isActive)
        .slice(0, 20)
        .map((t) =>
          withChild(
            [t.drugName, [t.dosageValue, t.dosageUnit].filter(Boolean).join(" ")]
              .filter(Boolean)
              .join(" · "),
            t.childId
          )
        )
    )
  );

  lines.push(
    section(
      "Prossime visite",
      visits
        .map((v) => ({ ...v, when: toMillis(v.nextVisitDate) }))
        .filter((v) => v.when && v.when >= now)
        .sort((a, b) => a.when - b.when)
        .slice(0, 10)
        .map((v) =>
          withChild(`${fmtDate(v.when)} — ${v.nextVisitReason || v.reason || "controllo"}`, v.childId)
        )
    )
  );

  lines.push(
    section(
      "Esami in sospeso",
      exams
        .filter((e) => e.statusRaw && e.statusRaw !== "done" && e.statusRaw !== "completed")
        .slice(0, 15)
        .map((e) => withChild(`${e.name}${e.isUrgent ? " (urgente)" : ""}`, e.childId))
    )
  );

  lines.push(
    section(
      "Vaccini in arrivo",
      vaccines
        .map((v) => ({ ...v, when: toMillis(v.scheduledDate) ?? toMillis(v.nextDoseDate) }))
        .filter((v) => v.when && v.when >= now)
        .sort((a, b) => a.when - b.when)
        .slice(0, 10)
        .map((v) =>
          withChild(
            `${v.commercialName || v.vaccineTypeRaw || "vaccino"}: ${fmtDate(v.when)}`,
            v.childId
          )
        )
    )
  );

  // Le azioni in coda: il modello deve vederle dopo i dati, così sa su che cosa
  // può agire davvero.
  lines.push(`\n${ACTIONS_PROMPT}`);

  return lines.filter(Boolean).join("\n");
}
