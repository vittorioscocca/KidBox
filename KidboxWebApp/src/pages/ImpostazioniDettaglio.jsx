/**
 * Pagine di dettaglio delle Impostazioni: una per voce dell'indice, con la
 * freccia per tornare indietro e gli stessi gruppi di righe. Rispecchiano le
 * schermate figlie di `SettingsView` su iOS.
 *
 * Le preferenze dell'account (chat, AI, notifiche) vanno su `users/{uid}` e
 * valgono per tutti i dispositivi. Ciò che il web non può davvero comandare
 * — trascrizione vocale, consigli, AutoFill, recap generati dall'app — è
 * mostrato come impostazione del dispositivo invece di essere finto.
 */
import { useEffect, useState } from "react";
import { Navigate, useParams } from "react-router-dom";
import {
  analyticsConsent,
  CONSENT_DENIED,
  CONSENT_GRANTED,
  setAnalyticsConsent,
} from "../services/analytics";
import { useAuth } from "../AuthContext";
import { useFamily } from "../FamilyContext";
import { useTranslation } from "../i18n/LocaleContext";
import AlexaCard from "../components/AlexaCard";
import { isAlexaAvailable } from "../i18n/alexaAvailability";
import { HEALTH_CONTEXT_PREFS, NOTIFICATION_PREFS } from "../services/settings";
import { deleteAccount, fetchStorageUsage, loadPlan } from "../services/profile";
import { PushNotConfiguredError, disablePush, enablePush, pushStatus } from "../services/push";
import { installId, removeDeviceSession } from "../services/deviceSession";
import { collection, deleteDoc, doc, getDocs } from "firebase/firestore";
import { getFunctions, httpsCallable } from "firebase/functions";
import { app, db } from "../firebase";
import { fetchUsage } from "../services/aiChat";
import { useAccountSettings } from "../hooks/useAccountSettings";
import { DeviceRow, Group, PageHeader, Row, StackRow, SwitchRow, Value } from "../components/SettingsRows";
import {
  AI_CONSENT_KEY,
  ERROR_REPORTS_KEY,
  NOTIFICATION_ICONS,
  PROVIDER_NAMES,
  formatBytes,
} from "./settingsConstants";

const BACK = "/account/impostazioni";

export default function ImpostazioniDettaglio() {
  const { section } = useParams();
  const { t, locale } = useTranslation();
  const s = t.settings;

  const pages = {
    piano: [t.profile.subscription, PianoPage],
    messaggi: [s.messages, MessaggiPage],
    assistente: [s.ai, AssistentePage],
    notifiche: [s.notifications, NotifichePage],
    privacy: [s.privacy, PrivacyPage],
    alexa: isAlexaAvailable(locale) ? [t.alexa.title, AlexaPage] : null,
    sessione: [s.session, SessionePage],
  };
  const entry = pages[section];
  if (!entry) return <Navigate to={BACK} replace />;
  const [title, Page] = entry;

  return (
    <div className="set-page">
      <PageHeader title={title} back={BACK} backLabel={s.title} />
      <Page />
    </div>
  );
}

/* ── Piano e spazio ──────────────────────────────────────────────────────── */

