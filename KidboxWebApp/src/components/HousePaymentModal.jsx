import { useState } from "react";
import Modal from "./Modal";
import { useTranslation } from "../i18n/LocaleContext";
import { PAYMENT_SUBTYPES, PAYMENT_TYPES } from "../services/homeItems";

const toDateInput = (millis) => (millis ? new Date(millis).toISOString().slice(0, 10) : "");
const fromDateInput = (v) => (v ? new Date(v).getTime() : null);

/** Scadenza di casa: gli stessi campi di `HousePaymentFormView`. */
export default function HousePaymentModal({ payment, locale, onSave, onClose }) {
  const { t } = useTranslation();
  const h = t.house;
  const [form, setForm] = useState(() => ({
    name: payment?.name || "",
    typeRaw: payment?.typeRaw || "bolletta",
    subtypeRaw: payment?.subtypeRaw || "",
    importo: payment?.importo != null ? String(payment.importo).replace(".", ",") : "",
    dataScadenza: toDateInput(payment?.dataScadenza),
    dataScadenzaContratto: toDateInput(payment?.dataScadenzaContratto),
    giornoDiScadenzaMensile:
      payment?.giornoDiScadenzaMensile != null ? String(payment.giornoDiScadenzaMensile) : "",
    fornitore: payment?.fornitore || "",
    note: payment?.note || "",
    reminderOn: payment?.reminderOn ?? false,
  }));
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState(null);
  const set = (patch) => setForm((f) => ({ ...f, ...patch }));

  const subtypes = PAYMENT_SUBTYPES[form.typeRaw] || [];

  const submit = async (e) => {
    e.preventDefault();
    if (!form.name.trim()) return;
    setSaving(true);
    try {
      const amount = parseFloat(form.importo.replace(",", "."));
      const day = parseInt(form.giornoDiScadenzaMensile, 10);
      await onSave({
        ...payment,
        name: form.name.trim(),
        typeRaw: form.typeRaw,
        subtypeRaw: form.subtypeRaw.trim() || null,
        importo: Number.isFinite(amount) ? amount : null,
        dataScadenza: fromDateInput(form.dataScadenza),
        dataScadenzaContratto: fromDateInput(form.dataScadenzaContratto),
        giornoDiScadenzaMensile: Number.isFinite(day) ? day : null,
        fornitore: form.fornitore.trim() || null,
        note: form.note.trim() || null,
        reminderOn: form.reminderOn,
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
        <h2>{payment?.id ? h.edit : h.addPayment}</h2>

        <label>
          {h.name}
          <input value={form.name} onChange={(e) => set({ name: e.target.value })} autoFocus required />
        </label>

        <div className="wl-two">
          <label>
            {h.type}
            <select
              value={form.typeRaw}
              onChange={(e) => set({ typeRaw: e.target.value, subtypeRaw: "" })}
            >
              {PAYMENT_TYPES.map((ty) => (
                <option key={ty.raw} value={ty.raw}>
                  {`${ty.emoji} ${locale === "en" ? ty.en : ty.it}`}
                </option>
              ))}
            </select>
          </label>
          {subtypes.length > 0 && (
            <label>
              {h.subtype}
              {/* Testo libero con scorciatoie: il valore salvato resta quello
                  italiano condiviso con iOS e Android. */}
              <select value={form.subtypeRaw} onChange={(e) => set({ subtypeRaw: e.target.value })}>
                <option value="">—</option>
                {subtypes.map((st) => (
                  <option key={st.raw} value={st.raw}>
                    {locale === "en" ? st.en : st.it}
                  </option>
                ))}
              </select>
            </label>
          )}
        </div>

        <div className="wl-two">
          <label>
            {h.amount}
            <input value={form.importo} onChange={(e) => set({ importo: e.target.value })} inputMode="decimal" placeholder="0,00" />
          </label>
          <label>
            {h.dueDate}
            <input type="date" value={form.dataScadenza} onChange={(e) => set({ dataScadenza: e.target.value })} />
          </label>
        </div>

        <p className="pw-hint">{h.amountHint}</p>

        <div className="wl-two">
          <label>
            {h.monthlyDay}
            <input
              value={form.giornoDiScadenzaMensile}
              onChange={(e) => set({ giornoDiScadenzaMensile: e.target.value })}
              inputMode="numeric"
              placeholder="1–31"
            />
          </label>
          <label>
            {h.contractEnd}
            <input type="date" value={form.dataScadenzaContratto} onChange={(e) => set({ dataScadenzaContratto: e.target.value })} />
          </label>
        </div>

        <label>
          {h.supplier}
          <input value={form.fornitore} onChange={(e) => set({ fornitore: e.target.value })} />
        </label>

        <label className="pw-check">
          <input type="checkbox" checked={form.reminderOn} onChange={(e) => set({ reminderOn: e.target.checked })} />
          {h.reminder}
        </label>

        <label>
          {h.notes}
          <textarea rows="3" value={form.note} onChange={(e) => set({ note: e.target.value })} />
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
