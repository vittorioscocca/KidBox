/**
 * Scheda medica — porting di `PediatricMedicalRecordView` e
 * `ReferenceDoctorFormView`.
 *
 * Il documento è uno solo per soggetto (`pediatricProfiles/{childId}`), quindi
 * la schermata è un form: si modifica e si salva, non si aggiunge e si elimina.
 *
 * Orari di ricevimento e contatti di emergenza viaggiano come array JSON in un
 * campo di testo (`doctorOfficeHoursJSON`, `emergencyContactsJSON`): è la forma
 * che iOS si aspetta di rileggere, e il giorno della settimana resta scritto in
 * italiano perché è il valore persistito, non un'etichetta.
 */
import { useEffect, useState } from "react";
import { BLOOD_GROUPS, WEEKDAYS_IT, savePediatricProfile } from "../../services/health";
import { Field, ModuleHeader, newId } from "./shared";

const emptyProfile = () => ({
  bloodGroup: "",
  allergies: "",
  medicalNotes: "",
  doctorName: "",
  doctorPhone: "",
  doctorEmail: "",
  doctorAddress: "",
  doctorWebsite: "",
  doctorOfficeHours: [],
  emergencyContacts: [],
});

export default function HealthMedicalRecord({
  familyId,
  userId,
  subject,
  profile,
  h,
  onError,
  onBack,
}) {
  const m = h.medicalRecord;
  const [draft, setDraft] = useState(() => ({ ...emptyProfile(), ...(profile || {}) }));
  const [saving, setSaving] = useState(false);
  const [saved, setSaved] = useState(false);

  // Il documento arriva dal listener, non dal montaggio: finché non è arrivato
  // il form è vuoto, e va riallineato quando compare (o quando cambia da un
  // altro dispositivo) senza sovrascrivere quello che si sta scrivendo.
  useEffect(() => {
    if (!profile) return;
    setDraft((d) => (d.dirty ? d : { ...emptyProfile(), ...profile }));
  }, [profile]);

  const set = (patch) => {
    setDraft((d) => ({ ...d, ...patch, dirty: true }));
    setSaved(false);
  };

  const submit = async () => {
    setSaving(true);
    try {
      await savePediatricProfile({
        familyId,
        userId,
        childId: subject.id,
        profile: draft,
      });
      setDraft((d) => ({ ...d, dirty: false }));
      setSaved(true);
    } catch (err) {
      onError(err);
    } finally {
      setSaving(false);
    }
  };

  const setSlot = (index, patch) =>
    set({
      doctorOfficeHours: draft.doctorOfficeHours.map((s, i) =>
        i === index ? { ...s, ...patch } : s
      ),
    });

  const setContact = (index, patch) =>
    set({
      emergencyContacts: draft.emergencyContacts.map((c, i) =>
        i === index ? { ...c, ...patch } : c
      ),
    });

  return (
    <div className="sa-page">
      <ModuleHeader title={m.title} onBack={onBack} backLabel={h.back}>
        <button className="pw-btn-primary" disabled={saving || !draft.dirty} onClick={submit}>
          {h.save}
        </button>
      </ModuleHeader>

      {saved && <p className="sa-notice">{m.saved}</p>}

      <section className="sa-card">
        <h3>{m.clinicalData}</h3>
        <div className="sa-grid-2">
          <Field label={m.bloodGroup}>
            <select
              value={draft.bloodGroup}
              onChange={(e) => set({ bloodGroup: e.target.value })}
            >
              <option value="">—</option>
              {BLOOD_GROUPS.map((g) => (
                <option key={g} value={g}>
                  {g}
                </option>
              ))}
            </select>
          </Field>
        </div>
        <Field label={m.allergies}>
          <textarea
            value={draft.allergies}
            placeholder={m.allergiesPlaceholder}
            onChange={(e) => set({ allergies: e.target.value })}
          />
        </Field>
        <Field label={m.medicalNotes}>
          <textarea
            value={draft.medicalNotes}
            onChange={(e) => set({ medicalNotes: e.target.value })}
          />
        </Field>
      </section>

      <section className="sa-card">
        <h3>{m.referenceDoctor}</h3>
        <div className="sa-grid-2">
          <Field label={m.doctorName}>
            <input
              value={draft.doctorName}
              onChange={(e) => set({ doctorName: e.target.value })}
            />
          </Field>
          <Field label={m.doctorPhone}>
            <input
              type="tel"
              value={draft.doctorPhone}
              onChange={(e) => set({ doctorPhone: e.target.value })}
            />
          </Field>
          <Field label={m.doctorEmail}>
            <input
              type="email"
              value={draft.doctorEmail}
              onChange={(e) => set({ doctorEmail: e.target.value })}
            />
          </Field>
          <Field label={m.doctorWebsite}>
            <input
              value={draft.doctorWebsite}
              onChange={(e) => set({ doctorWebsite: e.target.value })}
            />
          </Field>
        </div>
        <Field label={m.doctorAddress}>
          <input
            value={draft.doctorAddress}
            onChange={(e) => set({ doctorAddress: e.target.value })}
          />
        </Field>

        <h3>{m.officeHours}</h3>
        {draft.doctorOfficeHours.map((slot, i) => (
          <div key={slot.id || i} className="sa-grid-2">
            <Field label={m.weekday}>
              <select
                value={slot.weekday}
                onChange={(e) => setSlot(i, { weekday: e.target.value })}
              >
                {WEEKDAYS_IT.map((d) => (
                  <option key={d} value={d}>
                    {d}
                  </option>
                ))}
              </select>
            </Field>
            <Field label={m.fromTime}>
              <input
                type="time"
                value={slot.fromTime}
                onChange={(e) => setSlot(i, { fromTime: e.target.value })}
              />
            </Field>
            <Field label={m.toTime}>
              <input
                type="time"
                value={slot.toTime}
                onChange={(e) => setSlot(i, { toTime: e.target.value })}
              />
            </Field>
            <button
              className="sa-chip"
              onClick={() =>
                set({ doctorOfficeHours: draft.doctorOfficeHours.filter((_, j) => j !== i) })
              }
            >
              {h.delete}
            </button>
          </div>
        ))}
        <button
          className="sa-chip"
          onClick={() =>
            set({
              doctorOfficeHours: [
                ...draft.doctorOfficeHours,
                { id: newId(), weekday: WEEKDAYS_IT[0], fromTime: "09:00", toTime: "12:00" },
              ],
            })
          }
        >
          + {m.addSlot}
        </button>
      </section>

      <section className="sa-card">
        <h3>{m.emergencyContacts}</h3>
        {draft.emergencyContacts.length === 0 && <p className="pw-hint">{m.noContacts}</p>}
        {draft.emergencyContacts.map((contact, i) => (
          <div key={contact.id || i} className="sa-grid-2">
            <Field label={m.contactName}>
              <input
                value={contact.name}
                onChange={(e) => setContact(i, { name: e.target.value })}
              />
            </Field>
            <Field label={m.contactRelation}>
              <input
                value={contact.relation}
                placeholder={m.contactRelationPlaceholder}
                onChange={(e) => setContact(i, { relation: e.target.value })}
              />
            </Field>
            <Field label={m.contactPhone}>
              <input
                type="tel"
                value={contact.phone}
                onChange={(e) => setContact(i, { phone: e.target.value })}
              />
            </Field>
            <button
              className="sa-chip"
              onClick={() =>
                set({ emergencyContacts: draft.emergencyContacts.filter((_, j) => j !== i) })
              }
            >
              {h.delete}
            </button>
          </div>
        ))}
        <button
          className="sa-chip"
          onClick={() =>
            set({
              emergencyContacts: [
                ...draft.emergencyContacts,
                { id: newId(), name: "", relation: "", phone: "" },
              ],
            })
          }
        >
          + {m.addContact}
        </button>
      </section>
    </div>
  );
}
