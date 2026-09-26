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
import ReminderEditModal from "../components/ReminderEditModal";
import { useTodos } from "../hooks/useTodos";
import { useTodoLists } from "../hooks/useTodoLists";
import { useChildren } from "../hooks/useChildren";
import {
  HOUR_HEIGHT,
  addDays,
  calendarDays,
  categoryInfo,
  dayKey,
  dayTitle,
  daysWithEvents,
  eventOccursOnDay,
  expandEvents,
  occurrenceWindow,
  firstWeekday,
  isEventVisibleTo,
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
/**
 * La vista scelta sopravvive alla chiusura del browser: chi lavora a settimana
 * non deve rimetterla ogni volta. È una preferenza del dispositivo, come
 * `@AppStorage` su iOS e SharedPreferences su Android.
 */
const VIEW_STORAGE_KEY = "kidbox:calendarView";
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

function TimeGridView({
  days,
  events,
  remindersOn,
  onSelectEvent,
  onSelectReminder,
  onCreateAt,
  allDayLabel,
  reminderLabel,
  showHeader,
}) {
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

      {/* I promemoria stanno in una riga propria sopra la griglia, come in
          Calendario di Apple: hanno un istante, non una durata, e disegnarli
          come blocchi li farebbe sembrare appuntamenti di un'ora. */}
      {days.some((d) => remindersOn(d).length > 0) && (
        <div className="allday-row">
          <div className="allday-label">{reminderLabel}</div>
          <div className="allday-cells" style={{ "--cols": days.length }}>
            {days.map((day) => (
              <div key={day.toISOString()} className="allday-cell">
                {remindersOn(day).map((todo) => (
                  <button
                    key={todo.id}
                    className={"reminder-chip" + (todo.isDone ? " done" : "")}
                    onClick={() => onSelectReminder(todo)}
                  >
                    {todo.title}
                  </button>
                ))}
              </div>
            ))}
          </div>
        </div>
      )}

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

function MonthView({ anchor, events, remindersOn, selectedDate, onSelectDay, onSelectEvent, onSelectReminder, onCreateAt, locale, weekStart }) {
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
              // Doppio click sulla cella: nuovo evento in quel giorno, come il
              // doppio click sulla colonna oraria nelle viste giorno/settimana.
              onDoubleClick={() => onCreateAt(d)}
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
                      onDoubleClick={(ev) => ev.stopPropagation()}
                    >
                      <span className="mv-dot" style={{ background: cat.color }} />
                      <span className="mv-title">{e.title}</span>
                      {!e.isAllDay && start && (
                        <span className="mv-time">{timeLabel(start, locale)}</span>
                      )}
                    </button>
                  );
                })}
                {remindersOn(d).slice(0, 3).map((todo) => (
                  <button
                    key={todo.id}
                    className={"mv-event mv-reminder" + (todo.isDone ? " done" : "")}
                    onClick={(ev) => {
                      ev.stopPropagation();
                      onSelectReminder(todo);
                    }}
                    onDoubleClick={(ev) => ev.stopPropagation()}
                  >
                    <span className="mv-dot mv-dot-reminder" />
                    <span className="mv-title">{todo.title}</span>
                  </button>
                ))}
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

/**
 * La barra `Evento | Promemoria` in cima al modale di creazione, come in
 * Calendario di Apple. Le due schede non condividono nulla se non questa
 * barra: un evento sta in `calendarEvents`, un promemoria è un to-do.
 */
function KindSelector({ kind, onChange, t }) {
  return (
    <div className="kind-selector">
      <button
        type="button"
        className={"kind-btn" + (kind === "event" ? " active" : "")}
        onClick={() => onChange("event")}
      >
        {t.calendar.kindEvent}
      </button>
      <button
        type="button"
        className={"kind-btn" + (kind === "reminder" ? " active" : "")}
        onClick={() => onChange("reminder")}
      >
        {t.calendar.kindReminder}
      </button>
    </div>
  );
}

/* ── Pagina ───────────────────────────────────────────────────────────── */

