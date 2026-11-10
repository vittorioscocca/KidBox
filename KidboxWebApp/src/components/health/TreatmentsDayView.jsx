/**
 * Cure — vista per giorno con linea del tempo (porting di `TreatmentsCalendarView`
 * su iOS): in alto il giorno, sotto le ore e le dosi di tutte le cure come card
 * piccole sull'ora giusta, con preso (con orario) / saltato / annulla.
 *
 * Le dosi si calcolano dalla cura (data di inizio, durata, orari, intervallo) e dai
 * log: stesso id deterministico di iOS e Android (`dose_<cura>_<giorno>_<slot>`),
 * quindi ciò che si registra qui lo vede il telefono e viceversa. Un log con
 * `taken: false` è una dose «saltata»; annullare lo marca `isDeleted`, come iOS.
 *
 * Se in un'ora ci sono più dosi le card si impilano e la riga dell'ora si allunga.
 */
import { useEffect, useMemo, useRef, useState } from "react";
import Modal from "../Modal";
import { doseLogId, isScheduledDoseDay } from "../../services/health";

const CARD_H = 50;
const CARD_GAP = 4;
const MIN_HOUR_H = 44;
const DAY_MS = 86400000;

// Un colore stabile per cura (per posizione fra le cure ordinate per id).
const PALETTE = [
  [149, 115, 217],
  [51, 133, 242],
  [26, 173, 158],
  [235, 87, 140],
  [242, 140, 38],
  [97, 92, 217],
];

/** Giorno di calendario locale come numero intero (indipendente dall'ora legale). */
const dayNumberOf = (ms) => {
  const d = new Date(ms);
  return Math.round(Date.UTC(d.getFullYear(), d.getMonth(), d.getDate()) / DAY_MS);
};
const dateOfDayNumber = (n) => {
  const u = new Date(n * DAY_MS);
  return new Date(u.getUTCFullYear(), u.getUTCMonth(), u.getUTCDate());
};

/** Minuti dalla mezzanotte di "08:30" / "8.30"; `null` se illeggibile. */
const parseMinutes = (time) => {
  const parts = String(time || "")
    .trim()
    .replace(/[.,]/g, ":")
    .split(":")
    .map((x) => x.trim())
    .filter(Boolean);
  if (!parts.length) return null;
  const h = Number(parts[0]);
  if (!Number.isInteger(h) || h < 0 || h > 23) return null;
  const m = Number((parts[1] || "0").replace(/\D/g, "").slice(0, 2)) || 0;
  return h * 60 + Math.min(Math.max(m, 0), 59);
};

const hhmm = (ms, locale) =>
  new Date(ms).toLocaleTimeString(locale, { hour: "2-digit", minute: "2-digit" });

const upperFirst = (s) => s.charAt(0).toUpperCase() + s.slice(1);

