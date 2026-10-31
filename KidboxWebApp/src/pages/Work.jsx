import { useEffect, useMemo, useRef, useState } from "react";
import { useNavigate } from "react-router-dom";
import { useFamily } from "../FamilyContext";
import { useAuth } from "../AuthContext";
import { useTranslation } from "../i18n/LocaleContext";
import { useFamilyMembers } from "../hooks/useFamilyMembers";
import { usePlan } from "../hooks/usePlan";
import { isPaidPlan } from "../services/profile";
import Modal from "../components/Modal";
import {
  analyzeWorkDocument,
  BadResponseError,
  createLeaveEvents,
  deleteRecord,
  ensureProfile,
  formatDay,
  linkLegacyEvents,
  listenWork,
  NotAWorkDocumentError,
  openWorkFile,
  parseDay,
  reconcileLeaveEvents,
  saveRecord,
  setEmployerIfMissing,
  setSharing,
  UnreadableDocumentError,
  uploadWorkFile,
  WORK_KIND,
} from "../services/work";
import "./Password.css";
import "./Work.css";

const fmtMoney = (v, locale) =>
  new Intl.NumberFormat(locale, { style: "currency", currency: "EUR" }).format(v);
const fmtNum = (v, locale) => new Intl.NumberFormat(locale, { maximumFractionDigits: 2 }).format(v);
const fmtDay = (d, locale) => d.toLocaleDateString(locale, { day: "numeric", month: "short", year: "numeric" });

