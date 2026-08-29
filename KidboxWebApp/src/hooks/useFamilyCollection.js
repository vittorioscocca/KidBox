import { useEffect, useState } from "react";
import { collection, onSnapshot, query, where } from "firebase/firestore";
import { db } from "../firebase";

/**
 * Sottoscrizione generica a una sottocollezione di famiglia, filtrata sui
 * documenti non cancellati.
 *
 * Nessun `orderBy` nella query: combinarlo con il `where` richiederebbe un
 * indice composito su Firestore per ogni collezione. L'ordinamento avviene sui
 * dati già in memoria, che le sezioni scaricano comunque per intero.
 */
export function useFamilyCollection(familyId, name, { enabled = true } = {}) {
  const [items, setItems] = useState([]);
  const [error, setError] = useState(null);

  useEffect(() => {
    if (!familyId || !enabled) {
      setItems([]);
      return undefined;
    }
    const q = query(
      collection(db, "families", familyId, name),
      where("isDeleted", "==", false)
    );
    return onSnapshot(
      q,
      (snap) => setItems(snap.docs.map((d) => ({ id: d.id, ...d.data() }))),
      (err) => setError(err.message)
    );
  }, [familyId, name, enabled]);

  return { items, error };
}
