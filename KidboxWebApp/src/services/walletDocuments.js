/**
 * Documenti del Wallet — tessera sanitaria, carta d'identità, passaporto, patente.
 *
 * Non hanno una collezione propria: sono normali documenti di famiglia con i
 * metadati codificati nel campo `notes`, nella forma
 * `kb_wallet_doc:<kind>|enc=<base64 AES-GCM>`. Solo il `kind` resta in chiaro —
 * serve a filtrare e a scegliere l'icona senza decifrare — mentre codice
 * fiscale, intestatario, numero e date stanno nel blob cifrato con la chiave di
 * famiglia, la stessa che protegge il file.
 *
 * Qui si leggono e basta: la creazione resta ai client nativi, che sono quelli
 * che scansionano il documento. Porting del parser di `WalletDocumentMetadata`
 * (Android) e `KBWalletDocumentMetadata` (iOS) — stesso formato sul filo.
 */
import { onSnapshot, query, where } from "firebase/firestore";
import { documentsCol } from "./documents";
import { loadFamilyKey } from "./familyKey";
import { decryptBytes } from "./familyCrypto";

export const NOTES_PREFIX = "kb_wallet_doc:";

export const DOCUMENT_KINDS = [
  { raw: "tesseraSanitaria", it: "Tessera Sanitaria", en: "Health card", emoji: "🩺", color: "#2E86FF" },
  { raw: "cartaIdentita", it: "Carta d'identità (cartacea)", en: "ID card (paper)", emoji: "🪪", color: "#27AE60" },
  { raw: "cie", it: "CIE (Carta d'identità elettronica)", en: "Electronic ID card", emoji: "💳", color: "#0A84FF" },
  { raw: "passaporto", it: "Passaporto", en: "Passport", emoji: "📕", color: "#8E44AD" },
  { raw: "codiceFiscale", it: "Codice Fiscale", en: "Tax code", emoji: "🧾", color: "#B4661E" },
  { raw: "patente", it: "Patente", en: "Driving licence", emoji: "🚗", color: "#E0509A" },
  { raw: "altro", it: "Documento", en: "Document", emoji: "📄", color: "#5E5CE6" },
];

export const kindInfo = (raw) =>
  DOCUMENT_KINDS.find((k) => k.raw === raw) || DOCUMENT_KINDS[DOCUMENT_KINDS.length - 1];

const dec = new TextDecoder();

function b64ToBytes(b64) {
  const bin = atob(b64);
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i += 1) out[i] = bin.charCodeAt(i);
  return out;
}

/** Le date viaggiano in ISO `yyyy-MM-dd`. */
const parseDate = (raw) => (/^\d{4}-\d{2}-\d{2}$/.test(raw || "") ? raw : null);

function parseCategories(raw) {
  return (raw || "")
    .split(";")
    .map((entry) => {
      const [code, issue, expiry] = entry.split("~");
      if (!code) return null;
      return { code, issueDate: parseDate(issue), expiryDate: parseDate(expiry) };
    })
    .filter(Boolean);
}

function applyFields(payload, base) {
  const out = { ...base };
  for (const segment of (payload || "").split("|")) {
    const idx = segment.indexOf("=");
    if (idx <= 0) continue;
    const key = segment.slice(0, idx);
    const value = segment.slice(idx + 1);
    switch (key) {
      case "cf": out.codiceFiscale = value; break;
      case "holder": out.holderName = value; break;
      case "birth": out.birthInfo = value; break;
      case "docnum": out.documentNumber = value; break;
      case "issue": out.issueDate = parseDate(value); break;
      case "expiry": out.expiryDate = parseDate(value); break;
      case "cats": out.patenteCategories = parseCategories(value); break;
      case "notify": out.notifyBeforeExpiry = value === "1"; break;
      default: break;
    }
  }
  return out;
}

/**
 * Decodifica i metadati. Se la chiave non è disponibile o il blob è illeggibile
 * restituisce comunque il `kind`: meglio una riga con l'icona giusta e i campi
 * vuoti che un documento che sparisce dall'elenco.
 */
export async function parseWalletMetadata(notes, key) {
  if (!notes || !notes.startsWith(NOTES_PREFIX)) return null;
  const segments = notes.split("|");
  const rawKind = segments[0].slice(NOTES_PREFIX.length);
  if (!DOCUMENT_KINDS.some((k) => k.raw === rawKind)) return null;

  const base = {
    kind: rawKind,
    codiceFiscale: null,
    holderName: null,
    birthInfo: null,
    documentNumber: null,
    issueDate: null,
    expiryDate: null,
    patenteCategories: [],
    notifyBeforeExpiry: true,
  };

  const rest = segments.slice(1);
  const encSegment = rest.find((s) => s.startsWith("enc="));
  if (encSegment) {
    if (!key) return base;
    try {
      const plain = dec.decode(await decryptBytes(b64ToBytes(encSegment.slice(4)), key));
      return applyFields(plain, base);
    } catch {
      return base;
    }
  }

  // Vecchio formato: payload in chiaro subito dopo il kind.
  return applyFields(rest.join("|"), base);
}

/**
 * La scadenza che conta per l'avviso: per la patente è la più vicina fra le
 * categorie, come `effectiveExpiryDate` sugli altri client.
 */
export function effectiveExpiry(meta) {
  if (meta.kind === "patente") {
    const dates = meta.patenteCategories.map((c) => c.expiryDate).filter(Boolean).sort();
    return dates[0] || null;
  }
  return meta.expiryDate;
}

/** Ascolta i documenti di famiglia e tiene solo quelli del Wallet, già decodificati. */
export function listenWalletDocuments({ familyId, userId, onChange, onError }) {
  let cancelled = false;
  const q = query(documentsCol(familyId), where("isDeleted", "==", false));

  const unsub = onSnapshot(
    q,
    async (snap) => {
      try {
        // Il filtro sul prefisso si fa qui e non nella query: `notes` contiene
        // anche altri tag (es. "treatment:{id}") e Firestore non sa cercare
        // per prefisso senza un indice dedicato.
        const candidates = snap.docs.filter((d) =>
          (d.data().notes || "").startsWith(NOTES_PREFIX)
        );
        let key = null;
        if (candidates.length > 0) {
          key = await loadFamilyKey({ familyId, userId }).catch(() => null);
        }
        const items = await Promise.all(
          candidates.map(async (d) => {
            const data = d.data();
            return {
              // Il documento passa intero: `fetchDocumentBlob` vuole
              // `downloadURL`, `mimeType`, `storagePath` e `notes`, e sceglierne
              // a mano qualcuno significa scoprire quale manca solo al primo
              // tentativo di apertura.
              ...data,
              id: d.id,
              title: data.title || "",
              updatedAt: data.updatedAt?.toMillis?.() || null,
              meta: await parseWalletMetadata(data.notes, key),
            };
          })
        );
        if (!cancelled) onChange(items.filter((i) => i.meta));
      } catch (err) {
        if (!cancelled) onError?.(err);
      }
    },
    (err) => onError?.(err)
  );

  return () => {
    cancelled = true;
    unsub();
  };
}
