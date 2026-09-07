/**
 * Piano Alimentare — porting di `MealPlanView`.
 *
 * Il piano vive sotto `users/{uid}`, quindi è privato di chi lo genera: la
 * pagina lo legge all'apertura e lo riscrive solo quando viene rigenerato,
 * senza listener realtime, esattamente come su iOS.
 *
 * Peso e altezza sono obbligatori. Su iOS li fornisce l'app Salute; qui il
 * browser non li ha, e vengono precompilati dai dati del bambino quando ci
 * sono, altrimenti si chiedono nel form.
 */
import { useEffect, useState } from "react";
import {
  MEAL_ACTIVITY_LEVELS,
  MEAL_GOALS,
  deleteMealPlan,
  emptyMealInput,
  fetchMealPlan,
  generateMealPlan,
  parseSections,
} from "../../services/mealPlan";
import { isPaidPlan } from "../../services/profile";
import { Field, ModuleHeader, fmtDate, label } from "./shared";

export default function HealthMealPlan({
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
  const p = h.mealPlan;
  // `plan === null` = lettura non ancora arrivata: non si blocca nessuno, a
  // decidere è comunque il gate server dentro `askAI`.
  const planKnown = plan !== null;
  const blockedByPlan = planKnown && !isPaidPlan(plan);
  const [planDocument, setPlanDocument] = useState(null);
  const [loading, setLoading] = useState(true);
  const [busy, setBusy] = useState(false);
  const [usage, setUsage] = useState(null);
  const [showForm, setShowForm] = useState(false);
  const [input, setInput] = useState(() => ({
    ...emptyMealInput(),
    manualWeightKg: subject.weightKg ? String(subject.weightKg) : "",
    manualHeightCm: subject.heightCm ? String(subject.heightCm) : "",
  }));

  useEffect(() => {
    let cancelled = false;
    setLoading(true);
    fetchMealPlan({ uid: userId, childId: subject.id })
      .then((remote) => {
        if (cancelled) return;
        // `deleted` significa «eliminato da un altro dispositivo»: la pagina
        // deve mostrare il vuoto, non l'ultimo piano che aveva in mano.
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

  const generate = async () => {
    setBusy(true);
    try {
      const { document: doc, usage: info } = await generateMealPlan({
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
        MISSING_HEALTH_DATA: p.missingData,
        PLAN_NOT_INCLUDED: p.paidPlansOnly,
      };
      onError(messages[err.message] ? new Error(messages[err.message]) : err);
    } finally {
      setBusy(false);
    }
  };

  const discard = async () => {
    if (!window.confirm(p.confirmDelete)) return;
    try {
      await deleteMealPlan({ uid: userId, childId: subject.id });
      setPlanDocument(null);
      setUsage(null);
    } catch (err) {
      onError(err);
    }
  };

  const sections = planDocument ? parseSections(planDocument.text) : [];
  const [current, setCurrent] = useState(0);

  // Piano rigenerato: si torna alla prima sezione invece di restare su un
  // indice che ora punta a un'altra cosa.
  useEffect(() => {
    setCurrent(0);
  }, [planDocument?.generatedAt]);

  return (
    <div className="sa-page">
      <ModuleHeader title={p.title} onBack={onBack} backLabel={h.back}>
        {planDocument && !showForm && (
          <button className="sa-chip" onClick={() => setShowForm(true)}>
            {p.regenerate}
          </button>
        )}
      </ModuleHeader>

      <p className="pw-hint">{p.intro}</p>

      {loading ? (
        <p className="pw-hint">{h.loading}</p>
      ) : !planDocument || showForm ? (
        <section className="sa-card">
          <h3>{p.setupTitle}</h3>

          <div className="sa-grid-2">
            <Field label={p.goal}>
              <select value={input.goal} onChange={(e) => set({ goal: e.target.value })}>
                {MEAL_GOALS.map((g) => (
                  <option key={g.raw} value={g.raw}>
                    {label(g, locale)}
                  </option>
                ))}
              </select>
            </Field>
            <Field label={p.activityLevel}>
              <select
                value={input.activityLevel}
                onChange={(e) => set({ activityLevel: e.target.value })}
              >
                {MEAL_ACTIVITY_LEVELS.map((l) => (
                  <option key={l.raw} value={l.raw}>
                    {label(l, locale)}
                  </option>
                ))}
              </select>
            </Field>
            <Field label={p.age}>
              <input
                inputMode="numeric"
                value={input.manualAgeYears}
                onChange={(e) => set({ manualAgeYears: e.target.value })}
              />
            </Field>
            <Field label={p.weight}>
              <input
                inputMode="decimal"
                value={input.manualWeightKg}
                onChange={(e) => set({ manualWeightKg: e.target.value })}
              />
            </Field>
            <Field label={p.height}>
              <input
                inputMode="decimal"
                value={input.manualHeightCm}
                onChange={(e) => set({ manualHeightCm: e.target.value })}
              />
            </Field>
          </div>

          <Field label={p.preferredFoods}>
            <textarea
              value={input.preferredFoods}
              placeholder={p.preferredFoodsPlaceholder}
              onChange={(e) => set({ preferredFoods: e.target.value })}
            />
          </Field>
          <Field label={p.avoidedFoods}>
            <textarea
              value={input.avoidedFoods}
              placeholder={p.avoidedFoodsPlaceholder}
              onChange={(e) => set({ avoidedFoods: e.target.value })}
            />
          </Field>
          <Field label={p.notes}>
            <textarea value={input.notes} onChange={(e) => set({ notes: e.target.value })} />
          </Field>

          {blockedByPlan ? (
            <p className="sa-notice warn">{h.upgradeNeeded(plan)}</p>
          ) : (
            <p className="sa-notice warn">{p.paidPlansOnly}</p>
          )}

          <div className="pw-form-actions">
            {planDocument && (
              <button className="sa-chip" onClick={() => setShowForm(false)}>
                {h.cancel}
              </button>
            )}
            <button
              className="pw-btn-primary"
              disabled={busy || blockedByPlan}
              onClick={generate}
            >
              {busy ? p.generating : p.generate}
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

          <section className="sa-card">
            <h3>{planDocument.subjectName}</h3>
            <p className="sa-item-meta">
              {p.generatedAt(fmtDate(planDocument.generatedAt, locale))} ·{" "}
              {label(
                MEAL_GOALS.find((g) => g.raw === planDocument.input.goal) || MEAL_GOALS[0],
                locale
              )}
            </p>

            {/* Una sezione per volta con le schede in alto, come su iOS: il
                piano è lungo, e in una colonna sola diventa un muro di testo. */}
            {sections.length > 0 && (
              <>
                <div className="pw-chips meal-tabs">
                  {sections.map((sec, i) => (
                    <button
                      key={sec.id}
                      className={"pw-chip" + (i === current ? " selected" : "")}
                      onClick={() => setCurrent(i)}
                    >
                      {sec.title || p.sectionOf(i + 1, sections.length)}
                    </button>
                  ))}
                </div>

                <div className="sa-doc-section">
                  {sections[current]?.title && <h4>{sections[current].title}</h4>}
                  <div className="sa-doc-body">{sections[current]?.body}</div>
                </div>

                <div className="meal-pager">
                  <button
                    type="button"
                    onClick={() => setCurrent((c) => Math.max(0, c - 1))}
                    disabled={current === 0}
                  >
                    ‹
                  </button>
                  <span>{p.sectionOf(current + 1, sections.length)}</span>
                  <button
                    type="button"
                    onClick={() => setCurrent((c) => Math.min(sections.length - 1, c + 1))}
                    disabled={current >= sections.length - 1}
                  >
                    ›
                  </button>
                </div>
              </>
            )}

            <div className="pw-form-actions">
              <button className="pw-danger" onClick={discard}>
                {h.delete}
              </button>
              <button className="pw-btn-primary" onClick={() => setShowForm(true)}>
                {p.regenerate}
              </button>
            </div>
          </section>
        </>
      )}
    </div>
  );
}
