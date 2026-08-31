/**
 * Spese salvate («scontrini»), allineato a `KBShoppingTrip` e
 * `SaveShoppingTripView` su iOS.
 *
 * Quando si archiviano i prodotti presi nascono **due** documenti tenuti insieme
 * da `linkedExpenseId`: lo scontrino in `shoppingTrips`, che conserva il
 * dettaglio dei prodotti, e la voce in `expenses`, che è quella che conta i
 * soldi nella sezione Spese. È la stessa divisione dei client nativi: se
 * l'importo c'è, la spesa di famiglia si alimenta da sola.
 *
 * I prodotti archiviati escono dalla lista con soft delete: lo scontrino li
 * conserva, la lista riparte pulita.
 */
import {
  collection,
  doc,
  onSnapshot,
  query,
  serverTimestamp,
  Timestamp,
  where,
  writeBatch,
} from "firebase/firestore";
import { db } from "../firebase";
import { categoryId as expenseCategoryId } from "../expenseCategories";
import { deleteLinkedExpense, syncLinkedExpense } from "./linkedExpense";

const tripsCol = (familyId) => collection(db, "families", familyId, "shoppingTrips");
const expensesCol = (familyId) => collection(db, "families", familyId, "expenses");
const groceriesCol = (familyId) => collection(db, "families", familyId, "groceries");

const millis = (ts) => (ts?.toMillis ? ts.toMillis() : null);

/** Le righe viaggiano come JSON nel campo `linesJson`, come su iOS. */
function parseLines(linesJson) {
  if (!linesJson) return [];
  try {
    const parsed = JSON.parse(linesJson);
    return Array.isArray(parsed)
      ? parsed.map((l) => ({ name: l.name || "", quantity: l.quantity ?? null }))
      : [];
  } catch {
    return [];
  }
}

export function listenShoppingTrips({ familyId, onChange, onError }) {
  return onSnapshot(
    query(tripsCol(familyId), where("isDeleted", "==", false)),
    (snap) => {
      onChange(
        snap.docs
          .map((d) => {
            const data = d.data();
            return {
              id: d.id,
              storeName: data.storeName || null,
              total: Number(data.total) || 0,
              date: millis(data.date),
              lines: parseLines(data.linesJson),
              notes: data.notes || null,
              linkedExpenseId: data.linkedExpenseId || null,
              createdBy: data.createdBy || null,
            };
          })
          .sort((a, b) => (b.date || 0) - (a.date || 0))
      );
    },
    (err) => onError?.(err)
  );
}

/**
 * Archivia i prodotti presi in uno scontrino e, se c'è un importo, crea la
 * spesa collegata.
 *
 * Tutto in un batch: se qualcosa fallisce non resta uno scontrino senza spesa
 * o una lista svuotata a metà.
 */
export async function saveShoppingTrip({
  familyId,
  userId,
  storeName,
  total,
  date,
  items,
}) {
  if (!items.length) return null;

  const store = (storeName || "").trim();
  const lines = items.map((i) => ({ name: i.name, quantity: i.quantity ?? null }));

  // L'elenco finisce anche nelle note della spesa: chi apre la sezione Spese
  // vede cosa c'era dentro senza tornare qui.
  const notes = lines
    .map((l) => ((l.quantity ?? 1) > 1 ? `${l.name} x${l.quantity}` : l.name))
    .join(", ");

  const tripId = crypto.randomUUID();
  const when = Timestamp.fromMillis(date || Date.now());
  const batch = writeBatch(db);

  // La spesa nasce solo se un importo c'è davvero: uno scontrino da zero euro
  // non deve inquinare i totali della famiglia.
  const hasAmount = typeof total === "number" && total > 0;
  const expenseId = hasAmount ? crypto.randomUUID() : null;

  if (hasAmount) {
    batch.set(doc(expensesCol(familyId), expenseId), {
      id: expenseId,
      familyId,
      title: store || "Spesa",
      amount: total,
      date: when,
      categoryId: expenseCategoryId(familyId, "spesa"),
      notes: notes || null,
      isDeleted: false,
      createdByUid: userId,
      createdAt: serverTimestamp(),
      updatedBy: userId,
      updatedAt: serverTimestamp(),
    });
  }

  batch.set(doc(tripsCol(familyId), tripId), {
    familyId,
    storeName: store || null,
    total: hasAmount ? total : 0,
    date: when,
    linesJson: JSON.stringify(lines),
    notes: notes || null,
    linkedExpenseId: expenseId,
    isDeleted: false,
    createdBy: userId,
    createdAt: serverTimestamp(),
    updatedBy: userId,
    updatedAt: serverTimestamp(),
  });

  for (const item of items) {
    batch.set(
      doc(groceriesCol(familyId), item.id),
      { isDeleted: true, updatedBy: userId, updatedAt: serverTimestamp() },
      { merge: true }
    );
  }

  await batch.commit();
  return tripId;
}

/**
 * Modifica negozio, totale o data di uno scontrino, tenendo allineata la spesa
 * collegata: sono due facce dello stesso fatto, e lasciarle divergere
 * significherebbe uno scontrino da 52 € accanto a una spesa da 45 €.
 *
 * Il totale governa l'esistenza della spesa: toglierlo la elimina, aggiungerlo
 * a uno scontrino che non ce l'aveva la crea.
 *
 * I prodotti non si toccano: sono l'archivio di cosa è stato preso, e
 * riscriverli a posteriori vorrebbe dire falsificare lo scontrino.
 */
export async function updateShoppingTrip({ familyId, userId, trip, storeName, total, date }) {
  const store = (storeName || "").trim();
  const when = date || trip.date || Date.now();
  const batch = writeBatch(db);

  const linkedExpenseId = syncLinkedExpense({
    batch,
    familyId,
    userId,
    linkedExpenseId: trip.linkedExpenseId,
    amount: total,
    title: store,
    fallbackTitle: "Spesa",
    date: when,
    notes: trip.notes,
    categorySlug: "spesa",
  });

  batch.set(
    doc(tripsCol(familyId), trip.id),
    {
      storeName: store || null,
      total: typeof total === "number" && total > 0 ? total : 0,
      date: Timestamp.fromMillis(when),
      linkedExpenseId,
      updatedBy: userId,
      updatedAt: serverTimestamp(),
    },
    { merge: true }
  );

  await batch.commit();
}

/**
 * Elimina lo scontrino e la spesa collegata: sono lo stesso fatto, e lasciare
 * nei totali una spesa senza più il suo dettaglio sarebbe una sorpresa.
 */
export async function deleteShoppingTrip({ familyId, userId, id, linkedExpenseId }) {
  const batch = writeBatch(db);
  batch.set(
    doc(tripsCol(familyId), id),
    { isDeleted: true, updatedBy: userId, updatedAt: serverTimestamp() },
    { merge: true }
  );
  deleteLinkedExpense({ batch, familyId, userId, linkedExpenseId });
  await batch.commit();
}
