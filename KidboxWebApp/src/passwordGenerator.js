/**
 * Generatore di password, porting di `PasswordGenerator.swift`: stessi pool di
 * caratteri, stessa esclusione degli ambigui, stessa garanzia di almeno un
 * carattere per ogni set attivo.
 *
 * L'unica differenza è la sorgente casuale: qui `crypto.getRandomValues` al
 * posto di `SystemRandomNumberGenerator`.
 */
const LOWERCASE = "abcdefghijklmnopqrstuvwxyz";
const UPPERCASE = "ABCDEFGHIJKLMNOPQRSTUVWXYZ";
const DIGITS = "0123456789";
const SYMBOLS = "!@#$%^&*()-_=+[]{}|;:,.<>?/~`";
const AMBIGUOUS = new Set(["0", "O", "1", "l", "I"]);

export const DEFAULT_OPTIONS = {
  length: 18,
  includeUppercase: true,
  includeLowercase: true,
  includeNumbers: true,
  includeSymbols: true,
  excludeAmbiguous: true,
};

/** Indice casuale senza modulo bias. */
function randomIndex(max) {
  if (max <= 0) return 0;
  const limit = Math.floor(0xffffffff / max) * max;
  const buf = new Uint32Array(1);
  let value;
  do {
    crypto.getRandomValues(buf);
    [value] = buf;
  } while (value >= limit);
  return value % max;
}

function pick(pool) {
  return pool[randomIndex(pool.length)];
}

function filtered(pool, excludeAmbiguous) {
  if (!excludeAmbiguous) return pool;
  return [...pool].filter((c) => !AMBIGUOUS.has(c)).join("");
}

export function generate(raw = DEFAULT_OPTIONS) {
  const options = { ...DEFAULT_OPTIONS, ...raw };
  options.length = Math.max(8, Math.min(64, options.length || 18));

  let pools = [];
  if (options.includeLowercase) pools.push(filtered(LOWERCASE, options.excludeAmbiguous));
  if (options.includeUppercase) pools.push(filtered(UPPERCASE, options.excludeAmbiguous));
  if (options.includeNumbers) pools.push(filtered(DIGITS, options.excludeAmbiguous));
  // I simboli non contengono ambigui: nessun filtro, come su iOS.
  if (options.includeSymbols) pools.push(SYMBOLS);
  pools = pools.filter((p) => p.length > 0);

  // Nessun set attivo: si ricade sui default invece di restituire vuoto.
  if (pools.length === 0) {
    return generate({ ...DEFAULT_OPTIONS, length: options.length });
  }

  // Almeno un carattere da ogni set abilitato, poi si riempie dall'unione.
  const chars = pools.map(pick);
  const union = pools.join("");
  while (chars.length < options.length) chars.push(pick(union));

  for (let i = chars.length - 1; i > 0; i -= 1) {
    const j = randomIndex(i + 1);
    [chars[i], chars[j]] = [chars[j], chars[i]];
  }
  return chars.slice(0, options.length).join("");
}
