import { useEffect, useRef, useState } from "react";
import { useFamily } from "../FamilyContext";
import { useAuth } from "../AuthContext";
import { useTranslation } from "../i18n/LocaleContext";
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
import "./Profilo.css";

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

export default function Profilo() {
  const { currentFamilyId } = useFamily();
  const { user, logout } = useAuth();
  const { t, locale } = useTranslation();
  const p = t.profile;
  const fileInput = useRef(null);

  const [form, setForm] = useState({ firstName: "", lastName: "", familyAddress: "" });
  const [saved, setSaved] = useState(null);
  const [avatarURL, setAvatarURL] = useState("");
  const [plan, setPlan] = useState(null);
  const [storage, setStorage] = useState(null);
  const [busy, setBusy] = useState(null);
  const [error, setError] = useState(null);
  const [notice, setNotice] = useState(null);
  const [deleting, setDeleting] = useState(false);
  const [deleteConfirmText, setDeleteConfirmText] = useState("");

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
  }, [user]);

  useEffect(() => {
    if (!user) return;
    loadPlan({ familyId: currentFamilyId, uid: user.uid }).then(setPlan).catch(() => setPlan(null));
  }, [currentFamilyId, user]);

  useEffect(() => {
    if (!currentFamilyId) return;
    // Lo spazio arriva da una function: se non risponde, la card mostra il
    // piano lo stesso invece di restare vuota.
    fetchStorageUsage(currentFamilyId).then(setStorage).catch(() => setStorage(null));
  }, [currentFamilyId]);

  const isDirty =
    saved &&
    (form.firstName !== saved.firstName ||
      form.lastName !== saved.lastName ||
      form.familyAddress !== saved.familyAddress);

  const displayName = `${form.firstName} ${form.lastName}`.trim() || PLACEHOLDER_NAME;
  const initials =
    `${form.firstName[0] ?? ""}${form.lastName[0] ?? ""}`.toUpperCase() ||
    (user?.email?.[0] ?? "?").toUpperCase();

  const set = (patch) => setForm((f) => ({ ...f, ...patch }));

  const save = async () => {
    setError(null);
    setBusy(p.saving);
    try {
      await saveProfile({
        uid: user.uid,
        familyId: currentFamilyId,
        ...form,
        email: user.email,
      });
      setSaved({ ...form });
      setNotice(p.saved);
    } catch (err) {
      setError(err.message);
    } finally {
      setBusy(null);
    }
  };

  const pickAvatar = async (file) => {
    if (!file) return;
    setError(null);
    setBusy(p.uploadingAvatar);
    try {
      setAvatarURL(await uploadAvatar({ uid: user.uid, familyId: currentFamilyId, file }));
    } catch (err) {
      setError(err.message);
    } finally {
      setBusy(null);
    }
  };

  const dropAvatar = async () => {
    if (!window.confirm(p.removeAvatarConfirm)) return;
    setBusy(p.working);
    try {
      await removeAvatar({ uid: user.uid, familyId: currentFamilyId });
      setAvatarURL("");
    } catch (err) {
      setError(err.message);
    } finally {
      setBusy(null);
    }
  };

  const confirmDelete = async () => {
    setError(null);
    setBusy(p.working);
    try {
      await deleteAccount();
      await logout();
    } catch (err) {
      setError(err.message);
      setBusy(null);
    }
  };

  const lastLogin = user?.metadata?.lastSignInTime
    ? new Date(user.metadata.lastSignInTime).toLocaleString(
        locale === "en" ? "en-US" : "it-IT",
        { day: "2-digit", month: "long", year: "numeric", hour: "2-digit", minute: "2-digit" }
      )
    : null;

  const usedRatio =
    storage?.quotaBytes > 0 ? Math.min(1, storage.usedBytes / storage.quotaBytes) : 0;

  return (
    <div className="prof-page">
      <header className="pw-header">
        <h1>{p.title}</h1>
      </header>

      {error && <p className="error">{error}</p>}
      {busy && <p className="docs-busy">{busy}</p>}
      {notice && (
        <p className="docs-notice">
          {notice}
          <button className="link-btn" onClick={() => setNotice(null)}>✕</button>
        </p>
      )}

      <section className="prof-card prof-header-card">
        <button
          className="prof-avatar"
          onClick={() => fileInput.current?.click()}
          title={p.changePhoto}
        >
          {avatarURL ? <img src={avatarURL} alt="" /> : <span>{initials}</span>}
          <span className="prof-avatar-edit">✎</span>
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
        <div className="prof-header-body">
          <strong>{displayName}</strong>
          <span>{user?.email}</span>
          {avatarURL && (
            <button className="link-btn danger" onClick={dropAvatar}>
              {p.removePhoto}
            </button>
          )}
        </div>
      </section>

      <section className="prof-card">
        <h2>{p.personalData}</h2>
        <label>
          {p.firstName}
          <input
            value={form.firstName}
            onChange={(e) => set({ firstName: e.target.value })}
            autoComplete="given-name"
          />
        </label>
        <label>
          {p.lastName}
          <input
            value={form.lastName}
            onChange={(e) => set({ lastName: e.target.value })}
            autoComplete="family-name"
          />
        </label>
        <label>
          {p.familyAddress}
          <input
            value={form.familyAddress}
            onChange={(e) => set({ familyAddress: e.target.value })}
            placeholder={p.familyAddressPlaceholder}
            autoComplete="street-address"
          />
        </label>
        {/* `pw-form-actions` è la riga azioni dei moduli del progetto: da lì il
            pulsante prende forma, spaziatura e stato disabilitato. `pw-btn-primary`
            da sola dà solo i colori, e fuori da un contenitore riconosciuto
            restava un bottone nudo. */}
        <div className="pw-form-actions">
          <button className="pw-btn-primary" disabled={!isDirty || busy} onClick={save}>
            {p.save}
          </button>
        </div>
      </section>

      <section className="prof-card">
        <h2>{p.account}</h2>
        <div className="prof-row">
          <span>{p.email}</span>
          <strong>{user?.email || "—"}</strong>
        </div>
        {lastLogin && (
          <div className="prof-row">
            <span>{p.lastLogin}</span>
            <strong>{lastLogin}</strong>
          </div>
        )}
      </section>

      <section className="prof-card">
        <h2>{p.subscription}</h2>
        <div className="prof-row">
          <span>{p.plan}</span>
          <strong className="prof-plan">{plan ? plan.toUpperCase() : "—"}</strong>
        </div>
        {storage && (
          <>
            <div className="prof-row">
              <span>{p.storage}</span>
              <strong>
                {formatBytes(storage.usedBytes)} {p.of} {formatBytes(storage.quotaBytes)}
              </strong>
            </div>
            <div className="prof-bar">
              <span style={{ width: `${Math.round(usedRatio * 100)}%` }} />
            </div>
          </>
        )}
        <p className="pw-hint">{p.planHint}</p>
      </section>

      <section className="prof-card">
        <h2>{p.actions}</h2>
        <button className="prof-action" onClick={logout}>
          ⎋ {p.logout}
        </button>

        {!deleting ? (
          <button className="prof-action danger" onClick={() => setDeleting(true)}>
            🗑 {p.deleteAccount}
          </button>
        ) : (
          <div className="prof-delete">
            <p>{p.deleteWarning}</p>
            {/* Non basta un «sei sicuro?»: qui si perde tutto, e il web è più
                facile da lasciare aperto per sbaglio di un'app sul telefono. */}
            <label>
              {p.deleteTypePrompt}
              <input
                value={deleteConfirmText}
                onChange={(e) => setDeleteConfirmText(e.target.value)}
                placeholder={p.deleteKeyword}
              />
            </label>
            <div className="prof-delete-actions">
              <button className="link-btn" onClick={() => { setDeleting(false); setDeleteConfirmText(""); }}>
                {p.cancel}
              </button>
              <button
                className="prof-action danger"
                disabled={deleteConfirmText.trim().toUpperCase() !== p.deleteKeyword || busy}
                onClick={confirmDelete}
              >
                {p.deleteAccount}
              </button>
            </div>
          </div>
        )}
      </section>
    </div>
  );
}