function PianoPage() {
  const { user } = useAuth();
  const { currentFamilyId } = useFamily();
  const { t } = useTranslation();
  const s = t.settings;
  const p = t.profile;
  const [plan, setPlan] = useState(null);
  const [storage, setStorage] = useState(null);

  useEffect(() => {
    if (!user) return;
    loadPlan({ familyId: currentFamilyId, uid: user.uid }).then(setPlan).catch(() => setPlan(null));
  }, [currentFamilyId, user]);

  useEffect(() => {
    if (!currentFamilyId) return;
    // Lo spazio arriva da una function: se non risponde, la pagina mostra il
    // piano lo stesso invece di restare vuota.
    fetchStorageUsage(currentFamilyId).then(setStorage).catch(() => setStorage(null));
  }, [currentFamilyId]);

  const planName = plan ? plan.charAt(0).toUpperCase() + plan.slice(1) : null;
  const usedRatio =
    storage?.quotaBytes > 0 ? Math.min(1, storage.usedBytes / storage.quotaBytes) : 0;

  return (
    <>
      <Group label={p.plan} tone="gold">
        <Row icon="🚀" tint="gold" title={planName ? s.planNamed.replace("%@", planName) : "—"} hint={p.planHint} />
      </Group>
      {storage && (
        <Group label={s.storage}>
          <StackRow
            icon="💾"
            tint="blue"
            title={`${formatBytes(storage.usedBytes)} ${s.storageOf} ${formatBytes(storage.quotaBytes)}`}
            hint={s.storageHint}
          >
            <span className="prof-bar">
              <span style={{ width: `${Math.round(usedRatio * 100)}%` }} />
            </span>
          </StackRow>
          {Object.entries(storage.sections || {})
            .filter(([, bytes]) => bytes > 0)
            .sort((a, b) => b[1] - a[1])
            .map(([key, bytes]) => (
              <Row key={key} icon="▪" tint="plain" title={s.sections[key] || key} right={<Value>{formatBytes(bytes)}</Value>} />
            ))}
        </Group>
      )}
    </>
  );
}

/* ── Messaggi ────────────────────────────────────────────────────────────── */

function MessaggiPage() {
  const { t } = useTranslation();
  const s = t.settings;
  const { prefs, error, busy, toggleChat } = useAccountSettings();
  return (
    <>
      {error && <p className="error">{error}</p>}
      <Group>
        <SwitchRow
          icon="💬"
          tint="blue"
          title={s.chatEnabled}
          hint={s.chatFooter}
          checked={prefs?.chatEnabled ?? true}
          disabled={!prefs || busy}
          onChange={toggleChat}
        />
      </Group>
      <Group label={s.deviceSection}>
        <DeviceRow icon="🎙️" title={s.voiceTranscription} hint={s.voiceTranscriptionHint} label={s.deviceOnly} />
      </Group>
    </>
  );
}

/* ── Assistente AI ───────────────────────────────────────────────────────── */

function AssistentePage() {
  const { currentFamilyId } = useFamily();
  const { t } = useTranslation();
  const s = t.settings;
  const { prefs, error, busy, toggleAI, setHealthContext } = useAccountSettings();
  const [aiUsage, setAiUsage] = useState(null);

  useEffect(() => {
    if (!currentFamilyId || !prefs?.aiEnabled) return;
    fetchUsage(currentFamilyId).then(setAiUsage).catch(() => setAiUsage(null));
  }, [currentFamilyId, prefs?.aiEnabled]);

  const onToggle = (enabled) => {
    // Il consenso è la stessa promessa che l'app chiede prima di accendere
    // l'assistente: senza, l'interruttore non si muove.
    if (enabled && localStorage.getItem(AI_CONSENT_KEY) !== "1") {
      if (!window.confirm(s.aiConsent)) return;
      localStorage.setItem(AI_CONSENT_KEY, "1");
    }
    toggleAI(enabled);
  };

  return (
    <>
      {error && <p className="error">{error}</p>}
      <Group>
        <SwitchRow
          icon="✨"
          tint="purple"
          title={s.aiEnabled}
          hint={s.aiEnabledHint}
          checked={prefs?.aiEnabled ?? false}
          disabled={!prefs || busy}
          onChange={onToggle}
        />
        {aiUsage && (
          <Row
            icon="📊"
            tint="blue"
            title={aiUsage.period === "lifetime" ? s.aiUsageLifetime : s.aiUsage}
            right={
              <Value>
                {aiUsage.usageToday} {s.aiUsageOf} {aiUsage.dailyLimit} {s.aiMessages}
              </Value>
            }
          />
        )}
      </Group>
      {prefs?.aiEnabled && (
        <Group label={s.healthContext}>
          <StackRow icon="🩺" tint="green" hint={s.healthContextFooter}>
            <span className="set-options">
              {HEALTH_CONTEXT_PREFS.map((option) => (
                <button
                  key={option}
                  className={`set-option${prefs.healthContextSendPreference === option ? " selected" : ""}`}
                  disabled={busy}
                  onClick={() => setHealthContext(option)}
                >
                  <strong>{s[option]}</strong>
                  <small>{s[`${option}Detail`]}</small>
                </button>
              ))}
            </span>
          </StackRow>
        </Group>
      )}
      <Group label={s.deviceSection}>
        <DeviceRow icon="📝" title={s.aiRecaps} hint={s.aiRecapsHint} label={s.deviceOnly} />
      </Group>
    </>
  );
}

