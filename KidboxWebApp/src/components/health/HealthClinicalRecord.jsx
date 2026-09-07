/**
 * Cartella clinica — porting di `ClinicalRecordView`.
 *
 * Due passaggi come su iOS: la bozza nativa si costruisce dai soli dati
 * dell'app, senza AI e senza costi; la sintesi narrativa costa una generazione
 * (Sonnet lato server) e va chiesta esplicitamente.
 *
 * Il documento resta sul dispositivo, come su iOS: lì `ClinicalRecordStore`
 * scrive nei file locali, qui in `localStorage`. Non c'è una collezione
 * condivisa dove i client nativi andrebbero a cercarlo.
 */
import { useMemo, useState } from "react";
import {
  buildNativeReport,
  deleteReport,
  enhanceWithAI,
  loadReport,
  printReport,
  saveReport,
} from "../../services/clinicalRecord";
import { ModuleHeader, fmtDate } from "./shared";

export default function HealthClinicalRecord({
  familyId,
  subject,
  visits,
  exams,
  activeTreatments,
  vaccines,
  profile,
  h,
  locale,
  onError,
  onBack,
}) {
  const r = h.clinicalRecord;
  const [report, setReport] = useState(() => loadReport(subject.id));
  const [busy, setBusy] = useState(false);
  const [usage, setUsage] = useState(null);

  const nativeReport = useMemo(
    () =>
      buildNativeReport({
        subjectName: subject.name,
        birthDate: subject.birthDate,
        profile,
        visits,
        exams,
        treatments: activeTreatments,
        vaccines,
      }),
    [subject, profile, visits, exams, activeTreatments, vaccines]
  );

  const hasData =
    visits.length + exams.length + activeTreatments.length + vaccines.length > 0;

  const showNative = () => {
    saveReport(subject.id, nativeReport);
    setReport(nativeReport);
    setUsage(null);
  };

  const generate = async () => {
    setBusy(true);
    try {
      const { report: enhanced, usage: info } = await enhanceWithAI({
        familyId,
        subjectName: subject.name,
        nativeReport,
        visits,
        exams,
        treatments: activeTreatments,
        vaccines,
        profile,
        locale,
      });
      saveReport(subject.id, enhanced);
      setReport(enhanced);
      setUsage(info);
    } catch (err) {
      // Il server rifiuta i piani senza AI con `permission-denied`: il messaggio
      // che arriva di lì è già quello giusto da mostrare.
      onError(err);
    } finally {
      setBusy(false);
    }
  };

  const discard = () => {
    if (!window.confirm(r.confirmDelete)) return;
    deleteReport(subject.id);
    setReport(null);
    setUsage(null);
  };

  return (
    <div className="sa-page">
      <ModuleHeader title={r.title} onBack={onBack} backLabel={h.back}>
        {report && (
          <button className="sa-chip" onClick={() => printReport(report)}>
            {r.print}
          </button>
        )}
      </ModuleHeader>

      <p className="pw-hint">{r.intro}</p>
      <p className="sa-notice warn">{r.localOnly}</p>

      {!hasData ? (
        <p className="pw-empty">{r.noData}</p>
      ) : (
        <div className="sa-filters">
          <button className="sa-chip" onClick={showNative} disabled={busy}>
            {r.buildNative}
          </button>
          <button className="pw-btn-primary" onClick={generate} disabled={busy}>
            {busy ? r.generating : r.generateAI}
          </button>
        </div>
      )}

      {usage && (
        <p className="sa-notice">
          {h.aiUsage(usage.messageUnitsConsumed, usage.usageToday, usage.dailyLimit)}
        </p>
      )}

      {report && (
        <section className="sa-card">
          <h3>
            {report.subjectName} ·{" "}
            {report.source === "aiEnhanced" ? r.sourceAI : r.sourceNative}
          </h3>
          <p className="sa-item-meta">
            {r.generatedAt(fmtDate(report.generatedAt, locale))}
          </p>

          {report.areas.map((area) => (
            <div key={area.id} className="sa-doc-section">
              <h4>{area.title}</h4>
              <div className="sa-doc-body">{area.narrative}</div>
            </div>
          ))}

          <div className="pw-form-actions">
            <button className="pw-danger" onClick={discard}>
              {h.delete}
            </button>
          </div>
        </section>
      )}
    </div>
  );
}
