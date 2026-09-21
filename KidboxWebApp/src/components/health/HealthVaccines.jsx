/**
 * Vaccini — porting di `PediatricVaccinesView`.
 *
 * Lo stato decide quale data conta: somministrato → data di somministrazione,
 * appuntamento fissato → data prevista, da programmare → nessuna delle due.
 * È la stessa regola di `vaccineDate` sui client nativi, e da lì dipende
 * l'ordinamento della lista e la riga nello storico.
 */
import { useMemo, useState } from "react";
import Modal from "../Modal";
import {
  ADMINISTRATION_SITES,
  VACCINE_STATUSES,
  VACCINE_TYPES,
  deleteVaccine,
  saveVaccine,
  vaccineDate,
  vaccineStatusInfo,
  vaccineTypeInfo,
} from "../../services/health";
import { Field, ModuleHeader, fmtDate, fromDateInput, label, toDateInput } from "./shared";
import PeriodFilter, { emptyPeriod, inPeriod } from "./PeriodFilter";

const emptyVaccine = () => ({
  vaccineTypeRaw: "esavalente",
  statusRaw: "administered",
  commercialName: "",
  doseNumber: 1,
  totalDoses: 1,
  administeredDate: Date.now(),
  scheduledDate: null,
  lotNumber: "",
  administeredBy: "",
  administrationSiteRaw: "",
  notes: "",
  reminderOn: false,
  nextDoseDate: null,
});

