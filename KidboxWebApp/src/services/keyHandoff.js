/**
 * Passaggio della chiave col QR (piano v2, sezione 3.2): qui il lato di chi
 * RICEVE, cioè il browser con «Entra con il telefono».
 *
 * Il browser crea `keyHandoffs/{roomId}` con la pubblica di una coppia ECDH
 * P-256 effimera (la privata resta in memoria) e mostra il QR
 * `KBKEY1.{roomId}.{pub}`. L'app inquadra, usa la pubblica DEL QR (non quella
 * del documento: il server non può scambiarla), e deposita in `payload` la
 * chiave chiusa: AES-GCM con chiave HKDF-SHA256(ECDH, salt = roomId,
 * info = "kidbox-vault-v2:handoff"), AAD
 * "kidbox-vault-v2:handoff:{roomId}:{kind}:{familyId}". `kind` = "rk" (stesso
 * utente) o "familyKey" (da un familiare). iOS e Android usano le stesse
 * costanti. La stanza scade in 10 minuti e si cancella dopo l'uso.
 */
import { deleteDoc, doc, onSnapshot, serverTimestamp, setDoc, Timestamp } from "firebase/firestore";
import { db } from "../firebase";
import { vaultBytes } from "./familyKeyVault";

export const HANDOFF_PREFIX = "KBKEY1";
export const HANDOFF_INFO = "kidbox-vault-v2:handoff";
const enc = new TextEncoder();
const TTL_MS = 10 * 60 * 1000;

export const handoffAad = (roomId, kind, familyId) => `${HANDOFF_INFO}:${roomId}:${kind}:${familyId || ""}`;

/**
 * Apre una stanza e aspetta la consegna. `onPayload({ kind, familyId, bytes })`
 * arriva una volta sola con i 32 byte aperti; `onError(err)` se la busta non si
 * apre. Restituisce `{ qrText, expiresAt, close }`: `close` cancella la stanza.
 */
export async function openHandoffRoom({ uid, label, onPayload, onError }) {
  const roomId = vaultBytes.bytesToB64Url(crypto.getRandomValues(new Uint8Array(16)));
  const pair = await crypto.subtle.generateKey({ name: "ECDH", namedCurve: "P-256" }, false, ["deriveBits"]);
  const pub = vaultBytes.bytesToB64Url(new Uint8Array(await crypto.subtle.exportKey("raw", pair.publicKey)));
  const ref = doc(db, "keyHandoffs", roomId);
  const expiresAt = new Date(Date.now() + TTL_MS);
  await setDoc(ref, {
    uid,
    pub,
    ...(label ? { label: label.slice(0, 80) } : {}),
    createdAt: serverTimestamp(),
    expiresAt: Timestamp.fromDate(expiresAt),
  });

  let done = false;
  const close = async () => {
    unsub();
    try {
      await deleteDoc(ref);
    } catch {
      /* scade da sola */
    }
  };
  const unsub = onSnapshot(ref, async (snap) => {
    const p = snap.data()?.payload;
    if (!p || done) return;
    done = true;
    try {
      const epk = await crypto.subtle.importKey(
        "raw",
        vaultBytes.b64ToBytes(p.epk),
        { name: "ECDH", namedCurve: "P-256" },
        false,
        []
      );
      const shared = new Uint8Array(
        await crypto.subtle.deriveBits({ name: "ECDH", public: epk }, pair.privateKey, 256)
      );
      const key = await vaultBytes.hkdfAesKey(shared, enc.encode(roomId), HANDOFF_INFO, ["decrypt"]);
      shared.fill(0);
      const bytes = await vaultBytes.open(key, p, handoffAad(roomId, p.kind, p.familyId));
      if (bytes.length !== 32) throw new Error("lunghezza inattesa");
      await close();
      onPayload?.({ kind: p.kind, familyId: p.familyId || null, bytes });
    } catch (err) {
      await close();
      onError?.(err);
    }
  });

  return { qrText: `${HANDOFF_PREFIX}.${roomId}.${pub}`, expiresAt, close };
}
