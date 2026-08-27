import {
  GeoPoint,
  Timestamp,
  collection,
  deleteDoc,
  doc,
  onSnapshot,
  serverTimestamp,
  setDoc,
} from "firebase/firestore";
import { db } from "../firebase";

/**
 * Posizione di famiglia: porting di LocationRemoteStore (iOS).
 *
 * ⚠️ Lo stato della condivisione e le coordinate stanno su DUE documenti
 * distinti, e non è un dettaglio: la Cloud Function `notifyLocationSharingChanged`
 * osserva `locations/{uid}`. Scrivendoci anche le coordinate, ogni fix GPS
 * farebbe scattare quel trigger — sul progetto era arrivato a essere il 94% di
 * tutte le invocazioni. Le coordinate vanno quindi solo in `live/current`.
 */

export function locationsCol(familyId) {
  return collection(db, "families", familyId, "locations");
}

export function geofencesCol(familyId) {
  return collection(db, "families", familyId, "geofences");
}

function liveDoc(familyId, uid) {
  return doc(db, "families", familyId, "locations", uid, "live", "current");
}

/** @param mode "realtime" | "temporary" */
export async function startSharing({ familyId, uid, name, mode, expiresAt }) {
  const data = {
    isSharing: true,
    mode,
    name,
    startedAt: serverTimestamp(),
    lastUpdateAt: serverTimestamp(),
  };
  if (expiresAt) data.expiresAt = Timestamp.fromDate(expiresAt);
  await setDoc(doc(locationsCol(familyId), uid), data, { merge: true });
}

export async function stopSharing({ familyId, uid }) {
  await setDoc(
    doc(locationsCol(familyId), uid),
    { isSharing: false, lastUpdateAt: serverTimestamp() },
    { merge: true }
  );
}

/** Solo coordinate: mai sul documento di stato (vedi nota in testa al file). */
export async function updateCoordinates({ familyId, uid, lat, lon, accuracy }) {
  await setDoc(
    liveDoc(familyId, uid),
    { lat, lon, accuracy: accuracy ?? null, lastUpdateAt: serverTimestamp() },
    { merge: true }
  );
}

/**
 * Segue stato e coordinate di tutti i membri che condividono.
 * Emette solo chi ha entrambi: senza coordinate non c'è nulla da mostrare.
 */
export function listenSharedLocations({ familyId, onChange, onError }) {
  const statusByUid = new Map();
  const coordByUid = new Map();
  const coordUnsubs = new Map();

  const emit = () => {
    const users = [];
    statusByUid.forEach((status, uid) => {
      const coord = coordByUid.get(uid);
      if (coord) users.push({ id: uid, ...status, ...coord });
    });
    onChange(users);
  };

  const syncCoordListeners = () => {
    const wanted = new Set(statusByUid.keys());

    // Snapshot esplicito delle chiavi: si rimuove dalla stessa mappa che si sta
    // percorrendo.
    [...coordUnsubs.keys()].forEach((uid) => {
      if (!wanted.has(uid)) {
        coordUnsubs.get(uid)();
        coordUnsubs.delete(uid);
        coordByUid.delete(uid);
      }
    });

    wanted.forEach((uid) => {
      if (coordUnsubs.has(uid)) return;
      const unsub = onSnapshot(
        liveDoc(familyId, uid),
        (snap) => {
          const d = snap.data();
          if (d?.lat != null && d?.lon != null) {
            coordByUid.set(uid, {
              latitude: d.lat,
              longitude: d.lon,
              accuracy: d.accuracy ?? null,
              lastUpdateAt: d.lastUpdateAt ?? null,
            });
          } else {
            coordByUid.delete(uid);
          }
          emit();
        },
        onError
      );
      coordUnsubs.set(uid, unsub);
    });
  };

  const statusUnsub = onSnapshot(
    locationsCol(familyId),
    (snap) => {
      statusByUid.clear();
      snap.docs.forEach((d) => {
        const data = d.data();
        if (!data.isSharing) return;
        // Una condivisione a tempo scaduta non va mostrata: lo scheduler la
        // ripulisce ogni 5 minuti, nel frattempo la si ignora.
        const expires = data.expiresAt?.toDate?.();
        if (expires && expires < new Date()) return;
        statusByUid.set(d.id, {
          name: data.name ?? "",
          mode: data.mode ?? "realtime",
          expiresAt: expires ?? null,
          // Caricato da AvatarRemoteStore sui client nativi, sullo stesso
          // documento di stato: qui basta leggerlo.
          avatarURL: data.avatarURL ?? null,
        });
      });
      syncCoordListeners();
      emit();
    },
    onError
  );

  return () => {
    statusUnsub();
    coordUnsubs.forEach((unsub) => unsub());
    coordUnsubs.clear();
  };
}

/* ── Zone (geofence) ────────────────────────────────────────────────────── */

export function listenGeofences({ familyId, onChange, onError }) {
  return onSnapshot(
    geofencesCol(familyId),
    (snap) => onChange(snap.docs.map((d) => ({ id: d.id, ...d.data() }))),
    onError
  );
}

export async function saveGeofence({ familyId, uid, geofence }) {
  const id = geofence.id ?? crypto.randomUUID();
  const payload = {
    familyId,
    name: geofence.name,
    emoji: geofence.emoji ?? null,
    latitude: geofence.latitude,
    longitude: geofence.longitude,
    radius: geofence.radius,
    notifyOnArrive: geofence.notifyOnArrive ?? true,
    notifyOnLeave: geofence.notifyOnLeave ?? false,
    notifyMembers: geofence.notifyMembers ?? [],
    monitoredMemberIds: geofence.monitoredMemberIds ?? [],
    isActive: geofence.isActive ?? true,
    updatedAt: serverTimestamp(),
  };
  if (!geofence.id) {
    payload.createdBy = uid;
    payload.createdAt = serverTimestamp();
  }
  await setDoc(doc(geofencesCol(familyId), id), payload, { merge: true });
  return id;
}

/** Le rules consentono la cancellazione delle zone al solo proprietario. */
export async function deleteGeofence({ familyId, geofenceId }) {
  await deleteDoc(doc(geofencesCol(familyId), geofenceId));
}

export { GeoPoint };
