import { useEffect, useState } from "react";
import { collection, query, where } from "firebase/firestore";
import { db } from "../firebase";
import { listenSecure } from "../services/sectionCrypto";

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
    // Il nome può stare in `secure`: arriva già risolto.
    return listenSecure(q, "todoLists", familyId, (docs) =>
      setLists(docs.map((d) => ({ id: d.id, ...d.data() })))
    );
  }, [familyId]);

  return lists;
}