export default function Work() {
  const { currentFamilyId: familyId } = useFamily();
  const { user } = useAuth();
  const { t, locale } = useTranslation();
  const w = t.work;
  const navigate = useNavigate();
  const members = useFamilyMembers(familyId);
  const plan = usePlan({ familyId, uid: user?.uid });
  const fileRef = useRef(null);

  const [data, setData] = useState({ profiles: [], records: [] });
  const [selectedOwner, setSelectedOwner] = useState(null);
  const [staged, setStaged] = useState(null);        // File in attesa
  const [analyzing, setAnalyzing] = useState(false);
  const [draft, setDraft] = useState(null);
  const [detail, setDetail] = useState(null);
  const [showSharing, setShowSharing] = useState(false);
  const [error, setError] = useState(null);

  const me = user?.uid;
  const paid = isPaidPlan(plan);
  const planKnown = plan !== null;
  const labels = { leave: w.leaveDefault, rol: w.leaveRol, sick: w.leaveSick };

  const memberName = (uid) =>
    uid === me ? (members.find((m) => m.id === me)?.displayName || user?.displayName || w.me)
      : members.find((m) => m.id === uid)?.displayName || w.familyMember;
  const myName = memberName(me) === w.me ? (user?.displayName || w.me) : memberName(me);

  useEffect(() => {
    if (!familyId || !me || !paid) return undefined;
    return listenWork({
      familyId, userId: me,
      onChange: setData,
      // Un errore di Lavoro non è un problema della famiglia: niente `FamilyContext`.
      onError: (err) => setError(err.message),
    });
  }, [familyId, me, paid]);

  const owner = selectedOwner || me;
  const isMine = owner === me;
  const myProfile = data.profiles.find((p) => p.ownerUid === me);
  const owners = useMemo(() => {
    const others = data.profiles
      .filter((p) => p.ownerUid !== me && p.visibilityScope === "members" && p.visibilityMemberIds.includes(me))
      .map((p) => p.ownerUid);
    return [me, ...others];
  }, [data.profiles, me]);

  const records = useMemo(
    () => data.records.filter((r) => r.ownerUid === owner).sort((a, b) => b.referenceDate - a.referenceDate),
    [data.records, owner]
  );
  const latestPayslip = records.find((r) => r.kind === WORK_KIND.PAYSLIP && r.fields)?.fields || null;
  const latestContract = records.find((r) => r.kind === WORK_KIND.CONTRACT && r.fields)?.fields || null;
  const upcomingLeave = useMemo(() => {
    const today = new Date(); today.setHours(0, 0, 0, 0);
    return records.filter((r) => r.kind === WORK_KIND.LEAVE_PLAN && r.fields)
      .flatMap((r) => r.fields.leavePeriods)
      .filter((p) => (parseDay(p.end) || parseDay(p.start) || new Date(0)) >= today)
      .sort((a, b) => parseDay(a.start) - parseDay(b.start));
  }, [records]);

  const periodText = (p) => {
    const s = parseDay(p.start); const e = parseDay(p.end);
    if (!s) return "";
    return e && e > s ? `${fmtDay(s, locale)} – ${fmtDay(e, locale)}` : fmtDay(s, locale);
  };

  // ── Documento in attesa ───────────────────────────────────────────────

  const stage = (file) => { setError(null); setStaged(file || null); };

  const read = async () => {
    if (!staged || analyzing) return;
    setAnalyzing(true);
    setError(null);
    try {
      const result = await analyzeWorkDocument({ familyId, file: staged, labels });
      setDraft({ ...result, file: staged, recordId: null, base: null });
      setStaged(null);
    } catch (err) {
      if (err instanceof NotAWorkDocumentError) setError(w.errorNotWork);
      else if (err instanceof UnreadableDocumentError) setError(w.errorOnlyPdfImages);
      else if (err instanceof BadResponseError) setError(w.errorBadResponse);
      else setError(err?.message || w.errorGeneric);
    } finally {
      setAnalyzing(false);
    }
  };

  // ── Salvataggio ───────────────────────────────────────────────────────

  const save = async (d) => {
    try {
      await ensureProfile({ familyId, userId: me, name: myName });
      let fields = d.fields;
      let reference = d.referenceDate;
      if (d.recordId) {
        if (d.kind === WORK_KIND.LEAVE_PLAN) {
          fields = await reconcileLeaveEvents({ familyId, userId: me, ownerName: myName, base: d.base, fields, labels });
          const first = fields.leavePeriods.map((p) => parseDay(p.start)).filter(Boolean).sort((a, b) => a - b)[0];
          if (first) reference = first;
        }
        await saveRecord({ familyId, userId: me, name: myName, recordId: d.recordId, kind: d.kind, referenceDate: reference, fields });
      } else {
        const shared = myProfile?.visibilityScope === "members" ? myProfile.visibilityMemberIds : [];
        if (d.kind === WORK_KIND.LEAVE_PLAN) {
          const periods = await createLeaveEvents({ familyId, userId: me, ownerName: myName, periods: fields.leavePeriods, labels });
          fields = { ...fields, leavePeriods: periods, eventIds: periods.map((p) => p.eventId).filter(Boolean) };
        }
        const attachmentDocumentId = await uploadWorkFile({
          familyId, userId: me, file: d.file, sharedWith: shared, folderTitle: w.folderTitle,
        });
        await saveRecord({
          familyId, userId: me, name: myName, kind: d.kind, referenceDate: reference, fields, attachmentDocumentId,
        });
        await setEmployerIfMissing({ familyId, userId: me, name: myName, employer: fields.employer });
      }
      setDraft(null);
    } catch (err) {
      setError(err?.name === "MissingFamilyKeyError" ? w.errorUnreadableKey : w.errorSave);
    }
  };

  const startEdit = async (record) => {
    if (!record.fields) return;
    const fields = await linkLegacyEvents({ familyId, fields: record.fields });
    setDetail(null);
    setDraft({
      kind: record.kind, fields, referenceDate: new Date(record.referenceDate),
      file: null, recordId: record.id, base: fields,
    });
  };

  const remove = async (record) => {
    setDetail(null);
    try { await deleteRecord({ familyId, userId: me, record }); } catch (err) { setError(err.message); }
  };

  const openFile = async (record) => {
    try {
      const blob = await openWorkFile({ familyId, userId: me, documentId: record.attachmentDocumentId });
      window.open(URL.createObjectURL(blob), "_blank", "noopener");
    } catch {
      setError(w.errorOpenFile);
    }
  };

  // ── Render ────────────────────────────────────────────────────────────

  if (planKnown && !paid) {
    return (
      <div className="wk-page">
        <header className="pw-header"><h1>{w.title}</h1></header>
        <div className="wk-locked">
          <div className="wk-locked-icon">💼</div>
          <p>{w.lockedBody}</p>
          <button className="pw-btn-primary" onClick={() => navigate("/account/impostazioni")}>{w.upgrade}</button>
        </div>
      </div>
    );
  }

  const sharedWithText = myProfile?.visibilityScope === "members" && myProfile.visibilityMemberIds.length
    ? w.sharedWith.replace("{0}", myProfile.visibilityMemberIds.map(memberName).join(", "))
    : w.onlyMe;

  return (
    <div className="wk-page">
      <header className="pw-header">
        <h1>{w.title}</h1>
        {isMine && (
          <div className="pw-toolbar">
            <button className="pw-btn-primary" disabled={analyzing || !paid} onClick={() => fileRef.current?.click()}>
              + {w.chooseFile}
            </button>
            <input
              ref={fileRef} type="file" hidden accept="application/pdf,image/*"
              onChange={(e) => { stage(e.target.files?.[0]); e.target.value = ""; }}
            />
          </div>
        )}
      </header>

      {error && <p className="error">{error}</p>}
      {!planKnown && <p className="pw-empty">{w.loading}</p>}

      {owners.length > 1 && (
        <div className="wk-chips">
          {owners.map((uid) => (
            <button key={uid} className={`wk-chip ${owner === uid ? "active" : ""}`} onClick={() => setSelectedOwner(uid)}>
              {uid === me ? w.me : memberName(uid)}
            </button>
          ))}
        </div>
      )}

      {isMine && paid && (
        <button className="wk-row-card" onClick={async () => { await ensureProfile({ familyId, userId: me, name: myName }); setShowSharing(true); }}>
          <span className="wk-row-icon">{myProfile?.visibilityScope === "members" ? "👥" : "🔒"}</span>
          <span className="wk-row-text">
            <strong>{sharedWithText}</strong>
            <small>{w.sharingHint}</small>
          </span>
          <span>›</span>
        </button>
      )}

      {isMine && staged && (
        <div className="wk-card">
          <div className="wk-staged">
            <div className="wk-staged-icon">📄</div>
            <div className="wk-staged-text">
              <strong>{w.stagedTitle}</strong>
              <small>{staged.name}</small>
            </div>
            <button className="modal-icon-btn" onClick={() => stage(null)} aria-label={w.removeAttachment}>✕</button>
          </div>
          <button className="pw-btn-primary wk-wide" disabled={analyzing} onClick={read}>
            {analyzing ? w.reading : w.readDocument}
          </button>
          <small className="wk-hint">{w.costHint}</small>
        </div>
      )}

      {latestPayslip && (
        <Card title={w.latestPayslip.replace("{0}", latestPayslip.period || latestPayslip.title)}>
          <Row label={w.fLeaveRemaining} value={latestPayslip.vacationRemaining != null && w.daysFmt.replace("{0}", fmtNum(latestPayslip.vacationRemaining, locale))} />
          <Row label={w.fPermitRemaining} value={latestPayslip.permitHoursRemaining != null && w.hoursFmt.replace("{0}", fmtNum(latestPayslip.permitHoursRemaining, locale))} />
          <Row label={w.fGross} value={latestPayslip.gross != null && fmtMoney(latestPayslip.gross, locale)} />
          <Row label={w.fTaxes} value={latestPayslip.taxes != null && fmtMoney(latestPayslip.taxes, locale)} />
          <Row label={w.fNet} value={latestPayslip.net != null && fmtMoney(latestPayslip.net, locale)} />
          <Row label={w.fTfr} value={latestPayslip.tfr != null && fmtMoney(latestPayslip.tfr, locale)} />
        </Card>
      )}

      {latestContract && (
        <Card title={w.contract}>
          <Row label={w.fContractType} value={latestContract.contractType} />
          <Row label={w.fLevel} value={latestContract.level} />
          <Row label={w.fGrossAnnual} value={latestContract.grossAnnual != null && fmtMoney(latestContract.grossAnnual, locale)} />
          <Row label={w.fStart} value={parseDay(latestContract.startDate) && fmtDay(parseDay(latestContract.startDate), locale)} />
          <Row
            label={w.fEnd}
            value={parseDay(latestContract.endDate)
              ? fmtDay(parseDay(latestContract.endDate), locale)
              : latestContract.contractType.toLowerCase().includes("indeterm") ? w.noEnd : null}
          />
          <Row label={w.fNotice} value={latestContract.noticePeriod} />
        </Card>
      )}

      {upcomingLeave.length > 0 && (
        <Card title={w.plannedLeave}>
          {upcomingLeave.slice(0, 6).map((p) => (
            <Row key={p.id} label={p.label || w.leaveDefault} value={periodText(p)} />
          ))}
        </Card>
      )}

      {!latestPayslip && !latestContract && upcomingLeave.length === 0 && paid && (
        <div className="wk-empty">
          <div className="wk-locked-icon">📄</div>
          <strong>{isMine ? w.emptyMine : w.emptyOther}</strong>
          {isMine && <small>{w.emptyHint}</small>}
        </div>
      )}

      {isMine && (latestPayslip || latestContract || upcomingLeave.length > 0) && <p className="wk-hint">{w.askNote}</p>}

      {records.length > 0 && (
        <section className="wk-list">
          <h2>{w.documents}</h2>
          {records.map((r) => (
            <button key={r.id} className="wk-row-card" onClick={() => setDetail(r)}>
              <span className="wk-row-icon">{r.kind === WORK_KIND.LEAVE_PLAN ? "📅" : r.kind === WORK_KIND.PAYSLIP ? "💶" : "📄"}</span>
              <span className="wk-row-text">
                <strong>{r.fields?.title || (r.kind === WORK_KIND.LEAVE_PLAN ? w.leavePlan : r.kind === WORK_KIND.PAYSLIP ? w.payslip : w.contract)}</strong>
                <small>{fmtDay(new Date(r.referenceDate), locale)}</small>
              </span>
              {r.attachmentDocumentId && <span>📎</span>}
              <span>›</span>
            </button>
          ))}
        </section>
      )}

      {showSharing && (
        <SharingModal
          w={w} me={me} members={members} memberName={memberName}
          current={myProfile?.visibilityScope === "members" ? myProfile.visibilityMemberIds : []}
          onClose={() => setShowSharing(false)}
          onConfirm={async (ids) => {
            setShowSharing(false);
            try { await setSharing({ familyId, userId: me, name: myName, memberIds: ids }); } catch { setError(w.errorSave); }
          }}
        />
      )}
      {draft && (
        <ConfirmModal w={w} locale={locale} labels={labels} draft={draft} onChange={setDraft} onClose={() => setDraft(null)} onSave={() => save(draft)} />
      )}
      {detail && (
        <DetailModal
          w={w} locale={locale} record={detail} canEdit={detail.ownerUid === me} periodText={periodText}
          onClose={() => setDetail(null)} onEdit={() => startEdit(detail)} onDelete={() => remove(detail)}
          onOpenFile={() => openFile(detail)}
        />
      )}
    </div>
  );
}

