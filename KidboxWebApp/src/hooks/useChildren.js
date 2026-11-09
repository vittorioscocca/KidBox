import { useEffect, useState } from "react";
import { collection, query } from "firebase/firestore";
import { db } from "../firebase";
import { listenSecure } from "../services/sectionCrypto";

// Il nome del figlio può stare in `secure` (`sectionCrypto.js`): arriva già
// risolto, chiaro non vuoto altrimenti il valore cifrato.
export function useChildren(familyId) {
  const [children, setChildren] = useState([]);

  useEffect(() => {
    if (!familyId) return;
    const q = query(collection(db, "families", familyId, "children"));
    return listenSecure(q, "children", familyId, (docs) =>
      setChildren(docs.map((d) => ({ id: d.id, ...d.data() })))
    );
  }, [familyId]);

  return children;
}
