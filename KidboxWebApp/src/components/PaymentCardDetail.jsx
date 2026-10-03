import { useEffect, useRef, useState } from "react";
import PaymentCardTile from "./PaymentCardTile";
import { useTranslation } from "../i18n/LocaleContext";
import {
  deletePaymentCardPhoto,
  fetchPaymentCardPhoto,
  savePaymentCard,
  uploadPaymentCardPhoto,
} from "../services/paymentCards";
import { grouped, ibanGrouped, isExpired, masked } from "../services/paymentCardFormat";

const REVEAL_MS = 30_000;

/**
 * Pannello di dettaglio di una carta di pagamento. Sul web non c'è Face ID:
 * numero intero e PIN si mostrano a richiesta e si rinasconde da solo dopo 30
 * secondi o appena la scheda del browser passa in secondo piano.
 */
export default function PaymentCardDetail({ card, familyId, user, onCopy, onEdit, onDelete, onClose }) {
  const { t } = useTranslation();
  const w = t.wallet;
  const p = w.pay;

  const [revealed, setRevealed] = useState(false);
  const [photos, setPhotos] = useState({ front: null, back: null });
  const [busy, setBusy] = useState(null);
  const [error, setError] = useState(null);
  const fileRef = useRef(null);
  const pendingSide = useRef(null);

  useEffect(() => {
    if (!revealed) return undefined;
    const timer = window.setTimeout(() => setRevealed(false), REVEAL_MS);
    const onHide = () => {
      if (document.visibilityState !== "visible") setRevealed(false);
    };
    document.addEventListener("visibilitychange", onHide);
    return () => {
      window.clearTimeout(timer);
      document.removeEventListener("visibilitychange", onHide);
    };
  }, [revealed]);

  // Le foto si scaricano e si decifrano qui; gli object URL muoiono col pannello.
  useEffect(() => {
    let cancelled = false;
    const urls = [];
    const load = async (side, path) => {
      if (!path) return;
      try {
        const url = await fetchPaymentCardPhoto({ familyId, userId: user.uid, path });
        if (!url) return;
        urls.push(url);
        if (!cancelled) setPhotos((ph) => ({ ...ph, [side]: url }));
      } catch (err) {
        if (!cancelled) setError(err.message);
      }
    };
    setPhotos({ front: null, back: null });
    load("front", card.frontPhotoStoragePath);
    load("back", card.backPhotoStoragePath);
    return () => {
      cancelled = true;
      urls.forEach((u) => URL.revokeObjectURL(u));
    };
  }, [familyId, user.uid, card.frontPhotoStoragePath, card.backPhotoStoragePath]);

  const userName = user.displayName || "";

  const addPhoto = async (side, file) => {
    if (!file) return;
    setBusy(side);
    setError(null);
    try {
      const { url, path } = await uploadPaymentCardPhoto({
        familyId,
        userId: user.uid,
        cardId: card.id,
        side,
        file,
      });
      await savePaymentCard({
        familyId,
        userId: user.uid,
        userName,
        card: { ...card, [`${side}PhotoStorageURL`]: url, [`${side}PhotoStoragePath`]: path },
      });
    } catch (err) {
      setError(err.message);
    } finally {
      setBusy(null);
    }
  };

  const removePhoto = async (side) => {
    setBusy(side);
    setError(null);
    try {
      await deletePaymentCardPhoto(card[`${side}PhotoStoragePath`]);
      await savePaymentCard({
        familyId,
        userId: user.uid,
        userName,
        card: { ...card, [`${side}PhotoStorageURL`]: null, [`${side}PhotoStoragePath`]: null },
      });
    } catch (err) {
      setError(err.message);
    } finally {
      setBusy(null);
    }
  };

  return (
    <div className="pw-detail-overlay" onClick={onClose}>
      <aside className="pw-detail" onClick={(e) => e.stopPropagation()}>
        <header>
          <h2>{card.label || p.tab}</h2>
          <button onClick={onClose}>✕</button>
        </header>

        <PaymentCardTile
          card={card}
          otherNetwork={p.otherNetwork}
          expiredLabel={p.expired}
          unreadableLabel={p.unreadable}
        />

        {card.cardNumber && (
          <div className="pw-detail-row">
            <span className="pw-detail-label">{p.number}</span>
            <span className="pw-detail-value wl-mono">
              {revealed ? grouped(card.cardNumber) : masked(card.cardNumber)}
            </span>
            <button onClick={() => setRevealed((r) => !r)} title={p.autoHidden}>
              {revealed ? p.hide : p.show}
            </button>
            <button onClick={() => onCopy(card.cardNumber, p.number)}>{w.copy}</button>
          </div>
        )}
        {card.pin && (
          <div className="pw-detail-row">
            <span className="pw-detail-label">{p.pinTitle}</span>
            <span className="pw-detail-value wl-mono">{revealed ? card.pin : "••••"}</span>
            <button onClick={() => setRevealed((r) => !r)} title={p.autoHidden}>
              {revealed ? p.hide : p.show}
            </button>
            <button onClick={() => onCopy(card.pin, p.pinTitle)}>{w.copy}</button>
          </div>
        )}
        {card.holderName && (
          <div className="pw-detail-row">
            <span className="pw-detail-label">{p.holder}</span>
            <span className="pw-detail-value">{card.holderName}</span>
            <button onClick={() => onCopy(card.holderName, p.holder)}>{w.copy}</button>
          </div>
        )}
        {card.expiry && (
          <div className="pw-detail-row">
            <span className="pw-detail-label">{p.expiry}</span>
            <span className="pw-detail-value wl-mono">
              {card.expiry}
              {isExpired(card.expiry) && <strong className="wl-warn"> · {p.expired}</strong>}
            </span>
          </div>
        )}
        {card.iban && (
          <div className="pw-detail-row">
            <span className="pw-detail-label">IBAN</span>
            <span className="pw-detail-value wl-mono">{ibanGrouped(card.iban)}</span>
            <button onClick={() => onCopy(card.iban, "IBAN")}>{w.copy}</button>
          </div>
        )}
        {card.notes && (
          <div className="pw-detail-row">
            <span className="pw-detail-label">{w.notes}</span>
            <span className="pw-detail-value">{card.notes}</span>
          </div>
        )}

        <div className="pw-field-label">{p.photos}</div>
        <div className="wl-photos wl-photos-slots">
          {["front", "back"].map((side) => (
            <div key={side} className="wl-photo-slot">
              <span className="pw-detail-label">{side === "front" ? p.frontPhoto : p.backPhoto}</span>
              {photos[side] ? (
                <a href={photos[side]} target="_blank" rel="noopener noreferrer">
                  <img src={photos[side]} alt={side === "front" ? p.frontPhoto : p.backPhoto} />
                </a>
              ) : card[`${side}PhotoStoragePath`] ? (
                <span className="wl-photo-empty">…</span>
              ) : (
                <button
                  className="wl-photo-empty"
                  disabled={busy === side}
                  onClick={() => {
                    pendingSide.current = side;
                    fileRef.current?.click();
                  }}
                >
                  {busy === side ? "…" : `+ ${p.addPhoto}`}
                </button>
              )}
              {card[`${side}PhotoStoragePath`] && busy !== side && (
                <button className="pw-danger wl-photo-remove" onClick={() => removePhoto(side)}>
                  {p.removePhoto}
                </button>
              )}
            </div>
          ))}
        </div>
        <p className="pw-hint">{p.photosHint}</p>

        {error && <p className="error">{error}</p>}

        <div className="pw-form-actions">
          <button className="pw-danger" onClick={onDelete}>
            {p.deleteCard}
          </button>
          <button className="pw-btn-primary" onClick={onEdit}>
            {w.edit}
          </button>
        </div>

        <input
          ref={fileRef}
          type="file"
          accept="image/*"
          hidden
          onChange={(e) => {
            const f = e.target.files?.[0];
            e.target.value = "";
            if (f && pendingSide.current) addPhoto(pendingSide.current, f);
          }}
        />
      </aside>
    </div>
  );
}