export default function TreatmentsDayView({ treatments, doseLogs, c, locale, onTake, onSkip, onUndo, onOpen }) {
  const d = c.day;
  const todayN = dayNumberOf(Date.now());
  const [dayN, setDayN] = useState(todayN);
  const [confirm, setConfirm] = useState(null);

  // Dal primo giorno utile (cura più vecchia, almeno una settimana fa) all'ultimo
  // (fine della cura più lunga, almeno due settimane avanti).
  const [lo, hi] = useMemo(() => {
    let a = todayN - 7;
    let b = todayN + 14;
    for (const t of treatments) {
      const s = dayNumberOf(t.startDate);
      a = Math.min(a, s);
      b = Math.max(b, t.isLongTerm ? todayN + 30 : s + t.durationDays - 1);
    }
    return [Math.max(a, todayN - 400), Math.min(b, todayN + 400)];
  }, [treatments, todayN]);
  const go = (delta) => setDayN((n) => Math.min(hi, Math.max(lo, n + delta)));

  // Frecce della tastiera (non quando si sta scrivendo in un campo).
  useEffect(() => {
    const onKey = (e) => {
      const tag = e.target?.tagName;
      if (tag === "INPUT" || tag === "TEXTAREA" || tag === "SELECT") return;
      if (e.key === "ArrowLeft") go(-1);
      if (e.key === "ArrowRight") go(1);
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [lo, hi]);

  const touch = useRef(null);

  const logIndex = useMemo(() => {
    const m = new Map();
    for (const l of doseLogs) if (!l.isDeleted) m.set(l.id, l);
    return m;
  }, [doseLogs]);

  const colorIndex = useMemo(() => treatments.map((t) => t.id).sort(), [treatments]);
  const colorOf = (t) => PALETTE[Math.max(0, colorIndex.indexOf(t.id)) % PALETTE.length];

  const dosesOn = (n) => {
    const out = [];
    for (const t of treatments) {
      const offset = n - dayNumberOf(t.startDate);
      if (offset < 0) continue;
      if (!t.isLongTerm && offset >= t.durationDays) continue;
      if (!isScheduledDoseDay(t, offset)) continue;
      const times = t.scheduleTimes || [];
      const slots = t.intervalBetweenDosesDays > 0 ? [0] : times.map((_, i) => i);
      const dayNumber = offset + 1;
      for (const slot of slots) {
        const time = times[slot] ?? times[0] ?? "08:00";
        const log = logIndex.get(doseLogId(t.id, dayNumber, slot));
        // Cura interrotta: restano solo le dosi già registrate.
        if (t.isActive === false && !log) continue;
        const minutes = parseMinutes(time);
        out.push({
          treatment: t,
          dayNumber,
          slot,
          time,
          minutes: minutes ?? Number.MAX_SAFE_INTEGER,
          hour: minutes == null ? 8 : Math.min(23, Math.floor(minutes / 60)),
          state: !log ? "pending" : log.taken ? "taken" : "skipped",
          takenAt: log?.taken ? log.takenAt : null,
          future: n > todayN,
          past: n < todayN,
        });
      }
    }
    return out.sort(
      (a, b) =>
        a.minutes - b.minutes || a.treatment.drugName.localeCompare(b.treatment.drugName)
    );
  };

  const doses = dosesOn(dayN);
  const done = doses.filter((x) => x.state !== "pending").length;
  const date = dateOfDayNumber(dayN);
  const sameYear = date.getFullYear() === new Date().getFullYear();
  const title = upperFirst(
    date.toLocaleDateString(locale, {
      weekday: "long",
      day: "numeric",
      month: "long",
      ...(sameYear ? {} : { year: "numeric" }),
    })
  );
  const rel = { [-1]: d.yesterday, 0: d.today, 1: d.tomorrow }[dayN - todayN] || null;

  // Altezze di riga e posizione di ogni ora.
  const byHour = new Map();
  for (const x of doses) byHour.set(x.hour, [...(byHour.get(x.hour) || []), x]);
  const heights = Array.from({ length: 24 }, (_, h) =>
    Math.max(MIN_HOUR_H, (byHour.get(h)?.length || 0) * (CARD_H + CARD_GAP) + CARD_GAP)
  );
  const tops = [];
  heights.reduce((acc, h, i) => ((tops[i] = acc), acc + h), 0);

  // La scroll parte un'ora prima dell'ora attuale (oggi) o della prima dose.
  const scrollRef = useRef(null);
  const startHour =
    dayN === todayN
      ? Math.max(0, new Date().getHours() - 1)
      : doses.length
        ? Math.max(0, Math.min(...doses.map((x) => x.hour)) - 1)
        : 7;
  useEffect(() => {
    if (scrollRef.current) scrollRef.current.scrollTop = tops[startHour];
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [dayN]);

  const [now, setNow] = useState(() => new Date());
  useEffect(() => {
    const id = setInterval(() => setNow(new Date()), 60000);
    return () => clearInterval(id);
  }, []);
  const nowY = tops[now.getHours()] + heights[now.getHours()] * (now.getMinutes() / 60);
  const nowMinutes = now.getHours() * 60 + now.getMinutes();

  const rgba = (rgb, a) => `rgba(${rgb[0]}, ${rgb[1]}, ${rgb[2]}, ${a})`;

  return (
    <div
      className="td-wrap"
      onTouchStart={(e) => {
        touch.current = { x: e.touches[0].clientX, y: e.touches[0].clientY };
      }}
      onTouchEnd={(e) => {
        const s = touch.current;
        touch.current = null;
        if (!s) return;
        const dx = e.changedTouches[0].clientX - s.x;
        const dy = e.changedTouches[0].clientY - s.y;
        if (Math.abs(dx) > 60 && Math.abs(dx) > Math.abs(dy) * 1.5) go(dx < 0 ? 1 : -1);
      }}
    >
      <div className="td-head">
        <button className="td-nav" onClick={() => go(-1)} disabled={dayN <= lo} aria-label={d.prev}>
          ‹
        </button>
        <button className="td-title" onClick={() => setDayN(todayN)} disabled={dayN === todayN}>
          {rel && <span className="td-rel">{rel}</span>}
          <strong>{title}</strong>
          <span className={"td-count" + (doses.length && done === doses.length ? " ok" : "")}>
            {doses.length ? d.dosesCount(done, doses.length) : " "}
          </span>
        </button>
        <button className="td-nav" onClick={() => go(1)} disabled={dayN >= hi} aria-label={d.next}>
          ›
        </button>
      </div>

      {doses.length === 0 && <p className="td-empty">{d.empty}</p>}

      <div className="td-scroll" ref={scrollRef}>
        <div className="td-grid">
          {Array.from({ length: 24 }, (_, h) => (
            <div key={h} className="td-row" style={{ height: heights[h] }}>
              <span className="td-hour">{String(h).padStart(2, "0")}:00</span>
              <div className="td-slot">
                {(byHour.get(h) || []).map((x) => {
                  const rgb = colorOf(x.treatment);
                  const overdue =
                    x.state === "pending" && !x.future && (x.past || x.minutes < nowMinutes);
                  const v = x.treatment.dosageValue;
                  return (
                    <div
                      key={`${x.treatment.id}|${x.dayNumber}|${x.slot}`}
                      className={"td-card " + x.state}
                      style={{
                        height: CARD_H,
                        borderLeftColor: `rgb(${rgb.join(",")})`,
                        background: rgba(rgb, x.state === "taken" ? 0.1 : 0.18),
                      }}
                      onClick={() => onOpen(x.treatment.id)}
                    >
                      <span className="td-card-body">
                        <span className="td-card-line">
                          {x.state === "taken" && <span className="td-ic ok">✓</span>}
                          {x.state === "skipped" && <span className="td-ic skip">✕</span>}
                          <span className="td-time">{x.time}</span>
                          <strong>{x.treatment.drugName}</strong>
                        </span>
                        <span className="td-card-sub">
                          <span style={{ color: `rgb(${rgb.join(",")})` }}>
                            {v} {x.treatment.dosageUnit}
                          </span>
                          {x.state === "taken" && x.takenAt ? (
                            <span className="td-ok">{d.takenAt(hhmm(x.takenAt, locale))}</span>
                          ) : x.state === "skipped" ? (
                            <span className="td-skip">{d.skipped}</span>
                          ) : overdue ? (
                            <span className="td-late">{d.notLogged}</span>
                          ) : null}
                        </span>
                      </span>
                      <span className="td-actions" onClick={(e) => e.stopPropagation()}>
                        {x.state === "taken" || x.state === "skipped" ? (
                          <button
                            className={"td-pill " + (x.state === "taken" ? "taken" : "skipped")}
                            onClick={() => onUndo(x.treatment, x.dayNumber, x.slot)}
                          >
                            {x.state === "taken" ? d.undo : d.resume}
                          </button>
                        ) : x.future || x.treatment.isActive === false ? null : (
                          <>
                            <button
                              className="td-circle"
                              title={d.markSkipped}
                              aria-label={d.markSkipped}
                              onClick={() => onSkip(x.treatment, x.dayNumber, x.slot, x.time)}
                            >
                              ✕
                            </button>
                            <button
                              className="td-circle go"
                              title={d.markTaken}
                              aria-label={d.markTaken}
                              onClick={() => setConfirm(x)}
                            >
                              ✓
                            </button>
                          </>
                        )}
                      </span>
                    </div>
                  );
                })}
              </div>
            </div>
          ))}
          {dayN === todayN && (
            <div className="td-now" style={{ top: nowY }}>
              <span />
            </div>
          )}
        </div>
      </div>

      {confirm && (
        <ConfirmDose
          dose={confirm}
          dayTitle={title}
          d={d}
          onClose={() => setConfirm(null)}
          onConfirm={async (at) => {
            const x = confirm;
            setConfirm(null);
            await onTake(x.treatment, x.dayNumber, x.slot, x.time, at);
          }}
        />
      )}
    </div>
  );
}

/** «Quando hai dato la medicina?»: adesso, 30 min / 1 / 2 ore fa, oppure data e ora. */
function ConfirmDose({ dose, dayTitle, d, onClose, onConfirm }) {
  const toInput = (ms) => {
    const x = new Date(ms);
    const p = (n) => String(n).padStart(2, "0");
    return `${x.getFullYear()}-${p(x.getMonth() + 1)}-${p(x.getDate())}T${p(x.getHours())}:${p(x.getMinutes())}`;
  };
  const [value, setValue] = useState(() => toInput(Date.now()));
  const quick = [
    [d.quickNow, 0],
    [d.quick30, 30],
    [d.quick60, 60],
    [d.quick120, 120],
  ];
  const t = dose.treatment;
  const takenAt = Math.min(new Date(value).getTime() || Date.now(), Date.now());

  return (
    <Modal onClose={onClose}>
      <div className="modal-header">
        <button className="modal-text-btn" onClick={onClose}>
          {d.undo}
        </button>
        <strong>{d.confirmTitle}</strong>
        <span />
      </div>
      <div className="modal-body">
        <p style={{ margin: 0 }}>
          <strong>{t.drugName}</strong> · {t.dosageValue} {t.dosageUnit}
        </p>
        <p className="pw-hint" style={{ margin: "4px 0 12px" }}>
          {dayTitle} · {d.scheduledAt(dose.time)}
        </p>
        <p style={{ margin: "0 0 8px" }}>{d.confirmQuestion}</p>
        <div className="td-quick">
          {quick.map(([label, minutesAgo]) => (
            <button
              key={minutesAgo}
              className="td-quick-btn"
              onClick={() => setValue(toInput(Date.now() - minutesAgo * 60000))}
            >
              {label}
            </button>
          ))}
        </div>
        <label className="td-dt">
          <span>{d.dateTime}</span>
          <input
            type="datetime-local"
            value={value}
            max={toInput(Date.now())}
            onChange={(e) => setValue(e.target.value)}
          />
        </label>
        <button className="pw-btn-primary" style={{ width: "100%", marginTop: 14 }} onClick={() => onConfirm(takenAt)}>
          {d.confirmDose}
        </button>
      </div>
    </Modal>
  );
}
