/**
 * Cure — porting di `PediatricTreatmentsView` / `PediatricTreatmentEditView`.
 *
 * La griglia delle dosi replica la logica di `KBDoseLog`: un documento per
 * (cura, giorno, slot) con id deterministico, così la spunta messa qui è la
 * stessa che il telefono vede e viceversa.
 *
 * Il promemoria della cura resta una notifica locale del dispositivo: qui si
 * mostra il suo stato e lo si trasporta invariato, senza fingere di armarlo.
 */
import { useMemo, useState } from "react";
import Modal from "../Modal";
import {
  DOSAGE_UNITS,
  deleteTreatment,
  doseLogId,
  isScheduledDoseDay,
  saveTreatment,
  setDoseTaken,
  totalDoses,
} from "../../services/health";
import { frequencyLabel } from "../../services/healthContext";
import {
  Field,
  ModuleHeader,
  fmtDate,
  fromDateInput,
  toDateInput,
} from "./shared";

const emptyTreatment = () => ({
  drugName: "",
  activeIngredient: "",
  dosageValue: "",
  dosageUnit: "ml",
  isLongTerm: false,
  durationDays: 5,
  startDate: Date.now(),
  endDate: null,
  dailyFrequency: 1,
  intervalBetweenDosesDays: 0,
  scheduleTimes: ["08:00"],
  isActive: true,
  notes: "",
  reminderEnabled: false,
});

export default function HealthTreatments({
  familyId,
  userId,
  subject,
  treatments,
  activeTreatments,
  doseLogs,
  h,
  locale,
  onError,
  onBack,
}) {
  const c = h.treatments;
  const [editing, setEditing] = useState(null);
  const [openId, setOpenId] = useState(null);
  const [showEnded, setShowEnded] = useState(false);

  const activeIds = useMemo(
    () => new Set(activeTreatments.map((t) => t.id)),
    [activeTreatments]
  );
  const shown = showEnded ? treatments : treatments.filter((t) => activeIds.has(t.id));

  const takenFor = (treatmentId) =>
    doseLogs.filter((l) => l.treatmentId === treatmentId && l.taken).length;

  const remove = async (id) => {
    if (!window.confirm(c.confirmDelete)) return;
    try {
      await deleteTreatment({ familyId, userId, id });
      setOpenId(null);
    } catch (err) {
      onError(err);
    }
  };

  const toggleDose = async (treatment, dayNumber, slotIndex, taken) => {
    try {
      await setDoseTaken({
        familyId,
        userId,
        childId: subject.id,
        treatmentId: treatment.id,
        dayNumber,
        slotIndex,
        scheduledTime: treatment.scheduleTimes[slotIndex] || "",
        taken,
      });
    } catch (err) {
      onError(err);
    }
  };

  return (
    <div className="sa-page">
      <ModuleHeader title={c.title} onBack={onBack} backLabel={h.back}>
        <button className="pw-btn-primary" onClick={() => setEditing(emptyTreatment())}>
          + {c.add}
        </button>
      </ModuleHeader>

      <div className="sa-filters">
        <button
          className={"sa-chip" + (showEnded ? " on" : "")}
          style={showEnded ? { background: "var(--accent)" } : undefined}
          onClick={() => setShowEnded((x) => !x)}
        >
          {c.showEnded}
        </button>
      </div>

      {shown.length === 0 ? (
        <p className="pw-empty">{c.empty}</p>
      ) : (
        <ul className="sa-list">
          {shown.map((t) => {
            const total = totalDoses(t);
            const taken = takenFor(t.id);
            const isOpen = openId === t.id;
            return (
              <li key={t.id} className="sa-item" style={{ flexDirection: "column" }}>
                <div style={{ display: "flex", gap: 12, width: "100%" }}>
                  <span
                    className="sa-item-dot"
                    style={{ background: activeIds.has(t.id) ? "#9973D9" : "var(--muted)" }}
                  />
                  <span className="sa-item-body">
                    <span className="sa-item-title">
                      {t.drugName}
                      {t.activeIngredient ? ` · ${t.activeIngredient}` : ""}
                    </span>
                    <span className="sa-item-meta">
                      {[
                        `${t.dosageValue} ${t.dosageUnit}`,
                        frequencyLabel(t, locale),
                        t.isLongTerm ? c.longTerm : c.days(t.durationDays),
                        `${c.from} ${fmtDate(t.startDate, locale)}`,
                      ].join(" · ")}
                    </span>
                    {total > 0 && (
                      <>
                        <span className="sa-item-meta">{c.progress(taken, total)}</span>
                        <span className="sa-progress">
                          <span
                            style={{ width: `${Math.min(100, (taken / total) * 100)}%` }}
                          />
                        </span>
                      </>
                    )}
                    {t.notes && <span className="sa-item-note">{t.notes}</span>}
                  </span>
                  <span className="sa-item-actions">
                    <button onClick={() => setOpenId(isOpen ? null : t.id)}>
                      {isOpen ? c.hideDoses : c.showDoses}
                    </button>
                    <button onClick={() => setEditing(t)}>{h.edit}</button>
                    <button className="pw-danger" onClick={() => remove(t.id)}>
                      {h.delete}
                    </button>
                  </span>
                </div>

                {isOpen && (
                  <DoseGrid
                    treatment={t}
                    doseLogs={doseLogs}
                    c={c}
                    locale={locale}
                    onToggle={toggleDose}
                  />
                )}
              </li>
            );
          })}
        </ul>
      )}

      {editing && (
        <TreatmentModal
          treatment={editing}
          h={h}
          onClose={() => setEditing(null)}
          onSave={async (draft) => {
            try {
              await saveTreatment({ familyId, userId, childId: subject.id, treatment: draft });
              setEditing(null);
            } catch (err) {
              onError(err);
            }
          }}
        />
      )}
    </div>
  );
}

