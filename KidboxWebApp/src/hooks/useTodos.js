import { useEffect, useState } from "react";
import { collection, onSnapshot, query, where } from "firebase/firestore";
import { db } from "../firebase";
import { isVisibleTo } from "../visibility";

export function todosCol(familyId) {
  return collection(db, "families", familyId, "todos");
}

// I todo sono di FAMIGLIA: non si filtra per childId, come su iOS e Android.
// Il campo resta sui documenti e continua a essere scritto, ma non è mai stato
// uno scoping vero — `children[0]` su una query senza `orderBy` non ha ordine
// garantito, quindi con due figli il web poteva mostrare un elenco diverso da
// quello dell'app. Vedi il commento esteso in TodoHomeView.swift.
//
// Si filtra invece per visibilità, come `isVisible(to:)` in TodoHomeView,
// TodoListView e TodoSmartListView: i to-do «Solo io» o «Membri selezionati»
// di un altro membro non arrivano alle viste.
export function useTodos(familyId, uid) {
  const [todos, setTodos] = useState([]);
  const [error, setError] = useState(null);

  useEffect(() => {
    if (!familyId) {
      setTodos([]);
      return;
    }
    const q = query(
      todosCol(familyId),
      where("isDeleted", "==", false)
    );
    const unsub = onSnapshot(
      q,
      (snap) =>
        setTodos(
          snap.docs
            .map((d) => ({ id: d.id, ...d.data() }))
            .filter((todo) => isVisibleTo(todo, uid))
        ),
      (err) => setError(err.message)
    );
    return unsub;
  }, [familyId, uid]);

  return { todos, error };
}
