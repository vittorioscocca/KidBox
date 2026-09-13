/**
 * Invito arrivato dall'URL, in attesa che l'utente sia dentro.
 *
 * Gemello di `PendingFamilyInvite` (iOS): chi apre `app.kidboxapp.com/join?…#k=…`
 * di solito non è ancora loggato, e il login social ricarica la pagina — il
 * frammento con il segreto andrebbe perso. Lo si mette da parte in
 * sessionStorage (mai in localStorage: è materiale che apre una famiglia) e
 * si ripulisce subito l'indirizzo, così non resta nella cronologia.
 */
import { parseInvite } from "./onboarding";

const KEY = "kidbox:pendingInvite";

export function captureInviteFromLocation() {
  if (window.location.pathname.replace(/\/$/, "") !== "/join") return;
  const parsed = parseInvite(window.location.href);
  if (parsed) {
    try {
      sessionStorage.setItem(KEY, window.location.href);
    } catch {
      // Storage bloccato: si prosegue con il link ancora nell'URL.
      return;
    }
  }
  window.history.replaceState(null, "", "/");
}

export function pendingInvite() {
  try {
    const raw = sessionStorage.getItem(KEY);
    return raw ? parseInvite(raw) : null;
  } catch {
    return null;
  }
}

export function clearPendingInvite() {
  try {
    sessionStorage.removeItem(KEY);
  } catch {
    // niente da fare
  }
}
