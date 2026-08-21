import { useEffect, useState } from "react";
import { collection, onSnapshot, query, where } from "firebase/firestore";
import { db } from "../firebase";

export function useFamilyMembers(familyId) {
  const [members, setMembers] = useState([]);

  useEffect(() => {
    if (!familyId) return;
    const q = query(
      collection(db, "families", familyId, "members"),
      where("isDeleted", "==", false)
    );
    const unsub = onSnapshot(q, (snap) =>
      setMembers(snap.docs.map((d) => ({ id: d.id, ...d.data() })))
    );
    return unsub;
  }, [familyId]);

  return members;
}
