import { useEffect, useState } from "react";
import { loadPlan } from "../services/profile";

/**
 * Piano attivo della famiglia corrente, risolto come lo risolve il server
 * (`resolveFamilyPlanForQuotas`): override amministrativo, scadenza, fallback
 * sull'utente.
 *
 * Serve solo alla UX di upsell — a decidere davvero è il gate server sulla
 * callable. Finché la lettura non è arrivata il valore è `null`: le schermate
 * devono trattarlo come «non so ancora», non come «free», altrimenti un utente
 * Pro vede lampeggiare il messaggio di upgrade a ogni apertura.
 */
export function usePlan({ familyId, uid }) {
  const [plan, setPlan] = useState(null);

  useEffect(() => {
    if (!uid) return undefined;
    let cancelled = false;
    loadPlan({ familyId, uid })
      .then((value) => !cancelled && setPlan(value))
      .catch(() => !cancelled && setPlan(null));
    return () => {
      cancelled = true;
    };
  }, [familyId, uid]);

  return plan;
}
