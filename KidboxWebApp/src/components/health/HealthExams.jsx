/**
 * Analisi ed esami — porting di `PediatricExamsView` / `PediatricExamEditView`.
 *
 * L'ordinamento è dal più recente al meno recente (scadenza, altrimenti
 * creazione), lo stesso di visite, cure e vaccini.
 */
import { useMemo, useState } from "react";
import Modal from "../Modal";
import {
  EXAM_STATUSES,
  deleteExam,
  examStatusInfo,
  examTag,
  saveExam,
} from "../../services/health";
import HealthAIChat from "./HealthAIChat";
import HealthAttachments from "./HealthAttachments";
import PeriodFilter, { emptyPeriod, inPeriod } from "./PeriodFilter";
import AIFab from "../AIFab";
import { HEALTH_SCOPES, examsSystemPrompt } from "../../services/healthChat";
import {
  DetailRow,
  Field,
  ModuleHeader,
  fmtDate,
  fromDateInput,
  label,
  toDateInput,
} from "./shared";

const emptyExam = () => ({
  name: "",
  isUrgent: false,
  deadline: null,
  preparation: "",
  notes: "",
  cost: "",
  location: "",
  statusRaw: "In attesa",
  resultText: "",
  resultDate: null,
});

export default function HealthExams({
  familyId,
  userId,
  subject,
  exams,
  attachments,
  h,
  locale,
  onError,
  onBack,
}) {
  const x = h.exams;
  const [editing, setEditing] = useState(null);
  const [selectedId, setSelectedId] = useState(null);
  const [statusFilter, setStatusFilter] = useState(null);
  const [search, setSearch] = useState("");
  const [period, setPeriod] = useState(emptyPeriod);
  const [chatOpen, setChatOpen] = useState(false);

  const now = Date.now();

  const shown = useMemo(() => {
    const q = search.trim().toLowerCase();
    return exams.filter((e) => {
      if (statusFilter && e.statusRaw !== statusFilter) return false;
      // Riferimento come su iOS: la scadenza, altrimenti la creazione.
      if (!inPeriod(e.deadline || e.createdAt, period)) return false;
      if (!q) return true;
      return [e.name, e.location, e.notes, e.resultText]
        .filter(Boolean)
        .some((s) => s.toLowerCase().includes(q));
    });
  }, [exams, statusFilter, search, period]);

  const selected = exams.find((e) => e.id === selectedId) || null;

  const remove = async (id) => {
    if (!window.confirm(x.confirmDelete)) return;
    try {
      await deleteExam({ familyId, id });
      setSelectedId(null);
    } catch (err) {
      onError(err);
    }
  };

  return (
    <div className="sa-page">
      <ModuleHeader title={x.title} onBack={onBack} backLabel={h.back}>
        <button className="pw-btn-primary" onClick={() => setEditing(emptyExam())}>
          + {x.add}
        </button>
      </ModuleHeader>

      <div className="sa-filters">
        <input
          className="sa-search"
          placeholder={x.searchPlaceholder}
          value={search}
          onChange={(e) => setSearch(e.target.value)}
        />
        {EXAM_STATUSES.map((s) => {
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
      <PeriodFilter value={period} onChange={setPeriod} h={h} tint="#40A6BF" />

      {shown.length === 0 ? (
        <p className="pw-empty">{exams.length === 0 ? x.empty : h.noResults}</p>
      ) : (
        <ul className="sa-list">
          {shown.map((e) => {
            const status = examStatusInfo(e.statusRaw);
            const pending = e.statusRaw === "In attesa" || e.statusRaw === "Prenotato";
            const overdue = e.deadline && e.deadline < now && pending;
            return (
              <li key={e.id} className="sa-item">
                <span className="sa-item-dot" style={{ background: status.color }} />
                <span className="sa-item-body">
                  <span className="sa-item-title">
                    {e.name}
                    {e.isUrgent && <span className="sa-tag urgent"> {x.urgent}</span>}
                    {overdue && <span className="sa-tag late"> {x.overdue}</span>}
                  </span>
                  <span className="sa-item-meta">
                    {[
                      label(status, locale),
                      e.deadline ? `${x.deadline}: ${fmtDate(e.deadline, locale)}` : null,
                      e.location,
                      e.cost != null ? `€ ${e.cost.toFixed(2)}` : null,
                    ]
                      .filter(Boolean)
                      .join(" · ")}
                  </span>
                </span>
                <span className="sa-item-actions">
                  <button onClick={() => setSelectedId(e.id)}>{h.details}</button>
                  <button onClick={() => setEditing(e)}>{h.edit}</button>
                  <button className="pw-danger" onClick={() => remove(e.id)}>
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
              <h2>{selected.name}</h2>
              <button onClick={() => setSelectedId(null)}>✕</button>
            </header>
            <DetailRow label={x.status} value={label(examStatusInfo(selected.statusRaw), locale)} />
            <DetailRow label={x.deadline} value={fmtDate(selected.deadline, locale)} />
            <DetailRow label={x.location} value={selected.location} />
            <DetailRow label={x.preparation} value={selected.preparation} />
            <DetailRow label={x.notes} value={selected.notes} />
            <DetailRow
              label={x.cost}
              value={selected.cost != null ? `€ ${selected.cost.toFixed(2)}` : null}
            />
            <DetailRow label={x.resultDate} value={fmtDate(selected.resultDate, locale)} />
            <DetailRow label={x.result} value={selected.resultText} />
            <HealthAttachments
              familyId={familyId}
              userId={userId}
              childId={subject.id}
              tag={examTag(selected.id)}
              attachments={attachments}
              h={h}
              onError={onError}
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
        label={h.chat.askExams}
        disabled={exams.length === 0}
        onClick={() => setChatOpen(true)}
      />

      {chatOpen && (
        <HealthAIChat
          uid={userId}
          familyId={familyId}
          kind="exams"
          subjectId={subject.id}
          scopeId={HEALTH_SCOPES.exams(subject.id)}
          systemPrompt={examsSystemPrompt({ subjectName: subject.name, exams: shown })}
          title={`${h.chat.askExams} · ${subject.name}`}
          h={h}
          onClose={() => setChatOpen(false)}
        />
      )}

      {editing && (
        <ExamModal
          exam={editing}
          h={h}
          locale={locale}
          onClose={() => setEditing(null)}
          onSave={async (draft) => {
            try {
              await saveExam({ familyId, userId, childId: subject.id, exam: draft });
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

function ExamModal({ exam, h, locale, onSave, onClose }) {
  const x = h.exams;
  const [draft, setDraft] = useState({
    ...emptyExam(),
    ...exam,
    preparation: exam.preparation ?? "",
    notes: exam.notes ?? "",
    location: exam.location ?? "",
    resultText: exam.resultText ?? "",
    cost: exam.cost ?? "",
  });
  const [saving, setSaving] = useState(false);
  const set = (patch) => setDraft((d) => ({ ...d, ...patch }));

  const submit = async () => {
    setSaving(true);
    const cost = draft.cost === "" ? null : Number(String(draft.cost).replace(",", "."));
    await onSave({ ...draft, cost: Number.isFinite(cost) ? cost : null });
    setSaving(false);
  };

  return (
    <Modal onClose={onClose}>
      <div className="modal-header">
        <button className="modal-text-btn" onClick={onClose}>
          {h.cancel}
        </button>
        <strong>{draft.id ? x.editTitle : x.add}</strong>
        <button
          className="modal-save-btn"
          disabled={saving || !draft.name.trim()}
          onClick={submit}
        >
          {h.save}
        </button>
      </div>

      <Field label={x.name}>
        <input value={draft.name} onChange={(e) => set({ name: e.target.value })} />
      </Field>

      <div className="sa-grid-2">
        <Field label={x.status}>
          <select value={draft.statusRaw} onChange={(e) => set({ statusRaw: e.target.value })}>
            {EXAM_STATUSES.map((s) => (
              <option key={s.raw} value={s.raw}>
                {label(s, locale)}
              </option>
            ))}
          </select>
        </Field>
        <Field label={x.deadline}>
          <input
            type="date"
            value={toDateInput(draft.deadline)}
            onChange={(e) => set({ deadline: fromDateInput(e.target.value) })}
          />
        </Field>
        <Field label={x.location}>
          <input value={draft.location} onChange={(e) => set({ location: e.target.value })} />
        </Field>
        <Field label={x.cost}>
          <input
            inputMode="decimal"
            value={draft.cost}
            onChange={(e) => set({ cost: e.target.value })}
          />
        </Field>
      </div>

      <label className="sa-inline-check">
        <input
          type="checkbox"
          checked={draft.isUrgent}
          onChange={(e) => set({ isUrgent: e.target.checked })}
        />
        {x.urgent}
      </label>

      <Field label={x.preparation}>
        <textarea
          value={draft.preparation}
          onChange={(e) => set({ preparation: e.target.value })}
        />
      </Field>
      <Field label={x.notes}>
        <textarea value={draft.notes} onChange={(e) => set({ notes: e.target.value })} />
      </Field>

      <Field label={x.resultDate}>
        <input
          type="date"
          value={toDateInput(draft.resultDate)}
          onChange={(e) => set({ resultDate: fromDateInput(e.target.value) })}
        />
      </Field>
      <Field label={x.result}>
        <textarea
          value={draft.resultText}
          onChange={(e) => set({ resultText: e.target.value })}
        />
      </Field>
      <p className="pw-hint">{x.resultHint}</p>
    </Modal>
  );
}
