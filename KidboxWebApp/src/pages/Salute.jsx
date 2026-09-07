/**
 * Salute — porting web di `PediatricHomeView`.
 *
 * Il soggetto («childId» sui client nativi) può essere un bambino o un membro
 * adulto: è la stessa convenzione del telefono, dove `childId` è l'id
 * universale del soggetto sanitario.
 *
 * I listener stanno qui e non nei moduli: le stesse quattro collezioni servono
 * alla griglia (contatori), allo storico, alla cartella clinica e ai due piani
 * AI, e duplicarli significherebbe quattro sottoscrizioni Firestore per lo
 * stesso dato.
 *
 * Manca di proposito un solo modulo rispetto a iOS: **Apple App Salute**, che
 * legge HealthKit dal dispositivo e non ha equivalente nel browser.
 */
import { useEffect, useMemo, useRef, useState } from "react";
import { useSearchParams } from "react-router-dom";
import { useFamily } from "../FamilyContext";
import { useAuth } from "../AuthContext";
import { useTranslation } from "../i18n/LocaleContext";
import { useChildren } from "../hooks/useChildren";
import { useFamilyMembers } from "../hooks/useFamilyMembers";
import { usePlan } from "../hooks/usePlan";
import {
  activeTreatments as activeTreatmentsOf,
  listenDoseLogs,
  listenExams,
  listenPediatricProfile,
  listenTreatments,
  listenVaccines,
  listenVisits,
} from "../services/health";
import HealthVisits from "../components/health/HealthVisits";
import HealthTreatments from "../components/health/HealthTreatments";
import HealthVaccines from "../components/health/HealthVaccines";
import HealthExams from "../components/health/HealthExams";
import HealthMedicalRecord from "../components/health/HealthMedicalRecord";
import HealthClinicalRecord from "../components/health/HealthClinicalRecord";
import HealthMealPlan from "../components/health/HealthMealPlan";
import HealthFitnessPlan from "../components/health/HealthFitnessPlan";
import HealthTimeline from "../components/health/HealthTimeline";
import HealthAIChat from "../components/health/HealthAIChat";
import { HEALTH_SCOPES, healthSystemPrompt } from "../services/healthChat";
import "./Salute.css";

const SUBJECT_KEY = "kidbox:healthSubjectId";

const millis = (ts) => (ts?.toMillis ? ts.toMillis() : null);

