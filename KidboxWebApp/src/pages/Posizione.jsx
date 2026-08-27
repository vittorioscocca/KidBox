import { useEffect, useRef, useState } from "react";
import { useFamily } from "../FamilyContext";
import { useAuth } from "../AuthContext";
import { useTranslation } from "../i18n/LocaleContext";
import {
  deleteGeofence,
  listenGeofences,
  listenSharedLocations,
  saveGeofence,
  startSharing,
  stopSharing,
  updateCoordinates,
} from "../services/location";
import FamilyMap from "../components/FamilyMap";
import Modal from "../components/Modal";
import "./Posizione.css";

const DURATIONS = [1, 2, 4, 8];

export default function Posizione() {
  const { currentFamilyId } = useFamily();
  const { user } = useAuth();
  const { t, locale } = useTranslation();

  const [people, setPeople] = useState([]);
  const [zones, setZones] = useState([]);
  const [sharing, setSharing] = useState(false);
  const [mode, setMode] = useState("realtime");
  const [duration, setDuration] = useState(2);
  const [error, setError] = useState(null);
  const [focus, setFocus] = useState(null);
  const [zoneDraft, setZoneDraft] = useState(null);
  const [placingZone, setPlacingZone] = useState(false);
  const [selfPosition, setSelfPosition] = useState(null);
  const [layer, setLayer] = useState(
    () => localStorage.getItem("kidbox:mapLayer") || "map"
  );
  const watchRef = useRef(null);

  useEffect(() => {
    if (!currentFamilyId) return undefined;
    return listenSharedLocations({
      familyId: currentFamilyId,
      onChange: setPeople,
      onError: (err) => setError(err.message),
    });
  }, [currentFamilyId]);

  useEffect(() => {
    if (!currentFamilyId) return undefined;
    return listenGeofences({
      familyId: currentFamilyId,
      onChange: setZones,
      onError: (err) => setError(err.message),
    });
  }, [currentFamilyId]);

  /**
   * La condivisione dal browser vive quanto la scheda: alla chiusura il watch
   * si interrompe e nessuno aggiornerebbe più le coordinate. Meglio dichiarare
   * esplicitamente lo stop, così gli altri non vedono una posizione ferma
   * scambiandola per attuale.
   */
  useEffect(() => {
    const onUnload = () => {
      if (watchRef.current != null) {
        navigator.geolocation.clearWatch(watchRef.current);
        stopSharing({ familyId: currentFamilyId, uid: user.uid });
      }
    };
    window.addEventListener("pagehide", onUnload);
    return () => {
      window.removeEventListener("pagehide", onUnload);
      onUnload();
    };
  }, [currentFamilyId, user]);

  const beginSharing = async () => {
    setError(null);
    if (!navigator.geolocation) {
      setError(t.location.permissionDenied);
      return;
    }
    const expiresAt =
      mode === "temporary" ? new Date(Date.now() + duration * 3600e3) : null;

    try {
      await startSharing({
        familyId: currentFamilyId,
        uid: user.uid,
        name: user.displayName || user.email || "",
        mode,
        expiresAt,
      });
    } catch (err) {
      setError(err.message);
      return;
    }

    watchRef.current = navigator.geolocation.watchPosition(
      (pos) => {
        setSelfPosition({
          lat: pos.coords.latitude,
          lon: pos.coords.longitude,
          accuracy: pos.coords.accuracy,
        });
        updateCoordinates({
          familyId: currentFamilyId,
          uid: user.uid,
          lat: pos.coords.latitude,
          lon: pos.coords.longitude,
          accuracy: pos.coords.accuracy,
        });
      },
      (err) => {
        setError(
          err.code === err.PERMISSION_DENIED
            ? t.location.permissionDenied
            : err.message
        );
        endSharing();
      },
      { enableHighAccuracy: true, maximumAge: 10000, timeout: 20000 }
    );
    setSharing(true);
  };

  const endSharing = async () => {
    if (watchRef.current != null) {
      navigator.geolocation.clearWatch(watchRef.current);
      watchRef.current = null;
    }
    setSharing(false);
    try {
      await stopSharing({ familyId: currentFamilyId, uid: user.uid });
    } catch (err) {
      setError(err.message);
    }
  };

  /** Solo per inquadrare la mappa: non scrive nulla su Firestore. */
  const centerOnMe = () => {
    if (!navigator.geolocation) {
      setError(t.location.permissionDenied);
      return;
    }
    navigator.geolocation.getCurrentPosition(
      (pos) => {
        const here = {
          lat: pos.coords.latitude,
          lon: pos.coords.longitude,
          accuracy: pos.coords.accuracy,
        };
        setSelfPosition(here);
        setFocus({ ...here, zoom: 16 });
      },
      (err) =>
        setError(
          err.code === err.PERMISSION_DENIED
            ? t.location.permissionDenied
            : err.message
        ),
      { enableHighAccuracy: true, timeout: 15000 }
    );
  };

  const onMapClick = (lat, lon) => {
    if (!placingZone) return;
    setPlacingZone(false);
    setZoneDraft({ latitude: lat, longitude: lon, radius: 150, name: "", emoji: "📍" });
  };

  const timeLabel = (date) =>
    date
      ? new Intl.DateTimeFormat(locale === "en" ? "en-US" : "it-IT", {
          hour: "2-digit",
          minute: "2-digit",
        }).format(date)
      : "";

  return (
    <div className="location-page">
      <div className="overview-header">
        <h1>{t.location.title}</h1>
      </div>

      <p className="location-note">{t.location.webLimit}</p>
      {error && <p className="error">{error}</p>}

      <div className="location-layout">
        <div className="map-wrap">
          {placingZone && <div className="map-hint">{t.location.pickOnMap}</div>}
          <div className="map-layer-toggle">
            {["map", "satellite"].map((l) => (
              <button
                key={l}
                className={layer === l ? "active" : ""}
                onClick={() => {
                  localStorage.setItem("kidbox:mapLayer", l);
                  setLayer(l);
                }}
              >
                {l === "map" ? t.location.layerMap : t.location.layerSatellite}
              </button>
            ))}
          </div>
          <button className="map-center-btn" onClick={centerOnMe} title={t.location.centerMe}>
            ◎
          </button>
          <FamilyMap
            people={people}
            zones={zones}
            onMapClick={onMapClick}
            focus={focus}
            selfPosition={selfPosition}
            layer={layer}
          />
        </div>

        <aside className="location-side">
          <div className="share-card">
            {sharing ? (
              <>
                <strong className="share-on">● {t.location.sharing}</strong>
                <button className="docs-btn" onClick={endSharing}>
                  {t.location.shareOff}
                </button>
              </>
            ) : (
              <>
                <div className="seg-control">
                  {["realtime", "temporary"].map((m) => (
                    <button
                      key={m}
                      className={"seg-btn" + (mode === m ? " active" : "")}
                      onClick={() => setMode(m)}
                    >
                      {t.location[m]}
                    </button>
                  ))}
                </div>
                {mode === "temporary" && (
                  <div className="duration-row">
                    {DURATIONS.map((h) => (
                      <button
                        key={h}
                        className={"cat-chip" + (duration === h ? " active" : "")}
                        onClick={() => setDuration(h)}
                      >
                        {t.location.hours(h)}
                      </button>
                    ))}
                  </div>
                )}
                <button className="docs-btn primary" onClick={beginSharing}>
                  ▶ {t.location.shareOn}
                </button>
              </>
            )}
          </div>

          <h3 className="docs-section">{t.location.members}</h3>
          {people.length === 0 ? (
            <div className="side-empty">
              <strong>{t.location.nobody}</strong>
              <p>{t.location.nobodyHint}</p>
            </div>
          ) : (
            <ul className="people-list">
              {people.map((p) => (
                <li key={p.id}>
                  <button
                    onClick={() =>
                      setFocus({ lat: p.latitude, lon: p.longitude, zoom: 16 })
                    }
                  >
                    <span className="person-dot">
                      {(p.name || "?").charAt(0).toUpperCase()}
                    </span>
                    <span className="person-info">
                      <span className="person-name">{p.name || "—"}</span>
                      <span className="person-meta">
                        {p.mode === "temporary" && p.expiresAt
                          ? t.location.until(timeLabel(p.expiresAt))
                          : t.location.realtime}
                      </span>
                    </span>
                  </button>
                </li>
              ))}
            </ul>
          )}

          <div className="zones-head">
            <h3 className="docs-section">{t.location.zones}</h3>
            <button
              className="lists-add"
              onClick={() => setPlacingZone(true)}
              title={t.location.newZone}
            >
              +
            </button>
          </div>
          <ul className="zones-list">
            {zones.map((z) => (
              <li key={z.id}>
                <button
                  className="zone-main"
                  onClick={() =>
                    setFocus({ lat: z.latitude, lon: z.longitude, zoom: 15 })
                  }
                >
                  <span>{z.emoji ?? "📍"}</span>
                  <span className="zone-name">{z.name}</span>
                  <span className="zone-radius">{Math.round(z.radius ?? 0)} m</span>
                </button>
                <button className="zone-edit" onClick={() => setZoneDraft(z)}>
                  ✎
                </button>
              </li>
            ))}
            {zones.length === 0 && <p className="side-empty-inline">—</p>}
          </ul>
        </aside>
      </div>

      {zoneDraft && (
        <ZoneModal
          zone={zoneDraft}
          onCancel={() => setZoneDraft(null)}
          onSave={async (values) => {
            await saveGeofence({
              familyId: currentFamilyId,
              uid: user.uid,
              geofence: { ...zoneDraft, ...values },
            });
            setZoneDraft(null);
          }}
          onDelete={
            zoneDraft.id
              ? async () => {
                  if (!window.confirm(t.location.deleteZoneConfirm)) return;
                  try {
                    await deleteGeofence({
                      familyId: currentFamilyId,
                      geofenceId: zoneDraft.id,
                    });
                    setZoneDraft(null);
                  } catch (err) {
                    setError(err.message);
                  }
                }
              : null
          }
        />
      )}
    </div>
  );
}

