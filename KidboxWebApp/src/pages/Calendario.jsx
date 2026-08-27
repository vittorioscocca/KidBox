import { useEffect, useMemo, useRef, useState } from "react";
import {
  collection,
  doc,
  onSnapshot,
  query,
  serverTimestamp,
  setDoc,
  where,
} from "firebase/firestore";
import { db } from "../firebase";
import { useFamily } from "../FamilyContext";
import { useAuth } from "../AuthContext";
import { useTranslation } from "../i18n/LocaleContext";
import EventEditModal from "../components/EventEditModal";
import {
  HOUR_HEIGHT,
  addDays,
  calendarDays,
  categoryInfo,
  dayKey,
  dayTitle,
  daysWithEvents,
  eventOccursOnDay,
  firstWeekday,
  isSameDay,
  layoutOverlaps,
  monthAbbrev,
  monthTitle,
  startOfDay,
  timeLabel,
  weekDays,
  weekdayInitials,
  weekdayName,
} from "../calendarUtils";
import "./Calendario.css";

const VIEWS = ["day", "week", "month", "year"];
const HOURS = Array.from({ length: 24 }, (_, h) => h);

/* ── Griglia oraria condivisa da Giorno e Settimana ───────────────────── */

function HourGutter() {
  return (
    <div className="hour-gutter">
      {HOURS.map((h) => (
        <div key={h} className="hour-label" style={{ height: HOUR_HEIGHT }}>
          <span>{String(h).padStart(2, "0")}:00</span>
        </div>
      ))}
    </div>
  );
}

function DayColumn({ day, events, onSelectEvent, onCreateAt }) {
  const { locale } = useTranslation();
  const timed = events.filter((e) => !e.isAllDay && eventOccursOnDay(e, day));
  const laid = layoutOverlaps(timed, day);

  return (
    <div
      className="day-column"
      style={{ height: HOUR_HEIGHT * 24 }}
      onDoubleClick={(e) => {
        const y = e.clientY - e.currentTarget.getBoundingClientRect().top;
        const hour = Math.max(0, Math.min(23, Math.floor(y / HOUR_HEIGHT)));
        const at = startOfDay(day);
        at.setHours(hour);
        onCreateAt(at);
      }}
    >
      {HOURS.map((h) => (
        <div key={h} className="hour-line" style={{ height: HOUR_HEIGHT }} />
      ))}

      {laid.map(({ event, box, column, columns }) => {
        const cat = categoryInfo(event.categoryRaw);
        const width = 100 / (columns || 1);
        const start = event.startDate?.toDate?.();
        const end = event.endDate?.toDate?.();
        return (
          <button
            key={event.id}
            className="timed-event"
            style={{
              top: box.top,
              height: box.height,
              left: `calc(${column * width}% + 2px)`,
              width: `calc(${width}% - 4px)`,
              background: `color-mix(in srgb, ${cat.color} 26%, transparent)`,
              borderLeftColor: cat.color,
            }}
            onClick={(e) => {
              e.stopPropagation();
              onSelectEvent(event);
            }}
          >
            <span className="timed-title" style={{ color: cat.color }}>
              {event.title}
            </span>
            {box.height > 32 && start && (
              <span className="timed-time">
                {timeLabel(start, locale)}
                {end ? ` - ${timeLabel(end, locale)}` : ""}
              </span>
            )}
          </button>
        );
      })}
    </div>
  );
}

function AllDayRow({ days, events, onSelectEvent, label }) {
  return (
    <div className="allday-row">
      <div className="allday-label">{label}</div>
      <div className="allday-cells" style={{ "--cols": days.length }}>
        {days.map((day) => (
          <div key={day.toISOString()} className="allday-cell">
            {events
              .filter((e) => e.isAllDay && eventOccursOnDay(e, day))
              .map((e) => {
                const cat = categoryInfo(e.categoryRaw);
                return (
                  <button
                    key={e.id}
                    className="allday-chip"
                    style={{ background: cat.color }}
                    onClick={() => onSelectEvent(e)}
                  >
                    {e.title}
                  </button>
                );
              })}
          </div>
        ))}
      </div>
    </div>
  );
}

