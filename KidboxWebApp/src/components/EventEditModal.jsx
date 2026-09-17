import { useState } from "react";
import { Timestamp, doc, serverTimestamp, setDoc } from "firebase/firestore";
import { db } from "../firebase";
import { useAuth } from "../AuthContext";
import { useFamilyMembers } from "../hooks/useFamilyMembers";
import { useTranslation } from "../i18n/LocaleContext";
import {
  CATEGORIES,
  VISIBILITY_FAMILY,
  VISIBILITY_MEMBERS,
  VISIBILITY_PRIVATE,
  normalizedVisibilityScope,
  toLocalInputValue,
} from "../calendarUtils";
import Modal from "./Modal";

/**
 * Creazione e modifica evento, come CalendarEventFormView su iOS: stessa view per
 * entrambi i casi, distinti dalla presenza di `event`.
 */
export default function EventEditModal({ familyId, initialDate, event, onDelete, onClose }) {
  const { user } = useAuth();
  const { t } = useTranslation();
  const isEdit = Boolean(event);
  const members = useFamilyMembers(familyId);

  const VISIBILITY_OPTIONS = [
    { scope: VISIBILITY_FAMILY, label: t.calendar.visibilityFamily },
    { scope: VISIBILITY_MEMBERS, label: t.calendar.visibilityMembers },
    { scope: VISIBILITY_PRIVATE, label: t.calendar.visibilityPrivate },
  ];
  const chipLabel = (scope) =>
    VISIBILITY_OPTIONS.find((o) => o.scope === scope)?.label || VISIBILITY_OPTIONS[0].label;

  // Come `canEditVisibility` su iOS: la visibilità la cambia solo chi ha creato
  // l'evento (o chiunque, se il documento è legacy senza createdBy).
  const canEditVisibility =
    !isEdit || !(event?.createdBy || "").trim() || event.createdBy === user.uid;
  // Come `visibilitySelectableMembers`: chi crea vede sempre il proprio evento,
  // quindi non compare tra i membri da selezionare.
  const selectableMembers = members.filter((m) => m.id !== user.uid);

  const defaults = () => {
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

  const [title, setTitle] = useState(event?.title ?? "");
  const [category, setCategory] = useState(event?.categoryRaw ?? "family");
  const [isAllDay, setIsAllDay] = useState(event?.isAllDay ?? false);
  const [startAt, setStartAt] = useState(toLocalInputValue(initial.start));
  const [endAt, setEndAt] = useState(toLocalInputValue(initial.end));
  const [location, setLocation] = useState(event?.location ?? "");
  const [notes, setNotes] = useState(event?.notes ?? "");
  const [visibilityScope, setVisibilityScope] = useState(
    normalizedVisibilityScope(event?.visibilityScope)
  );
  const [visibilityMemberIds, setVisibilityMemberIds] = useState(
    new Set(event?.visibilityMemberIds ?? [])
  );
  const [view, setView] = useState("main"); // main | visibility
  const [visibilityLocked, setVisibilityLocked] = useState(false);
  const [error, setError] = useState(null);

  const toggleVisibilityMember = (uid) => {
    setVisibilityMemberIds((prev) => {
      const next = new Set(prev);
      if (next.has(uid)) next.delete(uid);
      else next.add(uid);
      return next;
    });
  };

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
      recurrenceRaw: event?.recurrenceRaw ?? "none",
      isDeleted: false,
      startDate: Timestamp.fromDate(startDate),
      endDate: Timestamp.fromDate(endDate >= startDate ? endDate : startDate),
      location: location.trim() || null,
      notes: notes.trim() || null,
      updatedAt: serverTimestamp(),
      updatedBy: user.uid,
      visibilityScope,
      visibilityMemberIds:
        visibilityScope === VISIBILITY_MEMBERS
          ? [...visibilityMemberIds].filter((uid) => uid !== user.uid).sort()
          : [],
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

  if (view === "visibility") {
    return (
      <Modal onClose={() => setView("main")}>
        <div className="modal-header">
          <button className="modal-text-btn" onClick={() => setView("main")}>
            {t.calendar.cancel}
          </button>
          <button className="modal-save-btn" onClick={() => setView("main")}>
            {t.calendar.confirm}
          </button>
        </div>
        <div className="modal-title">{t.calendar.visibility}</div>
        <div className="modal-label">{t.calendar.whoCanSee}</div>
        <div className="modal-section">
          {VISIBILITY_OPTIONS.map((opt) => (
            <button
              key={opt.scope}
              className="modal-option"
              onClick={() => {
                setVisibilityScope(opt.scope);
                if (opt.scope !== VISIBILITY_MEMBERS) setVisibilityMemberIds(new Set());
              }}
            >
              <span>{opt.label}</span>
              <span>{visibilityScope === opt.scope ? "●" : "○"}</span>
            </button>
          ))}
        </div>

        {visibilityScope === VISIBILITY_MEMBERS && (
          <>
            <div className="modal-label">{t.calendar.selectMembers}</div>
            <div className="modal-section">
              {selectableMembers.map((m) => (
                <button
                  key={m.id}
                  className="modal-option"
                  onClick={() => toggleVisibilityMember(m.id)}
                >
                  <span>{m.displayName || t.calendar.member}</span>
                  <span>{visibilityMemberIds.has(m.id) ? "●" : "○"}</span>
                </button>
              ))}
            </div>
          </>
        )}
      </Modal>
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
      {error && <p className="error">{error}</p>}

      <button
        className="modal-chip"
        onClick={() => {
          if (canEditVisibility) setView("visibility");
          else setVisibilityLocked(true);
        }}
      >
        {chipLabel(visibilityScope)}
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
