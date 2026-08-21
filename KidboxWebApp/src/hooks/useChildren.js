import { useEffect, useState } from "react";
import { collection, onSnapshot, query } from "firebase/firestore";
import { db } from "../firebase";

export function useChildren(familyId) {
  const [children, setChildren] = useState([]);

  useEffect(() => {
    if (!familyId) return;
    const q = query(collection(db, "families", familyId, "children"));
    const unsub = onSnapshot(q, (snap) => {
      setChildren(snap.docs.map((d) => ({ id: d.id, ...d.data() })));
    });
    return unsub;
  }, [familyId]);

  return children;
}
