import { useEffect, useState } from "react";
import CardPhotoSlots from "./CardPhotoSlots";
import PaymentCardTile from "./PaymentCardTile";
import { useTranslation } from "../i18n/LocaleContext";
import {
  deletePaymentCardPhoto,
  savePaymentCard,
  uploadPaymentCardPhoto,
} from "../services/paymentCards";
import { grouped, ibanGrouped, isExpired, masked } from "../services/paymentCardFormat";

const REVEAL_MS = 30_000;

/**
 * Pannello di dettaglio di una carta di pagamento. Sul web non c'è Face ID:
 * numero intero e PIN si mostrano a richiesta e si rinascondono da soli dopo 30
 * secondi o appena la scheda del browser passa in secondo piano.
 */
export default function PaymentCardDetail({ card, familyId, user, onCopy, onEdit, onDelete, onClose }) {
  const { t } = useTranslation();
  const w = t.wallet;
  const p = w.pay;

  const [revealed, setRevealed] = useState(false);

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

  const userName = user.displayName || "";

  const saveWithPhoto = (side, url, path) =>
    savePaymentCard({
      familyId,
      userId: user.uid,
      userName,
      card: { ...card, [`${side}PhotoStorageURL`]: url, [`${side}PhotoStoragePath`]: path },
    });

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

        <CardPhotoSlots
          familyId={familyId}
          userId={user.uid}
          frontPath={card.frontPhotoStoragePath}
          backPath={card.backPhotoStoragePath}
          labels={{
            title: p.photos,
            front: p.frontPhoto,
            back: p.backPhoto,
            add: p.addPhoto,
            remove: p.removePhoto,
            hint: p.photosHint,
          }}
          onUpload={async (side, file) => {
            const { url, path } = await uploadPaymentCardPhoto({
              familyId,
              userId: user.uid,
              cardId: card.id,
              side,
              file,
            });
            await saveWithPhoto(side, url, path);
          }}
          onRemove={async (side) => {
            await deletePaymentCardPhoto(card[`${side}PhotoStoragePath`]);
            await saveWithPhoto(side, null, null);
          }}
        />

        <div className="pw-form-actions">
          <button className="pw-danger" onClick={onDelete}>
            {p.deleteCard}
          </button>
          <button className="pw-btn-primary" onClick={onEdit}>
            {w.edit}
          </button>
        </div>
      </aside>
    </div>
  );
}
