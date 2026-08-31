import { useState } from "react";
import Modal from "./Modal";
import { useTranslation } from "../i18n/LocaleContext";
import { EVENT_TYPES } from "../services/pets";

const toLocalInput = (millis) => {
  if (!millis) return "";
  const d = new Date(millis - new Date(millis).getTimezoneOffset() * 60000);
  return d.toISOString().slice(0, 16);
};
const toDateInput = (millis) => (millis ? new Date(millis).toISOString().slice(0, 10) : "");

/** Evento dell'animale: gli stessi campi di `PetEventFormView`. */
export default function PetEventModal({ event, petId, locale, onSave, onClose }) {
  const { t } = useTranslation();
  const p = t.pets;
  const [form, setForm] = useState(() => ({
    title: event?.title || "",
    eventTypeRaw: event?.eventTypeRaw || "vaccine",
    date: toLocalInput(event?.date || Date.now()),
    nextDueDate: toDateInput(event?.nextDueDate),
    vetName: event?.vetName || "",
    cost: event?.cost != null ? String(event.cost) : "",
    notes: event?.notes || "",
    reminderEnabled: event?.reminderEnabled ?? false,
  }));
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState(null);
  const set = (patch) => setForm((f) => ({ ...f, ...patch }));

  const submit = async (e) => {
    e.preventDefault();
    if (!form.title.trim()) return;
    setSaving(true);
    try {
      const parsedCost = parseFloat(form.cost.replace(",", "."));
      await onSave({
        ...event,
        petId: event?.petId || petId,
        title: form.title.trim(),
        eventTypeRaw: form.eventTypeRaw,
        date: form.date ? new Date(form.date).getTime() : Date.now(),
        nextDueDate: form.nextDueDate ? new Date(form.nextDueDate).getTime() : null,
        vetName: form.vetName.trim() || null,
        cost: Number.isFinite(parsedCost) ? parsedCost : null,
        notes: form.notes.trim() || null,
        reminderEnabled: form.reminderEnabled,
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
        <h2>{event?.id ? p.edit : p.addEvent}</h2>
        <label>
          {p.eventTitle}
          <input value={form.title} onChange={(e) => set({ title: e.target.value })} autoFocus required />
        </label>
        <div className="wl-two">
          <label>
            {p.eventType}
            <select value={form.eventTypeRaw} onChange={(e) => set({ eventTypeRaw: e.target.value })}>
              {EVENT_TYPES.map((ty) => (
                <option key={ty.raw} value={ty.raw}>
                  {`${ty.emoji} ${locale === "en" ? ty.en : ty.it}`}
                </option>
              ))}
            </select>
          </label>
          <label>
            {p.date}
            <input type="datetime-local" value={form.date} onChange={(e) => set({ date: e.target.value })} />
          </label>
        </div>
        <div className="wl-two">
          <label>
            {p.nextDue}
            <input type="date" value={form.nextDueDate} onChange={(e) => set({ nextDueDate: e.target.value })} />
          </label>
          <label>
            {p.vetName}
            <input value={form.vetName} onChange={(e) => set({ vetName: e.target.value })} />
          </label>
        </div>
        <label>
          {p.cost}
          <input value={form.cost} onChange={(e) => set({ cost: e.target.value })} inputMode="decimal" />
        </label>
        <label className="pw-check">
          <input
            type="checkbox"
            checked={form.reminderEnabled}
            onChange={(e) => set({ reminderEnabled: e.target.checked })}
          />
          {p.reminder}
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