function Card({ title, children }) {
  return (
    <div className="wk-card">
      <strong className="wk-card-title">{title}</strong>
      {children}
    </div>
  );
}

function Row({ label, value }) {
  if (value === null || value === undefined || value === false || value === "") return null;
  return (
    <div className="wk-row">
      <span>{label}</span>
      <strong>{value}</strong>
    </div>
  );
}

function SharingModal({ w, me, members, memberName, current, onClose, onConfirm }) {
  const [selected, setSelected] = useState(new Set(current));
  const others = members.filter((m) => m.id !== me);
  const toggle = (id) => setSelected((s) => { const n = new Set(s); if (n.has(id)) n.delete(id); else n.add(id); return n; });
  return (
    <Modal onClose={onClose}>
      <div className="modal-header">
        <button className="modal-icon-btn" onClick={onClose}>✕</button>
        <button className="modal-save-btn" onClick={() => onConfirm([...selected])}>{w.save}</button>
      </div>
      <div className="modal-title">{w.sharingTitle}</div>
      {others.length === 0 && <p className="wk-hint">{w.sharingNone}</p>}
      {others.map((m) => (
        <label key={m.id} className="wk-check">
          <span>{memberName(m.id)}</span>
          <input type="checkbox" checked={selected.has(m.id)} onChange={() => toggle(m.id)} />
        </label>
      ))}
      <p className="wk-hint">{w.sharingNote}</p>
    </Modal>
  );
}