/**
 * Calendario delle dosi. Le cure a lungo termine non hanno una fine, quindi non
 * hanno una griglia: si mostrano i 14 giorni a partire dall'inizio, come fa il
 * telefono, per non generare righe all'infinito.
 */
function DoseGrid({ treatment, doseLogs, c, locale, onToggle }) {
  const days = treatment.isLongTerm ? 14 : Math.max(1, treatment.durationDays);
  const slots = treatment.intervalBetweenDosesDays > 0 ? 1 : treatment.dailyFrequency;

  const logById = useMemo(() => {
    const map = new Map();
    for (const l of doseLogs) map.set(l.id, l);
    return map;
  }, [doseLogs]);

  const rows = [];
  for (let day = 1; day <= days; day += 1) {
    if (!isScheduledDoseDay(treatment, day - 1)) continue;
    const date = new Date(treatment.startDate);
    date.setDate(date.getDate() + (day - 1));
    rows.push({ day, date: date.getTime() });
  }

  return (
    <div className="sa-doses">
      {rows.map(({ day, date }) => (
        <div key={day} className="sa-dose-day">
          <span className="sa-dose-label">{fmtDate(date, locale)}</span>
          <span className="sa-dose-slots">
            {Array.from({ length: slots }, (_, slotIndex) => {
              const log = logById.get(doseLogId(treatment.id, day, slotIndex));
              const taken = Boolean(log?.taken);
              return (
                <button
                  key={slotIndex}
                  className={"sa-dose" + (taken ? " taken" : "")}
                  onClick={() => onToggle(treatment, day, slotIndex, !taken)}
                >
                  {treatment.scheduleTimes[slotIndex] || c.dose(slotIndex + 1)}
                </button>
              );
            })}
          </span>
        </div>
      ))}
    </div>
  );
}

