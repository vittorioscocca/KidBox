import { useState } from "react";
import { useNavigate, useParams } from "react-router-dom";
import { doc, serverTimestamp, setDoc } from "firebase/firestore";
import { useFamily } from "../FamilyContext";
import { useAuth } from "../AuthContext";
import { useTodos, todosCol } from "../hooks/useTodos";
import { useTodoLists } from "../hooks/useTodoLists";
import { useChildren } from "../hooks/useChildren";
import { useFamilyMembers } from "../hooks/useFamilyMembers";
import { filterTodosForList } from "../todoFilters";
import { useTranslation } from "../i18n/LocaleContext";
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
  const { t } = useTranslation();
  const children = useChildren(currentFamilyId);
  const childId = children[0]?.id ?? "";
  const { todos, error } = useTodos(currentFamilyId, childId);
  const lists = useTodoLists(currentFamilyId, childId);
  const members = useFamilyMembers(currentFamilyId);
  const [showAdd, setShowAdd] = useState(false);

  const list = mode === "list" ? lists.find((l) => l.id === listId) : null;

  const items =
    mode === "filter"
      ? filterTodosForList(todos, filterKey, user.uid)
      : todos.filter((t) => t.listId === listId);

  const heading = mode === "filter" ? t.todo.filters[filterKey] : list?.name;
  const canAdd = !(mode === "filter" && filterKey === "completati");

  const assigneeName = (uid) => {
    if (!uid) return null;
    if (uid === user.uid) return user.displayName || t.todo.me;
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
          <button className="new-btn" onClick={() => setShowAdd(true)}>
            {t.todo.new}
          </button>
        )}
      </div>

      {error && <p className="error">{error}</p>}

      <ul className="detail-list">
        {items.map((todo) => {
          const assignee = assigneeName(todo.assignedTo);
          const due = todo.dueAt?.toDate?.();
          const isUrgent = (todo.priority ?? 0) === 1;
          const notes = (todo.notes || "").trim();

          return (
            <li key={todo.id}>
              <button className="check-circle" onClick={() => toggleDone(todo)}>
                {todo.isDone ? "●" : "○"}
              </button>
              <div className="todo-item-body">
                <div className="todo-item-title-row">
                  <span className={todo.isDone ? "done" : ""}>{todo.title}</span>
                  {isUrgent && <span className="urgent-badge">{t.todo.urgent}</span>}
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
                onClick={() => deleteTodo(todo)}
                title={t.todo.deleteTodo}
              >
                🗑
              </button>
            </li>
          );
        })}
        {items.length === 0 && <p className="hint">{t.todo.noItemsHere}</p>}
      </ul>

      {showAdd && (
        <TodoEditModal
          familyId={currentFamilyId}
          childId={list?.childId ?? childId}
          listId={mode === "list" ? listId : ""}
          listName={mode === "list" ? list?.name : t.todo.list}
          onClose={() => setShowAdd(false)}
        />
      )}
    </div>
  );
}
