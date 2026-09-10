import { useEffect, useState } from "react";
import { collection, onSnapshot, query, where } from "firebase/firestore";
import { db } from "../firebase";

export function todoListsCol(familyId) {
  return collection(db, "families", familyId, "todoLists");
}

// Come `useTodos`: nessun filtro per childId, le liste sono di famiglia.
export function useTodoLists(familyId) {
  const [lists, setLists] = useState([]);

  useEffect(() => {
    if (!familyId) {
      setLists([]);
      return;
    }
    const q = query(
      todoListsCol(familyId),
      where("isDeleted", "==", false)
    );
    const unsub = onSnapshot(q, (snap) =>
      setLists(snap.docs.map((d) => ({ id: d.id, ...d.data() })))
    );
    return unsub;
  }, [familyId]);

  return lists;
}
