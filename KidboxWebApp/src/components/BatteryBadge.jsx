import "./BatteryBadge.css";

/**
 * Pila e percentuale accanto a chi condivide la posizione, come `BatteryBadge`
 * su iOS: rossa sotto il 20% e non in carica, verde in carica, altrimenti
 * neutra. Il livello lo dice comunque il numero.
 */
export function batteryTone(level, isCharging) {
  if (isCharging) return "charging";
  return level <= 20 ? "low" : "normal";
}

/** Riempimento della pila: 4 tacche come i simboli battery.0/25/50/75/100. */
function fillWidth(level) {
  if (level <= 10) return 0;
  if (level <= 35) return 3;
  if (level <= 65) return 6;
  if (level <= 85) return 9;
  return 12;
}

export function batteryIconSvg(level, isCharging) {
  const w = fillWidth(level);
  const fill = w > 0 ? `<rect x="2" y="3" width="${w}" height="6" rx="1" fill="currentColor"/>` : "";
  const bolt = isCharging
    ? `<path d="M9 1 5.5 6.5H8L7 11l3.5-5.5H8z" fill="#fff" stroke="currentColor" stroke-width="0.6" stroke-linejoin="round"/>`
    : "";
  return (
    `<svg class="battery-icon" viewBox="0 0 18 12" width="18" height="12" aria-hidden="true">` +
    `<rect x="0.5" y="1.5" width="15" height="9" rx="2" fill="none" stroke="currentColor" stroke-width="1"/>` +
    `<rect x="16" y="4" width="1.5" height="4" rx="0.5" fill="currentColor"/>` +
    fill +
    bolt +
    `</svg>`
  );
}

/** Versione stringa per i marker Leaflet (divIcon accetta solo HTML). */
export function batteryBadgeHtml(level, isCharging) {
  if (level == null) return "";
  return (
    `<span class="battery-badge ${batteryTone(level, isCharging)}">` +
    batteryIconSvg(level, isCharging) +
    `<span>${Math.round(level)}%</span></span>`
  );
}

export default function BatteryBadge({ level, isCharging }) {
  if (level == null) return null;
  return (
    <span
      className={`battery-badge ${batteryTone(level, isCharging)}`}
      dangerouslySetInnerHTML={{
        __html: batteryIconSvg(level, isCharging) + `<span>${Math.round(level)}%</span>`,
      }}
    />
  );
}
