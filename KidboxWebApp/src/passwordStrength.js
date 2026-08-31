/**
 * Robustezza di una password: entropia stimata più penalità sui pattern comuni,
 * in cinque livelli. Porting fedele di `PasswordStrength.swift` — stessi pesi,
 * stesse soglie, stesse penalità — così la stessa password non risulta "Forte"
 * su iPhone e "Discreta" sul web.
 */

export const LEVELS = ["veryWeak", "weak", "fair", "strong", "veryStrong"];

/** Colori della barra, gli stessi di `barColor(colorScheme:)`. */
export const LEVEL_COLOR = {
  veryWeak: "#d93838",
  weak: "#f2731f",
  fair: "#c08c0d",
  strong: "#34c759",
  veryStrong: "#e8833a",
};

const COMMON = new Set([
  "password", "password1", "123456", "12345678", "123456789", "qwerty", "abc123",
  "letmein", "welcome", "monkey", "dragon", "111111", "sunshine", "princess",
  "football", "iloveyou", "admin", "login", "master", "passw0rd", "654321",
]);

const KEYBOARD_ROWS = ["qwertyuiop", "asdfghjkl", "zxcvbnm", "1234567890"];

const isDigit = (c) => c >= "0" && c <= "9";
const isLetter = (c) => /\p{L}/u.test(c);

function shannonPerChar(s) {
  if (!s) return 0;
  const counts = new Map();
  for (const ch of s) counts.set(ch, (counts.get(ch) || 0) + 1);
  const n = s.length;
  let h = 0;
  for (const c of counts.values()) {
    const p = c / n;
    h -= p * Math.log2(p);
  }
  return h;
}

function repeatingRunPenalty(s) {
  if (s.length <= 1) return 1;
  let maxRun = 1;
  let run = 1;
  for (let i = 1; i < s.length; i += 1) {
    if (s[i] === s[i - 1]) {
      run += 1;
      maxRun = Math.max(maxRun, run);
    } else run = 1;
  }
  if (maxRun >= s.length && s.length >= 4) return 0.25;
  if (maxRun >= 4) return 0.65;
  if (maxRun === 3) return 0.85;
  return 1;
}

const ALPHABET = "abcdefghijklmnopqrstuvwxyz";

function containsSequence(s, minLen, ascending) {
  let run = 1;
  for (let i = 1; i < s.length; i += 1) {
    const a = ALPHABET.indexOf(s[i - 1]);
    const b = ALPHABET.indexOf(s[i]);
    if (a < 0 || b < 0) {
      run = 1;
      continue;
    }
    if (ascending ? b === a + 1 : b === a - 1) {
      run += 1;
      if (run >= minLen) return true;
    } else run = 1;
  }
  return false;
}

function containsDigitRun(s, len) {
  const arr = [...s].filter(isDigit).map(Number);
  if (arr.length < len) return false;
  let run = 1;
  for (let i = 1; i < arr.length; i += 1) {
    if (arr[i] === arr[i - 1] + 1) {
      run += 1;
      if (run >= len) return true;
    } else run = 1;
  }
  return false;
}

function sequentialPenalty(s) {
  const lower = s.toLowerCase();
  if (containsSequence(lower, 4, true)) return 0.72;
  if (containsSequence(lower, 4, false)) return 0.72;
  if (containsDigitRun(s, 4)) return 0.75;
  return 1;
}

function containsKeyboardRun(s, row, minLen) {
  const chars = [...s.toLowerCase()];
  for (let i = 0; i < chars.length; i += 1) {
    const pos = row.indexOf(chars[i]);
    if (pos < 0) continue;
    let length = 1;
    let ni = i + 1;
    let expected = pos + 1;
    while (ni < chars.length && expected < row.length) {
      if (chars[ni] !== row[expected]) break;
      length += 1;
      ni += 1;
      expected += 1;
    }
    if (length >= minLen) return true;
  }
  return false;
}

function keyboardPenalty(s) {
  const t = s.toLowerCase();
  for (const row of KEYBOARD_ROWS) if (containsKeyboardRun(t, row, 4)) return 0.7;
  return 1;
}

function commonPasswordPenalty(s) {
  const t = s.toLowerCase();
  if (COMMON.has(t)) return 0.15;
  for (const w of COMMON) if (w.length >= 4 && t.includes(w)) return 0.45;
  return 1;
}

/** @returns {{level: string, fillFraction: number, estimatedBits: number}} */
export function evaluate(password) {
  const s = password || "";
  if (!s) return { level: "veryWeak", fillFraction: 0, estimatedBits: 0 };

  const L = s.length;
  const chars = [...s];
  const hasLower = chars.some((c) => c !== c.toUpperCase() && c === c.toLowerCase());
  const hasUpper = chars.some((c) => c !== c.toLowerCase() && c === c.toUpperCase());
  const hasDigit = chars.some(isDigit);
  const hasSymbol = chars.some((c) => !isLetter(c) && !isDigit(c));

  let pool = 0;
  if (hasLower) pool += 26;
  if (hasUpper) pool += 26;
  if (hasDigit) pool += 10;
  if (hasSymbol) pool += 33;
  pool = Math.max(pool, 2);

  const uniformBits = L * Math.log2(pool);
  const shannonTotal = L * shannonPerChar(s);
  let estimated = 0.55 * uniformBits + 0.45 * shannonTotal;

  let penalty = 1;
  penalty *= repeatingRunPenalty(s);
  penalty *= sequentialPenalty(s);
  penalty *= keyboardPenalty(s);
  penalty *= commonPasswordPenalty(s);
  if (L < 8) penalty *= 0.45;
  else if (L < 12) penalty *= 0.82;

  estimated = Math.max(0, Math.min(estimated * penalty, 160));

  let level;
  if (estimated < 18) level = "veryWeak";
  else if (estimated < 32) level = "weak";
  else if (estimated < 48) level = "fair";
  else if (estimated < 64) level = "strong";
  else level = "veryStrong";

  return { level, fillFraction: Math.min(1, estimated / 80), estimatedBits: estimated };
}

/** «Debole» o peggio: la soglia che iOS usa per il report Sicurezza. */
export function isWeak(level) {
  return LEVELS.indexOf(level) <= LEVELS.indexOf("weak");
}
