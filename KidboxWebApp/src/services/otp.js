/**
 * Codici TOTP (RFC 6238) per le voci che hanno un secondo fattore, allineato a
 * `OTPService.swift`. Il segreto sta nel campo cifrato `otpConfigCipherB64`,
 * salvato come URI `otpauth://` oppure come segreto base32 nudo.
 */
const B32 = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567";

function base32Decode(input) {
  const clean = (input || "").toUpperCase().replace(/=+$/, "").replace(/\s/g, "");
  let bits = 0;
  let value = 0;
  const out = [];
  for (const ch of clean) {
    const idx = B32.indexOf(ch);
    if (idx < 0) continue;
    value = (value << 5) | idx;
    bits += 5;
    if (bits >= 8) {
      bits -= 8;
      out.push((value >>> bits) & 0xff);
    }
  }
  return new Uint8Array(out);
}

/** Accetta sia `otpauth://totp/...?secret=XXX&digits=6&period=30` sia il solo segreto. */
export function parseOtpConfig(raw) {
  const text = (raw || "").trim();
  if (!text) return null;
  if (!text.toLowerCase().startsWith("otpauth://")) {
    return { secret: text, digits: 6, period: 30, algorithm: "SHA-1", label: null };
  }
  try {
    const url = new URL(text);
    const params = url.searchParams;
    const secret = params.get("secret");
    if (!secret) return null;
    return {
      secret,
      digits: Number(params.get("digits")) || 6,
      period: Number(params.get("period")) || 30,
      algorithm: (params.get("algorithm") || "SHA1").toUpperCase().replace("SHA", "SHA-"),
      label: decodeURIComponent(url.pathname.replace(/^\//, "")) || null,
    };
  } catch {
    return null;
  }
}

/** Codice corrente e secondi che mancano al prossimo. */
export async function totp(config, now = Date.now()) {
  if (!config?.secret) return null;
  const key = base32Decode(config.secret);
  if (key.length === 0) return null;

  const period = config.period || 30;
  const counter = Math.floor(now / 1000 / period);

  const buf = new ArrayBuffer(8);
  const view = new DataView(buf);
  view.setUint32(0, Math.floor(counter / 2 ** 32));
  view.setUint32(4, counter >>> 0);

  const hash = { "SHA-1": "SHA-1", "SHA-256": "SHA-256", "SHA-512": "SHA-512" }[config.algorithm] || "SHA-1";
  const cryptoKey = await crypto.subtle.importKey("raw", key, { name: "HMAC", hash }, false, ["sign"]);
  const mac = new Uint8Array(await crypto.subtle.sign("HMAC", cryptoKey, buf));

  const offset = mac[mac.length - 1] & 0x0f;
  const binary =
    ((mac[offset] & 0x7f) << 24) |
    ((mac[offset + 1] & 0xff) << 16) |
    ((mac[offset + 2] & 0xff) << 8) |
    (mac[offset + 3] & 0xff);

  const digits = config.digits || 6;
  const code = String(binary % 10 ** digits).padStart(digits, "0");
  const secondsLeft = period - Math.floor((now / 1000) % period);
  return { code, secondsLeft, period };
}