export default function Calendario() {
  const { currentFamilyId } = useFamily();
  const { user } = useAuth();
  const { t, locale } = useTranslation();

  const [view, setView] = useState(() => {
    const stored = localStorage.getItem(VIEW_STORAGE_KEY);
    return VIEWS.includes(stored) ? stored : "month";
  });
  const changeView = (next) => {
    setView(next);
    localStorage.setItem(VIEW_STORAGE_KEY, next);
  };
  const [anchor, setAnchor] = useState(() => new Date());
  const [selectedDate, setSelectedDate] = useState(() => new Date());
  const [events, setEvents] = useState([]);
  const [error, setError] = useState(null);
  const [showAdd, setShowAdd] = useState(false);
  const [addDate, setAddDate] = useState(null);
  const [editingEvent, setEditingEvent] = useState(null);
  const [editingReminder, setEditingReminder] = useState(null);
  /** Quale delle due schede è aperta quando si crea qualcosa di nuovo. */
  const [newItemKind, setNewItemKind] = useState("event");

  // I promemoria del calendario **sono** to-do con una scadenza: stessa
  // collezione, stesse liste, stessa visibilità. Il calendario è solo
  // un'altra porta d'ingresso agli stessi elementi.
  const children = useChildren(currentFamilyId);
  const { todos } = useTodos(currentFamilyId, user?.uid);
  const todoLists = useTodoLists(currentFamilyId);
  const reminders = useMemo(
    () => todos.filter((todo) => Boolean(todo.dueAt)),
    [todos]
  );
  const remindersByDay = useMemo(() => {
    const map = new Map();
    reminders.forEach((todo) => {
      const due = todo.dueAt?.toDate?.();
      if (!due) return;
      const key = dayKey(due);
      if (!map.has(key)) map.set(key, []);
      map.get(key).push(todo);
    });
    return map;
  }, [reminders]);
  const remindersOn = (day) =>
    (remindersByDay.get(dayKey(day)) ?? []).sort(
      (a, b) => (a.dueAt?.toMillis?.() ?? 0) - (b.dueAt?.toMillis?.() ?? 0)
    );

  useEffect(() => {
    if (!currentFamilyId) return undefined;
    const q = query(
      collection(db, "families", currentFamilyId, "calendarEvents"),
      where("isDeleted", "==", false)
    );
    // Come il predicato `isVisible(to:)` di CalendarView su iOS: gli eventi
    // «Solo io» o «Membri selezionati» di un altro membro non si mostrano.
    const uid = user?.uid;
    return onSnapshot(
      q,
      (snap) =>
        setEvents(
          snap.docs
            .map((d) => ({ id: d.id, ...d.data() }))
            .filter((e) => isEventVisibleTo(e, uid))
        ),
      (err) => setError(err.message)
    );
  }, [currentFamilyId, user?.uid]);

  const weekStart = firstWeekday(locale);
  // Le serie si espandono nelle ripetizioni attorno alle date guardate: una
  // serie senza fine non si può espandere tutta. Si disegnano le copie, si
  // modifica la serie (`_series`).
  const displayEvents = useMemo(() => {
    const [from, to] = occurrenceWindow(anchor, selectedDate);
    return expandEvents(events, from, to);
  }, [events, anchor, selectedDate]);
  const anchorYear = anchor.getFullYear();
  const marked = useMemo(
    () =>
      daysWithEvents(
        expandEvents(events, new Date(anchorYear, 0, 1), new Date(anchorYear + 1, 0, 1))
      ),
    [events, anchorYear]
  );
  const openEvent = (e) => setEditingEvent(e?._series ?? e);

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
    setNewItemKind("event");
    setShowAdd(true);
  };

  const closeAdd = () => {
    setShowAdd(false);
    setAddDate(null);
    setEditingEvent(null);
    setNewItemKind("event");
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
              onClick={() => changeView(v)}
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
          events={displayEvents}
          remindersOn={remindersOn}
          onSelectEvent={openEvent}
          onSelectReminder={setEditingReminder}
          onCreateAt={openCreate}
          allDayLabel={t.calendar.allDayShort}
          reminderLabel={t.calendar.remindersSection}
          showHeader={false}
        />
      )}

      {view === "week" && (
        <TimeGridView
          days={weekDays(anchor, weekStart)}
          events={displayEvents}
          remindersOn={remindersOn}
          onSelectEvent={openEvent}
          onSelectReminder={setEditingReminder}
          onCreateAt={openCreate}
          allDayLabel={t.calendar.allDayShort}
          reminderLabel={t.calendar.remindersSection}
          showHeader
        />
      )}

      {view === "month" && (
        <MonthView
          anchor={anchor}
          events={displayEvents}
          remindersOn={remindersOn}
          selectedDate={selectedDate}
          onSelectDay={setSelectedDate}
          onSelectEvent={openEvent}
          onSelectReminder={setEditingReminder}
          onCreateAt={(d) => {
            setSelectedDate(d);
            openCreate(d);
          }}
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
            changeView("month");
          }}
          locale={locale}
          weekStart={weekStart}
        />
      )}

      {(showAdd || editingEvent) && !editingReminder && (
        <>
          {showAdd && newItemKind === "reminder" ? (
            <ReminderEditModal
              familyId={currentFamilyId}
              childId={children[0]?.id ?? ""}
              initialDate={addDate ?? selectedDate}
              lists={todoLists}
              kindSelector={<KindSelector kind={newItemKind} onChange={setNewItemKind} t={t} />}
              onClose={closeAdd}
            />
          ) : (
            <EventEditModal
              familyId={currentFamilyId}
              initialDate={addDate ?? selectedDate}
              event={editingEvent}
              onDelete={editingEvent ? () => deleteEvent(editingEvent) : null}
              kindSelector={
                showAdd && !editingEvent ? (
                  <KindSelector kind={newItemKind} onChange={setNewItemKind} t={t} />
                ) : null
              }
              onClose={closeAdd}
            />
          )}
        </>
      )}

      {editingReminder && (
        <ReminderEditModal
          familyId={currentFamilyId}
          childId={editingReminder.childId ?? children[0]?.id ?? ""}
          initialDate={editingReminder.dueAt?.toDate?.() ?? selectedDate}
          todo={editingReminder}
          lists={todoLists}
          onClose={() => setEditingReminder(null)}
        />
      )}
    </div>
  );
}
