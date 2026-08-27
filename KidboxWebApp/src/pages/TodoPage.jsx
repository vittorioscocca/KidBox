import { useMemo, useState } from "react";
import { doc, serverTimestamp, setDoc, writeBatch } from "firebase/firestore";
import { db } from "../firebase";
import { useFamily } from "../FamilyContext";
import { useAuth } from "../AuthContext";
import { useTranslation } from "../i18n/LocaleContext";
import { useTodos, todosCol } from "../hooks/useTodos";
import { useTodoLists, todoListsCol } from "../hooks/useTodoLists";
import { useChildren } from "../hooks/useChildren";
import { useFamilyMembers } from "../hooks/useFamilyMembers";
import { TODO_FILTERS, filterTodos, filterTodosForList } from "../todoFilters";
import NewListModal from "../components/NewListModal";
import TodoEditModal from "../components/TodoEditModal";
import "./TodoPage.css";

function fmtDate(date, locale, withTime = false) {
  if (!date) return "";
  return new Intl.DateTimeFormat(locale === "en" ? "en-US" : "it-IT", {
    day: "2-digit",
    month: "2-digit",
    year: "2-digit",
    ...(withTime ? { hour: "2-digit", minute: "2-digit" } : {}),
  }).format(date);
}

export default function TodoPage() {
  const { currentFamilyId } = useFamily();
  const { user } = useAuth();
  const { t, locale } = useTranslation();

  const children = useChildren(currentFamilyId);
  const childId = children[0]?.id ?? "";
  const { todos, error } = useTodos(currentFamilyId, childId);
  const lists = useTodoLists(currentFamilyId, childId);
  const members = useFamilyMembers(currentFamilyId);

  // Una sola selezione: o un filtro, o un elenco.
  const [selection, setSelection] = useState({ type: "filter", key: "tutti" });
  const [showNewList, setShowNewList] = useState(false);
  const [showAdd, setShowAdd] = useState(false);
  const [editing, setEditing] = useState(null);
  const [localError, setLocalError] = useState(null);
  const [search, setSearch] = useState("");

  const activeFilter =
    selection.type === "filter"
      ? TODO_FILTERS.find((f) => f.key === selection.key)
      : null;
  const activeList =
    selection.type === "list" ? lists.find((l) => l.id === selection.key) : null;

  const items = useMemo(() => {
    const base =
      selection.type === "filter"
        ? filterTodosForList(todos, selection.key, user.uid)
        : todos.filter((todo) => todo.listId === selection.key);

    const q = search.trim().toLowerCase();
    if (!q) return base;
    return base.filter(
      (todo) =>
        todo.title.toLowerCase().includes(q) ||
        (todo.notes ?? "").toLowerCase().includes(q)
    );
  }, [todos, selection, user.uid, search]);

  const heading = activeFilter ? t.todo.filters[activeFilter.key] : activeList?.name;
  const headingColor = activeFilter?.color ?? "var(--accent)";
  const isCompletedView = selection.type === "filter" && selection.key === "completati";
  const canAdd = !isCompletedView;

  const listName = (id) => lists.find((l) => l.id === id)?.name ?? "";
  const assigneeName = (uid) => {
    if (!uid) return null;
    if (uid === user.uid) return user.displayName || t.todo.me;
    return members.find((m) => m.id === uid)?.displayName || null;
  };

  const toggleDone = async (todo) => {
    try {
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
    } catch (err) {
      setLocalError(err.message);
    }
  };

  const deleteTodo = async (todo) => {
    try {
      await setDoc(
        doc(todosCol(currentFamilyId), todo.id),
        { isDeleted: true, updatedBy: user.uid, updatedAt: serverTimestamp() },
        { merge: true }
      );
    } catch (err) {
      setLocalError(err.message);
    }
  };

  /** Come deleteAllCompleted su iOS: svuota in blocco la vista Completati. */
  const deleteAllCompleted = async () => {
    const batch = writeBatch(db);
    items.forEach((todo) => {
      batch.set(
        doc(todosCol(currentFamilyId), todo.id),
        { isDeleted: true, updatedBy: user.uid, updatedAt: serverTimestamp() },
        { merge: true }
      );
    });
    try {
      await batch.commit();
    } catch (err) {
      setLocalError(err.message);
    }
  };

  const deleteList = async (e, list) => {
    e.stopPropagation();
    // Eliminando un elenco spariscono anche i suoi to-do, come su iOS/Android.
    const batch = writeBatch(db);
    todos
      .filter((todo) => todo.listId === list.id)
      .forEach((todo) => {
        batch.set(
          doc(todosCol(currentFamilyId), todo.id),
          { isDeleted: true, updatedBy: user.uid, updatedAt: serverTimestamp() },
          { merge: true }
        );
      });
    batch.set(
      doc(todoListsCol(currentFamilyId), list.id),
      { isDeleted: true, updatedBy: user.uid, updatedAt: serverTimestamp() },
      { merge: true }
    );
    try {
      await batch.commit();
      if (selection.type === "list" && selection.key === list.id) {
        setSelection({ type: "filter", key: "tutti" });
      }
    } catch (err) {
      setLocalError(err.message);
    }
  };

  return (
    <div className="todo-page">
      <aside className="todo-sidebar">
        <div className="filter-grid">
          {TODO_FILTERS.map((f) => {
            const active = selection.type === "filter" && selection.key === f.key;
            return (
              <button
                key={f.key}
                className={"filter-card" + (active ? " active" : "")}
                style={
                  active
                    ? { background: `color-mix(in srgb, ${f.color} 30%, transparent)` }
                    : null
                }
                onClick={() => setSelection({ type: "filter", key: f.key })}
              >
                <span className="filter-top">
                  <span className="filter-icon" style={{ color: f.color }}>
                    {f.icon}
                  </span>
                  <span className="filter-count">
                    {filterTodos(todos, f.key, user.uid).length}
                  </span>
                </span>
                <span className="filter-label">{t.todo.filters[f.key]}</span>
              </button>
            );
          })}
        </div>

        <div className="lists-head">
          <span>{t.todo.myLists}</span>
          <button
            className="lists-add"
            onClick={() => setShowNewList(true)}
            title={t.todo.newList}
          >
            +
          </button>
        </div>

        <div className="lists-scroll">
          {lists.map((l) => {
            const active = selection.type === "list" && selection.key === l.id;
            const count = todos.filter(
              (todo) => todo.listId === l.id && !todo.isDone
            ).length;
            return (
              <div
                key={l.id}
                className={"list-row" + (active ? " active" : "")}
                onClick={() => setSelection({ type: "list", key: l.id })}
              >
                <span className="list-bullet">📋</span>
                <span className="list-name">{l.name}</span>
                <button
                  className="list-delete"
                  onClick={(e) => deleteList(e, l)}
                  title={t.todo.deleteList}
                >
                  🗑
                </button>
                <span className="list-count">{count}</span>
              </div>
            );
          })}
          {lists.length === 0 && <p className="lists-empty">{t.todo.noListsYet}</p>}
        </div>
      </aside>

      <section className="todo-main">
        {(error || localError) && <p className="error">{error || localError}</p>}

        <div className="main-toolbar">
          {canAdd && (
            <button
              className="toolbar-add"
              onClick={() => setShowAdd(true)}
              title={t.todo.new}
            >
              +
            </button>
          )}
          <div className="toolbar-search">
            <span className="search-icon">🔍</span>
            <input
              placeholder={t.todo.search}
              value={search}
              onChange={(e) => setSearch(e.target.value)}
            />
            {search && (
              <button className="search-clear" onClick={() => setSearch("")}>
                ✕
              </button>
            )}
          </div>
        </div>

        <div className="main-head">
          <h1 style={{ color: headingColor }}>{heading}</h1>
          <span className="main-count" style={{ color: headingColor }}>
            {items.length}
          </span>
        </div>

        {isCompletedView && items.length > 0 && (
          <div className="main-subhead">
            {t.todo.completedCount(items.length)}
            <span className="dot">•</span>
            <button className="link-btn" onClick={deleteAllCompleted}>
              {t.todo.deleteCompleted}
            </button>
          </div>
        )}

        <ul className="todo-items">
          {items.map((todo) => {
            const due = todo.dueAt?.toDate?.();
            const done = todo.doneAt?.toDate?.();
            const assignee = assigneeName(todo.assignedTo);
            const isUrgent = (todo.priority ?? 0) === 1;
            const notes = (todo.notes || "").trim();
            return (
              <li key={todo.id}>
                <button
                  className="item-check"
                  onClick={() => toggleDone(todo)}
                  title={todo.title}
                >
                  {todo.isDone ? "◉" : "○"}
                </button>
                <div className="item-body" onClick={() => setEditing(todo)}>
                  <div className="item-title-row">
                    <span className={todo.isDone ? "done" : ""}>{todo.title}</span>
                    {isUrgent && <span className="urgent-badge">{t.todo.urgent}</span>}
                  </div>
                  <div className="item-meta">
                    {todo.listId && <span>{listName(todo.listId)}</span>}
                    {due && <span>{fmtDate(due, locale, true)}</span>}
                    {assignee && <span>👤 {assignee}</span>}
                  </div>
                  {done && (
                    <div className="item-meta">
                      {t.todo.completedAt}: {fmtDate(done, locale, true)}
                    </div>
                  )}
                  {notes && <div className="item-notes">{notes}</div>}
                </div>
                <button
                  className="item-delete"
                  onClick={() => deleteTodo(todo)}
                  title={t.todo.deleteTodo}
                >
                  🗑
                </button>
              </li>
            );
          })}
          {items.length === 0 && (
            <p className="hint">
              {search.trim() ? t.todo.noResults : t.todo.noItemsHere}
            </p>
          )}
        </ul>
      </section>

      {showNewList && (
        <NewListModal
          familyId={currentFamilyId}
          childId={childId}
          onClose={() => setShowNewList(false)}
        />
      )}

      {(showAdd || editing) && (
        <TodoEditModal
          familyId={currentFamilyId}
          childId={activeList?.childId ?? childId}
          listId={activeList?.id ?? ""}
          listName={activeList?.name ?? t.todo.list}
          todo={editing}
          onClose={() => {
            setShowAdd(false);
            setEditing(null);
          }}
        />
      )}
    </div>
  );
}
