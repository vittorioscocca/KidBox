import { useEffect, useState } from "react";
import {
  Timestamp,
  collection,
  doc,
  onSnapshot,
  query,
  serverTimestamp,
  setDoc,
  where,
} from "firebase/firestore";
import { db } from "../firebase";
import { useFamily } from "../FamilyContext";
import { useAuth } from "../AuthContext";
import "./Calendario.css";

const CATEGORIES = [
  { value: "children", label: "👶 Bambini", color: "#F1C40F" },
  { value: "school", label: "🏫 Scuola", color: "#3498DB" },
  { value: "health", label: "🏥 Salute", color: "#E74C3C" },
  { value: "family", label: "👨‍👩‍👧 Famiglia", color: "#2ECC71" },
  { value: "admin", label: "🧾 Amministrazione", color: "#7F8C8D" },
  { value: "leisure", label: "🎉 Tempo libero", color: "#9B59B6" },
];

function eventsCol(familyId) {
  return collection(db, "families", familyId, "calendarEvents");
}

function toLocalInputValue(date) {
  const pad = (n) => String(n).padStart(2, "0");
  return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}T${pad(date.getHours())}:${pad(date.getMinutes())}`;
}

export default function Calendario() {
  const { currentFamilyId } = useFamily();
  const { user } = useAuth();
  const [events, setEvents] = useState([]);
  const [error, setError] = useState(null);

  const [title, setTitle] = useState("");
  const [category, setCategory] = useState("family");
  const [start, setStart] = useState(toLocalInputValue(new Date()));

  useEffect(() => {
    if (!currentFamilyId) return;
    const q = query(eventsCol(currentFamilyId), where("isDeleted", "==", false));
    const unsub = onSnapshot(
      q,
      (snap) => {
        const list = snap.docs.map((d) => ({ id: d.id, ...d.data() }));
        list.sort(
          (a, b) => (a.startDate?.toMillis?.() ?? 0) - (b.startDate?.toMillis?.() ?? 0)
        );
        setEvents(list);
      },
      (err) => setError(err.message)
    );
    return unsub;
  }, [currentFamilyId]);

  const addEvent = async (e) => {
    e.preventDefault();
    if (!title.trim() || !currentFamilyId) return;
    const id = crypto.randomUUID();
    const startDate = new Date(start);
    const endDate = new Date(startDate.getTime() + 60 * 60 * 1000);
    try {
      await setDoc(doc(eventsCol(currentFamilyId), id), {
        id,
        familyId: currentFamilyId,
        title: title.trim(),
        isAllDay: false,
        categoryRaw: category,
        recurrenceRaw: "none",
        isDeleted: false,
        startDate: Timestamp.fromDate(startDate),
        endDate: Timestamp.fromDate(endDate),
        createdAt: serverTimestamp(),
        updatedAt: serverTimestamp(),
        updatedBy: user.uid,
        createdBy: user.uid,
        visibilityScope: "family",
        visibilityMemberIds: [],
      });
      setTitle("");
    } catch (err) {
      setError(err.message);
    }
  };

  const removeEvent = async (ev) => {
    try {
      await setDoc(
        doc(eventsCol(currentFamilyId), ev.id),
        { isDeleted: true, updatedAt: serverTimestamp(), updatedBy: user.uid },
        { merge: true }
      );
    } catch (err) {
      setError(err.message);
    }
  };

  const catInfo = (raw) => CATEGORIES.find((c) => c.value === raw) || CATEGORIES[3];

  return (
    <div>
      <h1>Calendario</h1>
      {error && <p className="error">{error}</p>}

      <form className="cal-form" onSubmit={addEvent}>
        <input
          placeholder="Nuovo evento..."
          value={title}
          onChange={(e) => setTitle(e.target.value)}
        />
        <select value={category} onChange={(e) => setCategory(e.target.value)}>
          {CATEGORIES.map((c) => (
            <option key={c.value} value={c.value}>
              {c.label}
            </option>
          ))}
        </select>
        <input
          type="datetime-local"
          value={start}
          onChange={(e) => setStart(e.target.value)}
        />
        <button type="submit">Aggiungi</button>
      </form>

      <ul className="cal-list">
        {events.map((ev) => {
          const cat = catInfo(ev.categoryRaw);
          const date = ev.startDate?.toDate?.();
          return (
            <li key={ev.id}>
              <span className="cal-dot" style={{ background: cat.color }} />
              <div className="cal-info">
                <strong>{ev.title}</strong>
                <span className="cal-meta">
                  {date
                    ? date.toLocaleString("it-IT", {
                        weekday: "short",
                        day: "numeric",
                        month: "short",
                        hour: "2-digit",
                        minute: "2-digit",
                      })
                    : ""}{" "}
                  · {cat.label}
                </span>
              </div>
              <button className="cal-remove" onClick={() => removeEvent(ev)}>
                ✕
              </button>
            </li>
          );
        })}
        {events.length === 0 && <p className="hint">Nessun evento in programma.</p>}
      </ul>
    </div>
  );
}
