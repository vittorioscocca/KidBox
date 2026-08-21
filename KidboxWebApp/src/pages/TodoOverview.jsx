import { useState } from "react";
import { useNavigate } from "react-router-dom";
import { doc, serverTimestamp, writeBatch } from "firebase/firestore";
import { db } from "../firebase";
import { useFamily } from "../FamilyContext";
import { useAuth } from "../AuthContext";
import { useTodos, todosCol } from "../hooks/useTodos";
import { useTodoLists, todoListsCol } from "../hooks/useTodoLists";
import { useChildren } from "../hooks/useChildren";
import { TODO_FILTERS, filterTodos } from "../todoFilters";
import NewListModal from "../components/NewListModal";
import "./TodoOverview.css";

export default function TodoOverview() {
  const { currentFamilyId } = useFamily();
  const { user } = useAuth();
  const children = useChildren(currentFamilyId);
  const childId = children[0]?.id ?? "";
  const { todos, error } = useTodos(currentFamilyId, childId);
  const lists = useTodoLists(currentFamilyId, childId);
  const navigate = useNavigate();
  const [showNewList, setShowNewList] = useState(false);

  const deleteList = async (e, list) => {
    e.stopPropagation();
    // Come iOS/Android: eliminare una lista elimina (soft-delete) anche tutti
    // i to-do al suo interno, non solo la lista.
    const batch = writeBatch(db);
    todos
      .filter((t) => t.listId === list.id)
      .forEach((t) => {
        batch.set(
          doc(todosCol(currentFamilyId), t.id),
          { isDeleted: true, updatedBy: user.uid, updatedAt: serverTimestamp() },
          { merge: true }
        );
      });
    batch.set(
      doc(todoListsCol(currentFamilyId), list.id),
      { isDeleted: true, updatedBy: user.uid, updatedAt: serverTimestamp() },
      { merge: true }
    );
    await batch.commit();
  };

  return (
    <div>
      <div className="overview-header">
        <h1>To-Do</h1>
        <button className="round-btn" onClick={() => setShowNewList(true)} title="Nuova lista">
          +
        </button>
      </div>
      {error && <p className="error">{error}</p>}

      <h2 className="section-title">Panoramica</h2>
      <div className="todo-grid">
        {TODO_FILTERS.map((f) => (
          <button
            key={f.key}
            className="todo-card"
            onClick={() => navigate(`/todo/filtro/${f.key}`)}
          >
            <span className="todo-card-icon" style={{ background: `${f.color}22`, color: f.color }}>
              {f.icon}
            </span>
            <span className="todo-card-label">{f.label}</span>
            <span className="todo-card-count" style={{ background: f.color }}>
              {filterTodos(todos, f.key, user.uid).length}
            </span>
          </button>
        ))}
      </div>

      {lists.length > 0 && (
        <>
          <h2 className="section-title">Le mie liste</h2>
          <div className="todo-list-rows">
            {lists.map((l) => (
              <div
                key={l.id}
                className="todo-list-row"
                onClick={() => navigate(`/todo/lista/${l.id}`)}
              >
                <span className="todo-row-icon">📋</span>
                <span className="todo-list-row-name">{l.name}</span>
                <button
                  className="row-delete-btn"
                  onClick={(e) => deleteList(e, l)}
                  title="Elimina lista"
                >
                  🗑
                </button>
                <span className="chev">›</span>
              </div>
            ))}
          </div>
        </>
      )}

      {showNewList && (
        <NewListModal
          familyId={currentFamilyId}
          childId={childId}
          onClose={() => setShowNewList(false)}
        />
      )}
    </div>
  );
}
