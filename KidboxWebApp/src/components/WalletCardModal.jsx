import { useState } from "react";
import Modal from "./Modal";
import { useTranslation } from "../i18n/LocaleContext";
import { WALLET_FAMILY, WALLET_MEMBERS, WALLET_PRIVATE } from "../services/wallet";

const PALETTE = [
  ["#3A3A3C", "#1C1C1E"],
  ["#0A84FF", "#0B4F9E"],
  ["#34C759", "#1E7A38"],
  ["#FF9500", "#B36800"],
  ["#FF2D55", "#A31538"],
  ["#5E5CE6", "#3B3A93"],
  ["#e8833a", "#c96a20"],
];

/** Creazione e modifica di una tessera fedeltà. */
export default function WalletCardModal({ card, members, onSave, onUploadPhoto, onClose }) {
  const { t } = useTranslation();
  const w = t.wallet;
  const isNew = !card?.id;

  const [form, setForm] = useState(() => ({
    brandName: card?.brandName || "",
    cardNumber: card?.cardNumber || "",
    barcodeFormat: card?.barcodeFormat || "",
    note: card?.note || "",
    primaryColorHex: card?.primaryColorHex || PALETTE[0][0],
    secondaryColorHex: card?.secondaryColorHex || PALETTE[0][1],
    visibilityScope: card?.visibilityScope || WALLET_PRIVATE,
    visibilityMemberIds: card?.visibilityMemberIds || [],
    frontPhotoStorageURL: card?.frontPhotoStorageURL || null,
    frontPhotoStoragePath: card?.frontPhotoStoragePath || null,
    backPhotoStorageURL: card?.backPhotoStorageURL || null,
    backPhotoStoragePath: card?.backPhotoStoragePath || null,
  }));
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState(null);

  const set = (patch) => setForm((f) => ({ ...f, ...patch }));

  const pickPhoto = async (side, file) => {
    if (!file) return;
    try {
      const { url, path } = await onUploadPhoto(side, file);
      set(
        side === "front"
          ? { frontPhotoStorageURL: url, frontPhotoStoragePath: path }
          : { backPhotoStorageURL: url, backPhotoStoragePath: path }
      );
    } catch (err) {
      setError(err.message);
    }
  };

  const submit = async (e) => {
    e.preventDefault();
    if (!form.brandName.trim()) return;
    setSaving(true);
    setError(null);
    try {
      await onSave({
        ...card,
        ...form,
        brandName: form.brandName.trim(),
        cardNumber: form.cardNumber.trim(),
        note: form.note.trim() || null,
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
        <h2>{isNew ? w.addCard : w.edit}</h2>

        <label>
          {w.brandName}
          <input
            value={form.brandName}
            onChange={(e) => set({ brandName: e.target.value })}
            autoFocus
            required
          />
        </label>

        <div className="wl-two">
          <label>
            {w.cardNumber}
            <input
              value={form.cardNumber}
              onChange={(e) => set({ cardNumber: e.target.value })}
            />
          </label>
          <label>
            {w.barcodeFormat}
            <input
              value={form.barcodeFormat}
              onChange={(e) => set({ barcodeFormat: e.target.value })}
              placeholder="EAN-13, Code128, QR…"
            />
          </label>
        </div>

        <div className="pw-field-label">{w.cardColor}</div>
        <div className="pw-color-grid">
          {PALETTE.map(([primary, secondary]) => (
            <button
              type="button"
              key={primary}
              className={"pw-color" + (form.primaryColorHex === primary ? " selected" : "")}
              style={{ background: `linear-gradient(135deg, ${primary}, ${secondary})` }}
              onClick={() => set({ primaryColorHex: primary, secondaryColorHex: secondary })}
              aria-label={primary}
            />
          ))}
        </div>

        <div className="wl-two">
          <label>
            {w.frontPhoto}
            <input
              type="file"
              accept="image/*"
              onChange={(e) => pickPhoto("front", e.target.files?.[0])}
            />
          </label>
          <label>
            {w.backPhoto}
            <input
              type="file"
              accept="image/*"
              onChange={(e) => pickPhoto("back", e.target.files?.[0])}
            />
          </label>
        </div>

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
          <textarea rows="2" value={form.note} onChange={(e) => set({ note: e.target.value })} />
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
