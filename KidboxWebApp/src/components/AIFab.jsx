/**
 * Pulsante AI flottante, in basso a destra: l'equivalente web di
 * `AskAIControl(style: .circle)` su iOS, che è un cerchio sopra il contenuto e
 * non una voce fra le altre.
 *
 * Due usi: l'assistente di famiglia, montato dal `Layout` in tutte le sezioni
 * che non hanno un'AI propria, e le chat di Salute (hub, visite, analisi), che
 * lo montano al posto dell'assistente. Mai due insieme: la lista delle sezioni
 * escluse sta in `Layout`.
 *
 * L'etichetta si vede al passaggio del mouse; sul touch resta solo il cerchio,
 * col testo come nome accessibile.
 */
import "./AIFab.css";

export default function AIFab({ label, onClick, disabled = false }) {
  return (
    <button
      type="button"
      className="ai-fab"
      aria-label={label}
      title={label}
      disabled={disabled}
      onClick={onClick}
    >
      <svg viewBox="0 0 24 24" aria-hidden="true" className="ai-fab-icon">
        <path
          fill="currentColor"
          d="M9 3c.3 4.2 3.3 7.2 7.5 7.5-4.2.3-7.2 3.3-7.5 7.5-.3-4.2-3.3-7.2-7.5-7.5 4.2-.3 7.2-3.3 7.5-7.5ZM18.5 13c.2 2.1 1.4 3.3 3.5 3.5-2.1.2-3.3 1.4-3.5 3.5-.2-2.1-1.4-3.3-3.5-3.5 2.1-.2 3.3-1.4 3.5-3.5ZM18 2c.15 1.5 1 2.35 2.5 2.5-1.5.15-2.35 1-2.5 2.5-.15-1.5-1-2.35-2.5-2.5 1.5-.15 2.35-1 2.5-2.5Z"
        />
      </svg>
      <span className="ai-fab-label">{label}</span>
    </button>
  );
}
