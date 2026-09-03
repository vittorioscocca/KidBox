/**
 * Itinerario viaggi: porto in JS di `TravelItineraryBuilder` su iOS.
 *
 * Il contenuto ricco — tappe con orario, durata e costo — non sta nei
 * `dayPlans` di Firestore ma dentro `aiProposalJson`, la risposta del wizard
 * AI che l'app salva sul documento del viaggio. I `dayPlans` ne sono la
 * versione testuale, ed è quella che si usa quando la proposta manca o non
 * copre quel giorno.
 *
 * Le regole di parsing sono ricopiate dal telefono: un itinerario che sul web
 * si legge diverso da come si legge nell'app sarebbe un bug in sé.
 */

const CATEGORY_EMOJI = {
  flight: "✈️",
  transport: "🚕",
  food: "🍝",
  hotel: "🏨",
  culture: "🏛️",
  beach: "🏖️",
  shopping: "🛍️",
  other: "📍",
};

/** Mattina/pomeriggio/sera, con i colori di `TravelItineraryPeriod`. */
export const PERIODS = [
  { key: "morning", planKey: "morningPlan", stopsKey: "morningStops", color: "#F2BF1A" },
  { key: "afternoon", planKey: "afternoonPlan", stopsKey: "afternoonStops", color: "#F2611A" },
  { key: "evening", planKey: "eveningPlan", stopsKey: "eveningStops", color: "#8C59D9" },
];

/* ── Date ────────────────────────────────────────────────────────────────── */

const startOfDay = (millis) => {
  const d = new Date(millis);
  d.setHours(0, 0, 0, 0);
  return d;
};

const pad = (n) => String(n).padStart(2, "0");

export const isoDay = (date) =>
  `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}`;

/** Giorni di soggiorno inclusivi: 30 mag → 1 giu = 3 giorni, come `kbDayCount`. */
export function dayCountBetween(startMillis, endMillis) {
  const days = Math.round((startOfDay(endMillis) - startOfDay(startMillis)) / 86_400_000);
  return Math.max(days + 1, 1);
}

/** Date ISO di ogni giorno del viaggio, partenza inclusa. */
export function tripDateStrings(startMillis, count) {
  const start = startOfDay(startMillis);
  return Array.from({ length: Math.max(count, 1) }, (_, offset) => {
    const day = new Date(start);
    day.setDate(day.getDate() + offset);
    return isoDay(day);
  });
}

/* ── Proposta AI ─────────────────────────────────────────────────────────── */

export function parseProposal(json) {
  if (!json) return null;
  try {
    const parsed = JSON.parse(json);
    return parsed && typeof parsed === "object" && !Array.isArray(parsed) ? parsed : null;
  } catch {
    return null;
  }
}

const asDicts = (value) =>
  Array.isArray(value) ? value.filter((v) => v && typeof v === "object" && !Array.isArray(v)) : [];

const num = (value) => (typeof value === "number" && Number.isFinite(value) ? value : null);

/* ── Costruzione ─────────────────────────────────────────────────────────── */

/** Toglie il prefisso «Viaggio a » dal nome, come `destinationTitle`. */
export function destinationTitle(tripName) {
  const prefix = "Viaggio a ";
  return tripName.startsWith(prefix) ? tripName.slice(prefix.length) : tripName;
}

/**
 * Allinea i `dayPlans` salvati ai giorni effettivi del viaggio: uno per data
 * consecutiva, colmando i buchi con la proposta AI o con un giorno sintetico.
 */
