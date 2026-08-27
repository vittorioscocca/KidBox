import { useEffect, useMemo, useState } from "react";
import {
  Timestamp,
  collection,
  doc,
  onSnapshot,
  query,
  serverTimestamp,
  setDoc,
  where,
  writeBatch,
} from "firebase/firestore";
import { db } from "../firebase";
import { useFamily } from "../FamilyContext";
import { useAuth } from "../AuthContext";
import { useTranslation } from "../i18n/LocaleContext";
import Modal from "../components/Modal";
import "./Spesa.css";

/** Stesse categorie suggerite di KBGroceryCategory.suggested (iOS). */
const SUGGESTED = [
  "Frutta e Verdura",
  "Carne e Pesce",
  "Latticini",
  "Pane e Cereali",
  "Surgelati",
  "Bevande",
  "Dolci e Snack",
  "Pulizia",
  "Cura Personale",
  "Altro",
];
const UNCATEGORIZED = "Altro";

function groceriesCol(familyId) {
  return collection(db, "families", familyId, "groceries");
}

/**
 * L'etichetta mostrata è tradotta, ma il valore salvato resta la stringa
 * italiana: è la chiave che usano anche iOS e Android (KBGroceryCategory), e
 * cambiarla renderebbe le categorie incoerenti fra i client.
 */
function useCategoryLabel() {
  const { t } = useTranslation();
  return (key) => t.grocery.categories?.[key] ?? key;
}

export default function Spesa() {
  const { currentFamilyId } = useFamily();
  const { user } = useAuth();
  const { t } = useTranslation();
  const categoryLabel = useCategoryLabel();

  const [items, setItems] = useState([]);
  const [error, setError] = useState(null);
  const [draft, setDraft] = useState("");
  const [draftCategory, setDraftCategory] = useState("");
  const [editing, setEditing] = useState(null);

  useEffect(() => {
    if (!currentFamilyId) return undefined;
    const q = query(groceriesCol(currentFamilyId), where("isDeleted", "==", false));
    return onSnapshot(
      q,
      (snap) => setItems(snap.docs.map((d) => ({ id: d.id, ...d.data() }))),
      (err) => setError(err.message)
    );
  }, [currentFamilyId]);

  const toBuy = useMemo(() => items.filter((i) => !i.isPurchased), [items]);
  const purchased = useMemo(
    () =>
      items
        .filter((i) => i.isPurchased)
        .sort(
          (a, b) =>
            (b.purchasedAt?.toMillis?.() ?? 0) - (a.purchasedAt?.toMillis?.() ?? 0)
        ),
    [items]
  );

  // Da comprare raggruppati per categoria, come su iOS.
  const grouped = useMemo(() => {
    const map = new Map();
    toBuy.forEach((item) => {
      const key = item.category?.trim() ? item.category.trim() : UNCATEGORIZED;
      if (!map.has(key)) map.set(key, []);
      map.get(key).push(item);
    });
    return [...map.entries()]
      .sort((a, b) => a[0].localeCompare(b[0]))
      .map(([category, list]) => ({
        category,
        items: list.sort((a, b) => (a.name ?? "").localeCompare(b.name ?? "")),
      }));
  }, [toBuy]);

  const addItem = async (e) => {
    e.preventDefault();
    const name = draft.trim();
    if (!name || !currentFamilyId) return;
    setDraft("");
    try {
      const id = crypto.randomUUID();
      await setDoc(doc(groceriesCol(currentFamilyId), id), {
        name,
        category: draftCategory || null,
        notes: null,
        isPurchased: false,
        isDeleted: false,
        purchasedAt: null,
        purchasedBy: null,
        createdBy: user.uid,
        createdAt: serverTimestamp(),
        updatedBy: user.uid,
        updatedAt: serverTimestamp(),
      });
    } catch (err) {
      setError(err.message);
    }
  };

  const togglePurchased = async (item) => {
    try {
      await setDoc(
        doc(groceriesCol(currentFamilyId), item.id),
        {
          isPurchased: !item.isPurchased,
          purchasedAt: !item.isPurchased ? Timestamp.now() : null,
          purchasedBy: !item.isPurchased ? user.uid : null,
          updatedBy: user.uid,
          updatedAt: serverTimestamp(),
        },
        { merge: true }
      );
    } catch (err) {
      setError(err.message);
    }
  };

  const deleteItem = async (item) => {
    try {
      await setDoc(
        doc(groceriesCol(currentFamilyId), item.id),
        { isDeleted: true, updatedBy: user.uid, updatedAt: serverTimestamp() },
        { merge: true }
      );
    } catch (err) {
      setError(err.message);
    }
  };

  /** Svuota la sezione acquistati, come deleteAllPurchased su iOS. */
  const deleteAllPurchased = async () => {
    if (!window.confirm(t.grocery.deletePurchasedConfirm)) return;
    const batch = writeBatch(db);
    purchased.forEach((item) => {
      batch.set(
        doc(groceriesCol(currentFamilyId), item.id),
        { isDeleted: true, updatedBy: user.uid, updatedAt: serverTimestamp() },
        { merge: true }
      );
    });
    try {
      await batch.commit();
    } catch (err) {
      setError(err.message);
    }
  };

  const saveEdit = async (values) => {
    try {
      await setDoc(
        doc(groceriesCol(currentFamilyId), editing.id),
        {
          name: values.name,
          category: values.category || null,
          notes: values.notes || null,
          updatedBy: user.uid,
          updatedAt: serverTimestamp(),
        },
        { merge: true }
      );
      setEditing(null);
    } catch (err) {
      setError(err.message);
    }
  };

  const row = (item) => (
    <li key={item.id} className={item.isPurchased ? "purchased" : ""}>
      <button className="grocery-check" onClick={() => togglePurchased(item)}>
        {item.isPurchased ? "✅" : "⭕️"}
      </button>
      <button className="grocery-main" onClick={() => setEditing(item)}>
        <span className="grocery-name">{item.name}</span>
        {item.notes && <span className="grocery-notes">{item.notes}</span>}
      </button>
      <button
        className="grocery-delete"
        onClick={() => deleteItem(item)}
        title={t.grocery.delete}
      >
        🗑
      </button>
    </li>
  );

  return (
    <div className="grocery-page">
      <div className="grocery-head">
        <h1>{t.grocery.title}</h1>
        {toBuy.length > 0 && (
          <span className="grocery-remaining">{t.grocery.remaining(toBuy.length)}</span>
        )}
      </div>

      {/* Aggiunta rapida: un campo solo, come nella lista nativa. */}
      <form className="grocery-add" onSubmit={addItem}>
        <input
          placeholder={t.grocery.addPlaceholder}
          value={draft}
          onChange={(e) => setDraft(e.target.value)}
        />
        <button type="submit" disabled={!draft.trim()}>
          {t.grocery.add}
        </button>
      </form>

      <div className="grocery-cat-row">
        <span className="grocery-cat-label">{t.grocery.pickCategory}</span>
        <div className="cat-picker">
          {SUGGESTED.map((c) => (
            <button
              key={c}
              type="button"
              className={"cat-chip" + (draftCategory === c ? " active" : "")}
              onClick={() => setDraftCategory(draftCategory === c ? "" : c)}
            >
              {categoryLabel(c)}
            </button>
          ))}
        </div>
      </div>

      {error && <p className="error">{error}</p>}

      {items.length === 0 ? (
        <div className="docs-empty">
          <div className="empty-icon">🛒</div>
          <strong>{t.grocery.empty}</strong>
          <p>{t.grocery.emptyHint}</p>
        </div>
      ) : (
        <>
          {grouped.map((group) => (
            <section key={group.category} className="grocery-group">
              <h3>{categoryLabel(group.category)}</h3>
              <ul className="grocery-list">{group.items.map(row)}</ul>
            </section>
          ))}

          {purchased.length > 0 && (
            <section className="grocery-group">
              <div className="grocery-group-head">
                <h3>{t.grocery.purchased(purchased.length)}</h3>
                <button className="link-btn" onClick={deleteAllPurchased}>
                  {t.grocery.deletePurchased}
                </button>
              </div>
              <ul className="grocery-list">{purchased.map(row)}</ul>
            </section>
          )}
        </>
      )}

      {editing && (
        <EditItemModal
          item={editing}
          onCancel={() => setEditing(null)}
          onSave={saveEdit}
        />
      )}
    </div>
  );
}

