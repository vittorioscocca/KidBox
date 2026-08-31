import { useEffect, useMemo, useState } from "react";
import Modal from "./Modal";
import { useTranslation } from "../i18n/LocaleContext";
import { evaluate, LEVEL_COLOR } from "../passwordStrength";
import { DEFAULT_OPTIONS, generate } from "../passwordGenerator";
import { emojiForIcon } from "../services/passwords";
import {
  VISIBILITY_FAMILY,
  VISIBILITY_MEMBERS,
  VISIBILITY_PRIVATE,
} from "../services/passwordCrypto";

const toDateInput = (millis) =>
  millis ? new Date(millis).toISOString().slice(0, 10) : "";

/**
 * Creazione e modifica di una voce, con generatore e barra di robustezza —
 * stessi campi di `AddPasswordSheet` / `EditPasswordSheet` su iOS.
 */
export default function PasswordEditModal({
  entry,
  groups,
  members,
  currentUid,
  onSave,
  onClose,
}) {
  const { t } = useTranslation();
  const p = t.passwords;
  const isNew = !entry?.id;

  const [form, setForm] = useState(() => ({
    title: entry?.title || "",
    username: entry?.username || "",
    password: entry?.password || "",
    website: entry?.website || "",
    notes: entry?.notes || "",
    otp: entry?.otp || "",
    groupId: entry?.groupId || "",
    visibility: entry?.visibility || VISIBILITY_FAMILY,
    visibilityMemberIds: entry?.visibilityMemberIds || [],
    expiresAt: toDateInput(entry?.expiresAt),
  }));
  const [revealed, setRevealed] = useState(isNew);
  const [showGenerator, setShowGenerator] = useState(false);
  const [options, setOptions] = useState(DEFAULT_OPTIONS);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState(null);

  const set = (patch) => setForm((f) => ({ ...f, ...patch }));

  const strength = useMemo(() => evaluate(form.password), [form.password]);
  const strengthLabel = p[strength.level];

  // La visibilità di una voce esistente non si cambia: il testo cifrato è legato
  // alla chiave scelta al momento della creazione, e per «solo io» anche al
  // creatore. Cambiarla richiederebbe di ricifrare tutti i campi.
  const canChangeVisibility = isNew || entry.createdBy === currentUid;

  useEffect(() => {
    const onKey = (e) => {
      if (e.key === "Escape") onClose();
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [onClose]);

  const submit = async (e) => {
    e.preventDefault();
    if (!form.title.trim() || !form.password) return;
    setSaving(true);
    setError(null);
    try {
      await onSave({
        ...entry,
        title: form.title.trim(),
        username: form.username.trim() || null,
        password: form.password,
        website: form.website.trim() || null,
        notes: form.notes.trim() || null,
        otp: form.otp.trim() || null,
        groupId: form.groupId || null,
        visibility: form.visibility,
        visibilityMemberIds:
          form.visibility === VISIBILITY_MEMBERS ? form.visibilityMemberIds : [],
        expiresAt: form.expiresAt ? new Date(form.expiresAt).getTime() : null,
        // Su iOS `passwordUpdatedAt` si muove solo quando cambia la password.
        passwordUpdatedAt:
          isNew || form.password !== entry.password ? Date.now() : entry.passwordUpdatedAt,
      });
      onClose();
    } catch (err) {
      setError(err.message);
      setSaving(false);
    }
  };

  const toggleMember = (uid) =>
    set({
      visibilityMemberIds: form.visibilityMemberIds.includes(uid)
        ? form.visibilityMemberIds.filter((m) => m !== uid)
        : [...form.visibilityMemberIds, uid],
    });

  return (
    <Modal onClose={onClose}>
      <form className="pw-form" onSubmit={submit}>
        <h2>{isNew ? p.add : p.edit}</h2>

        <label>
          {p.fieldTitle}
          <input
            value={form.title}
            onChange={(e) => set({ title: e.target.value })}
            autoFocus
            required
          />
        </label>

        <label>
          {p.fieldUsername}
          <input
            value={form.username}
            onChange={(e) => set({ username: e.target.value })}
            autoComplete="off"
          />
        </label>

        <label>
          {p.fieldPassword}
          <div className="pw-password-row">
            <input
              type={revealed ? "text" : "password"}
              value={form.password}
              onChange={(e) => set({ password: e.target.value })}
              autoComplete="new-password"
              required
            />
            <button type="button" onClick={() => setRevealed((v) => !v)}>
              {revealed ? p.hide : p.show}
            </button>
            <button type="button" onClick={() => setShowGenerator((v) => !v)}>
              {p.generate}
            </button>
          </div>
        </label>

        <div className="pw-strength">
          <div className="pw-strength-track">
            <span
              style={{
                width: `${Math.max(4, strength.fillFraction * 100)}%`,
                background: LEVEL_COLOR[strength.level],
              }}
            />
          </div>
          <div className="pw-strength-labels">
            <span style={{ color: LEVEL_COLOR[strength.level] }}>{strengthLabel}</span>
            {form.password && <span>{p.bits(Math.round(strength.estimatedBits))}</span>}
          </div>
        </div>

        {showGenerator && (
          <div className="pw-generator">
            <label className="pw-gen-length">
              {p.generatorLength}: {options.length}
              <input
                type="range"
                min="8"
                max="64"
                value={options.length}
                onChange={(e) => setOptions({ ...options, length: Number(e.target.value) })}
              />
            </label>
            {[
              ["includeUppercase", p.generatorUppercase],
              ["includeLowercase", p.generatorLowercase],
              ["includeNumbers", p.generatorNumbers],
              ["includeSymbols", p.generatorSymbols],
              ["excludeAmbiguous", p.generatorNoAmbiguous],
            ].map(([key, label]) => (
              <label key={key} className="pw-check">
                <input
                  type="checkbox"
                  checked={options[key]}
                  onChange={(e) => setOptions({ ...options, [key]: e.target.checked })}
                />
                {label}
              </label>
            ))}
            <button
              type="button"
              className="pw-btn-primary"
              onClick={() => {
                set({ password: generate(options) });
                setRevealed(true);
              }}
            >
              {p.generate}
            </button>
          </div>
        )}

        <label>
          {p.fieldWebsite}
          <input
            value={form.website}
            onChange={(e) => set({ website: e.target.value })}
            placeholder="https://"
          />
        </label>

        <label>
          {p.fieldGroup}
          <select value={form.groupId} onChange={(e) => set({ groupId: e.target.value })}>
            <option value="">{p.unassigned}</option>
            {groups.map((g) => (
              <option key={g.id} value={g.id}>
                {`${emojiForIcon(g.icon)} ${g.name}`}
              </option>
            ))}
          </select>
        </label>

        <label>
          {p.fieldVisibility}
          <select
            value={form.visibility}
            disabled={!canChangeVisibility}
            onChange={(e) => set({ visibility: e.target.value })}
          >
            <option value={VISIBILITY_FAMILY}>{p.visibilityFamily}</option>
            <option value={VISIBILITY_MEMBERS}>{p.visibilityMembers}</option>
            <option value={VISIBILITY_PRIVATE}>{p.visibilityPrivate}</option>
          </select>
        </label>

        {form.visibility === VISIBILITY_MEMBERS && (
          <div className="pw-members">
            {members.map((m) => (
              <label key={m.id} className="pw-check">
                <input
                  type="checkbox"
                  checked={form.visibilityMemberIds.includes(m.id)}
                  onChange={() => toggleMember(m.id)}
                />
                {m.displayName || m.name || m.email || m.id}
              </label>
            ))}
          </div>
        )}

        <label>
          {p.fieldExpires}
          <input
            type="date"
            value={form.expiresAt}
            onChange={(e) => set({ expiresAt: e.target.value })}
          />
        </label>

        <label>
          {p.fieldOtp}
          <input
            value={form.otp}
            onChange={(e) => set({ otp: e.target.value })}
            placeholder={p.otpHint}
            autoComplete="off"
          />
        </label>

        <label>
          {p.fieldNotes}
          <textarea
            rows="3"
            value={form.notes}
            onChange={(e) => set({ notes: e.target.value })}
          />
        </label>

        {error && <p className="error">{error}</p>}

        <div className="pw-form-actions">
          <button type="button" onClick={onClose}>
            {p.cancel}
          </button>
          <button type="submit" className="pw-btn-primary" disabled={saving}>
            {p.save}
          </button>
        </div>
      </form>
    </Modal>
  );
}
