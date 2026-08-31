/**
 * Controllo password compromesse su Have I Been Pwned, con k-anonymity —
 * porting di `PwnedChecker.swift`.
 *
 * La password in chiaro non lascia mai il browser: si inviano solo i primi
 * cinque caratteri dell'hash SHA-1, e il confronto sul resto avviene qui.
 */
const ENDPOINT = "https://api.pwnedpasswords.com/range/";
const CACHE_TTL_MS = 24 * 60 * 60 * 1000;

/** Sentinella per «non si è potuto controllare» (offline, rete bloccata). */
export const UNKNOWN = -1;

const prefixCache = new Map();

async function sha1Hex(text) {
  const digest = await crypto.subtle.digest("SHA-1", new TextEncoder().encode(text));
  return [...new Uint8Array(digest)]
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("")
    .toUpperCase();
}

async function suffixesFor(prefix) {
  const cached = prefixCache.get(prefix);
  if (cached && cached.expiresAt > Date.now()) return cached.map;

  const res = await fetch(ENDPOINT + prefix, { headers: { "Add-Padding": "true" } });
  if (!res.ok) throw new Error(`HIBP ${res.status}`);
  const text = await res.text();

  const map = new Map();
  for (const line of text.split("\n")) {
    const [suffix, count] = line.trim().split(":");
    if (suffix) map.set(suffix.toUpperCase(), Number(count) || 0);
  }
  prefixCache.set(prefix, { expiresAt: Date.now() + CACHE_TTL_MS, map });
  return map;
}

/**
 * Quante volte la password compare nei data breach noti.
 * `0` = mai trovata, `>0` = numero di occorrenze, `UNKNOWN` = non verificabile.
 */
export async function pwnedCount(password) {
  const trimmed = (password || "").trim();
  if (!trimmed) return 0;
  if (typeof navigator !== "undefined" && navigator.onLine === false) return UNKNOWN;

  try {
    const hash = await sha1Hex(trimmed);
    const map = await suffixesFor(hash.slice(0, 5));
    return map.get(hash.slice(5)) ?? 0;
  } catch {
    return UNKNOWN;
  }
}

/** SHA-256 esadecimale: serve a raggruppare i duplicati senza uscire dal browser. */
export async function sha256Hex(text) {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text));
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, "0")).join("");
}
