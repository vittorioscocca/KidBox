import { createContext, useContext, useEffect, useMemo, useState } from "react";
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

  useEffect(() => {
    if (!user) return;
    let cancelled = false;
    async function load() {
      try {
        const membershipsSnap = await getDocs(
          collection(db, "users", user.uid, "memberships")
        );
        const results = await Promise.all(
          membershipsSnap.docs.map(async (m) => {
            const familySnap = await getDoc(doc(db, "families", m.id));
            const membersSnap = await getDocs(
              collection(db, "families", m.id, "members")
            );
            return {
              id: m.id,
              ...familySnap.data(),
              memberCount: membersSnap.size,
            };
          })
        );
        if (!cancelled) setFamilies(results);
      } catch (err) {
        if (!cancelled) setError(err.message);
      }
    }
    load();
    return () => {
      cancelled = true;
    };
  }, [user]);

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

  return (
    <FamilyContext.Provider
      value={{ families, error, currentFamily, currentFamilyId, selectFamily }}
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
