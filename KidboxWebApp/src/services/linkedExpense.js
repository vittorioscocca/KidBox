/**
 * Spesa collegata a una scheda (scontrino, scadenza di casa, visita…).
 *
 * È l'equivalente web di `KBLinkedExpense.sync` su iOS e di
 * `ExpenseRepository.syncLinkedExpense` su Android, e vale la stessa regola:
 *
 * - importo > 0 e nessuna spesa collegata → la crea;
 * - importo > 0 e spesa già collegata     → la aggiorna;
 * - importo tolto                          → la spesa collegata sparisce.
 *
 * Sta in un file suo perché la regola è una sola: averla in tre posti diversi
 * significa che prima o poi due divergono.
 */
import { collection, doc, serverTimestamp, Timestamp } from "firebase/firestore";
import { db } from "../firebase";
import { categoryId as expenseCategoryId } from "../expenseCategories";

const expensesCol = (familyId) => collection(db, "families", familyId, "expenses");

/**
 * Accoda le scritture sulla spesa a un batch già aperto e restituisce l'id da
 * conservare in `linkedExpenseId` (o `null` se la spesa non deve esistere).
 *
 * Lavora su un batch invece di scrivere da sé perché chi la chiama deve poter
 * salvare scheda e spesa insieme: se una delle due fallisce non deve restare
 * l'altra a metà.
 */
export function syncLinkedExpense({
  batch,
  familyId,
  userId,
  linkedExpenseId,
  amount,
  title,
  fallbackTitle,
  date,
  notes,
  categorySlug,
}) {
  const hasAmount = typeof amount === "number" && amount > 0;

  if (!hasAmount) {
    if (linkedExpenseId) {
      batch.set(
        doc(expensesCol(familyId), linkedExpenseId),
        { isDeleted: true, updatedBy: userId, updatedAt: serverTimestamp() },
        { merge: true }
      );
    }
    return null;
  }

  const isNew = !linkedExpenseId;
  const id = linkedExpenseId || crypto.randomUUID();
  const effectiveTitle = (title || "").trim() || fallbackTitle;

  batch.set(
    doc(expensesCol(familyId), id),
    {
      id,
      familyId,
      title: effectiveTitle,
      amount,
      date: Timestamp.fromMillis(date || Date.now()),
      categoryId: expenseCategoryId(familyId, categorySlug),
      notes: notes || null,
      isDeleted: false,
      updatedBy: userId,
      updatedAt: serverTimestamp(),
      // Creatore e data di creazione restano a chi l'ha inserita: il merge non
      // li tocca, e su una spesa nuova li mette il ramo qui sotto.
      ...(isNew ? { createdByUid: userId, createdAt: serverTimestamp() } : {}),
    },
    { merge: true }
  );

  return id;
}

/** Elimina la spesa collegata, se c'è. Anche questa dentro un batch. */
export function deleteLinkedExpense({ batch, familyId, userId, linkedExpenseId }) {
  if (!linkedExpenseId) return;
  batch.set(
    doc(expensesCol(familyId), linkedExpenseId),
    { isDeleted: true, updatedBy: userId, updatedAt: serverTimestamp() },
    { merge: true }
  );
}