function TimeGridView({ days, events, onSelectEvent, onCreateAt, allDayLabel, showHeader }) {
  const { locale } = useTranslation();
  const scrollRef = useRef(null);
  const today = new Date();

  // Apre la vista sull'orario utile, non a mezzanotte.
  useEffect(() => {
    if (scrollRef.current) scrollRef.current.scrollTop = HOUR_HEIGHT * 7;
  }, []);

  return (
    <div className="timegrid">
      {showHeader && (
        <div className="timegrid-head">
          <div className="head-spacer" />
          <div className="head-days" style={{ "--cols": days.length }}>
            {days.map((d) => (
              <div key={d.toISOString()} className="head-day">
                <span className="head-dow">{weekdayName(d, locale, "short")}</span>
                <span className={"head-num" + (isSameDay(d, today) ? " today" : "")}>
                  {d.getDate()}
                </span>
              </div>
            ))}
          </div>
        </div>
      )}

      <AllDayRow
        days={days}
        events={events}
        onSelectEvent={onSelectEvent}
        label={allDayLabel}
      />

      <div className="timegrid-body" ref={scrollRef}>
        <HourGutter />
        <div className="day-columns" style={{ "--cols": days.length }}>
          {days.map((d) => (
            <DayColumn
              key={d.toISOString()}
              day={d}
              events={events}
              onSelectEvent={onSelectEvent}
              onCreateAt={onCreateAt}
            />
          ))}
        </div>
      </div>
    </div>
  );
}

/* ── Vista Mese: eventi elencati dentro la cella ──────────────────────── */

function MonthView({ anchor, events, selectedDate, onSelectDay, onSelectEvent, locale, weekStart }) {
  const cells = calendarDays(anchor.getFullYear(), anchor.getMonth(), weekStart);
  const initials = weekdayInitials(locale, weekStart);
  const today = new Date();

  return (
    <div className="month-view">
      <div className="month-view-head">
        {initials.map((w, i) => (
          <span key={i}>{w}</span>
        ))}
      </div>
      <div className="month-view-grid">
        {cells.map((d, i) => {
          if (!d) return <div key={i} className="mv-cell out" />;
          const inMonth = d.getMonth() === anchor.getMonth();
          const dayEvents = events
            .filter((e) => eventOccursOnDay(e, d))
            .sort((a, b) => (a.startDate?.toMillis?.() ?? 0) - (b.startDate?.toMillis?.() ?? 0));
          return (
            <div
              key={i}
              className={
                "mv-cell" +
                (inMonth ? "" : " out") +
                (isSameDay(d, selectedDate) ? " selected" : "")
              }
              onClick={() => onSelectDay(d)}
            >
              <div className="mv-daynum-row">
                <span className={"mv-daynum" + (isSameDay(d, today) ? " today" : "")}>
                  {d.getDate()}
                </span>
              </div>
              <div className="mv-events">
                {dayEvents.slice(0, 4).map((e) => {
                  const cat = categoryInfo(e.categoryRaw);
                  const start = e.startDate?.toDate?.();
                  return (
                    <button
                      key={e.id}
                      className="mv-event"
                      onClick={(ev) => {
                        ev.stopPropagation();
                        onSelectEvent(e);
                      }}
                    >
                      <span className="mv-dot" style={{ background: cat.color }} />
                      <span className="mv-title">{e.title}</span>
                      {!e.isAllDay && start && (
                        <span className="mv-time">{timeLabel(start, locale)}</span>
                      )}
                    </button>
                  );
                })}
                {dayEvents.length > 4 && (
                  <span className="mv-more">+{dayEvents.length - 4}</span>
                )}
              </div>
            </div>
          );
        })}
      </div>
    </div>
  );
}

/* ── Vista Anno ───────────────────────────────────────────────────────── */

function YearView({ year, marked, onSelectMonth, locale, weekStart }) {
  const initials = weekdayInitials(locale, weekStart);
  const today = new Date();

  return (
    <div className="year-view">
      {Array.from({ length: 12 }, (_, m) => (
        <button key={m} className="yv-month" onClick={() => onSelectMonth(m)}>
          <div className="yv-title">{monthAbbrev(m, locale)}</div>
          <div className="yv-head">
            {initials.map((w, i) => (
              <span key={i}>{w}</span>
            ))}
          </div>
          <div className="yv-grid">
            {calendarDays(year, m, weekStart).map((d, i) => (
              <span
                key={i}
                className={
                  "yv-day" +
                  (d ? "" : " empty") +
                  (d && isSameDay(d, today) ? " today" : "") +
                  (d && marked.has(dayKey(d)) ? " has-event" : "")
                }
              >
                {d ? d.getDate() : ""}
              </span>
            ))}
          </div>
        </button>
      ))}
    </div>
  );
}

/* ── Pagina ───────────────────────────────────────────────────────────── */