function EditItemModal({ item, onCancel, onSave }) {
  const { t } = useTranslation();
  const categoryLabel = useCategoryLabel();
  const [name, setName] = useState(item.name ?? "");
  const [category, setCategory] = useState(item.category ?? "");
  const [notes, setNotes] = useState(item.notes ?? "");

  return (
    <Modal onClose={onCancel}>
      <div className="modal-header">
        <button className="modal-text-btn" onClick={onCancel}>
          {t.grocery.cancel}
        </button>
        <button
          className="modal-save-btn"
          disabled={!name.trim()}
          onClick={() =>
            onSave({ name: name.trim(), category: category.trim(), notes: notes.trim() })
          }
        >
          {t.grocery.save}
        </button>
      </div>
      <div className="modal-title">{t.grocery.edit}</div>

      <input
        className="modal-field"
        placeholder={t.grocery.itemName}
        value={name}
        autoFocus
        onChange={(e) => setName(e.target.value)}
      />

      <div className="modal-label">{t.grocery.category}</div>
      <input
        className="modal-field"
        placeholder={t.grocery.categoryPlaceholder}
        value={category}
        onChange={(e) => setCategory(e.target.value)}
      />
      {/* Le suggerite sono scorciatoie: la categoria resta un testo libero. */}
      <div className="cat-picker">
        {SUGGESTED.map((c) => (
          <button
            key={c}
            className={"cat-chip" + (category === c ? " active" : "")}
            onClick={() => setCategory(category === c ? "" : c)}
          >
            {categoryLabel(c)}
          </button>
        ))}
      </div>

      <div className="modal-label">{t.grocery.notes}</div>
      <textarea
        className="modal-field"
        placeholder={t.grocery.notesPlaceholder}
        value={notes}
        onChange={(e) => setNotes(e.target.value)}
      />
    </Modal>
  );
}
