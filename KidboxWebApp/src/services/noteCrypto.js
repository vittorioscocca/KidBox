/**
 * Cifratura dei campi nota, porting di NoteCryptoService (iOS).
 *
 * Formato sul filo: base64 della rappresentazione "combined" di CryptoKit,
 * cioè nonce(12) ‖ ciphertext ‖ tag(16). WebCrypto invece restituisce
 * ciphertext‖tag e vuole il nonce a parte: la conversione avviene qui.
 */
const NONCE_BYTES = 12;

const encoder = new TextEncoder();
const decoder = new TextDecoder();

function bytesToB64(bytes) {
  let bin = "";
  bytes.forEach((b) => {
    bin += String.fromCharCode(b);
  });
  return btoa(bin);
}

function b64ToBytes(b64) {
  const bin = atob(b64);
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i += 1) out[i] = bin.charCodeAt(i);
  return out;
}

export async function encryptString(plaintext, familyKey) {
  const nonce = crypto.getRandomValues(new Uint8Array(NONCE_BYTES));
  const sealed = new Uint8Array(
    await crypto.subtle.encrypt(
      { name: "AES-GCM", iv: nonce },
      familyKey,
      encoder.encode(plaintext ?? "")
    )
  );
  const combined = new Uint8Array(nonce.length + sealed.length);
  combined.set(nonce, 0);
  combined.set(sealed, nonce.length);
  return bytesToB64(combined);
}

export async function decryptString(combinedB64, familyKey) {
  if (!combinedB64) return "";
  const combined = b64ToBytes(combinedB64);
  const nonce = combined.slice(0, NONCE_BYTES);
  const payload = combined.slice(NONCE_BYTES);
  const plain = await crypto.subtle.decrypt(
    { name: "AES-GCM", iv: nonce },
    familyKey,
    payload
  );
  return decoder.decode(plain);
}

/**
 * Legge un campo che può essere cifrato (`*Enc`) o legacy in chiaro: le note
 * create prima dell'introduzione della cifratura hanno ancora `title`/`body`.
 */
export async function readField(encValue, plainValue, familyKey) {
  if (encValue && familyKey) {
    try {
      return await decryptString(encValue, familyKey);
    } catch {
      return plainValue ?? "";
    }
  }
  return plainValue ?? "";
}
