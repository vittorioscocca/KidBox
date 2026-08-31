import { useState } from "react";
import Modal from "./Modal";
import { useTranslation } from "../i18n/LocaleContext";
import { EVENT_TYPES } from "../services/vehicles";

const toLocalInput = (millis) => {
  if (!millis) return "";
  const d = new Date(millis - new Date(millis).getTimezoneOffset() * 60000);
  return d.toISOString().slice(0, 16);
};

/** Intervento: gli stessi campi di `VehicleEventFormView`. */
export default function VehicleEventModal({ event, vehicleId, locale, onSave, onClose }) {
  const { t } = useTranslation();
  const g = t.garage;
  const [form, setForm] = useState(() => ({
    title: event?.title || "",
    eventTypeRaw: event?.eventTypeRaw || "service",
    date: toLocalInput(event?.date || Date.now()),
    km: event?.km != null ? String(event.km) : "",
    cost: event?.cost != null ? String(event.cost).replace(".", ",") : "",
    garageName: event?.garageName || "",
    notes: event?.notes || "",
  }));
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState(null);
  const set = (patch) => setForm((f) => ({ ...f, ...patch }));

  const submit = async (e) => {
    e.preventDefault();
    if (!form.title.trim()) return;
    setSaving(true);
    try {
      const km = parseInt(form.km, 10);
      const cost = parseFloat(form.cost.replace(",", "."));
      await onSave({
        ...event,
        vehicleId: event?.vehicleId || vehicleId,
        title: form.title.trim(),
        eventTypeRaw: form.eventTypeRaw,
        date: form.date ? new Date(form.date).getTime() : Date.now(),
        km: Number.isFinite(km) ? km : null,
        cost: Number.isFinite(cost) ? cost : null,
        garageName: form.garageName.trim() || null,
        notes: form.notes.trim() || null,
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
        <h2>{event?.id ? g.edit : g.addEvent}</h2>

        <label>
          {g.eventTitle}
          <input value={form.title} onChange={(e) => set({ title: e.target.value })} autoFocus required />
        </label>

        <div className="wl-two">
          <label>
            {g.eventType}
            <select value={form.eventTypeRaw} onChange={(e) => set({ eventTypeRaw: e.target.value })}>
              {EVENT_TYPES.map((ty) => (
                <option key={ty.raw} value={ty.raw}>
                  {`${ty.emoji} ${locale === "en" ? ty.en : ty.it}`}
                </option>
              ))}
            </select>
          </label>
          <label>
            {g.date}
            <input type="datetime-local" value={form.date} onChange={(e) => set({ date: e.target.value })} />
          </label>
        </div>

        <div className="wl-two">
          <label>
            {g.km}
            <input value={form.km} onChange={(e) => set({ km: e.target.value })} inputMode="numeric" />
          </label>
          <label>
            {g.cost}
            <input value={form.cost} onChange={(e) => set({ cost: e.target.value })} inputMode="decimal" placeholder="0,00" />
          </label>
        </div>

        <p className="pw-hint">{g.costHint}</p>

        <label>
          {g.garageName}
          <input value={form.garageName} onChange={(e) => set({ garageName: e.target.value })} />
        </label>

        <label>
          {g.notes}
          <textarea rows="3" value={form.notes} onChange={(e) => set({ notes: e.target.value })} />
        </label>

        {error && <p className="error">{error}</p>}
        <div className="pw-form-actions">
          <button type="button" onClick={onClose}>{g.cancel}</button>
          <button type="submit" className="pw-btn-primary" disabled={saving}>{g.save}</button>
        </div>
      </form>
    </Modal>
  );
}
