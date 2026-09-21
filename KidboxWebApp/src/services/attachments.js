/**
 * Allegati delle schede (animali, casa, garage, salute).
 *
 * Non hanno una collezione propria: sono documenti di famiglia marcati nel
 * campo `notes` con un tag che li lega all'entità — `pet:{id}`,
 * `petEvent:{id}`, `homeItem:{id}`, `housePayment:{id}`, `vehicle:{id}`,
 * `vehicleEvent:{id}`, `visit:{id}`, `exam:{id}`, `treatment:{id}` — dentro
 * una cartella di Documenti (id deterministico, o per titolo nel caso di Salute).
 *
 * Il filtro sui prefissi sta qui e non nella query perché `notes` porta anche i
 * tag di altre sezioni (`treatment:{id}`, `kb_wallet_doc:…`) e Firestore non sa
 * cercare per prefisso senza un indice dedicato.
 */
import { doc, getDoc, getDocs, onSnapshot, query, where } from "firebase/firestore";
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

/**
 * Cartella dei referti di Salute: `Salute › Referti`, come `ensureHealthFolders`
 * su iOS e `HealthFolderResolver` su Android. A differenza delle altre sezioni
 * qui NON c'è un id deterministico: i client nativi le cercano per titolo
 * (radice «Salute», figlia «Referti») e le creano se mancano. Cercare per id
 * qui avrebbe generato una seconda coppia di cartelle accanto a quelle già
 * fatte dal telefono.
 */
export async function ensureHealthFolders({ familyId, userId }) {
  const snap = await getDocs(query(categoriesCol(familyId), where("isDeleted", "==", false)));
  const all = snap.docs.map((d) => ({ ...d.data(), id: d.id }));

  let salute = all.find((c) => !c.parentId && c.title === "Salute");
  if (!salute) {
    const id = await createFolder({ familyId, userId, title: "Salute" });
    salute = { id, title: "Salute" };
  }

  const saluteIds = new Set(all.filter((c) => c.title === "Salute").map((c) => c.id));
  saluteIds.add(salute.id);
  let referti = all.find((c) => c.title === "Referti" && saluteIds.has(c.parentId));
  if (!referti) {
    const id = await createFolder({ familyId, userId, title: "Referti", parentId: salute.id });
    referti = { id, title: "Referti" };
  }

  return { salute, referti };
}
