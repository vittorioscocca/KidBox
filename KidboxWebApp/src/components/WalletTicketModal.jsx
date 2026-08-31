import { useState } from "react";
import Modal from "./Modal";
import { useTranslation } from "../i18n/LocaleContext";
import {
  TICKET_KINDS,
  WALLET_FAMILY,
  WALLET_MEMBERS,
  WALLET_PRIVATE,
} from "../services/wallet";

const toLocalInput = (millis) => {
  if (!millis) return "";
  const d = new Date(millis - new Date(millis).getTimezoneOffset() * 60000);
  return d.toISOString().slice(0, 16);
};
const fromLocalInput = (value) => (value ? new Date(value).getTime() : null);

const REMINDERS = [null, 1, 2, 3, 6, 12, 24, 48];

/** Creazione e modifica di un biglietto: stessi campi di `AddWalletTicketSheet`. */
export default function WalletTicketModal({ ticket, members, locale, onSave, onClose }) {
  const { t } = useTranslation();
  const w = t.wallet;
  const isNew = !ticket?.id;

  const [form, setForm] = useState(() => ({
    title: ticket?.title || "",
    kind: ticket?.kind || "other",
    emitter: ticket?.emitter || "",
    eventDate: toLocalInput(ticket?.eventDate),
    eventEndDate: toLocalInput(ticket?.eventEndDate),
    location: ticket?.location || "",
    arrivalLocation: ticket?.arrivalLocation || "",
    seat: ticket?.seat || "",
    bookingCode: ticket?.bookingCode || "",
    holderName: ticket?.holderName || "",
    notes: ticket?.notes || "",
    barcodeText: ticket?.barcodeText || "",
    barcodeFormat: ticket?.barcodeFormat || "",
    reminderOffsetHours: ticket?.reminderOffsetHours ?? null,
    visibilityScope: ticket?.visibilityScope || WALLET_PRIVATE,
    visibilityMemberIds: ticket?.visibilityMemberIds || [],
  }));
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState(null);

  const set = (patch) => setForm((f) => ({ ...f, ...patch }));

  const submit = async (e) => {
    e.preventDefault();
    if (!form.title.trim()) return;
    setSaving(true);
    setError(null);
    try {
      await onSave({
        ...ticket,
        ...form,
        title: form.title.trim(),
        emitter: form.emitter.trim() || null,
        location: form.location.trim() || null,
        arrivalLocation: form.arrivalLocation.trim() || null,
        seat: form.seat.trim() || null,
        bookingCode: form.bookingCode.trim() || null,
        holderName: form.holderName.trim() || null,
        notes: form.notes.trim() || null,
        barcodeText: form.barcodeText.trim() || null,
        barcodeFormat: form.barcodeFormat.trim() || null,
        eventDate: fromLocalInput(form.eventDate),
        eventEndDate: fromLocalInput(form.eventEndDate),
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
        <h2>{isNew ? w.addTicket : w.edit}</h2>

        <label>
          {w.kind}
          <select value={form.kind} onChange={(e) => set({ kind: e.target.value })}>
            {TICKET_KINDS.map((k) => (
              <option key={k.id} value={k.id}>
                {`${k.emoji} ${locale === "en" ? k.en : k.it}`}
              </option>
            ))}
          </select>
        </label>

        <label>
          {w.fieldTitle}
          <input value={form.title} onChange={(e) => set({ title: e.target.value })} autoFocus required />
        </label>

        <label>
          {w.emitter}
          <input value={form.emitter} onChange={(e) => set({ emitter: e.target.value })} />
        </label>

        <div className="wl-two">
          <label>
            {w.eventDate}
            <input
              type="datetime-local"
              value={form.eventDate}
              onChange={(e) => set({ eventDate: e.target.value })}
            />
          </label>
          <label>
            {w.eventEndDate}
            <input
              type="datetime-local"
              value={form.eventEndDate}
              onChange={(e) => set({ eventEndDate: e.target.value })}
            />
          </label>
        </div>

        <div className="wl-two">
          <label>
            {w.location}
            <input value={form.location} onChange={(e) => set({ location: e.target.value })} />
          </label>
          <label>
            {w.arrival}
            <input
              value={form.arrivalLocation}
              onChange={(e) => set({ arrivalLocation: e.target.value })}
            />
          </label>
        </div>

        <div className="wl-two">
          <label>
            {w.seat}
            <input value={form.seat} onChange={(e) => set({ seat: e.target.value })} />
          </label>
          <label>
            {w.bookingCode}
            <input
              value={form.bookingCode}
              onChange={(e) => set({ bookingCode: e.target.value })}
            />
          </label>
        </div>

        <label>
          {w.holder}
          <input value={form.holderName} onChange={(e) => set({ holderName: e.target.value })} />
        </label>

        <div className="wl-two">
          <label>
            {w.barcodeText}
            <input
              value={form.barcodeText}
              onChange={(e) => set({ barcodeText: e.target.value })}
            />
          </label>
          <label>
            {w.barcodeFormat}
            <input
              value={form.barcodeFormat}
              onChange={(e) => set({ barcodeFormat: e.target.value })}
              placeholder="QR, Code128, EAN-13…"
            />
          </label>
        </div>

        <label>
          {w.reminder}
          <select
            value={form.reminderOffsetHours ?? ""}
            onChange={(e) =>
              set({ reminderOffsetHours: e.target.value === "" ? null : Number(e.target.value) })
            }
          >
            {REMINDERS.map((h) => (
              <option key={h ?? "none"} value={h ?? ""}>
                {h === null ? w.reminderNone : w.reminderHours(h)}
              </option>
            ))}
          </select>
        </label>

        <label>
          {w.visibility}
          <select
            value={form.visibilityScope}
            onChange={(e) => set({ visibilityScope: e.target.value })}
          >
            <option value={WALLET_PRIVATE}>{w.visibilityPrivate}</option>
            <option value={WALLET_MEMBERS}>{w.visibilityMembers}</option>
            <option value={WALLET_FAMILY}>{w.visibilityFamily}</option>
          </select>
        </label>

        {form.visibilityScope === WALLET_MEMBERS && (
          <div className="pw-members">
            {members.map((m) => (
              <label key={m.id} className="pw-check">
                <input
                  type="checkbox"
                  checked={form.visibilityMemberIds.includes(m.id)}
                  onChange={() =>
                    set({
                      visibilityMemberIds: form.visibilityMemberIds.includes(m.id)
                        ? form.visibilityMemberIds.filter((x) => x !== m.id)
                        : [...form.visibilityMemberIds, m.id],
                    })
                  }
                />
                {m.displayName || m.name || m.email || m.id}
              </label>
            ))}
          </div>
        )}

        <label>
          {w.notes}
          <textarea rows="3" value={form.notes} onChange={(e) => set({ notes: e.target.value })} />
        </label>

        {error && <p className="error">{error}</p>}

        <div className="pw-form-actions">
          <button type="button" onClick={onClose}>
            {w.cancel}
          </button>
          <button type="submit" className="pw-btn-primary" disabled={saving}>
            {w.save}
          </button>
        </div>
      </form>
    </Modal>
  );
}