function NumField({ label, value, onChange }) {
  const [text, setText] = useState(value == null ? "" : String(value));
  return (
    <label className="wk-field">
      <span>{label}</span>
      <input
        className="modal-field" inputMode="decimal" value={text}
        onChange={(e) => {
          setText(e.target.value);
          const n = Number(e.target.value.replace(",", "."));
          onChange(e.target.value.trim() === "" || !Number.isFinite(n) ? null : n);
        }}
      />
    </label>
  );
}

function TextField({ label, value, onChange }) {
  return (
    <label className="wk-field">
      <span>{label}</span>
      <input className="modal-field" value={value} onChange={(e) => onChange(e.target.value)} />
    </label>
  );
}

function DateInput({ label, value, onChange }) {
  return (
    <label className="wk-field">
      <span>{label}</span>
      <input className="modal-field" type="date" value={value} onChange={(e) => e.target.value && onChange(e.target.value)} />
    </label>
  );
}

function ConfirmModal({ w, draft, onChange, onClose, onSave }) {
  const f = draft.fields;
  const setF = (patch) => onChange({ ...draft, fields: { ...f, ...patch } });
  const setPeriod = (id, patch) =>
    setF({ leavePeriods: f.leavePeriods.map((p) => (p.id === id ? { ...p, ...patch } : p)) });
  const titleOf = draft.kind === WORK_KIND.PAYSLIP ? w.payslip : draft.kind === WORK_KIND.LEAVE_PLAN ? w.leavePlan : w.contract;
  return (
    <Modal onClose={onClose}>
      <div className="modal-header">
        <button className="modal-icon-btn" onClick={onClose}>✕</button>
        <button className="modal-save-btn" onClick={onSave}>{w.save}</button>
      </div>
      <div className="modal-title">{titleOf}</div>
      <TextField label={w.fTitle} value={f.title} onChange={(v) => setF({ title: v })} />
      <TextField label={w.fEmployer} value={f.employer} onChange={(v) => setF({ employer: v })} />
      <DateInput label={w.fReferenceDate} value={formatDay(draft.referenceDate)} onChange={(v) => onChange({ ...draft, referenceDate: parseDay(v) })} />

      {draft.kind === WORK_KIND.LEAVE_PLAN && (
        <>
          <div className="modal-label">{w.periods}</div>
          {f.leavePeriods.map((p) => (
            <div key={p.id} className="wk-period">
              <TextField label={w.periodType} value={p.label} onChange={(v) => setPeriod(p.id, { label: v })} />
              <DateInput label={w.periodFrom} value={p.start} onChange={(v) => setPeriod(p.id, { start: v, end: p.end < v ? v : p.end })} />
              <DateInput label={w.periodTo} value={p.end} onChange={(v) => setPeriod(p.id, { end: v < p.start ? p.start : v })} />
              <label className="wk-check">
                <span>{w.addToCalendar}</span>
                <input type="checkbox" checked={p.inCalendar} onChange={(e) => setPeriod(p.id, { inCalendar: e.target.checked })} />
              </label>
              <button className="modal-text-btn" onClick={() => setF({ leavePeriods: f.leavePeriods.filter((x) => x.id !== p.id) })}>
                🗑 {w.removePeriod}
              </button>
            </div>
          ))}
          <button
            className="modal-text-btn"
            onClick={() => {
              const today = formatDay(new Date());
              setF({ leavePeriods: [...f.leavePeriods, { id: crypto.randomUUID(), start: today, end: today, label: "", inCalendar: true, eventId: null }] });
            }}
          >
            + {w.addPeriod}
          </button>
          <p className="wk-hint">{draft.recordId ? w.leaveFooterEdit : w.leaveFooterNew}</p>
        </>
      )}

      {draft.kind === WORK_KIND.PAYSLIP && (
        <>
          <TextField label={w.fPeriod} value={f.period} onChange={(v) => setF({ period: v })} />
          <NumField label={w.fGrossEur} value={f.gross} onChange={(v) => setF({ gross: v })} />
          <NumField label={w.fNetEur} value={f.net} onChange={(v) => setF({ net: v })} />
          <NumField label={w.fTaxesEur} value={f.taxes} onChange={(v) => setF({ taxes: v })} />
          <NumField label={w.fContributionsEur} value={f.contributions} onChange={(v) => setF({ contributions: v })} />
          <NumField label={w.fTfrEur} value={f.tfr} onChange={(v) => setF({ tfr: v })} />
          <NumField label={w.fLeaveAccruedD} value={f.vacationAccrued} onChange={(v) => setF({ vacationAccrued: v })} />
          <NumField label={w.fLeaveTakenD} value={f.vacationTaken} onChange={(v) => setF({ vacationTaken: v })} />
          <NumField label={w.fLeaveRemainingD} value={f.vacationRemaining} onChange={(v) => setF({ vacationRemaining: v })} />
          <NumField label={w.fPermitAccruedH} value={f.permitHoursAccrued} onChange={(v) => setF({ permitHoursAccrued: v })} />
          <NumField label={w.fPermitRemainingH} value={f.permitHoursRemaining} onChange={(v) => setF({ permitHoursRemaining: v })} />
        </>
      )}

      {draft.kind === WORK_KIND.CONTRACT && (
        <>
          <TextField label={w.fContractType} value={f.contractType} onChange={(v) => setF({ contractType: v })} />
          <TextField label={w.fLevel} value={f.level} onChange={(v) => setF({ level: v })} />
          <NumField label={w.fGrossAnnualEur} value={f.grossAnnual} onChange={(v) => setF({ grossAnnual: v })} />
          <NumField label={w.fLeaveYearD} value={f.vacationDaysPerYear} onChange={(v) => setF({ vacationDaysPerYear: v })} />
          <TextField label={w.fNotice} value={f.noticePeriod} onChange={(v) => setF({ noticePeriod: v })} />
          <DateInput label={w.fStart} value={f.startDate || formatDay(new Date())} onChange={(v) => setF({ startDate: v })} />
          <label className="wk-check">
            <span>{w.fEnd}</span>
            <input type="checkbox" checked={!!f.endDate} onChange={(e) => setF({ endDate: e.target.checked ? formatDay(new Date()) : null })} />
          </label>
          {f.endDate && <DateInput label={w.fEnd} value={f.endDate} onChange={(v) => setF({ endDate: v })} />}
        </>
      )}

      <TextField label={w.fNotes} value={f.notes} onChange={(v) => setF({ notes: v })} />
      <p className="wk-hint">{w.checkValues}</p>
    </Modal>
  );
}

