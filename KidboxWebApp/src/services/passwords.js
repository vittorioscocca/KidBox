/**
 * Lettura e scrittura del modulo Password su Firestore, allineato a
 * `PasswordRemoteStore.swift`.
 *
 * Percorsi e nomi dei campi sono quelli del client iOS: `families/{id}/passwords`
 * e `families/{id}/passwordGroups`, campi cifrati in base64 con il suffisso
 * `CipherB64`. L'eliminazione è soft (`deletedAt`), come sugli altri client, così
 * il tombstone si propaga invece di far riapparire la voce al primo sync.
 */
import {
  collection,
  doc,
  getDoc,
  onSnapshot,
  query,
  serverTimestamp,
  setDoc,
  Timestamp,
  writeBatch,
} from "firebase/firestore";
import { db } from "../firebase";
import {
  decryptField,
  encryptField,
  isVisibleTo,
  normalizedVisibility,
  NotCreatorError,
  VISIBILITY_FAMILY,
} from "./passwordCrypto";

const SCHEMA_VERSION = 1;

const entriesCol = (familyId) => collection(db, "families", familyId, "passwords");
const groupsCol = (familyId) => collection(db, "families", familyId, "passwordGroups");

/* ── Gruppi seed ─────────────────────────────────────────────────────────── */

/**
 * Gli stessi sei gruppi di `PasswordGroupsService.seedDefinitions`, con gli
 * identici id deterministici: se li crea prima un client, gli altri li trovano
 * già lì invece di duplicarli.
 */
export const SEED_GROUPS = [
  { slug: "unassigned", it: "Senza gruppo", en: "Unassigned", icon: "tray", color: "#8E8E93", sortIndex: 0 },
  { slug: "work", it: "Lavoro", en: "Work", icon: "briefcase.fill", color: "#0A84FF", sortIndex: 1 },
  { slug: "personal", it: "Personale", en: "Personal", icon: "person.fill", color: "#34C759", sortIndex: 2 },
  { slug: "social", it: "Social", en: "Social", icon: "bubble.left.and.bubble.right.fill", color: "#FF9500", sortIndex: 3 },
  { slug: "finance", it: "Finanze", en: "Finance", icon: "creditcard.fill", color: "#5E5CE6", sortIndex: 4 },
  { slug: "family", it: "Famiglia", en: "Family", icon: "house.fill", color: "#FF2D55", sortIndex: 5 },
];

export const groupIdFor = (familyId, slug) => `kb.password.group.${familyId}.${slug}`;

export const isUnassignedGroup = (groupId, familyId) =>
  groupId === groupIdFor(familyId, "unassigned");

/**
 * Le icone sono nomi di SF Symbols: restano nel documento così com'è per non
 * rompere iOS e Android, e qui si traducono in emoji solo per mostrarle.
 */
const ICON_EMOJI = {
  tray: "📥",
  "briefcase.fill": "💼",
  "person.fill": "👤",
  "bubble.left.and.bubble.right.fill": "💬",
  "creditcard.fill": "💳",
  "house.fill": "🏠",
  "folder.fill": "📁",
  "star.fill": "⭐️",
  "lock.fill": "🔒",
  "gamecontroller.fill": "🎮",
  "cart.fill": "🛒",
  "airplane": "✈️",
};

export const emojiForIcon = (icon) => ICON_EMOJI[icon] || "📁";
export const AVAILABLE_ICONS = Object.keys(ICON_EMOJI);

/* ── Lettura ─────────────────────────────────────────────────────────────── */

const millis = (ts) => (ts?.toMillis ? ts.toMillis() : null);

function rawEntry(snap) {
  const d = snap.data();
  return {
    id: snap.id,
    createdBy: d.createdBy || "",
    visibility: normalizedVisibility(d.visibility),
    visibilityMemberIds: d.visibilityMemberIds || [],
    groupId: d.groupId || null,
    titleCipherB64: d.titleCipherB64 || null,
    usernameCipherB64: d.usernameCipherB64 || null,
    passwordCipherB64: d.passwordCipherB64 || null,
    websiteCipherB64: d.websiteCipherB64 || null,
    notesCipherB64: d.notesCipherB64 || null,
    otpConfigCipherB64: d.otpConfigCipherB64 || null,
    iconURL: d.iconURL || null,
    lastUsedAt: millis(d.lastUsedAt),
    passwordUpdatedAt: millis(d.passwordUpdatedAt),
    expiresAt: millis(d.expiresAt),
    pwnedCount: typeof d.pwnedCount === "number" ? d.pwnedCount : null,
    pwnedCheckedAt: millis(d.pwnedCheckedAt),
    createdAt: millis(d.createdAt),
    updatedAt: millis(d.updatedAt),
    deletedAt: millis(d.deletedAt),
    isFavorite: Boolean(d.isFavorite),
  };
}

