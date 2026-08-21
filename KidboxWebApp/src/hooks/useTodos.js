import { useEffect, useState } from "react";
import { collection, onSnapshot, query, where } from "firebase/firestore";
import { db } from "../firebase";

export function todosCol(familyId) {
  return collection(db, "families", familyId, "todos");
}

// Il client nativo scopa i todo sul primo (unico) figlio della famiglia
// (childId = "" se la famiglia non ha ancora un bambino, mai bloccato).
// Replichiamo la stessa logica per restare coerenti con l'app iOS/Android.
export function useTodos(familyId, childId) {
  const [todos, setTodos] = useState([]);
  const [error, setError] = useState(null);

  useEffect(() => {
    if (!familyId || childId === undefined) {
      setTodos([]);
      return;
    }
    const q = query(
      todosCol(familyId),
      where("isDeleted", "==", false),
      where("childId", "==", childId)
    );
    const unsub = onSnapshot(
      q,
      (snap) => setTodos(snap.docs.map((d) => ({ id: d.id, ...d.data() }))),
      (err) => setError(err.message)
    );
    return unsub;
  }, [familyId, childId]);

  return { todos, error };
}
