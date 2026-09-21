/**
 * Filtro temporale delle liste di Salute — porting di `TreatmentTimeFilter`,
 * `ExamTimeFilter` e `VaccineTimeFilter` di iOS: tutti, ultimi 3 mesi, ultimi
 * 6 mesi, ultimo anno, o un intervallo «da – a» scelto a mano.
 *
 * La data di riferimento la decide ogni modulo (visita: `date`; esame:
 * scadenza o creazione; cura: la più recente fra inizio e fine; vaccino:
 * somministrazione, prenotazione o aggiornamento), come sul telefono.
 */
import { fromDateInput, toDateInput } from "./shared";

export const PERIOD_KINDS = ["all", "m3", "m6", "y1", "custom"];

export const emptyPeriod = () => ({ kind: "all", from: null, to: null });

/** Limite inferiore del periodo rapido, in millisecondi; `null` = nessuno. */
function cutoff(period) {
  const d = new Date();
  switch (period.kind) {
    case "m3":
      d.setMonth(d.getMonth() - 3);
      return d.getTime();
    case "m6":
      d.setMonth(d.getMonth() - 6);
      return d.getTime();
    case "y1":
      d.setFullYear(d.getFullYear() - 1);
      return d.getTime();
    case "custom": {
      // «Da» è inclusivo dall'inizio del giorno: `fromDateInput` restituisce
      // mezzogiorno, che taglierebbe la mattina.
      if (period.from == null) return null;
      const start = new Date(period.from);
      start.setHours(0, 0, 0, 0);
      return start.getTime();
    }
    default:
      return null;
  }
}

/**
 * `true` se la data di riferimento sta nel periodo. Un elemento senza data
 * passa solo con «Tutti»: nasconderlo per un filtro che non può valutare
 * sarebbe una sparizione silenziosa.
 */
export function inPeriod(ref, period) {
  if (!period || period.kind === "all") return true;
  if (!ref) return false;
  const from = cutoff(period);
  if (from != null && ref < from) return false;
  if (period.kind === "custom" && period.to != null) {
    // «A» è inclusivo: fino alla fine di quel giorno, come sul telefono.
    const end = new Date(period.to);
    end.setDate(end.getDate() + 1);
    end.setHours(0, 0, 0, 0);
    if (ref >= end.getTime()) return false;
  }
  return true;
}

export default function PeriodFilter({ value, onChange, h, tint }) {
  const p = h.period;
  const labels = { all: p.all, m3: p.m3, m6: p.m6, y1: p.y1, custom: p.custom };

  const setCustom = (patch) => {
    let next = { ...value, kind: "custom", ...patch };
    // Da > A: si scambiano invece di produrre una lista vuota.
    if (next.from != null && next.to != null && next.from > next.to) {
      next = { ...next, from: next.to, to: next.from };
    }
    onChange(next);
  };

  return (
    <div className="sa-period">
      {PERIOD_KINDS.map((kind) => {
        const on = value.kind === kind;
        return (
          <button
            key={kind}
            className={"sa-chip" + (on ? " on" : "")}
            style={on ? { background: tint || "var(--accent)" } : undefined}
            onClick={() =>
              onChange(kind === "custom" ? { ...value, kind } : { kind, from: null, to: null })
            }
          >
            {labels[kind]}
          </button>
        );
      })}
      {value.kind === "custom" && (
        <span className="sa-period-range">
          <label>
            {p.from}
            <input
              type="date"
              value={toDateInput(value.from)}
              onChange={(e) => setCustom({ from: fromDateInput(e.target.value) })}
            />
          </label>
          <label>
            {p.to}
            <input
              type="date"
              value={toDateInput(value.to)}
              onChange={(e) => setCustom({ to: fromDateInput(e.target.value) })}
            />
          </label>
        </span>
      )}
    </div>
  );
}
