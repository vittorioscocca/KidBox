import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import {
  collection,
  doc,
  deleteField,
  onSnapshot,
  query,
  serverTimestamp,
  setDoc,
  where,
} from "firebase/firestore";
import { db } from "../firebase";
import { useFamily } from "../FamilyContext";
import { useAuth } from "../AuthContext";
import { useTranslation } from "../i18n/LocaleContext";
import { MissingFamilyKeyError, loadFamilyKey } from "../services/familyKey";
import { encryptString, readField } from "../services/noteCrypto";
import { noteHtmlToText } from "../services/noteHtml";
import RichTextEditor from "../components/RichTextEditor";
import "./Note.css";

const DAY = 24 * 60 * 60 * 1000;

function groupFor(date, now) {
  if (!date) return "older";
  const diff = now - date;
  const sameDay =
    date.getDate() === now.getDate() &&
    date.getMonth() === now.getMonth() &&
    date.getFullYear() === now.getFullYear();
  if (sameDay) return "today";
  if (diff < 7 * DAY) return "last7";
  if (diff < 30 * DAY) return "last30";
  return "older";
}

function stamp(date, locale, group) {
  if (!date) return "";
  const loc = locale === "en" ? "en-US" : "it-IT";
  // Come Apple Notes: l'ora per oggi, la data per tutto il resto.
  if (group === "today") {
    return new Intl.DateTimeFormat(loc, { hour: "2-digit", minute: "2-digit" }).format(date);
  }
  return new Intl.DateTimeFormat(loc, {
    day: "2-digit",
    month: "2-digit",
    year: "2-digit",
  }).format(date);
}

