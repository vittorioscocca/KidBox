// Porting delle funzioni di CalendarView.swift (iOS) / CalendarScreen.kt (Android).
// I nomi rispecchiano gli originali per rendere evidente la corrispondenza.

/** Categorie e colori sono gli stessi di KBEventCategory (KBCalendarEvent.swift). */
export const CATEGORIES = [
  { value: "children", icon: "👶", color: "#F1C40F" },
  { value: "school", icon: "🏫", color: "#3498DB" },
  { value: "health", icon: "🏥", color: "#E74C3C" },
  { value: "family", icon: "👨‍👩‍👧", color: "#2ECC71" },
  { value: "admin", icon: "🧾", color: "#7F8C8D" },
  { value: "leisure", icon: "🎉", color: "#9B59B6" },
];

export function categoryInfo(raw) {
  return CATEGORIES.find((c) => c.value === raw) || CATEGORIES[3];
}

/** In italiano la settimana parte da lunedì, in inglese da domenica. */
export function firstWeekday(locale) {
  return locale === "en" ? 0 : 1;
}

export function startOfDay(date) {
  const d = new Date(date);
  d.setHours(0, 0, 0, 0);
  return d;
}

export function isSameDay(a, b) {
  return (
    a.getFullYear() === b.getFullYear() &&
    a.getMonth() === b.getMonth() &&
    a.getDate() === b.getDate()
  );
}

export function dayKey(date) {
  return `${date.getFullYear()}-${date.getMonth()}-${date.getDate()}`;
}

/**
 * Griglia del mese: celle vuote iniziali per allineare il primo giorno, poi i
 * giorni, poi padding fino a 42 celle (6 righe) — come calendarDays(for:) su iOS,
 * che tiene le card di altezza uniforme anche nella vista annuale.
 */
export function calendarDays(year, month, weekStart) {
  const first = new Date(year, month, 1);
  const daysInMonth = new Date(year, month + 1, 0).getDate();
  const offset = (first.getDay() - weekStart + 7) % 7;

  const cells = new Array(offset).fill(null);
  for (let d = 1; d <= daysInMonth; d += 1) cells.push(new Date(year, month, d));
  while (cells.length < 42) cells.push(null);
  return cells;
}

/** Iniziali dei giorni ruotate sul primo giorno della settimana. */
export function weekdayInitials(locale, weekStart) {
  const fmt = new Intl.DateTimeFormat(locale === "en" ? "en-US" : "it-IT", {
    weekday: "short",
  });
  // 4 gennaio 2026 è una domenica: base stabile per generare i 7 nomi.
  return Array.from({ length: 7 }, (_, i) => {
    const d = new Date(2026, 0, 4 + ((i + weekStart) % 7));
    return fmt.format(d).charAt(0).toUpperCase();
  });
}

/**
 * Un evento occupa un giorno se il suo intervallo lo interseca. Come su iOS, le
 * ricorrenze NON vengono espanse qui: `recurrenceRaw` esiste sul modello ma la
 * vista mese dei client nativi mostra solo l'intervallo start→end.
 */
export function eventOccursOnDay(event, day) {
  const start = event.startDate?.toDate?.();
  const end = event.endDate?.toDate?.() ?? start;
  if (!start) return false;

  const dayStart = startOfDay(day);
  const dayEnd = new Date(dayStart);
  dayEnd.setDate(dayEnd.getDate() + 1);

  const eventStart = start <= end ? start : end;
  const eventEnd = start <= end ? end : start;
  return eventStart < dayEnd && eventEnd >= dayStart;
}

/** Insieme dei giorni (chiave) coperti da almeno un evento, per i pallini. */
export function daysWithEvents(events) {
  const keys = new Set();
  events.forEach((event) => {
    const start = event.startDate?.toDate?.();
    if (!start) return;
    const end = event.endDate?.toDate?.() ?? start;
    let cursor = startOfDay(start <= end ? start : end);
    const last = startOfDay(start <= end ? end : start);
    while (cursor <= last) {
      keys.add(dayKey(cursor));
      cursor = new Date(cursor.getFullYear(), cursor.getMonth(), cursor.getDate() + 1);
    }
  });
  return keys;
}

