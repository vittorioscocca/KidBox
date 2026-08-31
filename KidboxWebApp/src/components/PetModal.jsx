import { useState } from "react";
import Modal from "./Modal";
import { useTranslation } from "../i18n/LocaleContext";
import { SPECIES } from "../services/pets";

const toDateInput = (millis) => (millis ? new Date(millis).toISOString().slice(0, 10) : "");

/** Scheda dell'animale: gli stessi campi di `PetFormView`. */
export default function PetModal({ pet, locale, onSave, onClose }) {
  const { t } = useTranslation();
  const p = t.pets;
  const [form, setForm] = useState(() => ({
    name: pet?.name || "",
    species: pet?.species || "cane",
    breed: pet?.breed || "",
    birthDate: toDateInput(pet?.birthDate),
    color: pet?.color || "",
    chipCode: pet?.chipCode || "",
    notes: pet?.notes || "",
  }));
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState(null);
  const set = (patch) => setForm((f) => ({ ...f, ...patch }));

  const submit = async (e) => {
    e.preventDefault();
    if (!form.name.trim()) return;
    setSaving(true);
    try {
      await onSave({
        ...pet,
        ...form,
        name: form.name.trim(),
        breed: form.breed.trim() || null,
        color: form.color.trim() || null,
        chipCode: form.chipCode.trim() || null,
        notes: form.notes.trim() || null,
        birthDate: form.birthDate ? new Date(form.birthDate).getTime() : null,
      });
      onClose();
    } catch (err) {
      setError(err.message);
      setSaving(false);
    }
  };

  return (
    <Modal onClose={onClose}>
      <form className="pw-form" onSubmit={submit}>
        <h2>{pet?.id ? p.edit : p.add}</h2>
        <label>
          {p.name}
          <input value={form.name} onChange={(e) => set({ name: e.target.value })} autoFocus required />
        </label>
        <div className="wl-two">
          <label>
            {p.species}
            <select value={form.species} onChange={(e) => set({ species: e.target.value })}>
              {SPECIES.map((s) => (
                <option key={s.raw} value={s.raw}>
                  {`${s.emoji} ${locale === "en" ? s.en : s.it}`}
                </option>
              ))}
            </select>
          </label>
          <label>
            {p.breed}
            <input value={form.breed} onChange={(e) => set({ breed: e.target.value })} />
          </label>
        </div>
        <div className="wl-two">
          <label>
            {p.birthDate}
            <input type="date" value={form.birthDate} onChange={(e) => set({ birthDate: e.target.value })} />
          </label>
          <label>
            {p.color}
            <input value={form.color} onChange={(e) => set({ color: e.target.value })} />
          </label>
        </div>
        <label>
          {p.chipCode}
          <input value={form.chipCode} onChange={(e) => set({ chipCode: e.target.value })} />
        </label>
        <label>
          {p.notes}
          <textarea rows="3" value={form.notes} onChange={(e) => set({ notes: e.target.value })} />
        </label>
        {error && <p className="error">{error}</p>}
        <div className="pw-form-actions">
          <button type="button" onClick={onClose}>{p.cancel}</button>
          <button type="submit" className="pw-btn-primary" disabled={saving}>{p.save}</button>
        </div>
      </form>
    </Modal>
  );
}
