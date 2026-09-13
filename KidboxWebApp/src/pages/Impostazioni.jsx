/**
 * Impostazioni. Rispecchia `SettingsView` di iOS e le sue schermate figlie,
 * più il Profilo, in una pagina sola: un'intestazione con avatar e nome, poi
 * gruppi di righe con un'etichetta sopra — di che account si tratta, il piano,
 * la famiglia, i messaggi, l'AI, le notifiche, la privacy, il supporto.
 *
 * Le preferenze dell'account (notifiche, chat, AI) vanno su `users/{uid}` e
 * valgono per tutti i dispositivi; tema e lingua restano di questo browser,
 * come su iOS restano del telefono. Ciò che il web non può davvero comandare
 * — trascrizione vocale, consigli, AutoFill, recap generati dall'app — è
 * mostrato come impostazione del dispositivo invece di essere finto.
 */
import { useEffect, useRef, useState } from "react";
import { Link } from "react-router-dom";
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
import {
  deleteAccount,
  fetchStorageUsage,
  loadPlan,
  loadProfile,
  PLACEHOLDER_NAME,
  removeAvatar,
  saveProfile,
  uploadAvatar,
} from "../services/profile";
import { PushNotConfiguredError, disablePush, enablePush, pushStatus } from "../services/push";
import { fetchUsage } from "../services/aiChat";
import { useFamilyMembers } from "../hooks/useFamilyMembers";
import "./Impostazioni.css";

const GUIDE_URL = "https://kidboxapp.com/guide.html";
const SITE_URL = "https://kidboxapp.com";
const SUPPORT_MAIL = "supporto@kidboxapp.com";
const AI_CONSENT_KEY = "kidbox:aiConsent";
const ERROR_REPORTS_KEY = "kidbox:errorReports";

const PROVIDER_NAMES = {
  "google.com": "Google",
  "apple.com": "Apple",
  "facebook.com": "Facebook",
  password: "Email",
};

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

/* ── Mattoni della pagina ────────────────────────────────────────────────── */

/** Etichetta di gruppo + card che raccoglie le righe. */
function Group({ label, children, tone }) {
  return (
    <section className="set-group">
      <h2 className={`set-group-label${tone ? ` ${tone}` : ""}`}>{label}</h2>
      <div className="set-card set-list">{children}</div>
    </section>
  );
}

/**
 * Una riga: icona in un riquadro tinto, titolo con eventuale sottotitolo, e a
 * destra un valore, un interruttore, un selettore o una freccia. `to` la rende
 * un link, `onClick` un pulsante, altrimenti è statica.
 */
function Row({ icon, tint = "orange", title, hint, right, chevron, to, href, onClick, danger, disabled, children }) {
  const body = (
    <>
      <span className={`set-icon ${tint}`}>{icon}</span>
      <span className="set-row-text">
        <strong>{title}</strong>
        {hint && <small>{hint}</small>}
      </span>
      {right !== undefined && <span className="set-row-right">{right}</span>}
      {chevron && <span className="set-chevron">›</span>}
    </>
  );
  const cls = `set-row${danger ? " danger" : ""}${disabled ? " disabled" : ""}`;
  if (to) return <Link className={cls} to={to}>{body}</Link>;
  if (href) return <a className={cls} href={href} target={href.startsWith("http") ? "_blank" : undefined} rel="noreferrer">{body}</a>;
  if (onClick) return <button className={cls} onClick={onClick} disabled={disabled}>{body}</button>;
  return (
    <div className={cls}>
      {body}
      {children}
    </div>
  );
}

function Switch({ checked, disabled, onChange }) {
  return (
    <input
      type="checkbox"
      className="set-switch"
      checked={checked}
      disabled={disabled}
      onChange={(e) => onChange(e.target.checked)}
    />
  );
}

/** Interruttore con la sua riga: l'intera riga è cliccabile. */
function SwitchRow({ icon, tint, title, hint, checked, disabled, onChange }) {
  return (
    <label className={`set-row${disabled ? " disabled" : ""}`}>
      <span className={`set-icon ${tint || "orange"}`}>{icon}</span>
      <span className="set-row-text">
        <strong>{title}</strong>
        {hint && <small>{hint}</small>}
      </span>
      <span className="set-row-right">
        <Switch checked={checked} disabled={disabled} onChange={onChange} />
      </span>
    </label>
  );
}

