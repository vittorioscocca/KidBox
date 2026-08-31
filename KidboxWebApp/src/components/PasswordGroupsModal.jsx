import { useState } from "react";
import Modal from "./Modal";
import { useTranslation } from "../i18n/LocaleContext";
import { AVAILABLE_ICONS, emojiForIcon } from "../services/passwords";

const COLORS = ["#8E8E93", "#0A84FF", "#34C759", "#FF9500", "#5E5CE6", "#FF2D55", "#7C6FDE", "#e8833a"];

/**
 * Gestione dei gruppi, come `GroupsManagementView` su iOS: rinomina, icona,
 * colore, nuovo gruppo, eliminazione.
 *
 * I gruppi di sistema si possono rinominare ma non eliminare: gli altri client
 * li ricreerebbero con lo stesso id deterministico al primo avvio.
 */
export default function PasswordGroupsModal({ groups, onSave, onDelete, onClose }) {
  const { t } = useTranslation();
  const p = t.passwords;
  const [editing, setEditing] = useState(null);

  const startNew = () =>
    setEditing({ name: "", icon: "folder.fill", color: "#7C6FDE", isSystem: false });

  const save = async (e) => {
    e.preventDefault();
    if (!editing.name.trim()) return;
    await onSave({ ...editing, name: editing.name.trim() });
    setEditing(null);
  };

  return (
    <Modal onClose={onClose}>
      <div className="pw-groups">
        <h2>{p.manageGroups}</h2>

        {editing ? (
          <form className="pw-form" onSubmit={save}>
            <label>
              {p.groupName}
              <input
                value={editing.name}
                onChange={(e) => setEditing({ ...editing, name: e.target.value })}
                autoFocus
                required
              />
            </label>

            <div className="pw-field-label">{p.groupIcon}</div>
            <div className="pw-icon-grid">
              {AVAILABLE_ICONS.map((icon) => (
                <button
                  type="button"
                  key={icon}
                  className={"pw-icon" + (editing.icon === icon ? " selected" : "")}
                  onClick={() => setEditing({ ...editing, icon })}
                >
                  {emojiForIcon(icon)}
                </button>
              ))}
            </div>

            <div className="pw-field-label">{p.groupColor}</div>
            <div className="pw-color-grid">
              {COLORS.map((color) => (
                <button
                  type="button"
                  key={color}
                  className={"pw-color" + (editing.color === color ? " selected" : "")}
                  style={{ background: color }}
                  onClick={() => setEditing({ ...editing, color })}
                  aria-label={color}
                />
              ))}
            </div>

            <div className="pw-form-actions">
              <button type="button" onClick={() => setEditing(null)}>
                {p.cancel}
              </button>
              <button type="submit" className="pw-btn-primary">
                {p.save}
              </button>
            </div>
          </form>
        ) : (
          <>
            <ul className="pw-group-list">
              {groups.map((g) => (
                <li key={g.id}>
                  <span className="pw-group-dot" style={{ background: g.color }} />
                  <span className="pw-group-emoji">{emojiForIcon(g.icon)}</span>
                  <span className="pw-group-name">{g.name}</span>
                  {g.isSystem && <span className="pw-group-tag">{p.systemGroup}</span>}
                  <button type="button" onClick={() => setEditing(g)}>
                    {p.edit}
                  </button>
                  {!g.isSystem && (
                    <button
                      type="button"
                      className="pw-danger"
                      onClick={() => {
                        if (window.confirm(p.deleteGroupHint)) onDelete(g.id);
                      }}
                    >
                      {p.delete}
                    </button>
                  )}
                </li>
              ))}
            </ul>
            <p className="pw-hint">{p.deleteGroupHint}</p>
            <div className="pw-form-actions">
              <button type="button" onClick={onClose}>
                {p.cancel}
              </button>
              <button type="button" className="pw-btn-primary" onClick={startNew}>
                {p.newGroup}
              </button>
            </div>
          </>
        )}
      </div>
    </Modal>
  );
}
