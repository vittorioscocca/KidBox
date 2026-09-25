import { createContext, useCallback, useContext, useEffect, useMemo, useState } from "react";
import { collection, doc, getDoc, getDocs, onSnapshot } from "firebase/firestore";
import { useAuth } from "./AuthContext";
import { db } from "./firebase";

const FamilyContext = createContext(null);

export function FamilyProvider({ children }) {
  const { user } = useAuth();
  const [families, setFamilies] = useState(null);
  const [error, setError] = useState(null);
  const [currentFamilyId, setCurrentFamilyId] = useState(
    () => localStorage.getItem("kidbox:currentFamilyId") || null
  );

  // Contatore che forza la rilettura: l'onboarding crea o aggiunge una
  // famiglia e la lista va ricaricata senza passare da un reload di pagina.
  const [reloadTick, setReloadTick] = useState(0);
  const reload = useCallback(() => setReloadTick((n) => n + 1), []);

  useEffect(() => {
    if (!user) return;
    let cancelled = false;
    async function load() {
      try {
        const membershipsSnap = await getDocs(
          collection(db, "users", user.uid, "memberships")
        );
        // Come `FamilyBootstrapService` su iOS: l'indice membership può
        // puntare a una famiglia che non c'è più (quella vuota dell'onboarding)
        // o da cui si è stati revocati. Lì la lettura è negata dalle regole, e
        // non deve bloccare tutte le altre: la famiglia si salta e basta.
        const results = await Promise.all(
          membershipsSnap.docs.map(async (m) => {
            try {
              const familySnap = await getDoc(doc(db, "families", m.id));
              if (!familySnap.exists()) return null;
              const membersSnap = await getDocs(
                collection(db, "families", m.id, "members")
              );
              return {
                id: m.id,
                ...familySnap.data(),
                memberCount: membersSnap.size,
              };
            } catch (err) {
              if (err?.code !== "permission-denied") throw err;
              console.warn(`[Family] membership orfana saltata: ${m.id}`);
              return null;
            }
          })
        );
        if (!cancelled) setFamilies(results.filter(Boolean));
      } catch (err) {
        if (!cancelled) setError(err.message);
      }
    }
    load();
    return () => {
      cancelled = true;
    };
  }, [user, reloadTick]);

  useEffect(() => {
    if (!families || families.length === 0) return;
    const stillValid = families.some((f) => f.id === currentFamilyId);
    if (!stillValid) {
      setCurrentFamilyId(families[0].id);
    }
  }, [families, currentFamilyId]);

  // Il documento della famiglia attiva va seguito in realtime, non letto una volta
  // sola: la foto hero e il nome possono cambiare da un altro device e devono
  // comparire qui senza ricaricare la pagina.
  useEffect(() => {
    if (!currentFamilyId) return;
    const unsub = onSnapshot(
      doc(db, "families", currentFamilyId),
      (snap) => {
        if (!snap.exists()) return;
        const data = snap.data();
        setFamilies((prev) =>
          prev?.map((f) => (f.id === snap.id ? { ...f, ...data } : f)) ?? prev
        );
      },
      (err) => setError(err.message)
    );
    return unsub;
  }, [currentFamilyId]);

  const selectFamily = (id) => {
    localStorage.setItem("kidbox:currentFamilyId", id);
    setCurrentFamilyId(id);
  };

  const currentFamily = useMemo(
    () => families?.find((f) => f.id === currentFamilyId) || null,
    [families, currentFamilyId]
  );

  // Alle pagine arriva solo una famiglia verificata. L'id salvato nel browser può
  // essere di un altro account passato di qui o di una famiglia da cui si è
  // usciti: per il render che precede la correzione qui sopra, le pagine
  // chiedevano la chiave di quella famiglia, ricevevano un rifiuto e mostravano
  // «chiave non disponibile» anche dopo aver caricato quella giusta.
  const validFamilyId = currentFamily ? currentFamilyId : null;

  return (
    <FamilyContext.Provider
      value={{ families, error, currentFamily, currentFamilyId: validFamilyId, selectFamily, reload }}
    >
      {children}
    </FamilyContext.Provider>
  );
}

export function useFamily() {
  const ctx = useContext(FamilyContext);
  if (!ctx) throw new Error("useFamily must be used within FamilyProvider");
  return ctx;
}
