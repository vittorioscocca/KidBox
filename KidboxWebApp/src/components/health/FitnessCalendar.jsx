import { useEffect, useMemo, useState } from "react";
import {
  planRange,
  sessionsOn,
  sessionStatusInfo,
  startOfDayMillis,
  weekIndexFor,
} from "../../services/fitnessPlan";

/**
 * Calendario del piano fitness, come la `calendarCard` di iOS: griglia del mese
 * con lo stato delle sedute, giorno selezionato, e sotto le sedute di quel
 * giorno. Le frecce non escono dall'arco coperto dal piano.
 */
export default function FitnessCalendar({ plan, locale, f, renderSession }) {

  const today = startOfDayMillis(Date.now());
  const [selectedDay, setSelectedDay] = useState(today);

  const range = useMemo(() => planRange(plan), [plan]);

  const startOfMonth = (millis) => {
    const d = new Date(millis);
    return new Date(d.getFullYear(), d.getMonth(), 1).getTime();
  };

  const [month, setMonth] = useState(() => startOfMonth(today));

  // All'apertura si parte dal mese del giorno selezionato, e il mese segue la
  // selezione: com'è su iOS.
  useEffect(() => {
    setMonth(startOfMonth(selectedDay));
  }, [selectedDay]);

  // La settimana inizia di lunedì dove è la convenzione, di domenica in inglese.
  const firstWeekday = locale === "en" ? 0 : 1;

  const weekdayLabels = useMemo(() => {
    const fmt = new Intl.DateTimeFormat(locale === "en" ? "en-US" : "it-IT", { weekday: "narrow" });
    // 4 gennaio 1970 era una domenica: base comoda per generare i sette nomi.
    return Array.from({ length: 7 }, (_, i) =>
      fmt.format(new Date(Date.UTC(1970, 0, 4 + ((firstWeekday + i) % 7))))
    );
  }, [locale, firstWeekday]);

  const cells = useMemo(() => {
    const d = new Date(month);
    const year = d.getFullYear();
    const m = d.getMonth();
    const daysInMonth = new Date(year, m + 1, 0).getDate();
    const leading = (new Date(year, m, 1).getDay() - firstWeekday + 7) % 7;
    return [
      ...Array.from({ length: leading }, () => null),
      ...Array.from({ length: daysInMonth }, (_, i) => new Date(year, m, i + 1).getTime()),
    ];
  }, [month, firstWeekday]);

  const monthTitle = new Intl.DateTimeFormat(locale === "en" ? "en-US" : "it-IT", {
    month: "long",
    year: "numeric",
  }).format(new Date(month));

  const firstMonth = range ? startOfMonth(range.first) : month;
  const lastMonth = range ? startOfMonth(range.last) : month;
  const canGoBack = month > firstMonth;
  const canGoForward = month < lastMonth;

  const shiftMonth = (delta) => {
    const d = new Date(month);
    setMonth(new Date(d.getFullYear(), d.getMonth() + delta, 1).getTime());
  };

  const weekIndex = weekIndexFor(plan, selectedDay);
  const daySessions = sessionsOn(plan, selectedDay);

  const longDate = new Intl.DateTimeFormat(locale === "en" ? "en-US" : "it-IT", {
    weekday: "long",
    day: "numeric",
    month: "long",
  }).format(new Date(selectedDay));

  return (
    <section className="sa-card fit-cal">
      <div className="fit-cal-head">
        <h3>{f.calendar}</h3>
        {weekIndex != null && <span className="fit-week-badge">{f.week(weekIndex)}</span>}
      </div>

      <div className="fit-cal-month">
        <button type="button" onClick={() => shiftMonth(-1)} disabled={!canGoBack}>
          ‹
        </button>
        <strong>{monthTitle}</strong>
        <button type="button" onClick={() => shiftMonth(1)} disabled={!canGoForward}>
          ›
        </button>
      </div>

      <div className="fit-cal-grid fit-cal-weekdays">
        {weekdayLabels.map((label, i) => (
          <span key={i}>{label}</span>
        ))}
      </div>

      <div className="fit-cal-grid">
        {cells.map((day, i) => {
          if (day === null) return <span key={`empty-${i}`} className="fit-cal-empty" />;
          const sessions = sessionsOn(plan, day);
          const status = sessions[0] ? sessionStatusInfo(sessions[0].status) : null;
          const isSelected = day === selectedDay;
          const isToday = day === today;
          const inPlan = weekIndexFor(plan, day) != null;
          return (
            <button
              type="button"
              key={day}
              className={
                "fit-cal-day" +
                (isSelected ? " selected" : "") +
                (isToday ? " today" : "") +
                (!inPlan ? " outside" : "") +
                (sessions.length > 0 && !isSelected ? " has-session" : "")
              }
              onClick={() => setSelectedDay(day)}
            >
              <span className="fit-cal-num">{new Date(day).getDate()}</span>
              <span
                className="fit-cal-dot"
                style={{ background: status && !isSelected ? status.color : "transparent" }}
              />
            </button>
          );
        })}
      </div>

      <div className="fit-cal-legend">
        {["done", "planned", "skipped"].map((raw) => {
          const info = sessionStatusInfo(raw);
          return (
            <span key={raw}>
              <span className="fit-cal-dot" style={{ background: info.color }} />
              {locale === "en" ? info.en : info.it}
            </span>
          );
        })}
      </div>

      <div className="fit-cal-day-detail">
        <h4>{longDate}</h4>
        {daySessions.length === 0 ? (
          <p className="pw-hint">{f.noSessionsToday}</p>
        ) : (
          daySessions.map((s) => renderSession(s))
        )}
      </div>
    </section>
  );
}
