import { useEffect, useMemo, useRef, useState } from "react";
import { useFamily } from "../FamilyContext";
import { useAuth } from "../AuthContext";
import { useTranslation } from "../i18n/LocaleContext";
import {
  deleteVehicle,
  deleteVehicleEvent,
  eventTypeInfo,
  fuelInfo,
  garageFolderId,
  listenGarage,
  saveVehicle,
  saveVehicleEvent,
  vehicleEventTag,
  vehicleTag,
} from "../services/vehicles";
import { fetchDocumentBlob, uploadDocument } from "../services/documents";
import { ensureFolder, listenTaggedDocuments } from "../services/attachments";
import { formatAmount } from "../expenseCategories";
import VehicleModal from "../components/VehicleModal";
import VehicleEventModal from "../components/VehicleEventModal";
import "./Garage.css";

export default function Garage() {
  const { currentFamilyId } = useFamily();
  const { user } = useAuth();
  const { t, locale } = useTranslation();
  const g = t.garage;
  const fileRef = useRef(null);

  const [vehicles, setVehicles] = useState([]);
  const [events, setEvents] = useState([]);
  const [attachments, setAttachments] = useState(new Map());
  const [error, setError] = useState(null);

  const [selectedId, setSelectedId] = useState(null);
  const [editingVehicle, setEditingVehicle] = useState(null);
  const [editingEvent, setEditingEvent] = useState(null);
  const [pendingTag, setPendingTag] = useState(null);

  useEffect(() => {
    if (!currentFamilyId) return undefined;
    return listenGarage({
      familyId: currentFamilyId,
      onChange: ({ vehicles: v, events: e }) => {
        setVehicles(v);
        setEvents(e);
      },
      onError: (err) => setError(err.message),
    });
  }, [currentFamilyId]);

  useEffect(() => {
    if (!currentFamilyId) return undefined;
    return listenTaggedDocuments({
      familyId: currentFamilyId,
      prefixes: ["vehicle:", "vehicleEvent:"],
      onChange: setAttachments,
      onError: (err) => setError(err.message),
    });
  }, [currentFamilyId]);

  const now = Date.now();
  const selected = vehicles.find((v) => v.id === selectedId) || null;

  const eventsByVehicle = useMemo(() => {
    const map = new Map();
    for (const e of events) map.set(e.vehicleId, [...(map.get(e.vehicleId) || []), e]);
    return map;
  }, [events]);

  const fmt = (millis) =>
    millis
      ? new Date(millis).toLocaleDateString(locale === "en" ? "en-US" : "it-IT", {
          day: "2-digit",
          month: "short",
          year: "numeric",
        })
      : null;

  const fmtDateTime = (millis) =>
    millis
      ? new Date(millis).toLocaleString(locale === "en" ? "en-US" : "it-IT", {
          day: "2-digit",
          month: "short",
          year: "numeric",
        })
      : null;

  const state = (millis) => {
    if (!millis) return null;
    if (millis < now) return "expired";
    if (millis - now < 60 * 24 * 60 * 60 * 1000) return "soon";
    return null;
  };

  /** Le tre scadenze del veicolo, per la copertina e il dettaglio. */
  const deadlines = (v) => [
    { label: g.insurance, date: v.insuranceExpiryDate },
    { label: g.revision, date: v.revisionExpiryDate },
    { label: g.tax, date: v.taxExpiryDate },
    { label: g.nextService, date: v.nextServiceDate },
  ];

  const nextDeadline = (v) =>
    deadlines(v)
      .filter((d) => d.date)
      .sort((a, b) => a.date - b.date)[0] || null;

  const removeVehicle = async (id) => {
    if (!window.confirm(g.confirmDelete)) return;
    await deleteVehicle({ familyId: currentFamilyId, userId: user.uid, id });
    setSelectedId(null);
  };

  const removeEvent = async (event) => {
    if (!window.confirm(g.confirmDeleteEvent)) return;
    await deleteVehicleEvent({
      familyId: currentFamilyId,
      userId: user.uid,
      id: event.id,
      linkedExpenseId: event.linkedExpenseId,
    });
  };

  const pickAttachment = (tag) => {
    setPendingTag(tag);
    fileRef.current?.click();
  };

  const uploadAttachment = async (file) => {
    if (!file || !pendingTag) return;
    try {
      const id = await ensureFolder({
        familyId: currentFamilyId,
        userId: user.uid,
        id: garageFolderId(currentFamilyId),
        title: g.title,
      });
      await uploadDocument({
        familyId: currentFamilyId,
        userId: user.uid,
        file,
        categoryId: id,
        notes: pendingTag,
      });
    } catch (err) {
      setError(err.message);
    } finally {
      setPendingTag(null);
    }
  };

  const openAttachment = async (docData) => {
    try {
      const blob = await fetchDocumentBlob({
        familyId: currentFamilyId,
        userId: user.uid,
        document: docData,
      });
      window.open(URL.createObjectURL(blob), "_blank", "noopener");
    } catch (err) {
      setError(err.message);
    }
  };

  const attachmentList = (tag) => (
    <div className="an-attachments">
      {(attachments.get(tag) || []).map((d) => (
        <button key={d.id} className="an-attachment" onClick={() => openAttachment(d)}>
          📎 {d.title || d.fileName}
        </button>
      ))}
      <button className="an-attachment add" onClick={() => pickAttachment(tag)}>
        + {g.addAttachment}
      </button>
    </div>
  );

  return (
    <div className="gar-page">
      <header className="pw-header">
        <h1>{g.title}</h1>
        <div className="pw-toolbar">
          <button className="pw-btn-primary" onClick={() => setEditingVehicle({})}>
            + {g.addVehicle}
          </button>
        </div>
      </header>

      {error && <p className="error">{error}</p>}

      {vehicles.length === 0 ? (
        <p className="pw-empty">{g.empty}</p>
      ) : (
        <div className="gar-grid">
          {vehicles.map((v) => {
            const next = nextDeadline(v);
            const st = next ? state(next.date) : null;
            return (
              <button key={v.id} className="gar-card" onClick={() => setSelectedId(v.id)}>
                <span className="gar-top">
                  <span className="gar-name">🚗 {v.name}</span>
                  {v.licensePlate && <span className="gar-plate">{v.licensePlate}</span>}
                </span>
                <span className="gar-meta">
                  {[v.brand, v.model, v.year, v.fuelTypeRaw ? (locale === "en" ? fuelInfo(v.fuelTypeRaw).en : fuelInfo(v.fuelTypeRaw).it) : null]
                    .filter(Boolean)
                    .join(" · ")}
                </span>
                {next && (
                  <span className={"gar-due" + (st ? " " + st : "")}>
                    {next.label}: {fmt(next.date)}
                  </span>
                )}
              </button>
            );
          })}
        </div>
      )}

      <input
        ref={fileRef}
        type="file"
        hidden
        onChange={(e) => {
          const f = e.target.files?.[0];
          e.target.value = "";
          if (f) uploadAttachment(f);
        }}
      />

      {selected && (
        <div className="pw-detail-overlay" onClick={() => setSelectedId(null)}>
          <aside className="pw-detail" onClick={(e) => e.stopPropagation()}>
            <header>
              <h2>🚗 {selected.name}</h2>
              <button onClick={() => setSelectedId(null)}>✕</button>
            </header>

            <Row label={g.plate} value={selected.licensePlate} />
            <Row label={g.brand} value={[selected.brand, selected.model].filter(Boolean).join(" ")} />
            <Row label={g.year} value={selected.year ? String(selected.year) : null} />
            <Row
              label={g.fuel}
              value={
                selected.fuelTypeRaw
                  ? locale === "en"
                    ? fuelInfo(selected.fuelTypeRaw).en
                    : fuelInfo(selected.fuelTypeRaw).it
                  : null
              }
            />
            <Row label={g.color} value={selected.color} />
            <Row label={g.vin} value={selected.vin} />
            <Row label={g.currentKm} value={selected.currentKm != null ? `${selected.currentKm} km` : null} />

            {deadlines(selected)
              .filter((d) => d.date)
              .map((d) => {
                const st = state(d.date);
                return (
                  <div key={d.label} className="pw-detail-row">
                    <span className="pw-detail-label">{d.label}</span>
                    <span className={"pw-detail-value gar-due" + (st ? " " + st : "")}>
                      {fmt(d.date)}
                      {st === "expired" ? ` · ${g.expiredLabel}` : st === "soon" ? ` · ${g.expiringLabel}` : ""}
                    </span>
                  </div>
                );
              })}

            <Row label={g.lastService} value={fmt(selected.lastServiceDate)} />
            <Row label={g.notes} value={selected.notes} />

            <h3 className="an-section">{g.attachments}</h3>
            {attachmentList(vehicleTag(selected.id))}

            <h3 className="an-section">
              {g.events}
              <button className="an-add-event" onClick={() => setEditingEvent({ vehicleId: selected.id })}>
                + {g.addEvent}
              </button>
            </h3>

            {(eventsByVehicle.get(selected.id) || []).length === 0 ? (
              <p className="pw-hint">{g.noEvents}</p>
            ) : (
              <ul className="an-events">
                {(eventsByVehicle.get(selected.id) || []).map((ev) => {
                  const ty = eventTypeInfo(ev.eventTypeRaw);
                  return (
                    <li key={ev.id}>
                      <span className="an-event-dot" style={{ background: ty.color }} />
                      <span className="an-event-body">
                        <span className="an-event-title">
                          {ty.emoji} {ev.title}
                        </span>
                        <span className="an-event-meta">
                          {[
                            fmtDateTime(ev.date),
                            ev.km != null ? `${ev.km} km` : null,
                            ev.garageName,
                            ev.cost != null ? formatAmount(ev.cost, locale) : null,
                          ]
                            .filter(Boolean)
                            .join(" · ")}
                        </span>
                        {ev.notes && <span className="an-event-notes">{ev.notes}</span>}
                        {ev.linkedExpenseId && (
                          <span className="an-event-notes">💶 {g.linkedExpense}</span>
                        )}
                        {attachmentList(vehicleEventTag(ev.id))}
                      </span>
                      <span className="an-event-actions">
                        <button onClick={() => setEditingEvent(ev)}>{g.edit}</button>
                        <button className="pw-danger" onClick={() => removeEvent(ev)}>
                          {g.delete}
                        </button>
                      </span>
                    </li>
                  );
                })}
              </ul>
            )}

            <div className="pw-form-actions">
              <button className="pw-danger" onClick={() => removeVehicle(selected.id)}>
                {g.delete}
              </button>
              <button className="pw-btn-primary" onClick={() => setEditingVehicle(selected)}>
                {g.edit}
              </button>
            </div>
          </aside>
        </div>
      )}

      {editingVehicle && (
        <VehicleModal
          vehicle={editingVehicle}
          locale={locale}
          onSave={(vehicle) => saveVehicle({ familyId: currentFamilyId, userId: user.uid, vehicle })}
          onClose={() => setEditingVehicle(null)}
        />
      )}

      {editingEvent && (
        <VehicleEventModal
          event={editingEvent}
          vehicleId={editingEvent.vehicleId}
          locale={locale}
          onSave={(event) => saveVehicleEvent({ familyId: currentFamilyId, userId: user.uid, event })}
          onClose={() => setEditingEvent(null)}
        />
      )}
    </div>
  );
}

/** Riga del pannello di dettaglio, fuori dal componente per non rimontarla. */
function Row({ label, value }) {
  if (!value) return null;
  return (
    <div className="pw-detail-row">
      <span className="pw-detail-label">{label}</span>
      <span className="pw-detail-value">{value}</span>
    </div>
  );
}
