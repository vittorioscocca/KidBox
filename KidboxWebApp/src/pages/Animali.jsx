import { useEffect, useMemo, useRef, useState } from "react";
import { useFamily } from "../FamilyContext";
import { useAuth } from "../AuthContext";
import { useTranslation } from "../i18n/LocaleContext";
import {
  deleteEvent,
  deletePet,
  eventTypeInfo,
  listenPets,
  petEventTag,
  petTag,
  saveEvent,
  savePet,
  speciesInfo,
} from "../services/pets";
import { fetchDocumentBlob, uploadDocument } from "../services/documents";
import { ensureFolder, listenTaggedDocuments } from "../services/attachments";
import { petsFolderId } from "../services/pets";
import PetModal from "../components/PetModal";
import PetEventModal from "../components/PetEventModal";
import "./Animali.css";

export default function Animali() {
  const { currentFamilyId } = useFamily();
  const { user } = useAuth();
  const { t, locale } = useTranslation();
  const p = t.pets;
  const fileRef = useRef(null);

  const [pets, setPets] = useState([]);
  const [events, setEvents] = useState([]);
  const [attachments, setAttachments] = useState(new Map());
  const [error, setError] = useState(null);

  const [selectedId, setSelectedId] = useState(null);
  const [editingPet, setEditingPet] = useState(null);
  const [editingEvent, setEditingEvent] = useState(null);
  const [pendingTag, setPendingTag] = useState(null);

  useEffect(() => {
    if (!currentFamilyId) return undefined;
    return listenPets({
      familyId: currentFamilyId,
      onChange: ({ pets: ps, events: ev }) => {
        setPets(ps);
        setEvents(ev);
      },
      onError: (err) => setError(err.message),
    });
  }, [currentFamilyId]);

  useEffect(() => {
    if (!currentFamilyId) return undefined;
    return listenTaggedDocuments({
      familyId: currentFamilyId,
      prefixes: ["pet:", "petEvent:"],
      onChange: setAttachments,
      onError: (err) => setError(err.message),
    });
  }, [currentFamilyId]);

  const now = Date.now();
  const selected = pets.find((x) => x.id === selectedId) || null;

  const eventsByPet = useMemo(() => {
    const map = new Map();
    for (const e of events) map.set(e.petId, [...(map.get(e.petId) || []), e]);
    return map;
  }, [events]);

  /** La scadenza più vicina fra gli eventi dell'animale: è quella che va in copertina. */
  const nextDueFor = (petId) => {
    const due = (eventsByPet.get(petId) || [])
      .map((e) => e.nextDueDate)
      .filter(Boolean)
      .sort((a, b) => a - b);
    return due[0] || null;
  };

  const fmtDate = (millis) =>
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
          hour: "2-digit",
          minute: "2-digit",
        })
      : null;

  const ageOf = (birthDate) => {
    if (!birthDate) return null;
    const months = Math.max(
      0,
      Math.floor((now - birthDate) / (30.44 * 24 * 60 * 60 * 1000))
    );
    return p.age(Math.floor(months / 12), months % 12);
  };

  const removePet = async (id) => {
    if (!window.confirm(p.confirmDeletePet)) return;
    await deletePet({ familyId: currentFamilyId, userId: user.uid, id });
    setSelectedId(null);
  };

  const removeEvent = async (id) => {
    if (!window.confirm(p.confirmDelete)) return;
    await deleteEvent({ familyId: currentFamilyId, userId: user.uid, id });
  };

  const pickAttachment = (tag) => {
    setPendingTag(tag);
    fileRef.current?.click();
  };

  const uploadAttachment = async (file) => {
    if (!file || !pendingTag) return;
    try {
      const categoryId = await ensureFolder({
        familyId: currentFamilyId,
        userId: user.uid,
        id: petsFolderId(currentFamilyId),
        title: p.title,
      });
      await uploadDocument({
        familyId: currentFamilyId,
        userId: user.uid,
        file,
        categoryId,
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

  const attachmentList = (tag) => {
    const items = attachments.get(tag) || [];
    return (
      <div className="an-attachments">
        {items.map((d) => (
          <button key={d.id} className="an-attachment" onClick={() => openAttachment(d)}>
            📎 {d.title || d.fileName}
          </button>
        ))}
        <button className="an-attachment add" onClick={() => pickAttachment(tag)}>
          + {p.addAttachment}
        </button>
      </div>
    );
  };

  return (
    <div className="an-page">
      <header className="pw-header">
        <h1>{p.title}</h1>
        <div className="pw-toolbar">
          <button className="pw-btn-primary" onClick={() => setEditingPet({})}>
            + {p.add}
          </button>
        </div>
      </header>

      {error && <p className="error">{error}</p>}

      {pets.length === 0 ? (
        <p className="pw-empty">{p.empty}</p>
      ) : (
        <div className="an-grid">
          {pets.map((pet) => {
            const info = speciesInfo(pet.species);
            const due = nextDueFor(pet.id);
            const late = due && due < now;
            return (
              <button key={pet.id} className="an-card" onClick={() => setSelectedId(pet.id)}>
                <span className="an-avatar">
                  {pet.photoURL ? <img src={pet.photoURL} alt={pet.name} /> : info.emoji}
                </span>
                <span className="an-card-body">
                  <span className="an-name">{pet.name}</span>
                  <span className="an-meta">
                    {[locale === "en" ? info.en : info.it, pet.breed, ageOf(pet.birthDate)]
                      .filter(Boolean)
                      .join(" · ")}
                  </span>
                  {due && (
                    <span className={"an-due" + (late ? " late" : "")}>
                      {late ? p.overdue : p.nextLabel(fmtDate(due))}
                    </span>
                  )}
                </span>
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
              <h2>
                {speciesInfo(selected.species).emoji} {selected.name}
              </h2>
              <button onClick={() => setSelectedId(null)}>✕</button>
            </header>

            <Row label={p.species} value={locale === "en" ? speciesInfo(selected.species).en : speciesInfo(selected.species).it} />
            <Row label={p.breed} value={selected.breed} />
            <Row
              label={p.birthDate}
              value={[fmtDate(selected.birthDate), ageOf(selected.birthDate)]
                .filter(Boolean)
                .join(" · ")}
            />
            <Row label={p.color} value={selected.color} />
            <Row label={p.chipCode} value={selected.chipCode} />
            <Row label={p.notes} value={selected.notes} />

            <h3 className="an-section">{p.attachments}</h3>
            {attachmentList(petTag(selected.id))}

            <h3 className="an-section">
              {p.events}
              <button
                className="an-add-event"
                onClick={() => setEditingEvent({ petId: selected.id })}
              >
                + {p.addEvent}
              </button>
            </h3>

            {(eventsByPet.get(selected.id) || []).length === 0 ? (
              <p className="pw-hint">{p.noEvents}</p>
            ) : (
              <ul className="an-events">
                {(eventsByPet.get(selected.id) || []).map((ev) => {
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
                            ev.vetName,
                            ev.cost != null ? `€ ${ev.cost.toFixed(2)}` : null,
                          ]
                            .filter(Boolean)
                            .join(" · ")}
                        </span>
                        {ev.nextDueDate && (
                          <span className={"an-due" + (ev.nextDueDate < now ? " late" : "")}>
                            {p.nextLabel(fmtDate(ev.nextDueDate))}
                          </span>
                        )}
                        {ev.notes && <span className="an-event-notes">{ev.notes}</span>}
                        {attachmentList(petEventTag(ev.id))}
                      </span>
                      <span className="an-event-actions">
                        <button onClick={() => setEditingEvent(ev)}>{p.edit}</button>
                        <button className="pw-danger" onClick={() => removeEvent(ev.id)}>
                          {p.delete}
                        </button>
                      </span>
                    </li>
                  );
                })}
              </ul>
            )}

            <div className="pw-form-actions">
              <button className="pw-danger" onClick={() => removePet(selected.id)}>
                {p.delete}
              </button>
              <button className="pw-btn-primary" onClick={() => setEditingPet(selected)}>
                {p.edit}
              </button>
            </div>
          </aside>
        </div>
      )}

      {editingPet && (
        <PetModal
          pet={editingPet}
          locale={locale}
          onSave={(pet) => savePet({ familyId: currentFamilyId, userId: user.uid, pet })}
          onClose={() => setEditingPet(null)}
        />
      )}

      {editingEvent && (
        <PetEventModal
          event={editingEvent}
          petId={editingEvent.petId}
          locale={locale}
          onSave={(event) => saveEvent({ familyId: currentFamilyId, userId: user.uid, event })}
          onClose={() => setEditingEvent(null)}
        />
      )}
    </div>
  );
}

function Row({ label, value }) {
  if (!value) return null;
  return (
    <div className="pw-detail-row">
      <span className="pw-detail-label">{label}</span>
      <span className="pw-detail-value">{value}</span>
    </div>
  );
}
