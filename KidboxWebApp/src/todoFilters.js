function isToday(date) {
  if (!date) return false;
  const now = new Date();
  return (
    date.getFullYear() === now.getFullYear() &&
    date.getMonth() === now.getMonth() &&
    date.getDate() === now.getDate()
  );
}

export const TODO_FILTERS = [
  {
    key: "oggi",
    label: "Oggi",
    icon: "📅",
    color: "#E8833A",
    predicate: (t) => t.isDone !== true && isToday(t.dueAt?.toDate?.()),
  },
  {
    // Nel client nativo il badge "Tutti" conta solo i non completati, ma la
    // lista che si apre mostra TUTTI gli elementi (anche quelli fatti) —
    // vedi listPredicate sotto, usato solo per il contenuto della lista.
    key: "tutti",
    label: "Tutti",
    icon: "📋",
    color: "#3498DB",
    predicate: (t) => t.isDone !== true,
    listPredicate: () => true,
  },
  {
    key: "assegnati-a-me",
    label: "Assegnati a me",
    icon: "🙋",
    color: "#3EC6C1",
    predicate: (t, uid) => t.isDone !== true && t.assignedTo === uid,
  },
  {
    key: "completati",
    label: "Completati",
    icon: "✅",
    color: "#2ECC71",
    predicate: (t) => t.isDone === true,
  },
  {
    key: "non-assegnati-a-me",
    label: "Non assegnati a me",
    icon: "👥",
    color: "#9B59B6",
    predicate: (t, uid) => t.isDone !== true && t.assignedTo !== uid,
  },
  {
    key: "non-completati",
    label: "Non completati",
    icon: "⭕",
    color: "#E74C3C",
    predicate: (t) => t.isDone !== true,
  },
];

export function filterTodos(todos, filterKey, uid) {
  const filter = TODO_FILTERS.find((f) => f.key === filterKey);
  if (!filter) return [];
  return todos.filter((t) => filter.predicate(t, uid));
}

// Per il contenuto della lista aperta (non per il conteggio nel badge):
// alcuni filtri mostrano più elementi di quanti ne conta il badge.
export function filterTodosForList(todos, filterKey, uid) {
  const filter = TODO_FILTERS.find((f) => f.key === filterKey);
  if (!filter) return [];
  const predicate = filter.listPredicate || filter.predicate;
  return todos.filter((t) => predicate(t, uid));
}
