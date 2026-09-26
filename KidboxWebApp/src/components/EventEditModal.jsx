import { useState } from "react";
import { Timestamp, doc, serverTimestamp, setDoc } from "firebase/firestore";
import { db } from "../firebase";
import { useAuth } from "../AuthContext";
import { useFamilyMembers } from "../hooks/useFamilyMembers";
import { useTranslation } from "../i18n/LocaleContext";
import { CATEGORIES, RECURRENCES, isRecurring, toLocalInputValue } from "../calendarUtils";
import { VISIBILITY_MEMBERS, normalizedVisibilityScope } from "../visibility";
import Modal from "./Modal";
import VisibilityPickerModal, { visibilityChipLabel } from "./VisibilityPickerModal";

/**
 * Creazione e modifica evento, come CalendarEventFormView su iOS: stessa view per
 * entrambi i casi, distinti dalla presenza di `event`.
 */
export default function EventEditModal({
  familyId,
  initialDate,
  event,
  onDelete,
  onClose,
  /** La barra `Evento | Promemoria`, passata solo in creazione. */
  kindSelector = null,
  /**
   * «Copia in KidBox» da un calendario iscritto: titolo, date, luogo e note
   * già scritti; categoria, visibilità e promemoria li sceglie l'utente.
   */
  prefill = null,
}) {
  const { user } = useAuth();
  const { t } = useTranslation();
  const isEdit = Boolean(event);
  const members = useFamilyMembers(familyId);

  // Come `canEditVisibility` su iOS: la visibilità la cambia solo chi ha creato
  // l'evento (o chiunque, se il documento è legacy senza createdBy).
  const canEditVisibility =
    !isEdit || !(event?.createdBy || "").trim() || event.createdBy === user.uid;

  const defaults = () => {
    if (!event && prefill) {
      return { start: new Date(prefill.start), end: new Date(prefill.end) };
    }
    if (event) {
      const s = event.startDate?.toDate?.() ?? new Date(initialDate);
      const e = event.endDate?.toDate?.() ?? new Date(s.getTime() + 60 * 60 * 1000);
      return { start: s, end: e };
    }
    const s = new Date(initialDate);
    s.setHours(9, 0, 0, 0);
    return { start: s, end: new Date(s.getTime() + 60 * 60 * 1000) };
  };
  const initial = defaults();

  const [title, setTitle] = useState(event?.title ?? prefill?.title ?? "");
  const [category, setCategory] = useState(event?.categoryRaw ?? "family");
  const [isAllDay, setIsAllDay] = useState(event?.isAllDay ?? prefill?.isAllDay ?? false);
  const [startAt, setStartAt] = useState(toLocalInputValue(initial.start));
  const [endAt, setEndAt] = useState(toLocalInputValue(initial.end));
  const [location, setLocation] = useState(event?.location ?? prefill?.location ?? "");
  // La ricorrenza prima si conservava e basta: dal web non si poteva scegliere.
  const [recurrence, setRecurrence] = useState(
    RECURRENCES.includes(event?.recurrenceRaw) ? event.recurrenceRaw : "none"
  );
  const [notes, setNotes] = useState(event?.notes ?? prefill?.notes ?? "");
  // `reminderMinutes` esisteva già ma non armava niente: da oggi lo leggono
  // iOS e Android, che al momento giusto avvisano davvero.
  const [hasReminder, setHasReminder] = useState((event?.reminderMinutes ?? 0) > 0);
  const [isUrgent, setIsUrgent] = useState((event?.priority ?? 0) === 1);
  const [visibilityScope, setVisibilityScope] = useState(
    normalizedVisibilityScope(event?.visibilityScope)
  );
  // Già ripuliti dal picker: senza il proprio uid e ordinati, come su iOS.
  const [visibilityMemberIds, setVisibilityMemberIds] = useState(
    event?.visibilityMemberIds ?? []
  );
  const [view, setView] = useState("main"); // main | visibility
  const [visibilityLocked, setVisibilityLocked] = useState(false);
  const [error, setError] = useState(null);

  const save = async () => {
    const trimmed = title.trim();
    if (!trimmed || !familyId) return;
    const id = isEdit ? event.id : crypto.randomUUID();
    const startDate = new Date(startAt);
    const endDate = new Date(endAt);

    const payload = {
      id,
      familyId,
      title: trimmed,
      isAllDay,
      categoryRaw: category,
      recurrenceRaw: recurrence,
      isDeleted: false,
      startDate: Timestamp.fromDate(startDate),
      endDate: Timestamp.fromDate(endDate >= startDate ? endDate : startDate),
      location: location.trim() || null,
      notes: notes.trim() || null,
      reminderMinutes: hasReminder ? event?.reminderMinutes ?? 30 : null,
      // Urgente senza promemoria non vuol dire niente: non c'è nulla da far
      // suonare. Si scrive sempre, anche a zero, così toglierlo arriva agli
      // altri dispositivi invece di restare qui.
      priority: hasReminder && isUrgent ? 1 : 0,
      updatedAt: serverTimestamp(),
      updatedBy: user.uid,
      visibilityScope,
      visibilityMemberIds: visibilityScope === VISIBILITY_MEMBERS ? visibilityMemberIds : [],
    };
    // In modifica createdAt/createdBy non si toccano: sovrascriverli farebbe
    // risultare l'evento creato da chi lo ha solo modificato.
    if (!isEdit) {
      payload.createdAt = serverTimestamp();
      payload.createdBy = user.uid;
    }

    try {
      await setDoc(doc(db, "families", familyId, "calendarEvents", id), payload, {
        merge: true,
      });
      onClose();
    } catch (err) {
      setError(err.message);
    }
  };

  // Il picker sostituisce il contenuto della modale, come la push nello stesso
  // NavigationStack su iOS; torna al form sia su Conferma sia su Annulla.
  if (view === "visibility") {
    return (
      <VisibilityPickerModal
        scope={visibilityScope}
        memberIds={visibilityMemberIds}
        members={members}
        whoCanSee={t.calendar.whoCanSee}
        onConfirm={(scope, ids) => {
          setVisibilityScope(scope);
          setVisibilityMemberIds(ids);
          setView("main");
        }}
        onClose={() => setView("main")}
      />
    );
  }

  return (
    <Modal onClose={onClose}>
      <div className="modal-header">
        <button className="modal-icon-btn" onClick={onClose}>✕</button>
        <button className="modal-save-btn" disabled={!title.trim()} onClick={save}>
          {t.calendar.save}
        </button>
      </div>
      <div className="modal-title">
        {isEdit ? t.calendar.editEvent : t.calendar.newEvent}
      </div>
      {kindSelector}
      {error && <p className="error">{error}</p>}

      <button
        className="modal-chip"
        onClick={() => {
          if (canEditVisibility) setView("visibility");
          else setVisibilityLocked(true);
        }}
      >
        {visibilityChipLabel(t, visibilityScope)}
      </button>
      {visibilityLocked && <p className="modal-hint">{t.calendar.visibilityLocked}</p>}

      <input
        className="modal-field"
        placeholder={t.calendar.titlePlaceholder}
        value={title}
        autoFocus
        onChange={(e) => setTitle(e.target.value)}
      />

      <div className="modal-label">{t.calendar.category}</div>
      <div className="cat-picker">
        {CATEGORIES.map((c) => (
          <button
            key={c.value}
            className={"cat-chip" + (category === c.value ? " active" : "")}
            style={
              category === c.value
                ? { borderColor: c.color, background: `${c.color}22` }
                : null
            }
            onClick={() => setCategory(c.value)}
          >
            <span>{c.icon}</span> {t.calendar.categories[c.value]}
          </button>
        ))}
      </div>

      <div className="modal-section">
        <div className="modal-row clickable" onClick={() => setIsAllDay((v) => !v)}>
          <span>{t.calendar.allDay}</span>
          <span className={`modal-check ${isAllDay ? "on" : "off"}`}>✓</span>
        </div>
        <div className="modal-row">
          <span>{t.calendar.starts}</span>
          <input
            type={isAllDay ? "date" : "datetime-local"}
            value={isAllDay ? startAt.slice(0, 10) : startAt}
            onChange={(e) =>
              setStartAt(isAllDay ? `${e.target.value}T00:00` : e.target.value)
            }
          />
        </div>
        <div className="modal-row">
          <span>{t.calendar.ends}</span>
          <input
            type={isAllDay ? "date" : "datetime-local"}
            value={isAllDay ? endAt.slice(0, 10) : endAt}
            onChange={(e) =>
              setEndAt(isAllDay ? `${e.target.value}T23:59` : e.target.value)
            }
          />
        </div>
      </div>

      <div className="modal-section">
        <div className="modal-row">
          <span>{t.calendar.recurrence}</span>
          <select value={recurrence} onChange={(e) => setRecurrence(e.target.value)}>
            {RECURRENCES.map((r) => (
              <option key={r} value={r}>
                {t.calendar.recurrences[r]}
              </option>
            ))}
          </select>
        </div>
      </div>

      <div className="modal-label">{t.calendar.reminderLabel}</div>
      <div className="modal-section">
        <div className="modal-row clickable" onClick={() => setHasReminder((v) => !v)}>
          <span>{t.calendar.reminderLabel}</span>
          <span className={`modal-check ${hasReminder ? "on" : "off"}`}>✓</span>
        </div>
        {hasReminder && (
          <div className="modal-row clickable" onClick={() => setIsUrgent((v) => !v)}>
            <span>{t.calendar.urgent}</span>
            <span className={`modal-check ${isUrgent ? "on" : "off"}`}>✓</span>
          </div>
        )}
      </div>
      {hasReminder && <p className="modal-hint">{t.calendar.urgentHint}</p>}

      <input
        className="modal-field"
        placeholder={t.calendar.location}
        value={location}
        onChange={(e) => setLocation(e.target.value)}
      />
      <textarea
        className="modal-field"
        placeholder={t.calendar.notes}
        value={notes}
        onChange={(e) => setNotes(e.target.value)}
      />

      {isEdit && onDelete && (
        <button
          className="modal-delete-btn"
          onClick={() => {
            // Non ci sono eccezioni per singola data: su una serie si
            // cancellano tutte le ripetizioni, e va detto prima.
            if (isRecurring(event?.recurrenceRaw) && !window.confirm(t.calendar.deleteSeriesConfirm)) {
              return;
            }
            onDelete();
            onClose();
          }}
        >
          {t.calendar.deleteEvent}
        </button>
      )}
    </Modal>
  );
}
