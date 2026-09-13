/** Costanti condivise fra indice e dettaglio delle Impostazioni. */
export const GUIDE_URL = "https://kidboxapp.com/guide.html";
export const SITE_URL = "https://kidboxapp.com";
export const SUPPORT_MAIL = "supporto@kidboxapp.com";
export const AI_CONSENT_KEY = "kidbox:aiConsent";
export const ERROR_REPORTS_KEY = "kidbox:errorReports";

export const PROVIDER_NAMES = {
  "google.com": "Google",
  "apple.com": "Apple",
  "facebook.com": "Facebook",
  password: "Email",
};

export const NOTIFICATION_ICONS = {
  notifyOnNewMessages: "💬",
  notifyOnLocationSharing: "📍",
  notifyOnTodoAssigned: "✅",
  notifyOnNewGroceryItem: "🛒",
  notifyOnNewNote: "📝",
  notifyOnNewExpense: "💶",
  notifyOnNewCalendarEvent: "📅",
  notifyOnNewDocument: "📄",
  notifyOnWallet: "👛",
};

export function formatBytes(bytes) {
  if (!bytes) return "0 B";
  const units = ["B", "KB", "MB", "GB", "TB"];
  let value = bytes;
  let i = 0;
  while (value >= 1024 && i < units.length - 1) {
    value /= 1024;
    i += 1;
  }
  return `${value.toFixed(i === 0 ? 0 : 1)} ${units[i]}`;
}