function ZoneModal({ zone, onCancel, onSave, onDelete }) {
  const { t } = useTranslation();
  const [name, setName] = useState(zone.name ?? "");
  const [emoji, setEmoji] = useState(zone.emoji ?? "📍");
  const [radius, setRadius] = useState(zone.radius ?? 150);
  const [onArrive, setOnArrive] = useState(zone.notifyOnArrive ?? true);
  const [onLeave, setOnLeave] = useState(zone.notifyOnLeave ?? false);

  return (
    <Modal onClose={onCancel}>
      <div className="modal-header">
        <button className="modal-text-btn" onClick={onCancel}>
          {t.location.cancel}
        </button>
        <button
          className="modal-save-btn"
          disabled={!name.trim()}
          onClick={() =>
            onSave({
              name: name.trim(),
              emoji,
              radius: Number(radius),
              notifyOnArrive: onArrive,
              notifyOnLeave: onLeave,
            })
          }
        >
          {t.location.save}
        </button>
      </div>
      <div className="modal-title">
        {zone.id ? t.location.editZone : t.location.newZone}
      </div>

      <div className="zone-name-row">
        <input
          className="modal-field emoji-field"
          value={emoji}
          maxLength={2}
          onChange={(e) => setEmoji(e.target.value)}
        />
        <input
          className="modal-field"
          placeholder={t.location.zoneName}
          value={name}
          autoFocus
          onChange={(e) => setName(e.target.value)}
        />
      </div>

      <div className="modal-label">
        {t.location.radius}: {radius} m
      </div>
      <input
        type="range"
        min="50"
        max="2000"
        step="25"
        value={radius}
        onChange={(e) => setRadius(e.target.value)}
        className="radius-slider"
      />

      <div className="modal-section">
        <div className="modal-row clickable" onClick={() => setOnArrive((v) => !v)}>
          <span>{t.location.onArrive}</span>
          <span className={`modal-check ${onArrive ? "on" : "off"}`}>✓</span>
        </div>
        <div className="modal-row clickable" onClick={() => setOnLeave((v) => !v)}>
          <span>{t.location.onLeave}</span>
          <span className={`modal-check ${onLeave ? "on" : "off"}`}>✓</span>
        </div>
      </div>

      {onDelete && (
        <button className="modal-delete-btn" onClick={onDelete}>
          {t.location.deleteZone}
        </button>
      )}
    </Modal>
  );
}
