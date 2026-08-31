/**
 * Casa: oggetti (elettrodomestici, impianti, contratti) e scadenze/pagamenti,
 * allineato a `HomeItemRemoteStore` e `HousePaymentRemoteStore` su iOS.
 *
 * Tutto in chiaro, eliminazione con `isDeleted: true`.
 *
 * I pagamenti hanno un `linkedExpenseId`: se c'è un importo, la scadenza
 * alimenta le spese di famiglia nella categoria «casa». La regola è quella
 * condivisa in `linkedExpense.js`, la stessa degli scontrini.
 *
 * Gli allegati sono documenti di famiglia marcati `homeItem:{id}` e
 * `housePayment:{id}`, come per gli animali.
 */
import {
  collection,
  doc,
  onSnapshot,
  query,
  serverTimestamp,
  setDoc,
  Timestamp,
  where,
  writeBatch,
} from "firebase/firestore";
import { db } from "../firebase";
import { deleteLinkedExpense, syncLinkedExpense } from "./linkedExpense";

const itemsCol = (familyId) => collection(db, "families", familyId, "homeItems");
const paymentsCol = (familyId) => collection(db, "families", familyId, "housePayments");

/* ── Categorie e tipi, come sui client nativi ────────────────────────────── */

export const ITEM_CATEGORIES = [
  { raw: "appliance", it: "Elettrodomestico", en: "Appliance", plural: "Elettrodomestici", pluralEn: "Appliances", emoji: "🧺" },
  { raw: "system", it: "Impianto", en: "System", plural: "Impianti", pluralEn: "Systems", emoji: "🔥" },
  { raw: "contract", it: "Contratto", en: "Contract", plural: "Contratti", pluralEn: "Contracts", emoji: "📄" },
  { raw: "other", it: "Altro", en: "Other", plural: "Altro", pluralEn: "Other", emoji: "🏡" },
];

export const itemCategory = (raw) =>
  ITEM_CATEGORIES.find((c) => c.raw === raw) || ITEM_CATEGORIES[ITEM_CATEGORIES.length - 1];

export const PAYMENT_TYPES = [
  { raw: "mutuo", it: "Mutuo", en: "Mortgage", emoji: "🏦" },
  { raw: "affitto", it: "Affitto", en: "Rent", emoji: "🔑" },
  { raw: "bolletta", it: "Bolletta", en: "Bill", emoji: "💡" },
  { raw: "tassa", it: "Tassa", en: "Tax", emoji: "🧾" },
  { raw: "altro", it: "Altro", en: "Other", emoji: "📌" },
];

export const paymentType = (raw) =>
  PAYMENT_TYPES.find((t) => t.raw === raw) || PAYMENT_TYPES[PAYMENT_TYPES.length - 1];

/**
 * I sottotipi: il `raw` è il valore SALVATO, condiviso con iOS e Android, e
 * resta in italiano minuscolo. Tradotta è solo l'etichetta.
 */
export const PAYMENT_SUBTYPES = {
  bolletta: [
    { raw: "luce", it: "Luce", en: "Electricity" },
    { raw: "gas", it: "Gas", en: "Gas" },
    { raw: "internet", it: "Internet", en: "Internet" },
    { raw: "telefono", it: "Telefono", en: "Phone" },
    { raw: "acqua", it: "Acqua", en: "Water" },
    { raw: "condominio", it: "Condominio", en: "Building fees" },
  ],
  tassa: [
    { raw: "IMU", it: "IMU", en: "IMU" },
    { raw: "TARI", it: "TARI", en: "TARI" },
    { raw: "dichiarazione redditi", it: "Dichiarazione redditi", en: "Tax return" },
    { raw: "bollo auto", it: "Bollo auto", en: "Car tax" },
    { raw: "altre", it: "Altre", en: "Other" },
  ],
  mutuo: [],
  affitto: [],
  altro: [],
};

export const homeItemTag = (id) => `homeItem:${id}`;
export const housePaymentTag = (id) => `housePayment:${id}`;
export const homeFolderId = (familyId) => `home-root-${familyId}`;

/* ── Lettura ─────────────────────────────────────────────────────────────── */

const millis = (ts) => (ts?.toMillis ? ts.toMillis() : null);

function readItem(snap) {
  const d = snap.data();
  return {
    id: snap.id,
    name: d.name || "",
    categoryRaw: d.categoryRaw || "other",
    brand: d.brand || null,
    model: d.model || null,
    serialNumber: d.serialNumber || null,
    purchaseDate: millis(d.purchaseDate),
    warrantyExpiryDate: millis(d.warrantyExpiryDate),
    nextServiceDate: millis(d.nextServiceDate),
    servicePeriodMonths: typeof d.servicePeriodMonths === "number" ? d.servicePeriodMonths : null,
    notes: d.notes || null,
    reminderEnabled: Boolean(d.reminderEnabled),
    updatedAt: millis(d.updatedAt),
  };
}

