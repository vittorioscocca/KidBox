/**
 * Pezzi comuni ai moduli di Salute: intestazione con il tasto indietro,
 * formattazione delle date e le due utilità di conversione fra i millisecondi
 * usati in memoria e il valore che gli `<input type="date">` si aspettano.
 */

export function ModuleHeader({ title, onBack, backLabel, children }) {
  return (
    <header className="sa-module-header">
      <button className="sa-back" onClick={onBack}>
        ← {backLabel}
      </button>
      <h2>{title}</h2>
      <span className="sa-spacer" />
      {children}
    </header>
  );
}

export const localeTag = (locale) => (locale === "en" ? "en-US" : "it-IT");

export const label = (info, locale) =>
  info ? (locale === "en" ? info.en : info.it) : "";

export const fmtDate = (millis, locale) =>
  millis
    ? new Date(millis).toLocaleDateString(localeTag(locale), {
        day: "2-digit",
        month: "short",
        year: "numeric",
      })
    : "";

export const fmtDateLong = (millis, locale) =>
  millis
    ? new Date(millis).toLocaleDateString(localeTag(locale), {
        weekday: "short",
        day: "2-digit",
        month: "long",
      })
    : "";

/** `yyyy-MM-dd` in ora locale: `toISOString()` sposterebbe il giorno a UTC. */
export function toDateInput(millis) {
  if (!millis) return "";
  const d = new Date(millis);
  const pad = (n) => String(n).padStart(2, "0");
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
}

/** Mezzogiorno locale: mette al riparo dal cambio di giorno sui fusi negativi. */
export function fromDateInput(value) {
  if (!value) return null;
  const [y, m, d] = value.split("-").map(Number);
  if (!y || !m || !d) return null;
  return new Date(y, m - 1, d, 12, 0, 0, 0).getTime();
}

/** Campo di form con etichetta, nella stessa forma in tutti i moduli. */
export function Field({ label: text, children }) {
  return (
    <label className="sa-field">
      {text}
      {children}
    </label>
  );
}

/** Riga «etichetta / valore» del pannello di dettaglio. Sparisce se vuota. */
export function DetailRow({ label: text, value }) {
  if (value === null || value === undefined || value === "") return null;
  return (
    <div className="pw-detail-row">
      <span className="pw-detail-label">{text}</span>
      <span className="pw-detail-value">{value}</span>
    </div>
  );
}

export const newId = () =>
  typeof crypto !== "undefined" && crypto.randomUUID
    ? crypto.randomUUID()
    : `${Date.now()}-${Math.random().toString(16).slice(2)}`;