export default function Calendario() {
  const { currentFamilyId } = useFamily();
  const { user } = useAuth();
  const { t, locale } = useTranslation();

  const [view, setView] = useState("month");
  const [anchor, setAnchor] = useState(() => new Date());
  const [selectedDate, setSelectedDate] = useState(() => new Date());
  const [events, setEvents] = useState([]);
  const [error, setError] = useState(null);
  const [showAdd, setShowAdd] = useState(false);
  const [addDate, setAddDate] = useState(null);
  const [editingEvent, setEditingEvent] = useState(null);

  useEffect(() => {
    if (!currentFamilyId) return undefined;
    const q = query(
      collection(db, "families", currentFamilyId, "calendarEvents"),
      where("isDeleted", "==", false)
    );
    return onSnapshot(
      q,
      (snap) => setEvents(snap.docs.map((d) => ({ id: d.id, ...d.data() }))),
      (err) => setError(err.message)
    );
  }, [currentFamilyId]);

  const weekStart = firstWeekday(locale);
  const marked = useMemo(() => daysWithEvents(events), [events]);

  const shift = (delta) => {
    setAnchor((prev) => {
      if (view === "day") return addDays(prev, delta);
      if (view === "week") return addDays(prev, delta * 7);
      if (view === "month") return new Date(prev.getFullYear(), prev.getMonth() + delta, 1);
      return new Date(prev.getFullYear() + delta, prev.getMonth(), 1);
    });
  };

  const goToday = () => {
    const now = new Date();
    setAnchor(now);
    setSelectedDate(now);
  };

  const openCreate = (date) => {
    setAddDate(date ?? selectedDate);
    setShowAdd(true);
  };

  const deleteEvent = async (ev) => {
    try {
      await setDoc(
        doc(db, "families", currentFamilyId, "calendarEvents", ev.id),
        { isDeleted: true, updatedAt: serverTimestamp(), updatedBy: user.uid },
        { merge: true }
      );
    } catch (err) {
      setError(err.message);
    }
  };

  const heading = () => {
    if (view === "day") {
      const { dayMonth, year } = dayTitle(anchor, locale);
      return (
        <>
          <strong>{dayMonth}</strong> <span className="dim">{year}</span>
        </>
      );
    }
    if (view === "year") return <strong>{anchor.getFullYear()}</strong>;
    const title = monthTitle(anchor, locale);
    const [m, y] = title.split(" ");
    return (
      <>
        <strong>{m}</strong> <span className="dim">{y}</span>
      </>
    );
  };

  return (
    <div className="cal-page">
      <div className="cal-toolbar">
        <button className="cal-add" onClick={() => openCreate()} title={t.calendar.newEvent}>
          +
        </button>
        <div className="seg-control">
          {VIEWS.map((v) => (
            <button
              key={v}
              className={"seg-btn" + (view === v ? " active" : "")}
              onClick={() => setView(v)}
            >
              {t.calendar[v]}
            </button>
          ))}
        </div>
        <div className="cal-nav">
          <button onClick={() => shift(-1)}>‹</button>
          <button className="today-btn" onClick={goToday}>
            {t.calendar.todayBtn}
          </button>
          <button onClick={() => shift(1)}>›</button>
        </div>
      </div>

      <div className="cal-heading">
        {heading()}
        {view === "day" && (
          <div className="cal-subheading">{weekdayName(anchor, locale)}</div>
        )}
      </div>

      {error && <p className="error">{error}</p>}

      {view === "day" && (
        <TimeGridView
          days={[anchor]}
          events={events}
          onSelectEvent={setEditingEvent}
          onCreateAt={openCreate}
          allDayLabel={t.calendar.allDayShort}
          showHeader={false}
        />
      )}

      {view === "week" && (
        <TimeGridView
          days={weekDays(anchor, weekStart)}
          events={events}
          onSelectEvent={setEditingEvent}
          onCreateAt={openCreate}
          allDayLabel={t.calendar.allDayShort}
          showHeader
        />
      )}

      {view === "month" && (
        <MonthView
          anchor={anchor}
          events={events}
          selectedDate={selectedDate}
          onSelectDay={setSelectedDate}
          onSelectEvent={setEditingEvent}
          locale={locale}
          weekStart={weekStart}
        />
      )}

      {view === "year" && (
        <YearView
          year={anchor.getFullYear()}
          marked={marked}
          onSelectMonth={(m) => {
            const d = new Date(anchor.getFullYear(), m, 1);
            setAnchor(d);
            setSelectedDate(d);
            setView("month");
          }}
          locale={locale}
          weekStart={weekStart}
        />
      )}

      {(showAdd || editingEvent) && (
        <EventEditModal
          familyId={currentFamilyId}
          initialDate={addDate ?? selectedDate}
          event={editingEvent}
          onDelete={editingEvent ? () => deleteEvent(editingEvent) : null}
          onClose={() => {
            setShowAdd(false);
            setAddDate(null);
            setEditingEvent(null);
          }}
        />
      )}
    </div>
  );
}
