/**
 * Impostazioni: l'indice. Rispecchia `SettingsView` di iOS — intestazione con
 * avatar e nome, poi gruppi di righe; ogni voce si apre nella sua pagina di
 * dettaglio (`ImpostazioniDettaglio`), come la Famiglia si apre nella sua.
 * Qui restano in linea solo le cose da un tocco: tema e lingua.
 */
import { useEffect, useRef, useState } from "react";
import { useAuth } from "../AuthContext";
import { useFamily } from "../FamilyContext";
import { useTranslation } from "../i18n/LocaleContext";
import { isAlexaAvailable } from "../i18n/alexaAvailability";
import { THEMES, useTheme } from "../ThemeContext";
import { LANGUAGES, setNotificationLanguage } from "../services/settings";
import {
  loadPlan,
  loadProfile,
  PLACEHOLDER_NAME,
  removeAvatar,
  saveProfile,
  uploadAvatar,
} from "../services/profile";
import { useFamilyMembers } from "../hooks/useFamilyMembers";
import { Group, PageHeader, Row, Segmented, Value } from "../components/SettingsRows";
import { GUIDE_URL, PROVIDER_NAMES, SITE_URL, SUPPORT_MAIL } from "./settingsConstants";

export default function Impostazioni() {
  const { user } = useAuth();
  const { currentFamily, currentFamilyId } = useFamily();
  const { t, locale, setLocale } = useTranslation();
  const { theme, setTheme } = useTheme();
  const s = t.settings;
  const p = t.profile;
  const members = useFamilyMembers(currentFamilyId);
  const fileInput = useRef(null);

  const [plan, setPlan] = useState(null);
  const [error, setError] = useState(null);
  const [notice, setNotice] = useState(null);
  const [busy, setBusy] = useState(false);

  // Profilo
  const [form, setForm] = useState({ firstName: "", lastName: "", familyAddress: "" });
  const [saved, setSaved] = useState(null);
  const [editingName, setEditingName] = useState(false);
  const [avatarURL, setAvatarURL] = useState("");

  useEffect(() => {
    if (!user) return;
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
    loadPlan({ familyId: currentFamilyId, uid: user.uid }).then(setPlan).catch(() => setPlan(null));
  }, [user, currentFamilyId]);

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

  const chooseLanguage = (code) => {
    setLocale(code);
    // Il server traduce le push leggendo `notificationLanguage`: senza
    // l'allineamento resterebbero nella lingua precedente.
    if (user) setNotificationLanguage(user.uid, code).catch(() => {});
  };

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

  const providerId = user?.providerData?.[0]?.providerId;
  const providerName = PROVIDER_NAMES[providerId] || null;
  const memberCount = members.filter((m) => !m.isDeleted).length;
  const planName = plan ? plan.charAt(0).toUpperCase() + plan.slice(1) : null;
  const base = "/account/impostazioni";

  return (
    <div className="set-page">
      <PageHeader title={s.title} />

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
          hint={s.planRowHint}
          to={`${base}/piano`}
          chevron
        />
      </Group>

      {/* ── Account ──────────────────────────────────────────────────────── */}
      <Group label={p.account}>
        <Row icon="✉️" title={p.email} right={<Value>{user?.email || "—"}</Value>} />
        <Row
          icon="🔒"
          title={s.password}
          right={
            <Value>
              {providerId === "password" ? s.passwordEmail : s.passwordManagedBy.replace("%@", providerName || "—")}
            </Value>
          }
        />
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
        <Row icon="⎋" tint="grey" title={s.session} hint={s.sessionHint} to={`${base}/sessione`} chevron />
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
        <Row icon="👥" tint="purple" title={t.family.members} to="/account/family" right={<Value>{memberCount || ""}</Value>} chevron />
      </Group>

      {/* ── Preferenze ───────────────────────────────────────────────────── */}
      <Group label={s.preferences}>
        <Row icon="💬" tint="blue" title={s.messages} hint={s.messagesRowHint} to={`${base}/messaggi`} chevron />
        <Row icon="✨" tint="purple" title={s.ai} hint={s.aiRowHint} to={`${base}/assistente`} chevron />
        <Row icon="🔔" title={s.notifications} hint={s.notificationsRowHint} to={`${base}/notifiche`} chevron />
        <Row icon="🛡️" tint="green" title={s.privacy} hint={s.privacyRowHint} to={`${base}/privacy`} chevron />
        {/* La skill esiste solo in italiano: vedi `isAlexaAvailable`. */}
        {isAlexaAvailable(locale) && (
          <Row icon="🔊" tint="blue" title={t.alexa.title} hint={s.alexaRowHint} to={`${base}/alexa`} chevron />
        )}
      </Group>

      {/* ── Supporto ─────────────────────────────────────────────────────── */}
      <Group label={s.support}>
        <Row icon="✉️" title={SUPPORT_MAIL} hint={s.supportHint} href={`mailto:${SUPPORT_MAIL}`} chevron />
        <Row icon="📖" tint="blue" title={s.guide} href={GUIDE_URL} chevron />
        <Row icon="🌐" tint="green" title={s.website} href={SITE_URL} chevron />
      </Group>

      <p className="set-version">
        {s.version} {__BUILD_DATE__}
      </p>
    </div>
  );
}