export default function Note() {
  const { currentFamilyId } = useFamily();
  const { user } = useAuth();
  const { t, locale } = useTranslation();

  const [familyKey, setFamilyKey] = useState(null);
  const [keyError, setKeyError] = useState(null);
  const [rawNotes, setRawNotes] = useState([]);
  const [notes, setNotes] = useState([]);
  const [selectedId, setSelectedId] = useState(null);
  const [search, setSearch] = useState("");
  const [error, setError] = useState(null);

  const [draft, setDraft] = useState({ title: "", body: "" });
  const saveTimer = useRef(null);

  // 1. Chiave di famiglia (dall'escrow su Firestore).
  useEffect(() => {
    let cancelled = false;
    setFamilyKey(null);
    setKeyError(null);
    if (!currentFamilyId || !user) return undefined;

    loadFamilyKey({ familyId: currentFamilyId, userId: user.uid })
      .then((key) => {
        if (!cancelled) setFamilyKey(key);
      })
      .catch((err) => {
        if (!cancelled) {
          setKeyError(
            err instanceof MissingFamilyKeyError ? "missing" : err.message
          );
        }
      });
    return () => {
      cancelled = true;
    };
  }, [currentFamilyId, user]);

  // 2. Note in realtime (ancora cifrate).
  useEffect(() => {
    if (!currentFamilyId) return undefined;
    const q = query(
      collection(db, "families", currentFamilyId, "notes"),
      where("isDeleted", "==", false)
    );
    return onSnapshot(
      q,
      (snap) => setRawNotes(snap.docs.map((d) => ({ id: d.id, ...d.data() }))),
      (err) => setError(err.message)
    );
  }, [currentFamilyId]);

  // 3. Decifratura: fuori dal render, perché è asincrona.
  useEffect(() => {
    let cancelled = false;
    if (!familyKey) {
      setNotes([]);
      return undefined;
    }
    Promise.all(
      rawNotes.map(async (n) => {
        const body = await readField(n.bodyEnc, n.body, familyKey);
        return {
          ...n,
          title: await readField(n.titleEnc, n.title, familyKey),
          body,
          // Il corpo è HTML: il testo estratto serve per anteprima e ricerca.
          bodyText: noteHtmlToText(body),
        };
      })
    ).then((decoded) => {
      if (cancelled) return;
      decoded.sort(
        (a, b) => (b.updatedAt?.toMillis?.() ?? 0) - (a.updatedAt?.toMillis?.() ?? 0)
      );
      setNotes(decoded);
    });
    return () => {
      cancelled = true;
    };
  }, [rawNotes, familyKey]);

  const selected = useMemo(
    () => notes.find((n) => n.id === selectedId) ?? null,
    [notes, selectedId]
  );

  // Allinea la bozza quando cambia nota selezionata (non a ogni battuta).
  useEffect(() => {
    if (selected) setDraft({ title: selected.title, body: selected.body });
  }, [selectedId]); // eslint-disable-line react-hooks/exhaustive-deps

  const filtered = useMemo(() => {
    const q = search.trim().toLowerCase();
    if (!q) return notes;
    return notes.filter(
      (n) =>
        n.title.toLowerCase().includes(q) ||
        (n.bodyText ?? "").toLowerCase().includes(q)
    );
  }, [notes, search]);

  const grouped = useMemo(() => {
    const now = new Date();
    const buckets = { today: [], last7: [], last30: [], older: [] };
    filtered.forEach((n) => {
      buckets[groupFor(n.updatedAt?.toDate?.(), now)].push(n);
    });
    return buckets;
  }, [filtered]);

  const persist = useCallback(
    async (noteId, title, body) => {
      if (!familyKey || !currentFamilyId) return;
      try {
        await setDoc(
          doc(db, "families", currentFamilyId, "notes", noteId),
          {
            schemaVersion: 1,
            titleEnc: await encryptString(title, familyKey),
            bodyEnc: await encryptString(body, familyKey),
            // I client nativi rimuovono i campi in chiaro legacy a ogni scrittura.
            title: deleteField(),
            body: deleteField(),
            isDeleted: false,
            updatedBy: user.uid,
            updatedByName: user.displayName ?? null,
            updatedAt: serverTimestamp(),
          },
          { merge: true }
        );
      } catch (err) {
        setError(err.message);
      }
    },
    [familyKey, currentFamilyId, user]
  );

  // Salvataggio automatico, come nelle app native: nessun pulsante "salva".
  const onEdit = (patch) => {
    const next = { ...draft, ...patch };
    setDraft(next);
    if (!selectedId) return;
    clearTimeout(saveTimer.current);
    saveTimer.current = setTimeout(() => {
      persist(selectedId, next.title, next.body);
    }, 600);
  };

  const createNote = async () => {
    if (!familyKey || !currentFamilyId) return;
    const id = crypto.randomUUID();
    try {
      await setDoc(doc(db, "families", currentFamilyId, "notes", id), {
        schemaVersion: 1,
        titleEnc: await encryptString("", familyKey),
        bodyEnc: await encryptString("", familyKey),
        visibilityScope: "family",
        visibilityMemberIds: [],
        isDeleted: false,
        createdAt: serverTimestamp(),
        createdBy: user.uid,
        createdByName: user.displayName ?? null,
        updatedBy: user.uid,
        updatedByName: user.displayName ?? null,
        updatedAt: serverTimestamp(),
      });
      setSelectedId(id);
      setDraft({ title: "", body: "" });
    } catch (err) {
      setError(err.message);
    }
  };

  const deleteNote = async (note) => {
    try {
      await setDoc(
        doc(db, "families", currentFamilyId, "notes", note.id),
        { isDeleted: true, updatedBy: user.uid, updatedAt: serverTimestamp() },
        { merge: true }
      );
      if (selectedId === note.id) setSelectedId(null);
    } catch (err) {
      setError(err.message);
    }
  };

  if (keyError === "missing") {
    return (
      <div className="notes-locked">
        <div className="locked-icon">🔒</div>
        <h2>{t.notes.keyMissing}</h2>
        <p>{t.notes.keyMissingHint}</p>
      </div>
    );
  }

  const groupOrder = ["today", "last7", "last30", "older"];

  return (
    <div className="notes-page">
      <aside className="notes-list">
        <div className="notes-list-head">
          <div>
            <strong>{t.notes.title}</strong>
            <span className="notes-count">{t.notes.count(notes.length)}</span>
          </div>
          <button className="notes-new" onClick={createNote} title={t.notes.new}>
            ✎
          </button>
        </div>

        <input
          className="notes-search"
          placeholder={t.notes.search}
          value={search}
          onChange={(e) => setSearch(e.target.value)}
        />

        <div className="notes-scroll">
          {groupOrder.map((g) =>
            grouped[g].length ? (
              <div key={g} className="notes-group">
                <div className="notes-group-title">{t.notes.groups[g]}</div>
                {grouped[g].map((n) => (
                  <button
                    key={n.id}
                    className={"note-row" + (selectedId === n.id ? " active" : "")}
                    onClick={() => setSelectedId(n.id)}
                  >
                    <span className="note-row-title">
                      {n.title.trim() || t.notes.untitled}
                    </span>
                    <span className="note-row-meta">
                      <span className="note-row-stamp">
                        {stamp(n.updatedAt?.toDate?.(), locale, g)}
                      </span>
                      <span className="note-row-preview">
                        {(n.bodyText ?? "").slice(0, 60) || "—"}
                      </span>
                    </span>
                  </button>
                ))}
              </div>
            ) : null
          )}

          {notes.length === 0 && familyKey && (
            <div className="notes-empty">
              <strong>{t.notes.noNotes}</strong>
              <p>{t.notes.noNotesHint}</p>
            </div>
          )}
        </div>
      </aside>

      <section className="note-editor">
        {error && <p className="error">{error}</p>}
        {selected ? (
          <>
            <div className="note-editor-bar">
              <span className="note-editor-date">
                {selected.updatedAt?.toDate?.()
                  ? new Intl.DateTimeFormat(locale === "en" ? "en-US" : "it-IT", {
                      dateStyle: "long",
                      timeStyle: "short",
                    }).format(selected.updatedAt.toDate())
                  : ""}
              </span>
              <button
                className="note-delete"
                onClick={() => deleteNote(selected)}
                title={t.notes.delete}
              >
                🗑
              </button>
            </div>
            <input
              className="note-title-input"
              placeholder={t.notes.titlePlaceholder}
              value={draft.title}
              onChange={(e) => onEdit({ title: e.target.value })}
            />
            <RichTextEditor
              value={draft.body}
              placeholder={t.notes.bodyPlaceholder}
              onChange={(html) => onEdit({ body: html })}
            />
          </>
        ) : (
          <div className="note-placeholder">{t.notes.pickOne}</div>
        )}
      </section>
    </div>
  );
}