function DetailModal({ w, locale, record, canEdit, periodText, onClose, onEdit, onDelete, onOpenFile }) {
  const f = record.fields;
  const [confirm, setConfirm] = useState(false);
  const title = record.kind === WORK_KIND.PAYSLIP ? w.payslip : record.kind === WORK_KIND.LEAVE_PLAN ? w.leavePlan : w.contract;
  const money = (v) => v != null && fmtMoney(v, locale);
  const dd = (v) => v != null && w.daysFmt.replace("{0}", fmtNum(v, locale));
  const hh = (v) => v != null && w.hoursFmt.replace("{0}", fmtNum(v, locale));
  const day = (s) => parseDay(s) && fmtDay(parseDay(s), locale);
  return (
    <Modal onClose={onClose}>
      <div className="modal-header">
        <button className="modal-icon-btn" onClick={onClose}>✕</button>
        {canEdit && f && <button className="modal-save-btn" onClick={onEdit}>{w.edit}</button>}
      </div>
      <div className="modal-title">{title}</div>
      {record.attachmentDocumentId && (
        <>
          <button className="pw-btn-primary wk-wide" onClick={onOpenFile}>📄 {w.openOriginal}</button>
          <small className="wk-hint">{w.docStaysHere}</small>
        </>
      )}
      {!f ? <p className="wk-hint">{w.unreadable}</p> : (
        <div className="wk-card">
          <Row label={w.fTitle} value={f.title} />
          <Row label={w.fEmployer} value={f.employer} />
          <Row label={w.fPeriod} value={f.period} />
          <Row label={w.fGross} value={money(f.gross)} />
          <Row label={w.fNet} value={money(f.net)} />
          <Row label={w.fTaxes} value={money(f.taxes)} />
          <Row label={w.fContributions} value={money(f.contributions)} />
          <Row label={w.fTfr} value={money(f.tfr)} />
          <Row label={w.fLeaveAccrued} value={dd(f.vacationAccrued)} />
          <Row label={w.fLeaveTaken} value={dd(f.vacationTaken)} />
          <Row label={w.fLeaveRemaining} value={dd(f.vacationRemaining)} />
          <Row label={w.fPermitAccrued} value={hh(f.permitHoursAccrued)} />
          <Row label={w.fPermitRemaining} value={hh(f.permitHoursRemaining)} />
          <Row label={w.fContractType} value={f.contractType} />
          <Row label={w.fLevel} value={f.level} />
          <Row label={w.fGrossAnnual} value={money(f.grossAnnual)} />
          <Row label={w.fLeaveYear} value={dd(f.vacationDaysPerYear)} />
          <Row label={w.fStart} value={day(f.startDate)} />
          <Row label={w.fEnd} value={day(f.endDate)} />
          <Row label={w.fNotice} value={f.noticePeriod} />
          <Row label={w.fNotes} value={f.notes} />
        </div>
      )}
      {f?.leavePeriods?.length > 0 && (
        <div className="wk-card">
          <strong className="wk-card-title">{w.periods}</strong>
          {f.leavePeriods.map((p) => (
            <Row key={p.id} label={(p.label || w.leaveDefault) + (p.inCalendar ? " 📅" : "")} value={periodText(p)} />
          ))}
        </div>
      )}
      {canEdit && (
        confirm ? (
          <div className="wk-confirm">
            <strong>{w.deleteQ}</strong>
            <button className="modal-text-btn" onClick={() => setConfirm(false)}>{w.cancel}</button>
            <button className="modal-save-btn wk-danger" onClick={onDelete}>{w.delete}</button>
          </div>
        ) : (
          <button className="modal-text-btn wk-danger" onClick={() => setConfirm(true)}>🗑 {w.delete}</button>
        )
      )}
    </Modal>
  );
}
