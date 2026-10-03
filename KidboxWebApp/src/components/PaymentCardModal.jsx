import { useState } from "react";
import Modal from "./Modal";
import VisibilityPickerModal, { VisibilityChip } from "./VisibilityPickerModal";
import PaymentCardTile from "./PaymentCardTile";
import { useTranslation } from "../i18n/LocaleContext";
import { WALLET_PRIVATE } from "../services/wallet";
import {
  digits,
  expiryInput,
  grouped,
  ibanCompact,
  ibanGrouped,
  isValidExpiry,
  isValidIban,
  passesLuhn,
  PAYMENT_CARD_DEFAULT_HEX,
  PAYMENT_CARD_PALETTE,
} from "../services/paymentCardFormat";

/**
 * Creazione e modifica di una carta di pagamento, solo a mano: niente AI,
 * niente scansione del numero. I controlli avvisano ma non bloccano, tranne
 * il numero (almeno 12 cifre). Mirror di `PaymentCardFormView` (iOS).
 */
export default function PaymentCardModal({ card, members, onSave, onClose }) {
  const { t } = useTranslation();
  const w = t.wallet;
  const p = w.pay;
  const isNew = !card?.id;

  const [form, setForm] = useState(() => ({
    label: card?.label || "",
    cardNumber: grouped(card?.cardNumber || ""),
    holderName: card?.holderName || "",
    expiry: card?.expiry || "",
    iban: ibanGrouped(card?.iban || ""),
    notes: card?.notes || "",
    pin: card?.pin || "",
    colorHex: card?.colorHex || PAYMENT_CARD_DEFAULT_HEX,
    visibilityScope: card?.visibilityScope || WALLET_PRIVATE,
    visibilityMemberIds: card?.visibilityMemberIds || [],
  }));
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState(null);
  const [showVisibility, setShowVisibility] = useState(false);

  const set = (patch) => setForm((f) => ({ ...f, ...patch }));
  const numberDigits = digits(form.cardNumber);
  const numberWarn = numberDigits.length >= 12 && !passesLuhn(numberDigits);
  const expiryWarn = form.expiry.length === 5 && !isValidExpiry(form.expiry);
  const ibanWarn = ibanCompact(form.iban).length >= 15 && !isValidIban(form.iban);

  const submit = async (e) => {
    e.preventDefault();
    if (numberDigits.length < 12) return;
    setSaving(true);
    setError(null);
    try {
      await onSave({
        ...card,
        ...form,
        label: form.label.trim(),
        cardNumber: numberDigits,
        holderName: form.holderName.trim(),
        expiry: isValidExpiry(form.expiry) ? form.expiry : "",
        iban: ibanCompact(form.iban),
        notes: form.notes.trim(),
      });
      onClose();
    } catch (err) {
      setError(err.message);
      setSaving(false);
    }
  };

  return (
    <Modal onClose={onClose}>
      <form className="pw-form" onSubmit={submit} autoComplete="off">
        <h2>{isNew ? p.newTitle : p.editTitle}</h2>

        <PaymentCardTile
          card={{
            label: form.label.trim(),
            cardNumber: numberDigits,
            holderName: form.holderName.trim(),
            expiry: form.expiry,
            colorHex: form.colorHex,
          }}
          otherNetwork={p.otherNetwork}
          expiredLabel={p.expired}
          unreadableLabel={p.unreadable}
        />

        <label>
          {p.label}
          <input
            value={form.label}
            placeholder={p.labelPlaceholder}
            onChange={(e) => set({ label: e.target.value })}
          />
        </label>

        <label>
          {p.number}
          <input
            className="wl-mono"
            inputMode="numeric"
            autoComplete="off"
            value={form.cardNumber}
            onChange={(e) => set({ cardNumber: grouped(e.target.value) })}
            required
          />
          {numberWarn && <span className="wl-warn">{p.numberInvalid}</span>}
        </label>

        <div className="wl-two">
          <label>
            {p.holder}
            <input
              value={form.holderName}
              placeholder={p.holderPlaceholder}
              autoComplete="off"
              onChange={(e) => set({ holderName: e.target.value.toUpperCase() })}
            />
          </label>
          <label>
            {p.expiry}
            <input
              className="wl-mono"
              inputMode="numeric"
              placeholder="MM/AA"
              value={form.expiry}
              onChange={(e) => set({ expiry: expiryInput(e.target.value) })}
            />
            {expiryWarn && <span className="wl-warn">{p.expiryInvalid}</span>}
          </label>
        </div>

        <label>
          {p.iban}
          <input
            className="wl-mono"
            placeholder="IT00 X000 0000 0000 0000 0000 000"
            value={form.iban}
            onChange={(e) => set({ iban: ibanGrouped(e.target.value) })}
          />
          {ibanWarn && <span className="wl-warn">{p.ibanInvalid}</span>}
        </label>

        <label>
          {p.pin}
          <input
            className="wl-mono"
            type="password"
            inputMode="numeric"
            autoComplete="off"
            value={form.pin}
            onChange={(e) => set({ pin: e.target.value.replace(/\D/g, "").slice(0, 8) })}
          />
          <span className="pw-hint">{p.pinHint}</span>
        </label>

        <div className="pw-field-label">{p.color}</div>
        <div className="pw-color-grid">
          {PAYMENT_CARD_PALETTE.map((hex) => (
            <button
              type="button"
              key={hex}
              className={"pw-color" + (form.colorHex === hex ? " selected" : "")}
              style={{ background: hex }}
              onClick={() => set({ colorHex: hex })}
              aria-label={hex}
            />
          ))}
        </div>

        <label>
          {w.visibility}
          <VisibilityChip
            scope={form.visibilityScope}
            locked={false}
            lockedHint={w.visibilityLocked}
            onOpen={() => setShowVisibility(true)}
          />
        </label>

        <label>
          {p.notes}
          <textarea rows="2" value={form.notes} onChange={(e) => set({ notes: e.target.value })} />
        </label>

        <p className="pw-hint">{p.securityFooter}</p>

        {error && <p className="error">{error}</p>}

        <div className="pw-form-actions">
          <button type="button" onClick={onClose}>
            {w.cancel}
          </button>
          <button type="submit" className="pw-btn-primary" disabled={saving || numberDigits.length < 12}>
            {w.save}
          </button>
        </div>
      </form>
      {showVisibility && (
        <VisibilityPickerModal
          scope={form.visibilityScope}
          memberIds={form.visibilityMemberIds}
          members={members}
          whoCanSee={p.whoCanSee}
          onConfirm={(scope, ids) => {
            set({ visibilityScope: scope, visibilityMemberIds: ids });
            setShowVisibility(false);
          }}
          onClose={() => setShowVisibility(false)}
        />
      )}
    </Modal>
  );
}