/* ── Notifiche ───────────────────────────────────────────────────────────── */

function NotifichePage() {
  const { user } = useAuth();
  const { t } = useTranslation();
  const s = t.settings;
  const { prefs, error, setError, busy, setBusy, toggleNotification } = useAccountSettings();
  const [push, setPush] = useState(null);

  useEffect(() => {
    pushStatus().then(setPush);
  }, []);

  const togglePush = async (enabled) => {
    setError(null);
    setBusy(true);
    try {
      if (enabled) {
        const res = await enablePush({ uid: user.uid });
        if (!res.granted) setError(s.pushDenied);
      } else {
        await disablePush({ uid: user.uid });
      }
      setPush(await pushStatus());
    } catch (err) {
      setError(err instanceof PushNotConfiguredError ? s.pushNotConfigured : err.message);
    } finally {
      setBusy(false);
    }
  };

  return (
    <>
      {error && <p className="error">{error}</p>}
      {/* Le push sul browser sono una cosa a sé: gli interruttori sotto
          dicono *cosa* notificare sull'account, questo dice *se* questo
          browser è tra i posti in cui le notifiche arrivano. */}
      <Group label={s.thisBrowser}>
        {push && !push.supported && <Row icon="🔔" tint="grey" title={s.pushOnThisBrowser} hint={s.pushUnsupported} />}
        {push && push.supported && !push.configured && (
          <Row icon="🔔" tint="grey" title={s.pushOnThisBrowser} hint={s.pushNotConfigured} />
        )}
        {push && push.supported && push.configured && (
          <SwitchRow
            icon="🔔"
            title={s.pushOnThisBrowser}
            hint={push.permission === "denied" ? s.pushDenied : s.pushHint}
            checked={push.enabled}
            disabled={busy || push.permission === "denied"}
            onChange={togglePush}
          />
        )}
      </Group>
      <Group label={s.notificationsTitle}>
        <Row icon="📡" tint="blue" title={s.notificationsTitle} hint={s.notificationsHint} />
        {NOTIFICATION_PREFS.map((key) => {
          // Con la chat spenta la riga resta ma non si tocca: riaccenderla
          // manderebbe notifiche per una schermata che non si apre.
          const chatOff = key === "notifyOnNewMessages" && prefs && !prefs.chatEnabled;
          return (
            <SwitchRow
              key={key}
              icon={NOTIFICATION_ICONS[key] || "🔔"}
              tint="plain"
              title={s[key]}
              hint={chatOff ? s.notifyOnNewMessagesOff : undefined}
              checked={prefs ? prefs.notifications[key] && !chatOff : false}
              disabled={!prefs || busy || chatOff}
              onChange={(enabled) => toggleNotification(key, enabled)}
            />
          );
        })}
      </Group>
      <Group label={s.deviceSection}>
        <DeviceRow icon="💡" title={s.nudges} hint={s.nudgesHint} label={s.deviceOnly} />
      </Group>
    </>
  );
}

/* ── Privacy ─────────────────────────────────────────────────────────────── */

