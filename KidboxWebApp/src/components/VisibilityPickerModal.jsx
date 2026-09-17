import { useState } from "react";
import { useAuth } from "../AuthContext";
import { useTranslation } from "../i18n/LocaleContext";
import { VISIBILITY_FAMILY, VISIBILITY_MEMBERS, VISIBILITY_PRIVATE } from "../visibility";
import Modal from "./Modal";

/** Etichetta del chip, come `KBVisibilityScope.chipLabel(for:)`. */
export function visibilityChipLabel(t, scope) {
  if (scope === VISIBILITY_MEMBERS) return t.visibility.members;
  if (scope === VISIBILITY_PRIVATE) return t.visibility.onlyMe;
  return t.visibility.family;
}

/**
 * Selettore di visibilità a sé stante, come VisibilityPickerSheet su iOS:
 * tre opzioni e, per «Membri selezionati», l'elenco dei membri escluso chi
 * sta scegliendo (che vede sempre il proprio contenuto). Conferma con
 * `onConfirm(scope, memberIds)` già ripuliti (niente uid proprio, ordinati).
 */
export default function VisibilityPickerModal({
  scope: initialScope,
  memberIds: initialMemberIds,
  members,
  whoCanSee,
  onConfirm,
  onClose,
}) {
  const { user } = useAuth();
  const { t } = useTranslation();
  const [scope, setScope] = useState(initialScope || VISIBILITY_FAMILY);
  const [memberIds, setMemberIds] = useState(new Set(initialMemberIds || []));

  const options = [
    { scope: VISIBILITY_FAMILY, label: t.visibility.family },
    { scope: VISIBILITY_MEMBERS, label: t.visibility.members },
    { scope: VISIBILITY_PRIVATE, label: t.visibility.onlyMe },
  ];
  const selectable = members.filter((m) => m.id !== user?.uid);

  const toggle = (uid) =>
    setMemberIds((prev) => {
      const next = new Set(prev);
      if (next.has(uid)) next.delete(uid);
      else next.add(uid);
      return next;
    });

  const confirm = () => {
    const ids =
      scope === VISIBILITY_MEMBERS
        ? [...memberIds].filter((uid) => uid !== user?.uid).sort()
        : [];
    onConfirm(scope, ids);
  };

  return (
    <Modal onClose={onClose}>
      <div className="modal-header">
        <button className="modal-text-btn" onClick={onClose}>
          {t.visibility.cancel}
        </button>
        <button className="modal-save-btn" onClick={confirm}>
          {t.visibility.confirm}
        </button>
      </div>
      <div className="modal-title">{t.visibility.title}</div>
      <div className="modal-label">{whoCanSee}</div>
      <div className="modal-section">
        {options.map((opt) => (
          <button
            key={opt.scope}
            className="modal-option"
            onClick={() => {
              setScope(opt.scope);
              if (opt.scope !== VISIBILITY_MEMBERS) setMemberIds(new Set());
            }}
          >
            <span>{opt.label}</span>
            <span>{scope === opt.scope ? "●" : "○"}</span>
          </button>
        ))}
      </div>

      {scope === VISIBILITY_MEMBERS && (
        <>
          <div className="modal-label">{t.visibility.selectMembers}</div>
          <div className="modal-section">
            {selectable.map((m) => (
              <button key={m.id} className="modal-option" onClick={() => toggle(m.id)}>
                <span>{m.displayName || t.visibility.member}</span>
                <span>{memberIds.has(m.id) ? "●" : "○"}</span>
              </button>
            ))}
          </div>
        </>
      )}
    </Modal>
  );
}