export function monthTitle(date, locale) {
  const s = new Intl.DateTimeFormat(locale === "en" ? "en-US" : "it-IT", {
    month: "long",
    year: "numeric",
  }).format(date);
  return s.charAt(0).toUpperCase() + s.slice(1);
}

export function monthAbbrev(month, locale) {
  const s = new Intl.DateTimeFormat(locale === "en" ? "en-US" : "it-IT", {
    month: "short",
  }).format(new Date(2026, month, 1));
  return s.charAt(0).toUpperCase() + s.slice(1);
}

export function timeLabel(date, locale) {
  return new Intl.DateTimeFormat(locale === "en" ? "en-US" : "it-IT", {
    hour: "2-digit",
    minute: "2-digit",
  }).format(date);
}

export function toLocalInputValue(date) {
  const pad = (n) => String(n).padStart(2, "0");
  return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(
    date.getDate()
  )}T${pad(date.getHours())}:${pad(date.getMinutes())}`;
}

/* ── Helper per le viste Giorno / Settimana (griglia oraria) ────────────── */

export const HOUR_HEIGHT = 52; // px per ora nella griglia

export function addDays(date, n) {
  const d = new Date(date);
  d.setDate(d.getDate() + n);
  return d;
}

export function startOfWeek(date, weekStart) {
  const d = startOfDay(date);
  const diff = (d.getDay() - weekStart + 7) % 7;
  return addDays(d, -diff);
}

export function weekDays(date, weekStart) {
  const first = startOfWeek(date, weekStart);
  return Array.from({ length: 7 }, (_, i) => addDays(first, i));
}

/** Minuti dalla mezzanotte, usati per posizionare i blocchi evento. */
function minutesFromMidnight(date, day) {
  const dayStart = startOfDay(day);
  return Math.max(0, (date - dayStart) / 60000);
}

/**
 * Posizione verticale e altezza di un evento dentro un giorno.
 * Gli eventi che iniziano prima o finiscono dopo il giorno vengono tagliati ai
 * suoi estremi, così un evento su più giorni si vede su ognuno di essi.
 */
export function eventLayout(event, day) {
  const start = event.startDate?.toDate?.();
  const end = event.endDate?.toDate?.() ?? start;
  if (!start) return null;

  const from = Math.min(minutesFromMidnight(start, day), 1440);
  const to = Math.min(Math.max(minutesFromMidnight(end, day), from + 15), 1440);
  return {
    top: (from / 60) * HOUR_HEIGHT,
    height: Math.max(((to - from) / 60) * HOUR_HEIGHT, 18),
  };
}

/**
 * Affianca gli eventi che si sovrappongono: ognuno riceve una colonna e il
 * numero totale di colonne del suo gruppo, così nessuno copre gli altri.
 */
export function layoutOverlaps(events, day) {
  const items = events
    .map((event) => ({ event, box: eventLayout(event, day) }))
    .filter((x) => x.box)
    .sort((a, b) => a.box.top - b.box.top);

  const groups = [];
  let current = [];
  let groupEnd = -1;

  items.forEach((item) => {
    const itemEnd = item.box.top + item.box.height;
    if (current.length && item.box.top >= groupEnd) {
      groups.push(current);
      current = [];
      groupEnd = -1;
    }
    current.push(item);
    groupEnd = Math.max(groupEnd, itemEnd);
  });
  if (current.length) groups.push(current);

  const result = [];
  groups.forEach((group) => {
    const columns = [];
    group.forEach((item) => {
      let col = columns.findIndex((c) => item.box.top >= c);
      if (col === -1) {
        columns.push(0);
        col = columns.length - 1;
      }
      columns[col] = item.box.top + item.box.height;
      result.push({ ...item, column: col });
    });
    const total = columns.length;
    result
      .filter((r) => group.includes(r))
      .forEach((r) => {
        r.columns = total;
      });
  });
  return result;
}

export function dayTitle(date, locale) {
  const loc = locale === "en" ? "en-US" : "it-IT";
  const dayMonth = new Intl.DateTimeFormat(loc, { day: "numeric", month: "long" }).format(date);
  return { dayMonth, year: date.getFullYear() };
}

export function weekdayName(date, locale, style = "long") {
  const s = new Intl.DateTimeFormat(locale === "en" ? "en-US" : "it-IT", {
    weekday: style,
  }).format(date);
  return s;
}