function PrivacyPage() {
  const { t } = useTranslation();
  const s = t.settings;
  // Il consenso alle statistiche si revoca con la stessa facilità con cui si
  // concede: è il senso della promessa fatta nel banner.
  const [analyticsOn, setAnalyticsOn] = useState(() => analyticsConsent() === CONSENT_GRANTED);
  const [errorReports, setErrorReports] = useState(() => localStorage.getItem(ERROR_REPORTS_KEY) === "1");

  return (
    <>
      <Group>
        <SwitchRow
          icon="📈"
          tint="blue"
          title={t.consent.settingsTitle}
          hint={t.consent.body}
          checked={analyticsOn}
          onChange={(on) => {
            setAnalyticsConsent(on ? CONSENT_GRANTED : CONSENT_DENIED);
            setAnalyticsOn(on);
          }}
        />
        <SwitchRow
          icon="🐞"
          title={s.errorReports}
          hint={`${s.privacyIntro} ${s.errorReportsHint}`}
          checked={errorReports}
          onChange={(enabled) => {
            localStorage.setItem(ERROR_REPORTS_KEY, enabled ? "1" : "0");
            setErrorReports(enabled);
          }}
        />
      </Group>
      <Group label={s.pwnedTitle}>
        <Row icon="🛡️" tint="green" title={s.pwnedTitle} hint={s.pwnedBody} />
      </Group>
      <Group label={s.deviceSection}>
        <DeviceRow icon="🔑" title={s.passwordsAutofill} hint={s.passwordsAutofillHint} label={s.deviceOnly} />
      </Group>
    </>
  );
}

/* ── Alexa ───────────────────────────────────────────────────────────────── */

function AlexaPage() {
  return (
    <section className="set-group">
      <AlexaCard />
    </section>
  );
}

/* ── Sessione ────────────────────────────────────────────────────────────── */

/**
 * Sessione: l'account, i dispositivi collegati e le uscite.
 *
 * Tutto in una pagina sola perché è una cosa sola — «da dove sono entrato e
 * come ne esco». Prima i dispositivi stavano in una voce a parte sotto
 * Preferenze, e si finiva con due posti che parlavano di sessioni senza
 * nominarsi a vicenda.
 */
