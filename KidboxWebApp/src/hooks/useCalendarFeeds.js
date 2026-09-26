import { useEffect, useState } from "react";
import { Timestamp, collection, onSnapshot } from "firebase/firestore";
import { db } from "../firebase";

/**
 * I calendari iscritti da link (feed ICS) della famiglia: scuola, squadra,
 * festività. Li scarica e li rilegge il server (functions/calendarFeeds.js),
 * che salva le occorrenze già espanse dentro il documento del feed: qui si
 * ascolta e basta, una lettura per feed. Gemello di `CalendarFeedStore` (iOS)
 * e `CalendarFeedRepository` (Android).
 *
 * Gli eventi escono nella stessa forma di quelli di KidBox (`startDate` e
 * `endDate` Timestamp, `isAllDay`, `title`), più `_feed` con nome e colore:
 * così il calendario li disegna con le stesse funzioni. Non si salvano mai.
 */
export function useCalendarFeeds(familyId) {
  const [state, setState] = useState({ feeds: [], events: [] });

  useEffect(() => {
    if (!familyId) {
      setState({ feeds: [], events: [] });
      return undefined;
    }
    return onSnapshot(
      collection(db, "families", familyId, "calendarFeeds"),
      (snap) => {
        const feeds = [];
        const events = [];
        snap.docs.forEach((d) => {
          const data = d.data();
          const feed = {
            id: d.id,
            name: data.name || "",
            url: data.url || "",
            colorHex: data.colorHex || FEED_PALETTE[0],
            eventCount: data.eventCount || 0,
            lastError: data.lastError || null,
            truncated: Boolean(data.truncated),
          };
          feeds.push(feed);
          (data.events || []).forEach((e) => {
            const ev = toEvent(e, feed);
            if (ev) events.push(ev);
          });
        });
        feeds.sort((a, b) => a.name.localeCompare(b.name));
        events.sort((a, b) => a.startDate.toMillis() - b.startDate.toMillis());
        setState({ feeds, events });
      },
      () => setState({ feeds: [], events: [] })
    );
  }, [familyId]);

  return state;
}

/** Colori proposti all'iscrizione: gli stessi su iOS e Android. */
export const FEED_PALETTE = ["#5B8DEF", "#E67E22", "#27AE60", "#8E44AD", "#E74C3C", "#16A085"];

/**
 * Tutto il giorno: date "YYYY-MM-DD" (fine esclusa) portate alla mezzanotte
 * LOCALE, così Natale resta il 25 in ogni fuso. A orario: millisecondi.
 * La fine si porta un millisecondo indietro: `eventOccursOnDay` la considera
 * inclusa, e un evento che finisce a mezzanotte comparirebbe anche il giorno dopo.
 */
function toEvent(e, feed) {
  let start;
  let end;
  if (e.a) {
    start = localMidnight(e.s);
    end = localMidnight(e.e) ?? (start ? start + 86400000 : null);
  } else {
    start = typeof e.s === "number" ? e.s : null;
    end = typeof e.e === "number" ? e.e : start;
  }
  if (start == null) return null;
  if (end == null || end < start) end = start;
  if (end > start) end -= 1;
  return {
    id: `feed:${feed.id}|${e.id}`,
    title: e.t || "",
    location: e.l || null,
    notes: e.n || null,
    isAllDay: Boolean(e.a),
    startDate: Timestamp.fromMillis(start),
    endDate: Timestamp.fromMillis(end),
    recurrenceRaw: "none",
    _feed: { id: feed.id, name: feed.name, colorHex: feed.colorHex },
  };
}

function localMidnight(ymd) {
  if (typeof ymd !== "string") return null;
  const [y, m, d] = ymd.split("-").map(Number);
  if (!y || !m || !d) return null;
  return new Date(y, m - 1, d).getTime();
}