function TreatmentModal({ treatment, h, onSave, onClose }) {
  const c = h.treatments;
  const [draft, setDraft] = useState({
    ...emptyTreatment(),
    ...treatment,
    activeIngredient: treatment.activeIngredient ?? "",
    notes: treatment.notes ?? "",
    dosageValue: treatment.dosageValue ?? "",
    scheduleTimes: treatment.scheduleTimes?.length
      ? treatment.scheduleTimes
      : ["08:00"],
  });
  const [saving, setSaving] = useState(false);
  const set = (patch) => setDraft((d) => ({ ...d, ...patch }));

  /**
   * Cambiando il numero di dosi al giorno la lista degli orari deve seguirlo:
   * altrimenti restano slot senza orario, e la griglia mostra «Dose 3» al posto
   * dell'ora.
   */
  const setFrequency = (value) => {
    const freq = Math.max(1, Math.min(8, Number(value) || 1));
    const times = [...draft.scheduleTimes];
    while (times.length < freq) times.push("08:00");
    set({ dailyFrequency: freq, scheduleTimes: times.slice(0, freq) });
  };

  const submit = async () => {
    setSaving(true);
    await onSave({
      ...draft,
      dosageValue: Number(String(draft.dosageValue).replace(",", ".")) || 0,
    });
    setSaving(false);
  };

  return (
    <Modal onClose={onClose}>
      <div className="modal-header">
        <button className="modal-text-btn" onClick={onClose}>
          {h.cancel}
        </button>
        <strong>{draft.id ? c.editTitle : c.add}</strong>
        <button
          className="modal-save-btn"
          disabled={saving || !draft.drugName.trim()}
          onClick={submit}
        >
          {h.save}
        </button>
      </div>

      <Field label={c.drugName}>
        <input value={draft.drugName} onChange={(e) => set({ drugName: e.target.value })} />
      </Field>
      <Field label={c.activeIngredient}>
        <input
          value={draft.activeIngredient}
          onChange={(e) => set({ activeIngredient: e.target.value })}
        />
      </Field>

      <div className="sa-grid-2">
        <Field label={c.dosage}>
          <input
            inputMode="decimal"
            value={draft.dosageValue}
            onChange={(e) => set({ dosageValue: e.target.value })}
          />
        </Field>
        <Field label={c.unit}>
          <select
            value={draft.dosageUnit}
            onChange={(e) => set({ dosageUnit: e.target.value })}
          >
            {DOSAGE_UNITS.map((u) => (
              <option key={u} value={u}>
                {u}
              </option>
            ))}
          </select>
        </Field>
        <Field label={c.startDate}>
          <input
            type="date"
            value={toDateInput(draft.startDate)}
            onChange={(e) => set({ startDate: fromDateInput(e.target.value) })}
          />
        </Field>
        <Field label={c.endDate}>
          <input
            type="date"
            value={toDateInput(draft.endDate)}
            onChange={(e) => set({ endDate: fromDateInput(e.target.value) })}
          />
        </Field>
      </div>

      <label className="sa-inline-check">
        <input
          type="checkbox"
          checked={draft.isLongTerm}
          onChange={(e) => set({ isLongTerm: e.target.checked })}
        />
        {c.longTerm}
      </label>

      {!draft.isLongTerm && (
        <Field label={c.durationDays}>
          <input
            type="number"
            min="1"
            value={draft.durationDays}
            onChange={(e) => set({ durationDays: Number(e.target.value) || 1 })}
          />
        </Field>
      )}

      <div className="sa-grid-2">
        <Field label={c.dailyFrequency}>
          <input
            type="number"
            min="1"
            max="8"
            value={draft.dailyFrequency}
            onChange={(e) => setFrequency(e.target.value)}
          />
        </Field>
        <Field label={c.intervalDays}>
          <input
            type="number"
            min="0"
            value={draft.intervalBetweenDosesDays}
            onChange={(e) =>
              set({ intervalBetweenDosesDays: Math.max(0, Number(e.target.value) || 0) })
            }
          />
        </Field>
      </div>
      <p className="pw-hint">{c.intervalHint}</p>

      <p className="modal-label">{c.scheduleTimes}</p>
      <div className="sa-filters">
        {draft.scheduleTimes.map((time, i) => (
          <input
            key={i}
            type="time"
            className="sa-search"
            style={{ maxWidth: 120 }}
            value={time}
            onChange={(e) =>
              set({
                scheduleTimes: draft.scheduleTimes.map((x, j) =>
                  j === i ? e.target.value : x
                ),
              })
            }
          />
        ))}
      </div>

      <label className="sa-inline-check">
        <input
          type="checkbox"
          checked={draft.isActive}
          onChange={(e) => set({ isActive: e.target.checked })}
        />
        {c.active}
      </label>
      <label className="sa-inline-check">
        <input
          type="checkbox"
          checked={draft.reminderEnabled}
          onChange={(e) => set({ reminderEnabled: e.target.checked })}
        />
        {c.reminder}
      </label>
      <p className="pw-hint">{h.remindersOnPhone}</p>

      <Field label={c.notes}>
        <textarea value={draft.notes} onChange={(e) => set({ notes: e.target.value })} />
      </Field>
    </Modal>
  );
}
