import { useState } from "react";
import { doc, serverTimestamp, setDoc } from "firebase/firestore";
import { todosCol } from "../hooks/useTodos";
import { useAuth } from "../AuthContext";
import { useFamilyMembers } from "../hooks/useFamilyMembers";
import { useTranslation } from "../i18n/LocaleContext";
import { VISIBILITY_FAMILY, VISIBILITY_MEMBERS, normalizedVisibilityScope } from "../visibility";
import { useFamily } from "../FamilyContext";
import { createRequest, requestAvailability } from "../services/requests";
import { useTodos } from "../hooks/useTodos";
import { useFamilyCollection } from "../hooks/useFamilyCollection";
import Modal from "./Modal";
import VisibilityPickerModal, { visibilityChipLabel } from "./VisibilityPickerModal";
import { AskRequestRow, AskRequestView, RequestSentView } from "./FamilyRequests";

function toLocalInputValue(date) {
  const pad = (n) => String(n).padStart(2, "0");
  return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}T${pad(date.getHours())}:${pad(date.getMinutes())}`;
}

export default function TodoEditModal({ familyId, childId, listId, listName, todo, onClose }) {
  const isEdit = Boolean(todo);
  const { user } = useAuth();
  const { t } = useTranslation();
  const members = useFamilyMembers(familyId);
  const { currentFamily } = useFamily();

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
  const [view, setView] = useState("main"); // main | assignee | visibility | ask
  const [visibilityLocked, setVisibilityLocked] = useState(false);
  const [error, setError] = useState(null);
  // «Chiedi a…»: invece del to-do si crea una richiesta; il to-do lo crea il
  // server alla prima risposta «Ci penso io», in questa lista. Solo per un
  // to-do nuovo visibile a tutta la famiglia, come su iOS e Android.
  const [askDraft, setAskDraft] = useState(null);
  const [sentRequest, setSentRequest] = useState(null);
  const [sending, setSending] = useState(false);
  const canAsk = !isEdit && Boolean(listId) && visibilityScope === VISIBILITY_FAMILY;
  const otherMembers = members.filter((m) => m.id !== user.uid);
  // «Chi è libero»: to-do ed eventi servono solo quando si può chiedere.
  const { todos: familyTodos } = useTodos(canAsk ? familyId : null, user.uid);
  const { items: calendarEvents } = useFamilyCollection(familyId, "calendarEvents", { enabled: canAsk });

  const assigneeLabel = () => {
    // Vuoto (non nullo) = preso da fuori dall'app con una richiesta.
    if (assignedTo === "" && (todo?.assignedExternalName || "").trim()) {
      return t.requests.externalAssignee(todo.assignedExternalName.trim());
    }
    if (!assignedTo) return t.todo.none;
    if (assignedTo === user.uid) return t.todo.me;
    return members.find((m) => m.id === assignedTo)?.displayName || t.todo.none;
  };

  const sendRequest = async (trimmed) => {
    setSending(true);
    setError(null);
    try {
      const created = await createRequest({
        familyId,
        childId,
        listId,
        uid: user.uid,
        title: trimmed,
        notes: notes.trim() || null,
        isUrgent,
        dueAt: hasDate ? new Date(dueDate) : null,
        draft: askDraft,
        familyName: currentFamily?.name || "",
        inviterDisplayName: user.displayName || "",
      });
      if (created.shareLink) setSentRequest(created);
      else onClose();
    } catch (err) {
      setError(err.message === "DUE_IN_PAST" ? t.requests.dueInPast : err.message || t.requests.sendFailed);
    } finally {
      setSending(false);
    }
  };

  const save = async () => {
    const trimmed = title.trim();
    if (!trimmed) return;
    if (askDraft && canAsk) {
      await sendRequest(trimmed);
      return;
    }
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

  if (sentRequest) {
    return (
      <RequestSentView
        created={sentRequest}
        title={title.trim()}
        dueAt={hasDate ? new Date(dueDate) : null}
        onDone={onClose}
      />
    );
  }

  if (view === "ask") {
    return (
      <AskRequestView
        initial={askDraft}
        members={otherMembers}
        availability={
          hasDate
            ? requestAvailability({
                around: new Date(dueDate),
                todos: familyTodos,
                events: calendarEvents,
                uid: user.uid,
              })
            : null
        }
        onBack={() => setView("main")}
        onConfirm={(d) => {
          setAskDraft(d);
          setView("main");
        }}
      />
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
          if (scope !== VISIBILITY_FAMILY) setAskDraft(null);
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
        <button className="modal-save-btn" disabled={!title.trim() || sending} onClick={save}>
          {sending ? "…" : askDraft && canAsk ? "➤" : "✓"}
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

      <div className="modal-label">{askDraft && canAsk ? t.requests.askSection : t.todo.assignedTo}</div>
      <div className="modal-section">
        {!(askDraft && canAsk) && (
          <div className="modal-row clickable" onClick={() => setView("assignee")}>
            <span>{assigneeLabel()}</span>
            <span>›</span>
          </div>
        )}
        {canAsk && (
          <AskRequestRow
            draft={askDraft}
            members={otherMembers}
            onEdit={() => setView("ask")}
            onClear={() => setAskDraft(null)}
          />
        )}
      </div>
    </Modal>
  );
}
