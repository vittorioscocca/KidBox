/**
 * Impostazioni. Rispecchia `SettingsView` di iOS e le sue schermate figlie,
 * appiattite in una pagina sola: sul web una colonna di card si legge tutta
 * insieme, e la navigazione a livelli del telefono qui sarebbe solo attrito.
 *
 * Le preferenze dell'account (notifiche, chat, AI) vanno su `users/{uid}` e
 * valgono per tutti i dispositivi; tema e lingua restano di questo browser,
 * come su iOS restano del telefono. Ciò che il web non può davvero comandare
 * — trascrizione vocale, consigli, AutoFill, recap generati dall'app — è
 * mostrato come impostazione del dispositivo invece di essere finto.
 */
import { useEffect, useState } from "react";
import { Link } from "react-router-dom";
import { useAuth } from "../AuthContext";
import { useFamily } from "../FamilyContext";
import { useTranslation } from "../i18n/LocaleContext";
import { THEMES, useTheme } from "../ThemeContext";
import {
  HEALTH_CONTEXT_PREFS,
  LANGUAGES,
  NOTIFICATION_PREFS,
  loadSettings,
  setAIEnabled,
  setChatEnabled,
  setHealthContextSendPreference,
  setNotificationLanguage,
  setNotificationPref,
} from "../services/settings";
import { fetchStorageUsage, loadPlan } from "../services/profile";
import { PushNotConfiguredError, disablePush, enablePush, pushStatus } from "../services/push";
import { fetchUsage } from "../services/aiChat";
import "./Impostazioni.css";

const GUIDE_URL = "https://kidboxapp.com/guide.html";
const SITE_URL = "https://kidboxapp.com";
const SUPPORT_MAIL = "supporto@kidboxapp.com";
const AI_CONSENT_KEY = "kidbox:aiConsent";
const ERROR_REPORTS_KEY = "kidbox:errorReports";

function formatBytes(bytes) {
  if (!bytes) return "0 B";
  const units = ["B", "KB", "MB", "GB", "TB"];
  let value = bytes;
  let i = 0;
  while (value >= 1024 && i < units.length - 1) {
    value /= 1024;
    i += 1;
  }
  return `${value.toFixed(i === 0 ? 0 : 1)} ${units[i]}`;
}

function Switch({ checked, disabled, onChange, label, hint }) {
  return (
    <label className={`set-row${disabled ? " disabled" : ""}`}>
      <span className="set-row-text">
        <strong>{label}</strong>
        {hint && <small>{hint}</small>}
      </span>
      <input
        type="checkbox"
        className="set-switch"
        checked={checked}
        disabled={disabled}
        onChange={(e) => onChange(e.target.checked)}
      />
    </label>
  );
}

