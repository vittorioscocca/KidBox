import { useState } from "react";
import { useNavigate, useParams } from "react-router-dom";
import { doc, serverTimestamp, setDoc } from "firebase/firestore";
import { useFamily } from "../FamilyContext";
import { useAuth } from "../AuthContext";
import { useTodos, todosCol } from "../hooks/useTodos";
import { useTodoLists } from "../hooks/useTodoLists";
import { useChildren } from "../hooks/useChildren";
import { useFamilyMembers } from "../hooks/useFamilyMembers";
import { TODO_FILTERS, filterTodosForList } from "../todoFilters";
import TodoEditModal from "../components/TodoEditModal";
import "./TodoDetail.css";

const MONTHS_IT = ["gen", "feb", "mar", "apr", "mag", "giu", "lug", "ago", "set", "ott", "nov", "dic"];

function formatDue(date) {
  const pad = (n) => String(n).padStart(2, "0");
  return `${date.getDate()} ${MONTHS_IT[date.getMonth()]}, ${pad(date.getHours())}:${pad(date.getMinutes())}`;
}

export default function TodoDetail({ mode }) {
  const { filterKey, listId } = useParams();
  const navigate = useNavigate();
  const { currentFamilyId } = useFamily();
  const { user } = useAuth();
  const children = useChildren(currentFamilyId);
  const childId = children[0]?.id ?? "";
  const { todos, error } = useTodos(currentFamilyId, childId);
  const lists = useTodoLists(currentFamilyId, childId);
  const members = useFamilyMembers(currentFamilyId);
  const [showAdd, setShowAdd] = useState(false);

  const list = mode === "list" ? lists.find((l) => l.id === listId) : null;
  const filter = mode === "filter" ? TODO_FILTERS.find((f) => f.key === filterKey) : null;

  const items =
    mode === "filter"
      ? filterTodosForList(todos, filterKey, user.uid)
      : todos.filter((t) => t.listId === listId);

  const heading = mode === "filter" ? filter?.label : list?.name;
  const canAdd = !(mode === "filter" && filterKey === "completati");

  const assigneeName = (uid) => {
    if (!uid) return null;
    if (uid === user.uid) return user.displayName || "Me";
    return members.find((m) => m.id === uid)?.displayName || null;
  };

  const toggleDone = async (todo) => {
    await setDoc(
      doc(todosCol(currentFamilyId), todo.id),
      {
        isDone: !todo.isDone,
        doneAt: !todo.isDone ? serverTimestamp() : null,
        doneBy: !todo.isDone ? user.uid : null,
        updatedBy: user.uid,
        updatedAt: serverTimestamp(),
      },
      { merge: true }
    );
  };

  const deleteTodo = async (todo) => {
    await setDoc(
      doc(todosCol(currentFamilyId), todo.id),
      { isDeleted: true, updatedBy: user.uid, updatedAt: serverTimestamp() },
      { merge: true }
    );
  };

  return (
    <div>
      <div className="detail-header">
        <button className="back-btn" onClick={() => navigate("/todo")}>
          ‹
        </button>
        <h1 style={{ flex: 1 }}>{heading}</h1>
        {canAdd && (
          <button className="back-btn" onClick={() => setShowAdd(true)}>
            +
          </button>
        )}
      </div>

      {error && <p className="error">{error}</p>}

      <ul className="detail-list">
        {items.map((t) => {
          const assignee = assigneeName(t.assignedTo);
          const due = t.dueAt?.toDate?.();
          const isUrgent = (t.priority ?? 0) === 1;
          const notes = (t.notes || "").trim();

          return (
            <li key={t.id}>
              <button className="check-circle" onClick={() => toggleDone(t)}>
                {t.isDone ? "●" : "○"}
              </button>
              <div className="todo-item-body">
                <div className="todo-item-title-row">
                  <span className={t.isDone ? "done" : ""}>{t.title}</span>
                  {isUrgent && <span className="urgent-badge">Urgente</span>}
                </div>
                {(assignee || due) && (
                  <div className="todo-item-meta">
                    {assignee && <span>👤 {assignee}</span>}
                    {due && <span>🕐 {formatDue(due)}</span>}
                  </div>
                )}
                {notes && <div className="todo-item-notes">{notes}</div>}
              </div>
              <button
                className="row-delete-btn"
                onClick={() => deleteTodo(t)}
                title="Elimina to-do"
              >
                🗑
              </button>
            </li>
          );
        })}
        {items.length === 0 && <p className="hint">Nessun elemento qui.</p>}
      </ul>

      {showAdd && (
        <TodoEditModal
          familyId={currentFamilyId}
          childId={list?.childId ?? childId}
          listId={mode === "list" ? listId : ""}
          listName={mode === "list" ? list?.name : "Lista"}
          onClose={() => setShowAdd(false)}
        />
      )}
    </div>
  );
}
