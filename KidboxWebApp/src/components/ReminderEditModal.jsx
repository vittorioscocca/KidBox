import { useState } from "react";
import { doc, serverTimestamp, setDoc } from "firebase/firestore";
import { todosCol } from "../hooks/useTodos";
import { todoListsCol } from "../hooks/useTodoLists";
import { useAuth } from "../AuthContext";
import { useFamilyMembers } from "../hooks/useFamilyMembers";
import { useTranslation } from "../i18n/LocaleContext";
import Modal from "./Modal";

/** `YYYY-MM-DD` per un <input type="date">, nel fuso locale. */
function toDateInput(date) {
  const pad = (n) => String(n).padStart(2, "0");
  return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}`;
}

/** `HH:MM` per un <input type="time">. */
function toTimeInput(date) {
  const pad = (n) => String(n).padStart(2, "0");
  return `${pad(date.getHours())}:${pad(date.getMinutes())}`;
}

/**
 * Creazione e modifica di un **promemoria** dal calendario.
 *
 * Un promemoria non è un'entità nuova: è un to-do (`families/{id}/todos`) con
 * una scadenza, nella lista che l'utente sceglie qui. Chi lo apre dalla
 * sezione To-Do lo trova identico. Gemello di `CalendarReminderFormView` su
 * iOS e di `CalendarReminderFormContent` su Android.
 *
 * `kindSelector` è la barra `Evento | Promemoria`, passata dal chiamante solo
 * in creazione.
 */
export default function ReminderEditModal({
  familyId,
  childId,
  initialDate,
  todo,
  lists = [],
  kindSelector = null,
  onClose,
}) {
  const { user } = useAuth();
  const { t } = useTranslation();
  const isEdit = Boolean(todo);
  const members = useFamilyMembers(familyId);

  const initial = todo?.dueAt?.toDate?.() ?? (() => {
    const d = new Date(initialDate);
    d.setHours(9, 0, 0, 0);
    return d;
  })();

  const [title, setTitle] = useState(todo?.title ?? "");
  const [notes, setNotes] = useState(todo?.notes ?? "");
  const [dueDate, setDueDate] = useState(toDateInput(initial));
  const [dueTime, setDueTime] = useState(toTimeInput(initial));
  // I to-do precedenti al campo hanno sempre un orario: `undefined` vale `true`.
  const [hasTime, setHasTime] = useState(todo?.dueHasTime ?? true);
  const [isUrgent, setIsUrgent] = useState((todo?.priority ?? 0) === 1);
  const [listId, setListId] = useState(todo?.listId || lists[0]?.id || "");
  const [assignedTo, setAssignedTo] = useState(todo?.assignedTo ?? null);
  const [view, setView] = useState("main"); // main | assignee
  const [error, setError] = useState(null);

  const assigneeLabel = () => {
    if (!assignedTo) return t.todo.none;
    if (assignedTo === user.uid) return t.todo.me;
    return members.find((m) => m.id === assignedTo)?.displayName || t.todo.none;
  };

  const save = async () => {
    const trimmed = title.trim();
    if (!trimmed || !familyId) return;
    // Senza orario il promemoria vale per le 9:00, come «tutto il giorno» in
    // Promemoria di Apple: un avviso a mezzanotte non lo legge nessuno.
    const due = new Date(`${dueDate}T${hasTime ? dueTime : "09:00"}`);

    try {
      let targetListId = listId;
      if (!targetListId) {
        // Senza `listId` il to-do esisterebbe ma non comparirebbe in nessuna
        // lista: è la trappola degli orfani già nota.
        const newListId = crypto.randomUUID();
        await setDoc(doc(todoListsCol(familyId), newListId), {
          id: newListId,
          familyId,
          childId: childId || "",
          name: t.calendar.reminderListDefault,
          isDeleted: false,
          createdBy: user.uid,
          createdAt: serverTimestamp(),
          updatedAt: serverTimestamp(),
        });
        targetListId = newListId;
      }

      const id = isEdit ? todo.id : crypto.randomUUID();
      const payload = {
        childId: isEdit ? todo.childId ?? "" : childId || "",
        title: trimmed,
        listId: targetListId,
        isDone: isEdit ? todo.isDone ?? false : false,
        isDeleted: false,
        notes: notes.trim() || null,
        dueAt: due,
        dueHasTime: hasTime,
        assignedTo,
        priority: isUrgent ? 1 : 0,
        visibilityScope: todo?.visibilityScope ?? "family",
        visibilityMemberIds: todo?.visibilityMemberIds ?? [],
        updatedBy: user.uid,
        updatedAt: serverTimestamp(),
      };
      if (!isEdit) {
        payload.doneAt = null;
        payload.doneBy = null;
        payload.createdBy = user.uid;
        payload.createdAt = serverTimestamp();
      }
      await setDoc(doc(todosCol(familyId), id), payload, { merge: true });
      onClose();
    } catch (err) {
      setError(err.message);
    }
  };

  if (view === "assignee") {
    return (
      <Modal onClose={() => setView("main")}>
        <div className="modal-header">
          <button className="modal-icon-btn" onClick={() => setView("main")}>‹</button>
        </div>
        <div className="modal-title">{t.todo.assignTo}</div>
        <div className="modal-section">
          <button
            className="modal-option"
            onClick={() => {
              setAssignedTo(null);
              setView("main");
            }}
          >
            {t.todo.none} {!assignedTo && "✓"}
          </button>
          <button
            className="modal-option"
            onClick={() => {
              setAssignedTo(user.uid);
              setView("main");
            }}
          >
            {t.todo.me} {assignedTo === user.uid && "✓"}
          </button>
          {members
            .filter((m) => m.id !== user.uid)
            .map((m) => (
              <button
                key={m.id}
                className="modal-option"
                onClick={() => {
                  setAssignedTo(m.id);
                  setView("main");
                }}
              >
                {m.displayName || t.todo.none} {assignedTo === m.id && "✓"}
              </button>
            ))}
        </div>
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
        {isEdit ? t.calendar.editReminder : t.calendar.newReminder}
      </div>
      {kindSelector}
      {error && <p className="error">{error}</p>}

      <input
        className="modal-field"
        placeholder={t.calendar.reminderTitlePlaceholder}
        value={title}
        autoFocus
        onChange={(e) => setTitle(e.target.value)}
      />
      <textarea
        className="modal-field"
        placeholder={t.calendar.notes}
        value={notes}
        onChange={(e) => setNotes(e.target.value)}
      />

      <div className="modal-label">{t.calendar.dateAndTime}</div>
      <div className="modal-section">
        <div className="modal-row">
          <span>{t.calendar.dateLabel}</span>
          <input
            type="date"
            value={dueDate}
            onChange={(e) => setDueDate(e.target.value)}
          />
        </div>
        <div className="modal-row clickable" onClick={() => setHasTime((v) => !v)}>
          <span>{t.calendar.timeLabel}</span>
          <span className={`modal-check ${hasTime ? "on" : "off"}`}>✓</span>
        </div>
        {hasTime && (
          <div className="modal-row">
            <span>{t.calendar.timeLabel}</span>
            <input
              type="time"
              value={dueTime}
              onChange={(e) => setDueTime(e.target.value)}
            />
          </div>
        )}
        <div className="modal-row clickable" onClick={() => setIsUrgent((v) => !v)}>
          <span>{t.calendar.urgent}</span>
          <span className={`modal-check ${isUrgent ? "on" : "off"}`}>✓</span>
        </div>
      </div>
      <p className="modal-hint">{t.calendar.urgentHint}</p>

      <div className="modal-label">{t.calendar.reminderList}</div>
      <div className="modal-section">
        {lists.length === 0 ? (
          <div className="modal-row">
            <span>{t.calendar.reminderListDefault}</span>
          </div>
        ) : (
          <div className="modal-row">
            <span>{t.calendar.reminderList}</span>
            <select value={listId} onChange={(e) => setListId(e.target.value)}>
              {lists.map((l) => (
                <option key={l.id} value={l.id}>
                  {l.name}
                </option>
              ))}
            </select>
          </div>
        )}
      </div>

      <div className="modal-label">{t.todo.assignedTo}</div>
      <div className="modal-section">
        <div className="modal-row clickable" onClick={() => setView("assignee")}>
          <span>{assigneeLabel()}</span>
          <span>›</span>
        </div>
      </div>
    </Modal>
  );
}
