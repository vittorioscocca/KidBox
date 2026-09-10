/**
 * Lista di destinazione per un to-do creato senza sceglierne una
 * (assistente AI, "salva come to-do" dalla chat).
 *
 * Prima questi flussi scrivevano `listId: ""`, e il to-do nasceva **orfano**:
 * esiste su Firestore, viene contato nei riepiloghi e il motore promemoria lo
 * notifica, ma non compare in nessuna schermata — iOS e Android mostrano i
 * to-do dentro le liste, e una lista vuota non è nessuna lista. Su Android
 * finiva anche per far girare a vuoto il deep link della notifica, che la lista
 * la cerca proprio dal `listId`.
 *
 * Il criterio è quello di iOS (`defaultTodoTarget` in `PlanningAIActionBlock`):
 * se il chiamante non indica una lista si prende la prima disponibile. In più,
 * qui, se di liste non ce n'è nessuna se ne crea una: iOS in quel caso lascia
 * `listId` nullo, ma è esattamente il caso che genera l'orfano, e una lista in
 * più è più onesta di un to-do che l'utente non vedrà mai.
 */
import { getDocs, query, where, doc, serverTimestamp, setDoc } from "firebase/firestore";
import { todoListsCol } from "../hooks/useTodoLists";

export async function resolveTodoListId({
  familyId,
  childId = "",
  uid,
  listId,
  defaultListName,
}) {
  const chosen = (listId || "").trim();
  if (chosen) return chosen;
  if (!familyId) return "";

  const snap = await getDocs(query(todoListsCol(familyId), where("isDeleted", "==", false)));
  // Ordine per nome e non quello di arrivo: la "prima lista" deve essere la
  // stessa a ogni chiamata, altrimenti due to-do aggiunti di fila dallo stesso
  // assistente finiscono in liste diverse.
  const existing = snap.docs
    .map((d) => ({ id: d.id, name: (d.data().name || "").toString() }))
    .sort((a, b) => a.name.localeCompare(b.name));
  if (existing.length > 0) return existing[0].id;

  const id = crypto.randomUUID();
  await setDoc(doc(todoListsCol(familyId), id), {
    childId: childId ?? "",
    name: defaultListName || "Generale",
    isDeleted: false,
    updatedBy: uid,
    updatedAt: serverTimestamp(),
  });
  return id;
}
