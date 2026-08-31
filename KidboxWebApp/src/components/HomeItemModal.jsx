import { useState } from "react";
import Modal from "./Modal";
import { useTranslation } from "../i18n/LocaleContext";
import { ITEM_CATEGORIES } from "../services/homeItems";

const toDateInput = (millis) => (millis ? new Date(millis).toISOString().slice(0, 10) : "");
const fromDateInput = (v) => (v ? new Date(v).getTime() : null);

/** Oggetto di casa: gli stessi campi di `HomeItemFormView`. */
export default function HomeItemModal({ item, locale, onSave, onClose }) {
  const { t } = useTranslation();
  const h = t.house;
  const [form, setForm] = useState(() => ({
    name: item?.name || "",
    categoryRaw: item?.categoryRaw || "appliance",
    brand: item?.brand || "",
    model: item?.model || "",
    serialNumber: item?.serialNumber || "",
    purchaseDate: toDateInput(item?.purchaseDate),
    warrantyExpiryDate: toDateInput(item?.warrantyExpiryDate),
    nextServiceDate: toDateInput(item?.nextServiceDate),
    servicePeriodMonths: item?.servicePeriodMonths != null ? String(item.servicePeriodMonths) : "",
    notes: item?.notes || "",
    reminderEnabled: item?.reminderEnabled ?? false,
  }));
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState(null);
  const set = (patch) => setForm((f) => ({ ...f, ...patch }));

  const submit = async (e) => {
    e.preventDefault();
    if (!form.name.trim()) return;
    setSaving(true);
    try {
      const months = parseInt(form.servicePeriodMonths, 10);
      await onSave({
        ...item,
        ...form,
        name: form.name.trim(),
        brand: form.brand.trim() || null,
        model: form.model.trim() || null,
        serialNumber: form.serialNumber.trim() || null,
        notes: form.notes.trim() || null,
        purchaseDate: fromDateInput(form.purchaseDate),
        warrantyExpiryDate: fromDateInput(form.warrantyExpiryDate),
        nextServiceDate: fromDateInput(form.nextServiceDate),
        servicePeriodMonths: Number.isFinite(months) ? months : null,
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
        <h2>{item?.id ? h.edit : h.addItem}</h2>
        <label>
          {h.name}
          <input value={form.name} onChange={(e) => set({ name: e.target.value })} autoFocus required />
        </label>
        <label>
          {h.category}
          <select value={form.categoryRaw} onChange={(e) => set({ categoryRaw: e.target.value })}>
            {ITEM_CATEGORIES.map((c) => (
              <option key={c.raw} value={c.raw}>{`${c.emoji} ${locale === "en" ? c.en : c.it}`}</option>
            ))}
          </select>
        </label>
        <div className="wl-two">
          <label>
            {h.brand}
            <input value={form.brand} onChange={(e) => set({ brand: e.target.value })} />
          </label>
          <label>
            {h.model}
            <input value={form.model} onChange={(e) => set({ model: e.target.value })} />
          </label>
        </div>
        <label>
          {h.serialNumber}
          <input value={form.serialNumber} onChange={(e) => set({ serialNumber: e.target.value })} />
        </label>
        <div className="wl-two">
          <label>
            {h.purchaseDate}
            <input type="date" value={form.purchaseDate} onChange={(e) => set({ purchaseDate: e.target.value })} />
          </label>
          <label>
            {h.warranty}
            <input type="date" value={form.warrantyExpiryDate} onChange={(e) => set({ warrantyExpiryDate: e.target.value })} />
          </label>
        </div>
        <div className="wl-two">
          <label>
            {h.nextService}
            <input type="date" value={form.nextServiceDate} onChange={(e) => set({ nextServiceDate: e.target.value })} />
          </label>
          <label>
            {h.servicePeriod}
            <input value={form.servicePeriodMonths} onChange={(e) => set({ servicePeriodMonths: e.target.value })} inputMode="numeric" />
          </label>
        </div>
        <label className="pw-check">
          <input type="checkbox" checked={form.reminderEnabled} onChange={(e) => set({ reminderEnabled: e.target.checked })} />
          {h.reminder}
        </label>
        <label>
          {h.notes}
          <textarea rows="3" value={form.notes} onChange={(e) => set({ notes: e.target.value })} />
        </label>
        {error && <p className="error">{error}</p>}
        <div className="pw-form-actions">
          <button type="button" onClick={onClose}>{h.cancel}</button>
          <button type="submit" className="pw-btn-primary" disabled={saving}>{h.save}</button>
        </div>
      </form>
    </Modal>
  );
}
