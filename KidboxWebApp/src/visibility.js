/**
 * Visibilità dei contenuti di famiglia, specchio di KBVisibilityScope su iOS.
 * Vale per eventi, to-do e note (wallet e password hanno le proprie varianti,
 * con default «solo io» invece di «tutta la famiglia»).
 */

export const VISIBILITY_FAMILY = "family";
export const VISIBILITY_MEMBERS = "members";
/** Valore salvato per «Solo io». */
export const VISIBILITY_PRIVATE = "private";

/** `KBVisibilityScope.normalized`: vuoto o ignoto → tutta la famiglia. */
export function normalizedVisibilityScope(raw) {
  if (raw === VISIBILITY_MEMBERS || raw === VISIBILITY_PRIVATE) return raw;
  return VISIBILITY_FAMILY;
}

/** `KBVisibilityScope.isVisible`: chi ha creato il contenuto lo vede sempre. */
export function isVisibleTo({ visibilityScope, visibilityMemberIds, createdBy }, uid) {
  if (!uid) return false;
  switch (normalizedVisibilityScope(visibilityScope)) {
    case VISIBILITY_FAMILY:
      return true;
    case VISIBILITY_MEMBERS:
      return createdBy === uid || (visibilityMemberIds || []).includes(uid);
    default:
      return createdBy === uid;
  }
}