function rawGroup(snap) {
  const d = snap.data();
  return {
    id: snap.id,
    createdBy: d.createdBy || "",
    visibility: normalizedVisibility(d.visibility),
    visibilityMemberIds: d.visibilityMemberIds || [],
    nameCipherB64: d.nameCipherB64 || null,
    icon: d.icon || "folder.fill",
    color: d.color || "#7C6FDE",
    isSystem: Boolean(d.isSystem),
    sortIndex: typeof d.sortIndex === "number" ? d.sortIndex : 0,
    createdAt: millis(d.createdAt),
    updatedAt: millis(d.updatedAt),
    deletedAt: millis(d.deletedAt),
  };
}

/**
 * Decifra i campi di una voce.
 *
 * Le voci private di altri membri arrivano comunque dal server — le regole
 * Firestore sono per famiglia — ma non sono decifrabili: invece di far fallire
 * tutta la lista vengono marcate `locked`, e la UI le nasconde.
 */
async function decryptEntry(raw, { familyId, userId }) {
  const ctx = {
    familyId,
    userId,
    visibility: raw.visibility,
    createdBy: raw.createdBy,
  };
  try {
    const [title, username, password, website, notes, otp] = await Promise.all([
      decryptField(raw.titleCipherB64, ctx),
      decryptField(raw.usernameCipherB64, ctx),
      decryptField(raw.passwordCipherB64, ctx),
      decryptField(raw.websiteCipherB64, ctx),
      decryptField(raw.notesCipherB64, ctx),
      decryptField(raw.otpConfigCipherB64, ctx),
    ]);
    return { ...raw, title: title || "", username, password: password || "", website, notes, otp, locked: false };
  } catch (err) {
    if (err instanceof NotCreatorError) return { ...raw, locked: true };
    // Chiave sbagliata o payload corrotto: la voce esiste ma non si può leggere.
    return { ...raw, locked: true, undecryptable: true };
  }
}

/** Ascolta voci e gruppi. Restituisce la funzione per smettere. */
export function listenPasswords({ familyId, userId, onChange, onError }) {
  let entriesRaw = null;
  let groupsRaw = null;
  let cancelled = false;

  const emit = async () => {
    if (entriesRaw === null || groupsRaw === null) return;
    try {
      const entries = await Promise.all(
        entriesRaw.map((raw) => decryptEntry(raw, { familyId, userId }))
      );
      const groups = await Promise.all(
        groupsRaw.map(async (raw) => {
          const ctx = { familyId, userId, visibility: raw.visibility, createdBy: raw.createdBy };
          let name = "";
          try {
            name = (await decryptField(raw.nameCipherB64, ctx)) || "";
          } catch {
            name = "";
          }
          return { ...raw, name };
        })
      );
      if (cancelled) return;
      onChange({
        entries: entries.filter((e) => !e.locked && isVisibleTo(e, userId)),
        groups: groups.filter((g) => isVisibleTo(g, userId)),
      });
    } catch (err) {
      if (!cancelled) onError?.(err);
    }
  };

  const stopEntries = onSnapshot(
    query(entriesCol(familyId)),
    (snap) => {
      entriesRaw = snap.docs.map(rawEntry).filter((e) => !e.deletedAt);
      emit();
    },
    (err) => onError?.(err)
  );

  const stopGroups = onSnapshot(
    query(groupsCol(familyId)),
    (snap) => {
      groupsRaw = snap.docs.map(rawGroup).filter((g) => !g.deletedAt);
      emit();
    },
    (err) => onError?.(err)
  );

  return () => {
    cancelled = true;
    stopEntries();
    stopGroups();
  };
}

/* ── Scrittura ───────────────────────────────────────────────────────────── */

const tsOrNull = (millisValue) => (millisValue ? Timestamp.fromMillis(millisValue) : null);

/**
 * Crea o aggiorna una voce.
 *
 * `createdBy` non si tocca mai in aggiornamento: è il salt della sotto-chiave
 * delle voci private, cambiarlo renderebbe illeggibile quello che c'è già.
 */
