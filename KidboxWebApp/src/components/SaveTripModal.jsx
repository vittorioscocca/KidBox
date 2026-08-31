import { useState } from "react";
import Modal from "./Modal";
import { useTranslation } from "../i18n/LocaleContext";

const toDateInput = (millis) => new Date(millis).toISOString().slice(0, 10);

/**
 * Archivia i prodotti presi in uno scontrino, come `SaveShoppingTripView`.
 * Il totale è facoltativo: senza importo lo scontrino resta un elenco, con
 * importo alimenta anche le spese di famiglia.
 */
export default function SaveTripModal({ items, trip, onSave, onClose }) {
  const { t } = useTranslation();
  const g = t.grocery;
  const editing = Boolean(trip);
  const [storeName, setStoreName] = useState(trip?.storeName || "");
  const [totalText, setTotalText] = useState(
    trip && trip.total > 0 ? String(trip.total).replace(".", ",") : ""
  );
  const [date, setDate] = useState(toDateInput(trip?.date || Date.now()));
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState(null);

  const lines = editing ? trip.lines : items;
  const parsedTotal = parseFloat(totalText.replace(",", "."));
  const total = Number.isFinite(parsedTotal) ? parsedTotal : null;

  const submit = async (e) => {
    e.preventDefault();
    setSaving(true);
    setError(null);
    try {
      await onSave({ storeName, total, date: new Date(date).getTime() });
      onClose();
    } catch (err) {
      setError(err.message);
      setSaving(false);
    }
  };

  return (
    <Modal onClose={onClose}>
      <form className="pw-form" onSubmit={submit}>
        <h2>{editing ? g.editTrip : g.saveTrip}</h2>

        <label>
          {g.store}
          <input
            value={storeName}
            onChange={(e) => setStoreName(e.target.value)}
            placeholder={g.storePlaceholder}
            autoFocus
          />
        </label>

        <div className="wl-two">
          <label>
            {g.total}
            <input
              value={totalText}
              onChange={(e) => setTotalText(e.target.value)}
              placeholder="0,00"
              inputMode="decimal"
            />
          </label>
          <label>
            {g.tripDate}
            <input type="date" value={date} onChange={(e) => setDate(e.target.value)} />
          </label>
        </div>

        {/* In modifica i prodotti si mostrano ma non si toccano: sono l'archivio
            di cosa è stato preso, riscriverli falsificherebbe lo scontrino. */}
        <div className="pw-field-label">{g.products(lines.length)}</div>
        <ul className="trip-preview">
          {lines.map((l, index) => (
            <li key={`${l.name}-${index}`}>
              {l.name}
              {(l.quantity ?? 1) > 1 && <span> ×{l.quantity}</span>}
            </li>
          ))}
        </ul>

        <p className="pw-hint">{editing ? g.editTripHint : g.tripHint}</p>
        {error && <p className="error">{error}</p>}

        <div className="pw-form-actions">
          <button type="button" onClick={onClose}>
            {g.cancel ?? "Annulla"}
          </button>
          <button type="submit" className="pw-btn-primary" disabled={saving || !lines.length}>
            {g.save ?? g.saveTrip}
          </button>
        </div>
      </form>
    </Modal>
  );
}
