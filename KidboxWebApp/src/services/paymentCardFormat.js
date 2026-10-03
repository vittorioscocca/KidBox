/**
 * Circuito, controlli e formattazione delle carte di pagamento. Stessa logica
 * di `PaymentCardFormatting.swift` (iOS) e `PaymentCardFormatting.kt`
 * (Android): se cambia qui, cambia anche lì.
 */

const NETWORK_NAMES = {
  visa: "Visa",
  mastercard: "Mastercard",
  amex: "American Express",
  maestro: "Maestro",
  discover: "Discover",
  diners: "Diners Club",
  jcb: "JCB",
  unionpay: "UnionPay",
  other: null,
};

/** Solo cifre, massimo 19. */
export const digits = (raw) => String(raw || "").replace(/\D/g, "").slice(0, 19);

/** Riconoscimento dalle prime cifre: serve solo a mostrare il circuito. */
export function detectNetwork(number) {
  const d = digits(number);
  if (!d) return "other";
  const p = (n) => (d.length >= n ? Number(d.slice(0, n)) : -1);
  const between = (v, a, b) => v >= a && v <= b;
  if (d[0] === "4") return "visa";
  if (p(2) === 34 || p(2) === 37) return "amex";
  if (between(p(2), 51, 55) || between(p(4), 2221, 2720)) return "mastercard";
  if (p(4) === 6011 || p(2) === 65 || between(p(3), 644, 649)) return "discover";
  if (between(p(4), 3528, 3589)) return "jcb";
  if (p(2) === 36 || p(2) === 38 || p(2) === 39 || between(p(3), 300, 305)) return "diners";
  if (p(2) === 62) return "unionpay";
  if (p(2) === 50 || between(p(2), 56, 69)) return "maestro";
  return "other";
}

export const networkName = (number) => NETWORK_NAMES[detectNetwork(number)];

/** A gruppi: 4-6-5 per American Express, 4-4-4-4(-3) per gli altri. */
export function grouped(number) {
  const d = digits(number);
  const sizes = detectNetwork(d) === "amex" ? [4, 6, 5] : [4, 4, 4, 4, 3];
  const out = [];
  let rest = d;
  for (const size of sizes) {
    if (!rest) break;
    out.push(rest.slice(0, size));
    rest = rest.slice(size);
  }
  return out.join(" ");
}

/** Restano visibili solo le ultime 4 cifre. */
export function masked(number) {
  const d = digits(number);
  if (d.length <= 4) return d;
  return "•••• •••• •••• " + d.slice(-4);
}

/** Controllo di Luhn: il form avvisa ma non blocca. */
export function passesLuhn(number) {
  const d = digits(number);
  if (d.length < 12) return false;
  let sum = 0;
  [...d].reverse().forEach((ch, i) => {
    let n = Number(ch);
    if (i % 2 === 1) {
      n *= 2;
      if (n > 9) n -= 9;
    }
    sum += n;
  });
  return sum % 10 === 0;
}

/** Normalizza quello che si digita in `MM/AA`, inserendo la barra da sé. */
export function expiryInput(raw) {
  const d = String(raw || "").replace(/\D/g, "").slice(0, 4);
  return d.length > 2 ? `${d.slice(0, 2)}/${d.slice(2)}` : d;
}

function monthYear(expiry) {
  const d = String(expiry || "").replace(/\D/g, "");
  if (d.length !== 4) return null;
  return [Number(d.slice(0, 2)), Number(d.slice(2))];
}

export function isValidExpiry(expiry) {
  const my = monthYear(expiry);
  return Boolean(my) && my[0] >= 1 && my[0] <= 12;
}

/** Scaduta = finito il mese indicato. */
export function isExpired(expiry, now = new Date()) {
  const my = monthYear(expiry);
  if (!my || my[0] < 1 || my[0] > 12) return false;
  const [m, y] = my;
  const curY = now.getFullYear() % 100;
  const curM = now.getMonth() + 1;
  return y < curY || (y === curY && m < curM);
}

/** Maiuscolo, senza spazi, massimo 34 caratteri. */
export const ibanCompact = (raw) =>
  String(raw || "").toUpperCase().replace(/[^A-Z0-9]/g, "").slice(0, 34);

export const ibanGrouped = (raw) => (ibanCompact(raw).match(/.{1,4}/g) || []).join(" ");

/** ISO 13616 (mod 97): anche qui il form avvisa, non blocca. */
export function isValidIban(raw) {
  const c = ibanCompact(raw);
  if (c.length < 15 || !/^[A-Z]{2}\d{2}/.test(c)) return false;
  const rearranged = c.slice(4) + c.slice(0, 4);
  let remainder = 0;
  for (const ch of rearranged) {
    const value = /\d/.test(ch) ? Number(ch) : ch.charCodeAt(0) - 55;
    for (const digit of String(value)) {
      remainder = (remainder * 10 + Number(digit)) % 97;
    }
  }
  return remainder === 1;
}

/** Palette fissa, uguale su iOS, Android e web. */
export const PAYMENT_CARD_DEFAULT_HEX = "#1C1C1E";
export const PAYMENT_CARD_PALETTE = [
  "#1C1C1E",
  "#0A3D91",
  "#1B7F5A",
  "#8E1B3A",
  "#B8860B",
  "#6E6E73",
  "#5856D6",
  "#D2462E",
];