export default function HealthVaccines({
  familyId,
  userId,
  subject,
  vaccines,
  h,
  locale,
  onError,
  onBack,
}) {
  const w = h.vaccines;
  const [editing, setEditing] = useState(null);
  const [statusFilter, setStatusFilter] = useState(null);
  const [period, setPeriod] = useState(emptyPeriod);
  const [search, setSearch] = useState("");

  const shown = useMemo(() => {
    const q = search.trim().toLowerCase();
    return vaccines.filter((v) => {
      if (statusFilter && v.statusRaw !== statusFilter) return false;
      // Riferimento come su iOS: somministrazione, poi prenotazione, poi
      // ultimo aggiornamento.
      if (!inPeriod(v.administeredDate || v.scheduledDate || v.updatedAt, period)) return false;
      if (!q) return true;
      const type = vaccineTypeInfo(v.vaccineTypeRaw);
      return [
        type?.it,
        type?.en,
        v.vaccineTypeRaw,
        v.commercialName,
        v.lotNumber,
        v.administeredBy,
        v.notes,
      ]
        .filter(Boolean)
        .some((x) => x.toLowerCase().includes(q));
    });
  }, [vaccines, statusFilter, period, search]);

  const remove = async (id) => {
    if (!window.confirm(w.confirmDelete)) return;
    try {
      await deleteVaccine({ familyId, userId, id });
    } catch (err) {
      onError(err);
    }
  };

  return (
    <div className="sa-page">
      <ModuleHeader title={w.title} onBack={onBack} backLabel={h.back}>
        <button className="pw-btn-primary" onClick={() => setEditing(emptyVaccine())}>
          + {w.add}
        </button>
      </ModuleHeader>

      <div className="sa-filters">
        <input
          className="sa-search"
          placeholder={w.searchPlaceholder}
          value={search}
          onChange={(e) => setSearch(e.target.value)}
        />
        {VACCINE_STATUSES.map((s) => {
          const on = statusFilter === s.raw;
          return (
            <button
              key={s.raw}
              className={"sa-chip" + (on ? " on" : "")}
              style={on ? { background: s.color } : undefined}
              onClick={() => setStatusFilter(on ? null : s.raw)}
            >
              {label(s, locale)}
            </button>
          );
        })}
      </div>
      <PeriodFilter value={period} onChange={setPeriod} h={h} tint="#F28C73" />

      {shown.length === 0 ? (
        <p className="pw-empty">{vaccines.length === 0 ? w.empty : h.noResults}</p>
      ) : (
        <ul className="sa-list">
          {shown.map((v) => {
            const status = vaccineStatusInfo(v.statusRaw);
            const type = vaccineTypeInfo(v.vaccineTypeRaw);
            const site = ADMINISTRATION_SITES.find((s) => s.raw === v.administrationSiteRaw);
            return (
              <li key={v.id} className="sa-item">
                <span className="sa-item-dot" style={{ background: status.color }} />
                <span className="sa-item-body">
                  <span className="sa-item-title">
                    {v.commercialName || label(type, locale)}
                    {v.totalDoses > 1 ? ` · ${v.doseNumber}/${v.totalDoses}` : ""}
                  </span>
                  <span className="sa-item-meta">
                    {[
                      label(status, locale),
                      fmtDate(vaccineDate(v), locale),
                      v.commercialName ? label(type, locale) : null,
                      v.lotNumber ? `${w.lot}: ${v.lotNumber}` : null,
                      v.administeredBy,
                      site ? label(site, locale) : null,
                    ]
                      .filter(Boolean)
                      .join(" · ")}
                  </span>
                  {v.nextDoseDate && (
                    <span className="sa-item-meta">
                      {w.nextDose}: {fmtDate(v.nextDoseDate, locale)}
                    </span>
                  )}
                  {v.notes && <span className="sa-item-note">{v.notes}</span>}
                </span>
                <span className="sa-item-actions">
                  <button onClick={() => setEditing(v)}>{h.edit}</button>
                  <button className="pw-danger" onClick={() => remove(v.id)}>
                    {h.delete}
                  </button>
                </span>
              </li>
            );
          })}
        </ul>
      )}

      {editing && (
        <VaccineModal
          vaccine={editing}
          h={h}
          locale={locale}
          onClose={() => setEditing(null)}
          onSave={async (draft) => {
            try {
              await saveVaccine({ familyId, userId, childId: subject.id, vaccine: draft });
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

function VaccineModal({ vaccine, h, locale, onSave, onClose }) {
  const w = h.vaccines;
  const [draft, setDraft] = useState({
    ...emptyVaccine(),
    ...vaccine,
    commercialName: vaccine.commercialName ?? "",
    lotNumber: vaccine.lotNumber ?? "",
    administeredBy: vaccine.administeredBy ?? "",
    administrationSiteRaw: vaccine.administrationSiteRaw ?? "",
    notes: vaccine.notes ?? "",
  });
  const [saving, setSaving] = useState(false);
  const set = (patch) => setDraft((d) => ({ ...d, ...patch }));

  /**
   * Cambiando stato si azzera la data che quello stato non usa: lasciarne due
   * valorizzate insieme confonde l'ordinamento della lista e lo storico.
   */
  const setStatus = (statusRaw) => {
    if (statusRaw === "administered") {
      set({ statusRaw, administeredDate: draft.administeredDate || Date.now(), scheduledDate: null });
    } else if (statusRaw === "scheduled") {
      set({ statusRaw, scheduledDate: draft.scheduledDate || Date.now(), administeredDate: null });
    } else {
      set({ statusRaw, administeredDate: null, scheduledDate: null });
    }
  };

  const submit = async () => {
    setSaving(true);
    await onSave(draft);
    setSaving(false);
  };

  return (
    <Modal onClose={onClose}>
      <div className="modal-header">
        <button className="modal-text-btn" onClick={onClose}>
          {h.cancel}
        </button>
        <strong>{draft.id ? w.editTitle : w.add}</strong>
        <button className="modal-save-btn" disabled={saving} onClick={submit}>
          {h.save}
        </button>
      </div>

      <div className="sa-grid-2">
        <Field label={w.type}>
          <select
            value={draft.vaccineTypeRaw}
            onChange={(e) => set({ vaccineTypeRaw: e.target.value })}
          >
            {VACCINE_TYPES.map((t) => (
              <option key={t.raw} value={t.raw}>
                {label(t, locale)}
              </option>
            ))}
          </select>
        </Field>
        <Field label={w.status}>
          <select value={draft.statusRaw} onChange={(e) => setStatus(e.target.value)}>
            {VACCINE_STATUSES.map((s) => (
              <option key={s.raw} value={s.raw}>
                {label(s, locale)}
              </option>
            ))}
          </select>
        </Field>
      </div>

      <Field label={w.commercialName}>
        <input
          value={draft.commercialName}
          onChange={(e) => set({ commercialName: e.target.value })}
        />
      </Field>

      <div className="sa-grid-2">
        <Field label={w.doseNumber}>
          <input
            type="number"
            min="1"
            value={draft.doseNumber}
            onChange={(e) => set({ doseNumber: Number(e.target.value) || 1 })}
          />
        </Field>
        <Field label={w.totalDoses}>
          <input
            type="number"
            min="1"
            value={draft.totalDoses}
            onChange={(e) => set({ totalDoses: Number(e.target.value) || 1 })}
          />
        </Field>

        {draft.statusRaw === "administered" && (
          <Field label={w.administeredDate}>
            <input
              type="date"
              value={toDateInput(draft.administeredDate)}
              onChange={(e) => set({ administeredDate: fromDateInput(e.target.value) })}
            />
          </Field>
        )}
        {draft.statusRaw === "scheduled" && (
          <Field label={w.scheduledDate}>
            <input
              type="date"
              value={toDateInput(draft.scheduledDate)}
              onChange={(e) => set({ scheduledDate: fromDateInput(e.target.value) })}
            />
          </Field>
        )}

        <Field label={w.nextDose}>
          <input
            type="date"
            value={toDateInput(draft.nextDoseDate)}
            onChange={(e) => set({ nextDoseDate: fromDateInput(e.target.value) })}
          />
        </Field>
        <Field label={w.lot}>
          <input value={draft.lotNumber} onChange={(e) => set({ lotNumber: e.target.value })} />
        </Field>
        <Field label={w.administeredBy}>
          <input
            value={draft.administeredBy}
            onChange={(e) => set({ administeredBy: e.target.value })}
          />
        </Field>
        <Field label={w.site}>
          <select
            value={draft.administrationSiteRaw}
            onChange={(e) => set({ administrationSiteRaw: e.target.value })}
          >
            <option value="">—</option>
            {ADMINISTRATION_SITES.map((s) => (
              <option key={s.raw} value={s.raw}>
                {label(s, locale)}
              </option>
            ))}
          </select>
        </Field>
      </div>

      <label className="sa-inline-check">
        <input
          type="checkbox"
          checked={draft.reminderOn}
          onChange={(e) => set({ reminderOn: e.target.checked })}
        />
        {w.reminder}
      </label>
      <p className="pw-hint">{h.remindersOnPhone}</p>

      <Field label={w.notes}>
        <textarea value={draft.notes} onChange={(e) => set({ notes: e.target.value })} />
      </Field>
    </Modal>
  );
}
