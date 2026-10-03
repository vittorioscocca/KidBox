import { isExpired, masked, networkName } from "../services/paymentCardFormat";

/**
 * La carta disegnata: nome e circuito in alto, numero mascherato, titolare e
 * scadenza in basso. Il numero intero non compare mai qui.
 * Mirror di `PaymentCardTileView` (iOS).
 */
export default function PaymentCardTile({ card, otherNetwork, expiredLabel, unreadableLabel, onClick }) {
  const network = networkName(card.cardNumber);
  // Il circuito sta già a destra: senza nome non si ripete.
  const title = card.unreadable ? unreadableLabel : card.label || (network ? "" : otherNetwork);
  const Tag = onClick ? "button" : "div";
  return (
    <Tag
      type={onClick ? "button" : undefined}
      className="wl-paycard"
      style={{ background: `linear-gradient(135deg, ${card.colorHex}, ${card.colorHex}c7), #000` }}
      onClick={onClick}
    >
      <span className="wl-paycard-top">
        <span className="wl-paycard-title">{title}</span>
        {network && <span className="wl-paycard-network">{network}</span>}
      </span>
      <span className="wl-paycard-chip" aria-hidden="true">💳</span>
      {card.cardNumber && <span className="wl-paycard-number">{masked(card.cardNumber)}</span>}
      <span className="wl-paycard-bottom">
        <span className="wl-paycard-holder">{(card.holderName || "").toUpperCase()}</span>
        {card.expiry && (
          <span className="wl-paycard-expiry">
            {isExpired(card.expiry) && <span className="wl-paycard-expired">{expiredLabel}</span>}
            {card.expiry}
          </span>
        )}
      </span>
    </Tag>
  );
}
