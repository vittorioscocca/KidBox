/**
 * Visite mediche — porting di `PediatricVisitsView` / `PediatricVisitEditView`.
 *
 * Il form ricalca i cinque passi del telefono (medico e data, esito,
 * prescrizioni, appunti, prossima visita) su un'unica pagina: in un browser la
 * navigazione a step non aggiunge niente, i campi sono gli stessi.
 */
import { useMemo, useState } from "react";
import Modal from "../Modal";
import {
  DOCTOR_SPECIALIZATIONS,
  THERAPY_TYPES,
  VISIT_STATUSES,
  deleteVisit,
  saveVisit,
  visitStatusInfo,
} from "../../services/health";
import HealthAIChat from "./HealthAIChat";
import AIFab from "../AIFab";
import { HEALTH_SCOPES, visitsSystemPrompt } from "../../services/healthChat";
import {
  DetailRow,
  Field,
  ModuleHeader,
  fmtDate,
  fromDateInput,
  label,
  newId,
  toDateInput,
} from "./shared";

const emptyVisit = () => ({
  date: Date.now(),
  doctorName: "",
  doctorSpecialization: "",
  reason: "",
  diagnosis: "",
  recommendations: "",
  therapyTypes: [],
  prescribedExams: [],
  asNeededDrugs: [],
  notes: "",
  cost: "",
  nextVisitDate: null,
  nextVisitReason: "",
  visitStatus: "completed",
});

