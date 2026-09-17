import { useState } from "react";
import { doc, serverTimestamp, setDoc } from "firebase/firestore";
import { todosCol } from "../hooks/useTodos";
import { useAuth } from "../AuthContext";
import { useFamilyMembers } from "../hooks/useFamilyMembers";
import { useTranslation } from "../i18n/LocaleContext";
import { VISIBILITY_MEMBERS, normalizedVisibilityScope } from "../visibility";
import Modal from "./Modal";
import VisibilityPickerModal, { visibilityChipLabel } from "./VisibilityPickerModal";

function toLocalInputValue(date) {
  const pad = (n) => String(n).padStart(2, "0");
  return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}T${pad(date.getHours())}:${pad(date.getMinutes())}`;
}

export default function TodoEditModal({ familyId, childId, listId, listName, todo, onClose }) {
  const isEdit = Boolean(todo);
  const { user } = useAuth();
  const { t } = useTranslation();
  const members = useFamilyMembers(familyId);

  // Come `canEditVisibility` in TodoEditView: la cambia solo chi ha creato il
  // to-do (o chiunque, se il documento è legacy senza createdBy).
  const canEditVisibility =
    !isEdit || !(todo?.createdBy || "").trim() || todo.createdBy === user.uid;

  const [title, setTitle] = useState(todo?.title ?? "");
  const [notes, setNotes] = useState(todo?.notes ?? "");
  const [hasDate, setHasDate] = useState(Boolean(todo?.dueAt));
  const [dueDate, setDueDate] = useState(
    toLocalInputValue(todo?.dueAt?.toDate?.() ?? new Date())
  );
  const [isUrgent, setIsUrgent] = useState((todo?.priority ?? 0) === 1);
  const [assignedTo, setAssignedTo] = useState(todo?.assignedTo ?? null);
  const [visibilityScope, setVisibilityScope] = useState(
    normalizedVisibilityScope(todo?.visibilityScope)
  );
  // Già ripuliti dal picker: senza il proprio uid e ordinati, come su iOS.
  const [visibilityMemberIds, setVisibilityMemberIds] = useState(
    todo?.visibilityMemberIds ?? []
  );
  const [view, setView] = useState("main"); // main | assignee | visibility
  const [visibilityLocked, setVisibilityLocked] = useState(false);
  const [error, setError] = useState(null);

  const assigneeLabel = () => {
    if (!assignedTo) return t.todo.none;
    if (assignedTo === user.uid) return t.todo.me;
    return members.find((m) => m.id === assignedTo)?.displayName || t.todo.none;
  };

  const save = async () => {
    const trimmed = title.trim();
    if (!trimmed) return;
    const id = isEdit ? todo.id : crypto.randomUUID();
    const finalMemberIds = visibilityScope === VISIBILITY_MEMBERS ? visibilityMemberIds : [];
    try {
      const payload = {
        childId: isEdit ? todo.childId : childId,
        title: trimmed,
        listId: isEdit ? todo.listId ?? "" : listId || "",
        isDone: isEdit ? todo.isDone ?? false : false,
        isDeleted: false,
        notes: notes.trim() || null,
        dueAt: hasDate ? new Date(dueDate) : null,
        assignedTo,
        priority: isUrgent ? 1 : 0,
        visibilityScope,
        visibilityMemberIds: finalMemberIds,
        updatedBy: user.uid,
        updatedAt: serverTimestamp(),
      };
      // In modifica non si toccano creatore e stato di completamento: li
      // sovrascriverebbe chi ha solo cambiato il titolo.
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
          <button className="modal-icon-btn" onClick={() => setView("main")}>
            ‹
          </button>
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
            {t.todo.me} ({user.displayName || user.email}) {assignedTo === user.uid && "✓"}
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

  if (view === "visibility") {
    return (
      <VisibilityPickerModal
        scope={visibilityScope}
        memberIds={visibilityMemberIds}
        members={members}
        whoCanSee={t.todo.whoCanSee}
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
        <button className="modal-icon-btn" onClick={onClose}>
          ✕
        </button>
        <button className="modal-save-btn" disabled={!title.trim()} onClick={save}>
          ✓
        </button>
      </div>
      <div className="modal-title">
        {isEdit ? t.todo.editTodo : t.todo.newInList(listName || t.todo.list)}
      </div>
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
      {visibilityLocked && <p className="modal-hint">{t.todo.visibilityLocked}</p>}

      <input
        className="modal-field"
        placeholder={t.todo.titlePlaceholder}
        value={title}
        autoFocus
        onChange={(e) => setTitle(e.target.value)}
      />

      <div className="modal-label">{t.todo.notes}</div>
      <textarea
        className="modal-field"
        placeholder={t.todo.notesPlaceholder}
        value={notes}
        onChange={(e) => setNotes(e.target.value)}
      />

      <div className="modal-label">{t.todo.dueDate}</div>
      <div className="modal-section">
        <div className="modal-row clickable" onClick={() => setHasDate((v) => !v)}>
          <span>{t.todo.setDueDate}</span>
          <span className={`modal-check ${hasDate ? "on" : "off"}`}>✓</span>
        </div>
        {hasDate && (
          <div className="modal-row">
            <input
              type="datetime-local"
              value={dueDate}
              onChange={(e) => setDueDate(e.target.value)}
            />
          </div>
        )}
      </div>

      <div className="modal-section">
        <div className="modal-row clickable" onClick={() => setIsUrgent((v) => !v)}>
          <span>{t.todo.urgent}</span>
          <span className={`modal-check ${isUrgent ? "on" : "off"}`}>✓</span>
        </div>
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
