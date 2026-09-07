/**
 * Piano Fitness — porting di `FitnessPlanSetupView` e `FitnessPlanView`.
 *
 * Il piano è un JSON annidato (settimane → sedute → esercizi) salvato in un
 * unico campo `payload` sotto `users/{uid}`: cambiare stato a una seduta
 * significa riscrivere il documento intero, ed è quello che fa anche iOS.
 *
 * Restano fuori le due funzioni che dipendono dal telefono: i promemoria delle
 * sedute (notifiche locali) e la riconciliazione con Apple Salute, che chiude
 * una seduta quando l'orologio registra l'allenamento. Qui la seduta si chiude
 * a mano, e il campo `completionSource` lo dichiara (`manual`).
 */
import { useEffect, useMemo, useState } from "react";
import {
  FITNESS_EXPERIENCE,
  FITNESS_GOALS,
  FITNESS_PLACES,
  FITNESS_SPORTS,
  PLAN_WEEKS,
  allSessions,
  deleteFitnessPlan,
  emptyFitnessInput,
  fetchFitnessPlan,
  generateFitnessPlan,
  isInputComplete,
  moveSession,
  rescheduleSession,
  sessionStatusInfo,
  setSessionStatus,
  startOfDayMillis,
  weeklyReport,
} from "../../services/fitnessPlan";
import { isPaidPlan } from "../../services/profile";
import { Field, ModuleHeader, fmtDate, fmtDateLong, label } from "./shared";
import FitnessCalendar from "./FitnessCalendar";

/** Convenzione `Calendar`: 1 = domenica … 7 = sabato, mostrata da lunedì. */
const WEEKDAY_ORDER = [2, 3, 4, 5, 6, 7, 1];

/** `<input type="date">` parla in `yyyy-mm-dd` **locale**: passare per
 *  `toISOString` sposterebbe il giorno a chi sta a est di Greenwich. */