export default function Salute() {
  const { currentFamilyId } = useFamily();
  const { user } = useAuth();
  const { t, locale } = useTranslation();
  const h = t.health;

  const children = useChildren(currentFamilyId);
  const members = useFamilyMembers(currentFamilyId);
  // Solo per la UX di upsell dei due piani AI: a decidere è il gate server.
  const plan = usePlan({ familyId: currentFamilyId, uid: user?.uid });

  const [subjectId, setSubjectId] = useState(
    () => localStorage.getItem(SUBJECT_KEY) || null
  );
  /**
   * Il modulo aperto vive anche nell'URL (`/salute?modulo=fitnessPlan`): serve
   * ai collegamenti diretti dalla home, che devono portare dentro il modulo e
   * non alla griglia, e fa sì che un ricaricamento rimanga dov'era.
   */
  const [searchParams, setSearchParams] = useSearchParams();
  const [moduleKey, setModuleKey] = useState(() => searchParams.get("modulo"));

  /** Apre o chiude un modulo tenendo allineato l'URL. */
  const openModuleKey = (key) => {
    setModuleKey(key);
    const next = new URLSearchParams(searchParams);
    if (key) next.set("modulo", key);
    else next.delete("modulo");
    setSearchParams(next, { replace: true });
  };
  const [chatOpen, setChatOpen] = useState(false);
  const [error, setError] = useState(null);

  const [visits, setVisits] = useState([]);
  const [exams, setExams] = useState([]);
  const [treatments, setTreatments] = useState([]);
  const [doseLogs, setDoseLogs] = useState([]);
  const [vaccines, setVaccines] = useState([]);
  const [profile, setProfile] = useState(null);

  /**
   * Bambini prima, poi i membri adulti: è l'ordine del selettore su iOS, dove
   * la sezione nasce pediatrica e i profili adulti sono arrivati dopo.
   */
  const subjects = useMemo(() => {
    const fromChildren = children.map((c) => ({
      id: c.id,
      name: c.name || h.unnamedChild,
      kind: "child",
      emoji: "🧒",
      photoURL: null,
      birthDate: millis(c.birthDate),
      weightKg: typeof c.weightKg === "number" ? c.weightKg : null,
      heightCm: typeof c.heightCm === "number" ? c.heightCm : null,
    }));
    const fromMembers = members.map((m) => ({
      id: m.id,
      name: (m.displayName || "").trim() || (m.email || "").trim() || h.unnamedMember,
      kind: "member",
      emoji: "🧑",
      photoURL: m.photoURL || null,
      birthDate: millis(m.birthDate),
      weightKg: null,
      heightCm: null,
    }));
    return [...fromChildren, ...fromMembers];
  }, [children, members, h.unnamedChild, h.unnamedMember]);

  // Il soggetto memorizzato può essere sparito (bambino eliminato, membro
  // uscito): in quel caso si ricade sul primo disponibile.
  useEffect(() => {
    if (subjects.length === 0) return;
    if (!subjects.some((s) => s.id === subjectId)) setSubjectId(subjects[0].id);
  }, [subjects, subjectId]);

  useEffect(() => {
    if (subjectId) localStorage.setItem(SUBJECT_KEY, subjectId);
  }, [subjectId]);

  const subject = subjects.find((s) => s.id === subjectId) || null;

  useEffect(() => {
    if (!currentFamilyId || !subjectId) return undefined;
    const onError = (err) => setError(err.message);
    const args = { familyId: currentFamilyId, childId: subjectId, onError };
    const stops = [
      listenVisits({ ...args, onChange: setVisits }),
      listenExams({ ...args, onChange: setExams }),
      listenTreatments({ ...args, onChange: setTreatments }),
      listenDoseLogs({ ...args, onChange: setDoseLogs }),
      listenVaccines({ ...args, onChange: setVaccines }),
      listenPediatricProfile({ ...args, onChange: setProfile }),
    ];
    return () => stops.forEach((stop) => stop());
  }, [currentFamilyId, subjectId]);

  // Cambiando soggetto i dati del precedente devono sparire subito: senza
  // questo azzeramento la griglia mostra per un istante i contatori sbagliati.
  // Solo un cambio vero di soggetto azzera. Il primo giro e la risoluzione
  // iniziale (memoria vuota → primo soggetto disponibile, che arriva dopo il
  // mount) non lo sono, e chiuderebbero il modulo aperto da un link diretto.
  const previousSubject = useRef(subjectId);
  useEffect(() => {
    const previous = previousSubject.current;
    previousSubject.current = subjectId;
    if (previous === null || previous === subjectId) return;
    setVisits([]);
    setExams([]);
    setTreatments([]);
    setDoseLogs([]);
    setVaccines([]);
    setProfile(null);
    openModuleKey(null);
    setChatOpen(false);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [subjectId]);

  const active = useMemo(
    () => activeTreatmentsOf(treatments, doseLogs),
    [treatments, doseLogs]
  );
  const pendingExams = useMemo(
    () => exams.filter((e) => e.statusRaw === "In attesa" || e.statusRaw === "Prenotato"),
    [exams]
  );
  // Senza un solo dato sanitario la chat non avrebbe contesto: il pulsante
  // resta spento invece di far spendere un messaggio per una risposta vuota.
  const hasHealthData =
    visits.length + exams.length + treatments.length + vaccines.length > 0;

  const shared = {
    familyId: currentFamilyId,
    userId: user?.uid,
    subject,
    visits,
    exams,
    treatments,
    activeTreatments: active,
    doseLogs,
    vaccines,
    profile,
    plan,
    h,
    locale,
    onError: (err) => setError(err?.message || String(err)),
    onBack: () => openModuleKey(null),
  };

  const modules = [
    {
      key: "treatments",
      title: h.modules.treatments,
      sub: active.length > 0 ? h.modules.treatmentsActive(active.length) : h.modules.treatmentsSub,
      emoji: "💊",
      tint: "#9973D9",
      badge: active.length || null,
      render: () => <HealthTreatments {...shared} />,
    },
    {
      key: "vaccines",
      title: h.modules.vaccines,
      sub: h.modules.vaccinesSub(vaccines.length),
      emoji: "💉",
      tint: "#F28C73",
      badge: vaccines.length || null,
      render: () => <HealthVaccines {...shared} />,
    },
    {
      key: "visits",
      title: h.modules.visits,
      sub: h.modules.visitsSub(visits.length),
      emoji: "🩺",
      tint: "#5A99D9",
      badge: visits.length || null,
      render: () => <HealthVisits {...shared} />,
    },
    {
      key: "exams",
      title: h.modules.exams,
      sub:
        pendingExams.length > 0
          ? h.modules.examsPending(pendingExams.length)
          : h.modules.examsSub(exams.length),
      emoji: "🧪",
      tint: "#40A6BF",
      badge: pendingExams.length || null,
      render: () => <HealthExams {...shared} />,
    },
    {
      key: "medicalRecord",
      title: h.modules.medicalRecord,
      sub: h.modules.medicalRecordSub,
      emoji: "📋",
      tint: "#66BFA6",
      render: () => <HealthMedicalRecord {...shared} />,
    },
    {
      key: "clinicalRecord",
      title: h.modules.clinicalRecord,
      sub: h.modules.clinicalRecordSub,
      emoji: "📁",
      tint: "#738CE6",
      render: () => <HealthClinicalRecord {...shared} />,
    },
    {
      key: "mealPlan",
      title: h.modules.mealPlan,
      sub: h.modules.mealPlanSub,
      emoji: "🍽️",
      tint: "#66B880",
      render: () => <HealthMealPlan {...shared} />,
    },
    {
      key: "fitnessPlan",
      title: h.modules.fitnessPlan,
      sub: h.modules.fitnessPlanSub,
      emoji: "🏃",
      tint: "#5A9EE0",
      render: () => <HealthFitnessPlan {...shared} />,
    },
    {
      key: "timeline",
      title: h.modules.timeline,
      sub: h.modules.timelineSub(
        visits.length + exams.length + treatments.length + vaccines.length
      ),
      emoji: "🗂️",
      tint: "#D98C59",
      render: () => <HealthTimeline {...shared} />,
    },
  ];

  const openModule = modules.find((m) => m.key === moduleKey) || null;

  if (!currentFamilyId) {
    return (
      <div className="sa-page">
        <header className="pw-header">
          <h1>{h.title}</h1>
        </header>
        <p className="pw-hint">{h.noFamily}</p>
      </div>
    );
  }

  return (
    <div className="sa-page">
      <header className="pw-header">
        <h1>{h.title}</h1>
      </header>

      {error && <p className="error">{error}</p>}

      {subjects.length > 1 && (
        <div className="sa-subjects">
          {subjects.map((s) => (
            <button
              key={s.id}
              className={"sa-subject" + (s.id === subjectId ? " active" : "")}
              onClick={() => setSubjectId(s.id)}
            >
              <span className="sa-subject-avatar">
                {s.photoURL ? <img src={s.photoURL} alt="" /> : s.emoji}
              </span>
              {s.name}
            </button>
          ))}
        </div>
      )}

      {!subject ? (
        <p className="pw-hint">{h.noSubject}</p>
      ) : openModule ? (
        openModule.render()
      ) : (
        <>
          <div className="sa-hero">
            <span className="sa-hero-avatar">
              {subject.photoURL ? <img src={subject.photoURL} alt="" /> : subject.emoji}
            </span>
            <span className="sa-hero-body">
              <span className="sa-hero-name">{subject.name}</span>
              <span className="sa-hero-sub">{h.subtitle}</span>
            </span>
            <span className="sa-spacer" />
            <button
              className="sa-ask-ai"
              disabled={!hasHealthData}
              onClick={() => setChatOpen(true)}
            >
              ✨ {h.chat.askHealth}
            </button>
          </div>

          <div className="sa-modules">
            {modules.map((m) => (
              <button key={m.key} className="sa-module" onClick={() => openModuleKey(m.key)}>
                {m.badge ? (
                  <span className="sa-module-badge" style={{ background: m.tint }}>
                    {m.badge}
                  </span>
                ) : null}
                <span
                  className="sa-module-icon"
                  style={{ background: `color-mix(in srgb, ${m.tint} 18%, transparent)` }}
                >
                  {m.emoji}
                </span>
                <span className="sa-module-title">{m.title}</span>
                <span className="sa-module-sub">{m.sub}</span>
              </button>
            ))}
          </div>

          <p className="pw-hint">{h.appleHealthOnlyOnPhone}</p>

          {chatOpen && (
            <HealthAIChat
              uid={user?.uid}
              familyId={currentFamilyId}
              kind="health"
              subjectId={subject.id}
              scopeId={HEALTH_SCOPES.health(subject.id)}
              systemPrompt={healthSystemPrompt({
                subjectName: subject.name,
                visits,
                exams,
                treatments: active,
                vaccines,
                profile,
                locale,
              })}
              title={`${h.chat.askHealth} · ${subject.name}`}
              h={h}
              onClose={() => setChatOpen(false)}
            />
          )}
        </>
      )}
    </div>
  );
}