export async function savePassword({ familyId, userId, entry }) {
  const id = entry.id || crypto.randomUUID();
  const createdBy = entry.createdBy || userId;
  const visibility = normalizedVisibility(entry.visibility);
  const ctx = { familyId, userId, visibility, createdBy };

  const data = {
    schemaVersion: SCHEMA_VERSION,
    familyId,
    createdBy,
    visibility,
    visibilityMemberIds: visibility === "members" ? entry.visibilityMemberIds || [] : [],
    titleCipherB64: await encryptField(entry.title || "", ctx),
    passwordCipherB64: await encryptField(entry.password || "", ctx),
    passwordUpdatedAt: tsOrNull(entry.passwordUpdatedAt) || serverTimestamp(),
    createdAt: tsOrNull(entry.createdAt) || serverTimestamp(),
    updatedAt: serverTimestamp(),
    updatedBy: userId,
    isFavorite: Boolean(entry.isFavorite),
    groupId: entry.groupId || null,
    usernameCipherB64: entry.username ? await encryptField(entry.username, ctx) : null,
    websiteCipherB64: entry.website ? await encryptField(entry.website, ctx) : null,
    notesCipherB64: entry.notes ? await encryptField(entry.notes, ctx) : null,
    otpConfigCipherB64: entry.otp ? await encryptField(entry.otp, ctx) : null,
    expiresAt: tsOrNull(entry.expiresAt),
    lastUsedAt: tsOrNull(entry.lastUsedAt),
    pwnedCount: typeof entry.pwnedCount === "number" ? entry.pwnedCount : null,
    pwnedCheckedAt: tsOrNull(entry.pwnedCheckedAt),
  };

  await setDoc(doc(entriesCol(familyId), id), data, { merge: true });
  return id;
}

/** Aggiorna solo alcuni campi in chiaro (preferito, ultimo uso, esito HIBP). */
export async function patchPassword({ familyId, userId, id, fields }) {
  await setDoc(
    doc(entriesCol(familyId), id),
    { ...fields, updatedAt: serverTimestamp(), updatedBy: userId },
    { merge: true }
  );
}

/** Soft delete: il tombstone si propaga agli altri client. */
export async function deletePassword({ familyId, userId, id }) {
  await setDoc(
    doc(entriesCol(familyId), id),
    { deletedAt: serverTimestamp(), updatedAt: serverTimestamp(), updatedBy: userId },
    { merge: true }
  );
}

export async function deletePasswords({ familyId, userId, ids }) {
  const batch = writeBatch(db);
  ids.forEach((id) => {
    batch.set(
      doc(entriesCol(familyId), id),
      { deletedAt: serverTimestamp(), updatedAt: serverTimestamp(), updatedBy: userId },
      { merge: true }
    );
  });
  await batch.commit();
}

export async function saveGroup({ familyId, userId, group }) {
  const id = group.id || crypto.randomUUID();
  const createdBy = group.createdBy || userId;
  const visibility = normalizedVisibility(group.visibility || VISIBILITY_FAMILY);
  const ctx = { familyId, userId, visibility, createdBy };

  await setDoc(
    doc(groupsCol(familyId), id),
    {
      schemaVersion: SCHEMA_VERSION,
      familyId,
      createdBy,
      visibility,
      visibilityMemberIds: visibility === "members" ? group.visibilityMemberIds || [] : [],
      nameCipherB64: await encryptField(group.name || "", ctx),
      icon: group.icon || "folder.fill",
      color: group.color || "#7C6FDE",
      isSystem: Boolean(group.isSystem),
      sortIndex: group.sortIndex ?? 0,
      createdAt: tsOrNull(group.createdAt) || serverTimestamp(),
      updatedAt: serverTimestamp(),
      updatedBy: userId,
    },
    { merge: true }
  );
  return id;
}

export async function deleteGroup({ familyId, userId, id }) {
  await setDoc(
    doc(groupsCol(familyId), id),
    { deletedAt: serverTimestamp(), updatedAt: serverTimestamp(), updatedBy: userId },
    { merge: true }
  );
}

/**
 * Crea i gruppi di sistema se mancano.
 *
 * Il controllo è sul documento, non su un flag locale: gli id sono deterministici,
 * quindi due client che partono insieme scrivono lo stesso documento invece di
 * creare due gruppi gemelli.
 */
export async function seedDefaultGroups({ familyId, userId, locale }) {
  const created = [];
  for (const seed of SEED_GROUPS) {
    const id = groupIdFor(familyId, seed.slug);
    // eslint-disable-next-line no-await-in-loop
    const snap = await getDoc(doc(groupsCol(familyId), id));
    if (snap.exists()) continue;
    // eslint-disable-next-line no-await-in-loop
    await saveGroup({
      familyId,
      userId,
      group: {
        id,
        name: locale === "en" ? seed.en : seed.it,
        icon: seed.icon,
        color: seed.color,
        visibility: VISIBILITY_FAMILY,
        createdBy: userId,
        isSystem: true,
        sortIndex: seed.sortIndex,
      },
    });
    created.push(id);
  }
  return created;
}