function alignedDayPlans(trip, dayPlans, proposal, syntheticText) {
  const dates = tripDateStrings(trip.startDate, dayCountBetween(trip.startDate, trip.endDate));
  const proposalDays = proposal ? asDicts(proposal.dayPlans) : null;
  const destination = destinationTitle(trip.name);

  return dates.map((dateString, index) => {
    const existing = dayPlans.find((p) => p.dateString === dateString);
    if (existing) return existing;

    const fromProposal =
      proposalDays?.find((d) => d.date === dateString) ?? proposalDays?.[index] ?? null;
    if (fromProposal) {
      const location = (fromProposal.location || "").trim();
      return {
        id: `proposal-${dateString}`,
        dateString,
        location: location || destination,
        morningPlan: fromProposal.morningPlan || "",
        afternoonPlan: fromProposal.afternoonPlan || "",
        eveningPlan: fromProposal.eveningPlan || "",
        accommodationName: fromProposal.accommodationName ?? null,
        accommodationType: fromProposal.accommodationType ?? null,
        accommodationCostPerNight: num(fromProposal.accommodationCostPerNight),
        weatherBackupPlan: fromProposal.weatherBackupPlan ?? null,
        estimatedDailyCost: num(fromProposal.estimatedDailyCost),
      };
    }

    return {
      id: `synthetic-${dateString}`,
      dateString,
      location: destination,
      morningPlan: syntheticText.morning(destination, index + 1),
      afternoonPlan: syntheticText.afternoon(destination),
      eveningPlan: syntheticText.evening(destination),
      accommodationName: null,
      accommodationType: null,
      accommodationCostPerNight: null,
      weatherBackupPlan: null,
      estimatedDailyCost: null,
    };
  });
}

function buildDay(plan, dayIndex, proposalDay) {
  const blocks = PERIODS.map((period) =>
    buildBlock(period, plan[period.planKey] || "", asDicts(proposalDay?.[period.stopsKey]))
  ).filter((block) => block.stops.length > 0);

  return {
    id: plan.id,
    dayIndex,
    dateString: plan.dateString,
    location: plan.location,
    dayCost: plan.estimatedDailyCost,
    accommodationName: plan.accommodationName,
    accommodationType: plan.accommodationType,
    accommodationCostPerNight: plan.accommodationCostPerNight,
    weatherBackupPlan: plan.weatherBackupPlan,
    blocks,
  };
}

function buildBlock(period, text, structured) {
  const stops = structured.length
    ? structured.map(parseStructuredStop).filter(Boolean)
    : parseTextStops(text);
  return {
    period: period.key,
    color: period.color,
    stops,
    durationSummary: summarizeDuration(stops),
    costSummary: summarizeCost(stops),
  };
}

const STOP_TITLE_KEYS = ["title", "name", "place", "location", "label", "activity", "description"];

function parseStructuredStop(dict) {
  const title = STOP_TITLE_KEYS.map((key) => (typeof dict[key] === "string" ? dict[key].trim() : ""))
    .find((value) => value.length > 0);
  if (!title) return null;

  const category = stopCategory(dict.category);
  return {
    time: dict.time || dict.startTime || dict.hour || "",
    title,
    detail: formatDetail(
      num(dict.durationMinutes) ?? num(dict.duration),
      num(dict.cost) ?? num(dict.estimatedCost),
      dict.costLabel || dict.price || null
    ),
    emoji: CATEGORY_EMOJI[category],
    category,
  };
}

function stopCategory(raw) {
  if (typeof raw !== "string") return "other";
  const key = raw.toLowerCase();
  return key in CATEGORY_EMOJI ? key : "other";
}

/**
 * Divide sul separatore solo fuori dalle parentesi.
 *
 * Il « · » separa le tappe, ma compare anche DENTRO il dettaglio di una tappa —
 * «Museo (2h · ~15)». Tagliando alla cieca quella riga diventava due tappe
 * monche, «Museo (2h» e «~15)», ed era così che l'utente le vedeva.
 */
function splitOutsideParentheses(text, separator) {
  const parts = [];
  let current = "";
  let depth = 0;
  let index = 0;

  while (index < text.length) {
    if (depth === 0 && text.startsWith(separator, index)) {
      parts.push(current);
      current = "";
      index += separator.length;
      continue;
    }
    const character = text[index];
    if (character === "(") depth += 1;
    if (character === ")") depth = Math.max(depth - 1, 0);
    current += character;
    index += 1;
  }
  parts.push(current);
  return parts;
}