export default function HealthVisits({
  familyId,
  userId,
  subject,
  visits,
  treatments,
  h,
  locale,
  onError,
  onBack,
}) {
  const v = h.visits;
  const [selectedId, setSelectedId] = useState(null);
  const [editing, setEditing] = useState(null);
  const [search, setSearch] = useState("");
  const [statusFilter, setStatusFilter] = useState(null);
  const [chatOpen, setChatOpen] = useState(false);

  const filtered = useMemo(() => {
    const q = search.trim().toLowerCase();
    return visits.filter((item) => {
      if (statusFilter && item.visitStatus !== statusFilter) return false;
      if (!q) return true;
      return [item.reason, item.doctorName, item.diagnosis, item.recommendations]
        .filter(Boolean)
        .some((s) => s.toLowerCase().includes(q));
    });
  }, [visits, search, statusFilter]);

  const selected = visits.find((x) => x.id === selectedId) || null;

  const remove = async (id) => {
    if (!window.confirm(v.confirmDelete)) return;
    try {
      await deleteVisit({ familyId, userId, id });
      setSelectedId(null);
    } catch (err) {
      onError(err);
    }
  };

  return (
    <div className="sa-page">
      <ModuleHeader title={v.title} onBack={onBack} backLabel={h.back}>
        <button className="pw-btn-primary" onClick={() => setEditing(emptyVisit())}>
          + {v.add}
        </button>
      </ModuleHeader>

      <div className="sa-filters">
        <input
          className="sa-search"
          placeholder={v.searchPlaceholder}
          value={search}
          onChange={(e) => setSearch(e.target.value)}
        />
        {VISIT_STATUSES.map((s) => {
          const on = statusFilter === s.code;
          return (
            <button
              key={s.code}
              className={"sa-chip" + (on ? " on" : "")}
              style={on ? { background: s.color } : undefined}
              onClick={() => setStatusFilter(on ? null : s.code)}
            >
              {label(s, locale)}
            </button>
          );
        })}
      </div>

      {filtered.length === 0 ? (
        <p className="pw-empty">{visits.length === 0 ? v.empty : h.noResults}</p>
      ) : (
        <ul className="sa-list">
          {filtered.map((item) => {
            const status = visitStatusInfo(item.visitStatus);
            return (
              <li key={item.id} className="sa-item">
                <span
                  className="sa-item-dot"
                  style={{ background: status?.color || "var(--muted)" }}
                />
                <span className="sa-item-body">
                  <span className="sa-item-title">{item.reason || v.untitled}</span>
                  <span className="sa-item-meta">
                    {[
                      fmtDate(item.date, locale),
                      item.doctorName,
                      item.doctorSpecialization,
                      status ? label(status, locale) : null,
                      item.cost != null ? `€ ${item.cost.toFixed(2)}` : null,
                    ]
                      .filter(Boolean)
                      .join(" · ")}
                  </span>
                </span>
                <span className="sa-item-actions">
                  <button onClick={() => setSelectedId(item.id)}>{h.details}</button>
                  <button onClick={() => setEditing(item)}>{h.edit}</button>
                  <button className="pw-danger" onClick={() => remove(item.id)}>
                    {h.delete}
                  </button>
                </span>
              </li>
            );
          })}
        </ul>
      )}

      {selected && (
        <div className="pw-detail-overlay" onClick={() => setSelectedId(null)}>
          <aside className="pw-detail" onClick={(e) => e.stopPropagation()}>
            <header>
              <h2>{selected.reason || v.untitled}</h2>
              <button onClick={() => setSelectedId(null)}>✕</button>
            </header>

            <DetailRow label={v.date} value={fmtDate(selected.date, locale)} />
            <DetailRow label={v.doctor} value={selected.doctorName} />
            <DetailRow label={v.specialization} value={selected.doctorSpecialization} />
            <DetailRow
              label={v.status}
              value={label(visitStatusInfo(selected.visitStatus), locale)}
            />
            <DetailRow label={v.diagnosis} value={selected.diagnosis} />
            <DetailRow label={v.recommendations} value={selected.recommendations} />
            <DetailRow label={v.therapies} value={selected.therapyTypes.join(", ")} />
            <DetailRow
              label={v.prescribedExams}
              value={selected.prescribedExams
                .map((e) => `${e.name}${e.isUrgent ? " ⚠️" : ""}`)
                .join(", ")}
            />
            <DetailRow
              label={v.asNeededDrugs}
              value={selected.asNeededDrugs
                .map((d) => `${d.drugName} ${d.dosageValue ?? ""} ${d.dosageUnit ?? ""}`.trim())
                .join(", ")}
            />
            <DetailRow label={v.notes} value={selected.notes} />
            <DetailRow
              label={v.cost}
              value={selected.cost != null ? `€ ${selected.cost.toFixed(2)}` : null}
            />
            <DetailRow
              label={v.nextVisit}
              value={
                selected.nextVisitDate
                  ? [fmtDate(selected.nextVisitDate, locale), selected.nextVisitReason]
                      .filter(Boolean)
                      .join(" — ")
                  : null
              }
            />

            <div className="pw-form-actions">
              <button className="pw-danger" onClick={() => remove(selected.id)}>
                {h.delete}
              </button>
              <button className="pw-btn-primary" onClick={() => setEditing(selected)}>
                {h.edit}
              </button>
            </div>
          </aside>
        </div>
      )}

      <AIFab
        label={h.chat.askVisits}
        disabled={visits.length === 0}
        onClick={() => setChatOpen(true)}
      />

      {chatOpen && (
        <HealthAIChat
          uid={userId}
          familyId={familyId}
          kind="visits"
          subjectId={subject.id}
          scopeId={HEALTH_SCOPES.visits(subject.id, subject.kind)}
          systemPrompt={visitsSystemPrompt({
            subjectName: subject.name,
            birthDate: subject.birthDate,
            // La chat parte dalle visite filtrate a schermo, come su iOS: se hai
            // ristretto la lista, è di quelle che stai chiedendo.
            visits: filtered,
            treatments: treatments || [],
          })}
          title={`${h.chat.askVisits} · ${subject.name}`}
          h={h}
          onClose={() => setChatOpen(false)}
        />
      )}

      {editing && (
        <VisitModal
          visit={editing}
          h={h}
          locale={locale}
          onClose={() => setEditing(null)}
          onSave={async (draft) => {
            try {
              await saveVisit({ familyId, userId, childId: subject.id, visit: draft });
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

function VisitModal({ visit, h, locale, onSave, onClose }) {
  const v = h.visits;
  const [draft, setDraft] = useState({
    ...emptyVisit(),
    ...visit,
    cost: visit.cost ?? "",
    doctorName: visit.doctorName ?? "",
    doctorSpecialization: visit.doctorSpecialization ?? "",
    diagnosis: visit.diagnosis ?? "",
    recommendations: visit.recommendations ?? "",
    notes: visit.notes ?? "",
    nextVisitReason: visit.nextVisitReason ?? "",
    therapyTypes: visit.therapyTypes ?? [],
    prescribedExams: visit.prescribedExams ?? [],
    asNeededDrugs: visit.asNeededDrugs ?? [],
  });
  const [saving, setSaving] = useState(false);

  const set = (patch) => setDraft((d) => ({ ...d, ...patch }));

  const toggleTherapy = (raw) =>
    set({
      therapyTypes: draft.therapyTypes.includes(raw)
        ? draft.therapyTypes.filter((x) => x !== raw)
        : [...draft.therapyTypes, raw],
    });

  const submit = async () => {
    setSaving(true);
    const cost = draft.cost === "" ? null : Number(String(draft.cost).replace(",", "."));
    await onSave({
      ...draft,
      cost: Number.isFinite(cost) ? cost : null,
      prescribedExams: draft.prescribedExams.filter((e) => e.name.trim()),
      asNeededDrugs: draft.asNeededDrugs.filter((d) => d.drugName.trim()),
    });
    setSaving(false);
  };

  return (
    <Modal onClose={onClose}>
      <div className="modal-header">
        <button className="modal-text-btn" onClick={onClose}>
          {h.cancel}
        </button>
        <strong>{draft.id ? v.editTitle : v.add}</strong>
        <button
          className="modal-save-btn"
          disabled={saving || !draft.reason.trim()}
          onClick={submit}
        >
          {h.save}
        </button>
      </div>

      <Field label={v.reason}>
        <input value={draft.reason} onChange={(e) => set({ reason: e.target.value })} />
      </Field>

      <div className="sa-grid-2">
        <Field label={v.date}>
          <input
            type="date"
            value={toDateInput(draft.date)}
            onChange={(e) => set({ date: fromDateInput(e.target.value) })}
          />
        </Field>
        <Field label={v.status}>
          <select
            value={draft.visitStatus || ""}
            onChange={(e) => set({ visitStatus: e.target.value || null })}
          >
            <option value="">—</option>
            {VISIT_STATUSES.map((s) => (
              <option key={s.code} value={s.code}>
                {label(s, locale)}
              </option>
            ))}
          </select>
        </Field>
        <Field label={v.doctor}>
          <input
            value={draft.doctorName}
            onChange={(e) => set({ doctorName: e.target.value })}
          />
        </Field>
        <Field label={v.specialization}>
          <select
            value={draft.doctorSpecialization || ""}
            onChange={(e) => set({ doctorSpecialization: e.target.value })}
          >
            <option value="">—</option>
            {DOCTOR_SPECIALIZATIONS.map((s) => (
              <option key={s.raw} value={s.raw}>
                {label(s, locale)}
              </option>
            ))}
          </select>
        </Field>
      </div>

      <Field label={v.diagnosis}>
        <textarea
          value={draft.diagnosis}
          onChange={(e) => set({ diagnosis: e.target.value })}
        />
      </Field>
      <Field label={v.recommendations}>
        <textarea
          value={draft.recommendations}
          onChange={(e) => set({ recommendations: e.target.value })}
        />
      </Field>

      <p className="modal-label">{v.therapies}</p>
      <div className="sa-filters">
        {THERAPY_TYPES.map((tt) => {
          const on = draft.therapyTypes.includes(tt.raw);
          return (
            <button
              key={tt.raw}
              className={"sa-chip" + (on ? " on" : "")}
              style={on ? { background: "var(--accent)" } : undefined}
              onClick={() => toggleTherapy(tt.raw)}
            >
              {label(tt, locale)}
            </button>
          );
        })}
      </div>

      <p className="modal-label">{v.prescribedExams}</p>
      {draft.prescribedExams.map((exam, i) => (
        <div key={exam.id} className="sa-grid-2">
          <Field label={v.examName}>
            <input
              value={exam.name}
              onChange={(e) =>
                set({
                  prescribedExams: draft.prescribedExams.map((x, j) =>
                    j === i ? { ...x, name: e.target.value } : x
                  ),
                })
              }
            />
          </Field>
          <label className="sa-inline-check">
            <input
              type="checkbox"
              checked={Boolean(exam.isUrgent)}
              onChange={(e) =>
                set({
                  prescribedExams: draft.prescribedExams.map((x, j) =>
                    j === i ? { ...x, isUrgent: e.target.checked } : x
                  ),
                })
              }
            />
            {v.urgent}
            <button
              className="sa-chip"
              onClick={() =>
                set({ prescribedExams: draft.prescribedExams.filter((_, j) => j !== i) })
              }
            >
              {h.delete}
            </button>
          </label>
        </div>
      ))}
      <button
        className="sa-chip"
        onClick={() =>
          set({
            prescribedExams: [
              ...draft.prescribedExams,
              { id: newId(), name: "", isUrgent: false },
            ],
          })
        }
      >
        + {v.addExam}
      </button>

      <p className="modal-label">{v.asNeededDrugs}</p>
      {draft.asNeededDrugs.map((drug, i) => (
        <div key={drug.id} className="sa-grid-2">
          <Field label={v.drugName}>
            <input
              value={drug.drugName}
              onChange={(e) =>
                set({
                  asNeededDrugs: draft.asNeededDrugs.map((x, j) =>
                    j === i ? { ...x, drugName: e.target.value } : x
                  ),
                })
              }
            />
          </Field>
          <Field label={v.dosage}>
            <input
              value={drug.dosageValue ?? ""}
              inputMode="decimal"
              onChange={(e) =>
                set({
                  asNeededDrugs: draft.asNeededDrugs.map((x, j) =>
                    j === i
                      ? { ...x, dosageValue: Number(e.target.value.replace(",", ".")) || 0 }
                      : x
                  ),
                })
              }
            />
          </Field>
        </div>
      ))}
      <button
        className="sa-chip"
        onClick={() =>
          set({
            asNeededDrugs: [
              ...draft.asNeededDrugs,
              { id: newId(), drugName: "", dosageValue: 0, dosageUnit: "ml" },
            ],
          })
        }
      >
        + {v.addDrug}
      </button>

      <Field label={v.notes}>
        <textarea value={draft.notes} onChange={(e) => set({ notes: e.target.value })} />
      </Field>

      <div className="sa-grid-2">
        <Field label={v.cost}>
          <input
            inputMode="decimal"
            value={draft.cost}
            onChange={(e) => set({ cost: e.target.value })}
          />
        </Field>
        <Field label={v.nextVisitDate}>
          <input
            type="date"
            value={toDateInput(draft.nextVisitDate)}
            onChange={(e) => set({ nextVisitDate: fromDateInput(e.target.value) })}
          />
        </Field>
      </div>
      <Field label={v.nextVisitReason}>
        <input
          value={draft.nextVisitReason}
          onChange={(e) => set({ nextVisitReason: e.target.value })}
        />
      </Field>

      <p className="pw-hint">{h.remindersOnPhone}</p>
    </Modal>
  );
}
