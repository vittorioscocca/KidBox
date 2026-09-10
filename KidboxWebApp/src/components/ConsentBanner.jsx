import { useState } from "react";
import { useTranslation } from "../i18n/LocaleContext";
import {
  analyticsConsent,
  CONSENT_DENIED,
  CONSENT_GRANTED,
  setAnalyticsConsent,
} from "../services/analytics";
import "./ConsentBanner.css";

/**
 * Richiesta di consenso per le statistiche d'uso.
 *
 * Compare finché la scelta non è stata fatta — anche sulla schermata di accesso,
 * perché è lì che partirebbero i primi eventi. Finché è aperto non viene
 * mandato nulla: il default è «non deciso», che equivale a spento.
 *
 * Le due risposte hanno lo stesso peso visivo: un «rifiuta» sbiadito accanto a
 * un «accetta» colorato è una scelta guidata, non una scelta.
 */
export default function ConsentBanner() {
  const { t } = useTranslation();
  const c = t.consent;
  const [decided, setDecided] = useState(() => analyticsConsent() !== null);

  if (decided) return null;

  const choose = (value) => {
    setAnalyticsConsent(value);
    setDecided(true);
  };

  return (
    <div className="consent-banner" role="dialog" aria-label={c.title}>
      <div className="consent-text">
        <strong>{c.title}</strong>
        <p>{c.body}</p>
      </div>
      <div className="consent-actions">
        <button type="button" onClick={() => choose(CONSENT_DENIED)}>
          {c.decline}
        </button>
        <button type="button" onClick={() => choose(CONSENT_GRANTED)}>
          {c.accept}
        </button>
      </div>
    </div>
  );
}