/** Il testo libero del giorno diventa tappe: una riga (o un « · ») per tappa. */
function parseTextStops(text) {
  const trimmed = (text || "").trim();
  if (!trimmed) return [];

  const lines = trimmed
    .split(/\r?\n/)
    .flatMap((line) => splitOutsideParentheses(line, " · "))
    .map((line) => line.trim())
    .filter(Boolean);

  // Anche la riga unica passa da `parseTextLine`: prima finiva tale e quale nel
  // titolo, orario e parentesi compresi, perché «non c'era niente da separare».
  // Ma l'orario e il dettaglio ci sono lo stesso.
  return lines.map((line) => parseTextLine(line)).filter(Boolean);
}

function parseTextLine(line) {
  const trimmed = line.trim();
  if (!trimmed) return null;

  const match = /^(\d{1,2}:\d{2})\s*[-–—]?\s*(.+)$/.exec(trimmed);
  if (match) {
    const [title, detail] = splitTitleDetail(match[2]);
    return textStop(title, detail, match[1]);
  }
  // Anche senza orario il dettaglio va staccato: «Museo Faggiano (1h · ~8)» è un
  // titolo più un dettaglio, e lasciandoli attaccati il riepilogo di fascia non
  // trovava né la durata né il costo.
  const [title, detail] = splitTitleDetail(trimmed);
  return textStop(title, detail, "");
}

function textStop(title, detail, time) {
  const category = categoryForTitle(title);
  return { time, title, detail, emoji: CATEGORY_EMOJI[category], category };
}

/**
 * Ultima coppia di parentesi di PRIMO livello.
 *
 * Si prendevano l'ultima « ( » e l'ultima « ) » qualunque fossero: con un
 * dettaglio annidato — «Tour guidato (centro storico (con guida) · 2h)» — il
 * taglio cadeva sulla parentesi interna e il titolo si portava dietro mezzo
 * dettaglio.
 */
function topLevelParentheses(text) {
  let depth = 0;
  let open = -1;
  let result = null;

  for (let index = 0; index < text.length; index += 1) {
    const character = text[index];
    if (character === "(") {
      if (depth === 0) open = index;
      depth += 1;
    } else if (character === ")") {
      depth = Math.max(depth - 1, 0);
      if (depth === 0 && open >= 0) {
        result = [open, index];
        open = -1;
      }
    }
  }
  // Parentesi aperta e mai chiusa: vale fino a fine riga. Il testo dell'AI ogni
  // tanto la dimentica, e senza questo ramo «Passeggiata (2h · ~5» restava tutto
  // nel titolo, durata e costo persi. Un `open` rimasto qui è per forza
  // successivo all'ultima coppia chiusa, quindi vince lui.
  if (open >= 0) result = [open, text.length];
  return result;
}

/** «Museo (2h · ~15)» → titolo e dettaglio; in mancanza di parentesi, il « · ». */
function splitTitleDetail(rest) {
  const parentheses = topLevelParentheses(rest);
  if (parentheses) {
    const [open, close] = parentheses;
    return [rest.slice(0, open).trim(), rest.slice(open + 1, close).replace(/•/g, "·")];
  }
  const sep = rest.indexOf(" · ");
  if (sep >= 0) return [rest.slice(0, sep), rest.slice(sep + 3)];
  return [rest, ""];
}

function formatDetail(durationMinutes, cost, costLabel) {
  const parts = [];
  if (durationMinutes && durationMinutes > 0) {
    const h = Math.floor(durationMinutes / 60);
    const m = durationMinutes % 60;
    parts.push(durationMinutes < 60 ? `${durationMinutes}m` : m === 0 ? `${h}h` : `${h}h ${m}m`);
  }
  if (costLabel) parts.push(costLabel);
  else if (cost != null) parts.push(cost <= 0 ? "Gratis" : `~${Math.round(cost)}`);
  return parts.join(" · ");
}

/**
 * Durata e costo di una tappa si leggono dallo stesso `detail`, che è
 * «1h 30m · ~45»: prima la durata, poi il prezzo. Serve un pattern solo per
 * entrambe le letture, perché l'una si trova togliendo l'altra.
 */
const DURATION = /(\d+)\s*h(?:\s*(\d+)\s*m)?|(\d+)\s*m/;

