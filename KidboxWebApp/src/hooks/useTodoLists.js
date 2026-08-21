import { useEffect, useState } from "react";
import { collection, onSnapshot, query, where } from "firebase/firestore";
import { db } from "../firebase";

export function todoListsCol(familyId) {
  return collection(db, "families", familyId, "todoLists");
}

export function useTodoLists(familyId, childId) {
  const [lists, setLists] = useState([]);

  useEffect(() => {
    if (!familyId || childId === undefined) {
      setLists([]);
      return;
    }
    const q = query(
      todoListsCol(familyId),
      where("isDeleted", "==", false),
      where("childId", "==", childId)
    );
    const unsub = onSnapshot(q, (snap) =>
      setLists(snap.docs.map((d) => ({ id: d.id, ...d.data() })))
    );
    return unsub;
  }, [familyId, childId]);

  return lists;
}
