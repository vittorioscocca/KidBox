/** Formattazioni condivise dalle bolle della chat e dal player dei vocali. */

export function formatBytes(bytes) {
  if (!bytes) return "";
  const units = ["B", "KB", "MB", "GB"];
  let value = bytes;
  let i = 0;
  while (value >= 1024 && i < units.length - 1) {
    value /= 1024;
    i += 1;
  }
  return `${value.toFixed(i === 0 ? 0 : 1)} ${units[i]}`;
}

export function formatDuration(seconds) {
  if (!seconds && seconds !== 0) return "";
  const total = Math.round(seconds);
  return `${Math.floor(total / 60)}:${String(total % 60).padStart(2, "0")}`;
}

/**
 * URL del video per le anteprime, con il fotogramma iniziale visibile.
 *
 * Safari (e ogni browser WebKit) con `preload="metadata"` scarica solo i
 * metadati e lascia il riquadro vuoto col pulsante play: nessun client salva una
 * miniatura dei video della chat, quindi non c'è un `poster` da dargli. Il
 * frammento `#t=0.1` gli fa cercare quell'istante e disegnare il fotogramma;
 * negli altri browser non cambia nulla.
 */
export function videoPreviewSrc(url) {
  if (!url || url.includes("#")) return url;
  return `${url}#t=0.1`;
}