function SessionePage() {
  const { user, logout } = useAuth();
  const { t, locale } = useTranslation();
  const s = t.settings;
  const p = t.profile;
  const [deleting, setDeleting] = useState(false);
  const [confirmText, setConfirmText] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState(null);
  const [sessions, setSessions] = useState(null);
  const current = installId();

  useEffect(() => {
    if (!user) return;
    let alive = true;
    (async () => {
      try {
        const snap = await getDocs(collection(db, "users", user.uid, "sessions"));
        if (!alive) return;
        const rows = snap.docs.map((d) => ({ id: d.id, ...d.data() }));
        // Questo dispositivo in cima, poi i più recenti.
        rows.sort((a, b) => {
          if ((a.id === current) !== (b.id === current)) return a.id === current ? -1 : 1;
          return (b.lastSeenAt?.seconds || 0) - (a.lastSeenAt?.seconds || 0);
        });
        setSessions(rows);
      } catch (err) {
        if (alive) setError(err.message);
      }
    })();
    return () => {
      alive = false;
    };
  }, [user, current]);

  const signOutOne = async (session) => {
    if (session.id === current) {
      // Il proprio logout passa da `logout`, che toglie già questa sessione:
      // aspettare il proprio listener lo renderebbe più lento e dipendente
      // dalla rete.
      if (!window.confirm(s.devicesConfirmCurrent)) return;
      await logout();
      return;
    }
    if (!window.confirm(s.devicesConfirmOther)) return;
    setBusy(true);
    setError(null);
    try {
      await deleteDoc(doc(db, "users", user.uid, "sessions", session.id));
      setSessions((prev) => prev.filter((x) => x.id !== session.id));
    } catch (err) {
      setError(err.message);
    } finally {
      setBusy(false);
    }
  };

  const signOutAll = async () => {
    if (!window.confirm(s.devicesConfirmAll)) return;
    setBusy(true);
    setError(null);
    try {
      await httpsCallable(getFunctions(app, "europe-west1"), "signOutAllDevices")();
      await removeDeviceSession(user?.uid).catch(() => {});
      await logout();
    } catch (err) {
      setError(err.message);
      setBusy(false);
    }
  };

  const confirmDelete = async () => {
    setError(null);
    setBusy(true);
    try {
      await deleteAccount();
      await logout();
    } catch (err) {
      setError(err.message);
      setBusy(false);
    }
  };

  const providerName = PROVIDER_NAMES[user?.providerData?.[0]?.providerId] || null;
  const lastLogin = user?.metadata?.lastSignInTime
    ? new Date(user.metadata.lastSignInTime).toLocaleString(
        { it: "it-IT", en: "en-US", fr: "fr-FR", es: "es-ES" }[locale] || "it-IT",
        { day: "2-digit", month: "long", year: "numeric", hour: "2-digit", minute: "2-digit" }
      )
    : null;

  return (
    <>
      {error && <p className="error">{error}</p>}
      <Group label={p.account}>
        <Row icon="✉️" title={p.email} right={<Value>{user?.email || "—"}</Value>} />
        {providerName && <Row icon="🔑" tint="grey" title={s.signedInWith.replace("%@", providerName)} />}
        {lastLogin && <Row icon="🕓" tint="grey" title={p.lastLogin} right={<Value>{lastLogin}</Value>} />}
      </Group>
      <Group label={s.devices} hint={s.devicesHint}>
        {sessions === null && <Row icon="⏳" tint="grey" title={t.common?.loading || "…"} />}
        {sessions?.length === 0 && <Row icon="💻" tint="grey" title={s.devicesEmpty} />}
        {sessions?.map((session) => {
          const when = session.lastSeenAt?.seconds
            ? new Date(session.lastSeenAt.seconds * 1000).toLocaleString(
                { it: "it-IT", en: "en-US", fr: "fr-FR", es: "es-ES" }[locale] || "it-IT",
                { day: "2-digit", month: "long", year: "numeric", hour: "2-digit", minute: "2-digit" }
              )
            : null;
          return (
            <Row
              key={session.id}
              icon={session.platform === "ios" ? "📱" : session.platform === "android" ? "🤖" : "💻"}
              tint="grey"
              title={session.deviceName || s.devicesFallbackName}
              hint={[
                session.id === current ? s.devicesThisOne : null,
                // «Ultima apertura» e non «ultima attività»: il campo si
                // aggiorna alla registrazione della sessione, non a ogni gesto.
                when ? s.devicesLastOpen.replace("%@", when) : null,
              ]
                .filter(Boolean)
                .join(" · ")}
              onClick={busy ? undefined : () => signOutOne(session)}
              chevron
            />
          );
        })}
      </Group>

      {/* Da solo col suo piede, come sui client mobile: è l'uscita imposta dal
          server, e la differenza con il tocco sulla riga qui sopra va letta
          prima di premere. Il logout normale non si ripete qui — si esce
          toccando «Questo dispositivo» nell'elenco, o dalla barra laterale. */}
      <Group hint={s.devicesSignOutAllHint}>
        <Row
          icon="⎋"
          tint="red"
          title={s.devicesSignOutAll}
          onClick={busy ? undefined : signOutAll}
          danger
          chevron
        />
      </Group>

      <Group>
        {!deleting ? (
          <Row icon="🗑" tint="red" title={p.deleteAccount} onClick={() => setDeleting(true)} danger chevron />
        ) : (
          <StackRow icon="🗑" tint="red" title={<span className="set-danger-text">{p.deleteAccount}</span>} hint={p.deleteWarning}>
            {/* Non basta un «sei sicuro?»: qui si perde tutto, e il web è più
                facile da lasciare aperto per sbaglio di un'app sul telefono. */}
            <label className="set-delete-label">
              {p.deleteTypePrompt}
              <input value={confirmText} onChange={(e) => setConfirmText(e.target.value)} placeholder={p.deleteKeyword} />
            </label>
            <span className="set-profile-actions">
              <button
                className="prof-action danger"
                disabled={confirmText.trim().toUpperCase() !== p.deleteKeyword || busy}
                onClick={confirmDelete}
              >
                {p.deleteAccount}
              </button>
              <button
                className="prof-action"
                onClick={() => {
                  setDeleting(false);
                  setConfirmText("");
                }}
              >
                {p.cancel}
              </button>
            </span>
          </StackRow>
        )}
      </Group>
    </>
  );
}