/** Selettore a segmenti (tema, lingua). */
function Segmented({ options, value, onChange }) {
  return (
    <span className="set-seg">
      {options.map((opt) => (
        <button
          key={opt.value}
          className={value === opt.value ? "on" : ""}
          onClick={() => onChange(opt.value)}
          title={opt.title}
        >
          {opt.label}
        </button>
      ))}
    </span>
  );
}

/** Riga «si imposta dal telefono»: non è un comando spento, è un'informazione. */
function DeviceRow({ icon, tint, title, hint, label }) {
  return (
    <Row icon={icon} tint={tint} title={title} hint={hint} right={<em className="set-device">{label}</em>} />
  );
}

/* ── Pagina ──────────────────────────────────────────────────────────────── */

export default function Impostazioni() {
  const { user, logout } = useAuth();
  const { currentFamily, currentFamilyId } = useFamily();
  const { t, locale, setLocale } = useTranslation();
  const { theme, setTheme } = useTheme();
  const s = t.settings;
  const p = t.profile;
  const members = useFamilyMembers(currentFamilyId);
  const fileInput = useRef(null);

  // Il consenso alle statistiche si revoca con la stessa facilità con cui si
  // concede: è il senso della promessa fatta nel banner.
  const [analyticsOn, setAnalyticsOn] = useState(() => analyticsConsent() === CONSENT_GRANTED);

  const [prefs, setPrefs] = useState(null);
  const [plan, setPlan] = useState(null);
  const [storage, setStorage] = useState(null);
  const [aiUsage, setAiUsage] = useState(null);
  const [error, setError] = useState(null);
  const [notice, setNotice] = useState(null);
  const [busy, setBusy] = useState(false);
  const [push, setPush] = useState(null);
  const [errorReports, setErrorReports] = useState(
    () => localStorage.getItem(ERROR_REPORTS_KEY) === "1"
  );

  // Profilo
  const [form, setForm] = useState({ firstName: "", lastName: "", familyAddress: "" });
  const [saved, setSaved] = useState(null);
  const [editingName, setEditingName] = useState(false);
  const [avatarURL, setAvatarURL] = useState("");
  const [deleting, setDeleting] = useState(false);
  const [deleteConfirmText, setDeleteConfirmText] = useState("");

  useEffect(() => {
    if (!user) return;
    loadSettings(user.uid).then(setPrefs).catch((err) => setError(err.message));
    loadProfile(user.uid)
      .then((profile) => {
        const next = {
          firstName: profile.firstName,
          lastName: profile.lastName,
          familyAddress: profile.familyAddress,
        };
        setForm(next);
        setSaved(next);
        setAvatarURL(profile.avatarURL);
      })
      .catch((err) => setError(err.message));
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
    // pagina resta usabile e le righe semplicemente non compaiono.
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

  const run = async (action) => {
    setError(null);
    setBusy(true);
    try {
      await action();
    } catch (err) {
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
      setPrefs((cur) => ({
        ...cur,
        chatEnabled: enabled,
        notifications: { ...cur.notifications, notifyOnNewMessages: notify },
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

  const togglePush = (enabled) =>
    run(async () => {
      try {
        if (enabled) {
          const res = await enablePush({ uid: user.uid });
          if (!res.granted) setError(s.pushDenied);
        } else {
          await disablePush({ uid: user.uid });
        }
        setPush(await pushStatus());
      } catch (err) {
        throw err instanceof PushNotConfiguredError ? new Error(s.pushNotConfigured) : err;
      }
    });

  /* ── Profilo ── */

  const isDirty =
    saved &&
    (form.firstName !== saved.firstName ||
      form.lastName !== saved.lastName ||
      form.familyAddress !== saved.familyAddress);
  const displayName = `${form.firstName} ${form.lastName}`.trim() || PLACEHOLDER_NAME;
  const initials =
    `${form.firstName[0] ?? ""}${form.lastName[0] ?? ""}`.toUpperCase() ||
    (user?.email?.[0] ?? "?").toUpperCase();
  const setField = (patch) => setForm((f) => ({ ...f, ...patch }));

  const saveNameForm = () =>
    run(async () => {
      await saveProfile({ uid: user.uid, familyId: currentFamilyId, ...form, email: user.email });
      setSaved({ ...form });
      setEditingName(false);
      setNotice(p.saved);
    });

  const pickAvatar = (file) => {
    if (!file) return;
    run(async () => {
      setAvatarURL(await uploadAvatar({ uid: user.uid, familyId: currentFamilyId, file }));
    });
  };

  const dropAvatar = () => {
    if (!window.confirm(p.removeAvatarConfirm)) return;
    run(async () => {
      await removeAvatar({ uid: user.uid, familyId: currentFamilyId });
      setAvatarURL("");
    });
  };

  const confirmDelete = () =>
    run(async () => {
      await deleteAccount();
      await logout();
    });

  const providerId = user?.providerData?.[0]?.providerId;
  const providerName = PROVIDER_NAMES[providerId] || null;
  const lastLogin = user?.metadata?.lastSignInTime
    ? new Date(user.metadata.lastSignInTime).toLocaleString(
        { it: "it-IT", en: "en-US", fr: "fr-FR", es: "es-ES" }[locale] || "it-IT",
        { day: "2-digit", month: "long", year: "numeric", hour: "2-digit", minute: "2-digit" }
      )
    : null;
  const usedRatio =
    storage?.quotaBytes > 0 ? Math.min(1, storage.usedBytes / storage.quotaBytes) : 0;
  const memberCount = members.filter((m) => !m.isDeleted).length;
  const planName = plan ? plan.charAt(0).toUpperCase() + plan.slice(1) : null;

  return (
    <div className="set-page">
      <header className="pw-header">
        <h1>{s.title}</h1>
      </header>

      {error && <p className="error">{error}</p>}
      {notice && (
        <p className="docs-notice">
          {notice}
          <button className="link-btn" onClick={() => setNotice(null)}>✕</button>
        </p>
      )}

      {/* ── Intestazione profilo ─────────────────────────────────────────── */}
      <section className="set-card set-profile">
        <div className="set-profile-head">
          <button className="prof-avatar" onClick={() => fileInput.current?.click()} title={p.changePhoto}>
            {avatarURL ? <img src={avatarURL} alt="" /> : <span>{initials}</span>}
            <span className="prof-avatar-edit">📷</span>
          </button>
          <input
            ref={fileInput}
            type="file"
            accept="image/*"
            hidden
            onChange={(e) => {
              const file = e.target.files?.[0];
              e.target.value = "";
              pickAvatar(file);
            }}
          />
          <div className="set-profile-body">
            <strong>{displayName}</strong>
            <span>{user?.email}</span>
            {providerName && <small>{s.signedInWith.replace("%@", providerName)}</small>}
          </div>
        </div>

        {editingName ? (
          <form
            className="set-profile-form"
            onSubmit={(e) => {
              e.preventDefault();
              saveNameForm();
            }}
          >
            <label>
              {p.firstName}
              <input value={form.firstName} autoFocus autoComplete="given-name" onChange={(e) => setField({ firstName: e.target.value })} />
            </label>
            <label>
              {p.lastName}
              <input value={form.lastName} autoComplete="family-name" onChange={(e) => setField({ lastName: e.target.value })} />
            </label>
            <label className="wide">
              {p.familyAddress}
              <input
                value={form.familyAddress}
                placeholder={p.familyAddressPlaceholder}
                autoComplete="street-address"
                onChange={(e) => setField({ familyAddress: e.target.value })}
              />
            </label>
            <div className="set-profile-actions">
              <button type="submit" className="prof-action primary" disabled={!isDirty || busy}>
                {p.save}
              </button>
              <button
                type="button"
                className="prof-action"
                onClick={() => {
                  setForm(saved);
                  setEditingName(false);
                }}
              >
                {p.cancel}
              </button>
            </div>
          </form>
        ) : (
          <div className="set-profile-actions">
            <button className="prof-action" onClick={() => setEditingName(true)}>
              ✎ {s.editName}
            </button>
            <button className="prof-action" onClick={() => fileInput.current?.click()}>
              📷 {p.changePhoto}
            </button>
            {avatarURL && (
              <button className="prof-action danger" onClick={dropAvatar}>
                {p.removePhoto}
              </button>
            )}
          </div>
        )}
      </section>

      {/* ── Piano ────────────────────────────────────────────────────────── */}
      <Group label={p.subscription} tone="gold">
        <Row
          icon="🚀"
          tint="gold"
          title={planName ? s.planNamed.replace("%@", planName) : p.plan}
          hint={p.planHint}
        />
        {storage && (
          <div className="set-row set-storage">
            <span className="set-icon blue">💾</span>
            <span className="set-row-text">
              <strong>{s.storage}</strong>
              <small>
                {formatBytes(storage.usedBytes)} {s.storageOf} {formatBytes(storage.quotaBytes)} · {s.storageHint}
              </small>
              <span className="prof-bar">
                <span style={{ width: `${Math.round(usedRatio * 100)}%` }} />
              </span>
              <span className="set-storage-sections">
                {Object.entries(storage.sections || {})
                  .filter(([, bytes]) => bytes > 0)
                  .sort((a, b) => b[1] - a[1])
                  .map(([key, bytes]) => (
                    <small key={key}>
                      {s.sections[key] || key} <b>{formatBytes(bytes)}</b>
                    </small>
                  ))}
              </span>
            </span>
          </div>
        )}
      </Group>

      {/* ── Account ──────────────────────────────────────────────────────── */}
      <Group label={p.account}>
        <Row icon="✉️" tint="orange" title={p.email} right={<span className="set-value">{user?.email || "—"}</span>} />
        <Row
          icon="🔒"
          tint="orange"
          title={s.password}
          right={
            <span className="set-value">
              {providerId === "password" ? s.passwordEmail : s.passwordManagedBy.replace("%@", providerName || "—")}
            </span>
          }
        />
        {lastLogin && <Row icon="🕓" tint="grey" title={p.lastLogin} right={<span className="set-value">{lastLogin}</span>} />}
        <Row
          icon="☀️"
          tint="purple"
          title={s.appearance}
          hint={s.appearanceHint}
          right={
            <Segmented
              value={theme}
              onChange={setTheme}
              options={THEMES.map((o) => ({ value: o.value, label: s[o.value] }))}
            />
          }
        />
        <Row
          icon="🌍"
          tint="green"
          title={s.language}
          hint={s.languageHint}
          right={
            <Segmented
              value={locale}
              onChange={chooseLanguage}
              options={LANGUAGES.map((l) => ({ value: l.code, label: l.flag, title: l.label }))}
            />
          }
        />
      </Group>

      {/* ── Famiglia ─────────────────────────────────────────────────────── */}
      <Group label={t.family.title}>
        <Row
          icon="🏠"
          tint="green"
          title={currentFamily?.name || t.family.noFamily}
          hint={s.familyHint}
          to="/account/family"
          chevron
        />
        <Row
          icon="👥"
          tint="purple"
          title={t.family.members}
          to="/account/family"
          right={<span className="set-value">{memberCount || ""}</span>}
          chevron
        />
      </Group>

      {/* ── Messaggi ─────────────────────────────────────────────────────── */}
      <Group label={s.messages}>
        <SwitchRow
          icon="💬"
          tint="blue"
          title={s.chatEnabled}
          hint={s.chatFooter}
          checked={prefs?.chatEnabled ?? true}
          disabled={!prefs || busy}
          onChange={toggleChat}
        />
        <DeviceRow icon="🎙️" tint="grey" title={s.voiceTranscription} hint={s.voiceTranscriptionHint} label={s.deviceOnly} />
      </Group>

      {/* ── Assistente AI ────────────────────────────────────────────────── */}
      <Group label={s.ai}>
        <SwitchRow
          icon="✨"
          tint="purple"
          title={s.aiEnabled}
          hint={s.aiEnabledHint}
          checked={prefs?.aiEnabled ?? false}
          disabled={!prefs || busy}
          onChange={toggleAI}
        />
        {aiUsage && (
          <Row
            icon="📊"
            tint="blue"
            title={aiUsage.period === "lifetime" ? s.aiUsageLifetime : s.aiUsage}
            right={
              <span className="set-value">
                {aiUsage.usageToday} {s.aiUsageOf} {aiUsage.dailyLimit} {s.aiMessages}
              </span>
            }
          />
        )}
        {prefs?.aiEnabled && (
          <div className="set-row set-stack">
            <span className="set-icon green">🩺</span>
            <span className="set-row-text">
              <strong>{s.healthContext}</strong>
              <small>{s.healthContextFooter}</small>
              <span className="set-options">
                {HEALTH_CONTEXT_PREFS.map((option) => (
                  <button
                    key={option}
                    className={`set-option${prefs.healthContextSendPreference === option ? " selected" : ""}`}
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
              </span>
            </span>
          </div>
        )}
        <DeviceRow icon="📝" tint="grey" title={s.aiRecaps} hint={s.aiRecapsHint} label={s.deviceOnly} />
      </Group>

      {/* ── Notifiche ────────────────────────────────────────────────────── */}
      <Group label={s.notifications}>
        {/* Le push sul browser sono una cosa a sé: gli interruttori sotto
            dicono *cosa* notificare sull'account, questo dice *se* questo
            browser è tra i posti in cui le notifiche arrivano. */}
        {push && !push.supported && <Row icon="🔔" tint="grey" title={s.pushOnThisBrowser} hint={s.pushUnsupported} />}
        {push && push.supported && !push.configured && (
          <Row icon="🔔" tint="grey" title={s.pushOnThisBrowser} hint={s.pushNotConfigured} />
        )}
        {push && push.supported && push.configured && (
          <SwitchRow
            icon="🔔"
            tint="orange"
            title={s.pushOnThisBrowser}
            hint={push.permission === "denied" ? s.pushDenied : s.pushHint}
            checked={push.enabled}
            disabled={busy || push.permission === "denied"}
            onChange={togglePush}
          />
        )}
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
        <DeviceRow icon="💡" tint="grey" title={s.nudges} hint={s.nudgesHint} label={s.deviceOnly} />
      </Group>

      {/* ── Privacy ──────────────────────────────────────────────────────── */}
      <Group label={s.privacy}>
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
          tint="orange"
          title={s.errorReports}
          hint={`${s.privacyIntro} ${s.errorReportsHint}`}
          checked={errorReports}
          onChange={(enabled) => {
            localStorage.setItem(ERROR_REPORTS_KEY, enabled ? "1" : "0");
            setErrorReports(enabled);
          }}
        />
        <Row icon="🛡️" tint="green" title={s.pwnedTitle} hint={s.pwnedBody} />
        <DeviceRow icon="🔑" tint="grey" title={s.passwordsAutofill} hint={s.passwordsAutofillHint} label={s.deviceOnly} />
      </Group>

      {/* ── Alexa ────────────────────────────────────────────────────────── */}
      {/* La skill esiste solo in italiano: vedi `isAlexaAvailable`. */}
      {isAlexaAvailable(locale) && (
        <section className="set-group">
          <h2 className="set-group-label">{t.alexa.title}</h2>
          <AlexaCard />
        </section>
      )}

      {/* ── Supporto ─────────────────────────────────────────────────────── */}
      <Group label={s.support}>
        <Row icon="✉️" tint="orange" title={SUPPORT_MAIL} hint={s.supportHint} href={`mailto:${SUPPORT_MAIL}`} chevron />
        <Row icon="📖" tint="blue" title={s.guide} href={GUIDE_URL} chevron />
        <Row icon="🌐" tint="green" title={s.website} href={SITE_URL} chevron />
      </Group>

      {/* ── Sessione ─────────────────────────────────────────────────────── */}
      <Group label={s.session}>
        <Row icon="⎋" tint="grey" title={p.logout} onClick={logout} chevron />
        {!deleting ? (
          <Row icon="🗑" tint="red" title={p.deleteAccount} onClick={() => setDeleting(true)} danger chevron />
        ) : (
          <div className="set-row set-stack">
            <span className="set-icon red">🗑</span>
            <span className="set-row-text">
              <strong className="set-danger-text">{p.deleteAccount}</strong>
              <small>{p.deleteWarning}</small>
              {/* Non basta un «sei sicuro?»: qui si perde tutto, e il web è più
                  facile da lasciare aperto per sbaglio di un'app sul telefono. */}
              <label className="set-delete-label">
                {p.deleteTypePrompt}
                <input
                  value={deleteConfirmText}
                  onChange={(e) => setDeleteConfirmText(e.target.value)}
                  placeholder={p.deleteKeyword}
                />
              </label>
              <span className="set-profile-actions">
                <button
                  className="prof-action danger"
                  disabled={deleteConfirmText.trim().toUpperCase() !== p.deleteKeyword || busy}
                  onClick={confirmDelete}
                >
                  {p.deleteAccount}
                </button>
                <button
                  className="prof-action"
                  onClick={() => {
                    setDeleting(false);
                    setDeleteConfirmText("");
                  }}
                >
                  {p.cancel}
                </button>
              </span>
            </span>
          </div>
        )}
      </Group>

      <p className="set-version">
        {s.version} {__BUILD_DATE__}
      </p>
    </div>
  );
}

const NOTIFICATION_ICONS = {
  notifyOnNewMessages: "💬",
  notifyOnLocationSharing: "📍",
  notifyOnTodoAssigned: "✅",
  notifyOnNewGroceryItem: "🛒",
  notifyOnNewNote: "📝",
  notifyOnNewExpense: "💶",
  notifyOnNewCalendarEvent: "📅",
  notifyOnNewDocument: "📄",
  notifyOnWallet: "👛",
};
