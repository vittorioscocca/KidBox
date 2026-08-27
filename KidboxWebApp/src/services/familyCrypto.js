/**
 * Cifratura AES-GCM condivisa da documenti e foto.
 *
 * Formato "combined" di CryptoKit: nonce(12) ‖ ciphertext ‖ tag(16). WebCrypto
 * vuole invece il nonce separato e restituisce ciphertext‖tag, quindi la
 * conversione sta qui una volta sola.
 */
const NONCE_BYTES = 12;

export async function encryptBytes(bytes, key) {
  const nonce = crypto.getRandomValues(new Uint8Array(NONCE_BYTES));
  const sealed = new Uint8Array(
    await crypto.subtle.encrypt({ name: "AES-GCM", iv: nonce }, key, bytes)
  );
  const combined = new Uint8Array(nonce.length + sealed.length);
  combined.set(nonce, 0);
  combined.set(sealed, nonce.length);
  return combined;
}

export async function decryptBytes(combined, key) {
  const data = new Uint8Array(combined);
  const nonce = data.slice(0, NONCE_BYTES);
  const payload = data.slice(NONCE_BYTES);
  return new Uint8Array(
    await crypto.subtle.decrypt({ name: "AES-GCM", iv: nonce }, key, payload)
  );
}

/** Riconosce i formati noti: serve a distinguere un blob in chiaro da uno cifrato. */
export function looksLikePlainFile(bytes) {
  if (bytes.length < 4) return false;
  const [a, b, c, d] = bytes;
  if (a === 0x25 && b === 0x50 && c === 0x44 && d === 0x46) return true; // %PDF
  if (a === 0x50 && b === 0x4b && c === 0x03 && d === 0x04) return true; // ZIP/office
  if (a === 0xff && b === 0xd8 && c === 0xff) return true; // JPEG
  if (a === 0x89 && b === 0x50 && c === 0x4e && d === 0x47) return true; // PNG
  return false;
}
