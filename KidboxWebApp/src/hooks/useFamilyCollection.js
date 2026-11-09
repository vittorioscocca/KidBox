import { useEffect, useState } from "react";
import { collection, onSnapshot, query, where } from "firebase/firestore";
import { db } from "../firebase";
import { listenSecure, SECURE_FIELDS } from "../services/sectionCrypto";

/**
 * Sottoscrizione generica a una sottocollezione di famiglia, filtrata sui
 * documenti non cancellati.
 *
 * Nessun `orderBy` nella query: combinarlo con il `where` richiederebbe un
 * indice composito su Firestore per ogni collezione. L'ordinamento avviene sui
 * dati già in memoria, che le sezioni scaricano comunque per intero.
 *
 * Le collezioni con campi in `secure` (`sectionCrypto.js`) arrivano già
 * risolte: chiaro non vuoto, altrimenti il valore cifrato.
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
    const toItems = (docs) => setItems(docs.map((d) => ({ id: d.id, ...d.data() })));
    const onErr = (err) => setError(err.message);
    if (SECURE_FIELDS[name]) return listenSecure(q, name, familyId, toItems, onErr);
    return onSnapshot(q, (snap) => toItems(snap.docs), onErr);
  }, [familyId, name, enabled]);

  return { items, error };
}
