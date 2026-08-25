import { useState } from "react";
import { doc, serverTimestamp, setDoc } from "firebase/firestore";
import { todoListsCol } from "../hooks/useTodoLists";
import { useAuth } from "../AuthContext";
import { useTranslation } from "../i18n/LocaleContext";
import Modal from "./Modal";

export default function NewListModal({ familyId, childId, onClose }) {
  const { user } = useAuth();
  const { t } = useTranslation();
  const [name, setName] = useState("");
  const [error, setError] = useState(null);

  const save = async () => {
    const trimmed = name.trim();
    if (!trimmed) return;
    const id = crypto.randomUUID();
    try {
      await setDoc(doc(todoListsCol(familyId), id), {
        childId,
        name: trimmed,
        isDeleted: false,
        updatedBy: user.uid,
        updatedAt: serverTimestamp(),
      });
      onClose();
    } catch (err) {
      setError(err.message);
    }
  };

  return (
    <Modal onClose={onClose}>
      <div className="modal-header">
        <button className="modal-icon-btn" onClick={onClose}>
          ✕
        </button>
        <button className="modal-save-btn" disabled={!name.trim()} onClick={save}>
          {t.todo.save}
        </button>
      </div>
      <div className="modal-title">{t.todo.newList}</div>
      {error && <p className="error">{error}</p>}
      <input
        className="modal-field"
        placeholder={t.todo.listName}
        value={name}
        autoFocus
        onChange={(e) => setName(e.target.value)}
        onKeyDown={(e) => e.key === "Enter" && save()}
      />
    </Modal>
  );
}