export default function Impostazioni() {
  const { user } = useAuth();
  const { currentFamily, currentFamilyId } = useFamily();
  const { t, locale, setLocale } = useTranslation();
  const { theme, setTheme } = useTheme();
  const s = t.settings;

  const [prefs, setPrefs] = useState(null);
  const [plan, setPlan] = useState(null);
  const [storage, setStorage] = useState(null);
  const [aiUsage, setAiUsage] = useState(null);
  const [error, setError] = useState(null);
  const [busy, setBusy] = useState(false);
  const [push, setPush] = useState(null);
  const [errorReports, setErrorReports] = useState(
    () => localStorage.getItem(ERROR_REPORTS_KEY) === "1"
  );

  useEffect(() => {
    if (!user) return;
    loadSettings(user.uid).then(setPrefs).catch((err) => setError(err.message));
  }, [user]);

  useEffect(() => {
    pushStatus().then(setPush);
  }, []);

  useEffect(() => {
    if (!user) return;
    loadPlan({ familyId: currentFamilyId, uid: user.uid }).then(setPlan).catch(() => setPlan(null));
  }, [currentFamilyId, user]);

  useEffect(() => {
    if (!currentFamilyId) return;
    // Spazio e utilizzo AI arrivano da due function: se non rispondono, la
    // pagina resta usabile e la card semplicemente non compare.
    fetchStorageUsage(currentFamilyId).then(setStorage).catch(() => setStorage(null));
  }, [currentFamilyId]);

  useEffect(() => {
    if (!currentFamilyId || !prefs?.aiEnabled) return;
    fetchUsage(currentFamilyId).then(setAiUsage).catch(() => setAiUsage(null));
  }, [currentFamilyId, prefs?.aiEnabled]);

  /**
   * Aggiornamento ottimistico con rollback, come i ViewModel di iOS:
   * l'interruttore si muove subito e torna indietro solo se la scrittura
   * fallisce davvero.
   */
  const commit = async (patch, write) => {
    const previous = prefs;
    setPrefs({ ...prefs, ...patch });
    setError(null);
    setBusy(true);
    try {
      await write();
    } catch (err) {
      setPrefs(previous);
      setError(err.message);
    } finally {
      setBusy(false);
    }
  };

  const toggleNotification = (key, enabled) =>
    commit({ notifications: { ...prefs.notifications, [key]: enabled } }, () =>
      setNotificationPref(user.uid, key, enabled)
    );

  const toggleChat = async (enabled) => {
    const previous = prefs;
    setPrefs({ ...prefs, chatEnabled: enabled });
    setError(null);
    setBusy(true);
    try {
      const notify = await setChatEnabled(
        user.uid,
        enabled,
        prefs.notifications.notifyOnNewMessages
      );
      setPrefs((p) => ({
        ...p,
        chatEnabled: enabled,
        notifications: { ...p.notifications, notifyOnNewMessages: notify },
      }));
    } catch (err) {
      setPrefs(previous);
      setError(err.message);
    } finally {
      setBusy(false);
    }
  };

  const toggleAI = (enabled) => {
    // Il consenso è la stessa promessa che l'app chiede prima di accendere
    // l'assistente: senza, l'interruttore non si muove.
    if (enabled && localStorage.getItem(AI_CONSENT_KEY) !== "1") {
      if (!window.confirm(s.aiConsent)) return;
      localStorage.setItem(AI_CONSENT_KEY, "1");
    }
    commit({ aiEnabled: enabled }, () => setAIEnabled(user.uid, enabled));
  };

  const chooseLanguage = (code) => {
    setLocale(code);
    // Il server traduce le push leggendo `notificationLanguage`: senza
    // l'allineamento resterebbero nella lingua precedente.
    if (user) setNotificationLanguage(user.uid, code).catch(() => {});
  };

  const usedRatio =
    storage?.quotaBytes > 0 ? Math.min(1, storage.usedBytes / storage.quotaBytes) : 0;

  return (
    <div className="set-page">
      <header className="pw-header">
        <h1>{s.title}</h1>
      </header>

      {error && <p className="error">{error}</p>}

      {/* Famiglia in cima, come su iOS: di che famiglia faccio parte è la prima
          cosa che si viene a cercare qui, e una riga in fondo non lo direbbe. */}
      <section className="set-card set-family">
        <span className="set-row-text">
          <small>{t.family.title}</small>
          <strong>{currentFamily?.name || t.family.noFamily}</strong>
        </span>
        <Link className="prof-action" to="/account/family">
          👪 {s.open}
        </Link>
      </section>

      {/* ── Tema ─────────────────────────────────────────────────────────── */}
      <section className="set-card">
        <h2>{s.appearance}</h2>
        <div className="set-choices">
          {THEMES.map((option) => (
            <button
              key={option.value}
              className={`set-choice${theme === option.value ? " selected" : ""}`}
              onClick={() => setTheme(option.value)}
            >
              <span>{option.icon}</span>
              {s[option.value]}
            </button>
          ))}
        </div>
        <p className="pw-hint">{s.appearanceHint}</p>
      </section>

      {/* ── Lingua ───────────────────────────────────────────────────────── */}
      <section className="set-card">
        <h2>{s.language}</h2>
        <div className="set-choices">
          {LANGUAGES.map((lang) => (
            <button
              key={lang.code}
              className={`set-choice${locale === lang.code ? " selected" : ""}`}
              onClick={() => chooseLanguage(lang.code)}
            >
              <span>{lang.flag}</span>
              {lang.label}
            </button>
          ))}
        </div>
        <p className="pw-hint">{s.languageHint}</p>
      </section>

      {/* ── Messaggi ─────────────────────────────────────────────────────── */}
      <section className="set-card">
        <h2>{s.messages}</h2>
        <Switch
          label={s.chatEnabled}
          hint={s.chatEnabledHint}
          checked={prefs?.chatEnabled ?? true}
          disabled={!prefs || busy}
          onChange={toggleChat}
        />
        <p className="pw-hint">{s.chatFooter}</p>
        <div className="set-device-row">
          <span className="set-row-text">
            <strong>{s.voiceTranscription}</strong>
            <small>{s.voiceTranscriptionHint}</small>
          </span>
          <em>{s.deviceOnly}</em>
        </div>
      </section>

      {/* ── Assistente AI ────────────────────────────────────────────────── */}
      <section className="set-card">
        <h2>{s.ai}</h2>
        <Switch
          label={s.aiEnabled}
          hint={s.aiEnabledHint}
          checked={prefs?.aiEnabled ?? false}
          disabled={!prefs || busy}
          onChange={toggleAI}
        />

        {plan && (
          <div className="prof-row">
            <span>{t.profile.plan}</span>
            <strong className="prof-plan">{plan.toUpperCase()}</strong>
          </div>
        )}

        {aiUsage && (
          <div className="prof-row">
            <span>{aiUsage.period === "lifetime" ? s.aiUsageLifetime : s.aiUsage}</span>
            <strong>
              {aiUsage.usageToday} {s.aiUsageOf} {aiUsage.dailyLimit} {s.aiMessages}
            </strong>
          </div>
        )}

        {prefs?.aiEnabled && (
          <>
            <h3>{s.healthContext}</h3>
            <div className="set-options">
              {HEALTH_CONTEXT_PREFS.map((option) => (
                <button
                  key={option}
                  className={`set-option${
                    prefs.healthContextSendPreference === option ? " selected" : ""
                  }`}
                  disabled={busy}
                  onClick={() =>
                    commit({ healthContextSendPreference: option }, () =>
                      setHealthContextSendPreference(user.uid, option)
                    )
                  }
                >
                  <strong>{s[option]}</strong>
                  <small>{s[`${option}Detail`]}</small>
                </button>
              ))}
            </div>
            <p className="pw-hint">{s.healthContextFooter}</p>
          </>
        )}

        <div className="set-device-row">
          <span className="set-row-text">
            <strong>{s.aiRecaps}</strong>
            <small>{s.aiRecapsHint}</small>
          </span>
          <em>{s.deviceOnly}</em>
        </div>
      </section>

      {/* ── Notifiche ────────────────────────────────────────────────────── */}
      <section className="set-card">
        <h2>{s.notifications}</h2>
        <p className="pw-hint">{s.notificationsHint}</p>

        {/* Le push sul browser sono una cosa a sé: gli interruttori qui sotto
            dicono *cosa* notificare sull'account, questo dice *se* questo
            browser è tra i posti in cui le notifiche arrivano. */}
        {push && !push.supported && <p className="pw-hint">{s.pushUnsupported}</p>}
        {push && push.supported && !push.configured && <p className="pw-hint">{s.pushNotConfigured}</p>}
        {push && push.supported && push.configured && (
          <>
            <Switch
              label={s.pushOnThisBrowser}
              hint={s.pushHint}
              checked={push.enabled}
              disabled={busy || push.permission === "denied"}
              onChange={async (enabled) => {
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
              }}
            />
            {push.permission === "denied" && <p className="pw-hint">{s.pushDenied}</p>}
          </>
        )}
        {NOTIFICATION_PREFS.map((key) => {
          // Con la chat spenta la riga resta ma non si tocca: riaccenderla
          // manderebbe notifiche per una schermata che non si apre.
          const chatOff = key === "notifyOnNewMessages" && prefs && !prefs.chatEnabled;
          return (
            <Switch
              key={key}
              label={s[key]}
              hint={chatOff ? s.notifyOnNewMessagesOff : undefined}
              checked={prefs ? prefs.notifications[key] && !chatOff : false}
              disabled={!prefs || busy || chatOff}
              onChange={(enabled) => toggleNotification(key, enabled)}
            />
          );
        })}
        <div className="set-device-row">
          <span className="set-row-text">
            <strong>{s.nudges}</strong>
            <small>{s.nudgesHint}</small>
          </span>
          <em>{s.deviceOnly}</em>
        </div>
      </section>

      {/* ── Privacy ──────────────────────────────────────────────────────── */}
      <section className="set-card">
        <h2>{s.privacy}</h2>
        <p className="pw-hint">{s.privacyIntro}</p>
        <Switch
          label={s.errorReports}
          hint={s.errorReportsHint}
          checked={errorReports}
          onChange={(enabled) => {
            localStorage.setItem(ERROR_REPORTS_KEY, enabled ? "1" : "0");
            setErrorReports(enabled);
          }}
        />
        <h3>{s.pwnedTitle}</h3>
        <p className="pw-hint">{s.pwnedBody}</p>
      </section>

      {/* ── Password e AutoFill ──────────────────────────────────────────── */}
      <section className="set-card">
        <h2>{s.passwordsAutofill}</h2>
        <div className="set-device-row">
          <span className="set-row-text">
            <small>{s.passwordsAutofillHint}</small>
          </span>
          <em>{s.deviceOnly}</em>
        </div>
      </section>

      {/* ── Utilizzo spazio ──────────────────────────────────────────────── */}
      {storage && (
        <section className="set-card">
          <h2>{s.storage}</h2>
          <div className="prof-row">
            <span>{s.storageUsed}</span>
            <strong>
              {formatBytes(storage.usedBytes)} {s.storageOf} {formatBytes(storage.quotaBytes)}
            </strong>
          </div>
          <div className="prof-bar">
            <span style={{ width: `${Math.round(usedRatio * 100)}%` }} />
          </div>
          {Object.entries(storage.sections || {})
            .filter(([, bytes]) => bytes > 0)
            .sort((a, b) => b[1] - a[1])
            .map(([key, bytes]) => (
              <div className="prof-row" key={key}>
                <span>{s.sections[key] || key}</span>
                <strong>{formatBytes(bytes)}</strong>
              </div>
            ))}
          <p className="pw-hint">{s.storageHint}</p>
        </section>
      )}

      {/* ── Supporto e collegamenti ──────────────────────────────────────── */}
      <section className="set-card">
        <h2>{s.support}</h2>
        <p className="pw-hint">{s.supportHint}</p>
        <a className="set-link" href={`mailto:${SUPPORT_MAIL}`}>
          ✉️ {SUPPORT_MAIL}
        </a>
        <a className="set-link" href={GUIDE_URL} target="_blank" rel="noreferrer">
          📖 {s.guide} ↗
        </a>
        <a className="set-link" href={SITE_URL} target="_blank" rel="noreferrer">
          🌐 {s.website} ↗
        </a>
      </section>

      <p className="set-version">
        {s.version} {__BUILD_DATE__}
      </p>
    </div>
  );
}
