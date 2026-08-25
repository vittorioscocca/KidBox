import { useState } from "react";
import { doc, serverTimestamp, setDoc } from "firebase/firestore";
import { todosCol } from "../hooks/useTodos";
import { useAuth } from "../AuthContext";
import { useFamilyMembers } from "../hooks/useFamilyMembers";
import { useTranslation } from "../i18n/LocaleContext";
import Modal from "./Modal";

function toLocalInputValue(date) {
  const pad = (n) => String(n).padStart(2, "0");
  return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}T${pad(date.getHours())}:${pad(date.getMinutes())}`;
}

export default function TodoEditModal({ familyId, childId, listId, listName, onClose }) {
  const { user } = useAuth();
  const { t } = useTranslation();
  const members = useFamilyMembers(familyId);

  const VISIBILITY_OPTIONS = [
    { scope: "family", label: t.todo.family },
    { scope: "members", label: t.todo.members },
    { scope: "private", label: t.todo.onlyMe },
  ];
  const chipLabel = (scope) =>
    VISIBILITY_OPTIONS.find((o) => o.scope === scope)?.label || VISIBILITY_OPTIONS[0].label;

  const [title, setTitle] = useState("");
  const [notes, setNotes] = useState("");
  const [hasDate, setHasDate] = useState(false);
  const [dueDate, setDueDate] = useState(toLocalInputValue(new Date()));
  const [isUrgent, setIsUrgent] = useState(false);
  const [assignedTo, setAssignedTo] = useState(null);
  const [visibilityScope, setVisibilityScope] = useState("family");
  const [visibilityMemberIds, setVisibilityMemberIds] = useState(new Set());
  const [view, setView] = useState("main"); // main | assignee | visibility
  const [error, setError] = useState(null);

  const assigneeLabel = () => {
    if (!assignedTo) return t.todo.none;
    if (assignedTo === user.uid) return t.todo.me;
    return members.find((m) => m.id === assignedTo)?.displayName || t.todo.none;
  };

  const toggleVisibilityMember = (uid) => {
    setVisibilityMemberIds((prev) => {
      const next = new Set(prev);
      next.has(uid) ? next.delete(uid) : next.add(uid);
      return next;
    });
  };

  const save = async () => {
    const trimmed = title.trim();
    if (!trimmed) return;
    const id = crypto.randomUUID();
    const finalMemberIds =
      visibilityScope === "members"
        ? [...visibilityMemberIds].filter((uid) => uid !== user.uid)
        : [];
    try {
      await setDoc(doc(todosCol(familyId), id), {
        childId,
        title: trimmed,
        listId: listId || "",
        isDone: false,
        isDeleted: false,
        notes: notes.trim() || null,
        dueAt: hasDate ? new Date(dueDate) : null,
        doneAt: null,
        doneBy: null,
        assignedTo,
        priority: isUrgent ? 1 : 0,
        visibilityScope,
        visibilityMemberIds: finalMemberIds,
        createdBy: user.uid,
        updatedBy: user.uid,
        createdAt: serverTimestamp(),
        updatedAt: serverTimestamp(),
      });
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
      <Modal onClose={() => setView("main")}>
        <div className="modal-header">
          <button className="modal-text-btn" onClick={() => setView("main")}>
            {t.todo.cancel}
          </button>
          <button className="modal-save-btn" onClick={() => setView("main")}>
            {t.todo.confirm}
          </button>
        </div>
        <div className="modal-title">{t.todo.visibility}</div>
        <div className="modal-label">{t.todo.whoCanSee}</div>
        <div className="modal-section">
          {VISIBILITY_OPTIONS.map((opt) => (
            <button
              key={opt.scope}
              className="modal-option"
              onClick={() => {
                setVisibilityScope(opt.scope);
                if (opt.scope !== "members") setVisibilityMemberIds(new Set());
              }}
            >
              <span>{opt.label}</span>
              <span>{visibilityScope === opt.scope ? "●" : "○"}</span>
            </button>
          ))}
        </div>

        {visibilityScope === "members" && (
          <>
            <div className="modal-label">{t.todo.selectMembers}</div>
            <div className="modal-section">
              {members.map((m) => (
                <button
                  key={m.id}
                  className="modal-option"
                  onClick={() => toggleVisibilityMember(m.id)}
                >
                  <span>{m.id === user.uid ? t.todo.me : m.displayName || t.todo.none}</span>
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
        <button className="modal-icon-btn" onClick={onClose}>
          ✕
        </button>
        <button className="modal-save-btn" disabled={!title.trim()} onClick={save}>
          ✓
        </button>
      </div>
      <div className="modal-title">{t.todo.newInList(listName || t.todo.list)}</div>
      {error && <p className="error">{error}</p>}

      <button className="modal-chip" onClick={() => setView("visibility")}>
        {chipLabel(visibilityScope)}
      </button>

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