/**
 * Minuti della tappa: «1h 30m» sono 90, non 30.
 *
 * Si cercava solo `(\d+)\s*m`, che su «1h 30m» trovava i minuti e buttava via
 * le ore: il riepilogo diceva «30m» per una mattinata da un'ora e mezza.
 */
function stopMinutes(detail) {
  const withHours = /(\d+)\s*h(?:\s*(\d+)\s*m)?/.exec(detail);
  if (withHours) return Number(withHours[1]) * 60 + Number(withHours[2] || 0);
  const onlyMinutes = /(\d+)\s*m/.exec(detail);
  return onlyMinutes ? Number(onlyMinutes[1]) : null;
}

/**
 * Costo della tappa, cercato DOPO aver tolto la durata.
 *
 * Prima si prendeva il primo numero del dettaglio: su «1h 15m · ~45» quello è
 * l'ora, non il prezzo, e la somma di fascia ne usciva senza senso — tre tappe
 * da ~45, ~12 e ~60 facevano «~3».
 */
function stopCost(detail) {
  const withoutDuration = detail.replace(DURATION, " ");
  if (/gratis/i.test(withoutDuration)) return null;
  const match = /~?\s*(\d+(?:[.,]\d+)?)/.exec(withoutDuration);
  return match ? Number(match[1].replace(",", ".")) : null;
}

function summarizeDuration(stops) {
  const minutes = stops.reduce((total, stop) => total + (stopMinutes(stop.detail) ?? 0), 0);
  if (minutes <= 0) return "";
  const h = Math.floor(minutes / 60);
  const m = minutes % 60;
  if (h === 0) return `${m}m`;
  return m === 0 ? `${h}h` : `${h}h ${m}m`;
}

/** Somma senza la tilde: la mette chi la mostra. */
function summarizeCost(stops) {
  const values = stops.map((stop) => stopCost(stop.detail)).filter((value) => value != null);
  if (!values.length) return "";
  const sum = values.reduce((a, b) => a + b, 0);
  return sum > 0 ? Math.round(sum) : "";
}

const FOOD_NEEDLES = [
  "ristor", "trattoria", "osteria", "pizzeria", "enoteca", "taverna", "locanda",
  "bistrot", "bacaro", "friggitoria", "gastronomia", "street food", "mercato",
  "degustazione", "cucina", "pranzo", "cena", "colazione", "aperitivo", "brunch",
  "gelateria", "pasticceria", "panificio", "pescheria", "food",
];

function categoryForTitle(title) {
  const lower = title.toLowerCase();
  if (lower.includes("aeroport") || lower.includes("volo") || lower.includes("flight")) return "flight";
  if (lower.includes("taxi") || lower.includes("bus") || lower.includes("traghetto") || lower.includes("metro")) return "transport";
  if (FOOD_NEEDLES.some((needle) => lower.includes(needle))) return "food";
  if (lower.includes("hotel") || lower.includes("suite") || lower.includes("bb")) return "hotel";
  if (lower.includes("muse") || lower.includes("castell") || lower.includes("chiesa")) return "culture";
  if (lower.includes("spiagg") || lower.includes("marina")) return "beach";
  return "other";
}

/**
 * Ripartizione del budget: quella dichiarata dall'AI se c'è, altrimenti la
 * stessa stima per quote di `budgetBreakdown` su iOS.
 */
function budgetBreakdown(dict, estimatedTotal, dayPlans, legs) {
  if (dict && typeof dict === "object") {
    return {
      hotels: num(dict.hotels) ?? 0,
      flights: num(dict.flights) ?? 0,
      restaurants: num(dict.restaurants) ?? 0,
      activities: num(dict.activities) ?? 0,
    };
  }

  const hotelNights = dayPlans.reduce((sum, p) => sum + (p.accommodationCostPerNight ?? 0), 0);
  const hotels =
    hotelNights > 0 ? hotelNights * Math.max(dayPlans.length - 1, 1) : estimatedTotal * 0.35;
  const flights = legs.some((l) => l.transportMode === "flight")
    ? estimatedTotal * 0.28
    : estimatedTotal * 0.1;
  const restaurants = estimatedTotal * 0.18;
  const activities = Math.max(
    estimatedTotal - hotels - flights - restaurants,
    estimatedTotal * 0.12
  );
  return { hotels, flights, restaurants, activities };
}

