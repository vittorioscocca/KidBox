import { useState } from "react";
import Modal from "./Modal";
import { useTranslation } from "../i18n/LocaleContext";
import { ALLOWED_OFFSETS, defaultOffsets, FUELS, OFFSET_KEYS } from "../services/vehicles";

const toDateInput = (millis) => (millis ? new Date(millis).toISOString().slice(0, 10) : "");
const fromDateInput = (v) => (v ? new Date(v).getTime() : null);
const intOrNull = (v) => {
  const n = parseInt(v, 10);
  return Number.isFinite(n) ? n : null;
};

/** Veicolo: gli stessi campi di `VehicleFormView`, preavvisi compresi. */
export default function VehicleModal({ vehicle, locale, onSave, onClose }) {
  const { t } = useTranslation();
  const g = t.garage;
  const [form, setForm] = useState(() => ({
    name: vehicle?.name || "",
    licensePlate: vehicle?.licensePlate || "",
    brand: vehicle?.brand || "",
    model: vehicle?.model || "",
    year: vehicle?.year != null ? String(vehicle.year) : "",
    fuelTypeRaw: vehicle?.fuelTypeRaw || "benzina",
    color: vehicle?.color || "",
    vin: vehicle?.vin || "",
    insuranceExpiryDate: toDateInput(vehicle?.insuranceExpiryDate),
    revisionExpiryDate: toDateInput(vehicle?.revisionExpiryDate),
    taxExpiryDate: toDateInput(vehicle?.taxExpiryDate),
    lastServiceDate: toDateInput(vehicle?.lastServiceDate),
    nextServiceDate: toDateInput(vehicle?.nextServiceDate),
    currentKm: vehicle?.currentKm != null ? String(vehicle.currentKm) : "",
    notes: vehicle?.notes || "",
    reminderEnabled: vehicle?.reminderEnabled ?? true,
    reminderOffsets: vehicle?.reminderOffsets || defaultOffsets(),
  }));
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState(null);
  const set = (patch) => setForm((f) => ({ ...f, ...patch }));

  const toggleOffset = (key, value) => {
    const current = form.reminderOffsets[key] || [];
    const next = current.includes(value)
      ? current.filter((v) => v !== value)
      : [...current, value].sort((a, b) => a - b);
    set({ reminderOffsets: { ...form.reminderOffsets, [key]: next } });
  };

  const submit = async (e) => {
    e.preventDefault();
    if (!form.name.trim()) return;
    setSaving(true);
    try {
      await onSave({
        ...vehicle,
        ...form,
        name: form.name.trim(),
        licensePlate: form.licensePlate.trim().toUpperCase() || null,
        brand: form.brand.trim() || null,
        model: form.model.trim() || null,
        color: form.color.trim() || null,
        vin: form.vin.trim() || null,
        notes: form.notes.trim() || null,
        year: intOrNull(form.year),
        currentKm: intOrNull(form.currentKm),
        insuranceExpiryDate: fromDateInput(form.insuranceExpiryDate),
        revisionExpiryDate: fromDateInput(form.revisionExpiryDate),
        taxExpiryDate: fromDateInput(form.taxExpiryDate),
        lastServiceDate: fromDateInput(form.lastServiceDate),
        nextServiceDate: fromDateInput(form.nextServiceDate),
      });
      onClose();
    } catch (err) {
      setError(err.message);
      setSaving(false);
    }
  };

  const offsetLabel = (n) => (n === 0 ? g.offsetSameDay : g.offsetDays(n));

  return (
    <Modal onClose={onClose}>
      <form className="pw-form" onSubmit={submit}>
        <h2>{vehicle?.id ? g.edit : g.addVehicle}</h2>

        <label>
          {g.name}
          <input value={form.name} onChange={(e) => set({ name: e.target.value })} autoFocus required />
        </label>

        <div className="wl-two">
          <label>
            {g.plate}
            <input value={form.licensePlate} onChange={(e) => set({ licensePlate: e.target.value })} />
          </label>
          <label>
            {g.year}
            <input value={form.year} onChange={(e) => set({ year: e.target.value })} inputMode="numeric" />
          </label>
        </div>

        <div className="wl-two">
          <label>
            {g.brand}
            <input value={form.brand} onChange={(e) => set({ brand: e.target.value })} />
          </label>
          <label>
            {g.model}
            <input value={form.model} onChange={(e) => set({ model: e.target.value })} />
          </label>
        </div>

        <div className="wl-two">
          <label>
            {g.fuel}
            <select value={form.fuelTypeRaw} onChange={(e) => set({ fuelTypeRaw: e.target.value })}>
              {FUELS.map((f) => (
                <option key={f.raw} value={f.raw}>{locale === "en" ? f.en : f.it}</option>
              ))}
            </select>
          </label>
          <label>
            {g.color}
            <input value={form.color} onChange={(e) => set({ color: e.target.value })} />
          </label>
        </div>

        <label>
          {g.vin}
          <input value={form.vin} onChange={(e) => set({ vin: e.target.value })} />
        </label>

        <div className="wl-two">
          <label>
            {g.insurance}
            <input type="date" value={form.insuranceExpiryDate} onChange={(e) => set({ insuranceExpiryDate: e.target.value })} />
          </label>
          <label>
            {g.revision}
            <input type="date" value={form.revisionExpiryDate} onChange={(e) => set({ revisionExpiryDate: e.target.value })} />
          </label>
        </div>

        <div className="wl-two">
          <label>
            {g.tax}
            <input type="date" value={form.taxExpiryDate} onChange={(e) => set({ taxExpiryDate: e.target.value })} />
          </label>
          <label>
            {g.currentKm}
            <input value={form.currentKm} onChange={(e) => set({ currentKm: e.target.value })} inputMode="numeric" />
          </label>
        </div>

        <div className="wl-two">
          <label>
            {g.lastService}
            <input type="date" value={form.lastServiceDate} onChange={(e) => set({ lastServiceDate: e.target.value })} />
          </label>
          <label>
            {g.nextService}
            <input type="date" value={form.nextServiceDate} onChange={(e) => set({ nextServiceDate: e.target.value })} />
          </label>
        </div>

        <label className="pw-check">
          <input type="checkbox" checked={form.reminderEnabled} onChange={(e) => set({ reminderEnabled: e.target.checked })} />
          {g.reminder}
        </label>

        {form.reminderEnabled && (
          <div className="gar-offsets">
            {/* Un preavviso per tipo di scadenza, con i soli valori ammessi dai
                client nativi: 0, 2 e 7 giorni. */}
            {OFFSET_KEYS.map((key) => (
              <div key={key} className="gar-offset-row">
                <span className="gar-offset-label">{g[key === "service" ? "nextService" : key]}</span>
                <div className="pw-chips">
                  {ALLOWED_OFFSETS.map((n) => (
                    <button
                      type="button"
                      key={n}
                      className={
                        "pw-chip" +
                        ((form.reminderOffsets[key] || []).includes(n) ? " selected" : "")
                      }
                      onClick={() => toggleOffset(key, n)}
                    >
                      {offsetLabel(n)}
                    </button>
                  ))}
                </div>
              </div>
            ))}
          </div>
        )}

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
