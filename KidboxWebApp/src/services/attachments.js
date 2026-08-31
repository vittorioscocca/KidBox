/**
 * Allegati delle schede (animali, casa, garage).
 *
 * Non hanno una collezione propria: sono documenti di famiglia marcati nel
 * campo `notes` con un tag che li lega all'entità — `pet:{id}`,
 * `petEvent:{id}`, `homeItem:{id}`, `housePayment:{id}`, `vehicle:{id}`,
 * `vehicleEvent:{id}` — dentro una cartella di Documenti con id deterministico.
 *
 * Il filtro sui prefissi sta qui e non nella query perché `notes` porta anche i
 * tag di altre sezioni (`treatment:{id}`, `kb_wallet_doc:…`) e Firestore non sa
 * cercare per prefisso senza un indice dedicato.
 */
import { doc, getDoc, onSnapshot, query, where } from "firebase/firestore";
import { categoriesCol, createFolder, documentsCol } from "./documents";

/**
 * Ascolta i documenti marcati con uno dei prefissi indicati e li raggruppa per
 * tag. `prefixes` è esplicito di proposito: la prima versione di questa
 * funzione era scritta per gli animali e teneva solo `pet:` — riusarla altrove
 * faceva sparire in silenzio gli allegati di casa e garage.
 */
export function listenTaggedDocuments({ familyId, prefixes, onChange, onError }) {
  return onSnapshot(
    query(documentsCol(familyId), where("isDeleted", "==", false)),
    (snap) => {
      const byTag = new Map();
      for (const d of snap.docs) {
        const data = d.data();
        const tag = data.notes || "";
        if (!prefixes.some((p) => tag.startsWith(p))) continue;
        byTag.set(tag, [...(byTag.get(tag) || []), { ...data, id: d.id }]);
      }
      onChange(byTag);
    },
    (err) => onError?.(err)
  );
}

/**
 * Crea la cartella di sezione se manca, con l'id deterministico dei client
 * nativi: due client che partono insieme scrivono lo stesso documento invece di
 * creare due cartelle gemelle.
 */
export async function ensureFolder({ familyId, userId, id, title }) {
  const snap = await getDoc(doc(categoriesCol(familyId), id));
  if (!snap.exists()) {
    await createFolder({ familyId, userId, title, id });
  }
  return id;
}