/**
 * Nomi dei partecipanti da `participantIdsJson`. `formatAge` è passato dal
 * chiamante perché l'età va scritta nella lingua della web app, non in quella
 * cablata nel modello iOS.
 */
export function travelerNames({ participantIdsJson, members, children, formatAge }) {
  let ids = [];
  try {
    const parsed = JSON.parse(participantIdsJson || "[]");
    if (Array.isArray(parsed)) ids = parsed.filter((id) => typeof id === "string");
  } catch {
    ids = [];
  }
  if (!ids.length) return [];

  return ids
    .map((id) => {
      const child = children.find((c) => c.id === id);
      if (child) {
        const age = formatAge(child.birthDate?.toMillis?.() ?? child.birthDate ?? null);
        return age ? `${child.name} (${age})` : child.name;
      }
      const member = members.find((m) => m.userId === id || m.id === id);
      return member ? member.displayName || member.name || null : null;
    })
    .filter(Boolean);
}

/** Vista completa dell'itinerario, equivalente di `TravelItineraryOverview`. */
export function buildOverview({ trip, dayPlans, legs, syntheticText }) {
  const proposal = parseProposal(trip.aiProposalJson);
  const tripMeta = proposal?.trip && typeof proposal.trip === "object" ? proposal.trip : null;

  const declaredTotal = num(tripMeta?.estimatedTotalCost);
  const estimated =
    declaredTotal ?? dayPlans.reduce((sum, p) => sum + (p.estimatedDailyCost ?? 0), 0);
  const total = estimated > 0 ? estimated : trip.budgetTotal;

  const aligned = alignedDayPlans(trip, dayPlans, proposal, syntheticText);
  const proposalDays = proposal ? asDicts(proposal.dayPlans) : null;

  return {
    destinationTitle: destinationTitle(trip.name),
    dayCount: dayCountBetween(trip.startDate, trip.endDate),
    estimatedTotal: total,
    budgetLimit: trip.budgetTotal,
    currency: tripMeta?.currency || trip.currency,
    summary: typeof tripMeta?.summary === "string" ? tripMeta.summary : "",
    budget: budgetBreakdown(tripMeta?.budgetBreakdown, total, dayPlans, legs),
    days: aligned.map((plan, index) => {
      const proposalDay =
        proposalDays?.find((d) => d.date === plan.dateString) ?? proposalDays?.[index] ?? null;
      return buildDay(plan, index + 1, proposalDay);
    }),
  };
}

/** «1.234 €» come `formatMoney` su iOS: intero, simbolo dopo. */
export function formatMoney(value, currency) {
  const symbol = (currency || "EUR").toUpperCase() === "EUR" ? "€" : currency;
  return `${Math.round(value || 0).toLocaleString("it-IT")} ${symbol}`;
}

/**
 * Destinazione da mostrare in copertina, come `primaryDestination`: l'arrivo
 * dell'ultima tratta, altrimenti la coda del nome dopo un separatore.
 *
 * Nella lista le tratte non ci sono — servirebbe un listener per ogni viaggio
 * su una sottocollezione — quindi lì si ragiona sul solo nome, che è il caso
 * che iOS copre con lo stesso ramo.
 */
export function primaryDestination(tripName, legs = []) {
  const lastLeg = [...legs].sort((a, b) => a.order - b.order).at(-1);
  const arrival = (lastLeg?.toLocation || "").trim();
  if (arrival) return arrival;

  const name = (tripName || "").trim();
  for (const separator of [" – ", " - ", " — ", " a ", " in ", " per ", " verso ", ", "]) {
    const at = name.toLowerCase().lastIndexOf(separator.toLowerCase());
    if (at < 0) continue;
    const tail = name.slice(at + separator.length).trim();
    if (tail.length >= 2) return tail;
  }
  return name;
}