function readPayment(snap) {
  const d = snap.data();
  return {
    id: snap.id,
    name: d.name || "",
    typeRaw: d.typeRaw || "altro",
    subtypeRaw: d.subtypeRaw || null,
    importo: typeof d.importo === "number" ? d.importo : null,
    linkedExpenseId: d.linkedExpenseId || null,
    giornoDiScadenzaMensile:
      typeof d.giornoDiScadenzaMensile === "number" ? d.giornoDiScadenzaMensile : null,
    dataScadenza: millis(d.dataScadenza),
    dataScadenzaContratto: millis(d.dataScadenzaContratto),
    fornitore: d.fornitore || null,
    note: d.note || null,
    reminderOn: Boolean(d.reminderOn),
    updatedAt: millis(d.updatedAt),
  };
}

export function listenHome({ familyId, onChange, onError }) {
  let items = null;
  let payments = null;
  const emit = () => {
    if (items === null || payments === null) return;
    onChange({ items, payments });
  };

  const stopItems = onSnapshot(
    query(itemsCol(familyId), where("isDeleted", "==", false)),
    (snap) => {
      items = snap.docs.map(readItem).sort((a, b) => a.name.localeCompare(b.name));
      emit();
    },
    (err) => onError?.(err)
  );

  const stopPayments = onSnapshot(
    query(paymentsCol(familyId), where("isDeleted", "==", false)),
    (snap) => {
      payments = snap.docs.map(readPayment).sort((a, b) => a.name.localeCompare(b.name));
      emit();
    },
    (err) => onError?.(err)
  );

  return () => {
    stopItems();
    stopPayments();
  };
}

/* ── Scrittura ───────────────────────────────────────────────────────────── */

const tsOrNull = (v) => (v ? Timestamp.fromMillis(v) : null);

export async function saveHomeItem({ familyId, userId, item }) {
  const id = item.id || crypto.randomUUID();
  const data = {
    name: item.name || "",
    categoryRaw: item.categoryRaw || "other",
    brand: item.brand || null,
    model: item.model || null,
    serialNumber: item.serialNumber || null,
    purchaseDate: tsOrNull(item.purchaseDate),
    warrantyExpiryDate: tsOrNull(item.warrantyExpiryDate),
    nextServiceDate: tsOrNull(item.nextServiceDate),
    servicePeriodMonths: item.servicePeriodMonths ?? null,
    notes: item.notes || null,
    reminderEnabled: Boolean(item.reminderEnabled),
    isDeleted: false,
    updatedBy: userId,
    updatedAt: serverTimestamp(),
  };
  if (!item.id) {
    data.createdAt = serverTimestamp();
    data.createdBy = userId;
  }
  await setDoc(doc(itemsCol(familyId), id), data, { merge: true });
  return id;
}

export async function deleteHomeItem({ familyId, userId, id }) {
  await setDoc(
    doc(itemsCol(familyId), id),
    { isDeleted: true, updatedBy: userId, updatedAt: serverTimestamp() },
    { merge: true }
  );
}

/** Le note della spesa: fornitore e note della scadenza, come `notesFor` su iOS. */
function expenseNotesFor(payment) {
  return (
    [payment.fornitore, payment.note]
      .map((v) => (v || "").trim())
      .filter(Boolean)
      .join(" · ") || null
  );
}

/**
 * Salva una scadenza e tiene allineata la spesa collegata.
 *
 * La data della spesa è la scadenza vera se c'è: una bolletta datata deve
 * cadere nel mese in cui si paga, non in quello in cui la si registra.
 */
export async function saveHousePayment({ familyId, userId, payment }) {
  const id = payment.id || crypto.randomUUID();
  const batch = writeBatch(db);

  const linkedExpenseId = syncLinkedExpense({
    batch,
    familyId,
    userId,
    linkedExpenseId: payment.linkedExpenseId,
    amount: payment.importo,
    title: payment.name,
    fallbackTitle: "Scadenza casa",
    date: payment.dataScadenza || Date.now(),
    notes: expenseNotesFor(payment),
    categorySlug: "casa",
  });

  const data = {
    name: payment.name || "",
    typeRaw: payment.typeRaw || "altro",
    subtypeRaw: payment.subtypeRaw || null,
    importo: payment.importo ?? null,
    linkedExpenseId,
    giornoDiScadenzaMensile: payment.giornoDiScadenzaMensile ?? null,
    dataScadenza: tsOrNull(payment.dataScadenza),
    dataScadenzaContratto: tsOrNull(payment.dataScadenzaContratto),
    fornitore: payment.fornitore || null,
    note: payment.note || null,
    reminderOn: Boolean(payment.reminderOn),
    isDeleted: false,
    updatedBy: userId,
    updatedAt: serverTimestamp(),
  };
  if (!payment.id) {
    data.createdAt = serverTimestamp();
    data.createdBy = userId;
  }

  batch.set(doc(paymentsCol(familyId), id), data, { merge: true });
  await batch.commit();
  return id;
}

/** Elimina la scadenza e la spesa collegata: sono lo stesso fatto. */
export async function deleteHousePayment({ familyId, userId, id, linkedExpenseId }) {
  const batch = writeBatch(db);
  deleteLinkedExpense({ batch, familyId, userId, linkedExpenseId });
  batch.set(
    doc(paymentsCol(familyId), id),
    { isDeleted: true, updatedBy: userId, updatedAt: serverTimestamp() },
    { merge: true }
  );
  await batch.commit();
}