const toInputDate = (millis) => {
  const d = new Date(millis);
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`;
};

/** Mezzogiorno per costruzione: mette al riparo dai fusi, poi il servizio
 *  normalizza comunque a mezzanotte locale. */
const fromInputDate = (value) => {
  const [y, m, d] = value.split("-").map(Number);
  return new Date(y, m - 1, d, 12).getTime();
};

const DAY = 24 * 60 * 60 * 1000;

export default function HealthFitnessPlan({
  familyId,
  userId,
  subject,
  visits,
  exams,
  activeTreatments,
  vaccines,
  profile,
  plan,
  h,
  locale,
  onError,
  onBack,
}) {
  const f = h.fitnessPlan;
  // `plan` è l'abbonamento, `planDocument` il piano di allenamento: due cose
  // diverse che in questa schermata convivono. `plan === null` significa
  // «lettura non ancora arrivata», e in quel caso non si blocca nessuno.
  const blockedByPlan = plan !== null && !isPaidPlan(plan);
  const [planDocument, setPlanDocument] = useState(null);
  const [loading, setLoading] = useState(true);
  const [busy, setBusy] = useState(false);
  const [usage, setUsage] = useState(null);
  const [showForm, setShowForm] = useState(false);
  const [input, setInput] = useState(() => ({
    ...emptyFitnessInput(),
    manualWeightKg: subject.weightKg ? String(subject.weightKg) : "",
    manualHeightCm: subject.heightCm ? String(subject.heightCm) : "",
  }));

  useEffect(() => {
    let cancelled = false;
    setLoading(true);
    fetchFitnessPlan({ uid: userId, childId: subject.id })
      .then((remote) => {
        if (cancelled) return;
        if (remote && !remote.deleted) {
          setPlanDocument(remote);
          setInput(remote.input);
        }
      })
      .catch((err) => !cancelled && onError(err))
      .finally(() => !cancelled && setLoading(false));
    return () => {
      cancelled = true;
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [userId, subject.id]);

  const set = (patch) => setInput((i) => ({ ...i, ...patch }));

  const toggleWeekday = (day) =>
    set({
      trainingWeekdays: input.trainingWeekdays.includes(day)
        ? input.trainingWeekdays.filter((d) => d !== day)
        : [...input.trainingWeekdays, day],
    });

  const toggleSport = (raw) =>
    set({
      preferredSports: input.preferredSports.includes(raw)
        ? input.preferredSports.filter((s) => s !== raw)
        : [...input.preferredSports, raw],
    });

  const generate = async () => {
    setBusy(true);
    try {
      const { document: doc, usage: info } = await generateFitnessPlan({
        uid: userId,
        familyId,
        childId: subject.id,
        subjectName: subject.name,
        birthDate: subject.birthDate,
        input,
        visits,
        exams,
        treatments: activeTreatments,
        vaccines,
        profile,
        subscriptionPlan: plan,
        locale,
      });
      setPlanDocument(doc);
      setUsage(info);
      setShowForm(false);
    } catch (err) {
      const messages = {
        MISSING_HEALTH_DATA: f.missingData,
        NO_TRAINING_DAYS: f.noTrainingDays,
        INVALID_PLAN_FORMAT: f.invalidFormat,
        PLAN_NOT_INCLUDED: f.paidPlansOnly,
      };
      onError(messages[err.message] ? new Error(messages[err.message]) : err);
    } finally {
      setBusy(false);
    }
  };

  const changeStatus = async (sessionId, status) => {
    try {
      const next = await setSessionStatus({
        uid: userId,
        childId: subject.id,
        plan: planDocument,
        sessionId,
        status,
      });
      setPlanDocument(next);
    } catch (err) {
      onError(err);
    }
  };

  /**
   * Sposta la seduta e fa riorganizzare la settimana all'AI, come iOS.
   *
   * Se l'AI non risponde — rete, quota, JSON illeggibile — lo spostamento si
   * applica lo stesso: la data l'ha scelta una persona, non è una proposta.
   */
  const applyMove = async () => {
    if (!moving?.date || busy) return;
    const sessionId = moving.id;
    const newDate = fromInputDate(moving.date);
    setBusy(true);
    setRationale(null);
    try {
      const { document: doc, rationale: why, usage: info } = await rescheduleSession({
        uid: userId,
        familyId,
        childId: subject.id,
        plan: planDocument,
        sessionId,
        newDate,
        subscriptionPlan: plan,
        locale,
      });
      setPlanDocument(doc);
      setUsage(info);
      setRationale(why || null);
      setMoving(null);
    } catch (err) {
      try {
        const fallback = await moveSession({
          uid: userId,
          childId: subject.id,
          plan: planDocument,
          sessionId,
          newDate,
        });
        setPlanDocument(fallback);
        setMoving(null);
        // La seduta è spostata; a mancare è solo la riorganizzazione.
        onError(err);
      } catch (saveErr) {
        onError(saveErr);
      }
    } finally {
      setBusy(false);
    }
  };

  const discard = async () => {
    if (!window.confirm(f.confirmDelete)) return;
    try {
      await deleteFitnessPlan({ uid: userId, childId: subject.id });
      setPlanDocument(null);
      setUsage(null);
    } catch (err) {
      onError(err);
    }
  };

  const sessions = useMemo(
    () => (planDocument ? allSessions(planDocument) : []),
    [planDocument]
  );
  const nextSession = sessions.find((s) => s.status === "planned");
  // Piano o calendario: le due viste che ha iOS.
  const [view, setView] = useState("plan");
  /** Seduta in corso di spostamento: `{ id, date }` con la data in formato
   *  input. Una sola alla volta, come la sheet del telefono. */
  const [moving, setMoving] = useState(null);
  /** Riga del criterio con cui l'AI ha riorganizzato la settimana: è la stessa
   *  frase che il telefono mostra come banner dopo lo spostamento. */
  const [rationale, setRationale] = useState(null);


  /** Una seduta. Serve sia alla vista Piano sia al calendario, che mostra
   *  quelle del giorno selezionato: definirla due volte le farebbe divergere. */
  const renderSession = (s) => {
    const status = sessionStatusInfo(s.status);
    return (
      <div key={s.id} className="sa-session">
        <div className="sa-session-head">
          <span
            className="sa-item-dot"
            style={{ background: status.color, marginTop: 0 }}
          />
          <strong>{s.title}</strong>
          <span className="sa-session-date">
            {[
              fmtDateLong(s.date, locale),
              `${s.durationMinutes} min`,
              s.intensity,
              s.targetKcal ? `${s.targetKcal} kcal` : null,
              label(status, locale),
            ]
              .filter(Boolean)
              .join(" · ")}
          </span>
          <span className="sa-session-actions">
            <button
              className="sa-chip"
              onClick={() =>
                changeStatus(s.id, s.status === "done" ? "planned" : "done")
              }
            >
              {s.status === "done" ? f.undo : f.markDone}
            </button>
            <button
              className="sa-chip"
              onClick={() =>
                changeStatus(s.id, s.status === "skipped" ? "planned" : "skipped")
              }
            >
              {f.markSkipped}
            </button>
            <button
              className="sa-chip"
              onClick={() =>
                setMoving(
                  moving?.id === s.id
                    ? null
                    : // Come iOS: la sheet si apre già sul giorno dopo, che è
                      // quello che si sceglie quasi sempre.
                      { id: s.id, date: toInputDate((s.date || Date.now()) + DAY) }
                )
              }
            >
              {f.move}
            </button>
          </span>
        </div>

        {moving?.id === s.id && (
          <div className="sa-session-move">
            <input
              type="date"
              value={moving.date}
              min={toInputDate(Date.now())}
              onChange={(e) => setMoving({ ...moving, date: e.target.value })}
            />
            <button className="sa-chip primary" disabled={!moving.date || busy} onClick={applyMove}>
              {busy ? f.reorganizing : f.moveConfirm}
            </button>
            <button className="sa-chip" disabled={busy} onClick={() => setMoving(null)}>
              {f.moveCancel}
            </button>
            <span className="sa-item-note">{f.moveHint}</span>
          </div>
        )}

        {s.originalDate && startOfDayMillis(s.originalDate) !== startOfDayMillis(s.date) && (
          <span className="sa-item-note">
            {f.movedFrom(fmtDate(s.originalDate, locale))}
          </span>
        )}

        {s.exercises.length > 0 && (
          <ul className="sa-exercises">
            {s.exercises.map((e) => (
              <li key={e.id}>
                {e.name} <span>{e.detail}</span>
                {e.notes ? <span> · {e.notes}</span> : null}
              </li>
            ))}
          </ul>
        )}

        {s.targets.length > 0 && (
          <div className="sa-targets">
            {s.targets.map((t, i) => (
              <span key={i} className="sa-target">
                {t}
              </span>
            ))}
          </div>
        )}

        {s.notes && <span className="sa-item-note">{s.notes}</span>}
      </div>
    );
  };

  return (
    <div className="sa-page">
      <ModuleHeader title={f.title} onBack={onBack} backLabel={h.back}>
        {planDocument && !showForm && (
          <button className="sa-chip" onClick={() => setShowForm(true)}>
            {f.regenerate}
          </button>
        )}
      </ModuleHeader>

      <p className="pw-hint">{f.intro}</p>

      {loading ? (
        <p className="pw-hint">{h.loading}</p>
      ) : !planDocument || showForm ? (
        <section className="sa-card">
          <h3>{f.setupTitle}</h3>

          <div className="sa-grid-2">
            <Field label={f.goal}>
              <select value={input.goal} onChange={(e) => set({ goal: e.target.value })}>
                {FITNESS_GOALS.map((g) => (
                  <option key={g.raw} value={g.raw}>
                    {g.emoji} {label(g, locale)}
                  </option>
                ))}
              </select>
            </Field>
            <Field label={f.experience}>
              <select
                value={input.experience}
                onChange={(e) => set({ experience: e.target.value })}
              >
                {FITNESS_EXPERIENCE.map((x) => (
                  <option key={x.raw} value={x.raw}>
                    {label(x, locale)}
                  </option>
                ))}
              </select>
            </Field>
            <Field label={f.place}>
              <select value={input.place} onChange={(e) => set({ place: e.target.value })}>
                {FITNESS_PLACES.map((x) => (
                  <option key={x.raw} value={x.raw}>
                    {label(x, locale)}
                  </option>
                ))}
              </select>
            </Field>
            <Field label={f.sessionMinutes}>
              <input
                type="number"
                min="15"
                max="180"
                value={input.sessionMinutes}
                onChange={(e) => set({ sessionMinutes: Number(e.target.value) || 45 })}
              />
            </Field>
            <Field label={f.age}>
              <input
                inputMode="numeric"
                value={input.manualAgeYears}
                onChange={(e) => set({ manualAgeYears: e.target.value })}
              />
            </Field>
            <Field label={f.weight}>
              <input
                inputMode="decimal"
                value={input.manualWeightKg}
                onChange={(e) => set({ manualWeightKg: e.target.value })}
              />
            </Field>
            <Field label={f.height}>
              <input
                inputMode="decimal"
                value={input.manualHeightCm}
                onChange={(e) => set({ manualHeightCm: e.target.value })}
              />
            </Field>
          </div>

          <p className="modal-label">{f.trainingDays}</p>
          <div className="sa-weekdays">
            {WEEKDAY_ORDER.map((day) => {
              const on = input.trainingWeekdays.includes(day);
              return (
                <button
                  key={day}
                  className={"sa-chip" + (on ? " on" : "")}
                  style={on ? { background: "var(--accent)" } : undefined}
                  onClick={() => toggleWeekday(day)}
                >
                  {f.weekdayShort[day]}
                </button>
              );
            })}
          </div>

          <p className="modal-label">{f.sports}</p>
          <div className="sa-weekdays">
            {FITNESS_SPORTS.map((s) => {
              const on = input.preferredSports.includes(s.raw);
              return (
                <button
                  key={s.raw}
                  className={"sa-chip" + (on ? " on" : "")}
                  style={on ? { background: "var(--accent)" } : undefined}
                  onClick={() => toggleSport(s.raw)}
                >
                  {label(s, locale)}
                </button>
              );
            })}
          </div>

          {input.goal === "race" && (
            <div className="sa-grid-2">
              <Field label={f.raceType}>
                <select
                  value={input.raceType || ""}
                  onChange={(e) => set({ raceType: e.target.value || null })}
                >
                  <option value="">—</option>
                  {FITNESS_SPORTS.map((s) => (
                    <option key={s.raw} value={s.raw}>
                      {label(s, locale)}
                    </option>
                  ))}
                </select>
              </Field>
              <Field label={f.raceDate}>
                <input
                  type="date"
                  value={input.raceDate ? new Date(input.raceDate).toISOString().slice(0, 10) : ""}
                  onChange={(e) =>
                    set({
                      raceDate: e.target.value
                        ? new Date(`${e.target.value}T12:00:00`).getTime()
                        : null,
                    })
                  }
                />
              </Field>
              <Field label={f.raceDetail}>
                <input
                  value={input.raceDetail}
                  placeholder={f.raceDetailPlaceholder}
                  onChange={(e) => set({ raceDetail: e.target.value })}
                />
              </Field>
            </div>
          )}

          <Field label={f.notes}>
            <textarea
              value={input.notes}
              placeholder={f.notesPlaceholder}
              onChange={(e) => set({ notes: e.target.value })}
            />
          </Field>

          {blockedByPlan ? (
            <p className="sa-notice warn">{h.upgradeNeeded(plan)}</p>
          ) : (
            <p className="sa-notice warn">{f.paidPlansOnly}</p>
          )}

          <div className="pw-form-actions">
            {planDocument && (
              <button className="sa-chip" onClick={() => setShowForm(false)}>
                {h.cancel}
              </button>
            )}
            <button
              className="pw-btn-primary"
              disabled={busy || blockedByPlan || !isInputComplete(input)}
              onClick={generate}
            >
              {busy ? f.generating : f.generate(PLAN_WEEKS)}
            </button>
          </div>
        </section>
      ) : (
        <>
          {usage && (
            <p className="sa-notice">
              {h.aiUsage(usage.messageUnitsConsumed, usage.usageToday, usage.dailyLimit)}
            </p>
          )}

          {rationale && (
            <p className="sa-notice">
              {rationale}
              <button className="link-btn" onClick={() => setRationale(null)}>
                ✕
              </button>
            </p>
          )}

          <section className="sa-card">
            <h3>{planDocument.subjectName}</h3>
            <p className="sa-item-meta">
              {f.generatedAt(fmtDate(planDocument.generatedAt, locale))} ·{" "}
              {f.startsOn(fmtDate(planDocument.startDate, locale))}
            </p>
            {planDocument.summary && (
              <div className="sa-doc-body">{planDocument.summary}</div>
            )}

            {nextSession && (
              <p className="sa-notice">
                {f.nextSession(nextSession.title, fmtDateLong(nextSession.date, locale))}
              </p>
            )}

            {planDocument.safetyNotes.length > 0 && (
              <div className="sa-doc-section">
                <h4>{f.safetyNotes}</h4>
                <ul className="sa-exercises">
                  {planDocument.safetyNotes.map((note, i) => (
                    <li key={i}>{note}</li>
                  ))}
                </ul>
              </div>
            )}
          </section>

          {/* Le due viste di iOS: il piano per settimane e il calendario. */}
          <div className="pw-chips fit-tabs">
            {[
              ["plan", f.tabPlan],
              ["calendar", f.tabCalendar],
            ].map(([key, tabLabel]) => (
              <button
                key={key}
                className={"pw-chip" + (view === key ? " selected" : "")}
                onClick={() => setView(key)}
              >
                {tabLabel}
              </button>
            ))}
          </div>

          {view === "calendar" && (
            <FitnessCalendar
              plan={planDocument}
              locale={locale}
              f={f}
              renderSession={renderSession}
            />
          )}

          {view === "plan" &&
            planDocument.weeks.map((week) => {
            const report = weeklyReport(planDocument, week.index);
            return (
              <section key={week.index} className="sa-week">
                <div className="sa-week-head">
                  <strong>{f.week(week.index)}</strong>
                  <span>{week.focus}</span>
                  {report && (
                    <span>
                      {f.weekProgress(report.completedSessions, report.plannedSessions)}
                    </span>
                  )}
                </div>

                {week.sessions.map((s) => renderSession(s))}
              </section>
            );
          })}

          <div className="pw-form-actions">
            <button className="pw-danger" onClick={discard}>
              {h.delete}
            </button>
            <button className="pw-btn-primary" onClick={() => setShowForm(true)}>
              {f.regenerate}
            </button>
          </div>

          <p className="pw-hint">{f.phoneOnlyFeatures}</p>
        </>
      )}
    </div>
  );
}
